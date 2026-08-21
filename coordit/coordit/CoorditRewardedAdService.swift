import Combine
import Foundation
import GoogleMobileAds
import UIKit

#if os(iOS)
struct CoorditRewardedWalletSession {
    let isAuthenticated: Bool
    let rewardedAdsEnabled: Bool
    let createAttempt: () async throws -> CoorditThreadRewardAttempt
    let fetchServerBalance: () async throws -> Int
}

@MainActor
protocol CoorditRewardedAdPresenting: AnyObject {
    var customRewardText: String { get }

    func present(
        from viewController: UIViewController,
        userDidEarnReward: @escaping () -> Void
    )
}

@MainActor
protocol CoorditRewardedAdLoading: AnyObject {
    func load(
        adUnitID: String,
        customRewardText: String,
        delegate: FullScreenContentDelegate
    ) async throws -> any CoorditRewardedAdPresenting
}

@MainActor
private final class CoorditGoogleRewardedAdLoader: CoorditRewardedAdLoading {
    func load(
        adUnitID: String,
        customRewardText: String,
        delegate: FullScreenContentDelegate
    ) async throws -> any CoorditRewardedAdPresenting {
        let ad = try await RewardedAd.load(with: adUnitID, request: Request())
        let verification = ServerSideVerificationOptions()
        verification.customRewardText = customRewardText
        ad.serverSideVerificationOptions = verification
        ad.fullScreenContentDelegate = delegate
        return CoorditGoogleRewardedAdPresenter(
            ad: ad,
            customRewardText: customRewardText
        )
    }
}

@MainActor
private final class CoorditGoogleRewardedAdPresenter: CoorditRewardedAdPresenting {
    let customRewardText: String
    private let ad: RewardedAd

    init(ad: RewardedAd, customRewardText: String) {
        self.ad = ad
        self.customRewardText = customRewardText
    }

    func present(
        from viewController: UIViewController,
        userDidEarnReward: @escaping () -> Void
    ) {
        ad.present(from: viewController, userDidEarnRewardHandler: userDidEarnReward)
    }
}

@MainActor
final class CoorditRewardedAdService: NSObject, ObservableObject, FullScreenContentDelegate {
    enum Status: Equatable {
        case idle
        case disabled
        case readinessUnavailable
        case loading
        case ready
        case presenting
        case awaitingServerSettlement
        case settled
        case requiresLogin
        case failed(String)

