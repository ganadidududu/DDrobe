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

    static func score(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    static func signed(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if abs(value) < 0.001 { return "0" }
        return "\(value > 0 ? "+" : "")\(number(value))"
    }
}

struct CoorditFitLabSizeOption: Identifiable {
    let sizeLabel: String
    let fitScore: Double?
    let isRecommended: Bool
    let measurements: [CoorditFitLabResultMeasurement]

    var id: String { sizeLabel }

    static func makeOptions(
        variant: CoorditFitLabResultVariant,
        recommendation: CoorditFitLabRecommendationResponse,
        report: CoorditFitLabReportResponse?,
        sizeDrafts: [CoorditFitLabSizeDraft]
    ) -> [CoorditFitLabSizeOption] {
        let reportScoreRows = report?.chartData.sizeScoreRanking ?? []
        let reportScoresBySize = scoresBySize(reportScoreRows)
        let recommendationScoresBySize = scoresBySize(recommendation.allSizeScores)
        let nonEmptyDrafts = sizeDrafts.filter {
            !CoorditFitLabDraftValidation.normalizedSizeLabel($0.label).isEmpty
        }
        var referenceComparisons = fallbackComparisons(
            variant: variant,
            recommendation: recommendation,
            sizeDrafts: nonEmptyDrafts
        )
        for comparison in report?.chartData.idealVsProduct ?? [] {
            referenceComparisons[comparison.measurement] = comparison
        }

        let draftOptions = nonEmptyDrafts.map { draft in
            let normalizedLabel = CoorditFitLabDraftValidation.normalizedSizeLabel(draft.label)
            let isRecommended = normalizedLabel
                == CoorditFitLabDraftValidation.normalizedSizeLabel(recommendation.recommendedSize)
            let score = reportScoresBySize[normalizedLabel]?.fitScore
                ?? recommendationScoresBySize[normalizedLabel]?.fitScore
                ?? (isRecommended ? recommendation.fitScore : nil)
            let measurements = isRecommended
                ? authoritativeMeasurements(variant: variant, comparisons: referenceComparisons)
                : measurements(variant: variant, draft: draft, comparisons: referenceComparisons)
            return CoorditFitLabSizeOption(
                sizeLabel: draft.label,
                fitScore: score,
                isRecommended: isRecommended,
                measurements: measurements
            )
        }

        if !draftOptions.isEmpty {
            return draftOptions
        }

        let scoreRows = mergedScoreRows(
            reportRows: reportScoreRows,
            recommendationRows: recommendation.allSizeScores
        )
        if !scoreRows.isEmpty {
            return scoreRows.map { row in
                let isRecommended = CoorditFitLabDraftValidation.normalizedSizeLabel(row.sizeLabel)
                    == CoorditFitLabDraftValidation.normalizedSizeLabel(recommendation.recommendedSize)
                return CoorditFitLabSizeOption(
                    sizeLabel: row.sizeLabel,
                    fitScore: row.fitScore,
                    isRecommended: isRecommended,
                    measurements: isRecommended
                        ? authoritativeMeasurements(variant: variant, comparisons: referenceComparisons)
                        : []
                )
            }
        }

        return [
            CoorditFitLabSizeOption(
                sizeLabel: recommendation.recommendedSize,
                fitScore: recommendation.fitScore,
                isRecommended: true,
                measurements: authoritativeMeasurements(variant: variant, comparisons: referenceComparisons)
            )
        ]
    }

    private static func scoresBySize(
        _ rows: [CoorditFitLabReportResponse.ChartData.SizeScore]
    ) -> [String: CoorditFitLabReportResponse.ChartData.SizeScore] {
        rows.reduce(into: [:]) { scores, row in
            let normalizedLabel = CoorditFitLabDraftValidation.normalizedSizeLabel(row.sizeLabel)
            guard !normalizedLabel.isEmpty else { return }
            scores[normalizedLabel] = row
        }
    }

    private static func mergedScoreRows(
        reportRows: [CoorditFitLabReportResponse.ChartData.SizeScore],
        recommendationRows: [CoorditFitLabReportResponse.ChartData.SizeScore]
    ) -> [CoorditFitLabReportResponse.ChartData.SizeScore] {
        let reportScoresBySize = scoresBySize(reportRows)
        let recommendationOnlyRows = recommendationRows.filter { row in
            let normalizedLabel = CoorditFitLabDraftValidation.normalizedSizeLabel(row.sizeLabel)
            return reportScoresBySize[normalizedLabel] == nil
        }
        return reportRows + recommendationOnlyRows
    }

