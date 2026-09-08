import SwiftUI

#if os(iOS)
struct CoorditSplashAuthenticationSheet: View {
    let onAuthenticated: () -> Void
    let onGuestAuthenticated: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @State private var mode: AuthenticationMode = .providers
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: AuthenticationField?

    var body: some View {
        VStack(spacing: 0) {
            Text("coordit 시작하기")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.titleSize, relativeTo: .title2))
                .foregroundStyle(Main01DesignTokens.Colors.chrome)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coordit-splash-auth-sheet")

            Text(mode == .providers ? "비회원으로 시작하거나 계정을 연결하세요." : "이메일과 비밀번호를 입력하세요.")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.subtitleSize, relativeTo: .subheadline))
                .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.6))
                .padding(.top, CoorditSplashAuthenticationDesign.titleToSubtitleSpacing)

            Group {
                switch mode {
                case .providers:
                    providerChoices
                case .email:
                    emailLoginForm
                }
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
                    .foregroundStyle(CoorditSplashAuthenticationDesign.errorForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, CoorditSplashAuthenticationDesign.statusTopSpacing)
                    .accessibilityIdentifier("splash-auth-error")
            }

            Spacer(minLength: CoorditSplashAuthenticationDesign.footerMinimumSpacing)

            Text("계속하면 coordit의 이용약관과 개인정보 처리방침에 동의하게 됩니다.")
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.legalSize, relativeTo: .caption2))
                .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("splash-auth-legal")
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

    private var providerChoices: some View {
        VStack(spacing: CoorditSplashAuthenticationDesign.providerStackSpacing) {
            socialButton(
                title: "Google로 계속하기",
                icon: "G",
                iconBackground: CoorditSplashAuthenticationDesign.googleMarkSurface,
                iconForeground: CoorditSplashAuthenticationDesign.googleMarkForeground,
                action: { await backendSession.loginWithGoogle() }
            )

            CoorditAppleSignInButton(
                identifier: "splash-auth-apple",
                height: CoorditSplashAuthenticationDesign.providerHeight,
                cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius
            ) {
                onAuthenticated()
                dismiss()
            }

            providerButton(title: "비회원으로 로그인하기", identifier: "splash-auth-guest") {
                Task {
                    guard let balance = await backendSession.bootstrapGuestIfNeeded() else { return }
                    onGuestAuthenticated(balance)
                    dismiss()
                }
            }

            secondaryActionButton(title: "이메일로 로그인", identifier: "splash-auth-email") {
                backendSession.clearStatus()
                mode = .email
                focusedField = .email
            }
        }
    }

    private var emailLoginForm: some View {
        VStack(spacing: CoorditSplashAuthenticationDesign.emailFormSpacing) {
            TextField("이메일", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .accessibilityIdentifier("splash-auth-email-field")
                .authFieldStyle()
                .disabled(backendSession.isWorking)

            SecureField("비밀번호", text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { submitEmailLogin() }
                .accessibilityIdentifier("splash-auth-password-field")
                .authFieldStyle()
                .disabled(backendSession.isWorking)

            providerButton(
                title: backendSession.isWorking ? "로그인 중…" : "이메일로 로그인",
                identifier: "splash-auth-email-submit",
                action: submitEmailLogin
            )
            .disabled(!canSubmitEmailLogin || backendSession.isWorking)

            secondaryActionButton(title: "다른 방법으로 로그인", identifier: "splash-auth-email-back") {
                focusedField = nil
                backendSession.clearStatus()
                mode = .providers
            }
        }
    }

    private var canSubmitEmailLogin: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func submitEmailLogin() {
        guard canSubmitEmailLogin, !backendSession.isWorking else { return }
        focusedField = nil
        Task {
            await backendSession.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            guard backendSession.isMember else { return }
            onAuthenticated()
            dismiss()
        }
    }

    private func providerButton(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.providerTitleSize, relativeTo: .body))
                .foregroundStyle(Main01DesignTokens.Colors.chrome)
                .frame(maxWidth: .infinity, minHeight: CoorditSplashAuthenticationDesign.providerHeight)
                .background(.white, in: RoundedRectangle(cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius, style: .continuous)
                        .stroke(Main01DesignTokens.Colors.chrome.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(backendSession.isWorking)
        .accessibilityIdentifier(identifier)
    }

    private func secondaryActionButton(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.emailEntrySize, relativeTo: .body))
                .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.72))
                .frame(minHeight: CoorditSplashAuthenticationDesign.secondaryActionHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(backendSession.isWorking)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func socialButton(
        title: String,
        icon: String? = nil,
        iconBackground: Color,
        iconForeground: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                guard backendSession.isMember else { return }
                onAuthenticated()
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Text(icon)
                            .font(.system(size: CoorditSplashAuthenticationDesign.googleMarkSize, weight: .bold, design: .rounded))
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
        .accessibilityIdentifier("splash-auth-google")
    }
}

private enum CoorditSplashAuthenticationDesign {
    static let sheetHeight: CGFloat = 450
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
    static let googleMarkSize: CGFloat = 16
    static let providerTitleSize: CGFloat = 14
    static let statusTopSpacing: CGFloat = 18
    static let statusSize: CGFloat = 11.5
    static let emailEntrySize: CGFloat = 12
    static let secondaryActionHeight: CGFloat = 44
    static let emailFormSpacing: CGFloat = 12
    static let errorForeground = Color(red: 0.62, green: 0.04, blue: 0.08)
    static let footerMinimumSpacing: CGFloat = 16
    static let legalSize: CGFloat = 11
}

private enum AuthenticationMode {
    case providers
    case email
}

private enum AuthenticationField: Hashable {
    case email
    case password
}

private extension View {
    func authFieldStyle() -> some View {
        font(CoorditTypography.gmarketMedium(size: CoorditSplashAuthenticationDesign.providerTitleSize, relativeTo: .body))
            .foregroundStyle(Main01DesignTokens.Colors.chrome)
            .padding(.horizontal, CoorditSplashAuthenticationDesign.providerHorizontalInset)
            .frame(maxWidth: .infinity, minHeight: CoorditSplashAuthenticationDesign.providerHeight)
            .background(
                CoorditSplashAuthenticationDesign.providerSurface,
                in: RoundedRectangle(cornerRadius: CoorditSplashAuthenticationDesign.providerCornerRadius, style: .continuous)
            )
    }
}
#endif
