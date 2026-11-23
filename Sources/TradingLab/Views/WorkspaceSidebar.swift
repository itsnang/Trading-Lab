import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(spacing: 8) {
            // MSNR Desk Brand Logo
            VStack(spacing: 3) {
                MSNRLogoMark(isDark: t.isDark, showSacredGrid: true)
                    .frame(width: 34, height: 34)
                Text("MSNR")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .tracking(1.6)
                    .foregroundStyle(t.primaryText)
                Text("DESK")
                    .font(.system(size: 6.5, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color(red: 200 / 255, green: 152 / 255, blue: 60 / 255))
            }
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
                .frame(width: 40)
                .overlay(t.border)
                .padding(.bottom, 4)

            ForEach(WorkspaceSection.allCases) { section in
                let isSelected = store.activeSection == section
                Button {
                    store.activeSection = section
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 15.5, weight: isSelected ? .semibold : .regular))
                        Text(section.rawValue)
                            .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .frame(width: 60, height: 48)
                    .foregroundStyle(isSelected ? t.accent : t.secondaryText)
                    .background(
                        isSelected ? t.accent.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("EQUITY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.secondaryText)
                Text(String(format: "$%.0f", store.sampleEquity))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.floatingPnL >= 0 ? t.bull : t.bear)
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .frame(width: 72)
        .background(t.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }
}