    private static func fallbackComparisons(
        variant: CoorditFitLabResultVariant,
        recommendation: CoorditFitLabRecommendationResponse,
        sizeDrafts: [CoorditFitLabSizeDraft]
    ) -> [CoorditFitLabMeasurementKey: CoorditFitLabReportResponse.ChartData.Comparison] {
        let recommendedSize = CoorditFitLabDraftValidation.normalizedSizeLabel(recommendation.recommendedSize)
        guard let recommendedDraft = sizeDrafts.first(where: {
            CoorditFitLabDraftValidation.normalizedSizeLabel($0.label) == recommendedSize
        }) else {
            return [:]
        }

        return recommendation.diff.reduce(into: [:]) { comparisons, entry in
            let (key, difference) = entry
            guard variant.measurementKeys.contains(key),
                  difference.isFinite,
                  let product = recommendedDraft.measurements[key],
                  product.isFinite else {
                return
            }

            let ideal = product - difference
            guard ideal.isFinite else { return }
            comparisons[key] = .init(
                measurement: key,
                label: variant.label(for: key),
                ideal: ideal,
                product: product,
                diff: difference,
                status: nil
            )
        }
    }

    private static func authoritativeMeasurements(
        variant: CoorditFitLabResultVariant,
        comparisons: [CoorditFitLabMeasurementKey: CoorditFitLabReportResponse.ChartData.Comparison]
    ) -> [CoorditFitLabResultMeasurement] {
        variant.measurementKeys.map { key in
            CoorditFitLabResultMeasurement(
                key: key,
                title: variant.label(for: key),
                comparison: comparisons[key]
            )
        }
    }

    private static func measurements(
        variant: CoorditFitLabResultVariant,
        draft: CoorditFitLabSizeDraft,
        comparisons: [CoorditFitLabMeasurementKey: CoorditFitLabReportResponse.ChartData.Comparison]
    ) -> [CoorditFitLabResultMeasurement] {
        variant.measurementKeys.map { key in
            let comparison = comparisons[key].flatMap { reference -> CoorditFitLabReportResponse.ChartData.Comparison? in
                guard let product = draft.measurements[key], product.isFinite else { return nil }
                return .init(
                    measurement: key,
                    label: reference.label,
                    ideal: reference.ideal,
                    product: product,
                    diff: product - reference.ideal,
                    status: nil
                )
            }
            return CoorditFitLabResultMeasurement(
                key: key,
                title: variant.label(for: key),
                comparison: comparison
            )
        }
    }
}

struct CoorditFitLabScoreCard: View {
    let variant: CoorditFitLabResultVariant
    let selectedSize: CoorditFitLabSizeOption?
    let metrics: CoorditResponsiveMetrics

    init(
        variant: CoorditFitLabResultVariant,
        selectedSize: CoorditFitLabSizeOption? = nil,
        metrics: CoorditResponsiveMetrics
    ) {
        self.variant = variant
        self.selectedSize = selectedSize
        self.metrics = metrics
    }

    init(
        variant: CoorditFitLabResultVariant,
        recommendation: CoorditFitLabRecommendationResponse? = nil,
        report: CoorditFitLabReportResponse? = nil,
        metrics: CoorditResponsiveMetrics
    ) {
        let selectedSize = recommendation.flatMap {
            let options = CoorditFitLabSizeOption.makeOptions(
                variant: variant,
                recommendation: $0,
                report: report,
                sizeDrafts: []
            )
            return options.first { $0.isRecommended } ?? options.first
        }
        self.init(variant: variant, selectedSize: selectedSize, metrics: metrics)
    }

