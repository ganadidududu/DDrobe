import Foundation
import Combine
import AuthenticationServices

#if os(iOS)
struct CoorditClosetServerSnapshot {
    let items: [CoorditClosetItem]
    let selectedReferenceIDs: Set<String>
}

struct CoorditReferenceSyncResult {
    let selectedIDs: Set<String>
    let referenceIDsByItemID: [String: String]
}

@MainActor
final class CoorditBackendSessionStore: ObservableObject {
    @Published private(set) var session: CoorditAuthSession?
    @Published private(set) var profile: CoorditUserProfile?
    @Published private(set) var latestBodyMeasurement: CoorditBodyMeasurement?
    @Published private(set) var referenceFitProfiles: [String: CoorditReferenceFitProfileResponse] = [:]
    @Published private(set) var statusText = "백엔드 연결 확인 전"
    @Published private(set) var isWorking = false
    @Published private(set) var isWarning = false

    private let client: CoorditBackendClient
    private let tokenStore: CoorditBackendTokenStore
    private var refreshTask: Task<CoorditAuthSession, Error>?
    private var scheduledRefreshTask: Task<Void, Never>?

#if DEBUG
    private let usesAuthenticatedUITestFixture: Bool
#endif

    init() {
        self.client = CoorditBackendClient(baseURL: CoorditBackendConfig.baseURL())
        self.tokenStore = CoorditBackendTokenStore()
#if DEBUG
        if Self.shouldUseAuthenticatedUITestFixture {
            usesAuthenticatedUITestFixture = true
            session = CoorditAuthSession(
                accessToken: Self.uiTestingAccessToken ?? "",
                refreshToken: "",
                user: CoorditAuthUser(id: "coordit-ui-test-user", email: "ui-test@coordit.invalid")
            )
            profile = CoorditUserProfile(
                id: "coordit-ui-test-user",
                email: "ui-test@coordit.invalid",
                displayName: "코딧 테스트 사용자",
                gender: nil,
                birthYear: nil,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z"
            )
        } else {
            usesAuthenticatedUITestFixture = false
            session = tokenStore.load()
        }
#else
        session = tokenStore.load()
#endif
        scheduleRefreshIfPossible()
    }

    init(client: CoorditBackendClient, tokenStore: CoorditBackendTokenStore) {
        self.client = client
        self.tokenStore = tokenStore
#if DEBUG
        usesAuthenticatedUITestFixture = false
#endif
        session = tokenStore.load()
        scheduleRefreshIfPossible()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var isMember: Bool {
        session?.user.isAnonymous == false
    }

    var shouldAutomaticallyAuthenticateAppleForUITest: Bool {
#if DEBUG
        Self.shouldSimulateAppleAuthenticationWithHydrationFailure
#else
        false
#endif
    }

    func clearStatus() {
        statusText = ""
        isWarning = false
    }

    var emailText: String {
        if session?.user.isAnonymous == true { return "계정을 연결해 기록을 보호하세요" }
        return profile?.email ?? session?.user.email ?? "로그인 필요"
    }

    var displayNameText: String {
        if session?.user.isAnonymous == true { return "비회원으로 이용 중" }
        return profile?.displayName ?? session?.user.email ?? "코딧 사용자"
    }

    func restorePersistedSession() async {
#if DEBUG
        if usesAuthenticatedUITestFixture { return }
#endif
        guard session != nil else { return }
        do {
            _ = try await refreshCurrentSession()
            statusText = "로그인 상태를 복구했어요."
            isWarning = false
        } catch {
            statusText = "로그인은 유지 중이에요. 연결되면 자동으로 다시 확인할게요."
            isWarning = true
        }
    }

    func refreshPersistedSessionIfNeeded() async {
#if DEBUG
        if usesAuthenticatedUITestFixture { return }
#endif
        guard let activeSession = session, shouldRefreshSoon(activeSession.accessToken) else { return }
        do {
            _ = try await refreshCurrentSession()
        } catch {
            statusText = "로그인은 유지 중이에요. 연결되면 자동으로 다시 확인할게요."
            isWarning = true
        }
    }

    func validAccessToken() async throws -> String {
        guard let activeSession = session else { throw CoorditBackendSessionError.loginRequired }
        guard shouldRefreshSoon(activeSession.accessToken), !activeSession.refreshToken.isEmpty else {
            return activeSession.accessToken
        }
        do {
            return try await refreshCurrentSession().accessToken
        } catch {
            return session?.accessToken ?? activeSession.accessToken
        }
    }

    func bootstrapGuestIfNeeded() async -> Int? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }

#if DEBUG
        if Self.shouldSimulateGuestBootstrap || Self.shouldSimulateGuestBootstrapFailure {
            let guestSession = CoorditAuthSession(
                accessToken: "coordit-ui-test-guest-access-token",
                refreshToken: "coordit-ui-test-guest-refresh-token",
                user: CoorditAuthUser(
                    id: "coordit-ui-test-guest-user",
                    email: "guest@guest.coordit.invalid",
                    isAnonymous: true
                )
            )
            try? tokenStore.save(guestSession)
            session = guestSession
            if Self.shouldSimulateGuestBootstrap {
                statusText = "비회원으로 시작했어요."
                isWarning = false
                return 3
            }
        }
#endif

