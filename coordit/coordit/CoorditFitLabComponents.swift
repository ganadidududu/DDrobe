import SwiftUI

#if os(iOS)
enum CoorditFitLabPalette {
    static let ink = CoorditDesignTokens.ColorToken.ink
    static let surface = CoorditDesignTokens.ColorToken.panel
    static let field = CoorditDesignTokens.ColorToken.field
    static let empty = CoorditDesignTokens.ColorToken.placeholder
    static let muted = CoorditDesignTokens.ColorToken.fitMuted
    static let noticeAccent = CoorditDesignTokens.ColorToken.loadingSparkle
}

struct CoorditFitLabTitleCard: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let onBack: () -> Void

    var body: some View {
        CoorditFeatureTitleBar(
            title: title,
            metrics: metrics,
            accessibilityLabel: "\(title) 뒤로가기",
            onBack: onBack
        )
    }
}

struct CoorditFitLabPrimaryButton: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(
                CoorditContentActionButtonStyle(
                    prominence: .primary,
                    height: metrics.value(48),
                    cornerRadius: metrics.value(7),
                    fontSize: metrics.value(15)
                )
            )
    }
}

struct CoorditFitLabSourceButton: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(15), relativeTo: .body))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(65))
                .background(
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 250 / 255, green: 251 / 255, blue: 254 / 255),
                                Color(red: 225 / 255, green: 230 / 255, blue: 243 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        CoorditFitLabSubtleNoise()
                            .opacity(0.38)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.value(7))
                        .stroke(.white.opacity(0.8), lineWidth: metrics.value(1))
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                .shadow(color: .black.opacity(0.12), radius: metrics.value(9), y: metrics.value(4))
        }
        .coorditPressFeedback()
    }
}

