import SwiftUI

struct DrawingToolbar: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(DrawingTool.allCases) { tool in
                        let selected = store.activeTool == tool
                        Button {
                            store.activeTool = tool
                        } label: {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                                .frame(width: 34, height: 32)
                                .foregroundStyle(selected ? .white : t.secondaryText)
                                .background(
                                    selected ? t.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(tool.rawValue)
                    }

                    Divider()
                        .overlay(t.border)
                        .padding(.vertical, 4)

                    // Magnet Mode (OHLC candle snap — just like TradingView!)
                    Button {
                        store.magnetEnabled.toggle()
                    } label: {
                        Image(systemName: "magnet")
                            .font(.system(size: 13.5, weight: store.magnetEnabled ? .bold : .medium))
                            .frame(width: 34, height: 30)
                            .foregroundStyle(store.magnetEnabled ? .white : t.secondaryText)
                            .background(
                                store.magnetEnabled ? t.accent : t.softSurface,
                                in: RoundedRectangle(cornerRadius: 7)
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
                                    .frame(width: 13, height: 13)
                                    .overlay(
                                        Circle()
                                            .stroke(t.primaryText, lineWidth: selected ? 2 : 0)
                                            .padding(-2.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Color: \(preset.name)")
                        }
                    }
                    .padding(.vertical, 4)

                    Divider()
                        .overlay(t.border)
                        .padding(.vertical, 4)

                    ToolIconButton(symbol: "plus.magnifyingglass", helpText: "Zoom In", theme: t) {
                        store.zoom(factor: 0.8)
                    }
                    ToolIconButton(symbol: "minus.magnifyingglass", helpText: "Zoom Out", theme: t) {
                        store.zoom(factor: 1.25)
                    }
                    ToolIconButton(symbol: "arrow.counterclockwise", helpText: "Reset Chart View", theme: t) {
                        store.resetCamera()
                    }

                    Divider()
                        .overlay(t.border)
                        .padding(.vertical, 4)

                    ToolIconButton(symbol: "arrow.uturn.backward", helpText: "Undo Last Drawing", theme: t) {
                        store.undoDrawing()
                    }
                    ToolIconButton(symbol: "trash", helpText: "Clear Drawings (\(store.currentDrawings.count))", theme: t, tint: t.bear) {
                        store.clearDrawings()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 48)
        .background(t.chromeBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }
}

private struct ToolIconButton: View {
    let symbol: String
    let helpText: String
    let theme: AppTheme
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 30)
                .foregroundStyle(tint ?? theme.secondaryText)
                .background(theme.softSurface, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
