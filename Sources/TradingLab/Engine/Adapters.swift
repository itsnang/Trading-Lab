import Foundation
import UserNotifications

/// Injectable macOS notification seam so tests can assert notification delivery
/// without invoking UNUserNotificationCenter outside an .app bundle.
protocol NotificationAdapter: AnyObject {
    func requestAuthorizationIfNeeded()
    func deliver(title: String, body: String, sound: Bool)
}

final class MacOSNotificationAdapter: NotificationAdapter {
    private var didRequestAuth = false

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorizationIfNeeded() {
        guard isAppBundle, !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func deliver(title: String, body: String, sound: Bool) {
        guard isAppBundle else { return }
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

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

    func fetchLiveSpotQuote(
        instrument: Instrument
    ) async throws -> (price: Double, timestamp: Date)?

    func startBinanceStream(
        symbol: String,
        interval: String,
        onKline: @escaping @Sendable (Date, Double, Double, Double, Double, Double) -> Void,
        onTrade: @escaping @Sendable (OrderFlowTrade) -> Void,
        onStatus: @escaping @Sendable (LiveFeedState) -> Void
    )

    func disconnectStream()
}

extension MarketDataAdapter {
    func fetchLiveSpotQuote(instrument: Instrument) async throws -> (price: Double, timestamp: Date)? {
        nil
    }
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