    var measurements: [CoorditFitLabResultMeasurement] {
        selectedSize?.measurements ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(10)) {
            Text(selectedSize?.isRecommended == false ? "선택 사이즈 비교 기준" : variant.scoreBasis)
                .font(CoorditTypography.mona12(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(Color.black.opacity(0.64))
            Text("FIT SCORE")
                .font(CoorditTypography.climate2019(size: metrics.value(19), relativeTo: .headline))
                .tracking(metrics.value(0.7))
                .foregroundStyle(Color.black)

            HStack(alignment: .firstTextBaseline, spacing: metrics.value(7)) {
                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text(selectedSize?.isRecommended == false ? "선택한 사이즈" : "추천 사이즈")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9), relativeTo: .caption))
                    Text(selectedSize?.sizeLabel ?? "-")
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
        guard let score = selectedSize?.fitScore, score.isFinite else { return "-" }
        return CoorditFitLabResultMeasurement.score(score)
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
    let options: [CoorditFitLabSizeOption]
    @Binding var selectedSizeLabel: String?
    private let isInteractive: Bool
    let metrics: CoorditResponsiveMetrics

    init(
        options: [CoorditFitLabSizeOption],
        selectedSizeLabel: Binding<String?>,
        isInteractive: Bool = true,
        metrics: CoorditResponsiveMetrics
    ) {
        self.options = options
        _selectedSizeLabel = selectedSizeLabel
        self.isInteractive = isInteractive
        self.metrics = metrics
    }

    init(
        report: CoorditFitLabReportResponse?,
        recommendation: CoorditFitLabRecommendationResponse?,
        metrics: CoorditResponsiveMetrics
    ) {
        self.options = recommendation.map {
            CoorditFitLabSizeOption.makeOptions(
                variant: .top,
                recommendation: $0,
                report: report,
                sizeDrafts: []
            )
        } ?? []
        _selectedSizeLabel = .constant(nil)
        isInteractive = false
        self.metrics = metrics
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

            ForEach(options) { option in
                let isSelected = selectedSizeLabel == option.sizeLabel
                    || (selectedSizeLabel == nil && option.isRecommended)
                Button {
                    selectedSizeLabel = option.sizeLabel
                } label: {
                    HStack(spacing: metrics.value(8)) {
                        Text(option.sizeLabel)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .body))
                            .foregroundStyle(isSelected ? Color.white : CoorditFitLabPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)
                            .frame(width: metrics.value(58), height: metrics.value(28), alignment: .leading)
                            .background(isSelected ? CoorditFitLabPalette.ink : CoorditFitLabPalette.field)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(CoorditFitLabPalette.field)
                                Capsule()
                                    .fill(isSelected ? CoorditFitLabPalette.ink : CoorditDesignTokens.ColorToken.blue.opacity(0.42))
                                    .frame(width: proxy.size.width * normalized(option.fitScore))
                            }
                        }
                        .frame(height: metrics.value(11))

                        Text(scoreText(option.fitScore))
                            .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .caption))
                            .frame(width: metrics.value(48), alignment: .trailing)

                        if option.isRecommended {
                            Text("추천")
                                .font(CoorditTypography.gmarketBold(size: metrics.value(8), relativeTo: .caption2))
                                .foregroundStyle(CoorditDesignTokens.ColorToken.green)
                        }
                    }
                }
                .buttonStyle(.plain)
                .coorditPressFeedback()
                .disabled(!isInteractive)
                .frame(maxWidth: .infinity, minHeight: metrics.value(44))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(option.sizeLabel) 사이즈 \(scoreText(option.fitScore))\(option.isRecommended ? ", 추천" : "")"
                )
                .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
                .accessibilityIdentifier("fitlab-size-score-\(option.sizeLabel)")
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

    private func normalized(_ score: Double?) -> CGFloat {
        guard let score, score.isFinite else { return 0 }
        return CGFloat(min(max(score, 0), 100) / 100)
    }

    private func scoreText(_ score: Double?) -> String {
        guard let score else { return "점수 없음" }
        return "\(CoorditFitLabResultMeasurement.score(score))점"
    }
}

private struct CoorditFitLabYarnStyle {
    static let travelFraction: CGFloat = 0.44
    static let frameHeight: CGFloat = 38
    static let ballRadius: CGFloat = 11
    static let ballRevealStartScale: CGFloat = 0.88
    static let ballRevealGrowthScale: CGFloat = 0.12
    static let animationDuration: TimeInterval = 0.42
    static let animationFrameInterval: TimeInterval = 1.0 / 30.0
    static let rotationMultiplier: CGFloat = 0.72

    static let differenceThreshold: Double = 0.001
    static let minimumTravelDistance: CGFloat = 1

    static let markerDotRadius: CGFloat = 2.4
    static let markerOpacity: Double = 1

