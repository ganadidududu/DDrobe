import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
@main
struct coorditApp: App {
    @StateObject private var backendSession = CoorditBackendSessionStore()

    init() {
        CoorditFontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendSession)
                .background(CoorditTouchResponsivenessTuner())
                .onOpenURL { url in
                    if CoorditSharedFitLabImport.isOpenURL(url) {
                        let productURL = CoorditSharedFitLabImport.productURL(fromOpenURL: url)
                        if let productURL {
                            CoorditSharedFitLabImport.store(
                                productURL: productURL,
                                sourceApplication: "url-scheme"
                            )
                        }
                        CoorditSharedFitLabImport.postOpenRequest(productURL: productURL)
                    } else {
                        _ = CoorditGoogleSignIn.handle(url)
                    }
                }
        }
    }
}

private struct CoorditTouchResponsivenessTuner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        scheduleTune(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        scheduleTune(from: uiView)
    }

    private func scheduleTune(from view: UIView) {
        [0.0, 0.08, 0.22, 0.55, 1.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                tuneAllScrollViews(near: view)
            }
        }
    }

    private func tuneAllScrollViews(near view: UIView) {
        guard let rootView = view.window ?? view.superview?.window else { return }
        tuneScrollViews(in: rootView)
    }

    private func tuneScrollViews(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.delaysContentTouches = false
            scrollView.canCancelContentTouches = true
        }

        for subview in view.subviews {
            tuneScrollViews(in: subview)
        }
    }
}
#endif
