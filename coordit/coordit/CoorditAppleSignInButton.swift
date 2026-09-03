import AuthenticationServices
import SwiftUI

#if os(iOS)
struct CoorditAppleSignInButton: View {
    let identifier: String
    let height: CGFloat
    let cornerRadius: CGFloat
    var onAuthenticated: () -> Void = {}

    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            rawNonce = CoorditAppleSignIn.prepare(request)
        } onCompletion: { result in
            Task {
                await backendSession.completeAppleLogin(result, rawNonce: rawNonce)
                guard backendSession.isMember else { return }
                onAuthenticated()
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 44))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .disabled(backendSession.isWorking)
        .accessibilityIdentifier(identifier)
        .task {
            guard backendSession.shouldAutomaticallyAuthenticateAppleForUITest else { return }
            await backendSession.loginWithApple()
            guard backendSession.isMember else { return }
            onAuthenticated()
        }
    }
}
#endif
