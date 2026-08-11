import Foundation
import GoogleSignIn
import UIKit

#if os(iOS)
enum CoorditGoogleSignInError: LocalizedError {
    case missingConfiguration
    case missingPresenter
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Google 로그인 설정이 필요해요."
        case .missingPresenter:
            "Google 로그인 화면을 열 수 없어요."
        case .missingIDToken:
            "Google 로그인 토큰을 가져오지 못했어요."
        }
    }
}

struct CoorditGoogleSignInCredential {
    let idToken: String
    let nonce: String
}

enum CoorditGoogleSignIn {
    static var isConfigured: Bool {
        infoValue("GIDClientID") != nil && infoValue("GIDServerClientID") != nil
    }

    @MainActor
    static func signInCredential() async throws -> CoorditGoogleSignInCredential {
        guard isConfigured, let clientID = infoValue("GIDClientID") else {
            throw CoorditGoogleSignInError.missingConfiguration
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: infoValue("GIDServerClientID")
        )

        guard let presenter = UIApplication.shared.coorditTopViewController else {
            throw CoorditGoogleSignInError.missingPresenter
        }

        let nonce = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token = result?.user.idToken?.tokenString else {
                    continuation.resume(throwing: CoorditGoogleSignInError.missingIDToken)
                    return
                }

                continuation.resume(returning: CoorditGoogleSignInCredential(idToken: token, nonce: nonce))
            }
        }
    }

    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }

        return trimmed
    }
}

private extension UIApplication {
    var coorditTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .coorditTopPresentedViewController
    }
}

private extension UIViewController {
    var coorditTopPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.coorditTopPresentedViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.coorditTopPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.coorditTopPresentedViewController
        }

        return self
    }
}
#endif
