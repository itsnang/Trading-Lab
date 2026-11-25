import SwiftUI
import AppKit

/// TradingView-style collapsible & resizable Bottom Tray (`Trading Panel | Strategy Tester | Journal | Bot Studio`).
/// Always shows a sleek `32pt` status & tab bar at the bottom of the chart; click any tab to expand below the candles.
struct BottomTrayView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var dragStartHeight: CGFloat? = nil

    var body: some View {
        let t = store.theme

        VStack(spacing: 0) {
            // Draggable top resize border when expanded (and not maximized)
            if store.activeBottomTrayTab != nil && !store.isBottomTrayMaximized {
                Rectangle()
                    .fill(t.border)
                    .frame(height: 1)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 7)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if dragStartHeight == nil { dragStartHeight = store.bottomTrayHeight }
                                        let base = dragStartHeight ?? store.bottomTrayHeight
                                        store.bottomTrayHeight = max(150.0, min(560.0, base - value.translation.height))
                                    }
                                    .onEnded { _ in dragStartHeight = nil }
                            )
                    )
            } else {
                Rectangle().fill(t.border).frame(height: 1)
            }

            // Always-visible 32pt TradingView Bottom Tab Bar
            HStack(spacing: 2) {
                ForEach(BottomTrayTab.allCases) { tab in
                    let active = store.activeBottomTrayTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            store.toggleBottomTrayTab(tab)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: active ? .bold : .medium))
                            if tab == .tradingPanel && (store.samplePositions.count + store.paperPendingOrders.count) > 0 {
                                Text("\(store.samplePositions.count + store.paperPendingOrders.count)")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(t.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(t.accent)
                            }
                        }
                        .foregroundStyle(active ? t.accent : t.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .overlay(alignment: .top) {
                            if active {
                                Rectangle().fill(t.accent).frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Live Account Equity & Floating PnL right in the bottom bar (TradingView Paper Trading bar style)
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("EQUITY")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.secondaryText)
                        Text(String(format: "$%.2f", store.sampleEquity))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.primaryText)
                    }
                    HStack(spacing: 4) {
                        Text("PNL")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.secondaryText)
                        Text(String(format: "%@$%.2f", store.floatingPnL >= 0 ? "+" : "-", abs(store.floatingPnL)))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(store.floatingPnL >= 0 ? t.bull : t.bear)
                    }
                }
                .padding(.trailing, 8)

                // Maximize / Collapse Controls
                if store.activeBottomTrayTab != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            store.isBottomTrayMaximized.toggle()
                        }
                    } label: {
                        Image(systemName: store.isBottomTrayMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(t.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(store.isBottomTrayMaximized ? "Restore Split View" : "Maximize Bottom Panel")

                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            store.activeBottomTrayTab = nil
                            store.isBottomTrayMaximized = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(t.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Panel")
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            store.activeBottomTrayTab = .tradingPanel
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(t.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Open Trading Panel")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 31)
            .background(t.chromeBg)

            // Expanded Tray Content
            if let tab = store.activeBottomTrayTab {
                Rectangle().fill(t.border).frame(height: 1)

                Group {
                    switch tab {
                    case .tradingPanel:
                        SampleAccountView()
                    case .strategyTester:
                        BacktestView()
                    case .journal:
                        JournalView()
                    case .botStudio:
                        BotStudioView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: store.isBottomTrayMaximized ? nil : store.bottomTrayHeight)
                .frame(maxHeight: store.isBottomTrayMaximized ? .infinity : store.bottomTrayHeight)
            }
        }
    }
}
