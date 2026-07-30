import Foundation
import UIKit
import Vision

#if os(iOS)
struct CoorditClosetOCRSizeRow: Identifiable, Equatable {
    let id: UUID
    var label: String
    var measurements: [CoorditFitLabMeasurementKey: Double]
    var extractedText: String?
    var confidence: Double?

    init(
        id: UUID = UUID(),
        label: String,
        measurements: [CoorditFitLabMeasurementKey: Double],
        extractedText: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.measurements = measurements
        self.extractedText = extractedText
        self.confidence = confidence
    }

    var clothingSizeRequest: ClothingSizeRequest {
        ClothingSizeRequest(
            sizeLabel: label,
            rawMeasurements: [
                "source": "ios-closet-reviewed-ocr",
                "ocrText": extractedText ?? "",
            ],
            totalLength: measurements[.totalLength],
            shoulderWidth: measurements[.shoulderWidth],
            chestWidth: measurements[.chestWidth],
            sleeveLength: measurements[.sleeveLength],
            waistWidth: measurements[.waistWidth],
            hipWidth: measurements[.hipWidth],
            rise: measurements[.rise],
            outseam: measurements[.outseam]
        )
    }
}

enum CoorditFitLabSizeExtractor {
    static func closetRows(from imageData: Data) async throws -> [CoorditClosetOCRSizeRow] {
        let result = try await CoorditFitLabVisionOCRService().recognizeSizeChart(imageData: imageData)
        return result.draft.sizes.map { size in
            CoorditClosetOCRSizeRow(
                label: size.label,
                measurements: size.measurements,
                extractedText: result.rawText,
                confidence: result.confidence
            )
        }
    }

    static func referenceClothingSizeRequest(from draft: CoorditClosetDraft) async -> ClothingSizeRequest {
        if let selectedRow = draft.selectedSizeRow {
            return selectedRow.clothingSizeRequest
        }
        guard
            draft.method == .photo,
            let imageData = draft.sizeChartImageData,
            let image = UIImage(data: imageData),
            let cgImage = image.cgImage
        else {
            return draft.clothingSizeRequest
        }

        do {
            let extractedText = try recognizeText(in: cgImage)
            guard let row = parseSizeRows(from: extractedText).first else {
                return draft.clothingSizeRequest.withRawMeasurements([
                    "source": "ios-closet-photo-ocr-fallback",
                    "ocrText": extractedText
                ])
            }

            return clothingSizeRequest(
                for: row,
                category: draft.category,
                extractedText: extractedText
            )
        } catch {
            return draft.clothingSizeRequest.withRawMeasurements([
                "source": "ios-closet-photo-ocr-error-fallback"
            ])
        }
    }

    static func candidateSizes(
        from imageData: Data?,
        category: CoorditClosetCategory
    ) async -> [ExternalProductSizeRequest] {
        guard
            let imageData,
            let image = UIImage(data: imageData),
            let cgImage = image.cgImage
        else {
            return category.fitLabCandidateSizes
        }

        do {
            let extractedText = try recognizeText(in: cgImage)
            let parsedRows = parseSizeRows(from: extractedText)
            let parsedSizes = parsedRows.map { row in
                request(for: row, category: category, extractedText: extractedText)
            }

            guard !parsedSizes.isEmpty else {
                return category.fitLabCandidateSizes.map {
                    $0.withExtractionMetadata(
                        source: "ios-fitlab-ocr-empty-fallback",
                        parsingStatus: "fallback",
                        measurementSource: "fallback",
                        extractedText: extractedText,
                        extractionConfidence: 0.2
                    )
                }
            }

            return parsedSizes
        } catch {
            return category.fitLabCandidateSizes.map {
                $0.withExtractionMetadata(
                    source: "ios-fitlab-ocr-error-fallback",
                    parsingStatus: "fallback",
                    measurementSource: "fallback",
                    extractedText: nil,
                    extractionConfidence: 0.15
                )
            }
        }
    }

    private static func recognizeText(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            .joined(separator: "\n")
    }

    private static func parseSizeRows(from text: String) -> [ParsedSizeRow] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rows: [ParsedSizeRow] = []
        var seenLabels: Set<String> = []

