import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func backendConnectionStatus(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsStatusBanner(
            text: backendAccountStatusText,
            identifier: "mypage-backend-status",
            metrics: metrics,
            isWarning: backendSession.isWarning
        )
    }

    private var backendAccountStatusText: String {
        if backendSession.isWarning { return backendSession.statusText }
        if backendSession.isMember { return "계정 연결됨" }
        if backendSession.isAuthenticated { return "비회원으로 이용 중" }
        return "계정을 연결하면 기록을 안전하게 보관할 수 있어요"
    }

    func syncBackendProfile() {
        guard let profile = backendSession.profile else { return }
        profileName = profile.displayName ?? "코딧 사용자"
        backendEmail = profile.email
    }

    func syncBackendBodyMeasurement() {
        guard let measurement = backendSession.latestBodyMeasurement else { return }
        shoulderMeasurement = measurement.shoulderWidth.map { String(format: "%.1f", $0) } ?? shoulderMeasurement
        chestMeasurement = measurement.chestCircumference.map { String(format: "%.1f", $0) } ?? chestMeasurement
        waistMeasurement = measurement.waistCircumference.map { String(format: "%.1f", $0) } ?? waistMeasurement
        hipMeasurement = measurement.hipCircumference.map { String(format: "%.1f", $0) } ?? hipMeasurement
    }

    func backendAuthControls(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsCard(metrics: metrics) {
            VStack(spacing: metrics.value(13)) {
                CoorditSettingsTextField(
                    title: "계정 이메일",
                    placeholder: "email@example.com",
                    text: $backendEmail,
                    identifier: "mypage-backend-email",
                    metrics: metrics
                )
                CoorditSettingsTextField(
                    title: "비밀번호",
                    placeholder: "비밀번호",
                    text: $backendPassword,
                    identifier: "mypage-backend-password",
                    metrics: metrics,
                    isSecure: true
                )

                CoorditSettingsGoogleButton(
                    identifier: "mypage-backend-google-login",
                    metrics: metrics,
                    isEnabled: !backendSession.isWorking
                ) {
                    Task {
                        await backendSession.loginWithGoogle()
                        syncBackendProfile()
                        syncBackendBodyMeasurement()
                    }
                }

                CoorditAppleSignInButton(
                    identifier: "mypage-backend-apple-login",
                    height: metrics.value(48),
                    cornerRadius: metrics.value(7)
                ) {
                    syncBackendProfile()
                    syncBackendBodyMeasurement()
                }

                HStack(spacing: metrics.value(10)) {
                    CoorditSettingsPrimaryButton(
                        title: "로그인",
                        identifier: "mypage-backend-login",
                        metrics: metrics,
                        isEnabled: canSubmitBackendAuth
                    ) {
                        Task {
                            await backendSession.login(email: backendEmail, password: backendPassword)
                            syncBackendProfile()
                            syncBackendBodyMeasurement()
                        }
                    }
                    CoorditSettingsPrimaryButton(
                        title: "가입",
                        identifier: "mypage-backend-signup",
                        metrics: metrics,
                        isEnabled: canSubmitBackendAuth
                    ) {
                        Task {
                            await backendSession.signup(email: backendEmail, password: backendPassword)
                            syncBackendProfile()
                            syncBackendBodyMeasurement()
                        }
                    }
                }

                if backendSession.isMember {
                    CoorditSettingsPrimaryButton(
                        title: "이 기기에서 로그아웃",
                        identifier: "mypage-backend-local-logout",
                        metrics: metrics
                    ) {
                        backendSession.logout()
                    }
                }
            }
            .padding(.horizontal, metrics.value(13))
        }
    }

    private var canSubmitBackendAuth: Bool {
        backendEmail.contains("@") && backendPassword.count >= 6 && !backendSession.isWorking
    }
}

private struct CoorditSettingsGoogleButton: View {
    let identifier: String
    let metrics: CoorditResponsiveMetrics
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.value(10)) {
                Text("G")
                    .font(.system(size: metrics.value(15), weight: .bold, design: .rounded))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                    .frame(width: metrics.value(24), height: metrics.value(24))
                    .background(.white)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(CoorditSettingsStyle.line, lineWidth: 1)
                    }

                Text("Google로 계속하기")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.value(14))
            .frame(maxWidth: .infinity)
            .frame(height: max(metrics.value(48), 44))
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                    .stroke(CoorditSettingsStyle.line, lineWidth: 1)
            }
        }
        .coorditPressFeedback()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityIdentifier(identifier)
    }
}
#endif