struct CoorditFitLabTexturedPanel: View {
    let cornerRadius: CGFloat
    let intensity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 90 / 255, green: 104 / 255, blue: 164 / 255),
                    Color(red: 21 / 255, green: 35 / 255, blue: 98 / 255),
                    CoorditFitLabPalette.ink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            CoorditFitLabSubtleNoise()
                .blendMode(.overlay)
                .opacity(0.34 * intensity)

            LinearGradient(
                colors: [.white.opacity(0.26), .clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CoorditFitLabSubtleNoise: View {
    var body: some View {
        Canvas { context, size in
            let columns = max(Int(size.width), 1)
            let rows = max(Int(size.height), 1)

            for row in stride(from: 0, to: rows, by: 2) {
                for column in stride(from: 0, to: columns, by: 2) {
                    let seed = Double((row * 89 + column * 157) % 1009)
                    let opacity = 0.025 + (sin(seed) + 1) * 0.045
                    let rect = CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1)
                    context.fill(Path(rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}

struct CoorditFitLabMannequinPanel: View {
    let assetName: String
    let metrics: CoorditResponsiveMetrics
    var measurements: [CoorditFitLabResultMeasurement] = []
    var accessibilityIdentifier: String? = nil
    var overlayIdentifierPrefix = "fitlab-overlay"

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if measurements.isEmpty {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(metrics.value(7))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    CoorditFitLabSemanticSilhouette(
                        assetName: assetName,
                        measurements: measurements,
                        inset: metrics.value(7)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                }

                ForEach(measurements) { measurement in
                    if let direction = measurement.direction,
                       let comparison = measurement.comparison,
                       comparison.diff.isFinite {
                        CoorditFitLabCalloutConnector(
                            start: bodyAnchor(for: measurement.key),
                            end: labelAnchor(for: measurement.key),
                            color: mannequinColor(for: direction)
                        )
                        .accessibilityHidden(true)

                        CoorditFitLabOverlayMarker(
                            measurement: measurement,
                            direction: direction,
                            intensity: min(max(abs(comparison.diff) / 5, 0), 1),
                            metrics: metrics,
                            identifierPrefix: overlayIdentifierPrefix
                        )
                        .position(
                            x: proxy.size.width * labelAnchor(for: measurement.key).x,
                            y: proxy.size.height * labelAnchor(for: measurement.key).y
                        )
                    }
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(4)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(4))
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(assetName == CoorditAssetNames.fitUpper ? "상의 핏 마네킹" : "하의 핏 마네킹")
        .accessibilityIdentifier(
            accessibilityIdentifier ?? (
                assetName == CoorditAssetNames.fitUpper
                    ? "fitlab-mannequin-upper"
                    : "fitlab-mannequin-lower"
            )
        )
    }

    private func bodyAnchor(for key: CoorditFitLabMeasurementKey) -> CGPoint {
        switch key {
        case .shoulderWidth: CGPoint(x: 0.40, y: 0.30)
        case .chestWidth: CGPoint(x: 0.56, y: 0.43)
        case .totalLength: CGPoint(x: 0.43, y: 0.60)
        case .sleeveLength: CGPoint(x: 0.62, y: 0.75)
        case .waistWidth: CGPoint(x: 0.445, y: 0.24)
        case .hipWidth: CGPoint(x: 0.57, y: 0.36)
        case .rise: CGPoint(x: 0.50, y: 0.50)
        case .outseam: CGPoint(x: 0.57, y: 0.82)
        }
    }

    private func labelAnchor(for key: CoorditFitLabMeasurementKey) -> CGPoint {
        switch key {
        case .shoulderWidth: CGPoint(x: 0.23, y: 0.22)
        case .chestWidth: CGPoint(x: 0.77, y: 0.32)
        case .totalLength: CGPoint(x: 0.23, y: 0.55)
        case .sleeveLength: CGPoint(x: 0.77, y: 0.57)
        case .waistWidth: CGPoint(x: 0.23, y: 0.23)
        case .hipWidth: CGPoint(x: 0.77, y: 0.35)
        case .rise: CGPoint(x: 0.23, y: 0.49)
        case .outseam: CGPoint(x: 0.77, y: 0.62)
        }
    }

    private func mannequinColor(for direction: CoorditFitLabResultMeasurement.Direction) -> Color {
        switch direction {
        case .tight: CoorditDesignTokens.ColorToken.red
        case .similar: Color(red: 0.48, green: 0.52, blue: 0.59)
        case .loose: CoorditDesignTokens.ColorToken.blue
        }
    }
}

private struct CoorditFitLabOverlayMarker: View {
    let measurement: CoorditFitLabResultMeasurement
    let direction: CoorditFitLabResultMeasurement.Direction
    let intensity: Double
    let metrics: CoorditResponsiveMetrics
    let identifierPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(1)) {
            HStack(spacing: metrics.value(3)) {
                Circle()
                    .fill(mannequinColor)
                    .frame(width: metrics.value(6), height: metrics.value(6))
                Text(measurement.title)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(8), relativeTo: .caption2))
            }
            Text("\(CoorditFitLabResultMeasurement.signed(measurement.comparison?.diff ?? 0)) cm · \(direction.label)")
                .font(CoorditTypography.gmarketBold(size: metrics.value(9), relativeTo: .caption2))
                .foregroundStyle(mannequinColor)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, metrics.value(7))
        .padding(.vertical, metrics.value(5))
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous)
                .stroke(mannequinColor.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: mannequinColor.opacity(0.16 + intensity * 0.12), radius: metrics.value(5), y: metrics.value(2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measurement.title) \(direction.label), 차이 \(CoorditFitLabResultMeasurement.signed(measurement.comparison?.diff ?? 0)) cm")
        .accessibilityIdentifier("\(identifierPrefix)-\(measurement.key.rawValue)")
    }

    private var mannequinColor: Color {
        switch direction {
        case .tight: CoorditDesignTokens.ColorToken.red
        case .similar: Color(red: 0.48, green: 0.52, blue: 0.59)
        case .loose: CoorditDesignTokens.ColorToken.blue
        }
    }
}

private struct CoorditFitLabCalloutConnector: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let startPoint = CGPoint(x: proxy.size.width * start.x, y: proxy.size.height * start.y)
                let endPoint = CGPoint(x: proxy.size.width * end.x, y: proxy.size.height * end.y)
                path.move(to: startPoint)
                path.addLine(to: CGPoint(x: (startPoint.x + endPoint.x) / 2, y: startPoint.y))
                path.addLine(to: endPoint)
            }
            .stroke(
                color.opacity(0.72),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .position(
                    x: proxy.size.width * start.x,
                    y: proxy.size.height * start.y
                )
        }
    }
}

private struct CoorditFitLabSemanticSilhouette: View {
    let assetName: String
    let measurements: [CoorditFitLabResultMeasurement]
    let inset: CGFloat

    var body: some View {
        ZStack {
            Color(red: 0.53, green: 0.57, blue: 0.64)
                .opacity(0.48)

            ForEach(measurements) { measurement in
                if let direction = measurement.direction,
                   let comparison = measurement.comparison,
                   comparison.diff.isFinite {
                    silhouetteColor(for: direction)
                        .opacity(0.76 + min(abs(comparison.diff) / 5, 1) * 0.08)
                        .mask(
                            CoorditFitLabMeasurementRegion(key: measurement.key)
                                .blur(radius: 8)
                        )
                }
            }
        }
        .mask(lineMask)
    }

