import SwiftUI

#if os(iOS)
struct CoorditSplashAuthenticationSheet: View {
    let onAuthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore

    var body: some View {
        VStack(spacing: 0) {
            Text("coordit에 로그인")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.titleSize, relativeTo: .title2))
                .foregroundStyle(Main01DesignTokens.Colors.chrome)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coordit-splash-auth-sheet")

            Text("나만의 디지털 옷장을 이어서 만나보세요.")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.subtitleSize, relativeTo: .subheadline))
                .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.6))
                .padding(.top, CoorditSplashAuthenticationDesign.titleToSubtitleSpacing)

            VStack(spacing: CoorditSplashAuthenticationDesign.providerStackSpacing) {
                socialButton(
                    title: "Google로 계속하기",
                    icon: "G",
                    iconBackground: CoorditSplashAuthenticationDesign.googleMarkSurface,
                    iconForeground: CoorditSplashAuthenticationDesign.googleMarkForeground,
                    action: { await backendSession.loginWithGoogle() }
                )

                socialButton(
                    title: "Apple로 계속하기",
                    systemImage: "apple.logo",
                    iconBackground: CoorditSplashAuthenticationDesign.appleMarkSurface,
                    iconForeground: CoorditSplashAuthenticationDesign.appleMarkForeground,
                    action: { await backendSession.loginWithApple() }
                )
            }
            .padding(.top, CoorditSplashAuthenticationDesign.subtitleToProviderSpacing)

            if backendSession.isWorking {
                ProgressView()
                    .tint(Main01DesignTokens.Colors.chrome)
                    .padding(.top, CoorditSplashAuthenticationDesign.statusTopSpacing)
                    .accessibilityLabel("로그인 진행 중")
            } else if backendSession.isWarning {
                Text(backendSession.statusText)
                    .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.statusSize, relativeTo: .caption))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, CoorditSplashAuthenticationDesign.statusTopSpacing)
                    .accessibilityIdentifier("splash-auth-error")
            }

            Spacer(minLength: CoorditSplashAuthenticationDesign.footerMinimumSpacing)

            Text("계속하면 coordit의 이용약관과 개인정보 처리방침에 동의하게 됩니다.")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.legalSize, relativeTo: .caption2))
                .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, CoorditSplashAuthenticationDesign.horizontalInset)
        .padding(.top, CoorditSplashAuthenticationDesign.topInset)
        .padding(.bottom, CoorditSplashAuthenticationDesign.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white)
        .presentationDetents([.height(CoorditSplashAuthenticationDesign.sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CoorditSplashAuthenticationDesign.sheetCornerRadius)
        .interactiveDismissDisabled(backendSession.isWorking)
    }

    @ViewBuilder
    private func socialButton(
        title: String,
        icon: String? = nil,
        systemImage: String? = nil,
        iconBackground: Color,
        iconForeground: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                guard backendSession.isAuthenticated else { return }
                onAuthenticated()
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Text(icon)
                            .font(.system(size: CoorditSplashAuthenticationDesign.googleMarkSize, weight: .bold, design: .rounded))
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: CoorditSplashAuthenticationDesign.appleMarkSize, weight: .semibold))
                    }
                }
                .foregroundStyle(iconForeground)
                .frame(width: CoorditSplashAuthenticationDesign.providerMarkFrame, height: CoorditSplashAuthenticationDesign.providerMarkFrame)
                .background(iconBackground, in: Circle())

                Text(title)
                    .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.providerTitleSize, relativeTo: .body))
                    .foregroundStyle(Main01DesignTokens.Colors.chrome)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CoorditSplashAuthenticationDesign.providerHorizontalInset)
            .frame(maxWidth: .infinity, minHeight: CoorditSplashAuthenticationDesign.providerHeight)
            .background(CoorditSplashAuthenticationDesign.providerSurface, in: RoundedRectangle(cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius, style: .continuous)
                    .stroke(Main01DesignTokens.Colors.chrome.opacity(CoorditSplashAuthenticationDesign.providerBorderOpacity), lineWidth: CoorditSplashAuthenticationDesign.providerBorderWidth)
            }
        }
        .buttonStyle(.plain)
        .disabled(backendSession.isWorking)
        .accessibilityIdentifier(title.hasPrefix("Google") ? "splash-auth-google" : "splash-auth-apple")
    }
}

private enum CoorditSplashAuthenticationDesign {
    static let sheetHeight: CGFloat = 340
    static let sheetCornerRadius: CGFloat = 28
    static let horizontalInset: CGFloat = 24
    static let topInset: CGFloat = 22
    static let bottomInset: CGFloat = 18
    static let titleSize: CGFloat = 22
    static let subtitleSize: CGFloat = 13
    static let titleToSubtitleSpacing: CGFloat = 10
    static let subtitleToProviderSpacing: CGFloat = 28
    static let providerStackSpacing: CGFloat = 12
    static let providerHeight: CGFloat = 56
    static let providerHorizontalInset: CGFloat = 16
    static let providerCornerRadius: CGFloat = 16
    static let providerBorderWidth: CGFloat = 1
    static let providerBorderOpacity: CGFloat = 0.09
    static let providerSurface = Color(red: 0.965, green: 0.968, blue: 0.98)
    static let providerMarkFrame: CGFloat = 28
    static let googleMarkSurface = Color.white
    static let googleMarkForeground = Color(red: 0.26, green: 0.45, blue: 0.83)
    static let appleMarkSurface = Main01DesignTokens.Colors.chrome
    static let appleMarkForeground = Color.white
    static let googleMarkSize: CGFloat = 16
    static let appleMarkSize: CGFloat = 17
    static let providerTitleSize: CGFloat = 14
    static let statusTopSpacing: CGFloat = 18
    static let statusSize: CGFloat = 11.5
    static let footerMinimumSpacing: CGFloat = 16
    static let legalSize: CGFloat = 10.5
}
#endif
