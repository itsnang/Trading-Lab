import XCTest
@testable import TradingLabCore

final class InMemoryPersistenceAdapter: PersistenceAdapter {
    var prefs: WorkspacePrefs?
    var drawings: [Instrument: [DrawingObject]] = [:]
    var journal: [JournalEntry] = []
    var alerts: [PriceAlert] = []

    func loadPrefs() -> WorkspacePrefs? { prefs }
    func savePrefs(_ prefs: WorkspacePrefs) { self.prefs = prefs }
    func loadDrawings() -> [Instrument: [DrawingObject]] { drawings }
    func saveDrawings(_ map: [Instrument: [DrawingObject]]) { self.drawings = map }
    func loadJournal() -> [JournalEntry] { journal }
    func saveJournal(_ entries: [JournalEntry]) { self.journal = entries }
    func loadAlerts() -> [PriceAlert] { alerts }
    func saveAlerts(_ alerts: [PriceAlert]) { self.alerts = alerts }
}

private func makeTestCandles(instrument: Instrument, timeframe: Timeframe, count: Int) -> [Candle] {
    var state: UInt64 = 0x5A17_C0DE_1234_5678
    func nextUnit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }

    let stepSec = timeframe.seconds
    let startEpoch = 1_700_000_000.0
    let vol = instrument.volatility * timeframe.volatilityScale
    var price = instrument.basePrice
    var drift = vol * 0.18
    var candles: [Candle] = []
    candles.reserveCapacity(count)

    for i in 0..<count {
        if i % 24 == 0 {
            drift = (i / 24) % 2 == 0 ? vol * 0.22 : -vol * 0.18
        }
        let open = price
        let delta = drift + (nextUnit() - 0.5) * vol * 1.4
        let close = max(open + delta, instrument.pipSize * 10)
        let high = max(open, close) + nextUnit() * vol * 0.5
        let low = max(min(open, close) - nextUnit() * vol * 0.5, instrument.pipSize * 5)
        candles.append(Candle(
            id: i,
            timestamp: Date(timeIntervalSince1970: startEpoch + Double(i) * stepSec),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 800.0 + nextUnit() * 1200.0
        ))
        price = close
    }
    return candles
}

final class FakeMarketDataAdapter: MarketDataAdapter {
    var historicalBatches: [[Candle]] = []
    var shouldFailHistorical: Bool = false
    var tailCandles: [Candle] = []
    var lastRequestedEndTime: Date?
    var lastRequestedLimit: Int?
    var streamStartCount: Int = 0
    var onKlineHandler: ((Date, Double, Double, Double, Double, Double) -> Void)?
    var onStatusHandler: ((LiveFeedState) -> Void)?

    func fetchHistoricalCandles(
        instrument: Instrument,
        timeframe: Timeframe,
        limit: Int,
        endTime: Date?
    ) async throws -> (candles: [Candle], provider: String) {
        lastRequestedLimit = limit
        lastRequestedEndTime = endTime
        if shouldFailHistorical {
            throw URLError(.notConnectedToInternet)
        }
        let batch = historicalBatches.isEmpty
            ? makeTestCandles(instrument: instrument, timeframe: timeframe, count: min(limit, 120))
            : historicalBatches.removeFirst()
        return (batch, instrument.binanceSymbol != nil ? "Binance" : "Yahoo Finance")
    }

    func fetchLiveTailCandles(instrument: Instrument, timeframe: Timeframe) async throws -> [Candle] {
        return tailCandles
    }

    func startBinanceStream(
        symbol: String,
        interval: String,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void,
        onStatus: @escaping @Sendable (LiveFeedState) -> Void
    ) {
        streamStartCount += 1
        onKlineHandler = onKline
        onStatusHandler = onStatus
        onStatus(.streaming("Binance WS"))
    }

