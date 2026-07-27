import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func threadCharge(
        metrics: CoorditResponsiveMetrics,
        contentMetrics: CoorditResponsiveMetrics
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: contentMetrics.value(12)) {
                Image(CoorditAssetNames.yarn)
                    .resizable()
                    .scaledToFit()
                    .frame(width: contentMetrics.value(50), height: contentMetrics.value(50))

                VStack(alignment: .leading, spacing: contentMetrics.value(4)) {
                    Text("보유 실타래")
                        .font(CoorditTypography.gmarketBold(size: contentMetrics.value(12), relativeTo: .subheadline))
                        .foregroundStyle(CoorditSettingsStyle.muted)
                    Text("36 실타래")
                        .font(CoorditTypography.gmarketBold(size: contentMetrics.value(29), relativeTo: .title))
                        .foregroundStyle(CoorditSettingsStyle.ink)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, contentMetrics.value(18))
            .frame(height: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.balanceHeight))
            .background(CoorditSettingsStyle.panel)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.balanceRadius),
                    style: .continuous
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coordit-thread-charge-balance")
            .padding(.bottom, contentMetrics.value(CoorditDesignTokens.ChargeMetrics.balanceToAdSpacing))

            Button(action: {}) {
                HStack(spacing: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adContentSpacing)) {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.playTileRadius),
                            style: .continuous
                        )
                        .fill(.white.opacity(0.14))

                        Image(CoorditAssetNames.rechargePlay)
                            .resizable()
                            .scaledToFit()
                            .frame(width: contentMetrics.value(24), height: contentMetrics.value(24))
                    }
                    .frame(
                        width: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.playTileSize),
                        height: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.playTileSize)
                    )

                    Text("광고 보고 실타래 충전하기")
                        .font(CoorditTypography.gmarketBold(size: contentMetrics.value(18), relativeTo: .headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                    CoorditSettingsChevron(metrics: contentMetrics, color: .white)
                }
                .padding(.horizontal, contentMetrics.value(15))
                .frame(height: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adHeight))
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: CoorditDesignTokens.ColorToken.chargeGradientTop, location: 0),
                            .init(color: CoorditSettingsStyle.ink, location: 0.62),
                            .init(color: CoorditDesignTokens.ColorToken.chargeGradientEnd, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adRadius),
                        style: .continuous
                    )
                )
                .shadow(
                    color: .black.opacity(0.18),
                    radius: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adShadowRadius),
                    y: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adShadowYOffset)
                )
            }
            .coorditPressFeedback()
            .accessibilityLabel("광고 보고 실타래 충전하기")
            .accessibilityIdentifier("coordit-thread-charge-ad-cta")
            .padding(.bottom, contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adToPackagesSpacing))

            VStack(spacing: contentMetrics.value(CoorditDesignTokens.ChargeMetrics.packageSpacing)) {
                yarnPurchaseRow(
                    amount: "5 실타래",
                    price: "1,500원",
                    identifier: "coordit-thread-charge-pack-5",
                    highlighted: false,
                    metrics: contentMetrics
                )
                yarnPurchaseRow(
                    amount: "10 실타래",
                    price: "2,500원",
                    identifier: "coordit-thread-charge-pack-10",
                    highlighted: true,
                    metrics: contentMetrics
                )
                yarnPurchaseRow(
                    amount: "20 실타래",
                    price: "4,000원",
                    identifier: "coordit-thread-charge-pack-20",
                    highlighted: false,
                    metrics: contentMetrics
                )
            }
        }
    }

    private func yarnPurchaseRow(
        amount: String,
        price: String,
        identifier: String,
        highlighted: Bool,
        metrics: CoorditResponsiveMetrics
    ) -> some View {
        Button(action: {}) {
            HStack(spacing: metrics.value(12)) {
                Image(CoorditAssetNames.yarn)
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.value(54), height: metrics.value(54))

                VStack(alignment: .leading, spacing: metrics.value(3)) {
                    Text(amount)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(16), relativeTo: .headline))
                        .foregroundStyle(.black)
                    Text("실타래 충전")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                        .foregroundStyle(CoorditSettingsStyle.muted)
                }

                Spacer(minLength: 0)

                Text(price)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, metrics.value(12))
                    .frame(height: metrics.value(31))
                    .background(CoorditSettingsStyle.ink)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, metrics.value(16))
            .frame(height: metrics.value(CoorditDesignTokens.ChargeMetrics.packageHeight))
            .background(CoorditSettingsStyle.panel)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: metrics.value(CoorditDesignTokens.ChargeMetrics.packageRadius),
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: metrics.value(CoorditDesignTokens.ChargeMetrics.packageRadius),
                    style: .continuous
                )
                .stroke(
                    highlighted ? CoorditSettingsStyle.warmLine : CoorditSettingsStyle.line,
                    lineWidth: highlighted ? 2 : 1
                )
            }
            .shadow(color: .black.opacity(0.035), radius: metrics.value(8), y: metrics.value(3))
        }
        .coorditPressFeedback()
        .accessibilityLabel(amount)
        .accessibilityIdentifier(identifier)
    }
}
#endif
