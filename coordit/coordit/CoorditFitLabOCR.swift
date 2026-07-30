import CoreGraphics
import Foundation
import ImageIO
import Vision

#if os(iOS)
#if DEBUG
actor CoorditFitLabVisionExecutionProbe {
    static let shared = CoorditFitLabVisionExecutionProbe()
    private var wasOnMainThread: Bool?

    func reset() { wasOnMainThread = nil }
    func record(_ value: Bool) { wasOnMainThread = value }
    func value() -> Bool? { wasOnMainThread }
}
#endif

struct CoorditFitLabOCRBox: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    nonisolated init(_ rectangle: CGRect) {
        x = rectangle.origin.x
        y = rectangle.origin.y
        width = rectangle.width
        height = rectangle.height
    }

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
}

struct CoorditFitLabOCRObservation: Equatable, Sendable {
    let text: String
    let confidence: Double
    let box: CoorditFitLabOCRBox
}

struct CoorditFitLabOCRResult: Equatable, Sendable {
    let rawText: String
    let confidence: Double
    let draft: CoorditFitLabDraft
    let didFindTable: Bool
    let observations: [CoorditFitLabOCRObservation]
    let visionExecutionWasOnMainThread: Bool?

    nonisolated init(
        rawText: String,
        confidence: Double,
        draft: CoorditFitLabDraft,
        didFindTable: Bool,
        observations: [CoorditFitLabOCRObservation],
        visionExecutionWasOnMainThread: Bool? = nil
    ) {
        self.rawText = rawText
        self.confidence = confidence
        self.draft = draft
        self.didFindTable = didFindTable
        self.observations = observations
        self.visionExecutionWasOnMainThread = visionExecutionWasOnMainThread
    }
}

extension CoorditFitLabDraft {
    var confirmedSizeRequests: [CoorditFitLabSizeRequest] {
        let confirmedOCR = source == .ocr && isSourceConfirmed ? ocrMetadata : nil
        return sizes.map { size in
            CoorditFitLabSizeRequest(
                sizeLabel: size.label,
                measurements: size.measurements,
                parsingStatus: confirmedOCR == nil ? "manual" : "parsed",
                measurementSource: source.rawValue,
                extractedText: confirmedOCR?.extractedText,
                extractionConfidence: confirmedOCR?.confidence
            )
        }
    }
}

protocol CoorditFitLabOCRParsing: Sendable {
    func parse(observations: [CoorditFitLabOCRObservation]) -> CoorditFitLabOCRResult
}

struct CoorditFitLabVisionOCRService: CoorditFitLabOCRServicing {
    private let parser: any CoorditFitLabOCRParsing

    nonisolated init(parser: any CoorditFitLabOCRParsing = CoorditFitLabSizeChartOCRParser()) {
        self.parser = parser
    }

    nonisolated func recognizeSizeChart(imageData: Data) async throws -> CoorditFitLabOCRResult {
        try await recognizeSizeChart(imageData: imageData, delayNanoseconds: 0)
    }

    #if DEBUG
    nonisolated func recognizeSizeChart(
        imageData: Data,
        debugDelayNanoseconds: UInt64
    ) async throws -> CoorditFitLabOCRResult {
        try await recognizeSizeChart(imageData: imageData, delayNanoseconds: debugDelayNanoseconds)
    }
    #endif

    private nonisolated func recognizeSizeChart(
        imageData: Data,
        delayNanoseconds: UInt64
    ) async throws -> CoorditFitLabOCRResult {
        let recognitionTask = Task.detached(priority: .userInitiated) {
            #if DEBUG
            await CoorditFitLabVisionExecutionProbe.shared.record(false)
            #endif
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            try Task.checkCancellation()
            return try Self.recognizeObservations(imageData: imageData)
        }
        let output = try await withTaskCancellationHandler {
            try await recognitionTask.value
        } onCancel: {
            recognitionTask.cancel()
        }
        try Task.checkCancellation()
        let parsed = await MainActor.run {
            parser.parse(observations: output.observations)
        }
        try Task.checkCancellation()
        return CoorditFitLabOCRResult(
            rawText: parsed.rawText,
            confidence: parsed.confidence,
            draft: parsed.draft,
            didFindTable: parsed.didFindTable,
            observations: parsed.observations,
            visionExecutionWasOnMainThread: output.wasOnMainThread
        )
    }

