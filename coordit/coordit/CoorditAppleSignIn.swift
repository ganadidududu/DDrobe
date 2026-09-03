import AuthenticationServices
import CryptoKit
import UIKit

#if os(iOS)
enum CoorditAppleSignInError: LocalizedError {
    case authorizationInProgress
    case missingPresentationAnchor
    case missingIdentityToken
    case cancelled

    var errorDescription: String? {
        switch self {
        case .authorizationInProgress:
            "Apple 로그인이 이미 진행 중이에요."
        case .missingPresentationAnchor:
            "Apple 로그인 화면을 열 수 없어요."
        case .missingIdentityToken:
            "Apple 로그인 토큰을 가져오지 못했어요."
        case .cancelled:
            "Apple 로그인이 취소되었어요."
        }
    }
}

@MainActor
enum CoorditAppleSignIn {
    private static var activeCoordinator: Coordinator?

    static func signInCredential() async throws -> CoorditAppleSignInCredential {
        guard activeCoordinator == nil else {
            throw CoorditAppleSignInError.authorizationInProgress
        }
        guard let anchor = UIApplication.shared.coorditApplePresentationAnchor else {
            throw CoorditAppleSignInError.missingPresentationAnchor
        }

        return try await withCheckedThrowingContinuation { continuation in
            let rawNonce = UUID().uuidString
            let coordinator = Coordinator(anchor: anchor, rawNonce: rawNonce) { result in
                activeCoordinator = nil
                continuation.resume(with: result)
            }
            activeCoordinator = coordinator

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = SHA256.hash(data: Data(rawNonce.utf8))
                .map { String(format: "%02x", $0) }
                .joined()

            let controller = ASAuthorizationController(authorizationRequests: [request])
            coordinator.controller = controller
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }

    static func prepare(_ request: ASAuthorizationAppleIDRequest) -> String {
        let rawNonce = UUID().uuidString
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return rawNonce
    }

    static func credential(
        from result: Result<ASAuthorization, Error>,
        rawNonce: String
    ) throws -> CoorditAppleSignInCredential {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            throw CoorditAppleSignInError.missingIdentityToken
        }
        return CoorditAppleSignInCredential(idToken: token, nonce: rawNonce)
    }

    private final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let anchor: ASPresentationAnchor
        let rawNonce: String
        let completion: (Result<CoorditAppleSignInCredential, Error>) -> Void
        var controller: ASAuthorizationController?

        init(
            anchor: ASPresentationAnchor,
            rawNonce: String,
            completion: @escaping (Result<CoorditAppleSignInCredential, Error>) -> Void
        ) {
            self.anchor = anchor
            self.rawNonce = rawNonce
            self.completion = completion
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            anchor
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.isEmpty else {
                completion(.failure(CoorditAppleSignInError.missingIdentityToken))
                return
            }
            completion(.success(CoorditAppleSignInCredential(idToken: token, nonce: rawNonce)))
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                completion(.failure(CoorditAppleSignInError.cancelled))
                return
            }
            completion(.failure(error))
        }
    }
}

struct CoorditAppleSignInCredential {
    let idToken: String
    let nonce: String
}

private extension UIApplication {
    var coorditApplePresentationAnchor: ASPresentationAnchor? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
