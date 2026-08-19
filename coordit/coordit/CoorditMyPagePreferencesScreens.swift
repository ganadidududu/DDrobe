import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

#if os(iOS)
extension CoorditMyPageFamilyView {
    func privacy(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "개인정보 처리방침", subtitle: "서비스 데이터 처리 기준", metrics: metrics, action: {
                    onRouteChange(.myPagePrivacyPolicy)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "서비스 이용약관", subtitle: "2026.06.30 기준", metrics: metrics, action: {
                    onRouteChange(.myPageTerms)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "데이터 수집 동의", metrics: metrics) {
                    CoorditSettingsValuePill(text: "필수 동의 완료", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "피드백 데이터 개인화 사용 동의", subtitle: "추천 개선에 사용", metrics: metrics) {
                    CoorditSettingsToggle(isOn: $feedDataConsent, metrics: metrics, label: "피드백 데이터 개인화 사용 동의")
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "AI/ML 추천 개선 데이터 사용 동의", subtitle: "비식별 학습 반영", metrics: metrics) {
                    CoorditSettingsToggle(isOn: $aiDataConsent, metrics: metrics, label: "AI/ML 추천 개선 데이터 사용 동의")
                }
            }
        }
    }

    func appSettings(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "앱 버전", metrics: metrics) {
                    CoorditSettingsValuePill(text: CoorditAppSupport.versionText, metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "문의하기", subtitle: CoorditAppSupport.emailAddress, metrics: metrics, action: {
                    openSupportEmail()
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
            }
        }
    }

    func notifications(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "마케팅 알림", subtitle: "혜택과 이벤트", metrics: metrics) {
                    CoorditSettingsToggle(
                        isOn: marketingNotificationsBinding,
                        metrics: metrics,
                        label: "마케팅 알림"
                    )
                    .accessibilityIdentifier("mypage-marketing-notifications")
                }
            }

            CoorditSettingsStatusBanner(
                text: marketingNotificationStatusText,
                identifier: "mypage-marketing-notifications-status",
                metrics: metrics,
                isWarning: !marketingNotificationStatus.isAuthorized
            )

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(
                    title: "iPhone 알림 설정",
                    subtitle: "시스템 알림 허용 상태 변경",
                    metrics: metrics,
                    action: openNotificationSettings
                ) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                .accessibilityIdentifier("mypage-open-notification-settings")
            }
        }
        .task { await refreshMarketingNotificationStatus() }
    }

    var marketingNotificationsBinding: Binding<Bool> {
        Binding(
            get: { marketingNotifications && marketingNotificationStatus.isAuthorized },
            set: { requestedValue in
                Task { await updateMarketingNotifications(requestedValue) }
            }
        )
    }

    var marketingNotificationStatusText: String {
        switch marketingNotificationStatus {
        case .notDetermined:
            "알림을 켜면 iPhone 알림 권한을 요청해요."
        case .authorized:
            marketingNotifications
                ? "마케팅 알림이 켜져 있어요."
                : "iPhone 알림은 허용되어 있지만 마케팅 알림은 꺼져 있어요."
        case .unavailable:
            "iPhone 설정에서 COORDIT 알림을 허용해 주세요."
        }
    }

    func refreshMarketingNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = CoorditMarketingNotificationStatus(settings.authorizationStatus)
        marketingNotificationStatus = status
        if !status.isAuthorized {
            marketingNotifications = false
        }
    }

    func updateMarketingNotifications(_ requestedValue: Bool) async {
        guard requestedValue else {
            marketingNotifications = false
            return
        }

        let notificationCenter = UNUserNotificationCenter.current()
        let settings = await notificationCenter.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            isAuthorized = (try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        marketingNotifications = isAuthorized
        await refreshMarketingNotificationStatus()
    }

    func openNotificationSettings() {
        let urlString: String
        if #available(iOS 16.0, *) {
            urlString = UIApplication.openNotificationSettingsURLString
        } else {
            urlString = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    func openSupportEmail() {
        guard let url = CoorditAppSupport.composeEmailURL else { return }
        openURL(url)
    }
}

enum CoorditMarketingNotificationStatus {
    case notDetermined
    case authorized
    case unavailable

    init(_ authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .authorized, .provisional, .ephemeral:
            self = .authorized
        case .denied:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var isAuthorized: Bool {
        self == .authorized
    }
}

enum CoorditAppSupport {
    static let emailAddress = "hyu.coordit@gmail.com"

    static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "1.0.0")"
    }

    static var composeEmailURL: URL? {
        var components = URLComponents(string: "mailto:\(emailAddress)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "[COORDIT] 문의"),
            URLQueryItem(name: "body", value: "안녕하세요. COORDIT 사용 중 문의가 있어 연락드립니다.\n\n")
        ]
        return components?.url
    }
}
#endif
