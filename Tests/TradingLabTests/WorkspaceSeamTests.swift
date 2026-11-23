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

final class FakeMarketDataAdapter: MarketDataAdapter {
    var historicalBatches: [[Candle]] = []
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
        let batch = historicalBatches.isEmpty
            ? SampleMarketEngine.generateCandles(instrument: instrument, timeframe: timeframe, count: min(limit, 120))
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
        let candles = SampleMarketEngine.generateCandles(instrument: .paxg, timeframe: .m5, count: 260)
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
}