        var message: String? {
            switch self {
            case .idle, .ready:
                nil
            case .disabled:
                "광고 충전은 아직 준비 중이에요."
            case .readinessUnavailable:
                "광고 충전 상태를 확인할 수 없어요. 다시 시도해 주세요."
            case .loading:
                "광고를 준비하고 있어요."
            case .presenting:
                "광고를 표시하고 있어요."
            case .awaitingServerSettlement:
                "실타래 지급을 확인하고 있어요."
            case .settled:
                "실타래 1개가 지급됐어요."
            case .requiresLogin:
                "광고 보상은 로그인 후 받을 수 있어요."
            case let .failed(message):
                message
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var settledBalance: Int?
    @Published private(set) var fixtureReceipt = ""

    private let loader: any CoorditRewardedAdLoading
    private let foregroundViewController: () -> UIViewController?
    private let sleepBetweenPolls: () async throws -> Void
    private let settlementPollLimit: Int
    private let fixtureScenario: CoorditRewardedAdFixtureScenario?

    private var rewardedAd: (any CoorditRewardedAdPresenting)?
    private var walletSession: CoorditRewardedWalletSession?
    private var settlementTask: Task<Void, Never>?
    private var prepareGeneration = UUID()
    private var fixtureBalancePollCount = 0

    override convenience init() {
        let fixtureScenario = CoorditRewardedAdFixtureScenario.launch()
        self.init(
            loader: fixtureScenario.map(CoorditFixtureRewardedAdLoader.init)
                ?? CoorditGoogleRewardedAdLoader(),
            foregroundViewController: Self.foregroundViewController,
            sleepBetweenPolls: {
                switch fixtureScenario {
                case .credited:
                    try await Task.sleep(for: .milliseconds(1_250))
                case .invalidCallback, .timeout, .loadFailure:
                    try await Task.sleep(for: .milliseconds(350))
                case nil:
                    try await Task.sleep(for: .seconds(2))
                }
            },
            settlementPollLimit: 8,
            fixtureScenario: fixtureScenario
        )
    }

    init(
        loader: any CoorditRewardedAdLoading,
        foregroundViewController: @escaping () -> UIViewController?,
        sleepBetweenPolls: @escaping () async throws -> Void,
        settlementPollLimit: Int,
        fixtureScenario: CoorditRewardedAdFixtureScenario? = nil
    ) {
        self.loader = loader
        self.foregroundViewController = foregroundViewController
        self.sleepBetweenPolls = sleepBetweenPolls
        self.settlementPollLimit = max(1, settlementPollLimit)
        self.fixtureScenario = fixtureScenario
        super.init()
    }

    var isReady: Bool {
        status == .ready && rewardedAd != nil
    }

    var isActionEnabled: Bool {
        switch status {
        case .idle, .ready, .settled, .failed:
            true
        case .disabled,
             .readinessUnavailable,
             .loading,
             .presenting,
             .awaitingServerSettlement,
             .requiresLogin:
            false
        }
    }

    func prepare(
        walletSession liveWalletSession: CoorditRewardedWalletSession,
        currentBalance: Int
    ) async {
        guard liveWalletSession.isAuthenticated else {
            transitionToUnavailable(.requiresLogin, receipt: "prepare-blocked:signed-out")
            return
        }
        guard liveWalletSession.rewardedAdsEnabled else {
            transitionToUnavailable(.disabled, receipt: "prepare-blocked:disabled")
            return
        }
        guard status != .loading, status != .presenting, status != .awaitingServerSettlement else {
            return
        }
        guard rewardedAd == nil else {
            status = .ready
            return
        }
        guard let adUnitID = Self.adUnitID(fixtureScenario: fixtureScenario) else {
            status = .failed("광고 설정을 확인할 수 없어요. 다시 시도해 주세요.")
            recordFixtureEvent("load-failed")
            return
        }

        let generation = UUID()
        prepareGeneration = generation
        settledBalance = nil
        fixtureBalancePollCount = 0
        fixtureReceipt = ""
        status = .loading
        let walletSession = effectiveWalletSession(
            liveWalletSession,
            initialBalance: currentBalance
        )
        self.walletSession = walletSession

        do {
            let attempt = try await walletSession.createAttempt()
            guard !Task.isCancelled, generation == prepareGeneration else { return }
            guard UUID(uuidString: attempt.attemptId) != nil else {
                throw CoorditBackendClientError.invalidResponse
            }
            recordFixtureEvent("attempt-created:\(attempt.attemptId)")

            let ad = try await loader.load(
                adUnitID: adUnitID,
                customRewardText: attempt.attemptId,
                delegate: self
            )
            guard !Task.isCancelled, generation == prepareGeneration else { return }
            guard ad.customRewardText == attempt.attemptId else {
                throw CoorditBackendClientError.invalidResponse
            }
            recordFixtureEvent("load-custom-data:\(ad.customRewardText)")
            rewardedAd = ad
            status = .ready
        } catch is CancellationError {
            return
        } catch let error as CoorditBackendClientError {
            guard !Task.isCancelled, generation == prepareGeneration else { return }
            rewardedAd = nil
            self.walletSession = nil
            if case .server(let code, _) = error, code == 401 {
                status = .requiresLogin
            } else {
                status = .failed("광고를 준비하지 못했어요. 다시 시도해 주세요.")
            }
            recordFixtureEvent("load-failed")
        } catch {
            guard !Task.isCancelled, generation == prepareGeneration else { return }
            rewardedAd = nil
            self.walletSession = nil
            status = .failed("광고를 준비하지 못했어요. 다시 시도해 주세요.")
            recordFixtureEvent("load-failed")
        }
    }

    func present(currentBalance: Int) {
        guard let rewardedAd, let viewController = foregroundViewController() else {
            self.rewardedAd = nil
            walletSession = nil
            status = .failed("광고 화면을 열 수 없어요. 다시 시도해 주세요.")
            return
        }
        guard walletSession?.isAuthenticated == true,
              walletSession?.rewardedAdsEnabled == true
        else {
            transitionToUnavailable(.requiresLogin, receipt: "present-blocked:signed-out")
            return
        }

        status = .presenting
        rewardedAd.present(from: viewController) { [weak self] in
            Task { @MainActor [weak self] in
                self?.beginServerSettlement(from: currentBalance)
            }
        }
    }

    func markSignedOut() {
        transitionToUnavailable(.requiresLogin, receipt: "prepare-blocked:signed-out")
    }

    func markDisabled() {
        transitionToUnavailable(.disabled, receipt: "prepare-blocked:disabled")
    }

    func markReadinessUnavailable() {
        transitionToUnavailable(.readinessUnavailable, receipt: "prepare-blocked:readiness-unavailable")
    }

    func deactivate() {
        prepareGeneration = UUID()
        settlementTask?.cancel()
        settlementTask = nil
        rewardedAd = nil
        walletSession = nil
        settledBalance = nil
        status = .idle
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard status == .presenting else { return }
        rewardedAd = nil
        walletSession = nil
        status = .failed("광고 시청이 완료되지 않았어요. 다시 시도해 주세요.")
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        settlementTask?.cancel()
        settlementTask = nil
        rewardedAd = nil
        walletSession = nil
        status = .failed("광고를 표시하지 못했어요. 다시 시도해 주세요.")
    }

    private func beginServerSettlement(from initialBalance: Int) {
        guard status == .presenting, let walletSession else { return }
        recordFixtureEvent("reward-callback")
        status = .awaitingServerSettlement
        settlementTask?.cancel()
        settlementTask = Task { [weak self] in
            guard let self else { return }
            for poll in 1...settlementPollLimit {
                do {
                    try await sleepBetweenPolls()
                    try Task.checkCancellation()
                    let serverBalance = try await walletSession.fetchServerBalance()
                    recordFixtureEvent("poll-balance:\(serverBalance)")
                    guard serverBalance > initialBalance else { continue }

                    settledBalance = serverBalance
                    rewardedAd = nil
                    self.walletSession = nil
                    status = .settled
                    recordFixtureEvent("settled-balance:\(serverBalance)")
                    settlementTask = nil
                    return
                } catch is CancellationError {
                    return
                } catch {
                    if poll == settlementPollLimit {
                        break
                    }
                }
            }

            rewardedAd = nil
            self.walletSession = nil
            status = .failed("실타래 지급 확인이 지연되고 있어요. 다시 시도해 주세요.")
            recordFixtureEvent("settlement-timeout:\(settlementPollLimit)")
            settlementTask = nil
        }
    }

    private func transitionToUnavailable(_ status: Status, receipt: String) {
        prepareGeneration = UUID()
        settlementTask?.cancel()
        settlementTask = nil
        rewardedAd = nil
        walletSession = nil
        settledBalance = nil
        self.status = status
        fixtureReceipt = ""
        recordFixtureEvent(receipt)
    }

    private func effectiveWalletSession(
        _ liveWalletSession: CoorditRewardedWalletSession,
        initialBalance: Int
    ) -> CoorditRewardedWalletSession {
        guard let fixtureScenario else { return liveWalletSession }

        return CoorditRewardedWalletSession(
            isAuthenticated: liveWalletSession.isAuthenticated,
            rewardedAdsEnabled: liveWalletSession.rewardedAdsEnabled,
            createAttempt: {
                CoorditThreadRewardAttempt(
                    attemptId: "00000000-0000-4000-8000-000000000401",
                    expiresAt: "2026-08-21T00:15:00.000Z",
                    status: "pending"
                )
            },
            fetchServerBalance: { [weak self] in
                guard let self else { throw CancellationError() }
                self.fixtureBalancePollCount += 1
                switch fixtureScenario {
                case .credited:
                    return self.fixtureBalancePollCount >= 2
                        ? initialBalance + 1
                        : initialBalance
                case .invalidCallback, .timeout, .loadFailure:
                    return initialBalance
                }
            }
        )
    }

    private func recordFixtureEvent(_ event: String) {
        guard fixtureScenario != nil else { return }
        fixtureReceipt = fixtureReceipt.isEmpty ? event : "\(fixtureReceipt)|\(event)"
    }

    private static func adUnitID(
        fixtureScenario: CoorditRewardedAdFixtureScenario?
    ) -> String? {
        if fixtureScenario != nil {
            return "coordit-ui-test-rewarded-unit"
        }
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        guard
            let configured = Bundle.main.object(
                forInfoDictionaryKey: "CoorditAdMobRewardedAdUnitID"
            ) as? String,
            !configured.isEmpty,
            !configured.contains("$(")
        else {
            return nil
        }
        return configured
        #endif
    }

    private static func foregroundViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return topViewController(from: scene?.keyWindow?.rootViewController)
    }

    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            return topViewController(from: tabController.selectedViewController)
        }
        if let presentedController = controller?.presentedViewController {
            return topViewController(from: presentedController)
        }
        return controller
    }
}

