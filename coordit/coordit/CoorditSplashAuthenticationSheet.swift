import SwiftUI

#if os(iOS)
struct CoorditAuthenticationEntryView: View {
    let onAuthenticated: () -> Void

    @EnvironmentObject private var backendSession: CoorditBackendSessionStore

    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            ZStack(alignment: .top) {
                CoorditSharedAppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        pageTitle(metrics: metrics)
                            .padding(.top, metrics.value(CoorditAuthenticationEntryDesign.titleTopInset))
                        introduction(metrics: metrics)
                            .padding(.top, metrics.value(CoorditAuthenticationEntryDesign.titleToIntroductionSpacing))
                        socialProviders(metrics: metrics)
                            .padding(.top, metrics.value(CoorditAuthenticationEntryDesign.introductionToProvidersSpacing))
                        legalNotice(metrics: metrics)
                            .padding(.top, metrics.value(CoorditAuthenticationEntryDesign.providersToLegalSpacing))
                    }
                    .frame(width: metrics.value(CoorditAuthenticationEntryDesign.contentWidth), alignment: .leading)
                    .padding(.top, metrics.value(CoorditAuthenticationEntryDesign.topInset))
                    .padding(.bottom, metrics.value(CoorditAuthenticationEntryDesign.bottomInset))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .accessibilityIdentifier("coordit-screen-splash")
    }

    private func pageTitle(metrics: CoorditResponsiveMetrics) -> some View {
        HStack(spacing: metrics.value(CoorditAuthenticationEntryDesign.titleStackSpacing)) {
            Text("로그인 / 회원가입")
                .font(CoorditTypography.gmarketBold(size: metrics.value(CoorditAuthenticationEntryDesign.pageTitleFontSize), relativeTo: .title))
                .foregroundStyle(.black)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.value(CoorditAuthenticationEntryDesign.titleHorizontalInset))
        .frame(height: metrics.value(CoorditAuthenticationEntryDesign.titleHeight))
        .background(CoorditSettingsStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(CoorditAuthenticationEntryDesign.titleCornerRadius), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.value(CoorditAuthenticationEntryDesign.titleCornerRadius), style: .continuous)
                .stroke(CoorditSettingsStyle.line.opacity(CoorditAuthenticationEntryDesign.titleBorderOpacity), lineWidth: CoorditAuthenticationEntryDesign.titleBorderWidth)
        }
        .shadow(color: .black.opacity(CoorditAuthenticationEntryDesign.titleShadowOpacity), radius: metrics.value(CoorditAuthenticationEntryDesign.titleShadowRadius), y: metrics.value(CoorditAuthenticationEntryDesign.titleShadowYOffset))
    }

    private func introduction(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(CoorditAuthenticationEntryDesign.introductionStackSpacing)) {
            Text("계속하려면\n로그인하세요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(CoorditAuthenticationEntryDesign.introductionTitleFontSize), relativeTo: .title2))
                .foregroundStyle(CoorditSettingsStyle.ink)
                .lineSpacing(metrics.value(CoorditAuthenticationEntryDesign.introductionTitleLineSpacing))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Google 또는 Apple 계정으로\n내 핏 기록을 이어갈 수 있어요.")
                .font(CoorditTypography.gmarketMedium(size: metrics.value(CoorditAuthenticationEntryDesign.introductionBodyFontSize), relativeTo: .subheadline))
                .foregroundStyle(CoorditSettingsStyle.muted)
                .lineSpacing(metrics.value(CoorditAuthenticationEntryDesign.introductionBodyLineSpacing))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func socialProviders(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsCard(metrics: metrics) {
            VStack(spacing: 0) {
                socialButton(
                    title: "Google로 계속하기",
                    mark: "G",
                    markBackground: CoorditSettingsStyle.field,
                    markForeground: CoorditDesignTokens.ColorToken.blue,
                    identifier: "splash-auth-google",
                    metrics: metrics,
                    action: { await backendSession.loginWithGoogle() }
                )

                CoorditSettingsDivider(metrics: metrics)

                socialButton(
                    title: "Apple로 계속하기",
                    systemImage: "apple.logo",
                    markBackground: CoorditSettingsStyle.ink,
                    markForeground: .white,
                    identifier: "splash-auth-apple",
                    metrics: metrics,
                    action: { await backendSession.loginWithApple() }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coordit-splash-auth-sheet")
    }

    @ViewBuilder
    private func socialButton(
        title: String,
        mark: String? = nil,
        systemImage: String? = nil,
        markBackground: Color,
        markForeground: Color,
        identifier: String,
        metrics: CoorditResponsiveMetrics,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                guard backendSession.isAuthenticated else { return }
                onAuthenticated()
            }
        } label: {
            HStack(spacing: metrics.value(CoorditAuthenticationEntryDesign.providerStackSpacing)) {
                Group {
                    if let mark {
                        Text(mark)
                            .font(.system(size: metrics.value(CoorditAuthenticationEntryDesign.providerMarkFontSize), weight: .bold, design: .rounded))
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: metrics.value(CoorditAuthenticationEntryDesign.providerMarkFontSize), weight: .semibold))
                    }
                }
                .foregroundStyle(markForeground)
                .frame(width: metrics.value(CoorditAuthenticationEntryDesign.providerMarkSize), height: metrics.value(CoorditAuthenticationEntryDesign.providerMarkSize))
                .background(markBackground, in: Circle())

                Text(title)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(CoorditAuthenticationEntryDesign.providerTitleFontSize), relativeTo: .body))
                    .foregroundStyle(CoorditSettingsStyle.ink)

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: metrics.value(CoorditAuthenticationEntryDesign.providerArrowFontSize), weight: .semibold))
                    .foregroundStyle(CoorditSettingsStyle.muted)
            }
            .padding(.horizontal, metrics.value(CoorditAuthenticationEntryDesign.providerHorizontalInset))
            .frame(minHeight: metrics.value(CoorditAuthenticationEntryDesign.providerHeight))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .coorditPressFeedback(
            cornerRadius: metrics.value(CoorditAuthenticationEntryDesign.providerCornerRadius),
            pressedScale: CoorditAuthenticationEntryDesign.providerPressedScale,
            pressedOpacity: CoorditAuthenticationEntryDesign.providerPressedOpacity,
            overlayOpacity: CoorditAuthenticationEntryDesign.providerPressedOverlayOpacity
        )
        .disabled(backendSession.isWorking)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func legalNotice(metrics: CoorditResponsiveMetrics) -> some View {
        Text("계속하면 이용약관 및 개인정보 처리방침에 동의하게 됩니다.")
            .font(CoorditTypography.gmarketMedium(size: metrics.value(CoorditAuthenticationEntryDesign.legalFontSize), relativeTo: .caption))
            .foregroundStyle(CoorditSettingsStyle.muted)
            .lineSpacing(metrics.value(CoorditAuthenticationEntryDesign.legalLineSpacing))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

}

