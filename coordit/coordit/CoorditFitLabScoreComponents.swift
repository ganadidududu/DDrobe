import SwiftUI

#if os(iOS)
struct CoorditFitLabResultMeasurement: Identifiable {
    enum Direction {
        case tight
        case similar
        case loose

        var label: String {
            switch self {
            case .tight: "타이트"
            case .similar: "비슷"
            case .loose: "여유"
            }
        }

        var glyph: String {
            switch self {
            case .tight: "−"
            case .similar: "≈"
            case .loose: "+"
            }
        }

        var color: Color {
            switch self {
            case .tight: CoorditDesignTokens.ColorToken.red
            case .similar: CoorditDesignTokens.ColorToken.green
            case .loose: CoorditDesignTokens.ColorToken.blue
            }
        }
    }

    let key: CoorditFitLabMeasurementKey
    let title: String
    let comparison: CoorditFitLabReportResponse.ChartData.Comparison?

    var id: String { key.rawValue }

    var direction: Direction? {
        guard let comparison, comparison.diff.isFinite else { return nil }
        switch comparison.status?.lowercased() {
        case "tight", "too_tight", "small", "slightly_small", "too_small", "타이트":
            return .tight
        case "good", "very_similar", "similar", "same", "비슷":
            return .similar
        case "loose", "too_loose", "large", "slightly_large", "too_large", "여유":
            return .loose
        default:
            if abs(comparison.diff) <= similarTolerance { return .similar }
            return comparison.diff < 0 ? .tight : .loose
        }
    }

    private var similarTolerance: Double {
        switch key {
        case .shoulderWidth, .waistWidth, .rise:
            0.5
        case .chestWidth, .sleeveLength, .hipWidth:
            0.75
        case .totalLength, .outseam:
            1
        }
    }

    var accessibilityValue: String {
        guard let comparison,
              comparison.ideal.isFinite,
              comparison.product.isFinite,
              comparison.diff.isFinite,
              let direction
        else { return "비교 데이터 없음" }
        return "베스트 \(Self.number(comparison.ideal)) cm | 상품 \(Self.number(comparison.product)) cm | 차이 \(Self.signed(comparison.diff)) cm | \(direction.label)"
    }

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value == value.rounded() { return String(Int(value)) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func signed(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if abs(value) < 0.001 { return "0" }
        return "\(value > 0 ? "+" : "")\(number(value))"
    }
}

struct CoorditFitLabScoreCard: View {
    let variant: CoorditFitLabResultVariant
    let recommendation: CoorditFitLabRecommendationResponse?
    let report: CoorditFitLabReportResponse?
    let metrics: CoorditResponsiveMetrics

    init(
        variant: CoorditFitLabResultVariant,
        recommendation: CoorditFitLabRecommendationResponse? = nil,
        report: CoorditFitLabReportResponse? = nil,
        metrics: CoorditResponsiveMetrics
    ) {
        self.variant = variant
        self.recommendation = recommendation
        self.report = report
        self.metrics = metrics
    }

