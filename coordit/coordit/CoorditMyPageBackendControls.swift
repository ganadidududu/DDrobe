import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func backendConnectionStatus(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsStatusBanner(
            text: backendSession.statusText,
            identifier: "mypage-backend-status",
            metrics: metrics,
            isWarning: backendSession.isWarning
        )
    }

    func syncBackendProfile() {
        guard let profile = backendSession.profile else { return }
        profileName = profile.displayName ?? "코딧 사용자"
    }

    func syncBackendBodyMeasurement() {
        guard let measurement = backendSession.latestBodyMeasurement else { return }
        heightMeasurement = measurement.heightCm.map { String(format: "%.1f", $0) } ?? ""
        weightMeasurement = measurement.weightKg.map { String(format: "%.1f", $0) } ?? ""
    }

    @ViewBuilder
    func backendAuthControls(metrics: CoorditResponsiveMetrics) -> some View {
        if backendSession.isAuthenticated {
            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    VStack(alignment: .leading, spacing: metrics.value(4)) {
                        Text(backendSession.displayNameText)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                            .foregroundStyle(CoorditSettingsStyle.ink)
                        Text(backendSession.emailText)
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                            .foregroundStyle(CoorditSettingsStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CoorditSettingsPrimaryButton(
                        title: "이 기기에서 로그아웃",
                        identifier: "mypage-backend-local-logout",
                        metrics: metrics
                    ) {
                        backendSession.logout()
                    }
                }
                .padding(.horizontal, metrics.value(13))
            }
        }
    }
}
#endif