private enum CoorditAuthenticationEntryDesign {
    static let contentWidth: CGFloat = 370
    static let topInset: CGFloat = 28
    static let bottomInset: CGFloat = 36
    static let titleTopInset: CGFloat = 24
    static let titleToIntroductionSpacing: CGFloat = 30
    static let introductionToProvidersSpacing: CGFloat = 22
    static let providersToLegalSpacing: CGFloat = 20
    static let titleStackSpacing: CGFloat = 12
    static let pageTitleFontSize: CGFloat = 24
    static let titleHorizontalInset: CGFloat = 18
    static let titleHeight: CGFloat = 72
    static let titleCornerRadius: CGFloat = 11
    static let titleBorderOpacity: Double = 0.72
    static let titleBorderWidth: CGFloat = 1
    static let titleShadowOpacity: Double = 0.045
    static let titleShadowRadius: CGFloat = 10
    static let titleShadowYOffset: CGFloat = 4
    static let introductionStackSpacing: CGFloat = 8
    static let introductionTitleFontSize: CGFloat = 26
    static let introductionTitleLineSpacing: CGFloat = 4
    static let introductionBodyFontSize: CGFloat = 12
    static let introductionBodyLineSpacing: CGFloat = 3
    static let providerStackSpacing: CGFloat = 12
    static let providerMarkFontSize: CGFloat = 16
    static let providerMarkSize: CGFloat = 28
    static let providerTitleFontSize: CGFloat = 14
    static let providerArrowFontSize: CGFloat = 13
    static let providerHorizontalInset: CGFloat = 15
    static let providerHeight: CGFloat = 58
    static let providerCornerRadius: CGFloat = 7
    static let providerPressedScale: CGFloat = 0.98
    static let providerPressedOpacity: CGFloat = 0.9
    static let providerPressedOverlayOpacity: CGFloat = 0.1
    static let legalFontSize: CGFloat = 10
    static let legalLineSpacing: CGFloat = 4
}
#endif