        if session == nil {
            do {
                let guestSession = try await client.createGuestSession()
                try persistSession(guestSession)
            } catch {
                statusText = error.localizedDescription
                isWarning = true
                return nil
            }
        }

        guard let activeSession = session else { return nil }
        guard activeSession.user.isAnonymous else {
            return await fetchThreadBalance()
        }

        do {
#if DEBUG
            if Self.shouldSimulateGuestBootstrapFailure {
                throw CoorditBackendClientError.server(
                    statusCode: 503,
                    message: "UI test welcome-credit failure"
                )
            }
#endif
            let deviceToken = try await CoorditDeviceCheck.token()
            let welcome = try await authenticatedValue { token in
                try await client.claimGuestWelcome(token: token, deviceToken: deviceToken)
            }
            statusText = welcome.status == "granted"
                ? "첫 이용 실타래 3개를 받았어요."
                : "비회원으로 시작했어요."
            isWarning = false
            return welcome.availableThreads
        } catch {
            let availableThreads = await fetchThreadBalance() ?? 0
            statusText = "비회원 로그인은 완료됐어요. 실타래 지급만 잠시 후 다시 시도해주세요."
            isWarning = true
            return availableThreads
        }
    }

    func bootstrap() async {
#if DEBUG
        if usesAuthenticatedUITestFixture {
            return
        }
#endif
        await run {
            let health = try await client.health()
            statusText = health.ok ? "\(health.service) 연결됨" : "백엔드 응답이 불안정해요."
            isWarning = !health.ok
            if session != nil {
                try await refreshAccount()
            }
        }
    }

    func fetchThreadBalance() async -> Int? {
        guard session != nil else { return nil }
        do {
            return try await authenticatedValue { token in
                try await client.threadBalance(token: token).availableThreads
            }
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func login(email: String, password: String) async {
        await authenticate {
            try await client.login(email: email, password: password)
        }
    }

    func signup(email: String, password: String) async {
        await authenticate {
            try await client.signup(email: email, password: password)
        }
    }

    func loginWithGoogle() async {
        let guestSession = session?.user.isAnonymous == true ? session : nil
        await authenticate {
            let idToken = try await CoorditGoogleSignIn.signInIDToken()
            return try await client.loginWithGoogle(
                idToken: idToken,
                guestSession: guestSession
            )
        }
    }

    func loginWithApple() async {
#if DEBUG
        if Self.shouldSimulateAppleAuthenticationWithHydrationFailure {
            await authenticate {
                CoorditAuthSession(
                    accessToken: "coordit-ui-test-apple-access-token",
                    refreshToken: "coordit-ui-test-apple-refresh-token",
                    user: CoorditAuthUser(
                        id: "coordit-ui-test-apple-user",
                        email: "apple-ui-test@coordit.invalid"
                    )
                )
            }
            return
        }
#endif
        await authenticate {
            let credential = try await CoorditAppleSignIn.signInCredential()
            return try await client.loginWithApple(
                idToken: credential.idToken,
                nonce: credential.nonce,
                guestSession: session?.user.isAnonymous == true ? session : nil
            )
        }
    }

    func completeAppleLogin(
        _ result: Result<ASAuthorization, Error>,
        rawNonce: String
    ) async {
        await authenticate {
            let credential = try CoorditAppleSignIn.credential(from: result, rawNonce: rawNonce)
            return try await client.loginWithApple(
                idToken: credential.idToken,
                nonce: credential.nonce,
                guestSession: session?.user.isAnonymous == true ? session : nil
            )
        }
    }

    func logout() {
        cancelRefreshWork()
        tokenStore.delete()
        session = nil
        profile = nil
        latestBodyMeasurement = nil
        referenceFitProfiles = [:]
        statusText = "이 기기에서 로그아웃했어요."
        isWarning = false
    }

    func deleteAccount() async -> Bool {
        guard session != nil else {
            statusText = "회원 탈퇴는 로그인 후 진행할 수 있어요."
            isWarning = true
            return false
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await authenticatedValue { token in
                try await client.deleteAccount(token: token)
            }
            cancelRefreshWork()
            tokenStore.delete()
            session = nil
            profile = nil
            latestBodyMeasurement = nil
            referenceFitProfiles = [:]
            statusText = "계정과 저장된 데이터를 삭제했어요."
            isWarning = false
            return true
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return false
        }
    }

    func saveProfile(displayName: String) async {
        await runAuthenticated { token in
            profile = try await client.updateMe(token: token, displayName: displayName)
            statusText = "프로필을 백엔드에 저장했어요."
            isWarning = false
        }
    }

    func saveBodyMeasurement(_ request: BodyMeasurementRequest) async {
        await runAuthenticated { token in
            latestBodyMeasurement = try await client.createBodyMeasurement(token: token, request: request)
            statusText = "신체 치수를 백엔드에 저장했어요."
            isWarning = false
        }
    }

    func prefillClosetProduct(
        from url: URL,
        category: CoorditFitLabCategory
    ) async throws -> CoorditFitLabURLPrefillResponse {
#if DEBUG
        if CoorditFitLabFixtureConfiguration.launch().name != nil {
            return try await CoorditFitLabFixtureAPI().prefillProduct(
                from: CoorditFitLabURLPrefillRequest(url: url, category: category)
            )
        }
#endif
        guard session != nil else { throw CoorditFitLabError.loginRequired }
        return try await authenticatedValue { token in
            let api = CoorditFitLabHTTPAPI(baseURL: CoorditBackendConfig.baseURL(), accessToken: token)
            return try await api.prefillProduct(
                from: CoorditFitLabURLPrefillRequest(url: url, category: category)
            )
        }
    }

    func saveClothing(
        from draft: CoorditClosetDraft,
        idempotencyKey: String
    ) async -> CoorditClothingSaveResult? {
        guard session != nil else {
            statusText = "보유 의류 저장은 로그인 후 백엔드에 반영돼요."
            isWarning = true
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let clothingSizeRequest = await CoorditFitLabSizeExtractor.referenceClothingSizeRequest(from: draft)
            let saved = try await authenticatedValue { token in
                try await client.createClothingItemWithSize(
                    token: token,
                    clothingItem: draft.clothingItemRequest,
                    clothingSize: clothingSizeRequest,
                    idempotencyKey: idempotencyKey
                )
            }
            statusText = "보유 의류를 옷장에 저장했어요."
            isWarning = false
            return CoorditClothingSaveResult(
                clothingItemId: saved.clothingItem.id,
                sizeChart: CoorditClosetSizeChart(
                    sizeLabel: saved.clothingSize.sizeLabel,
                    measurements: saved.clothingSize.measurements
                )
            )
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func loadClosetSnapshot(preserving localItems: [CoorditClosetItem]) async -> CoorditClosetServerSnapshot? {
        guard session != nil else { return nil }
        #if DEBUG
        if usesAuthenticatedUITestFixture { return nil }
        #endif

        do {
            let clothing = try await authenticatedValue { token in
                try await client.listClothingItems(token: token)
            }
            let references = try await authenticatedValue { token in
                try await client.listReferenceClothing(token: token)
            }
            let referenceByClothingID = Dictionary(
                references.map { ($0.clothingItemId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let localByBackendID = Dictionary(
                localItems.compactMap { item in
                    item.backendClothingItemId.map { ($0, item) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            var sizeChartByClothingID: [String: CoorditClosetSizeChart] = [:]
            for response in clothing {
                guard let size = try await authenticatedValue({ token in
                    try await client.listClothingSizes(token: token, clothingItemId: response.id)
                }).first else { continue }
                sizeChartByClothingID[response.id] = CoorditClosetSizeChart(
                    sizeLabel: size.sizeLabel,
                    measurements: size.measurements
                )
            }
            let items = clothing.compactMap { response -> CoorditClosetItem? in
                guard let exactCategory = CoorditFitLabCategory(rawValue: response.category) else { return nil }
                let parent: CoorditClosetCategory = exactCategory.garmentKind == .upper ? .top : .bottom
                let local = localByBackendID[response.id]
                let reference = referenceByClothingID[response.id]
                return CoorditClosetItem(
                    id: local?.id ?? response.id,
                    name: response.name,
                    category: parent,
                    exactCategory: exactCategory,
                    score: local?.score ?? 0,
                    scoreColor: CoorditClosetColors.navy,
                    route: parent == .top ? .closetDetailTop : .closetDetailBottom,
                    imageData: local?.imageData,
                    fitDiffs: local?.fitDiffs,
                    sizeChart: sizeChartByClothingID[response.id] ?? local?.sizeChart,
                    backendClothingItemId: response.id,
                    backendReferenceClothingId: reference?.id
                )
            }
            let selected: Set<String> = Set(items.compactMap { item -> String? in
                guard let backendID = item.backendClothingItemId,
                      referenceByClothingID[backendID]?.isActive == true else { return nil }
                return item.id
            })
            statusText = "서버의 옷장과 기준 의류를 불러왔어요."
            isWarning = false
            return CoorditClosetServerSnapshot(items: items, selectedReferenceIDs: selected)
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func deleteClothingItem(id: String) async -> Bool {
        guard session != nil else {
            statusText = "로그인되지 않은 로컬 의류를 삭제했어요."
            isWarning = false
            return true
        }
        do {
            try await authenticatedValue { token in
                try await client.deleteClothingItem(token: token, id: id)
            }
            statusText = "옷장에서 의류를 삭제했어요."
            isWarning = false
            return true
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return false
        }
    }

    func syncReferenceSelection(
        items: [CoorditClosetItem],
        selectedIDs: Set<String>
    ) async -> CoorditReferenceSyncResult? {
        guard session != nil else {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--coordit-ui-testing") {
                statusText = "UI 테스트 기준 의류 선택을 저장했어요."
                isWarning = false
                return CoorditReferenceSyncResult(selectedIDs: selectedIDs, referenceIDsByItemID: [:])
            }
            #endif
            statusText = "기준 의류 선택은 로그인 후 서버에 반영돼요."
            isWarning = true
            return nil
        }

        let syncableItems = items.filter {
            $0.backendClothingItemId != nil || $0.backendReferenceClothingId != nil
        }
        guard !syncableItems.isEmpty else {
            statusText = "먼저 서버에 저장된 의류를 옷장에 추가해주세요."
            isWarning = true
            return nil
        }

        do {
            var referenceIDsByItemID: [String: String] = [:]
            for item in syncableItems {
                if selectedIDs.contains(item.id), let clothingItemID = item.backendClothingItemId {
                    let reference = try await authenticatedValue { token in
                        try await client.createReferenceClothing(
                            token: token,
                            request: CreateReferenceClothingRequest(
                                clothingItemId: clothingItemID,
                                nickname: item.name,
                                category: item.exactCategory.rawValue,
                                fitType: "regular",
                                preferenceScore: 100,
                                isActive: true,
                                notes: "Selected from iOS Home"
                            )
                        )
                    }
                    referenceIDsByItemID[item.id] = reference.id
                } else if let referenceID = item.backendReferenceClothingId {
                    _ = try await authenticatedValue { token in
                        try await client.deactivateReferenceClothing(token: token, id: referenceID)
                    }
                    referenceIDsByItemID[item.id] = referenceID
                }
            }
            statusText = "기준 의류 선택을 저장했어요."
            isWarning = false
            return CoorditReferenceSyncResult(
                selectedIDs: selectedIDs,
                referenceIDsByItemID: referenceIDsByItemID
            )
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func reassessClothingItem(id: String) async -> CoorditClothingFitAssessmentResponse? {
        guard session != nil else {
            statusText = "핏 스코어 재평가는 로그인이 필요해요."
            isWarning = true
            return nil
        }

        do {
            let assessment = try await authenticatedValue { token in
                try await client.reassessClothingItem(token: token, id: id)
            }
            let score = CoorditFitLabResultMeasurement.score(assessment.fitScore)
            statusText = "선택한 의류의 핏 스코어를 \(score)점으로 다시 계산했어요."
            isWarning = false
            return assessment
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func referenceFitProfile(for category: CoorditClosetCategory) -> CoorditReferenceFitProfileResponse? {
        referenceFitProfiles[category == .top ? "upper" : "lower"]
    }

    func refreshReferenceFitProfiles() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coordit-test-reference-fit-profiles") {
            let upper = CoorditReferenceFitProfileResponse(
                garmentKind: "upper",
                referenceCount: 2,
                measurements: CoorditMeasurementMap(
                    totalLength: 70.5,
                    shoulderWidth: 46.25,
                    chestWidth: 54,
                    sleeveLength: 62,
                    waistWidth: nil,
                    hipWidth: nil,
                    rise: nil,
                    outseam: nil
                ),
                sampleCounts: [
                    "shoulder_width": 2,
                    "chest_width": 2,
                    "total_length": 2,
                    "sleeve_length": 2,
                ],
                strategy: "weighted_huber_profile_v1"
            )
            let lower = CoorditReferenceFitProfileResponse(
                garmentKind: "lower",
                referenceCount: 2,
                measurements: CoorditMeasurementMap(
                    totalLength: nil,
                    shoulderWidth: nil,
                    chestWidth: nil,
                    sleeveLength: nil,
                    waistWidth: 39,
                    hipWidth: 51.25,
                    rise: 29.5,
                    outseam: 102
                ),
                sampleCounts: [
                    "waist_width": 2,
                    "hip_width": 2,
                    "rise": 2,
                    "outseam": 2,
                ],
                strategy: "weighted_huber_profile_v1"
            )
            referenceFitProfiles = ["upper": upper, "lower": lower]
            return
        }
        #endif

        guard session != nil else {
            referenceFitProfiles = [:]
            return
        }
        do {
            let upper = try await authenticatedValue { token in
                try await client.referenceFitProfile(token: token, garmentKind: "upper")
            }
            let lower = try await authenticatedValue { token in
                try await client.referenceFitProfile(token: token, garmentKind: "lower")
            }
            let profiles = [upper, lower]
            referenceFitProfiles = Dictionary(
                uniqueKeysWithValues: profiles.map { ($0.garmentKind, $0) }
            )
        } catch {
            statusText = error.localizedDescription
            isWarning = true
        }
    }

    func recommendFitLabTarget(category: CoorditClosetCategory, sizeChartImageData: Data?) async -> CoorditFitRecommendation? {
        guard session != nil else {
            statusText = "핏 엔진 계산은 로그인이 필요해요."
            isWarning = true
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let references = try await authenticatedValue { token in
                try await client.listReferenceClothing(token: token, category: category.backendCategory)
            }
            guard let reference = references.first else {
                statusText = "먼저 \(category.title) 기준 옷을 하나 등록해주세요."
                isWarning = true
                return nil
            }

            let externalProduct = try await authenticatedValue { token in
                try await client.createExternalProduct(
                    token: token,
                    request: CreateExternalProductRequest(
                        productName: "Fit Lab 등록 상품",
                        brand: nil,
                        mallName: nil,
                        productUrl: nil,
                        category: category.backendCategory,
                        fitType: "regular",
                        rawProductData: ["source": "ios-fitlab"]
                    )
                )
            }

            let candidateSizes = await CoorditFitLabSizeExtractor.candidateSizes(
                from: sizeChartImageData,
                category: category
            )

            for sizeRequest in candidateSizes {
                _ = try await authenticatedValue { token in
                    try await client.createExternalProductSize(
                        token: token,
                        externalProductId: externalProduct.id,
                        request: sizeRequest
                    )
                }
            }

            let recommendationIdempotencyKey = UUID().uuidString
            let recommendation = try await authenticatedValue { token in
                try await client.recommendFit(
                    token: token,
                    request: FitRecommendRequest(
                        referenceClothingIds: [reference.id],
                        externalProductId: externalProduct.id,
                        idempotencyKey: recommendationIdempotencyKey
                    )
                )
            }
            let usedFallbackMeasurements = candidateSizes.contains { $0.measurementSource != "ocr" }
            statusText = usedFallbackMeasurements
                ? "사이즈표를 읽지 못해 기본 후보로 \(recommendation.recommendedSize) 사이즈를 추천했어요."
                : "사이즈표를 읽고 \(recommendation.recommendedSize) 사이즈를 추천했어요."
            isWarning = usedFallbackMeasurements
            return recommendation
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    private func authenticate(_ action: () async throws -> CoorditAuthSession) async {
        await run {
            let nextSession = try await action()
            try persistSession(nextSession)
            statusText = "백엔드 로그인 완료"
            isWarning = false
            Task { await refreshAccountAfterAuthentication(nextSession) }
        }
    }

    private func refreshAccountAfterAuthentication(_ authenticatedSession: CoorditAuthSession) async {
        do {
            try await refreshAccount()
        } catch {
            guard session?.user.id == authenticatedSession.user.id else { return }
            statusText = "로그인은 완료됐지만 계정 정보를 아직 동기화하지 못했어요."
            isWarning = true
        }
    }

    private func refreshAccount() async throws {
#if DEBUG
        if Self.shouldSimulateAppleAuthenticationWithHydrationFailure {
            throw CoorditBackendClientError.server(
                statusCode: 503,
                message: "UI test account hydration failure"
            )
        }
#endif
        guard let activeSession = session else { return }
        let nextProfile = try await authenticatedValue { token in
            try await client.me(token: token)
        }
        let nextBodyMeasurement = try await authenticatedValue { token in
            try await client.listBodyMeasurements(token: token).first
        }
        guard session?.user.id == activeSession.user.id else { return }
        profile = nextProfile
        latestBodyMeasurement = nextBodyMeasurement
    }

    private func runAuthenticated(_ action: (String) async throws -> Void) async {
        guard session != nil else {
            statusText = "백엔드 저장은 로그인이 필요해요."
            isWarning = true
            return
        }
        await run {
            try await authenticatedValue(action)
        }
    }

    private func authenticatedValue<Value>(
        _ action: (String) async throws -> Value
    ) async throws -> Value {
        guard let initialSession = session else {
            throw CoorditBackendSessionError.loginRequired
        }

        let requestSession: CoorditAuthSession
        if shouldRefreshSoon(initialSession.accessToken), !initialSession.refreshToken.isEmpty {
            requestSession = (try? await refreshCurrentSession()) ?? initialSession
        } else {
            requestSession = initialSession
        }

        do {
            return try await action(requestSession.accessToken)
        } catch {
            guard isUnauthorized(error), !requestSession.refreshToken.isEmpty else { throw error }
            let refreshed = try await refreshCurrentSession(
                afterFailureWith: requestSession.accessToken
            )
            return try await action(refreshed.accessToken)
        }
    }

    private func refreshCurrentSession(
        afterFailureWith failedAccessToken: String? = nil
    ) async throws -> CoorditAuthSession {
        guard let activeSession = session else {
            throw CoorditBackendSessionError.loginRequired
        }
        if let failedAccessToken, activeSession.accessToken != failedAccessToken {
            return activeSession
        }
        guard !activeSession.refreshToken.isEmpty else {
            throw CoorditBackendSessionError.refreshUnavailable
        }
        if let refreshTask {
            let refreshed = try await refreshTask.value
            return try publishRefreshedSession(
                refreshed,
                replacingAccessToken: activeSession.accessToken
            )
        }

        let client = self.client
        let task = Task {
            let response = try await client.refreshSession(
                refreshToken: activeSession.refreshToken
            )
            return CoorditAuthSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: activeSession.user
            )
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            refreshTask = nil
            return try publishRefreshedSession(
                refreshed,
                replacingAccessToken: activeSession.accessToken
            )
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func publishRefreshedSession(
        _ refreshed: CoorditAuthSession,
        replacingAccessToken accessToken: String
    ) throws -> CoorditAuthSession {
        guard let currentSession = session else {
            throw CoorditBackendSessionError.loginRequired
        }
        guard currentSession.accessToken == accessToken else {
            return currentSession
        }
        try persistSession(refreshed)
        return refreshed
    }

    private func persistSession(_ nextSession: CoorditAuthSession) throws {
        try tokenStore.save(nextSession)
        session = nextSession
        scheduleRefreshIfPossible()
    }

    private func cancelRefreshWork() {
        refreshTask?.cancel()
        refreshTask = nil
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
    }

    private func scheduleRefreshIfPossible() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        guard let activeSession = session, !activeSession.refreshToken.isEmpty else { return }

        let delay = max(1, refreshDelay(for: activeSession.accessToken))
        scheduledRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self else { return }
            do {
                _ = try await self.refreshCurrentSession()
            } catch {
                self.statusText = "로그인은 유지 중이에요. 연결되면 자동으로 다시 확인할게요."
                self.isWarning = true
            }
        }
    }

    private func shouldRefreshSoon(_ accessToken: String) -> Bool {
        guard let expiration = jwtExpiration(accessToken) else { return false }
        return expiration.timeIntervalSinceNow <= 5 * 60
    }

    private func refreshDelay(for accessToken: String) -> TimeInterval {
        guard let expiration = jwtExpiration(accessToken) else { return 45 * 60 }
        return expiration.timeIntervalSinceNow - (5 * 60)
    }

    private func jwtExpiration(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let expiration = object["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: expiration)
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        if let backendError = error as? CoorditBackendClientError,
           case .server(statusCode: 401, message: _) = backendError {
            return true
        }
        if let fitLabError = error as? CoorditFitLabError,
           case .server(statusCode: 401, message: _) = fitLabError {
            return true
        }
        return false
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await action()
        } catch {
            statusText = error.localizedDescription
            isWarning = true
        }
    }

#if DEBUG
    private static var shouldUseAuthenticatedUITestFixture: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--coordit-ui-testing")
            && arguments.contains("--coordit-ui-testing-authenticated")
    }

    private static var uiTestingAccessToken: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let markerIndex = arguments.firstIndex(of: "--coordit-ui-testing-access-token"),
            arguments.indices.contains(arguments.index(after: markerIndex))
        else {
            return nil
        }
        return arguments[arguments.index(after: markerIndex)]
    }

    private static var shouldSimulateAppleAuthenticationWithHydrationFailure: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--coordit-test-apple-auth-success-hydration-failure"
        )
    }

    private static var shouldSimulateGuestBootstrap: Bool {
        ProcessInfo.processInfo.arguments.contains("--coordit-test-guest-bootstrap")
    }

    private static var shouldSimulateGuestBootstrapFailure: Bool {
        ProcessInfo.processInfo.arguments.contains("--coordit-test-guest-bootstrap-failure")
    }
#endif
}

private enum CoorditBackendSessionError: LocalizedError {
    case loginRequired
    case refreshUnavailable

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            "로그인이 필요해요."
        case .refreshUnavailable:
            "저장된 로그인 정보를 갱신할 수 없어요."
        }
    }
}
#endif
