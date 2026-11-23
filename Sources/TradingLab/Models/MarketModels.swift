import Foundation

struct Candle: Identifiable, Hashable {
    let id: Int
    let timestamp: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double

    var isBullish: Bool { close >= open }
    var bodyTop: Double { max(open, close) }
    var bodyBottom: Double { min(open, close) }
    var range: Double { max(high - low, 0.00001) }
    var hlc3: Double { (high + low + close) / 3.0 }
}

enum DataSourceMode: String, CaseIterable, Identifiable {
    case live = "LIVE"
    case sample = "SAMPLE"

    var id: String { rawValue }
}

enum LiveFeedState: Equatable {
    case idle
    case connecting(String)
    case streaming(String)   // e.g. "Binance WS"
    case polling(String)     // e.g. "Yahoo Finance"
    case error(String)
}

enum Instrument: String, CaseIterable, Identifiable, Codable {
    case paxg = "PAXG/USDT"
    case xauusd = "XAU/USD"
    case eurusd = "EUR/USD"
    case btcusd = "BTC/USD"
    case ethusd = "ETH/USD"
    case us30 = "US30"
    case nas100 = "NAS100"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paxg: return "Gold 24/7 (PAXG)"
        case .xauusd: return "Gold Futures / Spot"
        case .eurusd: return "Euro / US Dollar"
        case .btcusd: return "Bitcoin"
        case .ethusd: return "Ethereum"
        case .us30: return "Dow Jones 30"
        case .nas100: return "Nasdaq 100"
        }
    }

    /// Binance symbol when supported via free real-time WebSocket + Order Flow tape
    var binanceSymbol: String? {
        switch self {
        case .paxg: return "PAXGUSDT"
        case .btcusd: return "BTCUSDT"
        case .ethusd: return "ETHUSDT"
        default: return nil
        }
    }

    /// Yahoo Finance ticker for FX / Gold Futures / Indices
    var yahooSymbol: String {
        switch self {
        case .paxg: return "PAXG-USD"
        case .xauusd: return "GC=F"
        case .eurusd: return "EURUSD=X"
        case .btcusd: return "BTC-USD"
        case .ethusd: return "ETH-USD"
        case .us30: return "YM=F"
        case .nas100: return "NQ=F"
        }
    }

    var basePrice: Double {
        switch self {
        case .paxg: return 2685.00
        case .xauusd: return 2684.50
        case .eurusd: return 1.08420
        case .btcusd: return 91450.0
        case .ethusd: return 3120.0
        case .us30: return 43280.0
        case .nas100: return 20890.0
        }
    }

    var volatility: Double {
        switch self {
        case .paxg: return 4.2
        case .xauusd: return 4.2
        case .eurusd: return 0.00085
        case .btcusd: return 260.0
        case .ethusd: return 14.0
        case .us30: return 55.0
        case .nas100: return 38.0
        }
    }

    var decimals: Int {
        switch self {
        case .paxg, .xauusd, .ethusd: return 2
        case .eurusd: return 5
        case .btcusd, .us30, .nas100: return 1
        }
    }

    var pipSize: Double {
        switch self {
        case .paxg, .xauusd: return 0.1
        case .eurusd: return 0.0001
        case .btcusd, .ethusd, .us30, .nas100: return 1.0
        }
    }

    /// Approximate dollar value per pip for 1.00 standard lot (used in Risk % lot calculator & paper PnL)
    var dollarPerPipPerLot: Double {
        switch self {
        case .paxg, .xauusd: return 10.0
        case .eurusd: return 10.0
        case .btcusd, .ethusd: return 1.0
        case .us30, .nas100: return 1.0
        }
    }

    var spread: Double {
        switch self {
        case .paxg, .xauusd: return 0.25
        case .eurusd: return 0.00008
        case .btcusd: return 12.0
        case .ethusd: return 0.8
        case .us30: return 2.5
        case .nas100: return 1.8
        }
    }

    func formatPrice(_ price: Double) -> String {
        String(format: "%.\(decimals)f", price)
    }

    var is24x7: Bool {
        self == .paxg || self == .btcusd || self == .ethusd
    }

    func marketStatus(at date: Date = Date()) -> MarketStatus {
        if is24x7 {
            let lbl = (self == .paxg) ? "24/7 Gold" : "24/7 Crypto"
            return MarketStatus(isOpen: true, sessionLabel: lbl, detailText: "Live 24/7")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = comps.weekday ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let totalMin = hour * 60 + minute
        let sundayOpenMin = (self == .xauusd) ? (18 * 60) : (17 * 60)

        let closedWeekend: Bool = {
            if weekday == 7 { return true }
            if weekday == 6 && totalMin >= 17 * 60 { return true }
            if weekday == 1 && totalMin < sundayOpenMin { return true }
            return false
        }()

        let dailyRolloverClosed = (self == .xauusd) && weekday >= 2 && weekday <= 5 && hour == 17

        if closedWeekend || dailyRolloverClosed {
            let nextOpen = nextOpenDate(from: date, calendar: cal, sundayOpenHour: self == .xauusd ? 18 : 17)
            let secs = max(0, Int(nextOpen.timeIntervalSince(date)))
            let hrs = secs / 3600
            let mins = (secs % 3600) / 60
            let countdown = hrs > 0 ? "Opens in \(hrs)h \(mins)m" : "Opens in \(mins)m"
            return MarketStatus(
                isOpen: false,
                sessionLabel: closedWeekend ? "Weekend Closed" : "Daily Rollover",
                detailText: countdown
            )
        }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = .gmt
        let utcHour = utcCal.component(.hour, from: date)
        let session: String
        if utcHour >= 12 && utcHour < 16 {
            session = "London / NY"
        } else if utcHour >= 7 && utcHour < 16 {
            session = "London"
        } else if utcHour >= 12 && utcHour < 21 {
            session = "New York"
        } else if utcHour >= 0 && utcHour < 9 {
            session = "Asia / Tokyo"
        } else {
            session = "Sydney"
        }
        return MarketStatus(isOpen: true, sessionLabel: session, detailText: "Market Open")
    }

    func lastTradingTimestamp(at date: Date = Date()) -> Date {
        if is24x7 || marketStatus(at: date).isOpen {
            return date
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let weekday = cal.component(.weekday, from: date)
        var daysBack = 0
        if weekday == 7 { daysBack = 1 }
        else if weekday == 1 { daysBack = 2 }
        else if weekday == 6 { daysBack = 0 }
        let targetDay = cal.date(byAdding: .day, value: -daysBack, to: date) ?? date
        var dc = cal.dateComponents([.year, .month, .day], from: targetDay)
        dc.hour = 17
        dc.minute = 0
        dc.second = 0
        return cal.date(from: dc) ?? date
    }

    private func nextOpenDate(from date: Date, calendar cal: Calendar, sundayOpenHour: Int) -> Date {
        let weekday = cal.component(.weekday, from: date)
        if weekday >= 2 && weekday <= 5 {
            var dc = cal.dateComponents([.year, .month, .day], from: date)
            dc.hour = 18
            dc.minute = 0
            dc.second = 0
            return cal.date(from: dc) ?? date
        }
        let daysUntilSunday: Int
        switch weekday {
        case 6: daysUntilSunday = 2
        case 7: daysUntilSunday = 1
        default: daysUntilSunday = 0
        }
        let sunday = cal.date(byAdding: .day, value: daysUntilSunday, to: date) ?? date
        var dc = cal.dateComponents([.year, .month, .day], from: sunday)
        dc.hour = sundayOpenHour
        dc.minute = 0
        dc.second = 0
        return cal.date(from: dc) ?? date
    }
}

struct MarketStatus: Equatable {
    let isOpen: Bool
    let sessionLabel: String
    let detailText: String
}

enum Timeframe: String, CaseIterable, Identifiable, Codable {
    case m1 = "M1"
    case m5 = "M5"
    case m15 = "M15"
    case m30 = "M30"
    case h1 = "H1"
    case h4 = "H4"
    case d1 = "D1"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .m30: return 1800
        case .h1: return 3600
        case .h4: return 14400
        case .d1: return 86400
        }
    }

    var binanceInterval: String {
        switch self {
        case .m1: return "1m"
        case .m5: return "5m"
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1: return "1h"
        case .h4: return "4h"
        case .d1: return "1d"
        }
    }

    var yahooParams: (interval: String, range: String) {
        switch self {
        case .m1: return ("1m", "1d")
        case .m5: return ("5m", "5d")
        case .m15: return ("15m", "5d")
        case .m30: return ("30m", "1mo")
        case .h1: return ("60m", "1mo")
        case .h4: return ("60m", "3mo")
        case .d1: return ("1d", "1y")
        }
    }

    var volatilityScale: Double {
        switch self {
        case .m1: return 0.45
        case .m5: return 1.0
        case .m15: return 1.6
        case .m30: return 2.2
        case .h1: return 3.1
        case .h4: return 5.4
        case .d1: return 10.5
        }
    }
}

