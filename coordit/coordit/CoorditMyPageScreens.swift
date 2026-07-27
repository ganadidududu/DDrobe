import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
struct CoorditMyPageFamilyView: View {
    let route: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void

    @EnvironmentObject var backendSession: CoorditBackendSessionStore
    @State var feedDataConsent = true
    @State var aiDataConsent = false
    @State var marketingNotifications = false
    @State var selectedTheme: MyPageTheme = .system
    @State var selectedLanguage: MyPageLanguage = .korean
    @State var profileName = "코딧 사용자"
    @State var profileBio = "나에게 꼭 맞는 핏을 찾고 있어요."
    @State var profileAvatarIndex = 0
    @State var profileSaved = false
    @State var currentPassword = ""
    @State var newPassword = ""
    @State var confirmedPassword = ""
    @State var passwordChanged = false
    @State var logoutCompleted = false
    @State var deletionAcknowledged = false
    @State var deletionCompleted = false
    @State var shoulderMeasurement = "44.5"
    @State var chestMeasurement = "103.0"
    @State var waistMeasurement = "80.0"
    @State var hipMeasurement = "96.0"
    @State var inseamMeasurement = "78.0"
    @State var bodyMeasurementsSaved = false
    @State var contactSubject = ""
    @State var contactMessage = ""
    @State var contactSent = false
    @State var bugSummary = ""
    @State var bugSteps = ""
    @State var bugReportSent = false
    @State var backendEmail = ""
    @State var backendPassword = ""
    var body: some View {
        CoorditScreenScaffold(
            route: route,
            onRouteChange: onRouteChange,
            contentTop: 115,
            contentBottom: 0
        ) { metrics in
            VStack(spacing: 0) {
                pageHeader(
                    routeHeader.title,
                    metrics: metrics,
                    backRoute: routeHeader.backRoute
                )
                .frame(width: metrics.value(contentWidth))
                .frame(maxWidth: .infinity)

                ScrollView(.vertical, showsIndicators: false) {
                    routeContent(metrics: metrics)
                        .frame(width: metrics.value(contentWidth))
                        .frame(maxWidth: .infinity)
                        .padding(.top, metrics.value(routeHeader.spacing))
                        .padding(
                            .bottom,
                            metrics.value(Main01DesignTokens.Metrics.navHeight + 26)
                        )
                }
                .coorditScrollEdgeTreatment(topFade: metrics.value(18))
                .scrollDismissesKeyboard(.immediately)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("완료") {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                        }
                        .accessibilityIdentifier("coordit-keyboard-dismiss")
                    }
                }
            }
            .accessibilityIdentifier(routeIdentifier)
        }
        .task {
            await backendSession.bootstrap()
            syncBackendProfile()
            syncBackendBodyMeasurement()
        }
    }

    private var routeIdentifier: String {
        switch route {
        case .myPage:
            "coordit-screen-mypage"
        case .myPageThreadCharge:
            "coordit-screen-mypage-thread-charge"
        case .myPageBody:
            "coordit-screen-mypage-body"
        case .myPageAccount:
            "coordit-screen-mypage-account"
        case .myPagePrivacy:
            "coordit-screen-mypage-privacy"
        case .myPageAppSettings:
            "coordit-screen-mypage-app-settings"
        case .myPageNotifications:
            "coordit-screen-mypage-notifications"
        case .myPageProfileEdit:
            "coordit-screen-mypage-profile-edit"
        case .myPagePasswordChange:
            "coordit-screen-mypage-password-change"
        case .myPageLogout:
            "coordit-screen-mypage-logout"
        case .myPageAccountDeletion:
            "coordit-screen-mypage-account-deletion"
        case .myPageBodyMeasurements:
            "coordit-screen-mypage-body-measurements"
        case .myPagePrivacyPolicy:
            "coordit-screen-mypage-privacy-policy"
        case .myPageTerms:
            "coordit-screen-mypage-terms"
        case .myPageContact:
            "coordit-screen-mypage-contact"
        case .myPageBugReport:
            "coordit-screen-mypage-bug-report"
        default:
            "coordit-screen-mypage"
        }
    }

    @ViewBuilder
    private func routeContent(metrics: CoorditResponsiveMetrics) -> some View {
        switch route {
        case .myPage:
            myPageLanding(metrics: metrics, contentMetrics: compactContentMetrics(for: metrics))
        case .myPageThreadCharge:
            threadCharge(metrics: metrics, contentMetrics: compactContentMetrics(for: metrics))
        case .myPageBody:
            bodyInfo(metrics: metrics)
        case .myPageAccount:
            account(metrics: metrics)
        case .myPagePrivacy:
            privacy(metrics: metrics)
        case .myPageAppSettings:
            appSettings(metrics: metrics)
        case .myPageNotifications:
            notifications(metrics: metrics)
        case .myPageProfileEdit:
            profileEdit(metrics: metrics)
        case .myPagePasswordChange:
            passwordChange(metrics: metrics)
        case .myPageLogout:
            logout(metrics: metrics)
        case .myPageAccountDeletion:
            accountDeletion(metrics: metrics)
        case .myPageBodyMeasurements:
            bodyMeasurements(metrics: metrics)
        case .myPagePrivacyPolicy:
            privacyPolicy(metrics: metrics)
        case .myPageTerms:
            terms(metrics: metrics)
        case .myPageContact:
            contact(metrics: metrics)
        case .myPageBugReport:
            bugReport(metrics: metrics)
        default:
            myPageLanding(metrics: metrics, contentMetrics: compactContentMetrics(for: metrics))
        }
    }

    private var contentWidth: CGFloat {
        route == .myPageThreadCharge
            ? CoorditDesignTokens.ChargeMetrics.contentWidth
            : 370
    }

    private var routeHeader: (title: String, backRoute: CoorditFrameRoute, spacing: CGFloat) {
        switch route {
        case .myPage:
            ("MY PAGE", .main04, 10)
        case .myPageThreadCharge:
            (
                "실타래 충전",
                .myPage,
                CoorditDesignTokens.ChargeMetrics.titleToBalanceSpacing
            )
        case .myPageBody:
            ("내 신체 정보", .myPage, 27)
        case .myPageAccount:
            ("계정", .myPage, 18)
        case .myPagePrivacy:
            ("개인정보/보안", .myPage, 112)
        case .myPageAppSettings:
            ("앱 설정", .myPage, 112)
        case .myPageNotifications:
            ("알림", .myPage, 112)
        case .myPageProfileEdit:
            ("프로필 수정", .myPageAccount, 18)
        case .myPagePasswordChange:
            ("비밀번호 변경", .myPageAccount, 18)
        case .myPageLogout:
            ("로그아웃", .myPageAccount, 18)
        case .myPageAccountDeletion:
            ("회원 탈퇴", .myPageAccount, 18)
        case .myPageBodyMeasurements:
            ("신체 치수 관리", .myPageBody, 18)
        case .myPagePrivacyPolicy:
            ("개인정보 처리방침", .myPagePrivacy, 18)
        case .myPageTerms:
            ("서비스 이용약관", .myPagePrivacy, 18)
        case .myPageContact:
            ("문의하기", .myPageAppSettings, 18)
        case .myPageBugReport:
            ("버그 신고", .myPageAppSettings, 18)
        default:
            ("MY PAGE", .main04, 10)
        }
    }

    private func isCompactVerticalLayout(_ metrics: CoorditResponsiveMetrics) -> Bool {
        metrics.size.width <= 380 && metrics.size.height <= 700
    }

    private func compactContentMetrics(for metrics: CoorditResponsiveMetrics) -> CoorditResponsiveMetrics {
        guard isCompactVerticalLayout(metrics) else { return metrics }

        return CoorditResponsiveMetrics(
            size: CGSize(width: metrics.size.width * 0.78, height: metrics.size.height)
        )
    }

    private func myPageLanding(
        metrics: CoorditResponsiveMetrics,
        contentMetrics: CoorditResponsiveMetrics
    ) -> some View {
        VStack(spacing: contentMetrics.value(10)) {
            if backendSession.isAuthenticated {
                myPageYarnBalanceCard(metrics: contentMetrics)
            } else {
                myPageLoginEntry(metrics: contentMetrics)
            }

            VStack(spacing: contentMetrics.value(10)) {
                CoorditSettingsMenuRow(
                    title: "계정",
                    subtitle: "프로필, 이메일, 비밀번호, 로그아웃",
                    assetName: CoorditAssetNames.mypageAccount,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPageAccount)
                }

                CoorditSettingsMenuRow(
                    title: "내 신체 정보",
                    subtitle: "키, 몸무게, 성별, 체수, 단위",
                    assetName: CoorditAssetNames.mypageBody,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPageBody)
                }

                CoorditSettingsMenuRow(
                    title: "알림",
                    subtitle: "구매 후 피드백, 재확인, 리포트",
                    assetName: CoorditAssetNames.mypageNotifications,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPageNotifications)
                }

                CoorditSettingsMenuRow(
                    title: "개인정보/보안",
                    subtitle: "정책, 약관, 데이터 동의",
                    assetName: CoorditAssetNames.mypagePrivacy,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPagePrivacy)
                }

                CoorditSettingsMenuRow(
                    title: "앱 설정",
                    subtitle: "테마, 언어, 버전, 문의, 신고",
                    assetName: CoorditAssetNames.mypageSettings,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPageAppSettings)
                }
            }
            .padding(.top, contentMetrics.value(19))
        }
    }

    private func myPageYarnBalanceCard(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsCard(metrics: metrics) {
            HStack(spacing: metrics.value(12)) {
                Image(CoorditAssetNames.yarn)
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.value(48), height: metrics.value(48))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text("보유 실타래")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(CoorditSettingsStyle.muted)
                    Text("36 실타래")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(20), relativeTo: .title3))
                        .foregroundStyle(CoorditSettingsStyle.ink)
                }

                Spacer(minLength: 0)

                Button {
                    onRouteChange(.myPageThreadCharge)
                } label: {
                    Text("충전")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .headline))
                        .foregroundStyle(.white)
                        .frame(
                            minWidth: max(metrics.value(62), 44),
                            minHeight: max(metrics.value(44), 44)
                        )
                        .background(CoorditSettingsStyle.ink)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
                }
                .coorditPressFeedback()
                .contentShape(Rectangle())
                .accessibilityIdentifier("mypage-yarn-charge")
            }
            .padding(.horizontal, metrics.value(13))
        }
        .padding(.top, metrics.value(18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mypage-yarn-balance-card")
    }

    private func myPageLoginEntry(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditSettingsCard(metrics: metrics) {
            VStack(alignment: .leading, spacing: metrics.value(13)) {
                HStack(spacing: metrics.value(10)) {
                    Image(systemName: backendSession.isAuthenticated ? "checkmark.seal.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: metrics.value(21), weight: .semibold))
                        .foregroundStyle(CoorditSettingsStyle.ink)
                        .frame(width: metrics.value(32), height: metrics.value(32))

                    VStack(alignment: .leading, spacing: metrics.value(4)) {
                        Text(backendSession.isAuthenticated ? backendSession.displayNameText : "로그인하고 내 핏 기록을 이어가세요")
                            .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .subheadline))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(backendSession.isAuthenticated ? backendSession.emailText : "계정으로 신체 정보와 추천 기록을 저장해요")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                            .foregroundStyle(CoorditSettingsStyle.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                CoorditSettingsPrimaryButton(
                    title: backendSession.isAuthenticated ? "계정 관리" : "로그인 / 회원가입",
                    identifier: "mypage-login-entry",
                    metrics: metrics
                ) {
                    onRouteChange(.myPageAccount)
                }
            }
            .padding(.horizontal, metrics.value(13))
        }
        .padding(.top, metrics.value(18))
    }

    private func account(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            backendConnectionStatus(metrics: metrics)
            backendAuthControls(metrics: metrics)

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "프로필 수정", subtitle: "이름, 사진, 기본 소개", metrics: metrics, action: {
                    onRouteChange(.myPageProfileEdit)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "이메일 확인", metrics: metrics) {
                    CoorditSettingsValuePill(text: backendSession.emailText, metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "비밀번호 변경", subtitle: "마지막 변경 32일 전", metrics: metrics, action: {
                    onRouteChange(.myPagePasswordChange)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "로그아웃", subtitle: "현재 기기에서 로그아웃", metrics: metrics, action: {
                    onRouteChange(.myPageLogout)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "회원 탈퇴", subtitle: "계정 및 데이터 삭제", metrics: metrics, titleColor: CoorditSettingsStyle.danger, action: {
                    onRouteChange(.myPageAccountDeletion)
                }) {
                    CoorditSettingsChevron(metrics: metrics, color: CoorditSettingsStyle.danger)
                }
            }
        }
    }

    private func bodyInfo(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(27)) {
            backendConnectionStatus(metrics: metrics)

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "키", metrics: metrics) {
                    CoorditSettingsValuePill(text: "미등록", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "몸무게", metrics: metrics) {
                    CoorditSettingsValuePill(text: "미등록", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "성별", metrics: metrics) {
                    CoorditSettingsValuePill(text: "남성", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "출생연도", metrics: metrics) {
                    CoorditSettingsValuePill(text: "1996", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "신체 치수 관리", subtitle: "어깨, 가슴, 허리 등", metrics: metrics, action: {
                    onRouteChange(.myPageBodyMeasurements)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
            }
        }
    }

    func pageHeader(
        _ title: String,
        metrics: CoorditResponsiveMetrics,
        backRoute: CoorditFrameRoute = .myPage
    ) -> some View {
        CoorditSettingsHeaderCard(title: title, metrics: metrics) {
            onRouteChange(backRoute)
        }
    }

}
#endif
