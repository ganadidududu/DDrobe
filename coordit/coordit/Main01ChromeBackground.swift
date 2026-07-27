import SwiftUI

#if os(iOS)
struct Main01ChromeBackground: View {
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Main01DesignTokens.Colors.topChrome)
            .frame(height: Main01DesignTokens.Metrics.topChromeHeight * scale)

            Spacer(minLength: 0)

            ZStack {
                Rectangle()
                    .fill(Main01DesignTokens.Colors.bottomChrome)

                Rectangle()
                    .fill(Main01DesignTokens.Colors.bottomChromeContour)
                    .mask(Main01DesignTokens.Colors.bottomChromeContourMask)
            }
            .frame(height: Main01DesignTokens.Metrics.bottomChromeHeight * scale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