struct OrderFlowTrade: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let price: Double
    let quantity: Double
    let usdValue: Double
    let isBuyerAggressor: Bool
}

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), 1e-9)
        let u2 = nextUnit()
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}

enum SampleMarketEngine {
    static func generateCandles(
        instrument: Instrument,
        timeframe: Timeframe,
        count: Int = 260
    ) -> [Candle] {
        var hash: UInt64 = 1469598103934665603
        for b in (instrument.rawValue + ":" + timeframe.rawValue).utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        var rng = SeededRNG(seed: hash)

        let anchorDate = instrument.lastTradingTimestamp(at: Date())
        let alignedNow = floor(anchorDate.timeIntervalSince1970 / timeframe.seconds) * timeframe.seconds
        let startEpoch = alignedNow - Double(count - 1) * timeframe.seconds

        let vol = instrument.volatility * timeframe.volatilityScale
        var price = instrument.basePrice * (0.985 + 0.03 * rng.nextUnit())
        var regimeDrift = 0.0
        var regimeCountdown = 0
        var candles: [Candle] = []
        candles.reserveCapacity(count)

        for i in 0..<count {
            if regimeCountdown <= 0 {
                let r = rng.nextUnit()
                if r < 0.34 {
                    regimeDrift = vol * (0.14 + 0.22 * rng.nextUnit())
                } else if r < 0.68 {
                    regimeDrift = -vol * (0.14 + 0.22 * rng.nextUnit())
                } else {
                    regimeDrift = 0.0
                }
                regimeCountdown = 16 + Int(rng.nextUnit() * 28)
            }
            regimeCountdown -= 1

            let open = price
            let impulse = (rng.nextUnit() < 0.08) ? 2.4 : 1.0
            let delta = regimeDrift + rng.nextGaussian() * vol * 0.72 * impulse
            let close = max(open + delta, instrument.pipSize * 10)

            let upperWick = abs(rng.nextGaussian()) * vol * 0.42 * impulse
            let lowerWick = abs(rng.nextGaussian()) * vol * 0.42 * impulse
            let high = max(open, close) + upperWick
            let low = max(min(open, close) - lowerWick, instrument.pipSize * 5)

            let bodySize = abs(close - open)
            let baseVol = 450.0 + rng.nextUnit() * 1400.0
            let volume = baseVol * (1.0 + (bodySize / max(vol, 1e-6)) * 1.45)

            let ts = Date(timeIntervalSince1970: startEpoch + Double(i) * timeframe.seconds)
            candles.append(Candle(
                id: i,
                timestamp: ts,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
            price = close
        }

        return candles
    }
}

struct SamplePosition: Identifiable, Hashable, Codable {
    let id: UUID
    let instrument: Instrument
    let isBuy: Bool
    let lots: Double
    let entryPrice: Double
    var stopLoss: Double?
    var takeProfit: Double?
    let openedAt: Date

    func floatingPnL(currentPrice: Double) -> Double {
        let diff = isBuy ? (currentPrice - entryPrice) : (entryPrice - currentPrice)
        let pipCount = diff / instrument.pipSize
        return pipCount * lots * instrument.dollarPerPipPerLot
    }
}

struct JournalEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var instrument: String
    var timeframe: String
    var isBuy: Bool
    var entryPrice: Double
    var exitPrice: Double
    var lots: Double
    var pnlUSD: Double
    var rMultiple: Double
    var setupTag: String
    var disciplineTag: String
    var notes: String
    var isLiveAccount: Bool = false

    static let setupTags = [
        "OB Retest", "CHoCH Reversal", "FVG Fill", "WaveTrend Cross", "Liquidity Sweep", "Session Breakout", "Manual Scalp"
    ]

    static let disciplineTags = [
        "Followed Plan", "Calm & Patient", "Early Exit", "Moved SL", "FOMO Entry", "Overtraded"
    ]
}
