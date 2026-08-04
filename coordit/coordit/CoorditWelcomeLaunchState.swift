import Foundation

#if os(iOS)
enum CoorditSplashPresentation: Equatable {
    case firstInstall
    case returningUser

    var allowsTapToEnter: Bool {
        self == .returningUser
    }
}

enum CoorditWelcomeLaunchState {
    private static let completedKey = "coordit.welcome.completed"

    static func splashPresentation(
        isAuthenticated: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> CoorditSplashPresentation {
        #if DEBUG
        if arguments.contains("--coordit-ui-testing"),
           let markerIndex = arguments.firstIndex(of: "--coordit-welcome-state"),
           arguments.indices.contains(arguments.index(after: markerIndex)) {
            switch arguments[arguments.index(after: markerIndex)] {
            case "fresh":
                return .firstInstall
            case "returning":
                return .returningUser
            default:
                break
            }
        }
        #endif

        return defaults.bool(forKey: completedKey) && isAuthenticated
            ? .returningUser
            : .firstInstall
    }

    static func markWelcomeCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }
}
#endif
