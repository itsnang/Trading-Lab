import SwiftUI

/// TradingView-style slim far-right icon dock (`40pt` wide).
/// Click any icon to open that panel; click the active icon again to collapse for a 100% full-width chart.
struct RightIconDock: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(spacing: 4) {
            ForEach(RightDockTab.allCases) { tab in
                let active = store.activeRightDockTab == tab
                let badgeCount = badge(for: tab)
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        store.toggleRightDockTab(tab)
                    }
                } label: {
                    ZStack(alignment: .trailing) {
                        if active {
                            Rectangle()
                                .fill(t.accent)
                                .frame(width: 2.5, height: 22)
                        }
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13.5, weight: active ? .semibold : .regular))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(active ? t.accent : t.secondaryText)
                                .background(
                                    active ? t.accent.opacity(t.isDark ? 0.14 : 0.10) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: t.radiusSharp)
                                )
                            if badgeCount > 0 {
                                Text("\(min(badgeCount, 99))")
                                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                    .foregroundStyle(t.isDark ? .black : .white)
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1)
                                    .background(t.accent, in: Capsule())
                                    .offset(x: 3, y: -2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .help("\(tab.rawValue) (click to toggle)")
            }

            Spacer()

            // Quick Bottom Tray toggle shortcut at bottom of far-right dock
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    store.toggleBottomTrayTab(store.activeBottomTrayTab ?? .tradingPanel)
                }
            } label: {
                Image(systemName: store.activeBottomTrayTab == nil ? "rectangle.bottomthird.inset.filled" : "chevron.down.square")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(store.activeBottomTrayTab != nil ? t.accent : t.secondaryText)
            }
            .buttonStyle(.plain)
            .help(store.activeBottomTrayTab == nil ? "Open Bottom Trading Panel" : "Collapse Bottom Panel")
            .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .frame(width: 40)
        .background(t.sidebarBg)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }

    private func badge(for tab: RightDockTab) -> Int {
        switch tab {
        case .watchlist: return 0
        case .orderTicket: return store.samplePositions.count + store.paperPendingOrders.count
        case .orderFlow: return 0
        case .alerts: return store.alerts.filter { !$0.isTriggered }.count + store.recentSignalAlerts.count
        case .drawings: return store.currentDrawings.count
        }
    }
}