    private func silhouetteColor(for direction: CoorditFitLabResultMeasurement.Direction) -> Color {
        switch direction {
        case .tight: Color(red: 0.90, green: 0.34, blue: 0.40)
        case .similar: Color(red: 0.55, green: 0.58, blue: 0.64)
        case .loose: Color(red: 0.10, green: 0.60, blue: 0.72)
        }
    }

    private var lineMask: some View {
        Image(
            assetName == CoorditAssetNames.fitUpper
                ? CoorditAssetNames.fitUpperLineMask
                : CoorditAssetNames.fitLowerLineMask
        )
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .padding(inset)
    }
}

private struct CoorditFitLabMeasurementRegion: Shape {
    let key: CoorditFitLabMeasurementKey

    func path(in rect: CGRect) -> Path {
        func region(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y,
                width: rect.width * width,
                height: rect.height * height
            )
        }

        var path = Path()
        switch key {
        case .shoulderWidth:
            path.addRect(region(0.26, 0.20, 0.48, 0.11))
        case .chestWidth:
            path.addRect(region(0.27, 0.32, 0.16, 0.18))
            path.addRect(region(0.57, 0.32, 0.16, 0.18))
        case .totalLength:
            path.addRect(region(0.28, 0.51, 0.17, 0.20))
            path.addRect(region(0.55, 0.51, 0.17, 0.20))
        case .sleeveLength:
            path.addRect(region(0.14, 0.31, 0.17, 0.47))
            path.addRect(region(0.69, 0.31, 0.17, 0.47))
        case .waistWidth:
            path.addRect(region(0.27, 0.18, 0.18, 0.13))
            path.addRect(region(0.55, 0.18, 0.18, 0.13))
        case .hipWidth:
            path.addRect(region(0.23, 0.29, 0.20, 0.16))
            path.addRect(region(0.57, 0.29, 0.20, 0.16))
        case .rise:
            path.addRect(region(0.42, 0.37, 0.16, 0.23))
        case .outseam:
            path.addRect(region(0.22, 0.42, 0.20, 0.50))
            path.addRect(region(0.58, 0.42, 0.20, 0.50))
        }
        return path
    }
}

struct CoorditFitLabOverlayLegend: View {
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        HStack(spacing: metrics.value(7)) {
            legend("타이트", color: CoorditDesignTokens.ColorToken.red)
            legend("비슷", color: Color(red: 0.48, green: 0.52, blue: 0.59))
            legend("여유", color: CoorditDesignTokens.ColorToken.blue)
        }
        .foregroundStyle(Color.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("마네킹 표시 범례. 빨간색 타이트, 회색 비슷, 파란색 여유")
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Capsule()
                .fill(color)
                .frame(width: metrics.value(16), height: metrics.value(4))
            Text(label)
        }
        .font(CoorditTypography.gmarketMedium(size: metrics.value(7), relativeTo: .caption2))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 1))
    }
}

