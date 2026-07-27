import Foundation

#if os(iOS)
struct CoorditFitLabFixtureConfiguration: Sendable {
    let name: String?
    let userID: String?
    let historyRootDirectory: URL?
    let resetsHistory: Bool

    static let production = Self(name: nil, userID: nil, historyRootDirectory: nil, resetsHistory: false)

    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        #if DEBUG
        guard arguments.contains("--coordit-ui-testing") else { return .production }
        let name = argument(after: "--coordit-fitlab-fixture", in: arguments)
        let requestedUserID = argument(after: "--coordit-fitlab-history-user", in: arguments)
        let defaultUserID = name?.hasPrefix("history-") == true ? "history-user-a" : "coordit-fitlab-test-user"
        let userID = name == "unauthenticated" ? nil : (requestedUserID ?? defaultUserID)
        let namespace = argument(after: "--coordit-fitlab-history-namespace", in: arguments)
        let rootDirectory = namespace.map {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("coordit-fitlab-\(safeNamespace($0))", isDirectory: true)
        }
        return Self(
            name: name,
            userID: userID,
            historyRootDirectory: rootDirectory,
            resetsHistory: arguments.contains("--coordit-fitlab-history-reset")
        )
        #else
        return .production
        #endif
    }

    #if DEBUG
    private static func argument(after marker: String, in arguments: [String]) -> String? {
        guard
            let index = arguments.firstIndex(of: marker),
            arguments.indices.contains(arguments.index(after: index))
        else { return nil }
        return arguments[arguments.index(after: index)]
    }

    private static func safeNamespace(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }.prefix(80))
    }
    #endif
}

#if DEBUG
enum CoorditFitLabHistoryFixtureResetRegistry {
    nonisolated(unsafe) private static var resetPaths: Set<String> = []
    private static let lock = NSLock()

