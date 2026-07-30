import Foundation

#if os(iOS)
struct CoorditFitLabReferenceRow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let clothingItemID: String
    let nickname: String?
    let category: CoorditFitLabCategory
    let fitType: String
    let preferenceScore: Double
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, nickname, category
        case clothingItemID = "clothing_item_id"
        case fitType = "fit_type"
        case preferenceScore = "preference_score"
        case isActive = "is_active"
    }
}

struct CoorditFitLabURLPrefillRequest: Codable, Equatable, Sendable {
    let url: URL
    let category: CoorditFitLabCategory?

    init(url: URL, category: CoorditFitLabCategory? = nil) {
        self.url = url
        self.category = category
    }
}

struct CoorditFitLabURLPrefillResponse: Codable, Equatable, Sendable {
    struct Size: Codable, Equatable, Sendable {
        let sizeLabel: String
        let shoulderWidth: Double?
        let chestWidth: Double?
        let totalLength: Double?
        let sleeveLength: Double?
        let waistWidth: Double?
        let hipWidth: Double?
        let rise: Double?
        let outseam: Double?
    }

    let productName: String
    let brand: String?
    let mallName: String?
    let productUrl: URL
    let category: CoorditFitLabCategory
    let fitType: String
    let parsingStatus: String
    let sizes: [Size]
}

struct CoorditFitLabProductRequest: Codable, Equatable, Sendable {
    let productName: String
    let brand: String?
    let mallName: String?
    let productURL: URL?
    let category: CoorditFitLabCategory
    let fitType: String

    enum CodingKeys: String, CodingKey {
        case productName, brand, mallName, category, fitType
        case productURL = "productUrl"
    }
}

struct CoorditFitLabExternalProductRow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let productName: String
    let category: CoorditFitLabCategory

    enum CodingKeys: String, CodingKey {
        case id, category
        case productName = "product_name"
    }
}

struct CoorditFitLabSizeRequest: Codable, Equatable, Sendable {
    let sizeLabel: String
    let measurements: [CoorditFitLabMeasurementKey: Double]
    let parsingStatus: String?
    let measurementSource: String?
    let extractedText: String?
    let extractionConfidence: Double?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(sizeLabel, forKey: DynamicCodingKey("sizeLabel"))
        try container.encodeIfPresent(parsingStatus, forKey: DynamicCodingKey("parsingStatus"))
        try container.encodeIfPresent(measurementSource, forKey: DynamicCodingKey("measurementSource"))
        try container.encodeIfPresent(extractedText, forKey: DynamicCodingKey("extractedText"))
        try container.encodeIfPresent(extractionConfidence, forKey: DynamicCodingKey("extractionConfidence"))
        for (key, value) in measurements {
            try container.encode(value, forKey: DynamicCodingKey(key.rawValue))
        }
    }

    init(
        sizeLabel: String,
        measurements: [CoorditFitLabMeasurementKey: Double],
        parsingStatus: String? = nil,
        measurementSource: String? = nil,
        extractedText: String? = nil,
        extractionConfidence: Double? = nil
    ) {
        self.sizeLabel = sizeLabel
        self.measurements = measurements
        self.parsingStatus = parsingStatus
        self.measurementSource = measurementSource
        self.extractedText = extractedText
        self.extractionConfidence = extractionConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        sizeLabel = try container.decode(String.self, forKey: DynamicCodingKey("sizeLabel"))
        parsingStatus = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("parsingStatus"))
        measurementSource = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("measurementSource"))
        extractedText = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("extractedText"))
        extractionConfidence = try container.decodeIfPresent(Double.self, forKey: DynamicCodingKey("extractionConfidence"))
        var decoded: [CoorditFitLabMeasurementKey: Double] = [:]
        for key in CoorditFitLabMeasurementKey.allCases {
            decoded[key] = try container.decodeIfPresent(Double.self, forKey: DynamicCodingKey(key.rawValue))
        }
        measurements = decoded
    }
}