    private struct RecognitionOutput: Sendable {
        let observations: [CoorditFitLabOCRObservation]
        let wasOnMainThread: Bool
    }

    private nonisolated static func recognizeObservations(imageData: Data) throws -> RecognitionOutput {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CoorditFitLabError.invalidDraft("이미지를 읽을 수 없어요.")
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        try VNImageRequestHandler(cgImage: image).perform([request])

        let observations = (request.results ?? []).compactMap { observation -> CoorditFitLabOCRObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return CoorditFitLabOCRObservation(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                box: CoorditFitLabOCRBox(observation.boundingBox)
            )
        }
        return RecognitionOutput(observations: observations, wasOnMainThread: Thread.isMainThread)
    }
}

struct CoorditFitLabSizeChartOCRParser: CoorditFitLabOCRParsing {
    nonisolated init() {}

    func parse(observations: [CoorditFitLabOCRObservation]) -> CoorditFitLabOCRResult {
        let tokens = expandedTokens(observations)
        let rows = clusteredRows(tokens)
        let rawText = rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        let confidence = observations.isEmpty
            ? 0
            : observations.map(\.confidence).reduce(0, +) / Double(observations.count)

        guard let headerIndex = rows.firstIndex(where: isHeaderRow) else {
            return result(rawText: rawText, confidence: confidence, observations: observations)
        }
        let header = rows[headerIndex]
        let groupedColumns = Dictionary(grouping: header.compactMap { token in
            measurementKey(for: token.text).map { ($0, token.box.midX) }
        }, by: \.0)
        let columns = groupedColumns.reduce(into: [CoorditFitLabMeasurementKey: Double]()) { resolved, entry in
            let sortedPositions = entry.value.map(\.1).sorted()
            guard !sortedPositions.isEmpty else { return }
            let middle = sortedPositions.count / 2
            resolved[entry.key] = sortedPositions.count.isMultiple(of: 2)
                ? (sortedPositions[middle - 1] + sortedPositions[middle]) / 2
                : sortedPositions[middle]
        }
        guard !columns.isEmpty else {
            return result(rawText: rawText, confidence: confidence, observations: observations)
        }

        let sizeX = header.first(where: { isSizeAlias($0.text) })?.box.midX ?? 0
        let kind: CoorditFitLabGarmentKind = columns.keys.filter { $0.garmentKind == .lower }.count
            > columns.keys.filter { $0.garmentKind == .upper }.count ? .lower : .upper
        var sizes: [CoorditFitLabSizeDraft] = []

        for row in rows.dropFirst(headerIndex + 1) {
            let compatibleColumns = columns.filter { $0.key.garmentKind == kind }
            let labelToken = row.min { abs($0.box.midX - sizeX) < abs($1.box.midX - sizeX) }
            guard let labelToken else { continue }
            let label = cleanedLabel(labelToken.text)
            guard !label.isEmpty, Double(label) == nil || abs(labelToken.box.midX - sizeX) < 0.12 else { continue }

            var measurements: [CoorditFitLabMeasurementKey: Double] = [:]
            var used = Set<Int>()
            if let labelIndex = row.firstIndex(of: labelToken) { used.insert(labelIndex) }
            for (key, x) in compatibleColumns.sorted(by: { $0.value < $1.value }) {
                guard let candidate = row.enumerated()
                    .filter({ !used.contains($0.offset) })
                    .compactMap({ index, token in numericValue(token.text).map { (index, token, $0) } })
                    .min(by: { abs($0.1.box.midX - x) < abs($1.1.box.midX - x) })
                else { continue }
                let nearestOtherDistance = compatibleColumns
                    .filter { $0.key != key }
                    .map { abs(candidate.1.box.midX - $0.value) }
                    .min() ?? .greatestFiniteMagnitude
                guard abs(candidate.1.box.midX - x) <= nearestOtherDistance else { continue }
                used.insert(candidate.0)
                measurements[key] = candidate.2
            }
            if !measurements.isEmpty {
                sizes.append(CoorditFitLabSizeDraft(label: label, measurements: measurements))
            }
        }

        guard !sizes.isEmpty else {
            return result(rawText: rawText, confidence: confidence, observations: observations)
        }
        let draft = CoorditFitLabDraft(
            source: .ocr,
            garmentKind: kind,
            category: kind == .upper ? .tshirt : .pants,
            sizes: sizes,
            ocrMetadata: CoorditFitLabOCRMetadata(extractedText: rawText, confidence: confidence),
            isSourceConfirmed: false
        )
        return CoorditFitLabOCRResult(
            rawText: rawText,
            confidence: confidence,
            draft: draft,
            didFindTable: true,
            observations: observations
        )
    }

