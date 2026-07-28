import Foundation

#if os(iOS)
protocol CoorditFitLabAPI: Sendable {
    func compatibleReferences(category: CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow]
    func prefillProduct(from request: CoorditFitLabURLPrefillRequest) async throws -> CoorditFitLabURLPrefillResponse
    func createProduct(_ request: CoorditFitLabProductRequest) async throws -> CoorditFitLabExternalProductRow
    func createSize(productID: String, request: CoorditFitLabSizeRequest) async throws -> CoorditFitLabExternalProductSizeRow
    func recommend(_ request: CoorditFitLabRecommendationRequest) async throws -> CoorditFitLabRecommendationResponse
    func result(id: String) async throws -> CoorditFitLabAnalysisResultRow
    func report(analysisID: String, request: CoorditFitLabReportRequest) async throws -> CoorditFitLabReportResponse
}

struct CoorditFitLabHTTPAPI: CoorditFitLabAPI {
    private static let reportTimeoutInterval: TimeInterval = 180

    let baseURL: URL
    let accessToken: String
    var session: URLSession = .shared

    func compatibleReferences(category: CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow] {
        try await send(path: "/reference-clothing/by-category/\(category.rawValue)", method: "GET", body: Optional<String>.none)
    }

    func prefillProduct(from request: CoorditFitLabURLPrefillRequest) async throws -> CoorditFitLabURLPrefillResponse {
        try await send(path: "/external-products/from-url", method: "POST", body: request)
    }

    func createProduct(_ request: CoorditFitLabProductRequest) async throws -> CoorditFitLabExternalProductRow {
        try await send(path: "/external-products", method: "POST", body: request)
    }

    func createSize(productID: String, request: CoorditFitLabSizeRequest) async throws -> CoorditFitLabExternalProductSizeRow {
        try await send(path: "/external-products/\(productID)/sizes", method: "POST", body: request)
    }

    func recommend(_ request: CoorditFitLabRecommendationRequest) async throws -> CoorditFitLabRecommendationResponse {
        try await send(path: "/fit/recommend", method: "POST", body: request)
    }

    func result(id: String) async throws -> CoorditFitLabAnalysisResultRow {
        try await send(path: "/fit-analysis-results/\(id)", method: "GET", body: Optional<String>.none)
    }

    func report(analysisID: String, request: CoorditFitLabReportRequest) async throws -> CoorditFitLabReportResponse {
        try await send(path: "/fit-analysis-results/\(analysisID)/report", method: "POST", body: request)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let urlRequest = try makeRequest(path: path, method: method, body: body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CoorditFitLabError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).message)
                ?? "핏 분석 요청에 실패했어요."
            throw CoorditFitLabError.server(statusCode: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CoorditFitLabError.malformedResponse
        }
    }

    func makeRequest<Body: Encodable>(path: String, method: String, body: Body?) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: path))
        urlRequest.httpMethod = method
        if path.hasSuffix("/report") {
            urlRequest.timeoutInterval = Self.reportTimeoutInterval
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        return urlRequest
    }
}

private struct ErrorEnvelope: Decodable {
    let message: String
}
#endif