struct CoorditFitLabExternalProductSizeRow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let externalProductID: String
    let sizeLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case externalProductID = "external_product_id"
        case sizeLabel = "size_label"
    }
}

struct CoorditFitLabRecommendationRequest: Codable, Equatable, Sendable {
    let referenceClothingIDs: [String]
    let externalProductID: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case referenceClothingIDs = "referenceClothingIds"
        case externalProductID = "externalProductId"
        case idempotencyKey
    }
}

struct CoorditFitLabRecommendationResponse: Codable, Equatable, Sendable {
    let fitAnalysisResultID: String
    let recommendedSize: String
    let fitScore: Double
    let fitLabel: String
    let fitComment: String
    let recommendationConfidence: String
    let diff: [CoorditFitLabMeasurementKey: Double]
    let partExplanations: [String]
    let availableThreads: Int?

    enum CodingKeys: String, CodingKey {
        case fitAnalysisResultID = "fitAnalysisResultId"
        case recommendedSize, fitScore, fitLabel, fitComment, recommendationConfidence, diff, partExplanations, availableThreads
    }

    init(
        fitAnalysisResultID: String,
        recommendedSize: String,
        fitScore: Double,
        fitLabel: String,
        fitComment: String,
        recommendationConfidence: String,
        diff: [CoorditFitLabMeasurementKey: Double],
        partExplanations: [String] = [],
        availableThreads: Int? = nil
    ) {
        self.fitAnalysisResultID = fitAnalysisResultID
        self.recommendedSize = recommendedSize
        self.fitScore = fitScore
        self.fitLabel = fitLabel
        self.fitComment = fitComment
        self.recommendationConfidence = recommendationConfidence
        self.diff = diff
        self.partExplanations = partExplanations
        self.availableThreads = availableThreads
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fitAnalysisResultID = try values.decode(String.self, forKey: .fitAnalysisResultID)
        recommendedSize = try values.decode(String.self, forKey: .recommendedSize)
        fitScore = try values.decode(Double.self, forKey: .fitScore)
        fitLabel = try values.decode(String.self, forKey: .fitLabel)
        fitComment = try values.decode(String.self, forKey: .fitComment)
        recommendationConfidence = try values.decode(String.self, forKey: .recommendationConfidence)
        let rawDiff = (try? values.decode([String: Double].self, forKey: .diff)) ?? [:]
        diff = Dictionary(uniqueKeysWithValues: rawDiff.compactMap { rawKey, value in
            CoorditFitLabMeasurementKey(rawValue: rawKey).map { ($0, value) }
        })
        partExplanations = (try? values.decode([String].self, forKey: .partExplanations)) ?? []
        availableThreads = try? values.decode(Int.self, forKey: .availableThreads)
    }
}

struct CoorditFitLabAnalysisResultRow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userID: String
    let referenceClothingID: String
    let externalProductID: String
    let recommendedExternalProductSizeID: String?
    let recommendedSizeLabel: String
    let fitScore: Double
    let fitLabel: String
    let fitComment: String
    let recommendationConfidence: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case referenceClothingID = "reference_clothing_id"
        case externalProductID = "external_product_id"
        case recommendedExternalProductSizeID = "recommended_external_product_size_id"
        case recommendedSizeLabel = "recommended_size_label"
        case fitScore = "fit_score"
        case fitLabel = "fit_label"
        case fitComment = "fit_comment"
        case recommendationConfidence = "recommendation_confidence"
    }
}

struct CoorditFitLabReportRequest: Codable, Equatable, Sendable {
    let selectedSizeLabel: String?
    let style: String?
}

struct CoorditFitLabReportResponse: Codable, Equatable, Sendable {
    struct Report: Codable, Equatable, Sendable {
        let title: String
        let summary: String
        let recommendationReason: String?
        let fitDnaSummary: String?
        let measurementAnalysis: [MeasurementAnalysis]
        let feedbackPersonalization: String?
        let cautions: [String]
        let nextActions: [String]

        struct MeasurementAnalysis: Codable, Equatable, Sendable {
            let measurement: String
            let text: String
        }

