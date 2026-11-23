import SwiftUI
import AppKit

final class TradingLabAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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

@main
struct TradingLabApp: App {
    @NSApplicationDelegateAdaptor(TradingLabAppDelegate.self) var appDelegate
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup("Trading Lab") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.isDarkTheme ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
