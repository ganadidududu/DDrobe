import SwiftUI

#if os(iOS)
struct CoorditRootView: View {
    @State private var route: CoorditFrameRoute
    @State private var navigationDirection: CoorditNavigationDirection = .forward
    @State private var closetItems: [CoorditClosetItem]
    @State private var selectedClosetItemID: String?
    @State private var closetDraft = CoorditClosetDraft()
    @State private var selectedReferenceIDs: Set<String> = []
    @State private var showsFitLabReferenceSelection = false
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var fitLabCoordinator: CoorditFitLabCoordinator

    init(startRoute: CoorditFrameRoute = .testingLaunchRoute()) {
        _route = State(initialValue: startRoute)
        _closetItems = State(initialValue: Self.initialClosetItems())
        _fitLabCoordinator = StateObject(
            wrappedValue: CoorditFitLabCoordinator.makeAppScoped(route: startRoute)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showsSharedAppBackground {
                CoorditSharedAppBackground()
                    .zIndex(-100)
            }

            Group {
                switch route {
        case .main01:
            CoorditMain01Screen(initialTab: .home) { selectedTab in
                navigate(to: CoorditFrameRoute.route(for: selectedTab, from: route))
            }
        case .splash:
            CoorditSplashScreen { navigate(to: $0) }
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
            ) { navigate(to: $0) }
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
                coordinator: fitLabCoordinator
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
             .myPageTerms,
             .myPageContact,
             .myPageBugReport:
            CoorditMyPageFamilyView(route: route) { navigate(to: $0) }
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
                selectedReferenceIDs: $selectedReferenceIDs
            ) { navigate(to: $0) }
                }
            }
            .id(route)
            .transition(routeTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.coorditShowsScreenChrome, false)
            .environment(\.coorditShowsScreenBackground, false)

            if showsScreenChrome {
                CoorditScreenChrome(route: route) { navigate(to: $0) }
                    .zIndex(90)
            }

            CoorditGlobalFitAnalysisBanner(
                coordinator: fitLabCoordinator,
                onOpenResult: { navigate(to: $0) },
                onOpenFitLab: { navigate(to: .fitLabInput) }
            )
            .zIndex(100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(CoorditPressFeedbackButtonStyle())
        .task(id: backendSession.session?.user.id) {
            guard let snapshot = await backendSession.loadClosetSnapshot(preserving: closetItems) else { return }
            closetItems = snapshot.items
            selectedReferenceIDs = snapshot.selectedReferenceIDs
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
        .sheet(isPresented: $showsFitLabReferenceSelection) {
            CoorditHomeReferenceSelectionSheet(
                items: closetItems,
                initialSelection: selectedReferenceIDs,
                onCommit: syncFitLabReferenceSelection,
                onAddGarment: { navigate(to: .closetAddMethod) }
            )
        }
    }

    private var routeTransition: AnyTransition {
        .coorditMenuPush(direction: navigationDirection, reduceMotion: reduceMotion)
    }

    private func navigate(to nextRoute: CoorditFrameRoute) {
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

    private var showsScreenChrome: Bool {
        route != .splash && route != .main01
    }

    private var showsSharedAppBackground: Bool {
        route != .splash && route != .main01
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
