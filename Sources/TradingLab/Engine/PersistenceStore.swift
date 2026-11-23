import Foundation

struct StoredDrawing: Codable {
    var id: UUID
    var toolRaw: String
    var startIndex: Double
    var startPrice: Double
    var endIndex: Double
    var endPrice: Double
    var colorPresetId: String
    var label: String
    var riskReward: Double
}

struct WorkspacePrefs: Codable {
    var isDarkTheme: Bool = false
    var activeStudies: [ActiveStudy] = [
        ActiveStudy(kind: .concept, isVisible: true),
        ActiveStudy(kind: .orderFlow, isVisible: true),
        ActiveStudy(kind: .momentumOscillator, isVisible: true)
    ]
    var indicatorConfig: IndicatorConfig = IndicatorConfig()
    var showStrategyOverlay: Bool = false

    // Chart & Session Workspace State
    var dataModeRaw: String = DataSourceMode.live.rawValue
    var instrumentRaw: String = Instrument.paxg.rawValue
    var timeframeRaw: String = Timeframe.m5.rawValue
    var visibleCandleCount: Double = 95.0
    var oscillatorHeight: Double = 155.0
    var tradeDrawerWidth: Double = 304.0
    var showTradeDrawer: Bool = false
    var magnetEnabled: Bool = false

    // Risk Calculator & Paper Account State
    var autoSizeByRisk: Bool = true
    var riskPercentPerTrade: Double = 1.0
    var orderLots: Double = 0.10
    var orderStopPips: Double = 40.0
    var orderTakeProfitPips: Double = 80.0
    var sampleBalance: Double = 10_000.0
    var samplePositions: [SamplePosition] = []

    init() {}

    init(
        isDarkTheme: Bool,
        activeStudies: [ActiveStudy],
        indicatorConfig: IndicatorConfig,
        showStrategyOverlay: Bool,
        dataModeRaw: String,
        instrumentRaw: String,
        timeframeRaw: String,
        visibleCandleCount: Double,
        oscillatorHeight: Double,
        tradeDrawerWidth: Double,
        showTradeDrawer: Bool,
        magnetEnabled: Bool,
        autoSizeByRisk: Bool,
        riskPercentPerTrade: Double,
        orderLots: Double,
        orderStopPips: Double,
        orderTakeProfitPips: Double,
        sampleBalance: Double,
        samplePositions: [SamplePosition]
    ) {
        self.isDarkTheme = isDarkTheme
        self.activeStudies = activeStudies
        self.indicatorConfig = indicatorConfig
        self.showStrategyOverlay = showStrategyOverlay
        self.dataModeRaw = dataModeRaw
        self.instrumentRaw = instrumentRaw
        self.timeframeRaw = timeframeRaw
        self.visibleCandleCount = visibleCandleCount
        self.oscillatorHeight = oscillatorHeight
        self.tradeDrawerWidth = tradeDrawerWidth
        self.showTradeDrawer = showTradeDrawer
        self.magnetEnabled = magnetEnabled
        self.autoSizeByRisk = autoSizeByRisk
        self.riskPercentPerTrade = riskPercentPerTrade
        self.orderLots = orderLots
        self.orderStopPips = orderStopPips
        self.orderTakeProfitPips = orderTakeProfitPips
        self.sampleBalance = sampleBalance
        self.samplePositions = samplePositions
    }

