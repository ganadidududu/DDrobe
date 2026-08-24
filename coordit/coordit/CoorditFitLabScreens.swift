import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
struct CoorditFitLabFamilyView: View {
    let currentRoute: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void
    let onManageReferences: () -> Void
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @ObservedObject var coordinator: CoorditFitLabCoordinator
    @Binding var threadBalance: Int
    @Binding var sharedImportURL: URL?
    let onInsufficientThread: () -> Void
    let onOpenThreadRecharge: () -> Void
    @State private var inputDestination: CoorditFitLabInputDestination = .sources
    @State private var inputNavigationDirection: CoorditNavigationDirection = .forward
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CoorditScreenScaffold(
            route: currentRoute,
            onRouteChange: onRouteChange,
            contentTop: 115,
            contentBottom: 0
        ) { metrics in
            VStack(spacing: metrics.value(22)) {
                CoorditFitLabTitleCard(
                    title: currentRoute == .fitLabHistoryDetail ? "FIT DETAIL" : "FIT LAB",
                    metrics: metrics
                ) {
                    handleTitleBack()
                }
                .padding(.horizontal, metrics.value(16))

                if shouldRenderFixtureContent {
                    fixtureContent(metrics: metrics)
                } else {
                    switch currentRoute {
                    case .fitLabInput:
                        fitLabInput(metrics: metrics)
                    case .fitLabLoading:
                        CoorditFitLabLoadingScreen(
                            metrics: metrics,
                            coordinator: coordinator,
                            retry: submitAnalysis
                        )
                    case .fitLabResultTop:
                        completedReportContent(variant: .top, metrics: metrics)
                    case .fitLabResultBottom:
                        completedReportContent(variant: .bottom, metrics: metrics)
                    case .fitLabHistoryRegister:
                        historyDetail(metrics: metrics)
                    case .fitLabHistoryDetail:
                        historyDetail(metrics: metrics)
                    default:
                        fitLabInput(metrics: metrics)
                    }
                }

                #if DEBUG
                Text(currentRoute.rawValue)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(currentRoute.rawValue)
                    .accessibilityIdentifier(currentRoute.fitLabAccessibilityIdentifier)
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .topLeading) {
                CoorditGmarketBoldFontDiagnostic()
            }
            #if DEBUG
            .overlay(alignment: .bottom) {
                if coordinator.fixtureName == "history-edge" {
                    historyDebugControls
                }
            }
            #endif
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: coordinator.analysisState) { _, state in
            routeToCompletedAnalysis(state)
        }
        .onChange(of: coordinator.authoritativeThreadBalance) { _, balance in
            if let balance { threadBalance = balance }
        }
        .onChange(of: coordinator.error) { _, error in
            guard case .server(statusCode: 402, message: _) = error else { return }
            onInsufficientThread()
        }
        .onAppear {
            routeToCompletedAnalysis(coordinator.analysisState)
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            debugProbeOverlay
        }
        .overlay(alignment: .bottom) {
            raceDebugControls
                .padding(.bottom, 104)
        }
        #endif
        .onChange(of: currentRoute) { _, route in
            coordinator.synchronize(route: route)
        }
        .onChange(of: sharedImportURL) { _, url in
            openSharedImport(url)
        }
        .onAppear {
            openSharedImport(sharedImportURL)
        }
        .task(id: effectiveHistoryUserID) {
            if coordinator.activeHistoryUserID != effectiveHistoryUserID {
                await coordinator.prepareHistory(userID: effectiveHistoryUserID)
            }
        }
    }

    private var shouldRenderFixtureContent: Bool {
        #if DEBUG
        guard let fixture = coordinator.fixtureName else { return false }
        return fixture != "manual-selected-reference"
            && !fixture.hasPrefix("ocr-")
            && !fixture.hasPrefix("url-")
            && !fixture.hasPrefix("submission-")
            && fixture != "upper-result"
            && fixture != "lower-result"
            && fixture != "size-score-numeric-labels"
            && fixture != "long-report"
            && fixture != "saved-history"
            && !fixture.hasPrefix("history-")
        #else
        false
        #endif
    }

    @ViewBuilder
    private func completedReportContent(
        variant: CoorditFitLabResultVariant,
        metrics: CoorditResponsiveMetrics
    ) -> some View {
        if coordinator.recommendation != nil {
            CoorditFitLabResultScreen(
                variant: variant,
                recommendation: coordinator.recommendation,
                report: coordinator.report,
                sizeDrafts: coordinator.draft.sizes,
                fallbackMessage: coordinator.reportFailureMessage,
                canSaveHistory: coordinator.report != nil,
                isSaved: coordinator.savedHistory.contains {
                    $0.analysisID == coordinator.recommendation?.fitAnalysisResultID
                },
                metrics: metrics,
                saveHistory: saveHistory,
                retryReport: submitAnalysis,
                finishReport: finishReport
            )
        } else {
            CoorditFitLabLoadingScreen(
                metrics: metrics,
                coordinator: coordinator,
                retry: submitAnalysis
            )
        }
    }

    private func routeToCompletedAnalysis(_ state: CoorditFitLabAnalysisState) {
        guard case .completed(let destination) = state,
              currentRoute == .fitLabInput || currentRoute == .fitLabLoading
        else { return }
        onRouteChange(destination)
    }

    private var fixtureAPIRequestLedger: [String] {
        #if DEBUG
        coordinator.fixtureAPI?.requestLedger ?? []
        #else
        []
        #endif
    }

    private func prefillProduct(
        from url: URL,
        category: CoorditFitLabCategory
    ) async throws -> CoorditFitLabURLPrefillResponse {
        #if DEBUG
        if coordinator.fixtureName != nil {
            return try await coordinator.prefillProduct(from: url, category: category)
        }
        #endif
        guard let token = backendSession.session?.accessToken else {
            throw CoorditFitLabError.loginRequired
        }
        let api = CoorditFitLabHTTPAPI(baseURL: CoorditBackendConfig.baseURL(), accessToken: token)
        return try await api.prefillProduct(
            from: CoorditFitLabURLPrefillRequest(url: url, category: category)
        )
    }

    private func compatibleReferences(for category: CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow] {
        #if DEBUG
        if coordinator.fixtureName != nil {
            return try await coordinator.fetchCompatibleReferences(category: category)
        }
        #endif
        guard let token = backendSession.session?.accessToken else {
            throw CoorditFitLabError.loginRequired
        }
        let api = CoorditFitLabHTTPAPI(baseURL: CoorditBackendConfig.baseURL(), accessToken: token)
        return try await coordinator.fetchCompatibleReferences(category: category, using: api)
    }

    @ViewBuilder
    private func fitLabInput(metrics: CoorditResponsiveMetrics) -> some View {
        if coordinator.draft.isSourceConfirmed {
            CoorditFitLabSubmissionView(
                metrics: metrics,
                coordinator: coordinator,
                requestLedger: { fixtureAPIRequestLedger },
                loadReferences: loadSubmissionReferences,
                manageReferences: onManageReferences,
                submit: submitAnalysis
            )
        } else {
            CoorditFitLabInputScreen(
                metrics: metrics,
                draft: $coordinator.draft,
                destination: inputDestinationBinding,
                navigationDirection: inputNavigationDirection,
                fixtureName: coordinator.fixtureName,
                apiRequestLedger: fixtureAPIRequestLedger,
                urlRequestLedger: { fixtureAPIRequestLedger },
                urlPrefill: prefillProduct,
                urlReferences: compatibleReferences,
                sharedImportURL: sharedImportURL,
                savedHistory: coordinator.savedHistory,
                historyRecoveryNotice: coordinator.historyRecoveryNotice,
                threadBalance: threadBalance,
                onThreadRecharge: onOpenThreadRecharge,
                onOpenHistory: { snapshot in
                    coordinator.selectHistory(snapshot)
                    onRouteChange(.fitLabHistoryDetail)
                }
            )
        }
    }

    private func handleTitleBack() {
        if currentRoute == .fitLabInput, inputDestination != .sources {
            navigateInput(to: .sources)
        } else if currentRoute == .fitLabInput {
            onRouteChange(.main04)
        } else if currentRoute == .fitLabLoading {
            onRouteChange(.main04)
        } else {
            onRouteChange(.fitLabInput)
        }
    }

    private var inputDestinationBinding: Binding<CoorditFitLabInputDestination> {
        Binding(
            get: { inputDestination },
            set: { navigateInput(to: $0) }
        )
    }

    private func navigateInput(to destination: CoorditFitLabInputDestination) {
        guard destination != inputDestination else { return }
        inputNavigationDirection = destination == .sources ? .backward : .forward
        withAnimation(.easeOut(duration: reduceMotion ? 0.14 : 0.22)) {
            inputDestination = destination
        }
    }

    private func openSharedImport(_ url: URL?) {
        guard let url else { return }
        coordinator.draft.source = .url
        coordinator.draft.productURL = url
        coordinator.draft.isSourceConfirmed = false
        coordinator.draft.selectedReferenceIDs.removeAll()
        inputNavigationDirection = .forward
        inputDestination = .url
        sharedImportURL = nil
    }

    private var effectiveHistoryUserID: String? {
        if coordinator.fixtureName != nil { return coordinator.userID }
        return backendSession.session?.user.id
    }

    private func saveHistory() async -> Bool {
        #if DEBUG
        if coordinator.fixtureName != nil {
            return await coordinator.saveCurrentAnalysis()
        }
        #endif
        return await coordinator.saveCurrentAnalysis(authenticatedUserID: backendSession.session?.user.id)
    }

    private func finishReport() {
        coordinator.discardAndRestart()
        inputDestination = .sources
        inputNavigationDirection = .forward
        onRouteChange(.fitLabInput)
    }

    @ViewBuilder
    private func historyDetail(metrics: CoorditResponsiveMetrics) -> some View {
        if let snapshot = coordinator.selectedHistory {
            CoorditFitLabHistoryDetailScreen(
                snapshot: snapshot,
                metrics: metrics,
                delete: {
                    #if DEBUG
                    let userID = coordinator.fixtureName == nil ? backendSession.session?.user.id : coordinator.activeHistoryUserID
                    #else
                    let userID = backendSession.session?.user.id
                    #endif
                    if await coordinator.deleteSelectedHistory(authenticatedUserID: userID) {
                        onRouteChange(.fitLabInput)
                    }
                },
                onRouteChange: onRouteChange
            )
        } else {
            VStack(spacing: metrics.value(14)) {
                ContentUnavailableView(
                    "저장된 분석을 찾을 수 없어요",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("저장된 분석이 아직 없어요. 핏 랩에서 분석을 만든 뒤 저장해 주세요.")
                )
                Button("핏 랩으로 돌아가기") { onRouteChange(.fitLabInput) }
                    .buttonStyle(
                        CoorditContentActionButtonStyle(
                            prominence: .primary,
                            height: metrics.value(48),
                            cornerRadius: metrics.value(7),
                            fontSize: metrics.value(13)
                        )
                    )
                    .accessibilityIdentifier("fitlab-history-empty-recovery")
            }
        }
    }

    #if DEBUG
    private var debugProbeOverlay: some View {
        VStack(spacing: 0) {
            debugProbe(CoorditFitLabContractProbe.status, identifier: "fitlab-dto-contract-status")
            debugProbe(
                "screen=\(coordinator.screen.rawValue)|checkpoint=\(coordinator.checkpoint.isEmpty ? "empty" : "present")|recommendation=\(coordinator.recommendation == nil ? "empty" : "present")|report=\(coordinator.report == nil ? "empty" : "present")",
                identifier: "fitlab-submission-state-probe"
            )
            debugProbe("\(coordinator.savedHistory.count)", identifier: "fitlab-history-count")
            debugProbe(coordinator.historyEdgeProbe, identifier: "fitlab-history-edge-probe")
            debugProbe(coordinator.historyUserProbe, identifier: "fitlab-history-user-probe")
            debugProbe(coordinator.historyStoreAudit, identifier: "fitlab-history-store-audit")
            debugProbe(coordinator.historyF2Probe, identifier: "fitlab-history-f2-probe")
            debugProbe(
                "source=\(coordinator.draft.source.rawValue)|category=\(coordinator.draft.category.rawValue)|product=\(coordinator.draft.productName)|url=\(coordinator.draft.productURL?.absoluteString ?? "nil")",
                identifier: "fitlab-draft-isolation-probe"
            )
            debugProbe("\(coordinator.historyQuarantineCount)", identifier: "fitlab-history-quarantine-count")
            debugProbe(
                fixtureAPIRequestLedger.isEmpty ? "[]" : "[\(fixtureAPIRequestLedger.joined(separator: ","))]",
                identifier: "fitlab-ocr-api-request-ledger"
            )
            debugProbe(submissionLedgerSummary, identifier: "fitlab-submission-ledger")
            debugProbe(
                fixtureAPIRequestLedger.joined(separator: "|"),
                identifier: "fitlab-submission-ledger-detail"
            )
            debugProbe("\(threadBalance)", identifier: "coordit-thread-balance-probe")
            debugProbe(ocrPayloadMetadataProbe, identifier: "fitlab-ocr-payload-metadata")
            debugProbe(ocrSizeRequestProbe, identifier: "fitlab-ocr-size-request-probe")
            debugProbe(productRequestProbe, identifier: "fitlab-product-request-probe")
        }
        .frame(width: 1, height: 1)
        .clipped()
    }

    @ViewBuilder
    private var raceDebugControls: some View {
        if coordinator.fixtureName == "submission-recommendation-race" {
            HStack {
                Button("테스트 제출 폐기") { coordinator.discardAndRestart() }
                    .accessibilityIdentifier("fitlab-test-force-discard")
                Button("테스트 추천 응답 재개") { coordinator.fixtureAPI?.releaseRecommendation() }
                    .accessibilityIdentifier("fitlab-test-release-recommendation")
            }
        } else if coordinator.fixtureName == "submission-report-race"
                    || coordinator.fixtureName == "submission-report-insufficient-thread" {
            HStack {
                Button("테스트 제출 폐기") { coordinator.discardAndRestart() }
                    .accessibilityIdentifier("fitlab-test-force-discard")
                Button("테스트 리포트 응답 재개") { coordinator.fixtureAPI?.releaseReport() }
                    .accessibilityIdentifier("fitlab-test-release-report")
            }
        }
    }

    private func debugProbe(_ value: String, identifier: String) -> some View {
        Text(value)
            .foregroundStyle(Color.clear)
            .accessibilityLabel(value)
            .accessibilityIdentifier(identifier)
    }

    private var ocrPayloadMetadataProbe: String {
        guard coordinator.draft.source == .ocr,
              coordinator.draft.isSourceConfirmed,
              coordinator.draft.confirmedSizeRequests.first?.extractedText != nil else {
            return "absent"
        }
        return "present"
    }

    private var ocrSizeRequestProbe: String {
        guard coordinator.draft.source == .ocr,
              coordinator.draft.isSourceConfirmed,
              let request = coordinator.draft.confirmedSizeRequests.first else {
            return "none"
        }
        let chest = request.measurements[.chestWidth]?.formatted(.number.precision(.fractionLength(0...3))) ?? "nil"
        let confidence = request.extractionConfidence?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
        return "count=\(coordinator.draft.confirmedSizeRequests.count)|label=\(request.sizeLabel)|chest=\(chest)|text=\(request.extractedText ?? "nil")|confidence=\(confidence)"
    }

    private var productRequestProbe: String {
        guard let request = coordinator.fixtureAPI?.lastProductRequest else { return "none" }
        return "name=\(request.productName)|category=\(request.category.rawValue)"
    }

    private var submissionLedgerSummary: String {
        func count(_ exact: String) -> Int {
            fixtureAPIRequestLedger.filter { $0 == exact }.count
        }
        return [
            "references=\(fixtureAPIRequestLedger.filter { $0.hasPrefix("references:") }.count)",
            "product=\(count("create-product"))",
            "M-attempts=\(count("create-size:M:attempt"))",
            "M-success=\(count("create-size:M:success"))",
            "L-attempts=\(count("create-size:L:attempt"))",
            "L-success=\(count("create-size:L:success"))",
            "recommend=\(count("recommend"))",
            "report=\(fixtureAPIRequestLedger.filter { $0.hasPrefix("report:") }.count)",
        ].joined(separator: "|")
    }

    private var historyDebugControls: some View {
        HStack(spacing: 4) {
            Button("51개 저장") { Task { await coordinator.seedRetentionHistory() } }
                .accessibilityIdentifier("fitlab-history-seed-retention")
            Button("B 사용자") { Task { await coordinator.debugSwitchHistoryUser(to: "history-user-b") } }
                .accessibilityIdentifier("fitlab-history-switch-user-b")
            Button("A 사용자") { Task { await coordinator.debugSwitchHistoryUser(to: "history-user-a") } }
                .accessibilityIdentifier("fitlab-history-switch-user-a")
            Button("중복 저장") { Task { await coordinator.saveDuplicateHistory() } }
                .accessibilityIdentifier("fitlab-history-save-duplicate")
            Button("감사") { Task { await coordinator.runHistoryStoreAudit() } }
                .accessibilityIdentifier("fitlab-history-run-store-audit")
            Button("경쟁") { Task { await coordinator.runHistoryRaceAudit() } }
                .accessibilityIdentifier("fitlab-history-run-race-audit")
            Button("F2 감사") { Task { await coordinator.runHistoryF2Audit() } }
                .accessibilityIdentifier("fitlab-history-run-f2-audit")
            Button("손상") { Task { await coordinator.corruptHistory() } }
                .accessibilityIdentifier("fitlab-history-corrupt")
        }
        .font(.system(size: 7))
        .padding(4)
        .background(Color.white.opacity(0.94))
        .accessibilityElement(children: .contain)
        .overlay {
            Text(coordinator.historyRaceProbe)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("fitlab-history-race-probe")
        }
    }
    #endif

    private func loadSubmissionReferences() async {
        #if DEBUG
        if coordinator.fixtureName != nil {
            await coordinator.loadCompatibleReferences()
            return
        }
        #endif
        guard let session = backendSession.session else {
            await coordinator.loadCompatibleReferences(authenticatedUserID: nil)
            return
        }
        let api = CoorditFitLabHTTPAPI(
            baseURL: CoorditBackendConfig.baseURL(),
            accessToken: session.accessToken
        )
        await coordinator.loadCompatibleReferences(using: api, authenticatedUserID: session.user.id)
    }

    private func submitAnalysis() {
        #if DEBUG
        if coordinator.fixtureName != nil {
            guard consumeThreadIfNeededForNewSubmission() else {
                onInsufficientThread()
                return
            }
            coordinator.startSubmission()
            onRouteChange(.fitLabLoading)
            return
        }
        #endif
        guard let session = backendSession.session else {
            coordinator.startSubmission(authenticatedUserID: nil)
            onRouteChange(.fitLabLoading)
            return
        }
        let api = CoorditFitLabHTTPAPI(
            baseURL: CoorditBackendConfig.baseURL(),
            accessToken: session.accessToken
        )
        coordinator.startSubmission(using: api, authenticatedUserID: session.user.id)
        onRouteChange(.fitLabLoading)
    }

    private func consumeThreadIfNeededForNewSubmission() -> Bool {
        guard currentRoute == .fitLabInput else { return true }
        guard CoorditFitLabDraftValidation.submissionError(for: coordinator.draft) == nil else {
            return true
        }
        guard threadBalance > 0 else { return false }
        threadBalance -= 1
        return true
    }

    @ViewBuilder
    private func fixtureContent(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(14)) {
            switch coordinator.screen {
            case .input:
                Text("\(coordinator.draft.productName) · \(coordinator.draft.category.rawValue)")
                    .font(.headline)
                    .accessibilityIdentifier("fitlab-fixture-input-ready")
                Text("사이즈 \(coordinator.draft.sizes.first?.label ?? "-") · 기준 옷 \(coordinator.draft.selectedReferenceIDs.count)개")
                    .font(.subheadline)
                Text("저장한 핏 분석이 아직 없어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("fitlab-history-empty")
                Button("핏 분석 시작") {
                    coordinator.startSubmission()
                }
                .buttonStyle(
                    CoorditContentActionButtonStyle(
                        prominence: .primary,
                        height: metrics.value(48),
                        cornerRadius: metrics.value(7),
                        fontSize: metrics.value(13)
                    )
                )
                fixtureRequestLedgerCount
            case .loading:
                ProgressView()
                Text("사이즈 생성 중")
                    .font(.headline)
                    .accessibilityIdentifier("fitlab-fixture-loading-submitting")
                Text("단계: \(coordinator.submissionStep.rawValue)")
                    .font(.caption)
            case .resultUpper:
                fixtureRecommendation(
                    identifier: "fitlab-fixture-result-upper",
                    prefix: "추천"
                )
            case .resultLower:
                fixtureRecommendation(
                    identifier: "fitlab-fixture-result-lower",
                    prefix: "추천"
                )
            case .historyRegister:
                fixtureRecommendation(
                    identifier: "fitlab-fixture-history-register",
                    prefix: "저장 대기"
                )
            case .historyDetail:
                fixtureRecommendation(
                    identifier: "fitlab-fixture-history-detail",
                    prefix: "저장된 분석"
                )
                Text(coordinator.report?.report.summary ?? "리포트 없음")
                    .font(.body)
            case .loginRequired:
                Text("핏 분석을 시작하려면 로그인이 필요해요.")
                    .font(.body)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("핏 분석을 시작하려면 로그인이 필요해요.")
                    .accessibilityIdentifier("fitlab-login-required")
                fixtureRequestLedgerCount
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.value(32))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func fixtureRecommendation(identifier: String, prefix: String) -> some View {
        if let recommendation = coordinator.recommendation {
            Text("\(prefix) \(recommendation.recommendedSize) · \(CoorditFitLabResultMeasurement.score(recommendation.fitScore))점")
                .font(.title3.bold())
                .accessibilityIdentifier(identifier)
            Text(recommendation.fitComment)
                .font(.body)
            Text(coordinator.report?.report.title ?? "리포트 준비 중")
                .font(.headline)
        } else {
            Text("추천 데이터 없음")
                .accessibilityIdentifier(identifier)
        }
    }

    #if DEBUG
    private var fixtureRequestLedgerCount: some View {
        let count = coordinator.fixtureAPI?.requestLedger.count ?? 0
        return Text("\(count)")
            .font(.caption)
            .accessibilityLabel("\(count)")
            .accessibilityIdentifier("fitlab-fixture-api-request-ledger-count")
    }
    #else
    private var fixtureRequestLedgerCount: some View { EmptyView() }
    #endif
}

private struct CoorditGmarketBoldFontDiagnostic: View {
    var body: some View {
#if DEBUG && canImport(UIKit)
        if ProcessInfo.processInfo.arguments.contains("--coordit-ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--coordit-test-font-diagnostic") {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("coordit-gmarket-bold-font-available")
                .accessibilityValue(
                    UIFont(name: CoorditTypography.PostScriptName.gmarketSansBold, size: 22) == nil
                        ? "false"
                        : "true"
                )
                .allowsHitTesting(false)
        }
#endif
    }
}

struct CoorditFitLabScreens: View {
    let currentRoute: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void
    @ObservedObject var coordinator: CoorditFitLabCoordinator
    @State private var threadBalance = 36

    var body: some View {
        CoorditFitLabFamilyView(
            currentRoute: currentRoute,
            onRouteChange: onRouteChange,
            onManageReferences: {},
            coordinator: coordinator,
            threadBalance: $threadBalance,
            sharedImportURL: .constant(nil),
            onInsufficientThread: { onRouteChange(.myPageThreadCharge) },
            onOpenThreadRecharge: { onRouteChange(.myPageThreadCharge) }
        )
    }
}

private struct CoorditFitLabLoadingScreen: View {
    let metrics: CoorditResponsiveMetrics
    @ObservedObject var coordinator: CoorditFitLabCoordinator
    let retry: () -> Void

    var body: some View {
        VStack(spacing: metrics.value(16)) {
            Spacer(minLength: 0)
            CoorditOrbitLoadingIndicator(metrics: metrics)
            Text("핏 리포트를 만들고 있어요")
                .font(CoorditTypography.gmarketMedium(size: metrics.value(16), relativeTo: .body))
                .foregroundStyle(Color.black.opacity(0.76))

            Text(statusMessage)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(CoorditFitLabPalette.muted)
                .multilineTextAlignment(.center)

            if coordinator.submissionStep == .generatingReport {
                Text("상세 리포트 1개 생성에 실타래 1개가 사용돼요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditFitLabPalette.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("fitlab-report-thread-cost-notice")
            }

            if let error = coordinator.error {
                VStack(spacing: metrics.value(10)) {
                    Text(error.errorDescription ?? "핏 리포트를 완성하지 못했어요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(CoorditDesignTokens.ColorToken.danger)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("fitlab-loading-error")

                    Button("다시 시도하기", action: retry)
                        .buttonStyle(
                            CoorditContentActionButtonStyle(
                                prominence: .primary,
                                height: metrics.value(46),
                                cornerRadius: metrics.value(7),
                                fontSize: metrics.value(12)
                            )
                        )
                        .accessibilityIdentifier("fitlab-loading-retry")
                }
                .padding(.horizontal, metrics.value(30))
            }
            Spacer(minLength: metrics.value(288))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusMessage: String {
        switch coordinator.submissionStep {
        case .creatingProduct, .creatingSizes:
            "상품과 사이즈 정보를 확인하고 있어요."
        case .recommending:
            "기준 옷과 비교해 핏 스코어를 계산하고 있어요."
        case .generatingReport:
            "핏 스코어를 바탕으로 상세 리포트를 작성하고 있어요."
        default:
            "핏 분석을 준비하고 있어요."
        }
    }
}

private struct CoorditFitLabResultScreen: View {
    let variant: CoorditFitLabResultVariant
    let recommendation: CoorditFitLabRecommendationResponse?
    let report: CoorditFitLabReportResponse?
    let sizeDrafts: [CoorditFitLabSizeDraft]
    let fallbackMessage: String?
    let canSaveHistory: Bool
    let isSaved: Bool
    let metrics: CoorditResponsiveMetrics
    let saveHistory: () async -> Bool
    let retryReport: () async -> Void
    let finishReport: () -> Void
    @State private var didSave = false
    @State private var isSaving = false
    @State private var isRetryingReport = false
    @State private var selectedSizeLabel: String?

    var body: some View {
        let sizeOptions = recommendation.map {
            CoorditFitLabSizeOption.makeOptions(
                variant: variant,
                recommendation: $0,
                report: report,
                sizeDrafts: sizeDrafts
            )
        } ?? []
        let selectedSize = sizeOptions.first { $0.sizeLabel == selectedSizeLabel }
            ?? sizeOptions.first { $0.isRecommended }
            ?? sizeOptions.first
        let scoreCard = CoorditFitLabScoreCard(
            variant: variant,
            selectedSize: selectedSize,
            metrics: metrics
        )
        ScrollView {
            VStack(spacing: metrics.value(14)) {
                scoreCard

                CoorditFitLabMannequinPanel(
                    assetName: variant.assetName,
                    metrics: metrics,
                    measurements: scoreCard.measurements
                )
                .frame(height: metrics.value(270))
                CoorditFitLabOverlayLegend(metrics: metrics)

                CoorditFitLabSizeScoreChart(
                    options: sizeOptions,
                    selectedSizeLabel: $selectedSizeLabel,
                    metrics: metrics
                )

                CoorditFitLabDifferenceChart(
                    measurements: scoreCard.measurements,
                    metrics: metrics
                )

                CoorditFitLabReportCard(
                    report: report,
                    fallbackMessage: fallbackMessage,
                    metrics: metrics
                )

                if fallbackMessage != nil {
                    Button(isRetryingReport ? "리포트 다시 시도 중..." : "리포트 다시 시도") {
                        guard !isRetryingReport else { return }
                        isRetryingReport = true
                        Task {
                            await retryReport()
                            isRetryingReport = false
                        }
                    }
                    .buttonStyle(
                        CoorditContentActionButtonStyle(
                            prominence: .primary,
                            height: metrics.value(48),
                            cornerRadius: metrics.value(7),
                            fontSize: metrics.value(13)
                        )
                    )
                    .disabled(isRetryingReport)
                    .accessibilityIdentifier("fitlab-retry-report")
                }

                if canSaveHistory {
                    CoorditFitLabPrimaryButton(
                        title: didSave || isSaved ? "히스토리에 저장됨" : (isSaving ? "저장 중..." : "히스토리에 추가"),
                        metrics: metrics
                    ) {
                        guard !isSaving, !didSave, !isSaved else { return }
                        isSaving = true
                        Task { @MainActor in
                            let saved = await saveHistory()
                            isSaving = false
                            guard saved else { return }
                            didSave = true
                            finishReport()
                        }
                    }
                    .accessibilityIdentifier("fitlab-add-history")
                } else {
                    Text("기준 옷 비교를 완성한 뒤 히스토리에 저장할 수 있어요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("fitlab-history-awaiting-report")
                }

                if didSave || isSaved {
                    Text("분석 결과를 히스토리에 저장했어요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .caption))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .accessibilityIdentifier("fitlab-history-saved-confirmation")
                }

                Button("확인하기") {
                    finishReport()
                }
                .buttonStyle(
                    CoorditContentActionButtonStyle(
                        prominence: .secondary,
                        height: metrics.value(48),
                        cornerRadius: metrics.value(7),
                        fontSize: metrics.value(14)
                    )
                )
                .accessibilityIdentifier("fitlab-confirm-report")

                Text(
                    didSave || isSaved
                        ? "저장한 리포트는 핏랩과 홈의 최근 히스토리에서 다시 확인할 수 있어요."
                        : "확인하기를 누르면 이 리포트는 저장되지 않고 핏랩으로 돌아가요."
                )
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(Color.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fitlab-confirm-report-guide")

                #if DEBUG
                if let recommendation {
                    Text("추천 \(recommendation.recommendedSize) · \(CoorditFitLabResultMeasurement.score(recommendation.fitScore))점")
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .accessibilityIdentifier(variant == .bottom ? "fitlab-fixture-result-lower" : "fitlab-fixture-result-upper")
                }
                #endif
            }
            .padding(.horizontal, metrics.value(24))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .onChange(of: recommendation?.fitAnalysisResultID) { _, _ in
            selectedSizeLabel = nil
        }
    }
}

private struct CoorditFitLabHistoryRegisterScreen: View {
    let metrics: CoorditResponsiveMetrics
    let onRouteChange: (CoorditFrameRoute) -> Void

    var body: some View {
        VStack(spacing: metrics.value(12)) {
            HStack(spacing: metrics.value(8)) {
                CoorditFitLabMannequinPanel(assetName: CoorditFitLabResultVariant.bottom.assetName, metrics: metrics)
                    .frame(width: metrics.value(109), height: metrics.value(240))

                CoorditFitLabScoreCard(variant: .bottom, metrics: metrics)
                    .frame(width: metrics.value(229), height: metrics.value(240))
            }

            CoorditFitLabDescriptionCard(metrics: metrics, compact: false, onDetail: nil)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(263))

            CoorditFitLabPrimaryButton(title: "히스토리에 추가", metrics: metrics) {
                onRouteChange(.fitLabHistoryDetail)
            }
        }
        .padding(.horizontal, metrics.value(28))
    }
}

private extension CoorditFrameRoute {
    var fitLabAccessibilityIdentifier: String {
        switch self {
        case .fitLabInput,
             .fitLabLoading,
             .fitLabResultTop,
             .fitLabResultBottom,
             .fitLabHistoryRegister,
             .fitLabHistoryDetail:
            "coordit-screen-\(rawValue)"
        default:
            "coordit-screen-fitlab-input"
        }
    }
}
#endif
