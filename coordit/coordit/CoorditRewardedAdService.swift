import Foundation
import UIKit
import Combine
import GoogleMobileAds

#if os(iOS)
@MainActor
final class CoorditRewardedAdService: NSObject, ObservableObject, FullScreenContentDelegate {
    enum Status: Equatable {
        case idle, loading, ready, presenting, awaitingServerSettlement, requiresLogin
        case failed(String)
        var message: String? {
            switch self {
            case .idle, .ready: nil
            case .loading: "광고를 준비하고 있어요."
            case .presenting: "광고를 표시하고 있어요."
            case .awaitingServerSettlement: "실타래 지급을 확인하고 있어요."
            case .requiresLogin: "광고 보상은 로그인 후 받을 수 있어요."
            case let .failed(message): message
            }
        }
    }
    @Published private(set) var status: Status = .idle
    private var rewardedAd: RewardedAd?
    var isReady: Bool { if case .ready = status { return true }; return false }

    func prepare(createAttempt: @escaping () async throws -> CoorditThreadRewardAttempt) async {
        guard rewardedAd == nil else { return }
        status = .loading
        do {
            let attempt = try await createAttempt()
            let ad = try await RewardedAd.load(with: Self.adUnitID, request: Request())
            let verification = ServerSideVerificationOptions()
            verification.customRewardText = attempt.attemptId
            ad.serverSideVerificationOptions = verification
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            status = .ready
        } catch let error as CoorditBackendClientError {
            if case .server(let code, _) = error, code == 401 { status = .requiresLogin }
            else { status = .failed(error.localizedDescription) }
        } catch { status = .failed("광고를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.") }
    }

    func present() {
        guard let rewardedAd, let viewController = Self.foregroundViewController() else {
            status = .failed("광고 화면을 열 수 없어요. 다시 시도해 주세요."); return
        }
        status = .presenting
        rewardedAd.present(from: viewController) { [weak self] in
            // The client only updates UI. The server credits after verified AdMob SSV.
            self?.status = .awaitingServerSettlement
        }
    }
    func finishServerSettlement() { rewardedAd = nil; status = .idle }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if status != .awaitingServerSettlement { rewardedAd = nil; status = .idle }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        rewardedAd = nil; status = .failed("광고를 표시하지 못했어요. 잠시 후 다시 시도해 주세요.")
    }
    private static var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        return Bundle.main.object(forInfoDictionaryKey: "CoorditAdMobRewardedAdUnitID") as? String ?? "ca-app-pub-7471774017488090/3769188728"
        #endif
    }
    private static func foregroundViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        return topViewController(from: scene?.keyWindow?.rootViewController)
    }
    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let nav = controller as? UINavigationController { return topViewController(from: nav.visibleViewController) }
        if let tab = controller as? UITabBarController { return topViewController(from: tab.selectedViewController) }
        if let presented = controller?.presentedViewController { return topViewController(from: presented) }
        return controller
    }
}
#endif
