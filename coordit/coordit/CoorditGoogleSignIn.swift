import CryptoKit
import Foundation
import GoogleSignIn
import Security
import UIKit

#if os(iOS)
struct CoorditGoogleSignInCredentials {
    let idToken: String
    let nonce: String
}

enum CoorditGoogleSignInError: LocalizedError {
    case missingConfiguration
    case missingPresenter
    case missingIDToken
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Google 로그인 설정이 필요해요."
        case .missingPresenter:
            "Google 로그인 화면을 열 수 없어요."
        case .missingIDToken:
            "Google 로그인 토큰을 가져오지 못했어요."
        case .nonceGenerationFailed:
            "Google 로그인 보안 값을 만들지 못했어요. 다시 시도해 주세요."
        }
    }
}

enum CoorditGoogleSignIn {
    static var isConfigured: Bool {
        infoValue("GIDClientID") != nil && infoValue("GIDServerClientID") != nil
    }

    @MainActor
    static func signInIDToken() async throws -> CoorditGoogleSignInCredentials {
        guard isConfigured, let clientID = infoValue("GIDClientID") else {
            throw CoorditGoogleSignInError.missingConfiguration
        }

        let nonce = try makeNonce()
        let hashedNonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: infoValue("GIDServerClientID")
        )

        guard let presenter = UIApplication.shared.coorditTopViewController else {
            throw CoorditGoogleSignInError.missingPresenter
        }

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token = result?.user.idToken?.tokenString else {
                    continuation.resume(throwing: CoorditGoogleSignInError.missingIDToken)
                    return
                }

                continuation.resume(returning: CoorditGoogleSignInCredentials(idToken: token, nonce: nonce))
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

    private static func makeNonce() throws -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let status = randomBytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw CoorditGoogleSignInError.nonceGenerationFailed
        }

        return Data(randomBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
