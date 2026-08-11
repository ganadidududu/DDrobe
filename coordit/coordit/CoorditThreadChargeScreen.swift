import SwiftUI

#if os(iOS)
private enum CoorditThreadChargeAvailability {
    // StoreKit verification and rewarded-ad settlement must be implemented before enabling either path.
    static let rewardedAds = false
    static let purchases = false
}

extension CoorditMyPageFamilyView {
    func threadCharge(
        metrics: CoorditResponsiveMetrics,
        contentMetrics: CoorditResponsiveMetrics,
        threadBalance: Int
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
                    Text("\(threadBalance) 실타래")
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
            .disabled(!CoorditThreadChargeAvailability.rewardedAds)
            .opacity(CoorditThreadChargeAvailability.rewardedAds ? 1 : 0.48)
            .accessibilityLabel("광고 보고 실타래 충전하기")
            .accessibilityIdentifier("coordit-thread-charge-ad-cta")
            .padding(.bottom, contentMetrics.value(CoorditDesignTokens.ChargeMetrics.adToPackagesSpacing))

            if !CoorditThreadChargeAvailability.rewardedAds || !CoorditThreadChargeAvailability.purchases {
                Text("실타래 충전은 출시 준비 중이에요.")
                    .font(CoorditTypography.gmarketMedium(size: contentMetrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("coordit-thread-charge-notice")
                    .padding(.bottom, contentMetrics.value(10))
            }

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
        .disabled(!CoorditThreadChargeAvailability.purchases)
        .opacity(CoorditThreadChargeAvailability.purchases ? 1 : 0.48)
        .accessibilityLabel(amount)
        .accessibilityIdentifier(identifier)
    }
}

struct CoorditThreadRechargeRequiredPopup: View {
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = CoorditResponsiveMetrics(size: proxy.size)

            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                VStack(spacing: metrics.value(15)) {
                    Image(CoorditAssetNames.yarn)
                        .resizable()
                        .scaledToFit()
                        .frame(width: metrics.value(70), height: metrics.value(70))
                        .accessibilityHidden(true)

                    VStack(spacing: metrics.value(7)) {
                        Text("실타래를 충전해주세요!")
                            .font(CoorditTypography.gmarketBold(size: metrics.value(18), relativeTo: .headline))
                            .foregroundStyle(CoorditSettingsStyle.ink)
                            .multilineTextAlignment(.center)

                        Text("FIT LAB 분석과 상세 리포트 생성에는 각각 실타래 1개가 필요해요.")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .caption))
                            .foregroundStyle(CoorditSettingsStyle.muted)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: dismiss) {
                        Text("충전하러 가기")
                            .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.value(48))
                            .background(CoorditSettingsStyle.ink)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
                    }
                    .coorditPressFeedback()
                    .accessibilityIdentifier("coordit-thread-recharge-required-confirm")
                }
                .padding(.horizontal, metrics.value(20))
                .padding(.vertical, metrics.value(22))
                .frame(width: min(proxy.size.width - metrics.value(56), metrics.value(318)))
                .background(CoorditSettingsStyle.panel)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(16), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.value(16), style: .continuous)
                        .stroke(CoorditSettingsStyle.line, lineWidth: metrics.value(1))
                }
                .shadow(color: .black.opacity(0.16), radius: metrics.value(24), y: metrics.value(12))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("coordit-thread-recharge-required-popup")
            }
        }
    }
}
#endif
