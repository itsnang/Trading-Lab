import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var dragStartOscHeight: CGFloat? = nil
    @State private var dragStartDrawerWidth: CGFloat? = nil

    var body: some View {
        let t = store.theme

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                WindowChromeBar()

                HStack(spacing: 0) {
                    WorkspaceSidebar()

                    switch store.activeSection {
                    case .terminal:
                        terminalWorkspace(theme: t)
                    case .backtest:
                        BacktestView()
                    case .journal:
                        JournalView()
                    case .botStudio:
                        BotStudioView()
                    case .account:
                        SampleAccountView()
                    }
                }
            }
            .background(t.canvasBg)

            // Triggered Price Alert Banner
            if let alert = store.triggeredAlertBanner {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.white)
                    Text("Alert: \(alert.instrument) \(alert.isAbove ? "crossed above" : "crossed below") \(String(format: "%.2f", alert.targetPrice)) — \(alert.note)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Button("Dismiss") {
                        store.triggeredAlertBanner = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.22), in: Capsule())
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(t.accent, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.top, 56)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .sheet(isPresented: $store.showIndicatorLibrary) {
            IndicatorLibraryView()
                .environmentObject(store)
        }
        .sheet(item: $store.settingsStudyKind) { kind in
            StudySettingsSheet(kind: kind)
                .environmentObject(store)
        }
        .sheet(item: $store.alertStudyKind) { kind in
            CreateAlertSheet(studyTitle: kind.title)
                .environmentObject(store)
        }
    }

    private func terminalWorkspace(theme t: AppTheme) -> some View {
        HStack(spacing: 0) {
            DrawingToolbar()

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    CandlestickCanvasView()

                    if store.isStudyVisible(.momentumOscillator) {
                        // Draggable horizontal pane divider (TradingView style)
                        horizontalPaneSplitter(theme: t)
                        OscillatorPaneView()
                    }
                }

                if store.isReplayMode {
                    ChartReplayBar()
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if store.showTradeDrawer {
                // Draggable vertical drawer divider
                verticalDrawerSplitter(theme: t)
                IndicatorDrawerView()
                    .transition(.move(edge: .trailing))
            }
        }
    }

    private func horizontalPaneSplitter(theme t: AppTheme) -> some View {
        ZStack {
            Rectangle().fill(t.border).frame(height: 1)
            Capsule()
                .fill(t.secondaryText.opacity(0.35))
                .frame(width: 36, height: 3)
        }
        .frame(height: 7)
        .frame(maxWidth: .infinity)
        .background(t.chartBg)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartOscHeight == nil { dragStartOscHeight = store.oscillatorHeight }
                    let base = dragStartOscHeight ?? store.oscillatorHeight
                    store.oscillatorHeight = max(72, min(420, base - value.translation.height))
                }
                .onEnded { _ in
                    dragStartOscHeight = nil
                }
        )
    }

    private func verticalDrawerSplitter(theme t: AppTheme) -> some View {
        ZStack {
            Rectangle().fill(t.border).frame(width: 1)
            Capsule()
                .fill(t.secondaryText.opacity(0.35))
                .frame(width: 3, height: 32)
        }
        .frame(width: 7)
        .frame(maxHeight: .infinity)
        .background(t.canvasBg)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartDrawerWidth == nil { dragStartDrawerWidth = store.tradeDrawerWidth }
                    let base = dragStartDrawerWidth ?? store.tradeDrawerWidth
                    store.tradeDrawerWidth = max(240, min(460, base - value.translation.width))
                }
                .onEnded { _ in
                    dragStartDrawerWidth = nil
                }
        )
    }
}
