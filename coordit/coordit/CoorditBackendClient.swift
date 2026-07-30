import Foundation

#if os(iOS)
enum CoorditBackendConfig {
    private static let unavailableReleaseURL = URL(string: "https://api.coordit.invalid")!

    static func baseURL(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL {
        if let url = configuredURL(arguments: arguments) {
            UserDefaults.standard.set(url.absoluteString, forKey: "coordit.apiBaseURL")
            return url
        }

        #if DEBUG
        return URL(string: "http://localhost:4000")!
        #else
        return unavailableReleaseURL
        #endif
    }

    static var isConfigured: Bool {
        configuredURL(arguments: ProcessInfo.processInfo.arguments) != nil
    }

    private static func configuredURL(arguments: [String]) -> URL? {
        if
            let markerIndex = arguments.firstIndex(of: "--coordit-api-base-url"),
            arguments.indices.contains(arguments.index(after: markerIndex)),
            let url = URL(string: arguments[arguments.index(after: markerIndex)]),
            isAllowed(url)
        {
            return url
        }

        if
            let bundled = Bundle.main.object(forInfoDictionaryKey: "CoorditAPIBaseURL") as? String,
            !bundled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !bundled.contains("$("),
            let url = URL(string: bundled),
            isAllowed(url)
        {
            return url
        }

        if
            let saved = UserDefaults.standard.string(forKey: "coordit.apiBaseURL"),
            let url = URL(string: saved),
            isAllowed(url)
        {
            return url
        }
        return nil
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard url.host?.isEmpty == false else { return false }
        #if DEBUG
        return ["http", "https"].contains(url.scheme?.lowercased())
        #else
        return url.scheme?.lowercased() == "https"
        #endif
    }
}

enum CoorditBackendClientError: LocalizedError {
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "백엔드 응답을 읽을 수 없어요."
        case .server(_, let message):
            message
        }
    }
}

struct CoorditBackendClient {
    let baseURL: URL
    var session: URLSession = .shared

    func health() async throws -> CoorditBackendHealth {
        try await send(path: "/health", method: "GET", token: nil, body: Optional<String>.none)
    }

    func login(email: String, password: String) async throws -> CoorditAuthSession {
        try await send(path: "/auth/login", method: "POST", token: nil, body: AuthRequest(email: email, password: password))
    }

    func signup(email: String, password: String) async throws -> CoorditAuthSession {
        try await send(path: "/auth/signup", method: "POST", token: nil, body: AuthRequest(email: email, password: password))
    }

    func loginWithGoogle(idToken: String) async throws -> CoorditAuthSession {
        try await send(path: "/auth/google", method: "POST", token: nil, body: GoogleAuthRequest(idToken: idToken))
    }

    func me(token: String) async throws -> CoorditUserProfile {
        try await send(path: "/users/me", method: "GET", token: token, body: Optional<String>.none)
    }

    func updateMe(token: String, displayName: String) async throws -> CoorditUserProfile {
        try await send(path: "/users/me", method: "PATCH", token: token, body: UpdateProfileRequest(displayName: displayName))
    }

    func deleteAccount(token: String) async throws {
        try await sendWithoutResponse(path: "/users/me", method: "DELETE", token: token)
    }

    func listBodyMeasurements(token: String) async throws -> [CoorditBodyMeasurement] {
        try await send(path: "/body-measurements", method: "GET", token: token, body: Optional<String>.none)
    }

    func createBodyMeasurement(token: String, request: BodyMeasurementRequest) async throws -> CoorditBodyMeasurement {
        try await send(path: "/body-measurements", method: "POST", token: token, body: request)
    }

    func threadBalance(token: String) async throws -> CoorditThreadBalanceResponse {
        try await send(path: "/thread-wallet/balance", method: "GET", token: token, body: Optional<String>.none)
    }

    func createClothingItem(token: String, request: CreateClothingItemRequest) async throws -> CoorditClothingItemResponse {
        try await send(path: "/clothing-items", method: "POST", token: token, body: request)
    }

    func createClothingItemWithSize(
        token: String,
        clothingItem: CreateClothingItemRequest,
        clothingSize: ClothingSizeRequest,
        idempotencyKey: String
    ) async throws -> CoorditClothingItemWithSizeResponse {
        try await send(
            path: "/clothing-items/with-size",
            method: "POST",
            token: token,
            body: CreateClothingItemWithSizeRequest(
                item: clothingItem,
                size: clothingSize,
                idempotencyKey: idempotencyKey
            )
        )
    }

    func listClothingItems(token: String) async throws -> [CoorditClothingItemResponse] {
        try await send(path: "/clothing-items", method: "GET", token: token, body: Optional<String>.none)
    }

    func deleteClothingItem(token: String, id: String) async throws {
        try await sendWithoutResponse(path: "/clothing-items/\(id)", method: "DELETE", token: token)
    }

    func createClothingSize(
        token: String,
        clothingItemId: String,
        request: ClothingSizeRequest
    ) async throws -> CoorditClothingSizeResponse {
        try await send(path: "/clothing-items/\(clothingItemId)/sizes", method: "POST", token: token, body: request)
    }

    func listClothingSizes(token: String, clothingItemId: String) async throws -> [CoorditClothingSizeResponse] {
        try await send(
            path: "/clothing-items/\(clothingItemId)/sizes",
            method: "GET",
            token: token,
            body: Optional<String>.none
        )
    }