    /// Backwards-compatible decoding so new settings never wipe your saved preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkspacePrefs()
        isDarkTheme = try c.decodeIfPresent(Bool.self, forKey: .isDarkTheme) ?? d.isDarkTheme
        activeStudies = try c.decodeIfPresent([ActiveStudy].self, forKey: .activeStudies) ?? d.activeStudies
        indicatorConfig = try c.decodeIfPresent(IndicatorConfig.self, forKey: .indicatorConfig) ?? d.indicatorConfig
        showStrategyOverlay = try c.decodeIfPresent(Bool.self, forKey: .showStrategyOverlay) ?? d.showStrategyOverlay
        dataModeRaw = try c.decodeIfPresent(String.self, forKey: .dataModeRaw) ?? d.dataModeRaw
        instrumentRaw = try c.decodeIfPresent(String.self, forKey: .instrumentRaw) ?? d.instrumentRaw
        timeframeRaw = try c.decodeIfPresent(String.self, forKey: .timeframeRaw) ?? d.timeframeRaw
        visibleCandleCount = try c.decodeIfPresent(Double.self, forKey: .visibleCandleCount) ?? d.visibleCandleCount
        oscillatorHeight = try c.decodeIfPresent(Double.self, forKey: .oscillatorHeight) ?? d.oscillatorHeight
        tradeDrawerWidth = try c.decodeIfPresent(Double.self, forKey: .tradeDrawerWidth) ?? d.tradeDrawerWidth
        showTradeDrawer = try c.decodeIfPresent(Bool.self, forKey: .showTradeDrawer) ?? d.showTradeDrawer
        magnetEnabled = try c.decodeIfPresent(Bool.self, forKey: .magnetEnabled) ?? d.magnetEnabled
        autoSizeByRisk = try c.decodeIfPresent(Bool.self, forKey: .autoSizeByRisk) ?? d.autoSizeByRisk
        riskPercentPerTrade = try c.decodeIfPresent(Double.self, forKey: .riskPercentPerTrade) ?? d.riskPercentPerTrade
        orderLots = try c.decodeIfPresent(Double.self, forKey: .orderLots) ?? d.orderLots
        orderStopPips = try c.decodeIfPresent(Double.self, forKey: .orderStopPips) ?? d.orderStopPips
        orderTakeProfitPips = try c.decodeIfPresent(Double.self, forKey: .orderTakeProfitPips) ?? d.orderTakeProfitPips
        sampleBalance = try c.decodeIfPresent(Double.self, forKey: .sampleBalance) ?? d.sampleBalance
        samplePositions = try c.decodeIfPresent([SamplePosition].self, forKey: .samplePositions) ?? d.samplePositions
    }
}

enum PersistenceStore {
    private static var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = appSupport.appendingPathComponent("TradingLab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var journalURL: URL { baseDirectory.appendingPathComponent("journal.json") }
    private static var drawingsURL: URL { baseDirectory.appendingPathComponent("drawings.json") }
    private static var prefsURL: URL { baseDirectory.appendingPathComponent("preferences.json") }
    private static var alertsURL: URL { baseDirectory.appendingPathComponent("alerts.json") }

    static func loadJournal() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: journalURL),
              let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveJournal(_ entries: [JournalEntry]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(entries) {
            try? data.write(to: journalURL, options: .atomic)
        }
    }

    static func loadAlerts() -> [PriceAlert] {
        guard let data = try? Data(contentsOf: alertsURL),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveAlerts(_ alerts: [PriceAlert]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(alerts) {
            try? data.write(to: alertsURL, options: .atomic)
        }
    }

    static func loadPrefs() -> WorkspacePrefs? {
        guard let data = try? Data(contentsOf: prefsURL),
              let decoded = try? JSONDecoder().decode(WorkspacePrefs.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func savePrefs(_ prefs: WorkspacePrefs) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(prefs) {
            try? data.write(to: prefsURL, options: .atomic)
        }
    }

    static func loadDrawings() -> [Instrument: [DrawingObject]] {
        guard let data = try? Data(contentsOf: drawingsURL),
              let rawMap = try? JSONDecoder().decode([String: [StoredDrawing]].self, from: data) else {
            return [:]
        }
        var result: [Instrument: [DrawingObject]] = [:]
        for (key, items) in rawMap {
            guard let inst = Instrument(rawValue: key) else { continue }
            result[inst] = items.compactMap { s in
                guard let tool = DrawingTool(rawValue: s.toolRaw) else { return nil }
                return DrawingObject(
                    id: s.id,
                    tool: tool,
                    start: ChartPoint(index: s.startIndex, price: s.startPrice),
                    end: ChartPoint(index: s.endIndex, price: s.endPrice),
                    colorPresetId: s.colorPresetId,
                    label: s.label,
                    riskReward: s.riskReward
                )
            }
        }
        return result
    }

    static func saveDrawings(_ map: [Instrument: [DrawingObject]]) {
        var rawMap: [String: [StoredDrawing]] = [:]
        for (inst, items) in map {
            rawMap[inst.rawValue] = items.map { d in
                StoredDrawing(
                    id: d.id,
                    toolRaw: d.tool.rawValue,
                    startIndex: d.start.index,
                    startPrice: d.start.price,
                    endIndex: d.end.index,
                    endPrice: d.end.price,
                    colorPresetId: d.colorPresetId,
                    label: d.label,
                    riskReward: d.riskReward
                )
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(rawMap) {
            try? data.write(to: drawingsURL, options: .atomic)
        }
    }
}