    static let trailHaloLineWidth: CGFloat = 3.2
    static let trailHaloOpacity: Double = 0.13
    static let trailCoreLineWidth: CGFloat = 1.7
    static let trailCoreOpacity: Double = 0.88

    static let ballImageScale: CGFloat = 1.38
    static let ballAssetBodyCenterXFraction: CGFloat = 23.625 / 54
    static let ballAssetBodyCenterYFraction: CGFloat = 27 / 54
    static let ballAssetBodyClipRadiusFraction: CGFloat = 16.8 / 54

    static let zeroCoilRadius: CGFloat = 8
    static let zeroCoilLineWidth: CGFloat = 1.6
    static let zeroCoilOpacity: Double = 0.82
    static let zeroCoilStartXScale: CGFloat = -1
    static let zeroCoilStartYScale: CGFloat = 0.18
    static let zeroCoilEndOneXScale: CGFloat = 0.9
    static let zeroCoilEndOneYScale: CGFloat = -0.12
    static let zeroCoilControlOneXScale: CGFloat = -0.36
    static let zeroCoilControlOneYScale: CGFloat = -0.92
    static let zeroCoilControlTwoXScale: CGFloat = 0.8
    static let zeroCoilControlTwoYScale: CGFloat = -0.84
    static let zeroCoilEndTwoXScale: CGFloat = -0.44
    static let zeroCoilEndTwoYScale: CGFloat = 0.55
    static let zeroCoilControlThreeXScale: CGFloat = 0.58
    static let zeroCoilControlThreeYScale: CGFloat = 0.76
    static let zeroCoilControlFourXScale: CGFloat = -0.86
    static let zeroCoilControlFourYScale: CGFloat = 0.92

    static let pathFirstFraction: CGFloat = 0.22
    static let pathSecondFraction: CGFloat = 0.54
    static let pathThirdFraction: CGFloat = 0.82
    static let pathControlOneFraction: CGFloat = 0.06
    static let pathControlTwoFraction: CGFloat = 0.14
    static let pathControlThreeFraction: CGFloat = 0.34
    static let pathControlFourFraction: CGFloat = 0.45
    static let pathControlFiveFraction: CGFloat = 0.65
    static let pathControlSixFraction: CGFloat = 0.74
    static let pathControlSevenFraction: CGFloat = 0.9
    static let pathControlEightFraction: CGFloat = 0.03
    static let pathSecondControlOneScale: CGFloat = 1.8
    static let pathSecondControlTwoScale: CGFloat = 1.5
    static let pathSecondControlThreeScale: CGFloat = 0.8
    static let pathSecondControlFourScale: CGFloat = 0.55
    static let pathFinalControlOneScale: CGFloat = 0.4
    static let pathFinalControlTwoScale: CGFloat = 0.3

    static func bendProfile(
        for key: CoorditFitLabMeasurementKey
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch key {
        case .shoulderWidth: (1.5, -2.8, 2.2, 1.2)
        case .chestWidth: (-2.6, 2.4, -1.3, 2.1)
        case .totalLength: (2.4, 1.1, -2.2, 1.6)
        case .sleeveLength: (-1.7, -2.9, 2.7, 1.1)
        case .waistWidth: (2.1, -1.4, 2.8, 1.4)
        case .hipWidth: (-2.2, 2.6, 1.1, 1.8)
        case .rise: (1.2, -2.4, 2.1, 1.3)
        case .outseam: (-2.7, 1.4, -1.9, 2.2)
        }
    }
}

struct CoorditFitLabYarnTrail: View {
    let measurement: CoorditFitLabResultMeasurement
    let difference: Double
    let maximumDifference: Double
    let direction: CoorditFitLabResultMeasurement.Direction
    let metrics: CoorditResponsiveMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()
    @State private var animationSettled = false

    private var endpoint: String {
        if difference < -CoorditFitLabYarnStyle.differenceThreshold { return "left" }
        if difference > CoorditFitLabYarnStyle.differenceThreshold { return "right" }
        return "center"
    }

    private var colorName: String {
        switch direction {
        case .tight: return "red"
        case .similar: return "green"
        case .loose: return "blue"
        }
    }

