import Foundation

/// Injectable market data seam allowing WorkspaceStore to run against live Binance/Yahoo
/// feeds in production or deterministic in-memory fakes in automated tests.
protocol MarketDataAdapter: AnyObject {
    func fetchHistoricalCandles(
        instrument: Instrument,
        timeframe: Timeframe,
        limit: Int,
        endTime: Date?
    ) async throws -> (candles: [Candle], provider: String)

    func fetchLiveTailCandles(
        instrument: Instrument,
        timeframe: Timeframe
    ) async throws -> [Candle]

    func startBinanceStream(
        symbol: String,
        interval: String,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void,
        onStatus: @escaping @Sendable (LiveFeedState) -> Void
    )

    func disconnectStream()
}

/// Injectable local persistence seam so tests never touch ~/Library/Application Support/TradingLab.
protocol PersistenceAdapter {
    func loadPrefs() -> WorkspacePrefs?
    func savePrefs(_ prefs: WorkspacePrefs)
    func loadDrawings() -> [Instrument: [DrawingObject]]
    func saveDrawings(_ map: [Instrument: [DrawingObject]])
    func loadJournal() -> [JournalEntry]
    func saveJournal(_ entries: [JournalEntry])
    func loadAlerts() -> [PriceAlert]
    func saveAlerts(_ alerts: [PriceAlert])
}

struct DiskPersistenceAdapter: PersistenceAdapter {
    func loadPrefs() -> WorkspacePrefs? { PersistenceStore.loadPrefs() }
    func savePrefs(_ prefs: WorkspacePrefs) { PersistenceStore.savePrefs(prefs) }
    func loadDrawings() -> [Instrument: [DrawingObject]] { PersistenceStore.loadDrawings() }
    func saveDrawings(_ map: [Instrument: [DrawingObject]]) { PersistenceStore.saveDrawings(map) }
    func loadJournal() -> [JournalEntry] { PersistenceStore.loadJournal() }
    func saveJournal(_ entries: [JournalEntry]) { PersistenceStore.saveJournal(entries) }
    func loadAlerts() -> [PriceAlert] { PersistenceStore.loadAlerts() }
    func saveAlerts(_ alerts: [PriceAlert]) { PersistenceStore.saveAlerts(alerts) }
}
