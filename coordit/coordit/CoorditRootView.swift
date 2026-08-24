import SwiftUI

#if os(iOS)
struct CoorditRootView: View {
    @State private var route: CoorditFrameRoute
    @State private var navigationDirection: CoorditNavigationDirection = .forward
    @State private var closetItems: [CoorditClosetItem]
    @State private var selectedClosetItemID: String?
    @State private var closetDraft = CoorditClosetDraft()
    @State private var closetAddSaveState = CoorditClosetAddSaveState()
    @State private var isRegisteringFitLabReference = false
    @State private var selectedReferenceIDs: Set<String> = []
    @State private var showsFitLabReferenceSelection = false
    @State private var showsOnboarding = false
    @State private var threadBalance: Int
    @State private var showsThreadRechargePrompt = false
    @State private var sharedFitLabImportURL: URL?
    @State private var showsAuthenticationEntry = false
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var fitLabCoordinator: CoorditFitLabCoordinator

    init(startRoute: CoorditFrameRoute = .testingLaunchRoute()) {
        Self.seedPendingSharedFitLabImportURLIfNeeded()
        let initialSharedURL = Self.initialSharedFitLabImportURL()
        let initialRoute = initialSharedURL == nil ? startRoute : CoorditFrameRoute.fitLabInput
        _route = State(initialValue: initialRoute)
        _closetItems = State(initialValue: Self.initialClosetItems())
        _closetDraft = State(initialValue: Self.initialClosetDraft())
        _threadBalance = State(initialValue: Self.initialThreadBalance())
        _showsThreadRechargePrompt = State(
            initialValue: Self.initialThreadRechargePrompt(startRoute: startRoute)
        )
        _sharedFitLabImportURL = State(initialValue: initialSharedURL)
        _fitLabCoordinator = StateObject(
            wrappedValue: CoorditFitLabCoordinator.makeAppScoped(route: initialRoute)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showsSharedAppBackground {
                CoorditSharedAppBackground()
                    .zIndex(-100)
            }

            Group {
                if blocksUnauthenticatedContent {
                    splashScreen
                } else {
                    switch route {
        case .main01:
            CoorditMain01Screen(initialTab: .home) { selectedTab in
                navigate(to: CoorditFrameRoute.route(for: selectedTab, from: route))
            }
        case .splash:
            splashScreen
        case .main04:
            CoorditMain04Screen(
                closetItems: $closetItems,
                selectedReferenceIDs: $selectedReferenceIDs,
                fitLabHistory: fitLabCoordinator.savedHistory,
                onOpenFitLabHistory: { snapshot in
                    fitLabCoordinator.selectHistory(snapshot)
                    navigate(to: .fitLabHistoryDetail)
                },
                onReferenceCommit: { selection in
                    Task {
                        guard let result = await backendSession.syncReferenceSelection(
                            items: closetItems,
                            selectedIDs: selection
                        ) else { return }
                        for index in closetItems.indices {
                            if let referenceID = result.referenceIDsByItemID[closetItems[index].id] {
                                closetItems[index].backendReferenceClothingId = referenceID
                            }
                        }
                        selectedReferenceIDs = result.selectedIDs
                        await backendSession.refreshReferenceFitProfiles()
                    }
                }
            ) { nextRoute in
                if nextRoute == .closetAddMethod {
                    startNewClosetRegistration()
                } else {
                    navigate(to: nextRoute)
                }
            }
        case .fitLabInput,
             .fitLabLoading,
             .fitLabResultTop,
             .fitLabResultBottom,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail:
            CoorditFitLabFamilyView(
                currentRoute: route,
                onRouteChange: { navigate(to: $0) },
                onManageReferences: { showsFitLabReferenceSelection = true },
                coordinator: fitLabCoordinator,
                threadBalance: $threadBalance,
                sharedImportURL: $sharedFitLabImportURL,
                onInsufficientThread: handleInsufficientThreadForFitLab,
                onOpenThreadRecharge: openThreadRechargeFromFitLab
            )
        case .myPage,
             .myPageThreadCharge,
             .myPageBody,
             .myPageAccount,
             .myPagePrivacy,
             .myPageAppSettings,
             .myPageNotifications,
             .myPageProfileEdit,
             .myPagePasswordChange,
             .myPageLogout,
             .myPageAccountDeletion,
             .myPageBodyMeasurements,
             .myPagePrivacyPolicy,
             .myPageTerms:
            CoorditMyPageFamilyView(
                route: route,
                threadBalance: $threadBalance,
                showsThreadRechargePrompt: $showsThreadRechargePrompt,
                onAccountDeleted: handleAccountDeletion
            ) { navigate(to: $0) }
        case .closetOverview,
             .closetDetailTop,
             .closetDetailBottom,
             .closetAddMethod,
             .closetAddLink,
             .closetAddPhoto,
             .closetAddManual,
             .closetAddLoading,
             .closetAddResult:
            CoorditClosetFamilyView(
                route: route,
                items: $closetItems,
                selectedItemID: $selectedClosetItemID,
                draft: $closetDraft,
                selectedReferenceIDs: $selectedReferenceIDs,
                addSaveState: $closetAddSaveState,
                onSavedItem: routeAfterSavingClosetItem
            ) { navigate(to: $0) }
                    }
                }
            }
            .id(route)
            .transition(routeTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.coorditShowsScreenChrome, false)
            .environment(\.coorditShowsScreenBackground, false)

            if showsScreenChrome {
                CoorditScreenChrome(
                    route: route,
                    onRouteChange: { navigate(to: $0) },
                    showsHeader: !fitLabCoordinator.isAnalysisNoticeVisible
                )
                    .zIndex(90)
            }

            if backendSession.isAuthenticated && !blocksUnauthenticatedContent {
                CoorditGlobalFitAnalysisBanner(
                    coordinator: fitLabCoordinator,
                    onOpenResult: { navigate(to: $0) },
                    onOpenFitLab: { navigate(to: .fitLabInput) }
                )
                .zIndex(100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(CoorditPressFeedbackButtonStyle())
        .task(id: backendSession.isAuthenticated) {
            guard !backendSession.isAuthenticated else { return }

            showsAuthenticationEntry = false
            threadBalance = 0
            showsFitLabReferenceSelection = false
            showsThreadRechargePrompt = false
            guard !permitsUnauthenticatedUITestRoute else { return }

            if route != .splash {
                navigate(to: .splash)
            }
        }
        .task(id: backendSession.session?.user.id) {
            await backendSession.bootstrap()
            if backendSession.isAuthenticated, !backendSession.onboardingComplete {
                return
            }
            guard canShowSelectedRoute else {
                presentOnboardingIfNeeded()
                return
            }
            if let snapshot = await backendSession.loadClosetSnapshot(preserving: closetItems) {
                closetItems = snapshot.items
                selectedReferenceIDs = snapshot.selectedReferenceIDs
            }
            if let balance = await backendSession.fetchThreadBalance() {
                threadBalance = balance
            }
        }
        .task(id: fitLabHistoryUserID) {
            await fitLabCoordinator.prepareHistory(userID: fitLabHistoryUserID)
        }
        #if DEBUG
        .task {
            await performTestingAutoNavigationIfNeeded()
        }
        #endif
        .onChange(of: closetItems.compactMap(\.backendReferenceClothingId)) { oldIDs, newIDs in
            let addedReferenceIDs = Set(newIDs).subtracting(oldIDs)
            guard !addedReferenceIDs.isEmpty else { return }
            selectedReferenceIDs.formUnion(
                closetItems.compactMap { item in
                    guard let referenceID = item.backendReferenceClothingId,
                          addedReferenceIDs.contains(referenceID) else { return nil }
                    return item.id
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: CoorditSharedFitLabImport.didRequestOpenNotification)) { notification in
            openSharedFitLabImport(notification.object as? URL)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            openPendingSharedFitLabImport()
        }
        .task {
            openPendingSharedFitLabImport()
        }
        .sheet(isPresented: $showsFitLabReferenceSelection) {
            CoorditHomeReferenceSelectionSheet(
                items: closetItems,
                initialSelection: selectedReferenceIDs,
                onCommit: syncFitLabReferenceSelection,
                onAddGarment: startFitLabReferenceRegistration
            )
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            CoorditOnboardingView {
                showsOnboarding = false
                guard backendSession.canUseProduct else { return }
                CoorditWelcomeLaunchState.markWelcomeCompleted()
                navigate(to: .main04)
            }
        }
    }

    private var routeTransition: AnyTransition {
        .coorditMenuPush(direction: navigationDirection, reduceMotion: reduceMotion)
    }

    private func navigate(to nextRoute: CoorditFrameRoute) {
        if isRegisteringFitLabReference, nextRoute == .closetOverview {
            isRegisteringFitLabReference = false
        }
        guard nextRoute == .splash || canShowSelectedRoute else {
            route = .splash
            return
        }
        let destination = nextRoute == .fitLabInput && fitLabCoordinator.isAnalysisRunning
            ? CoorditFrameRoute.fitLabLoading
            : nextRoute
        guard destination != route else { return }
        if destination.navigationSection == route.navigationSection {
            navigationDirection = destination.navigationDepth >= route.navigationDepth ? .forward : .backward
        } else if destination.navigationSection == 0 {
            navigationDirection = .backward
        } else {
            navigationDirection = .forward
        }
        withAnimation(.easeOut(duration: reduceMotion ? 0.14 : 0.22)) {
            route = destination
        }
    }

    private func startNewClosetRegistration() {
        isRegisteringFitLabReference = false
        closetDraft = CoorditClosetDraft()
        closetAddSaveState.reset()
        navigate(to: .closetAddMethod)
    }

    private func startFitLabReferenceRegistration() {
        isRegisteringFitLabReference = true
        closetDraft = CoorditClosetDraft()
        closetDraft.category = fitLabCoordinator.draft.category.garmentKind == .upper ? .top : .bottom
        closetDraft.exactCategory = fitLabCoordinator.draft.category
        closetAddSaveState.reset()
        navigate(to: .closetAddMethod)
    }

    private static func initialClosetItems(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> [CoorditClosetItem] {
        #if DEBUG
        if arguments.contains("--coordit-ui-testing"),
           !arguments.contains("--coordit-empty-closet") {
            return CoorditClosetItem.seedItems
        }
        #endif
        return []
    }

    private static func initialClosetDraft(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> CoorditClosetDraft {
        #if DEBUG
        if arguments.contains("--coordit-test-prefilled-closet-draft") {
            var draft = CoorditClosetDraft()
            draft.method = .link
            draft.productLink = "https://shop.example/products/previous-item"
            return draft
        }
        #endif
        return CoorditClosetDraft()
    }

    private static func initialThreadBalance(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Int {
        #if DEBUG
        if arguments.contains("--coordit-ui-testing"),
           let markerIndex = arguments.firstIndex(of: "--coordit-thread-balance"),
           arguments.indices.contains(arguments.index(after: markerIndex)),
           let value = Int(arguments[arguments.index(after: markerIndex)]) {
            return max(0, value)
        }
        #endif
        return 0
    }

    private static func initialThreadRechargePrompt(
        startRoute: CoorditFrameRoute,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains("--coordit-ui-testing")
            && arguments.contains("--coordit-thread-recharge-prompt")
            && startRoute == .myPageThreadCharge
        #else
        false
        #endif
    }

    private static func initialSharedFitLabImportURL(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL? {
        #if DEBUG
        guard arguments.contains("--coordit-ui-testing"),
              let markerIndex = arguments.firstIndex(of: "--coordit-shared-fitlab-url"),
              arguments.indices.contains(arguments.index(after: markerIndex)),
              let url = URL(string: arguments[arguments.index(after: markerIndex)]),
              url.isHTTPOrHTTPSProductURL
        else { return nil }
        return url
        #else
        return nil
        #endif
    }

    private static func seedPendingSharedFitLabImportURLIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        #if DEBUG
        guard arguments.contains("--coordit-ui-testing"),
              let markerIndex = arguments.firstIndex(of: "--coordit-pending-fitlab-url"),
              arguments.indices.contains(arguments.index(after: markerIndex)),
              let url = URL(string: arguments[arguments.index(after: markerIndex)]),
              url.isHTTPOrHTTPSProductURL
        else { return }
        CoorditSharedFitLabImport.store(productURL: url, sourceApplication: "ui-test")
        #endif
    }

    private var blocksUnauthenticatedContent: Bool {
        !backendSession.isAuthenticated
            && route != .splash
            && !permitsUnauthenticatedUITestRoute
    }

    private var permitsUnauthenticatedUITestRoute: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--coordit-ui-testing"),
              !arguments.contains("--coordit-enforce-auth-gate"),
              let markerIndex = arguments.firstIndex(of: "--coordit-start-route"),
              arguments.indices.contains(arguments.index(after: markerIndex))
        else { return false }

        return arguments[arguments.index(after: markerIndex)] != CoorditFrameRoute.splash.rawValue
        #else
        false
        #endif
    }

    private var showsScreenChrome: Bool {
        !blocksUnauthenticatedContent && route != .splash && route != .main01
    }

    private var splashPresentation: CoorditSplashPresentation {
        CoorditWelcomeLaunchState.splashPresentation(isAuthenticated: backendSession.isAuthenticated)
    }

    @ViewBuilder
    private var splashScreen: some View {
        if showsAuthenticationEntry {
            CoorditAuthenticationEntryView {
                showsAuthenticationEntry = false
                if backendSession.onboardingComplete {
                    CoorditWelcomeLaunchState.markWelcomeCompleted()
                    navigate(to: .main04)
                } else {
                    showsOnboarding = true
                }
            }
        } else {
            CoorditSplashScreen(
                presentation: splashPresentation,
                onRouteChange: { nextRoute in
                    guard backendSession.onboardingComplete else {
                        presentOnboardingIfNeeded()
                        return
                    }
                    navigate(to: nextRoute)
                },
                onAuthenticationRequested: { showsAuthenticationEntry = true }
            )
        }
    }

    private var canShowSelectedRoute: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coordit-ui-testing") {
            return true
        }
        #endif
        return route == .splash || backendSession.canUseProduct
    }

    private func presentOnboardingIfNeeded() {
        guard backendSession.isAuthenticated, !backendSession.onboardingComplete else { return }
        showsOnboarding = true
    }

    private var showsSharedAppBackground: Bool {
        !blocksUnauthenticatedContent && route != .splash && route != .main01
    }

    private var fitLabHistoryUserID: String? {
        #if DEBUG
        if fitLabCoordinator.fixtureName != nil {
            return fitLabCoordinator.userID
        }
        #endif
        return backendSession.session?.user.id
    }

    private func syncFitLabReferenceSelection(_ selection: Set<String>) {
        Task {
            _ = await persistFitLabReferenceSelection(selection)
        }
    }

    private func routeAfterSavingClosetItem(_ item: CoorditClosetItem) async -> CoorditFrameRoute? {
        guard isRegisteringFitLabReference else { return nil }
        defer { isRegisteringFitLabReference = false }

        let selection = selectedReferenceIDs.union([item.id])
        guard let result = await persistFitLabReferenceSelection(selection),
              let referenceID = result.referenceIDsByItemID[item.id],
              fitLabCoordinator.selectReference(id: referenceID)
        else { return nil }

        return .fitLabInput
    }

    private func persistFitLabReferenceSelection(
        _ selection: Set<String>
    ) async -> CoorditReferenceSyncResult? {
        guard let result = await backendSession.syncReferenceSelection(
            items: closetItems,
            selectedIDs: selection
        ) else { return nil }
        for index in closetItems.indices {
            if let referenceID = result.referenceIDsByItemID[closetItems[index].id] {
                closetItems[index].backendReferenceClothingId = referenceID
            }
        }
        selectedReferenceIDs = result.selectedIDs
        await backendSession.refreshReferenceFitProfiles()
        await reloadFitLabReferences()
        return result
    }

    private func reloadFitLabReferences() async {
        #if DEBUG
        if fitLabCoordinator.fixtureName != nil {
            await fitLabCoordinator.loadCompatibleReferences()
            return
        }
        #endif
        guard let session = backendSession.session else {
            await fitLabCoordinator.loadCompatibleReferences(authenticatedUserID: nil)
            return
        }
        let api = CoorditFitLabHTTPAPI(
            baseURL: CoorditBackendConfig.baseURL(),
            accessToken: session.accessToken
        )
        await fitLabCoordinator.loadCompatibleReferences(
            using: api,
            authenticatedUserID: session.user.id
        )
    }

    private func handleInsufficientThreadForFitLab() {
        showsThreadRechargePrompt = true
        navigate(to: .myPageThreadCharge)
    }

    private func openThreadRechargeFromFitLab() {
        showsThreadRechargePrompt = false
        navigate(to: .myPageThreadCharge)
    }

    private func handleAccountDeletion(userID: String) async -> Bool {
        closetItems = []
        selectedClosetItemID = nil
        closetDraft = CoorditClosetDraft()
        closetAddSaveState.reset()
        selectedReferenceIDs = []
        threadBalance = 0
        showsThreadRechargePrompt = false
        sharedFitLabImportURL = nil
        fitLabCoordinator.discardAndRestart()
        return await fitLabCoordinator.deleteLocalHistory(for: userID)
    }

    private func openPendingSharedFitLabImport() {
        guard let url = CoorditSharedFitLabImport.consumePendingProductURL() else { return }
        openSharedFitLabImport(url)
    }

    private func openSharedFitLabImport(_ url: URL?) {
        guard let url else { return }
        // A direct URL notification may arrive before scene activation. Remove
        // its queued copy so activation cannot reset the in-progress Fit Lab flow.
        CoorditSharedFitLabImport.removePendingProductURL(matching: url)
        fitLabCoordinator.discardAndRestart()
        sharedFitLabImportURL = url
        navigate(to: .fitLabInput)
    }

    #if DEBUG
    private func performTestingAutoNavigationIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) async {
        guard arguments.contains("--coordit-ui-testing"),
              let markerIndex = arguments.firstIndex(of: "--coordit-auto-route"),
              arguments.indices.contains(arguments.index(after: markerIndex)),
              let nextRoute = CoorditFrameRoute(
                rawValue: arguments[arguments.index(after: markerIndex)]
              ) else {
            return
        }

        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        navigate(to: nextRoute)
    }
    #endif
}
#endif
