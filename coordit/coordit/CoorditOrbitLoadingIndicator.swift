import SwiftUI

#if os(iOS)
struct CoorditOrbitLoadingIndicator: View {
    let metrics: CoorditResponsiveMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion
                ? 0.0
                : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.8) / 1.8 * 2 * Double.pi

            ZStack {
                Image(CoorditAssetNames.loadingMannequin)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: metrics.value(58), height: metrics.value(82))
                    .foregroundStyle(CoorditDesignTokens.ColorToken.muted.opacity(0.52))

                Ellipse()
                    .stroke(
                        CoorditDesignTokens.ColorToken.ink.opacity(0.3),
                        lineWidth: metrics.value(1.5)
                    )
                    .frame(width: metrics.value(82), height: metrics.value(38))
                    .rotationEffect(.degrees(-24))
                    .shadow(
                        color: CoorditDesignTokens.ColorToken.ink.opacity(0.12),
                        radius: metrics.value(3)
                    )

                Image(systemName: "sparkle")
                    .font(.system(size: metrics.value(10), weight: .bold))
                    .foregroundStyle(CoorditDesignTokens.ColorToken.loadingSparkle)
                    .shadow(
                        color: CoorditDesignTokens.ColorToken.loadingSparkle.opacity(0.68),
                        radius: metrics.value(4)
                    )
                    .offset(sparkleOffset(phase: phase))
            }
            .frame(width: metrics.value(92), height: metrics.value(92))
        }
        .accessibilityHidden(true)
    }

    private func sparkleOffset(phase: Double) -> CGSize {
        let x = cos(phase) * metrics.value(41)
        let y = sin(phase) * metrics.value(19)
        let angle = -24.0 * Double.pi / 180.0
        return CGSize(
            width: x * cos(angle) - y * sin(angle),
            height: x * sin(angle) + y * cos(angle)
        )
    }
}
#endif