        init(
            title: String = "핏 리포트",
            summary: String = "",
            recommendationReason: String? = nil,
            fitDnaSummary: String? = nil,
            measurementAnalysis: [MeasurementAnalysis] = [],
            feedbackPersonalization: String? = nil,
            cautions: [String] = [],
            nextActions: [String] = []
        ) {
            self.title = title
            self.summary = summary
            self.recommendationReason = recommendationReason
            self.fitDnaSummary = fitDnaSummary
            self.measurementAnalysis = measurementAnalysis
            self.feedbackPersonalization = feedbackPersonalization
            self.cautions = cautions
            self.nextActions = nextActions
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decodeIfPresent(String.self, forKey: .title) ?? "핏 리포트"
            summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
            recommendationReason = try values.decodeIfPresent(String.self, forKey: .recommendationReason)
            fitDnaSummary = try values.decodeIfPresent(String.self, forKey: .fitDnaSummary)
            measurementAnalysis = (try? values.decode([MeasurementAnalysis].self, forKey: .measurementAnalysis)) ?? []
            feedbackPersonalization = try? values.decode(String.self, forKey: .feedbackPersonalization)
            cautions = (try? values.decode([String].self, forKey: .cautions)) ?? []
            nextActions = (try? values.decode([String].self, forKey: .nextActions)) ?? []
        }
    }

    struct ChartData: Codable, Equatable, Sendable {
        struct Comparison: Codable, Equatable, Sendable {
            let measurement: CoorditFitLabMeasurementKey
            let label: String
            let ideal: Double
            let product: Double
            let diff: Double
            let status: String?
        }

        struct Difference: Codable, Equatable, Sendable {
            let measurement: CoorditFitLabMeasurementKey
            let label: String
            let diff: Double
            let direction: String
            let status: String?
        }

        struct SizeScore: Codable, Equatable, Sendable {
            let sizeLabel: String
            let fitScore: Double
            let fitLabel: String
            let weightedFitDistance: Double
            let recommendationConfidence: String
        }

        let idealVsProduct: [Comparison]
        let differenceBar: [Difference]
        let sizeScoreRanking: [SizeScore]

        nonisolated init(
            idealVsProduct: [Comparison] = [],
            differenceBar: [Difference] = [],
            sizeScoreRanking: [SizeScore] = []
        ) {
            self.idealVsProduct = idealVsProduct
            self.differenceBar = differenceBar
            self.sizeScoreRanking = sizeScoreRanking
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let comparisonRows = (try? values.decode([LossyDecodable<Comparison>].self, forKey: .idealVsProduct)) ?? []
            let differenceRows = (try? values.decode([LossyDecodable<Difference>].self, forKey: .differenceBar)) ?? []
            let scoreRows = (try? values.decode([LossyDecodable<SizeScore>].self, forKey: .sizeScoreRanking)) ?? []
            idealVsProduct = comparisonRows.compactMap(\.value)
            differenceBar = differenceRows.compactMap(\.value)
            sizeScoreRanking = scoreRows.compactMap(\.value)
        }
    }

    let fitAnalysisResultID: String
    let source: String
    let modelName: String?
    let report: Report
    let chartData: ChartData

    init(
        fitAnalysisResultID: String,
        source: String,
        modelName: String? = nil,
        report: Report,
        chartData: ChartData
    ) {
        self.fitAnalysisResultID = fitAnalysisResultID
        self.source = source
        self.modelName = modelName
        self.report = report
        self.chartData = chartData
    }

    enum CodingKeys: String, CodingKey {
        case fitAnalysisResultID = "fitAnalysisResultId"
        case source, modelName, report, chartData
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fitAnalysisResultID = try values.decodeIfPresent(String.self, forKey: .fitAnalysisResultID) ?? ""
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "fallback"
        modelName = try values.decodeIfPresent(String.self, forKey: .modelName)
        report = (try? values.decode(Report.self, forKey: .report)) ?? Report()
        chartData = (try? values.decode(ChartData.self, forKey: .chartData)) ?? ChartData()
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
#endif
