import SwiftUI

#if os(iOS)
struct CoorditLiquidGlassBottomNavigation: View {
    let selectedTab: Main01Tab?
    let scale: CGFloat
    let accessibilityIdentifier: String
    let tabIdentifierPrefix: String
    let onTabSelection: (Main01Tab) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10 * scale) {
            HStack(spacing: 8 * scale) {
                ForEach(Main01Tab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(6 * scale)
            .frame(maxWidth: .infinity)
            .frame(height: 66 * scale)
            .glassEffect(
                .regular
                    .tint(Main01DesignTokens.Colors.chrome.opacity(0.42))
                    .interactive(),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.28), lineWidth: 0.8)
            }
            .shadow(color: Main01DesignTokens.Colors.chrome.opacity(0.28), radius: 12, y: 6)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.bottom, 10 * scale)
        .frame(height: Main01DesignTokens.Metrics.navHeight * scale, alignment: .bottom)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func tabButton(_ tab: Main01Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            onTabSelection(tab)
        } label: {
            VStack(spacing: 3 * scale) {
                Image(tab.assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: tab.iconSize.width * scale, height: tab.iconSize.height * scale)
                    .frame(height: 20 * scale, alignment: .bottom)

                tabLabel(tab)
            }
            .foregroundStyle(Main01DesignTokens.Colors.foreground)
            .frame(maxWidth: .infinity, minHeight: 50 * scale)
            .contentShape(Capsule())
        }
        .coorditPressFeedback()
        .glassEffect(
            isSelected
                ? .regular.tint(.white.opacity(0.18)).interactive()
                : .identity,
            in: Capsule()
        )
        .animation(.easeOut(duration: 0.22), value: isSelected)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(tabIdentifierPrefix)-\(tab.rawValue)")
    }

    @ViewBuilder
    private func tabLabel(_ tab: Main01Tab) -> some View {
        if tab == .fitLab {
            HStack(spacing: 2 * scale) {
                Text("FIT")
                Text("LAB")
            }
            .font(Main01DesignTokens.Typography.navLabel(size: tab.fontSize * scale))
            .tracking(tab.tracking * scale)
            .lineLimit(1)
        } else {
            Text(tab.title)
                .font(Main01DesignTokens.Typography.navLabel(size: tab.fontSize * scale))
                .tracking(tab.tracking * scale)
                .lineLimit(1)
        }
    }
}
#endif
