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

                // TradingView-Style Edge-to-Edge Shell:
                // [42pt Drawing Rail] | [Chart + Optional Oscillator + Collapsible Bottom Tray] | [Optional Focused Right Panel] | [40pt Right Icon Dock]
                HStack(spacing: 0) {
                    DrawingToolbar()

                    VStack(spacing: 0) {
                        if !store.isBottomTrayMaximized || store.activeBottomTrayTab == nil {
                            ZStack(alignment: .bottom) {
                                VStack(spacing: 0) {
                                    CandlestickCanvasView()

                                    if store.isStudyVisible(.momentumOscillator) {
                                        horizontalPaneSplitter(theme: t)
                                        OscillatorPaneView()
                                    }
                                }

                                if store.isReplayMode {
                                    ChartReplayBar()
                                        .padding(.bottom, 12)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        BottomTrayView()
                    }

                    if store.activeRightDockTab != nil {
                        verticalDrawerSplitter(theme: t)
                        IndicatorDrawerView()
                            .transition(.move(edge: .trailing))
                    }

                    RightIconDock()
                }
            }
            .background(t.canvasBg)

            // Triggered Price / Study Signal Alert Toast
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
                .padding(.top, 52)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let sig = store.triggeredSignalBanner {
                HStack(spacing: 10) {
                    Image(systemName: sig.category == "Zone Touch" ? "scope" : "bolt.fill")
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sig.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                        Text(sig.body)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    if sig.suggestedSL != nil && sig.suggestedTP != nil {
                        Button("Apply SL/TP") {
                            store.applySignalTargetsToOrderTicket(sig)
                            store.triggeredSignalBanner = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(sig.isBullish ? t.bull : t.bear)
                    }
                    Button("Dismiss") {
                        store.triggeredSignalBanner = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.22), in: Capsule())
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(sig.category == "Zone Touch" ? t.amber : (sig.isBullish ? t.bull : t.bear), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.top, 52)
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
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartOscHeight == nil {
                        dragStartOscHeight = store.oscillatorHeight
                    }
                    let base = dragStartOscHeight ?? store.oscillatorHeight
                    store.oscillatorHeight = max(72.0, min(420.0, base - value.translation.height))
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
                .frame(width: 3, height: 36)
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
        .background(t.canvasBg)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartDrawerWidth == nil {
                        dragStartDrawerWidth = store.tradeDrawerWidth
                    }
                    let base = dragStartDrawerWidth ?? store.tradeDrawerWidth
                    store.tradeDrawerWidth = max(230.0, min(460.0, base - value.translation.width))
                }
                .onEnded { _ in
                    dragStartDrawerWidth = nil
                }
        )
    }
}
