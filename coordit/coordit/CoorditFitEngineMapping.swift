import Foundation

#if os(iOS)
struct CoorditClothingSaveResult: Equatable {
    let clothingItemId: String
    let sizeChart: CoorditClosetSizeChart
}

extension CoorditClosetCategory {
    var backendCategory: String {
        switch self {
        case .top:
            "shirt"
        case .bottom:
            "jeans"
        }
    }

    var resultRoute: CoorditFrameRoute {
        switch self {
        case .top:
            .fitLabResultTop
        case .bottom:
            .fitLabResultBottom
        }
    }

    var fitLabCandidateSizes: [ExternalProductSizeRequest] {
        switch self {
        case .top:
            [
                ExternalProductSizeRequest(sizeLabel: "S", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: 68, shoulderWidth: 44, chestWidth: 52, sleeveLength: 60, waistWidth: nil, hipWidth: nil, rise: nil, outseam: nil),
                ExternalProductSizeRequest(sizeLabel: "M", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: 70, shoulderWidth: 46, chestWidth: 55, sleeveLength: 61, waistWidth: nil, hipWidth: nil, rise: nil, outseam: nil),
                ExternalProductSizeRequest(sizeLabel: "L", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: 72, shoulderWidth: 48, chestWidth: 58, sleeveLength: 62, waistWidth: nil, hipWidth: nil, rise: nil, outseam: nil)
            ]
        case .bottom:
            [
                ExternalProductSizeRequest(sizeLabel: "S", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: nil, shoulderWidth: nil, chestWidth: nil, sleeveLength: nil, waistWidth: 38, hipWidth: 50, rise: 29, outseam: 98),
                ExternalProductSizeRequest(sizeLabel: "M", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: nil, shoulderWidth: nil, chestWidth: nil, sleeveLength: nil, waistWidth: 40, hipWidth: 53, rise: 30, outseam: 101),
                ExternalProductSizeRequest(sizeLabel: "L", rawSizeData: ["source": "ios-fitlab-fallback"], parsingStatus: "mocked", measurementSource: "mock", extractedText: nil, extractionConfidence: 0.35, totalLength: nil, shoulderWidth: nil, chestWidth: nil, sleeveLength: nil, waistWidth: 42, hipWidth: 56, rise: 31, outseam: 104)
            ]
        }
    }
}

extension CoorditClosetDraft {
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var clothingItemRequest: CreateClothingItemRequest {
        var rawProductData = [
            "source": "ios-closet-add",
            "method": method?.rawValue ?? "unknown"
        ]
        if !productLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawProductData["productUrl"] = productLink.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if garmentImageData != nil {
            rawProductData["hasGarmentImage"] = "true"
        }
        if sizeChartImageData != nil {
            rawProductData["hasSizeChartImage"] = "true"
        }

        return CreateClothingItemRequest(
            name: trimmedName.isEmpty ? "새로운 의류" : trimmedName,
            category: exactCategory.rawValue,
            fitType: "regular",
            sizeLabel: nil,
            rawProductData: rawProductData
        )
    }

    var clothingSizeRequest: ClothingSizeRequest {
        switch category {
        case .top:
            ClothingSizeRequest(
                sizeLabel: nil,
                rawMeasurements: ["source": method?.rawValue ?? "unknown"],
                totalLength: measurement3.coorditDoubleValue ?? 70,
                shoulderWidth: measurement1.coorditDoubleValue ?? 45,
                chestWidth: measurement2.coorditDoubleValue ?? 54,
                sleeveLength: measurement4.coorditDoubleValue ?? 61,
                waistWidth: nil,
                hipWidth: nil,
                rise: nil,
                outseam: nil
            )
        case .bottom:
            ClothingSizeRequest(
                sizeLabel: nil,
                rawMeasurements: ["source": method?.rawValue ?? "unknown"],
                totalLength: nil,
                shoulderWidth: nil,
                chestWidth: nil,
                sleeveLength: nil,
                waistWidth: measurement1.coorditDoubleValue ?? 40,
                hipWidth: measurement2.coorditDoubleValue ?? 53,
                rise: measurement3.coorditDoubleValue ?? 30,
                outseam: measurement4.coorditDoubleValue ?? 101
            )
        }
    }

    func referenceRequest(clothingItemId: String) -> CreateReferenceClothingRequest {
        CreateReferenceClothingRequest(
            clothingItemId: clothingItemId,
            nickname: trimmedName.isEmpty ? nil : trimmedName,
            category: exactCategory.rawValue,
            fitType: "regular",
            preferenceScore: 100,
            isActive: true,
            notes: "Created from iOS Closet"
        )
    }
}

extension ClothingSizeRequest {
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

    func withRawMeasurements(_ nextRawMeasurements: [String: String]) -> ClothingSizeRequest {
        ClothingSizeRequest(
            sizeLabel: sizeLabel,
            rawMeasurements: nextRawMeasurements,
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

extension ExternalProductSizeRequest {
    func withExtractionMetadata(
        source: String,
        parsingStatus: String,
        measurementSource: String,
        extractedText: String?,
        extractionConfidence: Double
    ) -> ExternalProductSizeRequest {
        ExternalProductSizeRequest(
            sizeLabel: sizeLabel,
            rawSizeData: rawSizeData.merging(["source": source]) { _, newValue in newValue },
            parsingStatus: parsingStatus,
            measurementSource: measurementSource,
            extractedText: extractedText,
            extractionConfidence: extractionConfidence,
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

private extension String {
    var coorditDoubleValue: Double? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
#endif