    func disconnectStream() {}
}

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class WorkspaceSeamTests: XCTestCase {

    func testPrimarySeamRestoresAndPersistsWorkspacePrefsWithoutTouchingDisk() {
        let mem = InMemoryPersistenceAdapter()
        var seeded = WorkspacePrefs()
        seeded.isDarkTheme = true
        seeded.instrumentRaw = Instrument.btcusd.rawValue
        seeded.timeframeRaw = Timeframe.m15.rawValue
        seeded.sampleBalance = 12_500.0
        mem.prefs = seeded

        let fakeMarket = FakeMarketDataAdapter()
        let store = WorkspaceStore(
            ephemeralPreview: false,
            marketService: fakeMarket,
            persistence: mem,
            startTimers: false
        )

        XCTAssertTrue(store.isDarkTheme)
        XCTAssertEqual(store.instrument, .btcusd)
        XCTAssertEqual(store.timeframe, .m15)
        XCTAssertEqual(store.sampleBalance, 12_500.0)

        // Mutating a setting persists into the injected in-memory adapter
        store.riskPercentPerTrade = 2.5
        XCTAssertEqual(mem.prefs?.riskPercentPerTrade, 2.5)
    }

    func testBackwardsCompatibleDecodingPreservesPartialPrefsJSON() throws {
        let partialJSON = """
        {
          "isDarkTheme": true,
          "instrumentRaw": "XAU/USD"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WorkspacePrefs.self, from: partialJSON)
        XCTAssertTrue(decoded.isDarkTheme)
        XCTAssertEqual(decoded.instrumentRaw, "XAU/USD")
        XCTAssertEqual(decoded.timeframeRaw, "M5")
        XCTAssertEqual(decoded.sampleBalance, 10_000.0)
    }

    func testSecondarySeamLiveMarketServiceParsesBinanceKlinesAndEndTime() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let service = LiveMarketService(session: session)

        var capturedURL: URL?
        StubURLProtocol.handler = { req in
            capturedURL = req.url
            let payload = """
            [
              [1700000000000, "2650.10", "2655.00", "2648.50", "2653.25", "142.5", 1700000299999]
            ]
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, payload)
        }

        let endDate = Date(timeIntervalSince1970: 1_700_000_300)
        let res = try await service.fetchHistoricalCandles(
            instrument: .paxg,
            timeframe: .m5,
            limit: 500,
            endTime: endDate
        )

        XCTAssertEqual(res.provider, "Binance")
        XCTAssertEqual(res.candles.count, 1)
        XCTAssertEqual(res.candles[0].open, 2650.10, accuracy: 0.001)
        XCTAssertEqual(res.candles[0].close, 2653.25, accuracy: 0.001)
        XCTAssertTrue(capturedURL?.absoluteString.contains("endTime=1700000300000") == true)
        XCTAssertTrue(capturedURL?.absoluteString.contains("limit=500") == true)
    }

    func testSecondarySeamDoesNotFailOverBetweenBinanceHostsOn429RateLimit() async {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let service = LiveMarketService(session: session)

        var callCount = 0
        StubURLProtocol.handler = { req in
            callCount += 1
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "5"])!
            return (resp, Data())
        }

        do {
            _ = try await service.fetchHistoricalCandles(
                instrument: .paxg,
                timeframe: .m5,
                limit: 500,
                endTime: Date(timeIntervalSince1970: 1_700_000_000)
            )
            XCTFail("Expected 429 rate-limit error")
        } catch {
            // Must stop on the first Binance host because data-api.binance.vision and api.binance.com share the same IP weight bucket
            XCTAssertEqual(callCount, 1)
        }
    }

    func testBackfillOlderHistoryRequestsEarliestMinus1MsAndPrependsDeduplicatedCandles() async {
        let mem = InMemoryPersistenceAdapter()
        let fakeMarket = FakeMarketDataAdapter()

        let baseTs: TimeInterval = 1_700_030_000
        let initialBatch = (0..<60).map { i in
            Candle(
                id: i,
                timestamp: Date(timeIntervalSince1970: baseTs + Double(i) * 300),
                open: 2650 + Double(i),
                high: 2652 + Double(i),
                low: 2649 + Double(i),
                close: 2651 + Double(i),
                volume: 100
            )
        }
        // Older batch with 1 overlapping candle at baseTs to verify deduplication
        let olderBatch = (0..<41).map { i in
            Candle(
                id: i,
                timestamp: Date(timeIntervalSince1970: (baseTs - 40 * 300) + Double(i) * 300),
                open: 2600 + Double(i),
                high: 2602 + Double(i),
                low: 2599 + Double(i),
                close: 2601 + Double(i),
                volume: 95
            )
        }
        fakeMarket.historicalBatches = [initialBatch, olderBatch]

        let store = WorkspaceStore(
            ephemeralPreview: false,
            marketService: fakeMarket,
            persistence: mem,
            startTimers: false
        )
        store.reloadMarket()
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(store.allCandles.count, 60)

        await store.backfillOlderHistory()

        // Must request endTime = earliestOpenMs - 1ms (1_700_030_000 - 0.001)
        XCTAssertNotNil(fakeMarket.lastRequestedEndTime)
        XCTAssertEqual(fakeMarket.lastRequestedEndTime!.timeIntervalSince1970, baseTs - 0.001, accuracy: 0.0005)

        // 60 initial + 40 older unique candles = 100 strictly ordered candles
        XCTAssertEqual(store.allCandles.count, 100)
        XCTAssertEqual(store.allCandles.first?.timestamp.timeIntervalSince1970, baseTs - 40 * 300)
        for idx in 1..<store.allCandles.count {
            XCTAssertLessThan(store.allCandles[idx - 1].timestamp, store.allCandles[idx].timestamp)
            XCTAssertEqual(store.allCandles[idx].id, idx)
        }
    }

    func testUnifiedFourStageStrategyEngineEvaluates4StageRulesWithPartialTPBreakevenAndZeroLookahead() {
        let candles = makeTestCandles(instrument: .paxg, timeframe: .m5, count: 260)
        let indicators = IndicatorEngine.computeAll(candles: candles, config: IndicatorConfig())

        var cfg = FourStageStrategyConfig()
        cfg.riskReward = 2.0
        cfg.riskPercent = 1.0
        cfg.nearATR = 0.8
        cfg.partialTakeProfit = true
        cfg.breakevenRR = 1.0
        cfg.trendRules = [RuleCondition(kind: "adx", compare: "gt", value: 12, lookback: 1)]
        cfg.setupRules = [RuleCondition(kind: "blockPressure", compare: "gt", value: 52, lookback: 1)]
        cfg.retestRules = [RuleCondition(kind: "blockTouch", compare: "gte", value: 1, lookback: 1)]
        cfg.entryRules = [
            RuleCondition(kind: "delta", compare: "gt", value: 200, lookback: 1),
            RuleCondition(kind: "rsi", compare: "lt", value: 75, lookback: 1)
        ]

        let reportFull = BacktestEngine.run(
            candles: candles,
            indicators: indicators,
            strategy: cfg,
            startingBalance: 10_000.0
        )
        XCTAssertFalse(reportFull.trades.isEmpty, "Expected unified 4-Stage Strategy Engine to find causal OB + Retest + Delta entries")

        // Verify rule-Response sensitivity: raising required blockPressure to 99.9% must filter out all setups
        var impossibleCfg = cfg
        impossibleCfg.setupRules = [RuleCondition(kind: "blockPressure", compare: "gt", value: 99.9, lookback: 1)]
        let reportImpossible = BacktestEngine.run(
            candles: candles,
            indicators: indicators,
            strategy: impossibleCfg,
            startingBalance: 10_000.0
        )
        XCTAssertTrue(reportImpossible.trades.isEmpty, "Strategy Engine must respect setupRules (blockPressure > 99.9%)")

        // Verify zero lookahead on the first trade entry: mutating all candles AFTER firstTrade.entryIndex must not change entryIndex or entryPrice
        let firstTrade = reportFull.trades[0]
        var mutatedFuture = candles
        for k in (firstTrade.entryIndex + 1)..<mutatedFuture.count {
            mutatedFuture[k].close += 500.0
            mutatedFuture[k].high += 500.0
            mutatedFuture[k].low += 500.0
        }
        let mutatedIndicators = IndicatorEngine.computeAll(candles: mutatedFuture, config: IndicatorConfig())
        let reportMutated = BacktestEngine.run(
            candles: mutatedFuture,
            indicators: mutatedIndicators,
            strategy: cfg,
            startingBalance: 10_000.0
        )
        XCTAssertFalse(reportMutated.trades.isEmpty)
        XCTAssertEqual(reportMutated.trades[0].entryIndex, firstTrade.entryIndex)
        XCTAssertEqual(reportMutated.trades[0].entryPrice, firstTrade.entryPrice, accuracy: 1e-6)
    }

    func testPaperDeskPendingLimitFillsPartialCloseBreakevenAndAutoTakeProfitClose() {
        let mem = InMemoryPersistenceAdapter()
        let fakeMarket = FakeMarketDataAdapter()
        let store = WorkspaceStore(
            ephemeralPreview: false,
            marketService: fakeMarket,
            persistence: mem,
            startTimers: false
        )
        store.instrument = .paxg
        store.autoSizeByRisk = false
        store.orderLots = 1.00
        store.orderStopPips = 100.0        // $10.00 distance on PAXG (pipSize = 0.10)
        store.orderTakeProfitPips = 200.0  // $20.00 distance on PAXG

        // 1. Place a Buy Limit pending order at 2640.00 (SL = 2630.00, TP = 2660.00)
        store.placePendingOrder(kind: .limit, isBuy: true, entryPrice: 2640.00)
        XCTAssertEqual(store.paperPendingOrders.count, 1)
        XCTAssertEqual(store.samplePositions.count, 0)
        XCTAssertEqual(mem.prefs?.paperPendingOrders.count, 1)

        // 2. Price dips to 2639.50 -> triggers Buy Limit fill at 2640.00
        store.evaluatePaperDeskExecution(barLow: 2639.50, barHigh: 2642.00, currentPrice: 2641.00)
        XCTAssertEqual(store.paperPendingOrders.count, 0)
        XCTAssertEqual(store.samplePositions.count, 1)
        let posId = store.samplePositions[0].id
        XCTAssertEqual(store.samplePositions[0].entryPrice, 2640.00, accuracy: 1e-6)
        XCTAssertEqual(store.samplePositions[0].stopLoss ?? 0, 2630.00, accuracy: 1e-6)
        XCTAssertEqual(store.samplePositions[0].takeProfit ?? 0, 2660.00, accuracy: 1e-6)

        // 3. Price reaches 2650.00 (+1R) -> Trader clicks 50% Partial Close & Move to Breakeven
        store.partialClosePaperPosition(id: posId, fraction: 0.5, fillPrice: 2650.00)
        store.movePaperPositionToBreakeven(id: posId)
        XCTAssertEqual(store.samplePositions.count, 1)
        XCTAssertEqual(store.samplePositions[0].lots, 0.50, accuracy: 1e-6)
        XCTAssertEqual(store.samplePositions[0].stopLoss ?? 0, 2640.00, accuracy: 1e-6)
        XCTAssertGreaterThan(store.sampleBalance, 10_000.0)
        let balanceAfterPartial = store.sampleBalance

        // 4. Subsequent candle reaches 2661.00 -> automatically fills remaining 0.50 lots at TP = 2660.00
        store.evaluatePaperDeskExecution(barLow: 2648.00, barHigh: 2661.00, currentPrice: 2660.50)
        XCTAssertEqual(store.samplePositions.count, 0)
        XCTAssertGreaterThan(store.sampleBalance, balanceAfterPartial)
        XCTAssertEqual(store.journalEntries.count, 2)
        XCTAssertTrue(store.journalEntries[0].notes.contains("Auto TP"))
    }

    func testFeedFailureDoesNotFallbackToSyntheticCandles() async {
        let fakeMarket = FakeMarketDataAdapter()
        fakeMarket.shouldFailHistorical = true
        let memory = InMemoryPersistenceAdapter()
        let store = WorkspaceStore(marketService: fakeMarket, persistence: memory, startTimers: false)

        store.reloadMarket()
        try? await Task.sleep(nanoseconds: 100_000_000)

        if case .error = store.liveFeedState {
            // Expected error state
        } else {
            XCTFail("Expected .error liveFeedState when feed fails, got \(store.liveFeedState)")
        }
        XCTAssertTrue(store.allCandles.isEmpty, "Should not inject synthetic sample candles on feed failure")
    }

    func testMergeTailCandlesMergesUnalignedYahooLiveQuotesIntoActiveTimeframeBucket() {
        let memory = InMemoryPersistenceAdapter()
        let store = WorkspaceStore(marketService: FakeMarketDataAdapter(), persistence: memory, startTimers: false)
        store.instrument = .xauusd
        store.timeframe = .m15

        // Seed 09:00 M15 candle (aligned to 900s)
        let t0900 = 1_795_424_400.0 // exact multiple of 900
        store.mergeTailCandles([
            Candle(id: 0, timestamp: Date(timeIntervalSince1970: t0900), open: 3614.1, high: 3614.3, low: 3611.0, close: 3613.3, volume: 1144)
        ])
        XCTAssertEqual(store.allCandles.count, 1)

        // Simulate 3 consecutive 10s Yahoo polls returning unaligned flat live quotes inside the same 09:00 M15 bar
        store.mergeTailCandles([
            Candle(id: 0, timestamp: Date(timeIntervalSince1970: t0900 + 603), open: 3612.4, high: 3612.4, low: 3612.4, close: 3612.4, volume: 0)
        ])
        store.mergeTailCandles([
            Candle(id: 0, timestamp: Date(timeIntervalSince1970: t0900 + 613), open: 3615.0, high: 3615.0, low: 3615.0, close: 3615.0, volume: 0)
        ])
        store.mergeTailCandles([
            Candle(id: 0, timestamp: Date(timeIntervalSince1970: t0900 + 623), open: 3610.2, high: 3610.2, low: 3610.2, close: 3610.2, volume: 0)
        ])

        // Must STILL be 1 candle (no fake flat bars appended), with merged OHLC and preserved volume
        XCTAssertEqual(store.allCandles.count, 1)
        let merged = store.allCandles[0]
        XCTAssertEqual(merged.timestamp.timeIntervalSince1970, t0900, accuracy: 0.1)
        XCTAssertEqual(merged.open, 3614.1, accuracy: 1e-6)
        XCTAssertEqual(merged.high, 3615.0, accuracy: 1e-6)
        XCTAssertEqual(merged.low, 3610.2, accuracy: 1e-6)
        XCTAssertEqual(merged.close, 3610.2, accuracy: 1e-6)
        XCTAssertEqual(merged.volume, 1144, accuracy: 1e-6)

        // Next M15 bucket (09:15) should append cleanly as candle #2
        store.mergeTailCandles([
            Candle(id: 1, timestamp: Date(timeIntervalSince1970: t0900 + 900), open: 3610.5, high: 3612.0, low: 3609.8, close: 3611.6, volume: 320)
        ])
        XCTAssertEqual(store.allCandles.count, 2)

        // Real-time Swissquote spot ticks inside 09:15 update high/low/close in place; 09:30 rolls over cleanly
        store.applyLiveSpotTick(price: 3618.4, timestamp: Date(timeIntervalSince1970: t0900 + 912))
        store.applyLiveSpotTick(price: 3617.9, timestamp: Date(timeIntervalSince1970: t0900 + 913))
        XCTAssertEqual(store.allCandles.count, 2)
        XCTAssertEqual(store.allCandles[1].high, 3618.4, accuracy: 1e-6)
        XCTAssertEqual(store.allCandles[1].close, 3617.9, accuracy: 1e-6)

        store.applyLiveSpotTick(price: 3618.1, timestamp: Date(timeIntervalSince1970: t0900 + 1801))
        XCTAssertEqual(store.allCandles.count, 3)
        XCTAssertEqual(store.allCandles[2].timestamp.timeIntervalSince1970, t0900 + 1800, accuracy: 0.1)
    }
}
