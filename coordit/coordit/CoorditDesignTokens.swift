import SwiftUI

#if os(iOS)
enum CoorditDesignTokens {
    enum ColorToken {
        static let appBackground = rgb(247, 248, 248)
        static let ink = rgb(0, 12, 64)
        static let muted = rgb(126, 132, 146)
        static let fitMuted = rgb(127, 133, 150)
        static let panel = rgb(252, 253, 254)
        static let field = rgb(245, 247, 252)
        static let settingsField = rgb(246, 247, 249)
        static let closetField = rgb(242, 244, 248)
        static let closetMuted = rgb(184, 193, 211)
        static let placeholder = rgb(231, 235, 244)
        static let line = rgb(225, 229, 234)
        static let blue = rgb(25, 64, 150)
        static let cyan = rgb(0, 172, 207)
        static let green = rgb(0, 180, 67)
        static let red = rgb(235, 37, 73)
        static let danger = rgb(234, 74, 86)
        static let warmLine = rgb(255, 188, 56)
        static let loadingSparkle = rgb(246, 215, 122)
        static let chargeGradientTop = rgb(50, 66, 116)
        static let chargeGradientEnd = rgb(74, 85, 132)

        private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
            Color(red: red / 255, green: green / 255, blue: blue / 255)
        }
    }

    enum Spacing {
        static let pageInset: CGFloat = 22
        static let panelPadding: CGFloat = 20
        static let navHeight: CGFloat = 86
        static let cornerRadius: CGFloat = 10
    }

    enum HomeReferenceMetrics {
        static let cardWidth: CGFloat = 361
        static let cardPadding: CGFloat = 13
        static let cardRadius: CGFloat = 10
        static let sheetPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let sectionRadius: CGFloat = 9
        static let rowHeight: CGFloat = 82
        static let rowRadius: CGFloat = 8
        static let thumbnailWidth: CGFloat = 52
        static let thumbnailHeight: CGFloat = 70
        static let introFontSize: CGFloat = 11
        static let actionFontSize: CGFloat = 12
        static let actionHeight: CGFloat = 44
        static let actionRadius: CGFloat = 8
        static let groupRowSpacing: CGFloat = 9
        static let groupTitleFontSize: CGFloat = 14
        static let emptyTextFontSize: CGFloat = 11
        static let emptyTextVerticalPadding: CGFloat = 12
        static let rowSpacing: CGFloat = 12
        static let rowTextSpacing: CGFloat = 3
        static let rowTitleFontSize: CGFloat = 13
        static let rowSubtitleFontSize: CGFloat = 10
        static let rowIconSize: CGFloat = 21
        static let rowHorizontalPadding: CGFloat = 10
        static let emptyPanelSpacing: CGFloat = 12
        static let emptyIconSize: CGFloat = 28
        static let emptyPanelVerticalPadding: CGFloat = 34
    }

    enum GlobalNoticeMetrics {
        static let horizontalInset: CGFloat = 16
        static let topInset: CGFloat = 8
        static let contentSpacing: CGFloat = 11
        static let contentInset: CGFloat = 14
        static let minHeight: CGFloat = 58
        static let radius: CGFloat = 10
        static let shadowRadius: CGFloat = 10
        static let shadowYOffset: CGFloat = 4
    }

    enum ChargeMetrics {
        static let contentWidth: CGFloat = 354
        static let titleToBalanceSpacing: CGFloat = 27
        static let balanceToAdSpacing: CGFloat = 20
        static let adToPackagesSpacing: CGFloat = 21
        static let packageSpacing: CGFloat = 20
        static let balanceHeight: CGFloat = 82
        static let adHeight: CGFloat = 136
        static let packageHeight: CGFloat = 72
        static let balanceRadius: CGFloat = 20
        static let adRadius: CGFloat = 8
        static let packageRadius: CGFloat = 8
        static let playTileSize: CGFloat = 44
        static let playTileRadius: CGFloat = 12
        static let adContentSpacing: CGFloat = 14
        static let adShadowRadius: CGFloat = 18
        static let adShadowYOffset: CGFloat = 9
    }
}

enum CoorditContentActionProminence {
    case primary
    case secondary
}

struct CoorditContentActionButtonStyle: ButtonStyle {
    let prominence: CoorditContentActionProminence
    let height: CGFloat
    let cornerRadius: CGFloat
    let fontSize: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    init(
        prominence: CoorditContentActionProminence,
        height: CGFloat = 48,
        cornerRadius: CGFloat = 7,
        fontSize: CGFloat = 13
    ) {
        self.prominence = prominence
        self.height = height
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CoorditTypography.gmarketBold(size: fontSize, relativeTo: .headline))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .foregroundStyle(prominence == .primary ? Color.white : CoorditDesignTokens.ColorToken.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                prominence == .primary
                    ? CoorditDesignTokens.ColorToken.ink
                    : CoorditDesignTokens.ColorToken.placeholder
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEnabled && configuration.isPressed ? Color.black.opacity(0.16) : Color.clear)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isEnabled && configuration.isPressed ? 0.965 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.38)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.linear(duration: 0.035), value: configuration.isPressed)
    }
}
#endif