    func createReferenceClothing(
        token: String,
        request: CreateReferenceClothingRequest
    ) async throws -> CoorditReferenceClothingResponse {
        try await send(path: "/reference-clothing", method: "POST", token: token, body: request)
    }

    func listReferenceClothing(token: String, category: String) async throws -> [CoorditReferenceClothingResponse] {
        try await send(path: "/reference-clothing/by-category/\(category)", method: "GET", token: token, body: Optional<String>.none)
    }

    func listReferenceClothing(token: String) async throws -> [CoorditReferenceClothingResponse] {
        try await send(path: "/reference-clothing", method: "GET", token: token, body: Optional<String>.none)
    }

    func deactivateReferenceClothing(token: String, id: String) async throws -> CoorditReferenceClothingResponse {
        try await send(path: "/reference-clothing/\(id)/deactivate", method: "PATCH", token: token, body: Optional<String>.none)
    }

    func reassessClothingItem(token: String, id: String) async throws -> CoorditClothingFitAssessmentResponse {
        try await send(path: "/clothing-items/\(id)/fit-reassessment", method: "POST", token: token, body: Optional<String>.none)
    }

    func referenceFitProfile(
        token: String,
        garmentKind: String
    ) async throws -> CoorditReferenceFitProfileResponse {
        try await send(
            path: "/fit/reference-profile/\(garmentKind)",
            method: "GET",
            token: token,
            body: Optional<String>.none
        )
    }

    func createExternalProduct(
        token: String,
        request: CreateExternalProductRequest
    ) async throws -> CoorditExternalProductResponse {
        try await send(path: "/external-products", method: "POST", token: token, body: request)
    }

    func createExternalProductSize(
        token: String,
        externalProductId: String,
        request: ExternalProductSizeRequest
    ) async throws -> CoorditExternalProductSizeResponse {
        try await send(path: "/external-products/\(externalProductId)/sizes", method: "POST", token: token, body: request)
    }

    func recommendFit(token: String, request: FitRecommendRequest) async throws -> CoorditFitRecommendation {
        try await send(path: "/fit/recommend", method: "POST", token: token, body: request)
    }

    private func send<ResponseBody: Decodable, RequestBody: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: RequestBody?
    ) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoorditBackendClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(CoorditBackendErrorResponse.self, from: data)
            throw CoorditBackendClientError.server(
                statusCode: httpResponse.statusCode,
                message: apiError?.message ?? "백엔드 요청에 실패했어요."
            )
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func sendWithoutResponse(path: String, method: String, token: String?) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoorditBackendClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(CoorditBackendErrorResponse.self, from: data)
            throw CoorditBackendClientError.server(
                statusCode: httpResponse.statusCode,
                message: apiError?.message ?? "백엔드 요청에 실패했어요."
            )
        }
    }
}

private struct AuthRequest: Encodable {
    let email: String
    let password: String
}

private struct GoogleAuthRequest: Encodable {
    let idToken: String
}

private struct UpdateProfileRequest: Encodable {
    let displayName: String
}

struct BodyMeasurementRequest: Encodable {
    let shoulderWidth: Double?
    let chestCircumference: Double?
    let waistCircumference: Double?
    let hipCircumference: Double?
    let rawData: RawData

    struct RawData: Encodable {
        let source: String
        let inseamCm: Double?
    }
}

struct CreateClothingItemRequest: Encodable {
    let name: String
    let category: String
    let fitType: String
    let sizeLabel: String?
    let rawProductData: [String: String]
}

private struct CreateClothingItemWithSizeRequest: Encodable {
    let item: CreateClothingItemRequest
    let size: ClothingSizeRequest
    let idempotencyKey: String
}

struct ClothingSizeRequest: Encodable {
    let sizeLabel: String?
    let rawMeasurements: [String: String]
    let totalLength: Double?
    let shoulderWidth: Double?
    let chestWidth: Double?
    let sleeveLength: Double?
    let waistWidth: Double?
    let hipWidth: Double?
    let rise: Double?
    let outseam: Double?

    enum CodingKeys: String, CodingKey {
        case sizeLabel
        case rawMeasurements
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

struct CreateReferenceClothingRequest: Encodable {
    let clothingItemId: String
    let nickname: String?
    let category: String
    let fitType: String
    let preferenceScore: Double
    let isActive: Bool
    let notes: String?
}

struct CreateExternalProductRequest: Encodable {
    let productName: String
    let brand: String?
    let mallName: String?
    let productUrl: String?
    let category: String
    let fitType: String
    let rawProductData: [String: String]
}

struct ExternalProductSizeRequest: Encodable {
    let sizeLabel: String
    let rawSizeData: [String: String]
    let parsingStatus: String
    let measurementSource: String
    let extractedText: String?
    let extractionConfidence: Double?
    let totalLength: Double?
    let shoulderWidth: Double?
    let chestWidth: Double?
    let sleeveLength: Double?
    let waistWidth: Double?
    let hipWidth: Double?
    let rise: Double?
    let outseam: Double?

    enum CodingKeys: String, CodingKey {
        case sizeLabel
        case rawSizeData
        case parsingStatus
        case measurementSource
        case extractedText
        case extractionConfidence
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

struct FitRecommendRequest: Encodable {
    let referenceClothingIds: [String]
    let externalProductId: String
    let idempotencyKey: String
}
#endif
