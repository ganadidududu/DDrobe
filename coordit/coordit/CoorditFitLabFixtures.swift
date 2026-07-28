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
    static let expectedStatus = "CONTRACT_OK url-request url-body size-keys reference product size recommendation-parts result report report-timeout adversarial"

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

            let reportRequest = try api.makeRequest(
                path: "/fit-analysis-results/analysis-1/report",
                method: "POST",
                body: CoorditFitLabReportRequest(selectedSizeLabel: "M", style: "detailed")
            )
            guard reportRequest.timeoutInterval >= 180 else {
                return "CONTRACT_ERROR report-timeout \(reportRequest.timeoutInterval)"
            }
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
        if fixtureName == "submission-report-fallback", reportAttempts == 1 {
            let completed = CoorditFitLabFixtures.report
            return CoorditFitLabReportResponse(
                fitAnalysisResultID: completed.fitAnalysisResultID,
                source: "fallback",
                modelName: nil,
                report: completed.report,
                chartData: completed.chartData
            )
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
            title: "M 사이즈 정밀 핏 리포트",
            summary: "M 사이즈는 92점으로 전체 후보 중 가장 안정적인 균형을 보여요. 어깨에는 자연스러운 여유가 있고 총장은 기준과 같아 전체 실루엣이 익숙하게 떨어집니다. 가슴과 소매는 기준보다 조금 작아 상체 라인은 상대적으로 정돈되어 보일 수 있어요.",
            recommendationReason: "S 사이즈는 가슴과 소매의 타이트함이 더 커질 수 있고, L 사이즈는 어깨와 몸통의 여유가 함께 증가합니다. M 사이즈는 어깨 1cm 여유와 동일한 총장을 유지하면서 가슴 차이를 1.5cm 안쪽으로 제한합니다. 폭과 길이 중 어느 한쪽으로 치우치지 않고 기준 의류의 실루엣에 가장 가깝게 접근한 후보이기 때문에 M을 추천해요.",
            measurementAnalysis: [
                .init(measurement: "어깨", text: "기준 53cm와 상품 54cm를 비교하면 1cm 여유가 있습니다. 어깨선이 지나치게 내려가지 않으면서 움직임에 필요한 공간을 확보하는 정도예요. 정사이즈 실루엣을 유지하면서 상체가 답답해 보이지 않는 차이입니다."),
                .init(measurement: "가슴", text: "기준 58cm보다 상품이 1.5cm 작습니다. 몸통이 기준 의류보다 조금 더 정돈되어 보이고, 두꺼운 이너를 입으면 가슴 부위가 타이트하게 느껴질 수 있어요. 단독 착용에서는 슬림한 상체 실루엣을 만드는 방향입니다."),
                .init(measurement: "총장", text: "기준과 상품이 모두 68cm로 동일합니다. 평소 익숙한 상의 길이와 밑단 위치를 그대로 기대할 수 있어요."),
                .init(measurement: "소매", text: "상품 소매는 기준보다 0.5cm 짧습니다. 손목에 닿는 위치가 아주 조금 올라가지만 전체 비율을 바꿀 정도의 차이는 아닙니다."),
            ],
            cautions: ["세탁 후 수축 가능성을 확인해 주세요."],
            nextActions: ["M 사이즈의 실측표를 한 번 더 확인해 주세요."]
        ),
        chartData: .init(
            idealVsProduct: [
                .init(measurement: .shoulderWidth, label: "어깨", ideal: 53, product: 54, diff: 1, status: "loose"),
                .init(measurement: .chestWidth, label: "가슴", ideal: 58, product: 56.5, diff: -1.5, status: "tight"),
                .init(measurement: .totalLength, label: "총장", ideal: 68, product: 68, diff: 0, status: "similar"),
                .init(measurement: .sleeveLength, label: "소매", ideal: 61, product: 60.5, diff: -0.5, status: "similar"),
            ],
            sizeScoreRanking: [
                .init(sizeLabel: "S", fitScore: 76, fitLabel: "acceptable", weightedFitDistance: 2.8, recommendationConfidence: "high"),
                .init(sizeLabel: "M", fitScore: 92, fitLabel: "good_fit", weightedFitDistance: 0.8, recommendationConfidence: "high"),
                .init(sizeLabel: "L", fitScore: 81, fitLabel: "good_fit", weightedFitDistance: 2.1, recommendationConfidence: "high"),
            ]
        )
    )

    nonisolated static let lowerReport = CoorditFitLabReportResponse(
        fitAnalysisResultID: "analysis-fixture-lower",
        source: "ollama",
        modelName: "fixture-llm",
        report: .init(
            title: "L 사이즈 정밀 핏 리포트",
            summary: "L 사이즈는 88점으로 허리와 총장에 편안한 여유를 확보하면서 힙은 기준 의류와 같은 균형을 유지합니다. 밑위는 기준보다 1cm 짧아 허리선의 위치가 조금 더 낮게 느껴질 수 있어요. 전체적으로 과하게 넓지 않으면서 다리 길이를 여유 있게 가져가는 실루엣입니다.",
            recommendationReason: "M 사이즈는 허리와 힙의 여유가 줄어들어 앉거나 움직일 때 더 타이트하게 느껴질 수 있습니다. XL은 허리와 총장의 여유가 함께 커져 기준 의류보다 루즈한 인상이 강해질 수 있어요. L은 힙 50cm를 그대로 유지하면서 허리 1cm, 총장 2cm의 여유를 더해 폭과 길이의 균형이 가장 안정적입니다. 따라서 익숙한 힙 실루엣을 보존하면서 활동성과 길이를 확보하는 L 사이즈를 추천해요.",
            measurementAnalysis: [
                .init(measurement: "허리", text: "기준 39cm보다 상품이 1cm 큽니다. 허리를 강하게 조이지 않으면서도 밴드나 벨트로 조절하기 쉬운 정도의 여유예요."),
                .init(measurement: "힙", text: "기준과 상품이 모두 50cm로 동일합니다. 골반과 힙 주변의 볼륨은 평소 잘 맞는 하의와 가장 비슷하게 유지될 가능성이 높아요."),
                .init(measurement: "밑위", text: "상품 밑위는 기준보다 1cm 짧습니다. 허리선이 조금 낮게 자리하고 앉았을 때 복부를 감싸는 범위가 줄어들 수 있어요."),
                .init(measurement: "총장", text: "상품 총장은 기준보다 2cm 깁니다. 신발 위로 떨어지는 길이가 늘어나 다리선이 길어 보일 수 있지만 밑단이 쌓이는지는 확인하는 편이 좋아요."),
            ],
            cautions: ["원단의 신축성과 허리 여밈 방식을 함께 확인해 주세요."],
            nextActions: ["밑위 착용감을 확인해 주세요."]
        ),
        chartData: .init(
            idealVsProduct: [
                .init(measurement: .waistWidth, label: "허리", ideal: 39, product: 40, diff: 1, status: "loose"),
                .init(measurement: .hipWidth, label: "힙", ideal: 50, product: 50, diff: 0, status: "similar"),
                .init(measurement: .rise, label: "밑위", ideal: 30, product: 29, diff: -1, status: "tight"),
                .init(measurement: .outseam, label: "총장", ideal: 100, product: 102, diff: 2, status: "loose"),
            ],
            sizeScoreRanking: [
                .init(sizeLabel: "M", fitScore: 72, fitLabel: "acceptable", weightedFitDistance: 3.1, recommendationConfidence: "high"),
                .init(sizeLabel: "L", fitScore: 88, fitLabel: "good_fit", weightedFitDistance: 1.1, recommendationConfidence: "high"),
                .init(sizeLabel: "XL", fitScore: 79, fitLabel: "acceptable", weightedFitDistance: 2.4, recommendationConfidence: "high"),
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
