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
    @Published var dataMode: DataSourceMode = .live {
        didSet {
            saveWorkspacePrefs()
            if !isBootstrapping { reloadMarket() }
        }
    }
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
    @Published var liveTickSimulation: Bool = true
    @Published var allowClosedMarketSim: Bool = false

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
    @Published private(set) var computed = ComputedIndicators()
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

    // Live Price Alerts
    @Published var alerts: [PriceAlert] = []
    @Published var triggeredAlertBanner: PriceAlert? = nil

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

    // Risk Calculator & Paper Trading Account
    @Published var sampleBalance: Double = 10_000.0 {
        didSet { saveWorkspacePrefs() }
    }
    @Published var samplePositions: [SamplePosition] = [] {
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

    private let liveService = LiveMarketService()
    private var loadTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var replayTimer: Timer?
    private var liveRNG = SeededRNG(seed: 0xB7AD321AB)
    private var isBootstrapping = true

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
        if dataMode == .live {
            if case .streaming = liveFeedState { return !isReplayMode }
            if case .polling = liveFeedState { return !isReplayMode && marketStatus.isOpen }
            return false
        }
        return liveTickSimulation && !isReplayMode && (marketStatus.isOpen || allowClosedMarketSim)
    }

    init() {
        self.drawingsByInstrument = PersistenceStore.loadDrawings()
        self.journalEntries = PersistenceStore.loadJournal()
        self.alerts = PersistenceStore.loadAlerts()
        if let prefs = PersistenceStore.loadPrefs() {
            self.isDarkTheme = prefs.isDarkTheme
            self.activeStudies = prefs.activeStudies
            self.indicatorConfig = prefs.indicatorConfig
            self.showBacktestSignalsOnChart = prefs.showStrategyOverlay
            if let m = DataSourceMode(rawValue: prefs.dataModeRaw) { self.dataMode = m }
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
        }
        self.isBootstrapping = false
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveWorkspacePrefs()
            }
        }
        reloadMarket()
        startSampleTickTimer()
        startCountdownTimer()
    }

    deinit {
        loadTask?.cancel()
        liveService.disconnectStream()
        pollTimer?.invalidate()
        tickTimer?.invalidate()
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
        guard !isBootstrapping else { return }
        PersistenceStore.savePrefs(WorkspacePrefs(
            isDarkTheme: isDarkTheme,
            activeStudies: activeStudies,
            indicatorConfig: indicatorConfig,
            showStrategyOverlay: showBacktestSignalsOnChart,
            dataModeRaw: dataMode.rawValue,
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
            samplePositions: samplePositions
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
        PersistenceStore.saveAlerts(alerts)
    }

    func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
        PersistenceStore.saveAlerts(alerts)
    }

    private func evaluateAlerts(currentPrice: Double) {
        var changed = false
        for i in alerts.indices {
            guard !alerts[i].isTriggered, alerts[i].instrument == instrument.rawValue else { continue }
            let hit = alerts[i].isAbove ? (currentPrice >= alerts[i].targetPrice) : (currentPrice <= alerts[i].targetPrice)
            if hit {
                alerts[i].isTriggered = true
                triggeredAlertBanner = alerts[i]
                NSSound.beep()
                changed = true
            }
        }
        if changed { PersistenceStore.saveAlerts(alerts) }
    }

    // MARK: - Market Loading (LIVE + SAMPLE)

    func reloadMarket() {
        loadTask?.cancel()
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

        if dataMode == .sample {
            liveFeedState = .idle
            allCandles = SampleMarketEngine.generateCandles(
                instrument: instrument,
                timeframe: timeframe,
                count: 260
            )
            replayIndex = max(60, allCandles.count - 55)
            recomputeIndicators()
            return
        }

        let selectedInstrument = instrument
        let selectedTimeframe = timeframe
        liveFeedState = .connecting(selectedInstrument.binanceSymbol != nil ? "Binance" : "Yahoo Finance")

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await self.liveService.fetchHistoricalCandles(
                    instrument: selectedInstrument,
                    timeframe: selectedTimeframe,
                    limit: 260
                )
                guard !Task.isCancelled,
                      self.dataMode == .live,
                      self.instrument == selectedInstrument,
                      self.timeframe == selectedTimeframe else { return }

                self.allCandles = res.candles
                self.replayIndex = max(60, res.candles.count - 55)
                self.recomputeIndicators()

                if let binSym = selectedInstrument.binanceSymbol, res.provider == "Binance" {
                    self.startLiveBinanceStream(symbol: binSym, interval: selectedTimeframe.binanceInterval)
                } else {
                    self.liveFeedState = .polling("Yahoo Live")
                    self.startYahooPolling(instrument: selectedInstrument, timeframe: selectedTimeframe)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.liveFeedState = .error("Feed unavailable (sample fallback)")
                self.allCandles = SampleMarketEngine.generateCandles(
                    instrument: selectedInstrument,
                    timeframe: selectedTimeframe,
                    count: 260
                )
                self.recomputeIndicators()
            }
        }
    }

    private func startLiveBinanceStream(symbol: String, interval: String) {
        liveService.startBinanceStream(
            symbol: symbol,
            interval: interval,
            onKline: { [weak self] ts, o, h, l, c, v in
                Task { @MainActor [weak self] in
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
                    self?.liveFeedState = status
                }
            }
        )
    }

    private func startYahooPolling(instrument: Instrument, timeframe: Timeframe) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dataMode == .live, !self.isReplayMode,
                      self.instrument == instrument, self.timeframe == timeframe else { return }
                self.marketStatus = instrument.marketStatus()
                if let res = try? await self.liveService.fetchHistoricalCandles(
                    instrument: instrument,
                    timeframe: timeframe,
                    limit: 260
                ), !res.candles.isEmpty {
                    self.allCandles = res.candles
                    self.recomputeIndicators()
                    self.evaluateAlerts(currentPrice: self.lastPrice)
                }
            }
        }
    }

    private func applyLiveKline(timestamp: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        guard dataMode == .live, !allCandles.isEmpty else { return }
        if let last = allCandles.last, abs(last.timestamp.timeIntervalSince(timestamp)) < 1.0 {
            allCandles[allCandles.count - 1] = Candle(
                id: last.id,
                timestamp: timestamp,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        } else if let last = allCandles.last, timestamp > last.timestamp {
            let nextId = last.id + 1
            allCandles.append(Candle(
                id: nextId,
                timestamp: timestamp,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
            if allCandles.count > 320 {
                allCandles.removeFirst(allCandles.count - 320)
                allCandles = allCandles.enumerated().map { idx, item in
                    Candle(id: idx, timestamp: item.timestamp, open: item.open, high: item.high, low: item.low, close: item.close, volume: item.volume)
                }
            }
        }
        recomputeIndicators()
        evaluateAlerts(currentPrice: close)
    }

    private func ingestOrderFlowTrade(_ trade: OrderFlowTrade) {
        orderFlowTrades.insert(trade, at: 0)
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
        PersistenceStore.saveDrawings(drawingsByInstrument)
    }

    func updateDrawing(_ updated: DrawingObject, persist: Bool = false) {
        var list = currentDrawings
        guard let idx = list.firstIndex(where: { $0.id == updated.id }) else { return }
        list[idx] = updated
        drawingsByInstrument[instrument] = list
        if persist {
            PersistenceStore.saveDrawings(drawingsByInstrument)
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
        PersistenceStore.saveDrawings(drawingsByInstrument)
    }

    func undoDrawing() {
        guard var stack = undoStackByInstrument[instrument], let previous = stack.popLast() else { return }
        undoStackByInstrument[instrument] = stack
        drawingsByInstrument[instrument] = previous
        selectedDrawingId = nil
        PersistenceStore.saveDrawings(drawingsByInstrument)
    }

    func clearDrawings() {
        guard !currentDrawings.isEmpty else { return }
        pushDrawingUndoSnapshot()
        drawingsByInstrument[instrument] = []
        selectedDrawingId = nil
        PersistenceStore.saveDrawings(drawingsByInstrument)
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

    // MARK: - Sample Mode Tick Simulation

    private func startSampleTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySampleTick()
            }
        }
    }

    private func applySampleTick() {
        let status = instrument.marketStatus()
        if status != marketStatus { marketStatus = status }

        guard dataMode == .sample, isReceivingTicks, !allCandles.isEmpty else { return }
        var last = allCandles[allCandles.count - 1]
        let step = instrument.volatility * timeframe.volatilityScale * 0.12
        let delta = liveRNG.nextGaussian() * step
        let nextClose = max(last.close + delta, instrument.pipSize * 10)
        last.close = nextClose
        last.high = max(last.high, nextClose)
        last.low = min(last.low, nextClose)
        let volAdd = 18.0 + liveRNG.nextUnit() * 45.0
        last.volume += volAdd
        allCandles[allCandles.count - 1] = last

        let simTrade = OrderFlowTrade(
            id: UUID(),
            timestamp: Date(),
            price: nextClose,
            quantity: volAdd / 10.0,
            usdValue: volAdd * 25.0,
            isBuyerAggressor: delta >= 0
        )
        ingestOrderFlowTrade(simTrade)
        recomputeIndicators()
        evaluateAlerts(currentPrice: nextClose)
    }

    // MARK: - Paper Orders & Auto-Journal Logging

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

    func closeSamplePosition(id: UUID) {
        guard let idx = samplePositions.firstIndex(where: { $0.id == id }) else { return }
        let pos = samplePositions[idx]
        let exitPrice = (pos.instrument == instrument) ? lastPrice : pos.instrument.basePrice
        let pnl = pos.floatingPnL(currentPrice: exitPrice)
        sampleBalance += pnl

        let riskPips = pos.stopLoss.map { abs(pos.entryPrice - $0) / pos.instrument.pipSize } ?? max(orderStopPips, 10.0)
        let riskUSD = max(1.0, riskPips * pos.lots * pos.instrument.dollarPerPipPerLot)
        let entry = JournalEntry(
            instrument: pos.instrument.rawValue,
            timeframe: timeframe.rawValue,
            isBuy: pos.isBuy,
            entryPrice: pos.entryPrice,
            exitPrice: exitPrice,
            lots: pos.lots,
            pnlUSD: pnl,
            rMultiple: pnl / riskUSD,
            setupTag: "OB Retest",
            disciplineTag: "Followed Plan",
            notes: "Closed from \(dataMode.rawValue) terminal",
            isLiveAccount: false
        )
        addJournalEntry(entry)
        samplePositions.remove(at: idx)
    }

    func closeAllSamplePositions() {
        let ids = samplePositions.map(\.id)
        for id in ids { closeSamplePosition(id: id) }
    }

    func addJournalEntry(_ entry: JournalEntry) {
        journalEntries.insert(entry, at: 0)
        PersistenceStore.saveJournal(journalEntries)
    }

    func deleteJournalEntry(id: UUID) {
        journalEntries.removeAll { $0.id == id }
        PersistenceStore.saveJournal(journalEntries)
    }
}