    var measurements: [CoorditFitLabResultMeasurement] {
        variant.measurementKeys.map { key in
            CoorditFitLabResultMeasurement(
                key: key,
                title: variant.label(for: key),
                comparison: report?.chartData.idealVsProduct.first { $0.measurement == key }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(10)) {
            Text(variant.scoreBasis)
                .font(CoorditTypography.mona12(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(Color.black.opacity(0.64))
            Text("FIT SCORE")
                .font(CoorditTypography.climate2019(size: metrics.value(19), relativeTo: .headline))
                .tracking(metrics.value(0.7))
                .foregroundStyle(Color.black)

            HStack(alignment: .firstTextBaseline, spacing: metrics.value(7)) {
                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text("추천 사이즈")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                    Text(recommendation?.recommendedSize ?? "-")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(20), relativeTo: .title3))
                        .accessibilityIdentifier("fitlab-recommended-size")
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: metrics.value(2)) {
                    Text("총점")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                    Text(scoreText)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(20), relativeTo: .title3))
                        .accessibilityIdentifier("fitlab-total-score")
                }
            }
            .foregroundStyle(Color.black)
        }
        .padding(metrics.value(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(7))
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private var scoreText: String {
        guard let score = recommendation?.fitScore, score.isFinite else { return "-" }
        return CoorditFitLabResultMeasurement.number(score)
    }
}

struct CoorditFitLabMeasurementRows: View {
    let measurements: [CoorditFitLabResultMeasurement]
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        VStack(spacing: metrics.value(7)) {
            ForEach(measurements) { measurement in
                HStack(spacing: metrics.value(8)) {
                    Text(measurement.title)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .body))
                        .frame(width: metrics.value(42), alignment: .leading)
                    if let comparison = measurement.comparison,
                       comparison.ideal.isFinite,
                       comparison.product.isFinite,
                       comparison.diff.isFinite,
                       let direction = measurement.direction {
                        Text("베스트 \(CoorditFitLabResultMeasurement.number(comparison.ideal))")
                        Text("상품 \(CoorditFitLabResultMeasurement.number(comparison.product))")
                        Spacer(minLength: 0)
                        Text("\(CoorditFitLabResultMeasurement.signed(comparison.diff)) cm · \(direction.label)")
                            .fontWeight(.bold)
                    } else {
                        Text("비교 데이터 없음")
                        Spacer(minLength: 0)
                    }
                }
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(Color.black)
                .padding(.horizontal, metrics.value(12))
                .padding(.vertical, metrics.value(10))
                .frame(maxWidth: .infinity, minHeight: metrics.value(44), alignment: .leading)
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(measurement.title)
                .accessibilityValue(measurement.accessibilityValue)
                .accessibilityIdentifier("fitlab-measurement-\(measurement.key.rawValue)")
            }
        }
    }
}

struct CoorditFitLabSizeScoreChart: View {
    let report: CoorditFitLabReportResponse?
    let recommendation: CoorditFitLabRecommendationResponse?
    let metrics: CoorditResponsiveMetrics

    private var rows: [CoorditFitLabReportResponse.ChartData.SizeScore] {
        if let scores = report?.chartData.sizeScoreRanking, !scores.isEmpty {
            return scores
        }
        guard let recommendation else { return [] }
        return [
            .init(
                sizeLabel: recommendation.recommendedSize,
                fitScore: recommendation.fitScore,
                fitLabel: recommendation.fitLabel,
                weightedFitDistance: 0,
                recommendationConfidence: recommendation.recommendationConfidence
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(12)) {
            VStack(alignment: .leading, spacing: metrics.value(3)) {
                Text("SIZE SCORE COMPARISON")
                    .font(CoorditTypography.mona12(size: metrics.value(16), relativeTo: .headline))
                Text("모든 사이즈를 같은 기준으로 비교한 결과예요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditFitLabPalette.muted)
            }

            ForEach(rows, id: \.sizeLabel) { row in
                let isRecommended = row.sizeLabel == recommendation?.recommendedSize
                HStack(spacing: metrics.value(8)) {
                    Text(row.sizeLabel)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .body))
                        .foregroundStyle(isRecommended ? Color.white : CoorditFitLabPalette.ink)
                        .frame(width: metrics.value(38), height: metrics.value(28))
                        .background(isRecommended ? CoorditFitLabPalette.ink : CoorditFitLabPalette.field)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CoorditFitLabPalette.field)
                            Capsule()
                                .fill(
                                    isRecommended
                                        ? CoorditFitLabPalette.ink
                                        : CoorditDesignTokens.ColorToken.blue.opacity(0.42)
                                )
                                .frame(width: proxy.size.width * normalized(row.fitScore))
                        }
                    }
                    .frame(height: metrics.value(11))

                    Text("\(CoorditFitLabResultMeasurement.number(row.fitScore))점")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .caption))
                        .frame(width: metrics.value(42), alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(row.sizeLabel) 사이즈 \(CoorditFitLabResultMeasurement.number(row.fitScore))점\(isRecommended ? ", 추천" : "")"
                )
                .accessibilityIdentifier("fitlab-size-score-\(row.sizeLabel)")
            }
        }
        .foregroundStyle(Color.black)
        .padding(metrics.value(16))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fitlab-size-score-chart")
    }

    private func normalized(_ score: Double) -> CGFloat {
        guard score.isFinite else { return 0 }
        return CGFloat(min(max(score, 0), 100) / 100)
    }
}

