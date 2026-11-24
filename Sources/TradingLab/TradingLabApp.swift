import SwiftUI
import AppKit

final class TradingLabAppDelegate: NSObject, NSApplicationDelegate {
    weak var storeRef: WorkspaceStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count {
            let outDir = args[idx + 1]
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.renderAllScreenshots(to: outDir)
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = img
        }
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                self.configureWindow(window)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private func renderAllScreenshots(to dirPath: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        func snapshot<V: View>(_ view: V, size: CGSize, file: String, dark: Bool) {
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(dark ? .dark : .light))
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let win = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentView = hosting
            win.appearance = hosting.appearance
            win.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.18))

            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dirPath)/\(file)"))
            }
            win.orderOut(nil)
        }

        // Fetch real live PAXG/USDT candles on a detached task so MainActor isn't blocked during CLI export
        var fetchedCandles: [Candle] = []
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            let svc = LiveMarketService()
            if let res = try? await svc.fetchHistoricalCandles(instrument: .paxg, timeframe: .m5, limit: 300, endTime: nil) {
                fetchedCandles = res.candles
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 8.0)

        let previewStore = WorkspaceStore(ephemeralPreview: true, initialCandles: fetchedCandles.isEmpty ? nil : fetchedCandles)

        // 1. Light Terminal (Market Structure 2.0 + Order Flow + Momentum Oscillator)
        previewStore.isDarkTheme = false
        previewStore.activeSection = .terminal
        previewStore.showTradeDrawer = true
        previewStore.activeStudies = [
            ActiveStudy(kind: .concept, isVisible: true),
            ActiveStudy(kind: .orderFlow, isVisible: true),
            ActiveStudy(kind: .momentumOscillator, isVisible: true)
        ]
        previewStore.recomputeIndicators()
        snapshot(ContentView().environmentObject(previewStore), size: CGSize(width: 1440, height: 900), file: "terminal-light.png", dark: false)

        // 2. Dark Terminal (Reversal & ATR Targets + Sideway Detector + Momentum Oscillator)
        previewStore.isDarkTheme = true
        previewStore.showTradeDrawer = false
        previewStore.activeStudies = [
            ActiveStudy(kind: .reversalTargets, isVisible: true),
            ActiveStudy(kind: .sidewayDetector, isVisible: true),
            ActiveStudy(kind: .momentumOscillator, isVisible: true)
        ]
        previewStore.recomputeIndicators()
        snapshot(ContentView().environmentObject(previewStore), size: CGSize(width: 1440, height: 900), file: "terminal-dark.png", dark: true)

        // 3. Indicator Library Modal (Light Theme)
        previewStore.isDarkTheme = false
        previewStore.activeStudies = [
            ActiveStudy(kind: .concept, isVisible: true),
            ActiveStudy(kind: .orderFlow, isVisible: true)
        ]
        snapshot(IndicatorLibraryView().environmentObject(previewStore), size: CGSize(width: 580, height: 660), file: "indicators-library.png", dark: false)

        // 4. Backtest Studio (Light Theme)
        previewStore.activeSection = .backtest
        snapshot(ContentView().environmentObject(previewStore), size: CGSize(width: 1440, height: 900), file: "backtest-studio.png", dark: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first {
            if window.isMiniaturized { window.deminiaturize(self) }
            window.makeKeyAndOrderFront(self)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    func configureWindow(_ window: NSWindow) {
        window.styleMask.insert([.resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.minSize = NSSize(width: 960, height: 640)
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
    }
}

public struct TradingLabApp: App {
    @NSApplicationDelegateAdaptor(TradingLabAppDelegate.self) var appDelegate
    @StateObject private var store = WorkspaceStore()

    public init() {}

    public var body: some Scene {
        WindowGroup("MSNR Desk") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.isDarkTheme ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
