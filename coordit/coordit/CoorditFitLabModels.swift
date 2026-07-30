import Foundation

#if os(iOS)
enum CoorditFitLabSource: String, Codable, CaseIterable, Sendable {
    case manual
    case ocr
    case url
}

enum CoorditFitLabGarmentKind: String, Codable, CaseIterable, Sendable {
    case upper
    case lower
}

enum CoorditFitLabCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tshirt, shirt, sweatshirt, hoodie, knit, jacket, coat
    case pants, jeans, shorts, skirt

    var id: Self { self }

    nonisolated var garmentKind: CoorditFitLabGarmentKind {
        switch self {
        case .tshirt, .shirt, .sweatshirt, .hoodie, .knit, .jacket, .coat: .upper
        case .pants, .jeans, .shorts, .skirt: .lower
        }
    }

    var koreanTitle: String {
        switch self {
        case .tshirt: "티셔츠"
        case .shirt: "셔츠"
        case .sweatshirt: "스웨트셔츠"
        case .hoodie: "후드"
        case .knit: "니트"
        case .jacket: "재킷"
        case .coat: "코트"
        case .pants: "팬츠"
        case .jeans: "데님"
        case .shorts: "쇼츠"
        case .skirt: "스커트"
        }
    }

    func isCompatible(with other: CoorditFitLabCategory) -> Bool {
        garmentKind == other.garmentKind
    }
}

enum CoorditFitLabMeasurementKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case shoulderWidth = "shoulder_width"
    case chestWidth = "chest_width"
    case totalLength = "total_length"
    case sleeveLength = "sleeve_length"
    case waistWidth = "waist_width"
    case hipWidth = "hip_width"
    case rise
    case outseam

    var id: Self { self }

    nonisolated var garmentKind: CoorditFitLabGarmentKind {
        switch self {
        case .shoulderWidth, .chestWidth, .totalLength, .sleeveLength: .upper
        case .waistWidth, .hipWidth, .rise, .outseam: .lower
        }
    }
}

enum CoorditFitLabScreen: String, Codable, CaseIterable, Sendable {
    case input
    case loading
    case resultUpper = "result_upper"
    case resultLower = "result_lower"
    case historyRegister = "history_register"
    case historyDetail = "history_detail"
    case loginRequired = "login_required"
}

enum CoorditFitLabSubmissionStep: String, Codable, CaseIterable, Sendable {
    case idle
    case loadingReferences = "loading_references"
    case creatingProduct = "creating_product"
    case creatingSizes = "creating_sizes"
    case recommending
    case loadingResult = "loading_result"
    case generatingReport = "generating_report"
    case complete
}

enum CoorditFitLabLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(CoorditFitLabError)
}

enum CoorditFitLabError: Error, Equatable, Sendable {
    case loginRequired
    case invalidDraft(String)
    case invalidURL
    case transport(String)
    case server(statusCode: Int, message: String)
    case malformedResponse
    case cancelled
}

extension CoorditFitLabError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .loginRequired: "핏 분석을 시작하려면 로그인이 필요해요."
        case .invalidDraft(let message), .transport(let message): message
        case .invalidURL: "상품 링크를 확인해 주세요."
        case .server(_, let message): message
        case .malformedResponse: "핏 분석 응답을 읽을 수 없어요."
        case .cancelled: "핏 분석이 취소되었어요."
        }
    }
}

struct CoorditFitLabSizeDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var label = ""
    var measurements: [CoorditFitLabMeasurementKey: Double] = [:]
}

struct CoorditFitLabDraft: Codable, Equatable, Sendable {
    var source: CoorditFitLabSource = .manual
    var garmentKind: CoorditFitLabGarmentKind = .upper
    var category: CoorditFitLabCategory = .tshirt
    var productName = ""
    var brand: String?
    var mallName: String?
    var productURL: URL?
    var sizes: [CoorditFitLabSizeDraft] = [CoorditFitLabSizeDraft()]
    var selectedReferenceIDs: Set<String> = []
    var ocrMetadata: CoorditFitLabOCRMetadata?
    var isSourceConfirmed = false
}