struct CoorditFitLabDifferenceChart: View {
    let measurements: [CoorditFitLabResultMeasurement]
    let metrics: CoorditResponsiveMetrics

    private var maximumDifference: Double {
        max(measurements.compactMap(\.comparison?.diff).map(abs).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(13)) {
            VStack(alignment: .leading, spacing: metrics.value(3)) {
                Text("BEST FIT DIFFERENCE")
                    .font(CoorditTypography.mona12(size: metrics.value(16), relativeTo: .headline))
                Text("0을 기준으로 왼쪽은 타이트, 오른쪽은 여유예요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditFitLabPalette.muted)
            }

            HStack {
                Text("− 타이트")
                    .foregroundStyle(CoorditDesignTokens.ColorToken.red)
                Spacer()
                Text("0")
                    .foregroundStyle(CoorditFitLabPalette.muted)
                Spacer()
                Text("+ 여유")
                    .foregroundStyle(CoorditDesignTokens.ColorToken.blue)
            }
            .font(CoorditTypography.gmarketBold(size: metrics.value(9), relativeTo: .caption2))

            ForEach(measurements) { measurement in
                if let comparison = measurement.comparison,
                   comparison.diff.isFinite,
                   let direction = measurement.direction {
                    VStack(spacing: metrics.value(6)) {
                        HStack(alignment: .firstTextBaseline, spacing: metrics.value(6)) {
                            Text(measurement.title)
                                .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .body))
                            Text("기준 \(CoorditFitLabResultMeasurement.number(comparison.ideal)) · 상품 \(CoorditFitLabResultMeasurement.number(comparison.product))")
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                                .foregroundStyle(CoorditFitLabPalette.muted)
                            Spacer(minLength: 0)
                            Text("\(CoorditFitLabResultMeasurement.signed(comparison.diff))cm")
                                .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .body))
                                .foregroundStyle(direction.color)
                        }

                        GeometryReader { proxy in
                            let centerX = proxy.size.width / 2
                            let barWidth = centerX * CGFloat(abs(comparison.diff) / maximumDifference)
                            let isZero = abs(comparison.diff) < 0.001
                            let renderedBarWidth = isZero ? metrics.value(4) : barWidth
                            let signedPosition = comparison.diff < 0
                                ? centerX - barWidth / 2
                                : comparison.diff > 0
                                    ? centerX + barWidth / 2
                                    : centerX
                            ZStack {
                                Capsule().fill(CoorditFitLabPalette.field)
                                Rectangle()
                                    .fill(CoorditFitLabPalette.muted.opacity(0.55))
                                    .frame(width: 1, height: metrics.value(18))
                                    .position(x: centerX, y: metrics.value(9))
                                Capsule()
                                    .fill(direction.color)
                                    .frame(width: renderedBarWidth, height: metrics.value(9))
                                    .position(x: signedPosition, y: metrics.value(9))
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(measurement.title) 차이 방향")
                                    .accessibilityValue(
                                        comparison.diff < 0
                                            ? "negative"
                                            : comparison.diff > 0
                                                ? "positive"
                                                : "zero"
                                    )
                                    .accessibilityIdentifier("fitlab-difference-bar-\(measurement.key.rawValue)")
                            }
                        }
                        .frame(height: metrics.value(18))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(measurement.title)
                    .accessibilityValue(measurement.accessibilityValue)
                    .accessibilityIdentifier("fitlab-measurement-\(measurement.key.rawValue)")
                } else {
                    HStack {
                        Text(measurement.title)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .body))
                        Spacer()
                        Text("비교 데이터 없음")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                            .foregroundStyle(CoorditFitLabPalette.muted)
                    }
                    .frame(minHeight: metrics.value(32))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(measurement.title)
                    .accessibilityValue("비교 데이터 없음")
                    .accessibilityIdentifier("fitlab-measurement-\(measurement.key.rawValue)")
                }
            }
        }
        .foregroundStyle(Color.black)
        .padding(metrics.value(16))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fitlab-difference-chart")
    }
}
#endif
