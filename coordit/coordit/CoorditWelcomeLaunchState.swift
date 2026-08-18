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
        if let testingPresentation = testingPresentation(arguments: arguments) {
            return testingPresentation
        }

        return hasCompletedWelcome(defaults: defaults) && isAuthenticated
            ? .returningUser
            : .firstInstall
    }

    static func shouldAutomaticallyPresentAuthentication(
        isAuthenticated: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard !isAuthenticated else { return false }
        if let testingPresentation = testingPresentation(arguments: arguments) {
            return testingPresentation == .returningUser
        }
        return hasCompletedWelcome(defaults: defaults)
    }

    static func hasCompletedWelcome(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    static func markWelcomeCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    private static func testingPresentation(
        arguments: [String]
    ) -> CoorditSplashPresentation? {
        #if DEBUG
        guard arguments.contains("--coordit-ui-testing"),
              let markerIndex = arguments.firstIndex(of: "--coordit-welcome-state"),
              arguments.indices.contains(arguments.index(after: markerIndex))
        else { return nil }

        switch arguments[arguments.index(after: markerIndex)] {
        case "fresh":
            return .firstInstall
        case "returning":
            return .returningUser
        default:
            return nil
        }
        #else
        return nil
        #endif
    }
}
#endif
