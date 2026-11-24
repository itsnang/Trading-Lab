import SwiftUI

struct DrawingToolbar: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(DrawingTool.allCases) { tool in
                        let selected = store.activeTool == tool
                        Button {
                            store.activeTool = tool
                        } label: {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                                .frame(width: 30, height: 28)
                                .foregroundStyle(selected ? t.accent : t.secondaryText)
                                .background(
                                    selected ? t.accent.opacity(t.isDark ? 0.14 : 0.11) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: t.radiusSharp)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: t.radiusSharp)
                                        .stroke(selected ? t.accent.opacity(0.45) : Color.clear, lineWidth: 0.75)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(tool.rawValue)
                    }

                    railDivider(theme: t)

                    // Magnet Mode (OHLC candle snap)
                    Button {
                        store.magnetEnabled.toggle()
                    } label: {
                        Image(systemName: "magnet")
                            .font(.system(size: 12.5, weight: store.magnetEnabled ? .semibold : .regular))
                            .frame(width: 30, height: 28)
                            .foregroundStyle(store.magnetEnabled ? t.accent : t.secondaryText)
                            .background(
                                store.magnetEnabled ? t.accent.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: t.radiusSharp)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: t.radiusSharp)
                                    .stroke(store.magnetEnabled ? t.accent.opacity(0.45) : Color.clear, lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(store.magnetEnabled ? "Magnet Mode ON (snaps drawings to candle OHLC)" : "Magnet Mode OFF (click to snap drawings to candles)")

                    VStack(spacing: 6) {
                        ForEach(DrawingColorPreset.presets) { preset in
                            let selected = store.activeColorPresetId == preset.id
                            Button {
                                store.activeColorPresetId = preset.id
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 11, height: 11)
                                    .overlay(
                                        Circle()
                                            .stroke(t.primaryText, lineWidth: selected ? 1.5 : 0)
                                            .padding(-2.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Color: \(preset.name)")
                        }
                    }
                    .padding(.vertical, 6)

                    railDivider(theme: t)

                    ToolIconButton(symbol: "plus.magnifyingglass", helpText: "Zoom In", theme: t) {
                        store.zoom(factor: 0.8)
                    }
                    ToolIconButton(symbol: "minus.magnifyingglass", helpText: "Zoom Out", theme: t) {
                        store.zoom(factor: 1.25)
                    }
                    ToolIconButton(symbol: "arrow.counterclockwise", helpText: "Reset Chart View (⌥R)", theme: t) {
                        store.resetCamera()
                    }

                    railDivider(theme: t)

                    ToolIconButton(symbol: "arrow.uturn.backward", helpText: "Undo Last Drawing (⌘Z)", theme: t) {
                        store.undoDrawing()
                    }
                    ToolIconButton(symbol: "trash", helpText: "Clear Drawings (\(store.currentDrawings.count))", theme: t, tint: t.bear.opacity(0.85)) {
                        store.clearDrawings()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 42)
        .background(t.chromeBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }

    private func railDivider(theme t: AppTheme) -> some View {
        Rectangle()
            .fill(t.border)
            .frame(width: 22, height: 1)
            .padding(.vertical, 5)
    }
}

private struct ToolIconButton: View {
    let symbol: String
    let helpText: String
    let theme: AppTheme
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 30, height: 26)
                .foregroundStyle(tint ?? (isHovered ? theme.primaryText : theme.secondaryText))
                .background(
                    isHovered ? theme.softSurface : Color.clear,
                    in: RoundedRectangle(cornerRadius: theme.radiusSharp)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}