    private var yarnColor: Color {
        direction.color
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: CoorditFitLabYarnStyle.animationFrameInterval,
                paused: reduceMotion || animationSettled
            )
        ) { timeline in
            Canvas { context, size in
                let centerX = size.width / 2
                let center = CGPoint(x: centerX, y: size.height / 2)
                let normalizedDifference = min(
                    abs(difference) / max(maximumDifference, CoorditFitLabYarnStyle.differenceThreshold),
                    1
                )
                let travel = size.width * CoorditFitLabYarnStyle.travelFraction * CGFloat(normalizedDifference)
                let signedTravel = difference < 0 ? -travel : difference > 0 ? travel : 0
                let ballRadius = metrics.value(CoorditFitLabYarnStyle.ballRadius)
                let progress = revealProgress(at: Date())
                let endpointX = centerX + signedTravel * progress
                let trail = path(
                    height: size.height,
                    centerX: centerX,
                    endpointX: endpointX
                )

                context.stroke(
                    trail,
                    with: .color(yarnColor.opacity(CoorditFitLabYarnStyle.trailHaloOpacity)),
                    style: StrokeStyle(
                        lineWidth: metrics.value(CoorditFitLabYarnStyle.trailHaloLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                context.stroke(
                    trail,
                    with: .color(yarnColor.opacity(CoorditFitLabYarnStyle.trailCoreOpacity)),
                    style: StrokeStyle(
                        lineWidth: metrics.value(CoorditFitLabYarnStyle.trailCoreLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if abs(difference) < CoorditFitLabYarnStyle.differenceThreshold {
                    let coil = zeroCoil(
                        center: center,
                        radius: metrics.value(CoorditFitLabYarnStyle.zeroCoilRadius)
                    )
                    context.stroke(
                        coil,
                        with: .color(yarnColor.opacity(CoorditFitLabYarnStyle.zeroCoilOpacity)),
                        style: StrokeStyle(
                            lineWidth: metrics.value(CoorditFitLabYarnStyle.zeroCoilLineWidth),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                let markerRadius = metrics.value(CoorditFitLabYarnStyle.markerDotRadius)
                let marker = Path(
                    ellipseIn: CGRect(
                        x: centerX - markerRadius,
                        y: center.y - markerRadius,
                        width: markerRadius * 2,
                        height: markerRadius * 2
                    )
                )
                context.fill(
                    marker,
                    with: .color(yarnColor.opacity(CoorditFitLabYarnStyle.markerOpacity))
                )

                let rotationAngle = signedTravel
                    / max(ballRadius, metrics.value(CoorditFitLabYarnStyle.minimumTravelDistance))
                    * CoorditFitLabYarnStyle.rotationMultiplier
                    * progress
                drawYarnBall(
                    in: &context,
                    center: CGPoint(x: endpointX, y: center.y),
                    radius: ballRadius * (
                        CoorditFitLabYarnStyle.ballRevealStartScale
                            + CoorditFitLabYarnStyle.ballRevealGrowthScale * progress
                    ),
                    rotationAngle: rotationAngle
                )
            }
        }
        .frame(height: metrics.value(CoorditFitLabYarnStyle.frameHeight))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measurement.title) 차이 실타래")
        .accessibilityValue("\(endpoint)|\(colorName)")
        .accessibilityIdentifier("fitlab-yarn-trail-\(measurement.key.rawValue)")
        .onAppear { animateArrival() }
        .onChange(of: difference) { _, _ in animateArrival() }
    }

    private func drawYarnBall(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        rotationAngle: CGFloat
    ) {
        let imageDiameter = radius * 2 * CoorditFitLabYarnStyle.ballImageScale
        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .radians(Double(rotationAngle)))
            let imageRect = CGRect(
                x: -imageDiameter * CoorditFitLabYarnStyle.ballAssetBodyCenterXFraction,
                y: -imageDiameter * CoorditFitLabYarnStyle.ballAssetBodyCenterYFraction,
                width: imageDiameter,
                height: imageDiameter
            )
            let bodyRadius = imageDiameter * CoorditFitLabYarnStyle.ballAssetBodyClipRadiusFraction
            layer.clip(
                to: Path(
                    ellipseIn: CGRect(
                        x: -bodyRadius,
                        y: -bodyRadius,
                        width: bodyRadius * 2,
                        height: bodyRadius * 2
                    )
                )
            )
            layer.draw(
                Image(CoorditAssetNames.yarn),
                in: imageRect
            )
        }
    }

    private func animateArrival() {
        let start = Date()
        animationStart = start
        animationSettled = reduceMotion

        guard !reduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoorditFitLabYarnStyle.animationDuration) {
            guard animationStart == start else { return }
            animationSettled = true
        }
    }

    private func revealProgress(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let elapsed = date.timeIntervalSince(animationStart)
        return CGFloat(
            min(
                max(elapsed / CoorditFitLabYarnStyle.animationDuration, 0),
                1
            )
        )
    }

    private func path(
        height: CGFloat,
        centerX: CGFloat,
        endpointX: CGFloat
    ) -> Path {
        let travel = endpointX - centerX
        let sign: CGFloat = travel < 0 ? -1 : 1
        let distance = abs(travel)
        let y = height / 2
        let profile = bendProfile
        let first = CGPoint(
            x: centerX + travel * CoorditFitLabYarnStyle.pathFirstFraction,
            y: y + metrics.value(profile.0)
        )
        let second = CGPoint(
            x: centerX + travel * CoorditFitLabYarnStyle.pathSecondFraction,
            y: y + metrics.value(profile.1)
        )
        let third = CGPoint(
            x: centerX + travel * CoorditFitLabYarnStyle.pathThirdFraction,
            y: y + metrics.value(profile.2)
        )
        let end = CGPoint(x: endpointX, y: y)

        var path = Path()
        path.move(to: CGPoint(x: centerX, y: y))
        guard distance > metrics.value(CoorditFitLabYarnStyle.minimumTravelDistance) else {
            path.addLine(to: CGPoint(x: centerX + sign * metrics.value(2), y: y))
            return path
        }
        path.addCurve(
            to: first,
            control1: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlOneFraction,
                y: y - metrics.value(profile.3)
            ),
            control2: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlTwoFraction,
                y: y + metrics.value(profile.0 * CoorditFitLabYarnStyle.pathSecondControlOneScale)
            )
        )
        path.addCurve(
            to: second,
            control1: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlThreeFraction,
                y: y + metrics.value(profile.1 * CoorditFitLabYarnStyle.pathSecondControlTwoScale)
            ),
            control2: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlFourFraction,
                y: y - metrics.value(profile.2 * CoorditFitLabYarnStyle.pathSecondControlThreeScale)
            )
        )
        path.addCurve(
            to: third,
            control1: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlFiveFraction,
                y: y + metrics.value(profile.3)
            ),
            control2: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlSixFraction,
                y: y + metrics.value(profile.1 * CoorditFitLabYarnStyle.pathSecondControlFourScale)
            )
        )
        path.addCurve(
            to: end,
            control1: CGPoint(
                x: centerX + travel * CoorditFitLabYarnStyle.pathControlSevenFraction,
                y: y - metrics.value(profile.0 * CoorditFitLabYarnStyle.pathFinalControlOneScale)
            ),
            control2: CGPoint(
                x: endpointX - travel * CoorditFitLabYarnStyle.pathControlEightFraction,
                y: y + metrics.value(profile.2 * CoorditFitLabYarnStyle.pathFinalControlTwoScale)
            )
        )
        return path
    }

    private func zeroCoil(center: CGPoint, radius: CGFloat) -> Path {
        var coil = Path()
        coil.move(
            to: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilStartXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilStartYScale
            )
        )
        coil.addCurve(
            to: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilEndOneXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilEndOneYScale
            ),
            control1: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilControlOneXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilControlOneYScale
            ),
            control2: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilControlTwoXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilControlTwoYScale
            )
        )
        coil.addCurve(
            to: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilEndTwoXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilEndTwoYScale
            ),
            control1: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilControlThreeXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilControlThreeYScale
            ),
            control2: CGPoint(
                x: center.x + radius * CoorditFitLabYarnStyle.zeroCoilControlFourXScale,
                y: center.y + radius * CoorditFitLabYarnStyle.zeroCoilControlFourYScale
            )
        )
        return coil
    }

    private var bendProfile: (CGFloat, CGFloat, CGFloat, CGFloat) {
        CoorditFitLabYarnStyle.bendProfile(for: measurement.key)
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

                        CoorditFitLabYarnTrail(
                            measurement: measurement,
                            difference: comparison.diff,
                            maximumDifference: maximumDifference,
                            direction: direction,
                            metrics: metrics
                        )
                    }
                    .accessibilityElement(children: .contain)
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
