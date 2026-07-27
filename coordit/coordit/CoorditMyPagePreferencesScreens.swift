import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func privacy(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(112)) {
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
        VStack(spacing: metrics.value(112)) {
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "테마", metrics: metrics) {
                    CoorditSettingsSegmentedOptions(
                        options: MyPageTheme.allCases,
                        selection: $selectedTheme,
                        width: 113,
                        metrics: metrics
                    )
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "언어", metrics: metrics) {
                    CoorditSettingsSegmentedOptions(
                        options: MyPageLanguage.allCases,
                        selection: $selectedLanguage,
                        width: 78,
                        metrics: metrics
                    )
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "앱 버전", metrics: metrics) {
                    CoorditSettingsValuePill(text: "v1.0.0 beta", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "문의하기", subtitle: "support@coordit.app", metrics: metrics, action: {
                    onRouteChange(.myPageContact)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "버그 신고", subtitle: "문제 화면과 로그 첨부", metrics: metrics, action: {
                    onRouteChange(.myPageBugReport)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
            }
        }
    }

    func notifications(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(112)) {
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "마케팅 알림", subtitle: "혜택과 이벤트", metrics: metrics) {
                    CoorditSettingsToggle(isOn: $marketingNotifications, metrics: metrics, label: "마케팅 알림")
                }
            }
        }
    }
}

enum MyPageTheme: String, CaseIterable, Identifiable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var id: Self { self }
}

enum MyPageLanguage: String, CaseIterable, Identifiable {
    case korean = "한국어"
    case english = "ENG"

    var id: Self { self }
}

private struct CoorditSettingsSegmentedOptions<Option>: View
where Option: CaseIterable & Hashable & RawRepresentable & Identifiable,
      Option.RawValue == String,
      Option.AllCases: RandomAccessCollection {
    let options: Option.AllCases
    @Binding var selection: Option
    let width: CGFloat
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.rawValue)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(7), relativeTo: .caption2))
                        .foregroundStyle(selection == option ? .white : CoorditSettingsStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.value(23))
                        .background(selection == option ? CoorditSettingsStyle.ink : Color.clear)
                        .clipShape(Capsule())
                }
                .coorditPressFeedback()
            }
        }
        .padding(metrics.value(2))
        .frame(width: metrics.value(width), height: metrics.value(27))
        .background(CoorditSettingsStyle.field)
        .clipShape(Capsule())
    }
}
#endif
