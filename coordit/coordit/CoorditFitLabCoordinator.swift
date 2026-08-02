import Foundation
import Combine

#if os(iOS)
enum CoorditFitLabAnalysisState: Equatable {
    case idle
    case running
    case completed(CoorditFrameRoute)
    case failed(String)
}

@MainActor
final class CoorditFitLabCoordinator: ObservableObject {
    @Published var draft: CoorditFitLabDraft
    @Published private(set) var references: [CoorditFitLabReferenceRow] = []
    @Published private(set) var createdProductID: String?
    @Published private(set) var createdSizeIDs: [String] = []
    @Published private(set) var checkpoint = CoorditFitLabSubmissionCheckpoint()
    @Published private(set) var recommendation: CoorditFitLabRecommendationResponse?
    @Published private(set) var report: CoorditFitLabReportResponse?
    @Published var selectedHistory: CoorditFitLabHistorySnapshot?
    @Published private(set) var savedHistory: [CoorditFitLabHistorySnapshot] = []
    @Published private(set) var historyRecoveryNotice: String?
    @Published private(set) var activeHistoryUserID: String?
    @Published private(set) var error: CoorditFitLabError?
    @Published private(set) var retryStep: CoorditFitLabSubmissionStep?
    @Published private(set) var submissionStep: CoorditFitLabSubmissionStep = .idle
    @Published private(set) var loadState: CoorditFitLabLoadState = .idle
    @Published private(set) var screen: CoorditFitLabScreen
    @Published private(set) var analysisState: CoorditFitLabAnalysisState = .idle
    @Published private(set) var isAnalysisNoticeVisible = false

    let userID: String?
    let fixtureName: String?
    private let api: (any CoorditFitLabAPI)?
    private let historyStore: (any CoorditFitLabHistoryStoring)?
    #if DEBUG
    private(set) var fixtureAPI: CoorditFitLabFixtureAPI?
    #endif
    private var operationGeneration = 0
    private var submissionTask: Task<Void, Never>?
    private var historyGeneration = 0
    private var historyMutationTask: Task<Bool, Never>?
    private var historyMutationGeneration = 0
    #if DEBUG
    @Published private(set) var historyEdgeProbe = "idle"
    @Published private(set) var historyUserProbe = "idle"
    @Published private(set) var historyStoreAudit = "idle"
    @Published private(set) var historyRaceProbe = "idle"
    @Published private(set) var historyF2Probe = "idle"
    @Published private(set) var historyQuarantineCount = 0
    #endif

