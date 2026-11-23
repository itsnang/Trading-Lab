import Foundation

/// Live market data client using free, zero-API-key public endpoints:
/// - Binance public REST + WebSocket (`data-api.binance.vision` / `data-stream.binance.vision`) for 24/7 Gold (`PAXGUSDT`) & Crypto (`BTCUSDT`, `ETHUSDT`)
/// - Yahoo Finance chart REST (`query1.finance.yahoo.com`) for Gold Futures (`GC=F`), Forex (`EURUSD=X`), and Indices (`YM=F`, `NQ=F`).
final class LiveMarketService: MarketDataAdapter {
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsGeneration: Int = 0

    init(session: URLSession? = nil) {
        if let custom = session {
            self.session = custom
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 20
            cfg.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) TradingLab/1.0"
            ]
            self.session = URLSession(configuration: cfg)
        }
    }

    func disconnectStream() {
        wsGeneration += 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Historical OHLCV Fetch

    func fetchHistoricalCandles(
        instrument: Instrument,
        timeframe: Timeframe,
        limit: Int = 260,
        endTime: Date? = nil
    ) async throws -> (candles: [Candle], provider: String) {
        if let binanceSym = instrument.binanceSymbol {
            do {
                let candles = try await fetchBinanceKlines(symbol: binanceSym, interval: timeframe.binanceInterval, limit: min(1000, max(1, limit)), endTime: endTime)
                return (candles, "Binance")
            } catch {
                // Fallback to Yahoo only for initial load (not Binance backward pagination)
                if endTime != nil { throw error }
                let candles = try await fetchYahooCandles(symbol: instrument.yahooSymbol, timeframe: timeframe)
                return (candles, "Yahoo Finance")
            }
        } else {
            let candles = try await fetchYahooCandles(symbol: instrument.yahooSymbol, timeframe: timeframe)
            return (candles, "Yahoo Finance")
        }
    }

    func fetchLiveTailCandles(
        instrument: Instrument,
        timeframe: Timeframe
    ) async throws -> [Candle] {
        let encoded = instrument.yahooSymbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? instrument.yahooSymbol
        let interval = timeframe.yahooParams.interval
        let tailRange = (timeframe == .d1) ? "5d" : "1d"
        return try await fetchYahooWindow(symbol: encoded, timeframe: timeframe, interval: interval, querySuffix: "interval=\(interval)&range=\(tailRange)&includePrePost=true")
    }

    /// Fetches zero-delay real-time spot bid/ask mid price from Swissquote public BBO feed
    /// for Spot Gold (XAU/USD) and EUR/USD (~0.15s latency, zero API key).
    func fetchLiveSpotQuote(instrument: Instrument) async throws -> (price: Double, timestamp: Date)? {
        guard let path = instrument.swissquotePath,
              let url = URL(string: "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/\(path)") else {
            return nil
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let profiles = first["spreadProfilePrices"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        let chosen = profiles.first(where: { ($0["spreadProfile"] as? String) == "elite" })
            ?? profiles.first(where: { ($0["spreadProfile"] as? String) == "prime" })
            ?? profiles.last
        guard let p = chosen,
              let bid = doubleFromAny(p["bid"] as Any),
              let ask = doubleFromAny(p["ask"] as Any),
              bid > 0, ask > 0 else {
            throw URLError(.cannotParseResponse)
        }
        let mid = (bid + ask) * 0.5
        let tsMs = doubleFromAny(first["ts"] as Any) ?? (Date().timeIntervalSince1970 * 1000.0)
        return (mid, Date(timeIntervalSince1970: tsMs / 1000.0))
    }

    private func fetchBinanceKlines(symbol: String, interval: String, limit: Int, endTime: Date? = nil) async throws -> [Candle] {
        let hosts = ["https://data-api.binance.vision", "https://api.binance.com"]
        var lastError: Error = URLError(.cannotConnectToHost)
        let endParam: String
        if let endTime {
            let ms = Int64(endTime.timeIntervalSince1970 * 1000.0)
            endParam = "&endTime=\(ms)"
        } else {
            endParam = ""
        }

        for host in hosts {
            guard let url = URL(string: "\(host)/api/v3/klines?symbol=\(symbol)&interval=\(interval)&limit=\(limit)\(endParam)") else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 429 || http.statusCode == 418 {
                    // Never fail over to api.binance.com on 429/418 — both hosts share the same IP weight bucket!
                    throw URLError(.resourceUnavailable)
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                    throw URLError(.cannotParseResponse)
                }
                var candles: [Candle] = []
                candles.reserveCapacity(rows.count)
                for (idx, row) in rows.enumerated() {
                    guard row.count >= 6,
                          let openMs = row[0] as? Double ?? (row[0] as? Int).map(Double.init),
                          let open = doubleFromAny(row[1]),
                          let high = doubleFromAny(row[2]),
                          let low = doubleFromAny(row[3]),
                          let close = doubleFromAny(row[4]),
                          let vol = doubleFromAny(row[5]) else { continue }
                    candles.append(Candle(
                        id: idx,
                        timestamp: Date(timeIntervalSince1970: openMs / 1000.0),
                        open: open,
                        high: high,
                        low: low,
                        close: close,
                        volume: vol
                    ))
                }
                if !candles.isEmpty { return candles }
            } catch {
                lastError = error
                if (error as? URLError)?.code == .resourceUnavailable { throw error }
            }
        }
        throw lastError
    }

    private func fetchYahooCandles(symbol: String, timeframe: Timeframe) async throws -> [Candle] {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let nowSec = Int(Date().timeIntervalSince1970)
        // Respect verified Yahoo intraday retention caps and avoid range=max 1d->1mo downgrade:
        // 1m: 7d window (within 30d), 5m/15m/30m: 59d, 60m/h4: 729d, 1d: 10y via period1/period2
        switch timeframe {
        case .m1:
            let p1 = nowSec - 7 * 86400
            return try await fetchYahooWindow(symbol: encoded, timeframe: timeframe, interval: "1m", querySuffix: "interval=1m&period1=\(p1)&period2=\(nowSec)&includePrePost=true")
        case .m5, .m15, .m30:
            let interval = timeframe.yahooParams.interval
            let p1 = nowSec - 59 * 86400
            return try await fetchYahooWindow(symbol: encoded, timeframe: timeframe, interval: interval, querySuffix: "interval=\(interval)&period1=\(p1)&period2=\(nowSec)&includePrePost=true")
        case .h1, .h4:
            let p1 = nowSec - 365 * 86400
            return try await fetchYahooWindow(symbol: encoded, timeframe: timeframe, interval: "60m", querySuffix: "interval=60m&period1=\(p1)&period2=\(nowSec)&includePrePost=true")
        case .d1:
            let p1 = nowSec - 10 * 365 * 86400
            return try await fetchYahooWindow(symbol: encoded, timeframe: timeframe, interval: "1d", querySuffix: "interval=1d&period1=\(p1)&period2=\(nowSec)&includePrePost=true")
        }
    }

    private func fetchYahooWindow(symbol encoded: String, timeframe: Timeframe, interval: String, querySuffix: String) async throws -> [Candle] {
        let hosts = ["https://query1.finance.yahoo.com", "https://query2.finance.yahoo.com"]
        var lastError: Error = URLError(.cannotConnectToHost)

        for host in hosts {
            guard let url = URL(string: "\(host)/v8/finance/chart/\(encoded)?\(querySuffix)") else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chart = root["chart"] as? [String: Any],
                      let results = chart["result"] as? [[String: Any]],
                      let first = results.first,
                      let timestamps = first["timestamp"] as? [Double],
                      let indicators = first["indicators"] as? [String: Any],
                      let quotes = indicators["quote"] as? [[String: Any]],
                      let q = quotes.first else {
                    throw URLError(.cannotParseResponse)
                }

                let opens = q["open"] as? [Any] ?? []
                let highs = q["high"] as? [Any] ?? []
                let lows = q["low"] as? [Any] ?? []
                let closes = q["close"] as? [Any] ?? []
                let vols = q["volume"] as? [Any] ?? []

                var rawCandles: [Candle] = []
                rawCandles.reserveCapacity(timestamps.count)
                for i in 0..<timestamps.count {
                    guard i < opens.count, i < highs.count, i < lows.count, i < closes.count,
                          let o = doubleFromAny(opens[i]),
                          let h = doubleFromAny(highs[i]),
                          let l = doubleFromAny(lows[i]),
                          let c = doubleFromAny(closes[i]),
                          o.isFinite, h.isFinite, l.isFinite, c.isFinite,
                          o > 0, h > 0, l > 0, c > 0 else { continue }
                    let v = (i < vols.count ? doubleFromAny(vols[i]) : nil) ?? 0.0
                    let safeHigh = max(o, h, l, c)
                    let safeLow = min(o, h, l, c)
                    rawCandles.append(Candle(
                        id: rawCandles.count,
                        timestamp: Date(timeIntervalSince1970: timestamps[i]),
                        open: o,
                        high: safeHigh,
                        low: safeLow,
                        close: c,
                        volume: max(v, 0.0)
                    ))
                }

                // Always normalize Yahoo bars to the active timeframe bucket so Yahoo's unaligned
                // trailing live quote tick (e.g. 09:10:13 with O=H=L=C, V=0 inside a 09:00 M15 bar)
                // merges into the active candle instead of creating duplicate flat bars.
                rawCandles = aggregateCandles(rawCandles, bucketSeconds: timeframe.seconds)
                let reindexed = rawCandles.enumerated().map { idx, c in
                    Candle(id: idx, timestamp: c.timestamp, open: c.open, high: c.high, low: c.low, close: c.close, volume: max(c.volume, 1.0))
                }
                if !reindexed.isEmpty { return reindexed }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func aggregateCandles(_ source: [Candle], bucketSeconds: TimeInterval) -> [Candle] {
        var result: [Candle] = []
        var currentBucket: TimeInterval? = nil
        var acc: Candle? = nil

        for c in source {
            let b = floor(c.timestamp.timeIntervalSince1970 / bucketSeconds) * bucketSeconds
            if currentBucket == b, var cur = acc {
                cur.high = max(cur.high, c.high)
                cur.low = min(cur.low, c.low)
                cur.close = c.close
                cur.volume += c.volume
                acc = cur
            } else {
                if let cur = acc { result.append(cur) }
                currentBucket = b
                acc = Candle(
                    id: result.count,
                    timestamp: Date(timeIntervalSince1970: b),
                    open: c.open,
                    high: c.high,
                    low: c.low,
                    close: c.close,
                    volume: c.volume
                )
            }
        }
        if let cur = acc { result.append(cur) }
        return result
    }

    // MARK: - Real-Time Binance WebSocket (Klines + Order Flow aggTrade)

    func startBinanceStream(
        symbol: String,
        interval: String,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void,
        onStatus: @escaping @Sendable (LiveFeedState) -> Void
    ) {
        disconnectStream()
        let gen = wsGeneration
        let lower = symbol.lowercased()
        let urlStr = "wss://data-stream.binance.vision/stream?streams=\(lower)@kline_\(interval)/\(lower)@aggTrade"
        guard let url = URL(string: urlStr) else { return }

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        onStatus(.streaming("Binance WS"))

        receiveLoop(task: task, generation: gen, onKline: onKline, onTrade: onTrade, onStatus: onStatus)
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        generation: Int,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void,
        onStatus: @escaping @Sendable (LiveFeedState) -> Void
    ) {
        task.receive { [weak self] result in
            guard let self, self.wsGeneration == generation else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseBinanceStreamPayload(text, onKline: onKline, onTrade: onTrade)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseBinanceStreamPayload(text, onKline: onKline, onTrade: onTrade)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop(task: task, generation: generation, onKline: onKline, onTrade: onTrade, onStatus: onStatus)

            case .failure(let err):
                onStatus(.error("Stream dropped: \(err.localizedDescription)"))
            }
        }
    }

    private func parseBinanceStreamPayload(
        _ text: String,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void
    ) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if (root["e"] as? String) == "serverShutdown" {
            disconnectStream()
            return
        }

        guard let stream = root["stream"] as? String,
              let payload = root["data"] as? [String: Any] else { return }

        if (payload["e"] as? String) == "serverShutdown" {
            disconnectStream()
            return
        }

        if stream.contains("@kline_"), let k = payload["k"] as? [String: Any] {
            guard let tMs = k["t"] as? Double ?? (k["t"] as? Int).map(Double.init),
                  let o = doubleFromAny(k["o"]),
                  let h = doubleFromAny(k["h"]),
                  let l = doubleFromAny(k["l"]),
                  let c = doubleFromAny(k["c"]),
                  let v = doubleFromAny(k["v"]) else { return }
            onKline(Date(timeIntervalSince1970: tMs / 1000.0), o, h, l, c, v)
        } else if stream.contains("@aggTrade") {
            guard let p = doubleFromAny(payload["p"]),
                  let q = doubleFromAny(payload["q"]) else { return }
            let isMakerSell = (payload["m"] as? Bool) ?? false // m=true -> buyer was maker -> seller aggressed
            let tMs = payload["T"] as? Double ?? (payload["T"] as? Int).map(Double.init) ?? Date().timeIntervalSince1970 * 1000.0
            let trade = OrderFlowTrade(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: tMs / 1000.0),
                price: p,
                quantity: q,
                usdValue: p * q,
                isBuyerAggressor: !isMakerSell
            )
            onTrade(trade)
        }
    }

    private func doubleFromAny(_ val: Any?) -> Double? {
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        if let s = val as? String { return Double(s) }
        return nil
    }
}
