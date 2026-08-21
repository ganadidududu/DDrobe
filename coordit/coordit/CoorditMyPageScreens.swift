import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
struct CoorditMyPageFamilyView: View {
    let route: CoorditFrameRoute
    @Binding var threadBalance: Int
    @Binding var showsThreadRechargePrompt: Bool
    let onAccountDeleted: (String) async -> Bool
    let onRouteChange: (CoorditFrameRoute) -> Void

    @EnvironmentObject var backendSession: CoorditBackendSessionStore
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase
    @State var feedDataConsent = true
    @State var aiDataConsent = false
    @AppStorage("coordit.marketing-notifications.enabled") var marketingNotifications = false
    @State var marketingNotificationStatus: CoorditMarketingNotificationStatus = .notDetermined
    @State var profileName = "코딧 사용자"
    @State var profileBio = "나에게 꼭 맞는 핏을 찾고 있어요."
    @State var profileAvatarIndex = 0
    @State var profileSaved = false
    @State var logoutCompleted = false
    @State var deletionAcknowledged = false
    @State var deletionCompleted = false
    @State var deletionLocalCleanupFailed = false
    @State var heightMeasurement = ""
    @State var weightMeasurement = ""
    @State var bodyMeasurementsSaved = false
    @State var bodyMeasurementSaveError = ""
    @StateObject var rewardedAdService = CoorditRewardedAdService()
    @StateObject var threadPurchaseService = CoorditThreadPurchaseService()
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
        .overlay {
            if route == .myPageThreadCharge, showsThreadRechargePrompt {
                CoorditThreadRechargeRequiredPopup {
                    showsThreadRechargePrompt = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }

        .task {
            await backendSession.bootstrap()
            syncBackendProfile()
            syncBackendBodyMeasurement()
        }
        .onChange(of: backendSession.latestBodyMeasurement) { _, _ in
            syncBackendBodyMeasurement()
        }
        .onChange(of: scenePhase) { _, phase in
            guard route == .myPageNotifications, phase == .active else { return }
            Task { await refreshMarketingNotificationStatus() }
        }
        .task(id: route) {
            guard route == .myPageThreadCharge else { return }
            await refreshChargeServices()
        }
        .onChange(of: route) { _, nextRoute in
            guard nextRoute != .myPageThreadCharge else { return }
            rewardedAdService.deactivate()
            threadPurchaseService.deactivate()
        }
        .onChange(of: threadPurchaseService.settledBalance) { _, balance in
            guard route == .myPageThreadCharge, let balance else { return }
            threadBalance = balance
        }
        .onChange(of: rewardedAdService.settledBalance) { _, balance in
            guard route == .myPageThreadCharge, let balance else { return }
            threadBalance = balance
        }
    }


    func prepareRewardedAd() async {
        let sessionStore = backendSession
        let walletSession = CoorditRewardedWalletSession(
            isAuthenticated: sessionStore.isAuthenticated,
            rewardedAdsEnabled: sessionStore.canUseRewardedAds,
            createAttempt: {
                try await sessionStore.createThreadRewardAttempt()
            },
            fetchServerBalance: {
                guard let balance = await sessionStore.fetchThreadBalance() else {
                    throw CoorditBackendClientError.invalidResponse
                }
                return balance
            }
        )
        await rewardedAdService.prepare(
            walletSession: walletSession,
            currentBalance: threadBalance
        )
    }

    func refreshChargeServices() async {
        let readiness = await backendSession.refreshMonetizationReadiness()
        guard !Task.isCancelled else { return }

        if readiness?.iapEnabled == true {
            await prepareThreadPurchases()
        } else {
            threadPurchaseService.deactivate(clearProducts: true)
        }

        guard backendSession.isAuthenticated else {
            rewardedAdService.markSignedOut()
            return
        }
        guard let readiness else {
            rewardedAdService.markReadinessUnavailable()
            return
        }
        guard readiness.rewardedAdsEnabled else {
            rewardedAdService.markDisabled()
            return
        }
        await prepareRewardedAd()
    }

    private func prepareThreadPurchases() async {
        guard
            let userID = backendSession.session?.user.id,
            let accountID = UUID(uuidString: userID)
        else {
            threadPurchaseService.markAccountUnavailable()
            return
        }
        let sessionStore = backendSession
        await threadPurchaseService.activate(
            accountID: accountID,
            verifyPurchase: { signedTransaction in
                try await sessionStore.settleAppleIapPurchase(
                    signedTransaction: signedTransaction
                )
            },
            refreshBalance: {
                try await sessionStore.fetchThreadBalanceAfterPurchase()
            }
        )
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
            threadCharge(
                metrics: metrics,
                contentMetrics: compactContentMetrics(for: metrics),
                threadBalance: threadBalance
            )
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
            ("개인정보/보안", .myPage, 18)
        case .myPageAppSettings:
            ("앱 설정", .myPage, 0)
        case .myPageNotifications:
            ("알림", .myPage, 0)
        case .myPageProfileEdit:
            ("프로필 수정", .myPageAccount, 18)
        case .myPagePasswordChange:
            ("비밀번호 변경", .myPageAccount, 18)
        case .myPageLogout:
            ("로그아웃", .myPageAccount, 18)
        case .myPageAccountDeletion:
            ("회원 탈퇴", .myPageAccount, 18)
        case .myPageBodyMeasurements:
            ("신체 정보 수정", .myPageBody, 18)
        case .myPagePrivacyPolicy:
            ("개인정보 처리방침", .myPagePrivacy, 18)
        case .myPageTerms:
            ("서비스 이용약관", .myPagePrivacy, 18)
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
            myPageYarnBalanceCard(metrics: contentMetrics)

            VStack(spacing: contentMetrics.value(10)) {
                CoorditSettingsMenuRow(
                    title: "계정",
                    subtitle: "프로필, 연결 계정, 로그아웃",
                    assetName: CoorditAssetNames.mypageAccount,
                    metrics: contentMetrics
                ) {
                    onRouteChange(.myPageAccount)
                }

                CoorditSettingsMenuRow(
                    title: "내 신체 정보",
                    subtitle: "키, 몸무게, 성별, 생일",
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
                    subtitle: "알림, 버전, 문의",
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
                    Text("\(threadBalance) 실타래")
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

    private func account(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            backendAuthControls(metrics: metrics)

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "프로필 수정", subtitle: "이름, 사진, 기본 소개", metrics: metrics, action: {
                    onRouteChange(.myPageProfileEdit)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
                if backendSession.isAuthenticated {
                    CoorditSettingsDivider(metrics: metrics)
                    CoorditSettingsDetailRow(title: "연결 계정", metrics: metrics) {
                        CoorditSettingsValuePill(text: backendSession.emailText, metrics: metrics)
                    }
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
            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDetailRow(title: "키", metrics: metrics) {
                    CoorditSettingsValuePill(
                        text: backendSession.latestBodyMeasurement?.heightCm.map { "\(Int($0)) cm" } ?? "미등록",
                        metrics: metrics
                    )
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "몸무게", metrics: metrics) {
                    CoorditSettingsValuePill(
                        text: backendSession.latestBodyMeasurement?.weightKg.map { "\(Int($0)) kg" } ?? "미등록",
                        metrics: metrics
                    )
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "성별", metrics: metrics) {
                    CoorditSettingsValuePill(text: genderLabel, metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "생일", metrics: metrics) {
                    CoorditSettingsValuePill(text: backendSession.profile?.birthDate ?? "미등록", metrics: metrics)
                }
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDetailRow(title: "신체 정보 수정", subtitle: "키와 몸무게 수정", metrics: metrics, action: {
                    onRouteChange(.myPageBodyMeasurements)
                }) {
                    CoorditSettingsChevron(metrics: metrics)
                }
            }
        }
    }

    private var genderLabel: String {
        switch backendSession.profile?.gender {
        case "female": "여성"
        case "male": "남성"
        case "prefer_not_to_say": "응답하지 않음"
        default: "미등록"
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