    init(
        route: CoorditFrameRoute,
        configuration: CoorditFitLabFixtureConfiguration,
        api: (any CoorditFitLabAPI)? = nil,
        historyStore: (any CoorditFitLabHistoryStoring)? = nil
    ) {
        self.userID = configuration.userID
        self.fixtureName = configuration.name
        self.api = api
        self.historyStore = historyStore
        self.activeHistoryUserID = configuration.userID
        #if DEBUG
        self.fixtureAPI = api as? CoorditFitLabFixtureAPI
        #endif
        self.draft = CoorditFitLabDraft()
        self.screen = Self.screen(for: route)
        #if DEBUG
        if configuration.name != nil {
            if configuration.name?.hasPrefix("submission-") == true {
                self.draft = CoorditFitLabFixtures.submissionDraft
            } else {
                self.draft = CoorditFitLabFixtures.upperDraft
            }
            seed(route: route, fixture: configuration.name)
        }
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("--coordit-test-analysis-running-then-completed") {
            analysisState = .running
            isAnalysisNoticeVisible = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.analysisState = .completed(.fitLabResultTop)
                self?.isAnalysisNoticeVisible = true
            }
        } else if launchArguments.contains("--coordit-test-analysis-running") {
            analysisState = .running
            isAnalysisNoticeVisible = true
        } else if launchArguments.contains("--coordit-test-analysis-completed") {
            analysisState = .completed(.fitLabResultTop)
            isAnalysisNoticeVisible = true
        }
        #endif
    }

    static func makeAppScoped(route: CoorditFrameRoute) -> CoorditFitLabCoordinator {
        let configuration = CoorditFitLabFixtureConfiguration.launch()
        #if DEBUG
        if configuration.name != nil {
            if configuration.resetsHistory, let directory = configuration.historyRootDirectory {
                CoorditFitLabHistoryFixtureResetRegistry.resetOnce(directory)
            }
            let historyStore: any CoorditFitLabHistoryStoring
            if let directory = configuration.historyRootDirectory {
                historyStore = CoorditFitLabFileHistoryStore(rootDirectory: directory)
            } else {
                historyStore = CoorditFitLabFixtureHistoryStore()
            }
            return CoorditFitLabCoordinator(
                route: route,
                configuration: configuration,
                api: CoorditFitLabFixtureAPI(fixtureName: configuration.name),
                historyStore: historyStore
            )
        }
        #endif
        return CoorditFitLabCoordinator(
            route: route,
            configuration: configuration,
            historyStore: CoorditFitLabFileHistoryStore()
        )
    }

    var isAnalysisRunning: Bool {
        if case .running = analysisState { return true }
        return false
    }

    func startSubmission(
        using overrideAPI: (any CoorditFitLabAPI)? = nil,
        authenticatedUserID: String? = nil
    ) {
        guard submissionTask == nil, loadState != .loading else { return }
        analysisState = .running
        isAnalysisNoticeVisible = true
        screen = .loading
        submissionTask = Task { [weak self] in
            guard let self else { return }
            await self.submit(using: overrideAPI, authenticatedUserID: authenticatedUserID)
            self.finishBackgroundSubmission()
        }
    }

    private func finishBackgroundSubmission() {
        submissionTask = nil
        if submissionStep == .complete,
           recommendation != nil,
           report != nil {
            analysisState = .completed(
                draft.garmentKind == .upper ? .fitLabResultTop : .fitLabResultBottom
            )
            isAnalysisNoticeVisible = true
        } else if let error {
            analysisState = .failed(error.errorDescription ?? "핏 분석을 완료하지 못했어요.")
            isAnalysisNoticeVisible = true
        } else {
            analysisState = .idle
            isAnalysisNoticeVisible = false
        }
    }

    func dismissAnalysisNotice() {
        isAnalysisNoticeVisible = false
    }

    var fixtureAccessibilityIdentifier: String {
        switch screen {
        case .input: "fitlab-fixture-input-ready"
        case .loading: "fitlab-fixture-loading-submitting"
        case .resultUpper: "fitlab-fixture-result-upper"
        case .resultLower: "fitlab-fixture-result-lower"
        case .historyRegister: "fitlab-fixture-history-register"
        case .historyDetail: "fitlab-fixture-history-detail"
        case .loginRequired: "fitlab-login-required"
        }
    }

    func prefillProduct(
        from url: URL,
        category: CoorditFitLabCategory
    ) async throws -> CoorditFitLabURLPrefillResponse {
        guard let api else {
            throw CoorditFitLabError.transport("상품 링크 API를 준비할 수 없어요.")
        }
        return try await api.prefillProduct(
            from: CoorditFitLabURLPrefillRequest(url: url, category: category)
        )
    }

    func fetchCompatibleReferences(
        category: CoorditFitLabCategory,
        using overrideAPI: (any CoorditFitLabAPI)? = nil
    ) async throws -> [CoorditFitLabReferenceRow] {
        guard let selectedAPI = overrideAPI ?? api else {
            throw CoorditFitLabError.transport("기준 옷 API를 준비할 수 없어요.")
        }
        return try await selectedAPI.compatibleReferences(category: category)
    }

    func loadCompatibleReferences(
        using overrideAPI: (any CoorditFitLabAPI)? = nil,
        authenticatedUserID: String? = nil
    ) async {
        guard loadState != .loading else { return }
        guard (authenticatedUserID ?? userID) != nil else {
            error = .loginRequired
            retryStep = .idle
            loadState = .failed(.loginRequired)
            screen = .loginRequired
            return
        }
        guard let selectedAPI = overrideAPI ?? api else {
            error = .transport("핏 분석 API를 준비할 수 없어요.")
            loadState = .failed(error ?? .malformedResponse)
            return
        }

        operationGeneration += 1
        let generation = operationGeneration
        error = nil
        retryStep = nil
        do {
            loadState = .loading
            submissionStep = .loadingReferences
            let requestedCategory = draft.category
            let loadedReferences = try await selectedAPI.compatibleReferences(category: requestedCategory)
            guard generation == operationGeneration, !Task.isCancelled else { return }
            references = loadedReferences.filter {
                $0.category.isCompatible(with: requestedCategory) && $0.isActive
            }
            draft.selectedReferenceIDs.formIntersection(Set(references.map(\.id)))
            submissionStep = .idle
            loadState = .loaded
            error = nil
            retryStep = nil
        } catch let fitError as CoorditFitLabError {
            guard generation == operationGeneration else { return }
            error = fitError
            retryStep = submissionStep
            loadState = .failed(fitError)
        } catch {
            guard generation == operationGeneration else { return }
            let wrapped = CoorditFitLabError.transport(error.localizedDescription)
            self.error = wrapped
            retryStep = submissionStep
            loadState = .failed(wrapped)
        }
    }

    var canSubmit: Bool {
        guard draft.isSourceConfirmed, !draft.sizes.isEmpty else { return false }
        let compatibleIDs = Set(references.filter {
            $0.category.isCompatible(with: draft.category) && $0.isActive
        }.map(\.id))
        return !draft.selectedReferenceIDs.isEmpty && draft.selectedReferenceIDs.isSubset(of: compatibleIDs)
    }

    func toggleReference(_ reference: CoorditFitLabReferenceRow) {
        guard loadState != .loading,
              reference.category.isCompatible(with: draft.category),
              reference.isActive,
              references.contains(where: { $0.id == reference.id })
        else { return }
        if draft.selectedReferenceIDs.contains(reference.id) {
            draft.selectedReferenceIDs.remove(reference.id)
        } else {
            draft.selectedReferenceIDs.insert(reference.id)
        }
        error = nil
    }

    func submit(
        using overrideAPI: (any CoorditFitLabAPI)? = nil,
        authenticatedUserID: String? = nil
    ) async {
        guard loadState != .loading else { return }
        guard (authenticatedUserID ?? userID) != nil else {
            fail(.loginRequired, at: .idle)
            screen = .loginRequired
            return
        }
        guard let selectedAPI = overrideAPI ?? api else {
            fail(.transport("핏 분석 API를 준비할 수 없어요."), at: .idle)
            return
        }
        if let validationError = CoorditFitLabDraftValidation.submissionError(for: draft) {
            fail(.invalidDraft(validationError), at: .idle)
            return
        }
        guard draft.isSourceConfirmed else {
            fail(.invalidDraft("사이즈표를 먼저 확인해 주세요."), at: .idle)
            return
        }
        let compatibleIDs = Set(references.filter {
            $0.category.isCompatible(with: draft.category) && $0.isActive
        }.map(\.id))
        guard !draft.selectedReferenceIDs.isEmpty,
              draft.selectedReferenceIDs.isSubset(of: compatibleIDs)
        else {
            fail(.invalidDraft("현재 카테고리와 맞는 기준 옷을 하나 이상 선택해 주세요."), at: .loadingReferences)
            return
        }

        operationGeneration += 1
        let generation = operationGeneration
        error = nil
        retryStep = nil
        loadState = .loading
        screen = .loading
        do {
            if checkpoint.productID == nil {
                submissionStep = .creatingProduct
                let product = try await selectedAPI.createProduct(productRequest)
                try ensureActive(generation)
                checkpoint.productID = product.id
                createdProductID = product.id
            }

            guard let productID = checkpoint.productID else {
                throw CoorditFitLabError.malformedResponse
            }
            for row in draft.sizes where checkpoint.sizeIDsByDraftID[row.id] == nil {
                submissionStep = .creatingSizes
                do {
                    let created = try await selectedAPI.createSize(
                        productID: productID,
                        request: sizeRequest(for: row)
                    )
                    try ensureActive(generation)
                    checkpoint.sizeIDsByDraftID[row.id] = created.id
                    createdSizeIDs = draft.sizes.compactMap { checkpoint.sizeIDsByDraftID[$0.id] }
                } catch {
                    let message = "\(row.label) 사이즈 저장에 실패했어요. 완료된 단계는 유지했어요."
                    throw CoorditFitLabError.transport(message)
                }
            }

            if recommendation == nil {
                submissionStep = .recommending
                let receivedRecommendation = try await selectedAPI.recommend(
                    CoorditFitLabRecommendationRequest(
                        referenceClothingIDs: draft.selectedReferenceIDs.sorted(),
                        externalProductID: productID,
                        idempotencyKey: checkpoint.recommendationIdempotencyKey.uuidString.lowercased()
                    )
                )
                try ensureActive(generation)
                recommendation = receivedRecommendation
            }

            guard let recommendation else { throw CoorditFitLabError.malformedResponse }
            if report == nil {
                submissionStep = .generatingReport
                do {
                    let receivedReport = try await selectedAPI.report(
                        analysisID: recommendation.fitAnalysisResultID,
                        request: CoorditFitLabReportRequest(
                            selectedSizeLabel: recommendation.recommendedSize,
                            style: nil
                        )
                    )
                    try ensureActive(generation)
                    report = receivedReport
                } catch {
                    try ensureActive(generation)
                    throw CoorditFitLabError.transport(
                        "핏 스코어 계산은 끝났지만 상세 리포트 생성이 지연되고 있어요. 다시 시도해 주세요."
                    )
                }
            }

            submissionStep = .complete
            loadState = .loaded
            screen = draft.garmentKind == .upper ? .resultUpper : .resultLower
        } catch let fitError as CoorditFitLabError {
            guard generation == operationGeneration else { return }
            fail(fitError, at: submissionStep)
        } catch {
            guard generation == operationGeneration else { return }
            fail(.transport(error.localizedDescription), at: submissionStep)
        }
    }

    func discardAndRestart() {
        submissionTask?.cancel()
        submissionTask = nil
        operationGeneration += 1
        checkpoint = CoorditFitLabSubmissionCheckpoint()
        createdProductID = nil
        createdSizeIDs = []
        recommendation = nil
        report = nil
        references = []
        draft = CoorditFitLabDraft()
        submissionStep = .idle
        loadState = .idle
        error = nil
        retryStep = nil
        screen = .input
        analysisState = .idle
        isAnalysisNoticeVisible = false
    }

    func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
        operationGeneration += 1
        submissionStep = .idle
        loadState = .idle
        error = nil
        retryStep = nil
        analysisState = .idle
        isAnalysisNoticeVisible = false
    }

    private var productRequest: CoorditFitLabProductRequest {
        CoorditFitLabProductRequest(
            productName: draft.productName,
            brand: draft.brand,
            mallName: draft.mallName,
            productURL: draft.productURL,
            category: draft.category,
            fitType: "regular"
        )
    }

    private func sizeRequest(for row: CoorditFitLabSizeDraft) -> CoorditFitLabSizeRequest {
        CoorditFitLabSizeRequest(
            sizeLabel: row.label,
            measurements: row.measurements,
            parsingStatus: draft.source == .url ? "confirmed" : nil,
            measurementSource: draft.source.rawValue,
            extractedText: draft.ocrMetadata?.extractedText,
            extractionConfidence: draft.ocrMetadata?.confidence
        )
    }

    private func ensureActive(_ generation: Int) throws {
        guard generation == operationGeneration, !Task.isCancelled else {
            throw CoorditFitLabError.cancelled
        }
    }

    private func fail(_ failure: CoorditFitLabError, at step: CoorditFitLabSubmissionStep) {
        error = failure
        retryStep = step
        loadState = .failed(failure)
    }

    func synchronize(route: CoorditFrameRoute) {
        if route == .fitLabLoading {
            screen = .loading
            return
        }
        operationGeneration += 1
        screen = Self.screen(for: route)
        error = nil
        retryStep = nil
        submissionStep = .idle
        loadState = .idle
        #if DEBUG
        if fixtureName != nil {
            seed(route: route, fixture: fixtureName)
        }
        #endif
    }

    func loadHistory() async {
        await switchHistoryUser(to: activeHistoryUserID ?? userID)
    }

    func prepareHistory(userID: String?) async {
        await switchHistoryUser(to: userID)
    }

    func switchHistoryUser(to userID: String?) async {
        historyGeneration += 1
        historyMutationGeneration += 1
        historyMutationTask?.cancel()
        historyMutationTask = nil
        let generation = historyGeneration
        activeHistoryUserID = userID
        savedHistory = []
        selectedHistory = nil
        historyRecoveryNotice = nil
        guard let userID else { return }
        await reloadHistory(userID: userID, generation: generation)
    }

    private func reloadHistory(userID: String, generation: Int) async {
        guard let historyStore else { return }
        do {
            let snapshots = try await historyStore.load(userID: userID)
            let recoveryNotice = await historyStore.recoveryNotice(userID: userID)
            guard generation == historyGeneration, activeHistoryUserID == userID else { return }
            savedHistory = snapshots
            historyRecoveryNotice = recoveryNotice
            if selectedHistory == nil,
               screen == .historyDetail || screen == .historyRegister {
                selectedHistory = snapshots.first
            }
        } catch {
            guard generation == historyGeneration, activeHistoryUserID == userID else { return }
            self.error = .transport(error.localizedDescription)
        }
    }

    @discardableResult
    func saveCurrentAnalysis(authenticatedUserID: String? = nil) async -> Bool {
        guard
            let historyStore,
            let userID = authorizedHistoryUser(authenticatedUserID),
            let snapshot = makeHistorySnapshot(userID: userID, savedAt: Date())
        else { return false }
        let generation = historyGeneration
        historyMutationTask?.cancel()
        historyMutationGeneration += 1
        let mutationGeneration = historyMutationGeneration
        let task = Task { () -> Bool in
            do {
                try Task.checkCancellation()
                try await historyStore.save(snapshot)
                try Task.checkCancellation()
                return true
            } catch { return false }
        }
        historyMutationTask = task
        let stored = await task.value
        guard mutationGeneration == historyMutationGeneration else { return false }
        historyMutationTask = nil
        do {
            guard stored else { throw CancellationError() }
            guard generation == historyGeneration, activeHistoryUserID == userID else { return true }
            await reloadHistory(userID: userID, generation: generation)
            guard generation == historyGeneration, activeHistoryUserID == userID else { return true }
            selectedHistory = savedHistory.first { $0.analysisID == snapshot.analysisID }
            return true
        } catch {
            guard generation == historyGeneration, activeHistoryUserID == userID else { return false }
            self.error = .transport(error.localizedDescription)
            return false
        }
    }

    func selectHistory(_ snapshot: CoorditFitLabHistorySnapshot) {
        guard snapshot.userID == activeHistoryUserID else { return }
        selectedHistory = snapshot
    }

    @discardableResult
    func deleteSelectedHistory(authenticatedUserID: String? = nil) async -> Bool {
        guard let historyStore, let selectedHistory,
              let userID = authorizedHistoryUser(authenticatedUserID),
              selectedHistory.userID == userID else { return false }
        let generation = historyGeneration
        historyMutationTask?.cancel()
        historyMutationGeneration += 1
        let mutationGeneration = historyMutationGeneration
        let task = Task { () -> Bool in
            do {
                try Task.checkCancellation()
                try await historyStore.delete(snapshotID: selectedHistory.id, userID: userID)
                try Task.checkCancellation()
                return true
            } catch { return false }
        }
        historyMutationTask = task
        let deleted = await task.value
        guard mutationGeneration == historyMutationGeneration else { return false }
        historyMutationTask = nil
        do {
            guard deleted else { throw CancellationError() }
            guard generation == historyGeneration, activeHistoryUserID == userID else { return true }
            self.selectedHistory = nil
            await reloadHistory(userID: userID, generation: generation)
            return true
        } catch {
            guard generation == historyGeneration, activeHistoryUserID == userID else { return false }
            self.error = .transport(error.localizedDescription)
            return false
        }
    }

    private func authorizedHistoryUser(_ authenticatedUserID: String?) -> String? {
        #if DEBUG
        if fixtureName != nil {
            let candidate = authenticatedUserID ?? activeHistoryUserID ?? userID
            return candidate == activeHistoryUserID ? candidate : nil
        }
        #endif
        guard let authenticatedUserID, authenticatedUserID == activeHistoryUserID else { return nil }
        return authenticatedUserID
    }

    private func makeHistorySnapshot(
        userID: String,
        savedAt: Date,
        analysisID: String? = nil,
        recommendation overrideRecommendation: CoorditFitLabRecommendationResponse? = nil
    ) -> CoorditFitLabHistorySnapshot? {
        guard let recommendation = overrideRecommendation ?? recommendation else { return nil }
        let resolvedAnalysisID = analysisID ?? recommendation.fitAnalysisResultID
        let referenceSummaries = draft.selectedReferenceIDs.sorted().map { id in
            let reference = references.first { $0.id == id }
            return CoorditFitLabHistorySnapshot.ReferenceSummary(
                id: id,
                name: reference?.nickname ?? reference?.clothingItemID ?? id
            )
        }
        return CoorditFitLabHistorySnapshot(
            id: resolvedAnalysisID,
            analysisID: resolvedAnalysisID,
            userID: userID,
            savedAt: savedAt,
            product: .init(
                name: draft.productName,
                brand: draft.brand,
                mallName: draft.mallName,
                url: draft.productURL
            ),
            category: draft.category,
            garmentKind: draft.garmentKind,
            references: referenceSummaries,
            originalSource: draft.source,
            recommendation: recommendation,
            report: report,
            chartData: report?.chartData ?? .init()
        )
    }

    #if DEBUG
    func seedRetentionHistory() async {
        guard let historyStore, let userID = activeHistoryUserID else { return }
        let base = CoorditFitLabFixtures.upperRecommendation
        for index in 1...51 {
            let recommendation = CoorditFitLabRecommendationResponse(
                fitAnalysisResultID: "analysis-\(index)",
                recommendedSize: base.recommendedSize,
                fitScore: base.fitScore,
                fitLabel: base.fitLabel,
                fitComment: base.fitComment,
                recommendationConfidence: base.recommendationConfidence,
                diff: base.diff
            )
            if let snapshot = makeHistorySnapshot(
                userID: userID,
                savedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                analysisID: "analysis-\(index)",
                recommendation: recommendation
            ) {
                try? await historyStore.save(snapshot)
            }
        }
        await switchHistoryUser(to: userID)
        updateHistoryEdgeProbe()
    }

    func saveDuplicateHistory() async {
        guard let historyStore, let userID = activeHistoryUserID else { return }
        let base = CoorditFitLabFixtures.upperRecommendation
        let recommendation = CoorditFitLabRecommendationResponse(
            fitAnalysisResultID: "analysis-51",
            recommendedSize: base.recommendedSize,
            fitScore: base.fitScore,
            fitLabel: base.fitLabel,
            fitComment: base.fitComment,
            recommendationConfidence: base.recommendationConfidence,
            diff: base.diff
        )
        if let snapshot = makeHistorySnapshot(
            userID: userID,
            savedAt: Date(timeIntervalSince1970: 10_000),
            analysisID: "analysis-51",
            recommendation: recommendation
        ) {
            try? await historyStore.save(snapshot)
        }
        await switchHistoryUser(to: userID)
        updateHistoryEdgeProbe()
    }

    func debugSwitchHistoryUser(to userID: String) async {
        await switchHistoryUser(to: userID)
        historyUserProbe = "user=\(userID)|count=\(savedHistory.count)"
    }

    func corruptHistory() async {
        guard
            let userID = activeHistoryUserID,
            let store = historyStore as? CoorditFitLabFileHistoryStore
        else { return }
        do {
            try await store.debugCorrupt(userID: userID)
            await switchHistoryUser(to: userID)
            historyQuarantineCount = try await store.debugQuarantineCount(userID: userID)
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func runHistoryStoreAudit() async {
        guard
            let userID = activeHistoryUserID,
            let store = historyStore as? CoorditFitLabFileHistoryStore,
            let sample = makeHistorySnapshot(
                userID: userID,
                savedAt: Date(),
                recommendation: CoorditFitLabFixtures.upperRecommendation
            )
        else { return }
        historyStoreAudit = await store.debugAudit(sample: sample)
    }

    func runHistoryRaceAudit() async {
        let userA = "history-user-a"
        let userB = "history-user-b"
        let userASnapshot = Self.raceSnapshot(userID: userA, analysisID: "race-a")
        let userBSnapshot = Self.raceSnapshot(userID: userB, analysisID: "race-b")

        let loadStore = CoorditFitLabSuspendingHistoryStore(
            snapshots: [userASnapshot, userBSnapshot],
            suspendedLoadUserID: userA
        )
        let loadCoordinator = CoorditFitLabCoordinator(
            route: .fitLabInput,
            configuration: .init(name: "history-edge", userID: userA, historyRootDirectory: nil, resetsHistory: false),
            historyStore: loadStore
        )
        let loadTask = Task { await loadCoordinator.prepareHistory(userID: userA) }
        await loadStore.waitForLoadStart()
        await loadCoordinator.prepareHistory(userID: userB)
        await loadStore.releaseLoad()
        await loadTask.value
        let loadPassed = loadCoordinator.activeHistoryUserID == userB
            && loadCoordinator.savedHistory == [userBSnapshot]

        let saveStore = CoorditFitLabSuspendingHistoryStore(snapshots: [userBSnapshot])
        let saveCoordinator = CoorditFitLabCoordinator(
            route: .fitLabResultTop,
            configuration: .init(name: "upper-result", userID: userA, historyRootDirectory: nil, resetsHistory: false),
            historyStore: saveStore
        )
        await saveCoordinator.prepareHistory(userID: userA)
        let saveTask = Task { await saveCoordinator.saveCurrentAnalysis(authenticatedUserID: userA) }
        await saveStore.waitForSaveStart()
        await saveCoordinator.prepareHistory(userID: userB)
        await saveStore.releaseSave()
        _ = await saveTask.value
        let savePassed = saveCoordinator.activeHistoryUserID == userB
            && saveCoordinator.savedHistory == [userBSnapshot]

        let deleteStore = CoorditFitLabSuspendingHistoryStore(snapshots: [userASnapshot, userBSnapshot])
        let deleteCoordinator = CoorditFitLabCoordinator(
            route: .fitLabInput,
            configuration: .init(name: "history-edge", userID: userA, historyRootDirectory: nil, resetsHistory: false),
            historyStore: deleteStore
        )
        await deleteCoordinator.prepareHistory(userID: userA)
        deleteCoordinator.selectHistory(userASnapshot)
        let deleteTask = Task { await deleteCoordinator.deleteSelectedHistory() }
        await deleteStore.waitForDeleteStart()
        await deleteCoordinator.prepareHistory(userID: userB)
        await deleteStore.releaseDelete()
        _ = await deleteTask.value
        let deletePassed = deleteCoordinator.activeHistoryUserID == userB
            && deleteCoordinator.savedHistory == [userBSnapshot]
            && deleteCoordinator.selectedHistory == nil

        historyRaceProbe = "load=\(loadPassed ? "pass" : "fail")|save=\(savePassed ? "pass" : "fail")|delete=\(deletePassed ? "pass" : "fail")"
    }

    func runHistoryF2Audit() async {
        let userA = "history-user-a"
        let userB = "history-user-b"

        let saveStore = CoorditFitLabSuspendingHistoryStore(snapshots: [])
        let saveCoordinator = CoorditFitLabCoordinator(
            route: .fitLabResultTop,
            configuration: .init(name: "upper-result", userID: userA, historyRootDirectory: nil, resetsHistory: false),
            historyStore: saveStore
        )
        await saveCoordinator.prepareHistory(userID: userA)
        let saveTask = Task { await saveCoordinator.saveCurrentAnalysis(authenticatedUserID: userA) }
        await saveStore.waitForSaveStart()
        await saveCoordinator.prepareHistory(userID: nil)
        await saveStore.releaseSave()
        _ = await saveTask.value
        let savePassed = !(await saveStore.contains(analysisID: "analysis-fixture-upper", userID: userA))
            && saveCoordinator.activeHistoryUserID == nil
            && saveCoordinator.savedHistory.isEmpty

        let userASnapshot = Self.raceSnapshot(userID: userA, analysisID: "race-a")
        let deleteStore = CoorditFitLabSuspendingHistoryStore(snapshots: [userASnapshot])
        let deleteCoordinator = CoorditFitLabCoordinator(
            route: .fitLabInput,
            configuration: .init(name: "history-edge", userID: userA, historyRootDirectory: nil, resetsHistory: false),
            historyStore: deleteStore
        )
        await deleteCoordinator.prepareHistory(userID: userA)
        deleteCoordinator.selectHistory(userASnapshot)
        let deleteTask = Task { await deleteCoordinator.deleteSelectedHistory(authenticatedUserID: userA) }
        await deleteStore.waitForDeleteStart()
        await deleteCoordinator.prepareHistory(userID: userB)
        await deleteStore.releaseDelete()
        _ = await deleteTask.value
        let deletePassed = await deleteStore.contains(analysisID: "race-a", userID: userA)
            && deleteCoordinator.activeHistoryUserID == userB
            && deleteCoordinator.savedHistory.isEmpty

        let migrationAudit: String
        if let fileStore = historyStore as? CoorditFitLabFileHistoryStore {
            migrationAudit = await fileStore.debugMigrationRewriteFailureAudit()
        } else {
            migrationAudit = "unavailable"
        }
        let migrationPassed = migrationAudit == "loaded=1|analysis=legacy-analysis|retained=true|quarantine=0|notice=present"
        historyF2Probe = "save=\(savePassed ? "pass" : "fail")|delete=\(deletePassed ? "pass" : "fail")|migration-write=\(migrationPassed ? "pass" : "fail")|legacy-retained=\(migrationPassed ? "pass" : "fail")"
        if !migrationPassed { historyF2Probe += "|detail=\(migrationAudit)" }
    }

    private static func raceSnapshot(userID: String, analysisID: String) -> CoorditFitLabHistorySnapshot {
        CoorditFitLabHistorySnapshot(
            id: analysisID,
            analysisID: analysisID,
            userID: userID,
            savedAt: Date(timeIntervalSince1970: 1),
            product: .init(name: analysisID, brand: nil, mallName: nil, url: nil),
            category: .hoodie,
            garmentKind: .upper,
            references: [],
            originalSource: .manual,
            recommendation: CoorditFitLabFixtures.upperRecommendation,
            report: nil,
            chartData: .init()
        )
    }

    private func updateHistoryEdgeProbe() {
        let unique = Set(savedHistory.map(\.analysisID)).count
        historyEdgeProbe = "count=\(savedHistory.count)|unique=\(unique)|newest=\(savedHistory.first?.analysisID ?? "none")|oldest=\(savedHistory.last?.analysisID ?? "none")"
        if let userID = activeHistoryUserID {
            historyUserProbe = "user=\(userID)|count=\(savedHistory.count)"
        }
    }
    #endif

    #if DEBUG
    private func seed(route: CoorditFrameRoute, fixture: String?) {
        guard fixture != nil else { return }
        switch route {
        case .fitLabLoading:
            submissionStep = .creatingSizes
            loadState = .loading
        case .fitLabResultTop:
            draft = CoorditFitLabFixtures.upperResultDraft
            recommendation = CoorditFitLabFixtures.upperRecommendation
            report = fixture == "long-report" ? CoorditFitLabFixtures.longReport : CoorditFitLabFixtures.report
        case .fitLabResultBottom:
            draft = CoorditFitLabFixtures.lowerResultDraft
            recommendation = CoorditFitLabFixtures.lowerRecommendation
            report = CoorditFitLabFixtures.lowerReport
        case .fitLabHistoryRegister, .fitLabHistoryDetail:
            recommendation = CoorditFitLabFixtures.lowerRecommendation
            report = CoorditFitLabFixtures.lowerReport
            if fixture == "saved-history" {
                selectedHistory = makeHistorySnapshot(
                    userID: userID ?? "coordit-fitlab-test-user",
                    savedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            }
        default:
            break
        }
    }
    #endif

    private static func screen(for route: CoorditFrameRoute) -> CoorditFitLabScreen {
        switch route {
        case .fitLabLoading: .loading
        case .fitLabResultTop: .resultUpper
        case .fitLabResultBottom: .resultLower
        case .fitLabHistoryRegister: .historyRegister
        case .fitLabHistoryDetail: .historyDetail
        default: .input
        }
    }
}
#endif