        for startIndex in lines.indices {
            for width in 1...3 {
                let endIndex = startIndex + width
                guard endIndex <= lines.count else { continue }
                let chunk = lines[startIndex..<endIndex].joined(separator: " ")
                guard let row = parseSizeRow(from: chunk), !seenLabels.contains(row.label) else {
                    continue
                }
                rows.append(row)
                seenLabels.insert(row.label)
            }
        }

        return rows
    }

    private static func parseSizeRow(from text: String) -> ParsedSizeRow? {
        let normalized = text
            .uppercased()
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "CM", with: " ")

        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard let sizeIndex = tokens.firstIndex(where: { normalizedSizeLabel($0) != nil }) else {
            return nil
        }

        let numbers = tokens[(sizeIndex + 1)...]
            .compactMap(numberValue)
            .filter { (15...180).contains($0) }

        guard numbers.count >= 4, let label = normalizedSizeLabel(tokens[sizeIndex]) else {
            return nil
        }

        return ParsedSizeRow(label: label, values: Array(numbers.prefix(4)))
    }

    private static func normalizedSizeLabel(_ token: String) -> String? {
        let cleaned = token.filter { $0.isLetter || $0.isNumber }.uppercased()
        switch cleaned {
        case "S", "M", "L", "XL", "XXL", "FREE", "F":
            return cleaned == "F" ? "FREE" : cleaned
        default:
            return nil
        }
    }

    private nonisolated static func numberValue(_ token: String) -> Double? {
        let cleaned = token
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    private static func request(
        for row: ParsedSizeRow,
        category: CoorditClosetCategory,
        extractedText: String
    ) -> ExternalProductSizeRequest {
        switch category {
        case .top:
            ExternalProductSizeRequest(
                sizeLabel: row.label,
                rawSizeData: ["source": "ios-fitlab-ocr", "parser": "row-v1"],
                parsingStatus: "parsed",
                measurementSource: "ocr",
                extractedText: extractedText,
                extractionConfidence: 0.72,
                totalLength: row.values[2],
                shoulderWidth: row.values[0],
                chestWidth: row.values[1],
                sleeveLength: row.values[3],
                waistWidth: nil,
                hipWidth: nil,
                rise: nil,
                outseam: nil
            )
        case .bottom:
            ExternalProductSizeRequest(
                sizeLabel: row.label,
                rawSizeData: ["source": "ios-fitlab-ocr", "parser": "row-v1"],
                parsingStatus: "parsed",
                measurementSource: "ocr",
                extractedText: extractedText,
                extractionConfidence: 0.72,
                totalLength: nil,
                shoulderWidth: nil,
                chestWidth: nil,
                sleeveLength: nil,
                waistWidth: row.values[0],
                hipWidth: row.values[1],
                rise: row.values[2],
                outseam: row.values[3]
            )
        }
    }

    private static func clothingSizeRequest(
        for row: ParsedSizeRow,
        category: CoorditClosetCategory,
        extractedText: String
    ) -> ClothingSizeRequest {
        switch category {
        case .top:
            ClothingSizeRequest(
                sizeLabel: row.label,
                rawMeasurements: [
                    "source": "ios-closet-photo-ocr",
                    "parser": "row-v1",
                    "ocrText": extractedText
                ],
                totalLength: row.values[2],
                shoulderWidth: row.values[0],
                chestWidth: row.values[1],
                sleeveLength: row.values[3],
                waistWidth: nil,
                hipWidth: nil,
                rise: nil,
                outseam: nil
            )
        case .bottom:
            ClothingSizeRequest(
                sizeLabel: row.label,
                rawMeasurements: [
                    "source": "ios-closet-photo-ocr",
                    "parser": "row-v1",
                    "ocrText": extractedText
                ],
                totalLength: nil,
                shoulderWidth: nil,
                chestWidth: nil,
                sleeveLength: nil,
                waistWidth: row.values[0],
                hipWidth: row.values[1],
                rise: row.values[2],
                outseam: row.values[3]
            )
        }
    }
}

private struct ParsedSizeRow {
    let label: String
    let values: [Double]
}
#endif
