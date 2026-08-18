import Foundation
import Combine

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
    @Published private(set) var onboardingComplete = false
    @Published private(set) var referenceFitProfiles: [String: CoorditReferenceFitProfileResponse] = [:]
    @Published private(set) var statusText = "백엔드 연결 확인 전"
    @Published private(set) var isWorking = false
    @Published private(set) var isWarning = false

    private let client: CoorditBackendClient
    private let tokenStore: CoorditBackendTokenStore

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
                birthDate: nil,
                birthYear: nil,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z"
            )
            onboardingComplete = !ProcessInfo.processInfo.arguments.contains("--coordit-ui-testing-onboarding-incomplete")
            statusText = "테스트 계정으로 로그인됨"
        } else {
            usesAuthenticatedUITestFixture = false
            session = tokenStore.load()
        }
#else
        session = tokenStore.load()
#endif
    }

    init(client: CoorditBackendClient, tokenStore: CoorditBackendTokenStore) {
        self.client = client
        self.tokenStore = tokenStore
#if DEBUG
        usesAuthenticatedUITestFixture = false
#endif
        session = tokenStore.load()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var canUseProduct: Bool {
        isAuthenticated && onboardingComplete
    }

    var emailText: String {
        profile?.email ?? session?.user.email ?? "로그인 필요"
    }

    var displayNameText: String {
        profile?.displayName ?? session?.user.email ?? "코딧 사용자"
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
                try await refreshOnboardingStatus()
            }
        }
    }

    func fetchThreadBalance() async -> Int? {
        guard let token = session?.accessToken else { return nil }
        do {
            return try await client.threadBalance(token: token).availableThreads
        } catch {
            statusText = error.localizedDescription
            isWarning = true
            return nil
        }
    }

    func loginWithGoogle() async {
        await authenticate {
            let idToken = try await CoorditGoogleSignIn.signInIDToken()
            return try await client.loginWithGoogle(idToken: idToken)
        }
    }

    func loginWithApple() async {
        await authenticate {
            let credential = try await CoorditAppleSignIn.signInCredential()
            return try await client.loginWithApple(
                idToken: credential.idToken,
                nonce: credential.nonce
            )
        }
    }

    func logout() {
        tokenStore.delete()
        session = nil
        profile = nil
        latestBodyMeasurement = nil
        onboardingComplete = false
        referenceFitProfiles = [:]
        statusText = "이 기기에서 로그아웃했어요."
        isWarning = false
    }

    func deleteAccount() async -> Bool {
        guard let token = session?.accessToken else {
            statusText = "회원 탈퇴는 로그인 후 진행할 수 있어요."
            isWarning = true
            return false
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await client.deleteAccount(token: token)
            tokenStore.delete()
            session = nil
            profile = nil
            latestBodyMeasurement = nil
            onboardingComplete = false
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

    func completeOnboarding(_ request: CoorditOnboardingRequest) async -> Bool {
        guard let token = session?.accessToken else {
            statusText = "초기 설정은 로그인 후 저장할 수 있어요."
            isWarning = true
            return false
        }

        var completed = false
        await run {
            let status = try await client.completeOnboarding(token: token, request: request)
            onboardingComplete = status.onboardingComplete
            try await refreshAccount()
            statusText = "나만의 핏 프로필을 저장했어요."
            isWarning = false
            completed = status.onboardingComplete
        }
        return completed
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
        guard let token = session?.accessToken else { throw CoorditFitLabError.loginRequired }
        let api = CoorditFitLabHTTPAPI(baseURL: CoorditBackendConfig.baseURL(), accessToken: token)
        return try await api.prefillProduct(
            from: CoorditFitLabURLPrefillRequest(url: url, category: category)
        )
    }

    func saveClothing(
        from draft: CoorditClosetDraft,
        idempotencyKey: String
    ) async -> CoorditClothingSaveResult? {
        guard let token = session?.accessToken else {
            statusText = "보유 의류 저장은 로그인 후 백엔드에 반영돼요."
            isWarning = true
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let clothingSizeRequest = await CoorditFitLabSizeExtractor.referenceClothingSizeRequest(from: draft)
            let saved = try await client.createClothingItemWithSize(
                token: token,
                clothingItem: draft.clothingItemRequest,
                clothingSize: clothingSizeRequest,
                idempotencyKey: idempotencyKey
            )
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
        guard let token = session?.accessToken else { return nil }
        #if DEBUG
        if usesAuthenticatedUITestFixture { return nil }
        #endif

        do {
            async let clothingRequest = client.listClothingItems(token: token)
            async let referenceRequest = client.listReferenceClothing(token: token)
            let (clothing, references) = try await (clothingRequest, referenceRequest)
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
                guard let size = try await client.listClothingSizes(
                    token: token,
                    clothingItemId: response.id
                ).first else { continue }
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
        guard let token = session?.accessToken else {
            statusText = "로그인되지 않은 로컬 의류를 삭제했어요."
            isWarning = false
            return true
        }
        do {
            try await client.deleteClothingItem(token: token, id: id)
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
        guard let token = session?.accessToken else {
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
                    let reference = try await client.createReferenceClothing(
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
                    referenceIDsByItemID[item.id] = reference.id
                } else if let referenceID = item.backendReferenceClothingId {
                    _ = try await client.deactivateReferenceClothing(token: token, id: referenceID)
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
        guard let token = session?.accessToken else {
            statusText = "핏 스코어 재평가는 로그인이 필요해요."
            isWarning = true
            return nil
        }

        do {
            let assessment = try await client.reassessClothingItem(token: token, id: id)
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

        guard let token = session?.accessToken else {
            referenceFitProfiles = [:]
            return
        }
        do {
            async let upper = client.referenceFitProfile(token: token, garmentKind: "upper")
            async let lower = client.referenceFitProfile(token: token, garmentKind: "lower")
            let profiles = try await [upper, lower]
            referenceFitProfiles = Dictionary(
                uniqueKeysWithValues: profiles.map { ($0.garmentKind, $0) }
            )
        } catch {
            statusText = error.localizedDescription
            isWarning = true
        }
    }

    func recommendFitLabTarget(category: CoorditClosetCategory, sizeChartImageData: Data?) async -> CoorditFitRecommendation? {
        guard let token = session?.accessToken else {
            statusText = "핏 엔진 계산은 로그인이 필요해요."
            isWarning = true
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let references = try await client.listReferenceClothing(token: token, category: category.backendCategory)
            guard let reference = references.first else {
                statusText = "먼저 \(category.title) 기준 옷을 하나 등록해주세요."
                isWarning = true
                return nil
            }

            let externalProduct = try await client.createExternalProduct(
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

            let candidateSizes = await CoorditFitLabSizeExtractor.candidateSizes(
                from: sizeChartImageData,
                category: category
            )

            for sizeRequest in candidateSizes {
                _ = try await client.createExternalProductSize(
                    token: token,
                    externalProductId: externalProduct.id,
                    request: sizeRequest
                )
            }

            let recommendation = try await client.recommendFit(
                token: token,
                request: FitRecommendRequest(
                    referenceClothingIds: [reference.id],
                    externalProductId: externalProduct.id,
                    idempotencyKey: UUID().uuidString
                )
            )
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
            try tokenStore.save(nextSession)
            session = nextSession
            try await refreshAccount()
            try await refreshOnboardingStatus()
            statusText = onboardingComplete ? "백엔드 로그인 완료" : "초기 설정을 완료해 주세요."
            isWarning = false
        }
    }

    private func refreshAccount() async throws {
        guard let token = session?.accessToken else { return }
        profile = try await client.me(token: token)
        latestBodyMeasurement = try await client.listBodyMeasurements(token: token).first
    }

    private func refreshOnboardingStatus() async throws {
        guard let token = session?.accessToken else {
            onboardingComplete = false
            return
        }
        onboardingComplete = try await client.onboardingStatus(token: token).onboardingComplete
    }

    private func runAuthenticated(_ action: (String) async throws -> Void) async {
        guard let token = session?.accessToken else {
            statusText = "백엔드 저장은 로그인이 필요해요."
            isWarning = true
            return
        }
        await run {
            try await action(token)
        }
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
#endif
}
#endif
