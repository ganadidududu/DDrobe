import Foundation

#if os(iOS)
struct CoorditAuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let user: CoorditAuthUser
}

struct CoorditAuthUser: Codable, Equatable {
    let id: String
    let email: String
}

struct CoorditUserProfile: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    let gender: String?
    let birthDate: String?
    let birthYear: Int?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case gender
        case birthDate = "birth_date"
        case birthYear = "birth_year"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CoorditBodyMeasurement: Codable, Equatable {
    let id: String?
    let heightCm: Double?
    let weightKg: Double?
    let shoulderWidth: Double?
    let chestCircumference: Double?
    let waistCircumference: Double?
    let hipCircumference: Double?
    let outseam: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case shoulderWidth = "shoulder_width"
        case chestCircumference = "chest_circumference"
        case waistCircumference = "waist_circumference"
        case hipCircumference = "hip_circumference"
        case outseam
        case createdAt = "created_at"
    }
}

struct CoorditOnboardingStatus: Decodable, Equatable {
    let onboardingComplete: Bool
}

struct CoorditOnboardingRequest: Encodable {
    let displayName: String
    let gender: String?
    let birthDate: String?
    let bodyMeasurements: Measurements
    let consents: [String: Consent]

    struct Measurements: Encodable {
        let heightCm: Double?
        let weightKg: Double?
    }

    struct Consent: Encodable {
        let accepted: Bool
        let version: String
    }
}

struct CoorditBackendHealth: Codable, Equatable {
    let ok: Bool
    let service: String
}

struct CoorditThreadBalanceResponse: Codable, Equatable {
    let availableThreads: Int
}

struct CoorditBackendErrorResponse: Codable, Equatable {
    let message: String
}

struct CoorditClothingItemResponse: Codable, Equatable {
    let id: String
    let name: String
    let category: String
    let fitType: String
    let sizeLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case fitType = "fit_type"
        case sizeLabel = "size_label"
    }
}

struct CoorditClothingItemWithSizeResponse: Codable, Equatable {
    let clothingItem: CoorditClothingItemResponse
    let clothingSize: CoorditClothingSizeResponse
}

struct CoorditReferenceClothingResponse: Codable, Equatable {
    let id: String
    let clothingItemId: String
    let category: String
    let fitType: String
    let preferenceScore: Double?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case clothingItemId = "clothing_item_id"
        case category
        case fitType = "fit_type"
        case preferenceScore = "preference_score"
        case isActive = "is_active"
    }
}

struct CoorditExternalProductResponse: Codable, Equatable {
    let id: String
    let productName: String
    let category: String
    let fitType: String

    enum CodingKeys: String, CodingKey {
        case id
        case productName = "product_name"
        case category
        case fitType = "fit_type"
    }
}

struct CoorditExternalProductSizeResponse: Codable, Equatable {
    let id: String
    let sizeLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case sizeLabel = "size_label"
    }
}

struct CoorditClothingSizeResponse: Codable, Equatable {
    let id: String
    let sizeLabel: String?
    let totalLength: Double?
    let shoulderWidth: Double?
    let chestWidth: Double?
    let sleeveLength: Double?
    let waistWidth: Double?
    let hipWidth: Double?
    let rise: Double?
    let outseam: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case sizeLabel = "size_label"
        case totalLength = "total_length"
        case shoulderWidth = "shoulder_width"
        case chestWidth = "chest_width"
        case sleeveLength = "sleeve_length"
        case waistWidth = "waist_width"
        case hipWidth = "hip_width"
        case rise
        case outseam
    }

    var measurements: CoorditMeasurementMap {
        CoorditMeasurementMap(
            totalLength: totalLength,
            shoulderWidth: shoulderWidth,
            chestWidth: chestWidth,
            sleeveLength: sleeveLength,
            waistWidth: waistWidth,
            hipWidth: hipWidth,
            rise: rise,
            outseam: outseam
        )
    }
}

struct CoorditMeasurementMap: Codable, Equatable {
    var totalLength: Double?
    var shoulderWidth: Double?
    var chestWidth: Double?
    var sleeveLength: Double?
    var waistWidth: Double?
    var hipWidth: Double?
    var rise: Double?
    var outseam: Double?

    enum CodingKeys: String, CodingKey {
        case totalLength = "total_length"
        case shoulderWidth = "shoulder_width"
        case chestWidth = "chest_width"
        case sleeveLength = "sleeve_length"
        case waistWidth = "waist_width"
        case hipWidth = "hip_width"
        case rise
        case outseam
    }
}

struct CoorditReferenceFitProfileResponse: Codable, Equatable {
    let garmentKind: String
    let referenceCount: Int
    let measurements: CoorditMeasurementMap
    let sampleCounts: [String: Int]
    let strategy: String
}

struct CoorditFitRecommendation: Codable, Equatable {
    let fitAnalysisResultId: String
    let recommendedSize: String
    let fitScore: Double
    let fitLabel: String
    let fitComment: String
    let recommendationConfidence: String
    let diff: CoorditMeasurementMap
    let partExplanations: [String]
    let partStatuses: CoorditMeasurementStatusMap?
    let allSizeScores: [CoorditFitRecommendationSizeScore]
    let algorithmVersion: String
}

struct CoorditMeasurementStatusMap: Codable, Equatable {
    var totalLength: String?
    var shoulderWidth: String?
    var chestWidth: String?
    var sleeveLength: String?
    var waistWidth: String?
    var hipWidth: String?
    var rise: String?
    var outseam: String?

    enum CodingKeys: String, CodingKey {
        case totalLength = "total_length"
        case shoulderWidth = "shoulder_width"
        case chestWidth = "chest_width"
        case sleeveLength = "sleeve_length"
        case waistWidth = "waist_width"
        case hipWidth = "hip_width"
        case rise
        case outseam
    }
}

struct CoorditFitRecommendationSizeScore: Codable, Equatable {
    let externalProductSizeId: String
    let sizeLabel: String
    let fitScore: Double
    let fitLabel: String
    let recommendationConfidence: String
}
#endif
