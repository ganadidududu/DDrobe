import Foundation

#if os(iOS)
enum CoorditFrameRoute: String, CaseIterable, Identifiable {
    case main01
    case splash
    case main04
    case fitLabInput = "fitlab-input"
    case fitLabLoading = "fitlab-loading"
    case fitLabResultTop = "fitlab-result-top"
    case fitLabResultBottom = "fitlab-result-bottom"
    case fitLabHistoryRegister = "fitlab-history-register"
    case fitLabHistoryDetail = "fitlab-history-detail"
    case myPage = "mypage"
    case myPageThreadCharge = "mypage-thread-charge"
    case myPageBody = "mypage-body"
    case myPageAccount = "mypage-account"
    case myPagePrivacy = "mypage-privacy"
    case myPageAppSettings = "mypage-app-settings"
    case myPageNotifications = "mypage-notifications"
    case myPageProfileEdit = "mypage-profile-edit"
    case myPagePasswordChange = "mypage-password-change"
    case myPageLogout = "mypage-logout"
    case myPageAccountDeletion = "mypage-account-deletion"
    case myPageBodyMeasurements = "mypage-body-measurements"
    case myPagePrivacyPolicy = "mypage-privacy-policy"
    case myPageTerms = "mypage-terms"
    case myPageContact = "mypage-contact"
    case myPageBugReport = "mypage-bug-report"
    case closetOverview = "closet-overview"
    case closetDetailTop = "closet-detail-top"
    case closetDetailBottom = "closet-detail-bottom"
    case closetAddMethod = "closet-add-method"
    case closetAddLink = "closet-add-link"
    case closetAddPhoto = "closet-add-photo"
    case closetAddManual = "closet-add-manual"
    case closetAddLoading = "closet-add-loading"
    case closetAddResult = "closet-add-result"

    var id: Self { self }

    static func testingLaunchRoute(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        #if DEBUG
        guard arguments.contains("--coordit-ui-testing") else { return .splash }
        guard
            let markerIndex = arguments.firstIndex(of: "--coordit-start-route"),
            arguments.indices.contains(arguments.index(after: markerIndex))
        else {
            return .splash
        }

        let routeValue = arguments[arguments.index(after: markerIndex)]
        return Self(rawValue: routeValue) ?? .splash
        #else
        return .splash
        #endif
    }

    var visibleIdentifier: String {
        switch self {
        case .main01:
            "main01-screen"
        case .main04, .fitLabInput, .closetOverview:
            "coordit-screen-\(rawValue)"
        case .splash,
             .fitLabLoading,
             .fitLabResultTop,
             .fitLabResultBottom,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail,
             .myPage,
             .myPageThreadCharge,
             .myPageBody,
             .myPageAccount,
             .myPagePrivacy,
             .myPageAppSettings,
             .myPageNotifications,
             .myPageProfileEdit,
             .myPagePasswordChange,
             .myPageLogout,
             .myPageAccountDeletion,
             .myPageBodyMeasurements,
             .myPagePrivacyPolicy,
             .myPageTerms,
             .myPageContact,
             .myPageBugReport,
             .closetDetailTop,
             .closetDetailBottom,
             .closetAddMethod,
             .closetAddLink,
             .closetAddPhoto,
             .closetAddManual,
             .closetAddLoading,
             .closetAddResult:
            "coordit-route-placeholder"
        }
    }

    var selectedTab: Main01Tab? {
        switch self {
        case .main01, .main04, .splash:
            .home
        case .fitLabInput,
             .fitLabLoading,
             .fitLabResultTop,
             .fitLabResultBottom,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail:
            .fitLab
        case .closetOverview,
             .closetDetailTop,
             .closetDetailBottom,
             .closetAddMethod,
             .closetAddLink,
             .closetAddPhoto,
             .closetAddManual,
             .closetAddLoading,
             .closetAddResult:
            .closet
        case .myPage,
             .myPageThreadCharge,
             .myPageBody,
             .myPageAccount,
             .myPagePrivacy,
             .myPageAppSettings,
             .myPageNotifications,
             .myPageProfileEdit,
             .myPagePasswordChange,
             .myPageLogout,
             .myPageAccountDeletion,
             .myPageBodyMeasurements,
             .myPagePrivacyPolicy,
             .myPageTerms,
             .myPageContact,
             .myPageBugReport:
            nil
        }
    }

    static func route(for tab: Main01Tab, from currentRoute: Self = .main04) -> Self {
        switch tab {
        case .home:
            currentRoute == .main01 ? .main01 : .main04
        case .fitLab:
            .fitLabInput
        case .closet:
            .closetOverview
        }
    }

    var navigationSection: Int {
        switch self {
        case .main01, .splash, .main04:
            0
        case .fitLabInput,
             .fitLabLoading,
             .fitLabResultTop,
             .fitLabResultBottom,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail:
            1
        case .closetOverview,
             .closetDetailTop,
             .closetDetailBottom,
             .closetAddMethod,
             .closetAddLink,
             .closetAddPhoto,
             .closetAddManual,
             .closetAddLoading,
             .closetAddResult:
            2
        case .myPage,
             .myPageThreadCharge,
             .myPageBody,
             .myPageAccount,
             .myPagePrivacy,
             .myPageAppSettings,
             .myPageNotifications,
             .myPageProfileEdit,
             .myPagePasswordChange,
             .myPageLogout,
             .myPageAccountDeletion,
             .myPageBodyMeasurements,
             .myPagePrivacyPolicy,
             .myPageTerms,
             .myPageContact,
             .myPageBugReport:
            3
        }
    }

    var navigationDepth: Int {
        switch self {
        case .main01, .splash, .main04, .fitLabInput, .closetOverview, .myPage:
            0
        case .fitLabLoading,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail,
             .closetDetailTop,
             .closetDetailBottom,
             .closetAddMethod,
             .myPageThreadCharge,
             .myPageBody,
             .myPageAccount,
             .myPagePrivacy,
             .myPageAppSettings,
             .myPageNotifications:
            1
        case .fitLabResultTop,
             .fitLabResultBottom,
             .closetAddLink,
             .closetAddPhoto,
             .closetAddManual,
             .myPageProfileEdit,
             .myPagePasswordChange,
             .myPageLogout,
             .myPageAccountDeletion,
             .myPageBodyMeasurements,
             .myPagePrivacyPolicy,
             .myPageTerms,
             .myPageContact,
             .myPageBugReport:
            2
        case .closetAddLoading:
            3
        case .closetAddResult:
            4
        }
    }
}
#endif