enum CoorditRewardedAdFixtureScenario: String {
    case credited
    case invalidCallback = "invalid-callback"
    case timeout
    case loadFailure = "load-failure"

    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        #if DEBUG
        guard
            arguments.contains("--coordit-ui-testing"),
            let markerIndex = arguments.firstIndex(of: "--coordit-rewarded-ad-fixture"),
            arguments.indices.contains(arguments.index(after: markerIndex))
        else {
            return nil
        }
        return Self(rawValue: arguments[arguments.index(after: markerIndex)])
        #else
        return nil
        #endif
    }
}

@MainActor
private final class CoorditFixtureRewardedAdLoader: CoorditRewardedAdLoading {
    private let scenario: CoorditRewardedAdFixtureScenario

    init(scenario: CoorditRewardedAdFixtureScenario) {
        self.scenario = scenario
    }

    func load(
        adUnitID: String,
        customRewardText: String,
        delegate: FullScreenContentDelegate
    ) async throws -> any CoorditRewardedAdPresenting {
        if scenario == .loadFailure {
            throw CoorditRewardedAdFixtureError.loadFailed
        }
        return CoorditFixtureRewardedAdPresenter(customRewardText: customRewardText)
    }
}

@MainActor
private final class CoorditFixtureRewardedAdPresenter: CoorditRewardedAdPresenting {
    let customRewardText: String

    init(customRewardText: String) {
        self.customRewardText = customRewardText
    }

    func present(
        from viewController: UIViewController,
        userDidEarnReward: @escaping () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            userDidEarnReward()
        }
    }
}

private enum CoorditRewardedAdFixtureError: Error {
    case loadFailed
}
#endif