    private func result(
        rawText: String,
        confidence: Double,
        observations: [CoorditFitLabOCRObservation]
    ) -> CoorditFitLabOCRResult {
        var draft = CoorditFitLabDraft(source: .ocr)
        draft.ocrMetadata = CoorditFitLabOCRMetadata(extractedText: rawText, confidence: confidence)
        return CoorditFitLabOCRResult(
            rawText: rawText,
            confidence: confidence,
            draft: draft,
            didFindTable: false,
            observations: observations
        )
    }

    private func expandedTokens(_ observations: [CoorditFitLabOCRObservation]) -> [CoorditFitLabOCRObservation] {
        observations.flatMap { observation in
            let parts = observation.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count > 1 else { return [observation] }
            let tokenWidth = observation.box.width / Double(parts.count)
            return parts.enumerated().map { index, part in
                CoorditFitLabOCRObservation(
                    text: part,
                    confidence: observation.confidence,
                    box: CoorditFitLabOCRBox(
                        CGRect(
                            x: observation.box.x + Double(index) * tokenWidth,
                            y: observation.box.y,
                            width: tokenWidth,
                            height: observation.box.height
                        )
                    )
                )
            }
        }
    }

    private func clusteredRows(_ observations: [CoorditFitLabOCRObservation]) -> [[CoorditFitLabOCRObservation]] {
        let sorted = observations.sorted {
            abs($0.box.midY - $1.box.midY) > 0.018 ? $0.box.midY > $1.box.midY : $0.box.midX < $1.box.midX
        }
        var rows: [[CoorditFitLabOCRObservation]] = []
        for observation in sorted {
            if let index = rows.firstIndex(where: { row in
                guard let center = row.map(\.box.midY).average else { return false }
                let tolerance = max(0.018, row.map(\.box.height).average ?? 0.018)
                return abs(center - observation.box.midY) <= tolerance
            }) {
                rows[index].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows
            .map { $0.sorted { $0.box.midX < $1.box.midX } }
            .sorted { ($0.map(\.box.midY).average ?? 0) > ($1.map(\.box.midY).average ?? 0) }
    }

    private func isHeaderRow(_ row: [CoorditFitLabOCRObservation]) -> Bool {
        row.contains { isSizeAlias($0.text) } && row.compactMap { measurementKey(for: $0.text) }.count >= 2
    }

    private func isSizeAlias(_ text: String) -> Bool {
        ["size", "사이즈", "호수", "치수"].contains(normalized(text))
    }

    private func measurementKey(for text: String) -> CoorditFitLabMeasurementKey? {
        let value = normalized(text)
        let aliases: [(CoorditFitLabMeasurementKey, Set<String>)] = [
            (.shoulderWidth, ["shoulder", "shoulderwidth", "어깨", "어깨너비", "어깨단면"]),
            (.chestWidth, ["chest", "chestwidth", "bust", "가슴", "가슴너비", "가슴단면"]),
            (.totalLength, ["length", "totallength", "bodylength", "총장", "기장"]),
            (.sleeveLength, ["sleeve", "sleevelength", "팔길이", "소매", "소매길이"]),
            (.waistWidth, ["waist", "waistwidth", "허리", "허리너비", "허리단면"]),
            (.hipWidth, ["hip", "hipwidth", "엉덩이", "엉덩이너비", "엉덩이단면"]),
            (.rise, ["rise", "frontrise", "밑위"]),
            (.outseam, ["outseam", "pantslength", "바지길이", "아웃심"]),
        ]
        return aliases.first { $0.1.contains(value) }?.0
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter }
    }

    private func numericValue(_ text: String) -> Double? {
        let decimalNormalized = text.replacingOccurrences(of: ",", with: ".")
        let characterNormalized = decimalNormalized.contains(where: \.isNumber)
            ? decimalNormalized.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "o", with: "0")
            : decimalNormalized
        let filtered = characterNormalized.filter {
            $0.isNumber || $0 == "." || $0 == "-" || $0 == "+"
        }
        guard let value = Double(filtered), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func cleanedLabel(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Collection where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
#endif
