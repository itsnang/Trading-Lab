import SwiftUI
import AppKit

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableWindowView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableWindowView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

struct WindowChromeBar: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var isHoveringControls = false

    var body: some View {
        let t = store.theme

        ZStack {
            WindowDragRegion()

            HStack(spacing: 8) {
                // Native-style macOS window controls
                HStack(spacing: 7) {
                    CaptionDot(color: Color(red: 0.99, green: 0.37, blue: 0.34), symbol: "xmark", hover: isHoveringControls) {
                        NSApp.keyWindow?.performClose(nil)
                    }
                    CaptionDot(color: Color(red: 0.99, green: 0.74, blue: 0.18), symbol: "minus", hover: isHoveringControls) {
                        NSApp.keyWindow?.miniaturize(nil)
                    }
                    CaptionDot(color: Color(red: 0.16, green: 0.79, blue: 0.25), symbol: "plus", hover: isHoveringControls) {
                        NSApp.keyWindow?.zoom(nil)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .onHover { isHoveringControls = $0 }

                toolbarDivider(theme: t)

                // Instrument Selector
                Menu {
                    Section("Real-Time WebSocket + Order Flow") {
                        ForEach([Instrument.xauusd, .paxg, .btcusd, .ethusd]) { inst in
                            instrumentMenuButton(inst)
                        }
                    }
                    Section("FX & US Indices") {
                        ForEach([Instrument.eurusd, .us30, .nas100]) { inst in
                            instrumentMenuButton(inst)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(store.instrument.rawValue)
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.primaryText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(t.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(t.softSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: t.radiusControl))
                    .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.border, lineWidth: 0.75))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                toolbarDivider(theme: t)

                // Sharp Timeframe Strip (1..7 hotkeys)
                HStack(spacing: 1) {
                    ForEach(Timeframe.allCases) { tf in
                        let selected = store.timeframe == tf
                        Button {
                            store.timeframe = tf
                        } label: {
                            Text(tf.rawValue)
                                .font(.system(size: 11, weight: selected ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(selected ? (t.isDark ? Color.black : .white) : t.secondaryText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    selected ? t.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: t.radiusSharp)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(t.softSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: t.radiusControl))

                toolbarDivider(theme: t)

                // Study Suites Library Trigger
                Button {
                    store.showIndicatorLibrary = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Studies")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("\(store.activeStudies.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(t.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(t.accent.opacity(t.isDark ? 0.11 : 0.08), in: RoundedRectangle(cornerRadius: t.radiusControl))
                    .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.accent.opacity(0.28), lineWidth: 0.75))
                }
                .buttonStyle(.plain)

                // Bar Replay Trigger
                Button {
                    store.toggleReplayMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gobackward")
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.isReplayMode ? "Replay On" : "Replay")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(store.isReplayMode ? (t.isDark ? .black : .white) : t.primaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        store.isReplayMode ? t.amber : Color.clear,
                        in: RoundedRectangle(cornerRadius: t.radiusControl)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: t.radiusControl)
                            .stroke(store.isReplayMode ? Color.clear : t.border, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)

                toolbarDivider(theme: t)

                // Live Price Telemetry
                HStack(spacing: 7) {
                    Text(store.instrument.formatPrice(store.lastPrice))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.primaryText)
                    let pct = store.priceChangePercent
                    Text(String(format: "%+.2f%%", pct))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(pct >= 0 ? t.bull : t.bear)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((pct >= 0 ? t.bull : t.bear).opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                // Live Feed Status
                feedStatusPill(theme: t)

                // Execution & Alerts Drawer Toggle
                if store.activeSection == .terminal {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            store.showTradeDrawer.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Desk")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(store.showTradeDrawer ? (t.isDark ? .black : .white) : t.primaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            store.showTradeDrawer ? t.accent : t.softSurface.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: t.radiusControl)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: t.radiusControl)
                                .stroke(store.showTradeDrawer ? Color.clear : t.border, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Paper Desk Order Ticket, Order Flow Tape & Signal Alerts")
                }

                // Light / Dark Mode Switch
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.isDarkTheme.toggle()
                    }
                } label: {
                    Image(systemName: store.isDarkTheme ? "sun.max" : "moon")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.secondaryText)
                        .frame(width: 28, height: 26)
                        .background(t.softSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: t.radiusControl))
                        .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.border, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help(store.isDarkTheme ? "Switch to Alabaster Light Theme" : "Switch to Obsidian Dark Theme")
                .padding(.trailing, 12)
            }
        }
        .frame(height: 44)
        .background(t.chromeBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }

    private func toolbarDivider(theme t: AppTheme) -> some View {
        Rectangle()
            .fill(t.border)
            .frame(width: 1, height: 16)
    }

    @ViewBuilder
    private func instrumentMenuButton(_ inst: Instrument) -> some View {
        Button {
            store.instrument = inst
        } label: {
            HStack {
                Text("\(inst.rawValue) — \(inst.displayName)")
                if inst == store.instrument {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    @ViewBuilder
    private func feedStatusPill(theme t: AppTheme) -> some View {
        Button { store.reloadMarket() } label: {
            HStack(spacing: 5) {
                switch store.liveFeedState {
                case .streaming(let src):
                    Circle().fill(t.bull).frame(width: 6, height: 6)
                    Text("\(src) · Live").foregroundStyle(t.bull)
                case .polling(let src):
                    Circle().fill(store.marketStatus.isOpen ? t.bull : t.bear).frame(width: 6, height: 6)
                    Text(store.marketStatus.isOpen ? "\(src) · \(store.marketStatus.sessionLabel)" : "Closed · \(store.marketStatus.detailText)")
                        .foregroundStyle(store.marketStatus.isOpen ? t.primaryText : t.bear)
                case .connecting(let src):
                    Circle().fill(t.amber).frame(width: 6, height: 6)
                    Text("Connecting \(src)...").foregroundStyle(t.amber)
                case .error:
                    Circle().fill(t.amber).frame(width: 6, height: 6)
                    Text("Retry Feed").foregroundStyle(t.amber)
                case .idle:
                    Circle().fill(t.secondaryText).frame(width: 6, height: 6)
                    Text("Standby").foregroundStyle(t.secondaryText)
                }
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(t.softSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: t.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.border, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help("Click to reload live market feed")
    }
}

private struct CaptionDot: View {
    let color: Color
    let symbol: String
    let hover: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 11.5, height: 11.5)
                if hover {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