enum CoorditFitLabDraftValidation {
    nonisolated static func normalizedSizeLabel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    nonisolated static func duplicateSizeLabels(in labels: [String]) -> Set<String> {
        let normalized = labels.map(normalizedSizeLabel)
        let counts = Dictionary(grouping: normalized.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
    }

    nonisolated static func submissionError(for draft: CoorditFitLabDraft) -> String? {
        guard !draft.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "상품명을 입력해 주세요."
        }
        guard !draft.sizes.isEmpty else { return "사이즈 행을 하나 이상 추가해 주세요." }
        guard duplicateSizeLabels(in: draft.sizes.map(\.label)).isEmpty else {
            return "사이즈명은 중복될 수 없어요."
        }
        let allowedKeys = Set(CoorditFitLabMeasurementKey.allCases.filter {
            $0.garmentKind == draft.category.garmentKind
        })
        for row in draft.sizes {
            guard !normalizedSizeLabel(row.label).isEmpty else { return "모든 사이즈명을 입력해 주세요." }
            guard !row.measurements.isEmpty,
                  row.measurements.allSatisfy({ allowedKeys.contains($0.key) && $0.value.isFinite && $0.value > 0 })
            else { return "카테고리에 맞는 측정값을 사이즈마다 하나 이상 입력해 주세요." }
        }
        return nil
    }
}

struct CoorditFitLabSubmissionCheckpoint: Codable, Equatable, Sendable {
    var productID: String?
    var sizeIDsByDraftID: [UUID: String] = [:]
    var idempotencyKey: String?

    var isEmpty: Bool {
        productID == nil && sizeIDsByDraftID.isEmpty && idempotencyKey == nil
    }
}

struct CoorditFitLabOCRMetadata: Codable, Equatable, Sendable {
    let extractedText: String
    let confidence: Double
}

struct CoorditFitLabHistorySnapshot: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let currentSchemaVersion = 2

    struct ProductSummary: Codable, Equatable, Sendable {
        let name: String
        let brand: String?
        let mallName: String?
        let url: URL?

        nonisolated init(name: String, brand: String?, mallName: String?, url: URL?) {
            self.name = name
            self.brand = brand
            self.mallName = mallName
            self.url = url
        }
    }

    struct ReferenceSummary: Codable, Equatable, Sendable {
        let id: String
        let name: String
    }

    let schemaVersion: Int
    let id: String
    let analysisID: String
    let userID: String
    let savedAt: Date
    let product: ProductSummary
    let category: CoorditFitLabCategory
    let garmentKind: CoorditFitLabGarmentKind
    let references: [ReferenceSummary]
    let originalSource: CoorditFitLabSource
    let recommendation: CoorditFitLabRecommendationResponse
    let report: CoorditFitLabReportResponse?
    let chartData: CoorditFitLabReportResponse.ChartData

    nonisolated init(
        schemaVersion: Int = currentSchemaVersion,
        id: String,
        analysisID: String,
        userID: String,
        savedAt: Date,
        product: ProductSummary,
        category: CoorditFitLabCategory,
        garmentKind: CoorditFitLabGarmentKind,
        references: [ReferenceSummary],
        originalSource: CoorditFitLabSource,
        recommendation: CoorditFitLabRecommendationResponse,
        report: CoorditFitLabReportResponse?,
        chartData: CoorditFitLabReportResponse.ChartData
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.analysisID = analysisID
        self.userID = userID
        self.savedAt = savedAt
        self.product = product
        self.category = category
        self.garmentKind = garmentKind
        self.references = references
        self.originalSource = originalSource
        self.recommendation = recommendation
        self.report = report
        self.chartData = chartData
    }
}

protocol CoorditFitLabOCRServicing: Sendable {
    nonisolated func recognizeSizeChart(imageData: Data) async throws -> CoorditFitLabOCRResult
}
#endif