struct CoorditFitLabReportCard: View {
    let report: CoorditFitLabReportResponse?
    let fallbackMessage: String?
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(14)) {
            VStack(alignment: .leading, spacing: metrics.value(3)) {
                Text("DETAILED FIT ANALYSIS")
                    .font(CoorditTypography.mona12(size: metrics.value(18), relativeTo: .headline))
                Text("기준 의류와 상품 실측을 부위별로 해석했어요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditFitLabPalette.muted)
            }

            if let fallbackMessage {
                Text(fallbackMessage)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .body))
                    .accessibilityIdentifier("fitlab-report-fallback")
            }

            if let report {
                reportSection(
                    eyebrow: "OVERALL VERDICT",
                    title: report.report.title,
                    text: report.report.summary,
                    prominent: true
                )

                if let reason = report.report.recommendationReason, !reason.isEmpty {
                    reportSection(
                        eyebrow: "WHY THIS SIZE",
                        title: "이 사이즈를 추천하는 이유",
                        text: reason,
                        prominent: false
                    )
                }

                if !report.report.measurementAnalysis.isEmpty {
                    Text("부위별 정밀 분석")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(17), relativeTo: .headline))
                        .padding(.top, metrics.value(3))

                    ForEach(Array(report.report.measurementAnalysis.enumerated()), id: \.offset) { _, analysis in
                        analysisSection(analysis)
                    }
                }

                if !report.report.cautions.isEmpty || !report.report.nextActions.isEmpty {
                    VStack(alignment: .leading, spacing: metrics.value(10)) {
                        Text("구매 전 마지막 확인")
                            .font(CoorditTypography.gmarketBold(size: metrics.value(15), relativeTo: .headline))
                        ForEach(Array(report.report.cautions.enumerated()), id: \.offset) { _, caution in
                            noteRow(caution, systemName: "exclamationmark.circle.fill")
                        }
                        ForEach(Array(report.report.nextActions.enumerated()), id: \.offset) { index, action in
                            noteRow(action, systemName: "checkmark.circle.fill")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(action)
                                .accessibilityIdentifier(
                                    index == report.report.nextActions.indices.last
                                        ? "fitlab-report-final-action"
                                        : "fitlab-report-action-\(index)"
                                )
                        }
                    }
                    .padding(metrics.value(16))
                    .background(CoorditFitLabPalette.field)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous))
                }
            } else {
                Text("상세 리포트를 불러오지 못했어요. 추천 점수와 비교 수치는 그대로 확인할 수 있어요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
            }
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("fitlab-report-description")
    }

    @ViewBuilder
    private func reportSection(
        eyebrow: String,
        title: String,
        text: String,
        prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            Text(eyebrow)
                .font(CoorditTypography.mona12(size: metrics.value(10), relativeTo: .caption))
                .tracking(metrics.value(0.7))
                .foregroundStyle(prominent ? Color.white.opacity(0.72) : CoorditFitLabPalette.muted)
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(16), relativeTo: .headline))
            Text(text)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
                .lineSpacing(metrics.value(4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(prominent ? Color.white : Color.black)
        .padding(metrics.value(17))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(prominent ? CoorditFitLabPalette.ink : CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous)
                .stroke(Color.black.opacity(prominent ? 0 : 0.1), lineWidth: 1)
        )
    }

    private func analysisSection(
        _ analysis: CoorditFitLabReportResponse.Report.MeasurementAnalysis
    ) -> some View {
        let direction = report?.chartData.idealVsProduct
            .first { $0.label == analysis.measurement }
            .flatMap { comparison in
                CoorditFitLabResultMeasurement(
                    key: comparison.measurement,
                    title: comparison.label,
                    comparison: comparison
                ).direction
            }

        return HStack(alignment: .top, spacing: metrics.value(11)) {
            Capsule()
                .fill(direction?.color ?? CoorditFitLabPalette.ink)
                .frame(width: metrics.value(4))
            VStack(alignment: .leading, spacing: metrics.value(6)) {
                HStack {
                    Text(analysis.measurement)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                    Spacer()
                    if let direction {
                        Text(direction.label)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(9), relativeTo: .caption))
                            .foregroundStyle(direction.color)
                    }
                }
                Text(analysis.text)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
                    .lineSpacing(metrics.value(4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(metrics.value(15))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(9), style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    private func noteRow(_ text: String, systemName: String) -> some View {
        HStack(alignment: .top, spacing: metrics.value(8)) {
            Image(systemName: systemName)
                .font(.system(size: metrics.value(13), weight: .semibold))
                .foregroundStyle(CoorditFitLabPalette.ink)
            Text(text)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .body))
                .lineSpacing(metrics.value(3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityDescription: String {
        guard let report else { return fallbackMessage ?? "상세 리포트 없음" }
        let analysis = report.report.measurementAnalysis.map { "\($0.measurement) \($0.text)" }
        return ([report.report.title, report.report.summary]
            + [report.report.recommendationReason].compactMap { $0 }
            + analysis
            + report.report.cautions
            + report.report.nextActions).joined(separator: " ")
    }
}

struct CoorditFitLabDescriptionCard: View {
    let metrics: CoorditResponsiveMetrics
    let compact: Bool
    let onDetail: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: metrics.value(10)) {
            Text("Score Description")
                .font(CoorditTypography.mona12(size: metrics.value(16), relativeTo: .body))
                .foregroundStyle(Color.black)
            Spacer(minLength: 0)
            if let onDetail {
                Button(action: onDetail) {
                    Text("자세히 보기")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(9), relativeTo: .caption))
                        .foregroundStyle(.white)
                        .frame(width: metrics.value(89), height: metrics.value(28))
                        .background(CoorditFitLabPalette.ink)
                        .clipShape(Capsule())
                }
                .coorditPressFeedback()
            }
        }
        .padding(.horizontal, metrics.value(18))
        .padding(.top, compact ? 0 : metrics.value(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .center : .topLeading)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(5)))
    }
}

struct CoorditFitLabStars: View {
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        HStack(spacing: metrics.value(3)) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: metrics.value(15), weight: .semibold))
                    .foregroundStyle(index < 3 ? Color(red: 48 / 255, green: 72 / 255, blue: 151 / 255) : Color.black.opacity(0.14))
            }
        }
    }
}
#endif
