import SwiftUI

struct ChartReplayBar: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        HStack(spacing: 12) {
            Label("BAR REPLAY", systemImage: "gobackward")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(t.amber)

            Button { store.stepReplayBackward() } label: {
                Image(systemName: "backward.frame.fill").foregroundStyle(t.primaryText)
            }
            .buttonStyle(.plain)

            Button { store.toggleReplayPlay() } label: {
                Image(systemName: store.isReplayPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 24)
                    .background(t.accent, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button { store.stepReplayForward() } label: {
                Image(systemName: "forward.frame.fill").foregroundStyle(t.primaryText)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { Double(store.replayIndex) },
                    set: {
                        store.replayIndex = Int($0)
                        store.recomputeIndicators()
                    }
                ),
                in: 35...Double(max(36, store.allCandles.count))
            )
            .frame(width: 170)

            Text("\(store.replayIndex)/\(store.allCandles.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(t.secondaryText)

            Menu {
                ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { spd in
                    Button("\(Int(spd))x / sec") { store.setReplaySpeed(spd) }
                }
            } label: {
                Text("\(Int(store.replaySpeed))x")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(t.softSurface, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Exit") {
                store.toggleReplayMode()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(t.bear)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(t.bear.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(t.cardBg.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(t.isDark ? 0.4 : 0.12), radius: 12, y: 4)
    }
}
