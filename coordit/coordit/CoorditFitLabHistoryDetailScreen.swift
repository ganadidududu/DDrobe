import SwiftUI

#if os(iOS)
struct CoorditFitLabHistoryDetailScreen: View {
    let snapshot: CoorditFitLabHistorySnapshot
    let metrics: CoorditResponsiveMetrics
    let delete: () async -> Void
    let onRouteChange: (CoorditFrameRoute) -> Void
    @State private var isDeleting = false

    var body: some View {
        let variant = CoorditFitLabResultVariant.history(snapshot.garmentKind)
        let scoreCard = CoorditFitLabScoreCard(
            variant: variant,
            recommendation: snapshot.recommendation,
            report: snapshot.report,
            metrics: metrics
        )
        ScrollView {
            VStack(spacing: metrics.value(15)) {
                VStack(alignment: .leading, spacing: metrics.value(7)) {
                    Text(snapshot.product.name)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(19), relativeTo: .title3))
                        .foregroundStyle(Color.black)
                        .accessibilityIdentifier("fitlab-history-detail-product")
                    Text("\(snapshot.category.rawValue) · \(snapshot.recommendation.recommendedSize) · \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .body))
                        .foregroundStyle(Color.black.opacity(0.62))
                    Text("입력: \(sourceLabel) · 기준 옷 \(snapshot.references.count)개")
                        .font(CoorditTypography.gmarketLight(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(Color.black.opacity(0.55))
                    #if DEBUG
                    Text(snapshot.analysisID)
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .accessibilityIdentifier("fitlab-history-detail-analysis")
                    #endif
                }
                .padding(metrics.value(15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CoorditFitLabPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))

                HStack(alignment: .top, spacing: metrics.value(9)) {
                    CoorditFitLabMannequinPanel(
                        assetName: variant.assetName,
                        metrics: metrics,
                        measurements: scoreCard.measurements
                    )
                    .frame(width: metrics.value(126), height: metrics.value(218))
                    scoreCard
                }

                CoorditFitLabMeasurementRows(measurements: scoreCard.measurements, metrics: metrics)
                CoorditFitLabReportCard(report: snapshot.report, fallbackMessage: nil, metrics: metrics)

                Button(isDeleting ? "삭제 중..." : "이 히스토리 삭제") {
                    guard !isDeleting else { return }
                    isDeleting = true
                    Task { await delete() }
                }
                .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: metrics.value(44))
                .background(CoorditFitLabPalette.empty)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                .accessibilityIdentifier("fitlab-history-delete")
            }
            .padding(.horizontal, metrics.value(24))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .accessibilityIdentifier("fitlab-history-detail")
    }

    private var sourceLabel: String {
        switch snapshot.originalSource {
        case .manual: "수동"
        case .ocr: "OCR"
        case .url: "링크"
        }
    }
}

enum CoorditFitLabResultVariant: Equatable {
    case top
    case bottom
    case history(CoorditFitLabGarmentKind)

    var assetName: String {
        switch self {
        case .top, .history(.upper):
            CoorditAssetNames.fitUpper
        case .bottom, .history(.lower):
            CoorditAssetNames.fitLower
        }
    }

    var scoreBasis: String {
        switch self {
        case .history:
            "과거 기준치 기준"
        case .top, .bottom:
            "현재 베스트 스코어 기준"
        }
    }

    var measurementKeys: [CoorditFitLabMeasurementKey] {
        switch self {
        case .top, .history(.upper):
            [.shoulderWidth, .chestWidth, .totalLength, .sleeveLength]
        case .bottom, .history(.lower):
            [.waistWidth, .hipWidth, .rise, .outseam]
        }
    }

    func label(for key: CoorditFitLabMeasurementKey) -> String {
        switch key {
        case .shoulderWidth: "어깨"
        case .chestWidth: "가슴"
        case .totalLength: "총장"
        case .sleeveLength: "소매"
        case .waistWidth: "허리"
        case .hipWidth: "힙"
        case .rise: "밑위"
        case .outseam: "총장"
        }
    }
}
#endif
