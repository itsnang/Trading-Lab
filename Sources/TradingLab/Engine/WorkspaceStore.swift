import Foundation
import SwiftUI
import AppKit
import Combine

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case backtest = "Backtest"
    case journal = "Journal"
    case botStudio = "Bot Studio"
    case account = "Account"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .terminal: return "chart.xyaxis.line"
        case .backtest: return "waveform.badge.magnifyingglass"
        case .journal: return "book.pages"
        case .botStudio: return "cpu"
        case .account: return "briefcase"
        }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var isDarkTheme: Bool = false {
        didSet { saveWorkspacePrefs() }
    }
    @Published var activeSection: WorkspaceSection = .terminal
    @Published var instrument: Instrument = .paxg {
        didSet {
            saveWorkspacePrefs()
            if !isBootstrapping { reloadMarket() }
        }
    }
    @Published var timeframe: Timeframe = .m5 {
        didSet {
            saveWorkspacePrefs()
            if !isBootstrapping { reloadMarket() }
        }
    }

    var theme: AppTheme { AppTheme(isDark: isDarkTheme) }

    // Candle data + live stream state
    @Published private(set) var allCandles: [Candle] = []
    @Published private(set) var liveFeedState: LiveFeedState = .idle
    @Published private(set) var marketStatus: MarketStatus = Instrument.paxg.marketStatus()
    @Published var isReplayMode: Bool = false
    @Published var replayIndex: Int = 180
    @Published var isReplayPlaying: Bool = false
    @Published var replaySpeed: Double = 2.0

    // Live Order Flow Tape
    @Published private(set) var orderFlowTrades: [OrderFlowTrade] = []
    @Published private(set) var buyVolumeWindow: Double = 0
    @Published private(set) var sellVolumeWindow: Double = 0

    // Viewport camera state (TradingView-style X & Y scaling + resizable panes)
    @Published var visibleCandleCount: Double = 95.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var rightOffsetBars: Double = 6.0
    @Published var isAutoPriceScale: Bool = true
    @Published var manualPriceMin: Double = 0.0
    @Published var manualPriceMax: Double = 1.0
    @Published var oscillatorHeight: CGFloat = 155.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var tradeDrawerWidth: CGFloat = 304.0 {
        didSet { saveWorkspacePrefs() }
    }

    // Clean Bundled Indicator Suites (inspired by BTrader study cards)
    @Published var activeStudies: [ActiveStudy] = [
        ActiveStudy(kind: .concept, isVisible: true),
        ActiveStudy(kind: .orderFlow, isVisible: true),
        ActiveStudy(kind: .momentumOscillator, isVisible: true)
    ] {
        didSet { saveWorkspacePrefs() }
    }
    @Published var indicatorConfig = IndicatorConfig() {
        didSet {
            recomputeIndicators()
            saveWorkspacePrefs()
        }
    }
    @Published var computed = ComputedIndicators()
    @Published var showBacktestSignalsOnChart: Bool = false {
        didSet { saveWorkspacePrefs() }
    }
    @Published private(set) var backtestReport = BacktestReport()

    // Clean Modal Sheets & Optional Trade Drawer (uncluttered chart by default!)
    @Published var showIndicatorLibrary: Bool = false
    @Published var showTradeDrawer: Bool = false {
        didSet { saveWorkspacePrefs() }
    }
    @Published var settingsStudyKind: StudyKind? = nil
    @Published var alertStudyKind: StudyKind? = nil

    // Live Price & Study Suite Signal Alerts
    @Published var alerts: [PriceAlert] = []
    @Published var triggeredAlertBanner: PriceAlert? = nil
    @Published var recentSignalAlerts: [SignalAlertEvent] = []
    @Published var triggeredSignalBanner: SignalAlertEvent? = nil
    @Published var signalAlertsEnabled: Bool = true { didSet { saveWorkspacePrefs() } }
    @Published var zoneTouchAlertsEnabled: Bool = true { didSet { saveWorkspacePrefs() } }
    @Published var macOSNotificationsEnabled: Bool = true {
        didSet {
            saveWorkspacePrefs()
            if macOSNotificationsEnabled && !isBootstrapping {
                notifications.requestAuthorizationIfNeeded()
            }
        }
    }
    @Published var soundAlertsEnabled: Bool = true { didSet { saveWorkspacePrefs() } }

    // Drawing tools & persisted per-instrument drawings
    @Published var activeTool: DrawingTool = .cursor
    @Published var activeColorPresetId: String = "cyan"
    @Published var pendingNoteText: String = "Key Level"
    @Published var magnetEnabled: Bool = false {
        didSet { saveWorkspacePrefs() }
    }
    @Published var selectedDrawingId: UUID? = nil
    @Published var drawingsByInstrument: [Instrument: [DrawingObject]] = [:]
    private var undoStackByInstrument: [Instrument: [[DrawingObject]]] = [:]

    // Live candle countdown clock
    @Published var candleCountdownText: String = ""
    private var countdownTimer: Timer?

    // Bot Studio & Strategy configs
    @Published var basketConfig = BasketManagerConfig()
    @Published var adaptiveGridConfig = AdaptiveGridConfig()
    @Published var strategyConfig = FourStageStrategyConfig() {
        didSet { recomputeBacktest() }
    }

    // Risk Calculator & Paper Desk Account
    @Published var sampleBalance: Double = 10_000.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var samplePositions: [SamplePosition] = [] {
        didSet { saveWorkspacePrefs() }
    }
    @Published var paperPendingOrders: [PaperPendingOrder] = [] {
        didSet { saveWorkspacePrefs() }
    }
    @Published var riskPercentPerTrade: Double = 1.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var autoSizeByRisk: Bool = true {
        didSet { saveWorkspacePrefs() }
    }
    @Published var orderLots: Double = 0.10 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var orderStopPips: Double = 40.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var orderTakeProfitPips: Double = 80.0 {
        didSet { saveWorkspacePrefs() }
    }

    // Persistent Trade Journal
    @Published var journalEntries: [JournalEntry] = []

    private let liveService: MarketDataAdapter
    private let persistence: PersistenceAdapter
    private let notifications: NotificationAdapter
    private var firedSignalKeys: Set<String> = []
    private var isAlertBaselineSeeded: Bool = false
    private var loadTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var isBackfillingHistory: Bool = false
    private var spotBasisOffset: Double = 0.0
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var wsRotationTimer: Timer?
    private var pollTimer: Timer?
    private var replayTimer: Timer?
    private var isBootstrapping = true
    private let isEphemeralPreview: Bool

    // MARK: - Study Suite Helpers

    func isStudyAdded(_ kind: StudyKind) -> Bool {
        activeStudies.contains(where: { $0.kind == kind })
    }

    func isStudyVisible(_ kind: StudyKind) -> Bool {
        activeStudies.first(where: { $0.kind == kind })?.isVisible ?? false
    }

    func addStudy(_ kind: StudyKind) {
        if let idx = activeStudies.firstIndex(where: { $0.kind == kind }) {
            activeStudies[idx].isVisible = true
        } else {
            activeStudies.append(ActiveStudy(kind: kind, isVisible: true))
        }
    }

    func removeStudy(_ kind: StudyKind) {
        activeStudies.removeAll { $0.kind == kind }
    }

    func toggleStudyVisibility(_ kind: StudyKind) {
        guard let idx = activeStudies.firstIndex(where: { $0.kind == kind }) else { return }
        activeStudies[idx].isVisible.toggle()
    }

    var visibleSeries: [Candle] {
        if isReplayMode {
            let end = max(20, min(allCandles.count, replayIndex))
            return Array(allCandles.prefix(end))
        }
        return allCandles
    }

    var currentDrawings: [DrawingObject] {
        drawingsByInstrument[instrument] ?? []
    }

    var lastPrice: Double {
        visibleSeries.last?.close ?? instrument.basePrice
    }

    var priceChangePercent: Double {
        guard let first = visibleSeries.first?.open, first > 0 else { return 0 }
        return ((lastPrice - first) / first) * 100.0
    }

    var floatingPnL: Double {
        samplePositions.reduce(0.0) { acc, pos in
            let refPrice = (pos.instrument == instrument) ? lastPrice : pos.instrument.basePrice
            return acc + pos.floatingPnL(currentPrice: refPrice)
        }
    }

    var sampleEquity: Double {
        sampleBalance + floatingPnL
    }

    var calculatedRiskLots: Double {
        guard orderStopPips > 0 else { return max(0.01, orderLots) }
        let riskDollars = max(1.0, sampleEquity * (riskPercentPerTrade / 100.0))
        let dollarsPerLotAtSL = orderStopPips * instrument.dollarPerPipPerLot
        let raw = riskDollars / max(dollarsPerLotAtSL, 0.01)
        return max(0.01, (raw * 100.0).rounded() / 100.0)
    }

    var effectiveOrderLots: Double {
        autoSizeByRisk ? calculatedRiskLots : max(0.01, orderLots)
    }

    var buyPressurePercent: Double {
        let total = buyVolumeWindow + sellVolumeWindow
        guard total > 0 else { return 50.0 }
        return (buyVolumeWindow / total) * 100.0
    }

    var isReceivingTicks: Bool {
        if case .streaming = liveFeedState { return !isReplayMode }
        if case .polling = liveFeedState { return !isReplayMode && marketStatus.isOpen }
        return false
    }

    init(
        ephemeralPreview: Bool = false,
        initialCandles: [Candle]? = nil,
        marketService: MarketDataAdapter = LiveMarketService(),
        persistence: PersistenceAdapter = DiskPersistenceAdapter(),
        notifications: NotificationAdapter = MacOSNotificationAdapter(),
        startTimers: Bool = true
    ) {
        self.liveService = marketService
        self.persistence = persistence
        self.notifications = notifications
        self.isEphemeralPreview = ephemeralPreview
        if ephemeralPreview {
            self.instrument = .paxg
            self.timeframe = .m5
            self.isBootstrapping = false
            if let candles = initialCandles {
                self.allCandles = candles
                self.replayIndex = max(60, candles.count - 55)
                self.recomputeIndicators()
            } else {
                reloadMarket()
            }
            return
        }
        self.drawingsByInstrument = persistence.loadDrawings()
        self.journalEntries = persistence.loadJournal()
        self.alerts = persistence.loadAlerts()
        if let prefs = persistence.loadPrefs() {
            self.isDarkTheme = prefs.isDarkTheme
            self.activeStudies = prefs.activeStudies
            self.indicatorConfig = prefs.indicatorConfig
            self.showBacktestSignalsOnChart = prefs.showStrategyOverlay
            if let inst = Instrument(rawValue: prefs.instrumentRaw) { self.instrument = inst }
            if let tf = Timeframe(rawValue: prefs.timeframeRaw) { self.timeframe = tf }
            self.visibleCandleCount = max(14.0, min(260.0, prefs.visibleCandleCount))
            self.oscillatorHeight = CGFloat(max(72.0, min(420.0, prefs.oscillatorHeight)))
            self.tradeDrawerWidth = CGFloat(max(240.0, min(460.0, prefs.tradeDrawerWidth)))
            self.showTradeDrawer = prefs.showTradeDrawer
            self.magnetEnabled = prefs.magnetEnabled
            self.autoSizeByRisk = prefs.autoSizeByRisk
            self.riskPercentPerTrade = prefs.riskPercentPerTrade
            self.orderLots = prefs.orderLots
            self.orderStopPips = prefs.orderStopPips
            self.orderTakeProfitPips = prefs.orderTakeProfitPips
            self.sampleBalance = prefs.sampleBalance
            self.samplePositions = prefs.samplePositions
            self.paperPendingOrders = prefs.paperPendingOrders
            self.signalAlertsEnabled = prefs.signalAlertsEnabled
            self.zoneTouchAlertsEnabled = prefs.zoneTouchAlertsEnabled
            self.macOSNotificationsEnabled = prefs.macOSNotificationsEnabled
            self.soundAlertsEnabled = prefs.soundAlertsEnabled
        }
        self.isBootstrapping = false
        if startTimers {
            if macOSNotificationsEnabled {
                notifications.requestAuthorizationIfNeeded()
            }
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveWorkspacePrefs()
                }
            }
            reloadMarket()
            startCountdownTimer()
        }
    }

    deinit {
        loadTask?.cancel()
        liveService.disconnectStream()
        pollTimer?.invalidate()
        replayTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCandleCountdown()
            }
        }
        updateCandleCountdown()
    }

    private func updateCandleCountdown() {
        if isReplayMode || !marketStatus.isOpen {
            candleCountdownText = ""
            return
        }
        let tfSec = Int(timeframe.seconds)
        let nowSec = Int(Date().timeIntervalSince1970)
        let rem = tfSec - (nowSec % tfSec)
        let hrs = rem / 3600
        let mins = (rem % 3600) / 60
        let secs = rem % 60
        if hrs > 0 {
            candleCountdownText = String(format: "%02d:%02d:%02d", hrs, mins, secs)
        } else {
            candleCountdownText = String(format: "%02d:%02d", mins, secs)
        }
    }

    private func saveWorkspacePrefs() {
        guard !isBootstrapping, !isEphemeralPreview else { return }
        persistence.savePrefs(WorkspacePrefs(
            isDarkTheme: isDarkTheme,
            activeStudies: activeStudies,
            indicatorConfig: indicatorConfig,
            showStrategyOverlay: showBacktestSignalsOnChart,
            instrumentRaw: instrument.rawValue,
            timeframeRaw: timeframe.rawValue,
            visibleCandleCount: visibleCandleCount,
            oscillatorHeight: Double(oscillatorHeight),
            tradeDrawerWidth: Double(tradeDrawerWidth),
            showTradeDrawer: showTradeDrawer,
            magnetEnabled: magnetEnabled,
            autoSizeByRisk: autoSizeByRisk,
            riskPercentPerTrade: riskPercentPerTrade,
            orderLots: orderLots,
            orderStopPips: orderStopPips,
            orderTakeProfitPips: orderTakeProfitPips,
            sampleBalance: sampleBalance,
            samplePositions: samplePositions,
            paperPendingOrders: paperPendingOrders,
            signalAlertsEnabled: signalAlertsEnabled,
            zoneTouchAlertsEnabled: zoneTouchAlertsEnabled,
            macOSNotificationsEnabled: macOSNotificationsEnabled,
            soundAlertsEnabled: soundAlertsEnabled
        ))
    }

    // MARK: - Alerts

    func addAlert(studyTitle: String, isAbove: Bool, targetPrice: Double, note: String) {
        let alert = PriceAlert(
            instrument: instrument.rawValue,
            studyTitle: studyTitle,
            isAbove: isAbove,
            targetPrice: targetPrice,
            note: note
        )
        alerts.insert(alert, at: 0)
        persistence.saveAlerts(alerts)
    }

    func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
        persistence.saveAlerts(alerts)
    }

    private func evaluateAlerts(currentPrice: Double) {
        var changed = false
        for i in alerts.indices {
            guard !alerts[i].isTriggered, alerts[i].instrument == instrument.rawValue else { continue }
            let hit = alerts[i].isAbove ? (currentPrice >= alerts[i].targetPrice) : (currentPrice <= alerts[i].targetPrice)
            if hit {
                alerts[i].isTriggered = true
                triggeredAlertBanner = alerts[i]
                if soundAlertsEnabled { NSSound.beep() }
                if macOSNotificationsEnabled {
                    let dir = alerts[i].isAbove ? "crossed above" : "crossed below"
                    notifications.deliver(
                        title: "\(alerts[i].instrument) Price Alert",
                        body: "\(dir) \(instrument.formatPrice(alerts[i].targetPrice)) — \(alerts[i].note)",
                        sound: soundAlertsEnabled
                    )
                }
                changed = true
            }
        }
        if changed { persistence.saveAlerts(alerts) }
    }

    // MARK: - Confirmed Study Suite & Early Zone-Touch Signal Alerts

    private func barKey(_ index: Int) -> String {
        guard allCandles.indices.contains(index) else { return "\(index)" }
        return "\(Int(allCandles[index].timestamp.timeIntervalSince1970))"
    }

    /// Records all existing historical signals into `firedSignalKeys` so loading history,
    /// switching symbols/timeframes, or reconnecting never fires retroactive alerts.
    private func seedSignalAlertBaseline() {
        let prefix = "\(instrument.rawValue):\(timeframe.rawValue):"
        for sig in computed.reversalSignals {
            firedSignalKeys.insert("\(prefix)REV:\(sig.isBullish ? "BUY" : "SELL"):\(barKey(sig.index))")
        }
        for br in computed.structureBreaks {
            firedSignalKeys.insert("\(prefix)STRUCT:\(br.label):\(barKey(br.index))")
        }
        for acc in computed.accelerators {
            firedSignalKeys.insert("\(prefix)FLOW:\(acc.caption):\(barKey(acc.index))")
        }
        for sz in computed.scalpZones {
            firedSignalKeys.insert("\(prefix)SCALP:\(barKey(sz.startIndex))")
        }
        for tr in backtestReport.trades {
            firedSignalKeys.insert("\(prefix)STRAT:\(tr.isBuy ? "BUY" : "SELL"):\(barKey(tr.entryIndex))")
        }
        if allCandles.count >= 2 {
            let confirmedIdx = allCandles.count - 2
            firedSignalKeys.insert("\(prefix)WT:BULL:\(barKey(confirmedIdx))")
            firedSignalKeys.insert("\(prefix)WT:BEAR:\(barKey(confirmedIdx))")
        }
        isAlertBaselineSeeded = true
    }

    func evaluateStudySignalAlerts(currentPrice: Double) {
        guard isAlertBaselineSeeded, !isReplayMode, allCandles.count >= 3 else { return }
        let confirmedIdx = allCandles.count - 2
        let lastIdx = allCandles.count - 1
        let prefix = "\(instrument.rawValue):\(timeframe.rawValue):"
        let fmt: (Double) -> String = { self.instrument.formatPrice($0) }

        var newEvents: [SignalAlertEvent] = []

        if signalAlertsEnabled {
            // 1. Reversal & ATR Targets (BUY / SELL with exact ENTRY / SL / TP1 / TP2 / TP3)
            if isStudyVisible(.reversalTargets) {
                for sig in computed.reversalSignals where sig.index == confirmedIdx {
                    let dir = sig.isBullish ? "BUY" : "SELL"
                    let key = "\(prefix)REV:\(dir):\(barKey(sig.index))"
                    guard !firedSignalKeys.contains(key) else { continue }
                    newEvents.append(SignalAlertEvent(
                        id: UUID(),
                        dedupeKey: key,
                        instrument: instrument.rawValue,
                        timeframe: timeframe.rawValue,
                        category: "\(dir) Signal",
                        title: "\(instrument.rawValue) (\(timeframe.rawValue)) \(dir) Signal",
                        body: "ENTRY \(fmt(sig.entry)) · SL \(fmt(sig.stopLoss)) · TP1 \(fmt(sig.tp1)) · TP2 \(fmt(sig.tp2)) · TP3 \(fmt(sig.tp3))",
                        isBullish: sig.isBullish,
                        timestamp: Date(),
                        suggestedEntry: sig.entry,
                        suggestedSL: sig.stopLoss,
                        suggestedTP: sig.tp2
                    ))
                }
            }

            // 2. Market Structure Breaks (CHoCH / BOS+)
            if isStudyVisible(.concept) {
                for br in computed.structureBreaks where br.index == confirmedIdx && (br.label.contains("CHoCH") || br.label.contains("+")) {
                    let key = "\(prefix)STRUCT:\(br.label):\(barKey(br.index))"
                    guard !firedSignalKeys.contains(key) else { continue }
                    newEvents.append(SignalAlertEvent(
                        id: UUID(),
                        dedupeKey: key,
                        instrument: instrument.rawValue,
                        timeframe: timeframe.rawValue,
                        category: "Structure",
                        title: "\(instrument.rawValue) (\(timeframe.rawValue)) \(br.label)",
                        body: "\(br.isBullish ? "Bullish" : "Bearish") structure break confirmed at \(fmt(br.price))",
                        isBullish: br.isBullish,
                        timestamp: Date(),
                        suggestedEntry: nil,
                        suggestedSL: nil,
                        suggestedTP: nil
                    ))
                }
            }

            // 3. Order Flow Impulse (BuAx+ / BeAx+)
            if isStudyVisible(.orderFlow) {
                for acc in computed.accelerators where acc.index == confirmedIdx && acc.isPlus {
                    let key = "\(prefix)FLOW:\(acc.caption):\(barKey(acc.index))"
                    guard !firedSignalKeys.contains(key) else { continue }
                    newEvents.append(SignalAlertEvent(
                        id: UUID(),
                        dedupeKey: key,
                        instrument: instrument.rawValue,
                        timeframe: timeframe.rawValue,
                        category: "Order Flow",
                        title: "\(instrument.rawValue) (\(timeframe.rawValue)) \(acc.caption)",
                        body: "\(acc.isBullish ? "Bullish" : "Bearish") order-flow impulse confirmed at \(fmt(allCandles[confirmedIdx].close))",
                        isBullish: acc.isBullish,
                        timestamp: Date(),
                        suggestedEntry: nil,
                        suggestedSL: nil,
                        suggestedTP: nil
                    ))
                }
            }

            // 4. WaveTrend Oversold / Overbought Crossover
            if isStudyVisible(.momentumOscillator),
               confirmedIdx > 0,
               confirmedIdx < computed.waveTrend.count,
               let cur = computed.waveTrend[confirmedIdx],
               let prev = computed.waveTrend[confirmedIdx - 1] {
                if prev.wt1 <= prev.wt2 && cur.wt1 > cur.wt2 && cur.wt1 < -45.0 {
                    let key = "\(prefix)WT:BULL:\(barKey(confirmedIdx))"
                    if !firedSignalKeys.contains(key) {
                        newEvents.append(SignalAlertEvent(
                            id: UUID(),
                            dedupeKey: key,
                            instrument: instrument.rawValue,
                            timeframe: timeframe.rawValue,
                            category: "WaveTrend",
                            title: "\(instrument.rawValue) (\(timeframe.rawValue)) WaveTrend Bull Cross",
                            body: String(format: "Oversold WT cross (%.1f) at %@", cur.wt1, fmt(allCandles[confirmedIdx].close)),
                            isBullish: true,
                            timestamp: Date(),
                            suggestedEntry: nil,
                            suggestedSL: nil,
                            suggestedTP: nil
                        ))
                    }
                } else if prev.wt1 >= prev.wt2 && cur.wt1 < cur.wt2 && cur.wt1 > 45.0 {
                    let key = "\(prefix)WT:BEAR:\(barKey(confirmedIdx))"
                    if !firedSignalKeys.contains(key) {
                        newEvents.append(SignalAlertEvent(
                            id: UUID(),
                            dedupeKey: key,
                            instrument: instrument.rawValue,
                            timeframe: timeframe.rawValue,
                            category: "WaveTrend",
                            title: "\(instrument.rawValue) (\(timeframe.rawValue)) WaveTrend Bear Cross",
                            body: String(format: "Overbought WT cross (%.1f) at %@", cur.wt1, fmt(allCandles[confirmedIdx].close)),
                            isBullish: false,
                            timestamp: Date(),
                            suggestedEntry: nil,
                            suggestedSL: nil,
                            suggestedTP: nil
                        ))
                    }
                }
            }

            // 5. 4-Stage Strategy Engine Confirmed Entry
            if showBacktestSignalsOnChart {
                for tr in backtestReport.trades where tr.entryIndex == confirmedIdx {
                    let dir = tr.isBuy ? "BUY" : "SELL"
                    let key = "\(prefix)STRAT:\(dir):\(barKey(tr.entryIndex))"
                    guard !firedSignalKeys.contains(key) else { continue }
                    newEvents.append(SignalAlertEvent(
                        id: UUID(),
                        dedupeKey: key,
                        instrument: instrument.rawValue,
                        timeframe: timeframe.rawValue,
                        category: "Strategy Engine",
                        title: "\(instrument.rawValue) (\(timeframe.rawValue)) 4-Stage \(dir)",
                        body: "ENTRY \(fmt(tr.entryPrice)) · SL \(fmt(tr.stopLoss)) · TP \(fmt(tr.takeProfit))",
                        isBullish: tr.isBuy,
                        timestamp: Date(),
                        suggestedEntry: tr.entryPrice,
                        suggestedSL: tr.stopLoss,
                        suggestedTP: tr.takeProfit
                    ))
                }
            }
        }

        // 6. Early Pre-Run Zone-Touch Alerts (active unmitigated Order Block & unfilled FVG)
        if zoneTouchAlertsEnabled {
            let liveBarTag = barKey(lastIdx)
            if isStudyVisible(.concept) {
                for ob in computed.orderBlocks where !ob.mitigated && ob.startIndex < lastIdx {
                    if currentPrice >= ob.bottom && currentPrice <= ob.top {
                        let key = "\(prefix)ZONE_OB:\(ob.startIndex):\(liveBarTag)"
                        guard !firedSignalKeys.contains(key) else { continue }
                        newEvents.append(SignalAlertEvent(
                            id: UUID(),
                            dedupeKey: key,
                            instrument: instrument.rawValue,
                            timeframe: timeframe.rawValue,
                            category: "Zone Touch",
                            title: "\(instrument.rawValue) Tapped \(ob.isBullish ? "Bullish" : "Bearish") Order Block",
                            body: "Early setup watch at \(fmt(currentPrice)) (Zone \(fmt(ob.bottom))–\(fmt(ob.top)))",
                            isBullish: ob.isBullish,
                            timestamp: Date(),
                            suggestedEntry: nil,
                            suggestedSL: nil,
                            suggestedTP: nil
                        ))
                    }
                }
            }
            if isStudyVisible(.orderFlow) {
                for fvg in computed.fvgs where !fvg.filled && fvg.startIndex < lastIdx {
                    if currentPrice >= fvg.bottom && currentPrice <= fvg.top {
                        let key = "\(prefix)ZONE_FVG:\(fvg.startIndex):\(liveBarTag)"
                        guard !firedSignalKeys.contains(key) else { continue }
                        newEvents.append(SignalAlertEvent(
                            id: UUID(),
                            dedupeKey: key,
                            instrument: instrument.rawValue,
                            timeframe: timeframe.rawValue,
                            category: "Zone Touch",
                            title: "\(instrument.rawValue) Tapped \(fvg.isBullish ? "Bullish" : "Bearish") FVG",
                            body: "Early imbalance retest at \(fmt(currentPrice)) (FVG \(fmt(fvg.bottom))–\(fmt(fvg.top)))",
                            isBullish: fvg.isBullish,
                            timestamp: Date(),
                            suggestedEntry: nil,
                            suggestedSL: nil,
                            suggestedTP: nil
                        ))
                    }
                }
            }
        }

        guard !newEvents.isEmpty else { return }
        for ev in newEvents {
            firedSignalKeys.insert(ev.dedupeKey)
            recentSignalAlerts.insert(ev, at: 0)
            triggeredSignalBanner = ev
            if macOSNotificationsEnabled {
                notifications.deliver(title: ev.title, body: ev.body, sound: soundAlertsEnabled)
            }
        }
        if recentSignalAlerts.count > 25 {
            recentSignalAlerts.removeLast(recentSignalAlerts.count - 25)
        }
        if soundAlertsEnabled {
            NSSound.beep()
        }
    }

    /// Copies a signal's suggested SL and TP distances (in pips) straight into the Paper Desk order ticket.
    func applySignalTargetsToOrderTicket(_ event: SignalAlertEvent) {
        guard let entry = event.suggestedEntry,
              let sl = event.suggestedSL,
              let tp = event.suggestedTP else { return }
        let pip = max(instrument.pipSize, 1e-6)
        orderStopPips = max(1.0, (abs(entry - sl) / pip).rounded())
        orderTakeProfitPips = max(1.0, (abs(tp - entry) / pip).rounded())
        showTradeDrawer = true
    }

    // MARK: - Market Loading (LIVE + SAMPLE)

    func reloadMarket() {
        loadTask?.cancel()
        backfillTask?.cancel()
        isBackfillingHistory = false
        reconnectWorkItem?.cancel()
        reconnectAttempt = 0
        wsRotationTimer?.invalidate()
        wsRotationTimer = nil
        liveService.disconnectStream()
        pollTimer?.invalidate()
        pollTimer = nil
        stopReplayPlayback()
        isReplayMode = false
        orderFlowTrades = []
        buyVolumeWindow = 0
        sellVolumeWindow = 0
        marketStatus = instrument.marketStatus()
        rightOffsetBars = 6.0
        isAutoPriceScale = true
        spotBasisOffset = 0.0
        isAlertBaselineSeeded = false

        let selectedInstrument = instrument
        let selectedTimeframe = timeframe
        liveFeedState = .connecting(selectedInstrument.binanceSymbol != nil ? "Binance" : "Yahoo Finance")

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await self.liveService.fetchHistoricalCandles(
                    instrument: selectedInstrument,
                    timeframe: selectedTimeframe,
                    limit: 500,
                    endTime: nil
                )
                guard !Task.isCancelled,
                      self.instrument == selectedInstrument,
                      self.timeframe == selectedTimeframe else { return }

                var loadedCandles = res.candles
                // For XAU/USD, align 0-delay real-time Gold klines (PAXGUSDT) to institutional
                // Swissquote Spot XAU/USD at the exact same second so candles match OANDA/Spot
                // breakouts in real time with zero 10-minute Yahoo Futures lag.
                if selectedInstrument == .xauusd,
                   res.provider == "Binance",
                   let lastClose = loadedCandles.last?.close,
                   let spotQuote = try? await self.liveService.fetchLiveSpotQuote(instrument: selectedInstrument) {
                    let basis = spotQuote.price - lastClose
                    if abs(basis) < lastClose * 0.05 {
                        self.spotBasisOffset = basis
                        loadedCandles = Self.shiftCandles(loadedCandles, by: basis)
                    }
                }

                self.allCandles = loadedCandles
                self.replayIndex = max(60, loadedCandles.count - 55)
                self.recomputeIndicators()
                self.seedSignalAlertBaseline()

                if let binSym = selectedInstrument.binanceSymbol, res.provider == "Binance" {
                    self.startLiveBinanceStream(symbol: binSym, interval: selectedTimeframe.binanceInterval)
                } else if selectedInstrument.swissquotePath != nil {
                    self.liveFeedState = .streaming("Swissquote Spot")
                    self.startSwissquoteSpotPolling(instrument: selectedInstrument, timeframe: selectedTimeframe)
                } else {
                    self.liveFeedState = .polling("Yahoo Live")
                    self.startYahooPolling(instrument: selectedInstrument, timeframe: selectedTimeframe)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.liveFeedState = .error("Feed unavailable")
            }
        }
    }

    /// Paginates older historical candles backward using endTime = earliestOpenMs - 1ms
    /// and prepends deduplicated bars while keeping visible scroll and drawings anchored.
    func backfillOlderHistory() async {
        guard !isBackfillingHistory,
              allCandles.count < 4000,
              let earliest = allCandles.first else { return }

        isBackfillingHistory = true
        defer { isBackfillingHistory = false }

        let targetInstrument = instrument
        let targetTimeframe = timeframe
        let endTime = earliest.timestamp.addingTimeInterval(-0.001)

        do {
            let res = try await liveService.fetchHistoricalCandles(
                instrument: targetInstrument,
                timeframe: targetTimeframe,
                limit: 500,
                endTime: endTime
            )
            guard instrument == targetInstrument,
                  timeframe == targetTimeframe else { return }

            var olderUnique = res.candles
                .filter { $0.timestamp.timeIntervalSince1970 < earliest.timestamp.timeIntervalSince1970 - 0.5 }
                .sorted { $0.timestamp < $1.timestamp }

            guard !olderUnique.isEmpty else { return }

            if spotBasisOffset != 0.0 {
                olderUnique = Self.shiftCandles(olderUnique, by: spotBasisOffset)
            }

            let prependedCount = olderUnique.count
            let combined = (olderUnique + allCandles).enumerated().map { idx, item in
                Candle(
                    id: idx,
                    timestamp: item.timestamp,
                    open: item.open,
                    high: item.high,
                    low: item.low,
                    close: item.close,
                    volume: item.volume
                )
            }
            allCandles = combined
            if isReplayMode {
                replayIndex += prependedCount
            }
            recomputeIndicators()
        } catch {
            // Best-effort backfill; ignore transient network/429 failure
        }
    }

    private func startLiveBinanceStream(symbol: String, interval: String) {
        wsRotationTimer?.invalidate()
        // Proactive 23h45m rotation before Binance's hard 24h WebSocket cutoff
        wsRotationTimer = Timer.scheduledTimer(withTimeInterval: 85_500, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let sym = self.instrument.binanceSymbol else { return }
                self.startLiveBinanceStream(symbol: sym, interval: self.timeframe.binanceInterval)
            }
        }

        liveService.startBinanceStream(
            symbol: symbol,
            interval: interval,
            onKline: { [weak self] ts, o, h, l, c, v in
                Task { @MainActor [weak self] in
                    self?.reconnectAttempt = 0
                    self?.applyLiveKline(timestamp: ts, open: o, high: h, low: l, close: c, volume: v)
                }
            },
            onTrade: { [weak self] trade in
                Task { @MainActor [weak self] in
                    self?.ingestOrderFlowTrade(trade)
                }
            },
            onStatus: { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.liveFeedState = status
                    if case .error = status, self.instrument.binanceSymbol == symbol {
                        self.scheduleBinanceReconnect(symbol: symbol, interval: interval)
                    }
                }
            }
        )
    }

    private func scheduleBinanceReconnect(symbol: String, interval: String) {
        reconnectWorkItem?.cancel()
        let expDelay = min(60.0, pow(2.0, Double(min(reconnectAttempt, 6))))
        let jitter = Double.random(in: 0.8...1.2)
        let delay = max(1.0, expDelay * jitter)
        reconnectAttempt += 1

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.instrument.binanceSymbol == symbol else { return }
                if let gap = try? await self.liveService.fetchHistoricalCandles(
                    instrument: self.instrument,
                    timeframe: self.timeframe,
                    limit: 60,
                    endTime: nil
                ) {
                    let gapCandles = self.spotBasisOffset != 0.0
                        ? Self.shiftCandles(gap.candles, by: self.spotBasisOffset)
                        : gap.candles
                    self.mergeTailCandles(gapCandles)
                    self.recomputeIndicators()
                    self.seedSignalAlertBaseline()
                }
                self.startLiveBinanceStream(symbol: symbol, interval: interval)
            }
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startSwissquoteSpotPolling(instrument: Instrument, timeframe: Timeframe) {
        pollTimer?.invalidate()
        // Immediate first tick so the live price snaps to real-time spot without waiting 1s
        Task { @MainActor [weak self] in
            guard let self, self.instrument == instrument, self.timeframe == timeframe else { return }
            if let quote = try? await self.liveService.fetchLiveSpotQuote(instrument: instrument) {
                self.applyLiveSpotTick(price: quote.price, timestamp: quote.timestamp)
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isReplayMode,
                      self.instrument == instrument, self.timeframe == timeframe else { return }
                self.marketStatus = instrument.marketStatus()
                guard self.marketStatus.isOpen else { return }
                if let quote = try? await self.liveService.fetchLiveSpotQuote(instrument: instrument) {
                    self.applyLiveSpotTick(price: quote.price, timestamp: quote.timestamp)
                }
            }
        }
    }

    private static func shiftCandles(_ candles: [Candle], by offset: Double) -> [Candle] {
        guard offset != 0.0 else { return candles }
        return candles.map { c in
            Candle(
                id: c.id,
                timestamp: c.timestamp,
                open: c.open + offset,
                high: c.high + offset,
                low: c.low + offset,
                close: c.close + offset,
                volume: c.volume
            )
        }
    }

    func applyLiveSpotTick(price: Double, timestamp: Date) {
        guard price.isFinite, price > 0, !allCandles.isEmpty else { return }
        if let last = allCandles.last, abs(price - last.close) > last.close * 0.05 {
            // Reject corrupted outlier tick (>5% single-tick jump)
            return
        }
        let bucketSec = timeframe.seconds
        let incomingBucket = floor(timestamp.timeIntervalSince1970 / bucketSec) * bucketSec
        let alignedDate = Date(timeIntervalSince1970: incomingBucket)

        if let last = allCandles.last {
            let lastBucket = floor(last.timestamp.timeIntervalSince1970 / bucketSec) * bucketSec
            if abs(lastBucket - incomingBucket) < 0.5 {
                allCandles[allCandles.count - 1] = Candle(
                    id: last.id,
                    timestamp: alignedDate,
                    open: last.open,
                    high: max(last.high, price),
                    low: min(last.low, price),
                    close: price,
                    volume: last.volume + 1.0
                )
            } else if incomingBucket > lastBucket {
                let openPrice = last.close
                allCandles.append(Candle(
                    id: last.id + 1,
                    timestamp: alignedDate,
                    open: openPrice,
                    high: max(openPrice, price),
                    low: min(openPrice, price),
                    close: price,
                    volume: 1.0
                ))
            }
        }

        if let latest = allCandles.last {
            recomputeIndicators()
            evaluateAlerts(currentPrice: price)
            evaluateStudySignalAlerts(currentPrice: price)
            evaluatePaperDeskExecution(barLow: latest.low, barHigh: latest.high, currentPrice: price)
        }
    }

    private func startYahooPolling(instrument: Instrument, timeframe: Timeframe) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isReplayMode,
                      self.instrument == instrument, self.timeframe == timeframe else { return }
                self.marketStatus = instrument.marketStatus()
                guard self.marketStatus.isOpen else { return }
                if let tail = try? await self.liveService.fetchLiveTailCandles(
                    instrument: instrument,
                    timeframe: timeframe
                ), !tail.isEmpty {
                    self.mergeTailCandles(tail)
                    self.recomputeIndicators()
                    self.evaluateAlerts(currentPrice: self.lastPrice)
                    self.evaluateStudySignalAlerts(currentPrice: self.lastPrice)
                    if let latest = self.allCandles.last {
                        self.evaluatePaperDeskExecution(barLow: latest.low, barHigh: latest.high, currentPrice: latest.close)
                    }
                }
            }
        }
    }

    func mergeTailCandles(_ incoming: [Candle]) {
        guard !incoming.isEmpty else { return }
        let bucketSec = timeframe.seconds
        func bucketEpoch(_ date: Date) -> TimeInterval {
            floor(date.timeIntervalSince1970 / bucketSec) * bucketSec
        }

        if allCandles.isEmpty {
            allCandles = incoming.enumerated().map { idx, c in
                Candle(
                    id: idx,
                    timestamp: Date(timeIntervalSince1970: bucketEpoch(c.timestamp)),
                    open: c.open,
                    high: max(c.open, c.high, c.low, c.close),
                    low: min(c.open, c.high, c.low, c.close),
                    close: c.close,
                    volume: c.volume
                )
            }
            return
        }

        for bar in incoming {
            let incomingBucket = bucketEpoch(bar.timestamp)
            let alignedDate = Date(timeIntervalSince1970: incomingBucket)

            if let idx = allCandles.lastIndex(where: { abs(bucketEpoch($0.timestamp) - incomingBucket) < 0.5 }) {
                let existing = allCandles[idx]
                allCandles[idx] = Candle(
                    id: existing.id,
                    timestamp: alignedDate,
                    open: existing.open,
                    high: max(existing.high, bar.high),
                    low: min(existing.low, bar.low),
                    close: bar.close,
                    volume: max(existing.volume, bar.volume)
                )
            } else if let last = allCandles.last, incomingBucket > bucketEpoch(last.timestamp) {
                allCandles.append(Candle(
                    id: last.id + 1,
                    timestamp: alignedDate,
                    open: bar.open,
                    high: max(bar.open, bar.high, bar.low, bar.close),
                    low: min(bar.open, bar.high, bar.low, bar.close),
                    close: bar.close,
                    volume: bar.volume
                ))
            }
        }
    }

    private func applyLiveKline(timestamp: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        guard !allCandles.isEmpty else { return }
        let o = open + spotBasisOffset
        let h = high + spotBasisOffset
        let l = low + spotBasisOffset
        let c = close + spotBasisOffset
        if let last = allCandles.last, abs(last.timestamp.timeIntervalSince(timestamp)) < 1.0 {
            allCandles[allCandles.count - 1] = Candle(
                id: last.id,
                timestamp: timestamp,
                open: o,
                high: h,
                low: l,
                close: c,
                volume: volume
            )
        } else if let last = allCandles.last, timestamp > last.timestamp {
            let nextId = last.id + 1
            allCandles.append(Candle(
                id: nextId,
                timestamp: timestamp,
                open: o,
                high: h,
                low: l,
                close: c,
                volume: volume
            ))
            if allCandles.count > 4500 {
                allCandles.removeFirst(allCandles.count - 4500)
                allCandles = allCandles.enumerated().map { idx, item in
                    Candle(id: idx, timestamp: item.timestamp, open: item.open, high: item.high, low: item.low, close: item.close, volume: item.volume)
                }
            }
        }
        recomputeIndicators()
        evaluateAlerts(currentPrice: c)
        evaluateStudySignalAlerts(currentPrice: c)
        evaluatePaperDeskExecution(barLow: l, barHigh: h, currentPrice: c)
    }

    private func ingestOrderFlowTrade(_ trade: OrderFlowTrade) {
        let adjusted = spotBasisOffset != 0.0
            ? OrderFlowTrade(
                id: trade.id,
                timestamp: trade.timestamp,
                price: trade.price + spotBasisOffset,
                quantity: trade.quantity,
                usdValue: trade.usdValue,
                isBuyerAggressor: trade.isBuyerAggressor
            )
            : trade
        orderFlowTrades.insert(adjusted, at: 0)
        if orderFlowTrades.count > 45 {
            orderFlowTrades.removeLast(orderFlowTrades.count - 45)
        }
        if trade.isBuyerAggressor {
            buyVolumeWindow = buyVolumeWindow * 0.96 + trade.usdValue
        } else {
            sellVolumeWindow = sellVolumeWindow * 0.96 + trade.usdValue
        }
    }

    func recomputeIndicators() {
        computed = IndicatorEngine.computeAll(candles: visibleSeries, config: indicatorConfig)
        recomputeBacktest()
    }

    func recomputeBacktest() {
        backtestReport = BacktestEngine.run(
            candles: visibleSeries,
            indicators: computed,
            strategy: strategyConfig,
            startingBalance: 10_000.0
        )
    }

    // MARK: - Camera Controls (TradingView-Style X/Y Scaling & Panning)

    func zoom(factor: Double, anchorFraction: Double = 0.85) {
        let oldVis = visibleCandleCount
        let newVis = max(14.0, min(260.0, oldVis * factor))
        let count = Double(max(1, visibleSeries.count))
        let oldEnd = (count - 1.0) + rightOffsetBars
        let oldStart = oldEnd - oldVis
        let anchorIndex = oldStart + anchorFraction * oldVis
        let newStart = anchorIndex - anchorFraction * newVis
        let newEnd = newStart + newVis
        let newRightOffset = newEnd - (count - 1.0)

        visibleCandleCount = newVis
        let maxScrollBack = Double(max(0, visibleSeries.count - 10))
        rightOffsetBars = max(-maxScrollBack, min(120.0, newRightOffset))
    }

    func pan(deltaBars: Double) {
        let maxScrollBack = Double(max(0, visibleSeries.count - 10))
        rightOffsetBars = max(-maxScrollBack, min(120.0, rightOffsetBars + deltaBars))

        // Trigger background backfill when panning within 35 bars of the earliest loaded candle
        let leftVisibleIdx = Double(visibleSeries.count - 1) + rightOffsetBars - visibleCandleCount
        if leftVisibleIdx < 35.0, !isBackfillingHistory {
            backfillTask = Task { [weak self] in
                await self?.backfillOlderHistory()
            }
        }
    }

    func scalePriceAxis(deltaY: CGFloat, currentMin: Double, currentMax: Double) {
        let minP = isAutoPriceScale ? currentMin : manualPriceMin
        let maxP = isAutoPriceScale ? currentMax : manualPriceMax
        let mid = (minP + maxP) * 0.5
        let halfSpan = max((maxP - minP) * 0.5, instrument.pipSize * 2.0)
        // Dragging down (positive deltaY) expands range (compresses candles); dragging up stretches candles
        let scale = exp(Double(deltaY) * 0.0075)
        let newHalf = max(instrument.pipSize * 2.0, min(mid * 0.9, halfSpan * scale))
        isAutoPriceScale = false
        manualPriceMin = mid - newHalf
        manualPriceMax = mid + newHalf
    }

    func panPriceAxis(deltaPrice: Double, currentMin: Double, currentMax: Double) {
        guard !isAutoPriceScale else { return }
        manualPriceMin += deltaPrice
        manualPriceMax += deltaPrice
    }

    func resetPriceScale() {
        isAutoPriceScale = true
    }

    func resetCamera() {
        visibleCandleCount = 95.0
        rightOffsetBars = 6.0
        isAutoPriceScale = true
    }

    func jumpToLatest() {
        rightOffsetBars = 6.0
        isAutoPriceScale = true
    }

    var isScrolledBackInHistory: Bool {
        rightOffsetBars < -6.0
    }

    // MARK: - Drawings (Auto-Persisted + Interactive Edit)

    func pushDrawingUndoSnapshot() {
        var stack = undoStackByInstrument[instrument] ?? []
        stack.append(currentDrawings)
        if stack.count > 40 { stack.removeFirst() }
        undoStackByInstrument[instrument] = stack
    }

    func addDrawing(_ drawing: DrawingObject) {
        pushDrawingUndoSnapshot()
        var list = currentDrawings
        list.append(drawing)
        drawingsByInstrument[instrument] = list
        selectedDrawingId = drawing.id
        persistence.saveDrawings(drawingsByInstrument)
    }

    func updateDrawing(_ updated: DrawingObject, persist: Bool = false) {
        var list = currentDrawings
        guard let idx = list.firstIndex(where: { $0.id == updated.id }) else { return }
        list[idx] = updated
        drawingsByInstrument[instrument] = list
        if persist {
            persistence.saveDrawings(drawingsByInstrument)
        }
    }

    func setSelectedDrawingColor(_ presetId: String) {
        guard let id = selectedDrawingId,
              var obj = currentDrawings.first(where: { $0.id == id }) else { return }
        pushDrawingUndoSnapshot()
        obj.colorPresetId = presetId
        updateDrawing(obj, persist: true)
    }

    func duplicateSelectedDrawing() {
        guard let id = selectedDrawingId,
              let obj = currentDrawings.first(where: { $0.id == id }) else { return }
        let offsetP = instrument.pipSize * 12.0
        let copy = DrawingObject(
            id: UUID(),
            tool: obj.tool,
            start: ChartPoint(index: obj.start.index + 3, price: obj.start.price + offsetP),
            end: ChartPoint(index: obj.end.index + 3, price: obj.end.price + offsetP),
            colorPresetId: obj.colorPresetId,
            label: obj.label,
            riskReward: obj.riskReward
        )
        addDrawing(copy)
    }

    func deleteSelectedDrawing() {
        guard let id = selectedDrawingId else { return }
        removeDrawing(id: id)
        selectedDrawingId = nil
    }

    func removeDrawing(id: UUID) {
        pushDrawingUndoSnapshot()
        var list = currentDrawings
        list.removeAll { $0.id == id }
        drawingsByInstrument[instrument] = list
        if selectedDrawingId == id { selectedDrawingId = nil }
        persistence.saveDrawings(drawingsByInstrument)
    }

    func undoDrawing() {
        guard var stack = undoStackByInstrument[instrument], let previous = stack.popLast() else { return }
        undoStackByInstrument[instrument] = stack
        drawingsByInstrument[instrument] = previous
        selectedDrawingId = nil
        persistence.saveDrawings(drawingsByInstrument)
    }

    func clearDrawings() {
        guard !currentDrawings.isEmpty else { return }
        pushDrawingUndoSnapshot()
        drawingsByInstrument[instrument] = []
        selectedDrawingId = nil
        persistence.saveDrawings(drawingsByInstrument)
    }

    // MARK: - Bar Replay

    func toggleReplayMode() {
        if isReplayMode {
            stopReplayPlayback()
            isReplayMode = false
        } else {
            isReplayMode = true
            replayIndex = max(60, allCandles.count - 55)
            rightOffsetBars = 8.0
        }
        recomputeIndicators()
    }

    func stepReplayForward() {
        guard isReplayMode else { return }
        if replayIndex < allCandles.count {
            replayIndex += 1
            recomputeIndicators()
        } else {
            stopReplayPlayback()
        }
    }

    func stepReplayBackward() {
        guard isReplayMode, replayIndex > 35 else { return }
        replayIndex -= 1
        recomputeIndicators()
    }

    func toggleReplayPlay() {
        if isReplayPlaying {
            stopReplayPlayback()
        } else {
            guard isReplayMode else { return }
            isReplayPlaying = true
            restartReplayTimer()
        }
    }

    func setReplaySpeed(_ speed: Double) {
        replaySpeed = speed
        if isReplayPlaying { restartReplayTimer() }
    }

    private func restartReplayTimer() {
        replayTimer?.invalidate()
        let interval = max(0.08, 1.0 / replaySpeed)
        replayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepReplayForward()
            }
        }
    }

    func stopReplayPlayback() {
        isReplayPlaying = false
        replayTimer?.invalidate()
        replayTimer = nil
    }

    // MARK: - Paper Desk Execution, Pending Orders & Auto-Journal Logging

    func openSampleOrder(isBuy: Bool) {
        let entry = isBuy ? (lastPrice + instrument.spread * 0.5) : (lastPrice - instrument.spread * 0.5)
        let slDist = orderStopPips * instrument.pipSize
        let tpDist = orderTakeProfitPips * instrument.pipSize
        let sl = orderStopPips > 0 ? (isBuy ? entry - slDist : entry + slDist) : nil
        let tp = orderTakeProfitPips > 0 ? (isBuy ? entry + tpDist : entry - tpDist) : nil
        let pos = SamplePosition(
            id: UUID(),
            instrument: instrument,
            isBuy: isBuy,
            lots: effectiveOrderLots,
            entryPrice: entry,
            stopLoss: sl,
            takeProfit: tp,
            openedAt: Date()
        )
        samplePositions.insert(pos, at: 0)
    }

    func placePendingOrder(kind: PendingOrderKind, isBuy: Bool, entryPrice: Double) {
        let slDist = orderStopPips * instrument.pipSize
        let tpDist = orderTakeProfitPips * instrument.pipSize
        let sl = orderStopPips > 0 ? (isBuy ? entryPrice - slDist : entryPrice + slDist) : nil
        let tp = orderTakeProfitPips > 0 ? (isBuy ? entryPrice + tpDist : entryPrice - tpDist) : nil
        let pending = PaperPendingOrder(
            id: UUID(),
            instrument: instrument,
            kind: kind,
            isBuy: isBuy,
            lots: effectiveOrderLots,
            entryPrice: entryPrice,
            stopLoss: sl,
            takeProfit: tp,
            createdAt: Date()
        )
        paperPendingOrders.insert(pending, at: 0)
    }

    func cancelPendingOrder(id: UUID) {
        paperPendingOrders.removeAll { $0.id == id }
    }

    func movePaperPositionToBreakeven(id: UUID) {
        guard let idx = samplePositions.firstIndex(where: { $0.id == id }) else { return }
        samplePositions[idx].stopLoss = samplePositions[idx].entryPrice
    }

    func partialClosePaperPosition(id: UUID, fraction: Double = 0.5, fillPrice: Double? = nil) {
        guard let idx = samplePositions.firstIndex(where: { $0.id == id }) else { return }
        let pos = samplePositions[idx]
        let clamped = max(0.1, min(0.95, fraction))
        let closeLots = max(0.01, (pos.lots * clamped * 100.0).rounded() / 100.0)
        guard closeLots < pos.lots else {
            closeSamplePosition(id: id, fillPrice: fillPrice, reasonNote: "Full close from Paper Desk")
            return
        }

        let exitPrice = fillPrice ?? ((pos.instrument == instrument) ? lastPrice : pos.instrument.basePrice)
        samplePositions[idx].lots = max(0.01, ((pos.lots - closeLots) * 100.0).rounded() / 100.0)
        logClosedPaperTrade(
            pos: pos,
            closedLots: closeLots,
            exitPrice: exitPrice,
            note: "Partial close (\(Int(clamped * 100))%) from Paper Desk"
        )
    }

    func evaluatePaperDeskExecution(barLow: Double, barHigh: Double, currentPrice: Double) {
        // 1. Trigger eligible pending Limit / Stop orders for current instrument
        var remainingPending: [PaperPendingOrder] = []
        for ord in paperPendingOrders {
            if ord.instrument == instrument && ord.shouldTrigger(barLow: barLow, barHigh: barHigh) {
                let filled = SamplePosition(
                    id: ord.id,
                    instrument: ord.instrument,
                    isBuy: ord.isBuy,
                    lots: ord.lots,
                    entryPrice: ord.entryPrice,
                    stopLoss: ord.stopLoss,
                    takeProfit: ord.takeProfit,
                    openedAt: Date()
                )
                samplePositions.insert(filled, at: 0)
            } else {
                remainingPending.append(ord)
            }
        }
        if remainingPending.count != paperPendingOrders.count {
            paperPendingOrders = remainingPending
        }

        // 2. Check open positions for automatic SL / TP execution (conservative SL-first tie-break)
        var toClose: [(id: UUID, price: Double, note: String)] = []
        for pos in samplePositions where pos.instrument == instrument {
            if let sl = pos.stopLoss {
                let slHit = pos.isBuy ? (barLow <= sl) : (barHigh >= sl)
                if slHit {
                    let isBE = abs(sl - pos.entryPrice) <= pos.instrument.pipSize * 0.5
                    toClose.append((pos.id, sl, isBE ? "Auto Breakeven Stop Fill" : "Auto SL Fill"))
                    continue
                }
            }
            if let tp = pos.takeProfit {
                let tpHit = pos.isBuy ? (barHigh >= tp) : (barLow <= tp)
                if tpHit {
                    toClose.append((pos.id, tp, "Auto TP Fill"))
                }
            }
        }

        for item in toClose {
            closeSamplePosition(id: item.id, fillPrice: item.price, reasonNote: item.note)
        }
    }

    func closeSamplePosition(id: UUID, fillPrice: Double? = nil, reasonNote: String? = nil) {
        guard let idx = samplePositions.firstIndex(where: { $0.id == id }) else { return }
        let pos = samplePositions[idx]
        let exitPrice = fillPrice ?? ((pos.instrument == instrument) ? lastPrice : pos.instrument.basePrice)
        logClosedPaperTrade(
            pos: pos,
            closedLots: pos.lots,
            exitPrice: exitPrice,
            note: reasonNote ?? "Closed from Paper Desk"
        )
        samplePositions.remove(at: idx)
    }

    private func logClosedPaperTrade(pos: SamplePosition, closedLots: Double, exitPrice: Double, note: String) {
        let diff = pos.isBuy ? (exitPrice - pos.entryPrice) : (pos.entryPrice - exitPrice)
        let pipCount = diff / pos.instrument.pipSize
        let pnl = pipCount * closedLots * pos.instrument.dollarPerPipPerLot
        sampleBalance += pnl

        let riskPips = pos.stopLoss.map { abs(pos.entryPrice - $0) / pos.instrument.pipSize } ?? max(orderStopPips, 10.0)
        let riskUSD = max(1.0, max(riskPips, 1.0) * closedLots * pos.instrument.dollarPerPipPerLot)
        addJournalEntry(JournalEntry(
            instrument: pos.instrument.rawValue,
            timeframe: timeframe.rawValue,
            isBuy: pos.isBuy,
            entryPrice: pos.entryPrice,
            exitPrice: exitPrice,
            lots: closedLots,
            pnlUSD: pnl,
            rMultiple: pnl / riskUSD,
            setupTag: "OB Retest",
            disciplineTag: "Followed Plan",
            notes: note,
            isLiveAccount: false
        ))
    }

    func closeAllSamplePositions() {
        let ids = samplePositions.map(\.id)
        for id in ids { closeSamplePosition(id: id) }
    }

    func addJournalEntry(_ entry: JournalEntry) {
        journalEntries.insert(entry, at: 0)
        persistence.saveJournal(journalEntries)
    }

    func deleteJournalEntry(id: UUID) {
        journalEntries.removeAll { $0.id == id }
        persistence.saveJournal(journalEntries)
    }
}