    static func resetOnce(_ rootDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard resetPaths.insert(rootDirectory.standardizedFileURL.path).inserted else { return }
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
#endif

#if DEBUG
enum CoorditFitLabContractProbe {
    static let expectedStatus = "CONTRACT_OK url-request url-body size-keys reference product size recommendation-parts result report adversarial"

    static let status: String = {
        do {
            let encoder = JSONEncoder()
            let url = URL(string: "https://shop.example/item")
            let baseURL = URL(string: "https://api.example")
            guard let url, let baseURL else { return "CONTRACT_ERROR url" }
            let api = CoorditFitLabHTTPAPI(baseURL: baseURL, accessToken: "fixture-token")
            let builtRequest = try api.makeRequest(
                path: "/external-products/from-url",
                method: "POST",
                body: CoorditFitLabURLPrefillRequest(url: url, category: .pants)
            )
            guard
                builtRequest.url?.absoluteString == "https://api.example/external-products/from-url",
                builtRequest.httpMethod == "POST",
                builtRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token",
                let builtBody = builtRequest.httpBody
            else { return "CONTRACT_ERROR url-request" }
            let urlObject = try JSONSerialization.jsonObject(
                with: builtBody
            ) as? [String: Any]
            guard
                urlObject?.count == 2,
                urlObject?["url"] as? String == url.absoluteString,
                urlObject?["category"] as? String == "pants"
            else { return "CONTRACT_ERROR url-body" }

            let sizeObject = try JSONSerialization.jsonObject(
                with: encoder.encode(
                    CoorditFitLabSizeRequest(
                        sizeLabel: "M",
                        measurements: [.shoulderWidth: 54, .chestWidth: 58]
                    )
                )
            ) as? [String: Any]
            guard
                sizeObject?["shoulder_width"] as? Double == 54,
                sizeObject?["chest_width"] as? Double == 58,
                sizeObject?["shoulderWidth"] == nil
            else { return "CONTRACT_ERROR size-keys" }

            let decoder = JSONDecoder()
            let reference = try decoder.decode(
                CoorditFitLabReferenceRow.self,
                from: Data(#"{"id":"ref-1","clothing_item_id":"cloth-1","nickname":"기준","category":"hoodie","fit_type":"regular","preference_score":5,"is_active":true}"#.utf8)
            )
            let product = try decoder.decode(
                CoorditFitLabExternalProductRow.self,
                from: Data(#"{"id":"product-1","product_name":"후드","category":"hoodie","ignored":true}"#.utf8)
            )
            let size = try decoder.decode(
                CoorditFitLabExternalProductSizeRow.self,
                from: Data(#"{"id":"size-1","external_product_id":"product-1","size_label":"M"}"#.utf8)
            )
            let recommendation = try decoder.decode(
                CoorditFitLabRecommendationResponse.self,
                from: Data(#"{"fitAnalysisResultId":"analysis-1","recommendedSize":"M","fitScore":92,"fitLabel":"good_fit","fitComment":"좋아요","recommendationConfidence":"high","diff":{"shoulder_width":1,"future_measurement":99},"partExplanations":["어깨 원문","가슴 원문"],"futureOptional":{"nested":true}}"#.utf8)
            )
            let result = try decoder.decode(
                CoorditFitLabAnalysisResultRow.self,
                from: Data(#"{"id":"analysis-1","user_id":"user-1","reference_clothing_id":"ref-1","external_product_id":"product-1","recommended_external_product_size_id":"size-1","recommended_size_label":"M","fit_score":92,"fit_label":"good_fit","fit_comment":"좋아요","recommendation_confidence":"high","result_details":{"nested":1}}"#.utf8)
            )
            guard
                reference.clothingItemID == "cloth-1",
                product.productName == "후드",
                size.externalProductID == "product-1",
                recommendation.diff == [.shoulderWidth: 1],
                recommendation.partExplanations == ["어깨 원문", "가슴 원문"],
                result.recommendedSizeLabel == "M"
            else { return "CONTRACT_ERROR response-decode" }

            let minimalReport = Data(
                #"{"unknownFutureField":true,"report":{"title":"테스트","measurementAnalysis":"malformed","cautions":42,"unknownSection":"ignored"},"chartData":{"idealVsProduct":[{"measurement":"shoulder_width","label":"어깨","ideal":53,"product":54,"diff":1,"status":null},{"measurement":"future_measurement","label":"미래","ideal":1,"product":2,"diff":1},{"measurement":42}],"unknownSeries":[]}}"#.utf8
            )
            let decoded = try decoder.decode(CoorditFitLabReportResponse.self, from: minimalReport)
            guard
                decoded.report.title == "테스트",
                decoded.report.measurementAnalysis.isEmpty,
                decoded.report.cautions.isEmpty,
                decoded.chartData.idealVsProduct.count == 1,
                decoded.chartData.idealVsProduct.first?.measurement == .shoulderWidth
            else { return "CONTRACT_ERROR adversarial" }
            return expectedStatus
        } catch {
            return "CONTRACT_ERROR \(String(describing: error))"
        }
    }()
}

@MainActor
final class CoorditFitLabFixtureAPI: CoorditFitLabAPI {
    private(set) var requestLedger: [String] = []
    private(set) var lastProductRequest: CoorditFitLabProductRequest?
    private let fixtureName: String?
    private var prefillAttempts = 0
    private var sizeAttempts: [String: Int] = [:]
    private var reportAttempts = 0
    private var recommendationContinuation: CheckedContinuation<Void, Never>?
    private var reportContinuation: CheckedContinuation<Void, Never>?

    init(fixtureName: String? = nil) {
        self.fixtureName = fixtureName
    }

    func compatibleReferences(category: CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow] {
        requestLedger.append("references:\(category.rawValue)")
        if fixtureName == "url-category-race" {
            if category == .shirt {
                try? await Task.sleep(for: .seconds(30))
            } else if category == .tshirt {
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        if fixtureName == "url-compatible-lower-reference", category == .pants {
            return [
                CoorditFitLabReferenceRow(
                    id: "reference-fixture-jeans",
                    clothingItemID: "clothing-fixture-jeans",
                    nickname: "기준 데님",
                    category: .jeans,
                    fitType: "regular",
                    preferenceScore: 5,
                    isActive: true
                )
            ]
        }
        let referenceID: String
        if fixtureName == "url-category-race" {
            referenceID = category == .tshirt ? "reference-tshirt-new" : "reference-shirt-stale"
        } else {
            referenceID = "reference-fixture-\(category.rawValue)"
        }
        return [
            CoorditFitLabReferenceRow(
                id: referenceID,
                clothingItemID: "clothing-fixture-1",
                nickname: "가장 잘 맞는 옷",
                category: category,
                fitType: "regular",
                preferenceScore: 5,
                isActive: true
            )
        ]
    }

    func prefillProduct(from request: CoorditFitLabURLPrefillRequest) async throws -> CoorditFitLabURLPrefillResponse {
        prefillAttempts += 1
        requestLedger.append("prefill:\(request.url.absoluteString)")
        if fixtureName == "url-late-response" {
            try? await Task.sleep(for: .seconds(1))
        }
        if fixtureName == "url-server-error", prefillAttempts == 1 {
            throw CoorditFitLabError.server(statusCode: 500, message: "상품 정보를 가져오지 못했어요.")
        }
        let json = #"{"productName":"리넨 셔츠","brand":"Coordit","mallName":"shop.example","productUrl":"https://shop.example/products/linen-shirt","category":"shirt","fitType":"regular","parsingStatus":"mocked","sizes":[{"sizeLabel":"M","shoulderWidth":45,"chestWidth":56,"totalLength":70,"sleeveLength":61,"waistWidth":null,"hipWidth":null,"rise":null,"outseam":null},{"sizeLabel":"L","shoulderWidth":47,"chestWidth":58,"totalLength":72,"sleeveLength":63,"waistWidth":null,"hipWidth":null,"rise":null,"outseam":null}]}"#
        let response = try JSONDecoder().decode(CoorditFitLabURLPrefillResponse.self, from: Data(json.utf8))
        let category = request.category ?? response.category
        let lowerSizes = [
            CoorditFitLabURLPrefillResponse.Size(
                sizeLabel: "M",
                shoulderWidth: nil,
                chestWidth: nil,
                totalLength: 101,
                sleeveLength: nil,
                waistWidth: 39,
                hipWidth: 51,
                rise: 30,
                outseam: 101
            )
        ]
        return CoorditFitLabURLPrefillResponse(
            productName: category.garmentKind == .lower ? "와이드 팬츠" : response.productName,
            brand: response.brand,
            mallName: response.mallName,
            productUrl: response.productUrl,
            category: category,
            fitType: response.fitType,
            parsingStatus: response.parsingStatus,
            sizes: category.garmentKind == .lower ? lowerSizes : response.sizes
        )
    }

    func createProduct(_ request: CoorditFitLabProductRequest) async throws -> CoorditFitLabExternalProductRow {
        lastProductRequest = request
        requestLedger.append("create-product")
        return CoorditFitLabExternalProductRow(id: "product-fixture-1", productName: request.productName, category: request.category)
    }

    func createSize(productID: String, request: CoorditFitLabSizeRequest) async throws -> CoorditFitLabExternalProductSizeRow {
        sizeAttempts[request.sizeLabel, default: 0] += 1
        requestLedger.append("create-size:\(request.sizeLabel):attempt")
        if fixtureName == "submission-size-retry",
           request.sizeLabel == "L",
           sizeAttempts[request.sizeLabel] == 1 {
            throw CoorditFitLabError.server(statusCode: 500, message: "L 사이즈 저장 실패")
        }
        requestLedger.append("create-size:\(request.sizeLabel):success")
        return CoorditFitLabExternalProductSizeRow(
            id: "size-fixture-\(request.sizeLabel)",
            externalProductID: productID,
            sizeLabel: request.sizeLabel
        )
    }

    func recommend(_ request: CoorditFitLabRecommendationRequest) async throws -> CoorditFitLabRecommendationResponse {
        requestLedger.append("recommend")
        if fixtureName == "submission-recommendation-race" {
            await withCheckedContinuation { continuation in
                recommendationContinuation = continuation
            }
        }
        return CoorditFitLabFixtures.upperRecommendation
    }

    func result(id: String) async throws -> CoorditFitLabAnalysisResultRow {
        requestLedger.append("result:\(id)")
        let data = Data(#"{"id":"analysis-fixture-upper","user_id":"coordit-fitlab-test-user","reference_clothing_id":"reference-fixture-1","external_product_id":"product-fixture-1","recommended_external_product_size_id":"size-fixture-M","recommended_size_label":"M","fit_score":92,"fit_label":"good_fit","fit_comment":"좋아요","recommendation_confidence":"high"}"#.utf8)
        return try JSONDecoder().decode(CoorditFitLabAnalysisResultRow.self, from: data)
    }

    func report(analysisID: String, request: CoorditFitLabReportRequest) async throws -> CoorditFitLabReportResponse {
        reportAttempts += 1
        requestLedger.append("report:\(analysisID)")
        if fixtureName == "submission-report-failure", reportAttempts == 1 {
            throw CoorditFitLabError.server(statusCode: 503, message: "리포트 생성 지연")
        }
        if fixtureName == "submission-report-race" {
            if reportAttempts == 1 {
                throw CoorditFitLabError.server(statusCode: 503, message: "리포트 생성 지연")
            }
            await withCheckedContinuation { continuation in
                reportContinuation = continuation
            }
        }
        return CoorditFitLabFixtures.report
    }

    func releaseRecommendation() {
        recommendationContinuation?.resume()
        recommendationContinuation = nil
    }

    func releaseReport() {
        reportContinuation?.resume()
        reportContinuation = nil
    }
}

struct CoorditFitLabFixtureOCRService: CoorditFitLabOCRServicing {
    nonisolated func recognizeSizeChart(imageData: Data) async throws -> CoorditFitLabOCRResult {
        let draft = CoorditFitLabFixtures.upperDraft
        return CoorditFitLabOCRResult(
            rawText: "SIZE SHOULDER CHEST LENGTH SLEEVE",
            confidence: 1,
            draft: draft,
            didFindTable: true,
            observations: []
        )
    }
}

actor CoorditFitLabFixtureHistoryStore: CoorditFitLabHistoryStoring {
    private var snapshots: [CoorditFitLabHistorySnapshot]

    init(snapshots: [CoorditFitLabHistorySnapshot] = []) {
        self.snapshots = snapshots
    }

    func load(userID: String) async throws -> [CoorditFitLabHistorySnapshot] {
        return snapshots.filter { $0.userID == userID }
    }

    func save(_ snapshot: CoorditFitLabHistorySnapshot) async throws {
        snapshots.removeAll { $0.id == snapshot.id && $0.userID == snapshot.userID }
        snapshots.insert(snapshot, at: 0)
    }

    func delete(snapshotID: String, userID: String) async throws {
        snapshots.removeAll { $0.id == snapshotID && $0.userID == userID }
    }
}

actor CoorditFitLabSuspendingHistoryStore: CoorditFitLabHistoryStoring {
    private var snapshots: [CoorditFitLabHistorySnapshot]
    private let suspendedLoadUserID: String?
    private var loadStarted = false
    private var saveStarted = false
    private var deleteStarted = false
    private var loadStartContinuation: CheckedContinuation<Void, Never>?
    private var saveStartContinuation: CheckedContinuation<Void, Never>?
    private var deleteStartContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var loadContinuation: CheckedContinuation<Void, Never>?

    init(snapshots: [CoorditFitLabHistorySnapshot], suspendedLoadUserID: String? = nil) {
        self.snapshots = snapshots
        self.suspendedLoadUserID = suspendedLoadUserID
    }

    func load(userID: String) async -> [CoorditFitLabHistorySnapshot] {
        if userID == suspendedLoadUserID {
            loadStarted = true
            loadStartContinuation?.resume()
            loadStartContinuation = nil
            await withCheckedContinuation { loadContinuation = $0 }
        }
        return snapshots.filter { $0.userID == userID }
    }

    func save(_ snapshot: CoorditFitLabHistorySnapshot) async throws {
        saveStarted = true
        saveStartContinuation?.resume()
        saveStartContinuation = nil
        await withCheckedContinuation { saveContinuation = $0 }
        try Task.checkCancellation()
        snapshots.removeAll { $0.id == snapshot.id && $0.userID == snapshot.userID }
        snapshots.insert(snapshot, at: 0)
    }

    func delete(snapshotID: String, userID: String) async throws {
        deleteStarted = true
        deleteStartContinuation?.resume()
        deleteStartContinuation = nil
        await withCheckedContinuation { deleteContinuation = $0 }
        try Task.checkCancellation()
        snapshots.removeAll { $0.id == snapshotID && $0.userID == userID }
    }

    func waitForSaveStart() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { saveStartContinuation = $0 }
    }

    func waitForLoadStart() async {
        guard !loadStarted else { return }
        await withCheckedContinuation { loadStartContinuation = $0 }
    }

    func waitForDeleteStart() async {
        guard !deleteStarted else { return }
        await withCheckedContinuation { deleteStartContinuation = $0 }
    }

    func releaseSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func releaseLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func releaseDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }

    func contains(analysisID: String, userID: String) -> Bool {
        snapshots.contains { $0.analysisID == analysisID && $0.userID == userID }
    }
}
#endif

#if DEBUG
enum CoorditFitLabFixtures {
    nonisolated static let upperDraft = CoorditFitLabDraft(
        source: .manual,
        garmentKind: .upper,
        category: .hoodie,
        productName: "픽스처 후드",
        sizes: [
            CoorditFitLabSizeDraft(
                label: "M",
                measurements: [.shoulderWidth: 54, .chestWidth: 58, .totalLength: 68, .sleeveLength: 61]
            )
        ],
        selectedReferenceIDs: ["reference-fixture-1"]
    )

    nonisolated static let submissionDraft = CoorditFitLabDraft(
        source: .manual,
        garmentKind: .upper,
        category: .hoodie,
        productName: "픽스처 후드",
        sizes: [
            CoorditFitLabSizeDraft(
                label: "M",
                measurements: [.shoulderWidth: 54, .chestWidth: 58, .totalLength: 68, .sleeveLength: 61]
            ),
            CoorditFitLabSizeDraft(
                label: "L",
                measurements: [.shoulderWidth: 56, .chestWidth: 60, .totalLength: 70, .sleeveLength: 63]
            ),
        ],
        selectedReferenceIDs: [],
        isSourceConfirmed: true
    )

    nonisolated static let upperRecommendation = CoorditFitLabRecommendationResponse(
        fitAnalysisResultID: "analysis-fixture-upper",
        recommendedSize: "M",
        fitScore: 92,
        fitLabel: "good_fit",
        fitComment: "기준 옷과 가장 비슷해요.",
        recommendationConfidence: "high",
        diff: [.shoulderWidth: 1, .chestWidth: 0.5, .totalLength: -1, .sleeveLength: 0],
        partExplanations: [
            "어깨는 기준 옷보다 정확히 1cm 여유로워요.",
            "가슴은 기준 옷과 거의 같아요.",
        ]
    )

    nonisolated static let lowerRecommendation = CoorditFitLabRecommendationResponse(
        fitAnalysisResultID: "analysis-fixture-lower",
        recommendedSize: "L",
        fitScore: 88,
        fitLabel: "good_fit",
        fitComment: "하의 기준 옷과 비슷해요.",
        recommendationConfidence: "high",
        diff: [.waistWidth: 1, .hipWidth: 0.5, .rise: -0.5, .outseam: 1]
    )

    nonisolated static let report = CoorditFitLabReportResponse(
        fitAnalysisResultID: "analysis-fixture-upper",
        source: "ollama",
        modelName: "fixture-llm",
        report: .init(
            title: "상의 핏 리포트",
            summary: "기준 옷과 비슷한 실루엣이며 가슴은 조금 타이트해요.",
            recommendationReason: "어깨와 총장 균형을 기준으로 M 사이즈를 추천해요.",
            measurementAnalysis: [
                .init(measurement: "어깨", text: "베스트보다 1 cm 여유 있어요."),
                .init(measurement: "가슴", text: "베스트보다 1.5 cm 타이트해요."),
            ],
            cautions: ["세탁 후 수축 가능성을 확인해 주세요."],
            nextActions: ["M 사이즈의 실측표를 한 번 더 확인해 주세요."]
        ),
        chartData: .init(
            idealVsProduct: [
                .init(measurement: .shoulderWidth, label: "어깨", ideal: 53, product: 54, diff: 1, status: "loose"),
                .init(measurement: .chestWidth, label: "가슴", ideal: 58, product: 56.5, diff: -1.5, status: "tight"),
                .init(measurement: .totalLength, label: "총장", ideal: 68, product: 68, diff: 0, status: "similar"),
                .init(measurement: .sleeveLength, label: "소매", ideal: 61, product: 60.5, diff: -0.5, status: "tight"),
            ]
        )
    )

    nonisolated static let lowerReport = CoorditFitLabReportResponse(
        fitAnalysisResultID: "analysis-fixture-lower",
        source: "ollama",
        modelName: "fixture-llm",
        report: .init(
            title: "하의 핏 리포트",
            summary: "허리와 총장은 여유 있고 힙은 기준과 비슷해요.",
            recommendationReason: "허리와 힙 균형을 기준으로 L 사이즈를 추천해요.",
            nextActions: ["밑위 착용감을 확인해 주세요."]
        ),
        chartData: .init(
            idealVsProduct: [
                .init(measurement: .waistWidth, label: "허리", ideal: 39, product: 40, diff: 1, status: "loose"),
                .init(measurement: .hipWidth, label: "힙", ideal: 50, product: 50, diff: 0, status: "similar"),
                .init(measurement: .rise, label: "밑위", ideal: 30, product: 29, diff: -1, status: "tight"),
                .init(measurement: .outseam, label: "총장", ideal: 100, product: 102, diff: 2, status: "loose"),
            ]
        )
    )

    nonisolated static let longReport = CoorditFitLabReportResponse(
        fitAnalysisResultID: "analysis-fixture-upper",
        source: "ollama",
        modelName: "fixture-long-llm",
        report: .init(
            title: "확장형 핏 리포트",
            summary: String(repeating: "긴 설명도 잘리지 않고 자연스럽게 이어져야 하며 사용자는 모든 분석 문장을 읽을 수 있어요. ", count: 34),
            recommendationReason: String(repeating: "베스트 실측과 상품 실측을 비교한 근거를 충분히 설명합니다. ", count: 18),
            measurementAnalysis: [
                .init(measurement: "어깨", text: String(repeating: "어깨선의 여유와 실루엣 변화를 자세히 설명합니다. ", count: 12)),
                .init(measurement: "가슴", text: String(repeating: "가슴 단면의 착용감과 레이어링 가능성을 자세히 설명합니다. ", count: 12)),
            ],
            cautions: [String(repeating: "원단과 세탁 방식에 따른 오차를 확인하세요. ", count: 10)],
            nextActions: ["긴 리포트의 마지막 액션"]
        ),
        chartData: .init(
            idealVsProduct: [
                .init(measurement: .shoulderWidth, label: "어깨", ideal: 53, product: 54, diff: 1, status: "loose"),
                .init(measurement: .chestWidth, label: "가슴", ideal: 58, product: 56.5, diff: -1.5, status: "tight"),
                .init(measurement: .totalLength, label: "총장", ideal: 68, product: 68, diff: 0, status: "similar"),
            ]
        )
    )
}
#endif
#endif
