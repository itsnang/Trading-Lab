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

            HStack(spacing: 10) {
                // Custom macOS traffic lights
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
                .onHover { isHoveringControls = $0 }

                // Compact Brand Badge
                HStack(spacing: 5) {
                    MSNRLogoMark(isDark: t.isDark, showSacredGrid: false)
                        .frame(width: 18, height: 18)
                    Text("MSNR")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .tracking(1.4)
                        .foregroundStyle(t.primaryText)
                }
                .padding(.leading, 6)
                .padding(.trailing, 2)

                // Instrument Selector
                Menu {
                    Section("24/7 Live WebSocket + Order Flow (Binance)") {
                        ForEach([Instrument.paxg, .btcusd, .ethusd]) { inst in
                            instrumentMenuButton(inst)
                        }
                    }
                    Section("FX, Gold Futures & Indices (Yahoo Finance)") {
                        ForEach([Instrument.xauusd, .eurusd, .us30, .nas100]) { inst in
                            instrumentMenuButton(inst)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(store.instrument.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(t.primaryText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(t.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: 0.8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Timeframe Pills
                HStack(spacing: 2) {
                    ForEach(Timeframe.allCases) { tf in
                        let selected = store.timeframe == tf
                        Button {
                            store.timeframe = tf
                        } label: {
                            Text(tf.rawValue)
                                .font(.system(size: 11, weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? .white : t.secondaryText)
                                .padding(.horizontal, 7.5)
                                .padding(.vertical, 4)
                                .background(selected ? t.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))

                // Prominent Indicators Library Button (matching screenshot workflow!)
                Button {
                    store.showIndicatorLibrary = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Indicators")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(store.activeStudies.count)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(t.accent.opacity(0.16), in: Capsule())
                    }
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(t.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.accent.opacity(0.25), lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                // Bar Replay Button
                Button {
                    store.toggleReplayMode()
                } label: {
                    Label(store.isReplayMode ? "Replay On" : "Replay", systemImage: "gobackward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(store.isReplayMode ? .white : t.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(store.isReplayMode ? t.amber : t.softSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: store.isReplayMode ? 0 : 0.8))
                }
                .buttonStyle(.plain)

                // Live Quote
                HStack(spacing: 6) {
                    Text(store.instrument.formatPrice(store.lastPrice))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.primaryText)
                    let pct = store.priceChangePercent
                    Text(String(format: "%+.2f%%", pct))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(pct >= 0 ? t.bull : t.bear)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                // Feed / Session Status
                feedStatusPill(theme: t)

                // Optional Trade & Order Flow Drawer Toggle
                if store.activeSection == .terminal {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            store.showTradeDrawer.toggle()
                        }
                    } label: {
                        Label("Trade", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(store.showTradeDrawer ? .white : t.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5.5)
                            .background(store.showTradeDrawer ? t.accent : t.softSurface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: store.showTradeDrawer ? 0 : 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Paper Order Ticket, Risk Calculator & Order Flow Tape")
                }

                // Light / Dark Mode Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.isDarkTheme.toggle()
                    }
                } label: {
                    Image(systemName: store.isDarkTheme ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(t.softSurface, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(store.isDarkTheme ? "Switch to Clean Light Theme" : "Switch to Dark Theme")

                // LIVE | SAMPLE Switcher
                HStack(spacing: 2) {
                    ForEach(DataSourceMode.allCases) { mode in
                        let selected = store.dataMode == mode
                        Button {
                            store.dataMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected ? .white : t.secondaryText)
                                .padding(.horizontal, 8.5)
                                .padding(.vertical, 4)
                                .background(
                                    selected ? (mode == .live ? t.bull : t.amber) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(t.softSurface, in: Capsule())
                .overlay(Capsule().stroke(t.border, lineWidth: 0.8))
                .padding(.trailing, 14)
            }
        }
        .frame(height: 48)
        .background(t.chromeBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
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
        if store.dataMode == .live {
            Button { store.reloadMarket() } label: {
                HStack(spacing: 5) {
                    switch store.liveFeedState {
                    case .streaming(let src):
                        Circle().fill(t.bull).frame(width: 7, height: 7)
                        Text("\(src) · Live").foregroundStyle(t.bull)
                    case .polling(let src):
                        Circle().fill(store.marketStatus.isOpen ? t.bull : t.bear).frame(width: 7, height: 7)
                        Text(store.marketStatus.isOpen ? "\(src) · \(store.marketStatus.sessionLabel)" : "Closed · \(store.marketStatus.detailText)")
                            .foregroundStyle(store.marketStatus.isOpen ? t.primaryText : t.bear)
                    case .connecting(let src):
                        Circle().fill(t.amber).frame(width: 7, height: 7)
                        Text("Connecting \(src)...").foregroundStyle(t.amber)
                    case .error:
                        Circle().fill(t.amber).frame(width: 7, height: 7)
                        Text("Retry Feed").foregroundStyle(t.amber)
                    case .idle:
                        Circle().fill(t.secondaryText).frame(width: 7, height: 7)
                        Text("Idle").foregroundStyle(t.secondaryText)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                if !store.marketStatus.isOpen { store.allowClosedMarketSim.toggle() }
                else { store.liveTickSimulation.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isReceivingTicks ? t.bull : (!store.marketStatus.isOpen ? t.bear : t.secondaryText))
                        .frame(width: 7, height: 7)
                    if !store.marketStatus.isOpen && !store.allowClosedMarketSim {
                        Text("Closed · \(store.marketStatus.detailText)").foregroundStyle(t.bear)
                    } else if !store.marketStatus.isOpen && store.allowClosedMarketSim {
                        Text("Weekend Sim").foregroundStyle(t.amber)
                    } else {
                        Text(store.liveTickSimulation ? "\(store.marketStatus.sessionLabel) · Sim" : "Paused").foregroundStyle(t.primaryText)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
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
                Circle().fill(color).frame(width: 12, height: 12)
                if hover {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
