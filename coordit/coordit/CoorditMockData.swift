import Foundation

#if os(iOS)
struct CoorditRouteContent {
    let eyebrow: String
    let title: String
    let detail: String
}

enum CoorditMockData {
    static func content(for route: CoorditFrameRoute) -> CoorditRouteContent {
        switch route {
        case .main01:
            CoorditRouteContent(eyebrow: "HOME", title: "Main 01", detail: route.rawValue)
        case .splash:
            CoorditRouteContent(eyebrow: "START", title: "Splash", detail: route.rawValue)
        case .main04:
            CoorditRouteContent(eyebrow: "HOME", title: "Today Coordination", detail: route.rawValue)
        case .fitLabInput:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "Fit Lab Input", detail: route.rawValue)
        case .fitLabLoading:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "Analyzing Fit", detail: route.rawValue)
        case .fitLabResultTop:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "Top Fit Result", detail: route.rawValue)
        case .fitLabResultBottom:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "Bottom Fit Result", detail: route.rawValue)
        case .fitLabHistoryRegister:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "Register History", detail: route.rawValue)
        case .fitLabHistoryDetail:
            CoorditRouteContent(eyebrow: "FIT LAB", title: "History Detail", detail: route.rawValue)
        case .myPage:
            CoorditRouteContent(eyebrow: "MY", title: "My Page", detail: route.rawValue)
        case .myPageThreadCharge:
            CoorditRouteContent(eyebrow: "MY", title: "Thread Charge", detail: route.rawValue)
        case .myPageBody:
            CoorditRouteContent(eyebrow: "MY", title: "Body Profile", detail: route.rawValue)
        case .myPageAccount:
            CoorditRouteContent(eyebrow: "MY", title: "Account", detail: route.rawValue)
        case .myPagePrivacy:
            CoorditRouteContent(eyebrow: "MY", title: "Privacy", detail: route.rawValue)
        case .myPageAppSettings:
            CoorditRouteContent(eyebrow: "MY", title: "App Settings", detail: route.rawValue)
        case .myPageNotifications:
            CoorditRouteContent(eyebrow: "MY", title: "Notifications", detail: route.rawValue)
        case .myPageProfileEdit:
            CoorditRouteContent(eyebrow: "MY", title: "Edit Profile", detail: route.rawValue)
        case .myPagePasswordChange:
            CoorditRouteContent(eyebrow: "MY", title: "Change Password", detail: route.rawValue)
        case .myPageLogout:
            CoorditRouteContent(eyebrow: "MY", title: "Log Out", detail: route.rawValue)
        case .myPageAccountDeletion:
            CoorditRouteContent(eyebrow: "MY", title: "Delete Account", detail: route.rawValue)
        case .myPageBodyMeasurements:
            CoorditRouteContent(eyebrow: "MY", title: "Body Measurements", detail: route.rawValue)
        case .myPagePrivacyPolicy:
            CoorditRouteContent(eyebrow: "MY", title: "Privacy Policy", detail: route.rawValue)
        case .myPageTerms:
            CoorditRouteContent(eyebrow: "MY", title: "Terms of Service", detail: route.rawValue)
        case .closetOverview:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Closet Overview", detail: route.rawValue)
        case .closetDetailTop:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Top Detail", detail: route.rawValue)
        case .closetDetailBottom:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Bottom Detail", detail: route.rawValue)
        case .closetAddMethod:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Choose Add Method", detail: route.rawValue)
        case .closetAddLink:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Link Input", detail: route.rawValue)
        case .closetAddPhoto:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Photo Input", detail: route.rawValue)
        case .closetAddManual:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Manual Input", detail: route.rawValue)
        case .closetAddLoading:
            CoorditRouteContent(eyebrow: "CLOSET", title: "Analyzing Garment", detail: route.rawValue)
        case .closetAddResult:
            CoorditRouteContent(eyebrow: "CLOSET", title: "New Garment Detail", detail: route.rawValue)
        }
    }
}
#endif
