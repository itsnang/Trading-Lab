import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(spacing: 4) {
            // MSNR Desk Architectural Emblem
            VStack(spacing: 3) {
                MSNRLogoMark(isDark: t.isDark, showSacredGrid: true)
                    .frame(width: 30, height: 30)
                Text("MSNR")
                    .font(.system(size: 8.5, weight: .bold, design: .serif))
                    .tracking(2.0)
                    .foregroundStyle(t.primaryText)
                Text("DESK")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(t.accent)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Rectangle()
                .fill(t.border)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            ForEach(WorkspaceSection.allCases) { section in
                let isSelected = store.activeSection == section
                Button {
                    store.activeSection = section
                } label: {
                    ZStack(alignment: .leading) {
                        if isSelected {
                            Rectangle()
                                .fill(t.accent)
                                .frame(width: 2.5, height: 26)
                        }
                        VStack(spacing: 4) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 14.5, weight: isSelected ? .semibold : .regular))
                            Text(section.rawValue)
                                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(isSelected ? t.primaryText : t.secondaryText)
                        .background(
                            isSelected ? t.accent.opacity(t.isDark ? 0.12 : 0.10) : Color.clear,
                            in: RoundedRectangle(cornerRadius: t.radiusControl)
                        )
                        .padding(.horizontal, 6)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Rectangle()
                .fill(t.border)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                Text("EQUITY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(t.secondaryText)
                Text(String(format: "$%.0f", store.sampleEquity))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.floatingPnL >= 0 ? t.bull : t.bear)
            }
            .padding(.bottom, 12)
        }
        .frame(width: 66)
        .background(t.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }
}
