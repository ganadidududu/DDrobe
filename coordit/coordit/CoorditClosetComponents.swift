import SwiftUI
import UIKit

#if os(iOS)
enum CoorditClosetColors {
    static let navy = CoorditDesignTokens.ColorToken.ink
    static let card = CoorditDesignTokens.ColorToken.panel
    static let field = CoorditDesignTokens.ColorToken.closetField
    static let muted = CoorditDesignTokens.ColorToken.closetMuted
    static let blue = CoorditDesignTokens.ColorToken.blue
    static let cyan = CoorditDesignTokens.ColorToken.cyan
    static let green = CoorditDesignTokens.ColorToken.green
    static let red = CoorditDesignTokens.ColorToken.red
}

struct CoorditClosetTitleBar: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let horizontalOutset: CGFloat
    let onBack: () -> Void

    init(
        title: String,
        metrics: CoorditResponsiveMetrics,
        horizontalOutset: CGFloat = 0,
        onBack: @escaping () -> Void
    ) {
        self.title = title
        self.metrics = metrics
        self.horizontalOutset = horizontalOutset
        self.onBack = onBack
    }

    var body: some View {
        CoorditFeatureTitleBar(
            title: title,
            metrics: metrics,
            accessibilityLabel: title,
            onBack: onBack
        )
        .padding(.horizontal, -metrics.value(horizontalOutset))
    }
}

struct CoorditClosetSegment: View {
    let selected: CoorditClosetCategory
    let metrics: CoorditResponsiveMetrics
    let onSelect: (CoorditClosetCategory) -> Void

    var body: some View {
        HStack(spacing: metrics.value(7)) {
            segment(.top)
            segment(.bottom)
        }
        .padding(metrics.value(5))
        .background(CoorditClosetColors.field)
        .clipShape(Capsule())
    }

    private func segment(_ category: CoorditClosetCategory) -> some View {
        Button {
            onSelect(category)
        } label: {
            Text(category.title)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(11)))
                .foregroundStyle(selected == category ? .white : CoorditClosetColors.navy)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(28))
                .background(selected == category ? CoorditClosetColors.navy : .white.opacity(0.65))
                .clipShape(Capsule())
        }
        .coorditPressFeedback()
        .accessibilityIdentifier("closet-category-\(category == .top ? "top" : "bottom")")
    }
}

struct CoorditClosetMetricTile: View {
    let value: String
    let label: String
    let color: Color
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(3)) {
            Text(value)
                .font(CoorditTypography.gmarketBold(size: metrics.value(16)))
                .foregroundStyle(color)
            Text(label)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(8)))
                .foregroundStyle(CoorditClosetColors.navy.opacity(0.46))
        }
        .padding(.horizontal, metrics.value(9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.value(51))
        .background(CoorditClosetColors.field)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
    }
}

struct CoorditClosetPrimaryButton: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(17), relativeTo: .headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(height))
                .background(CoorditClosetColors.navy)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
        }
        .coorditPressFeedback()
    }
}

struct CoorditSolidPrimaryButton: View {
    let title: String
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(11.5)))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(36))
                .background(CoorditDesignTokens.ColorToken.ink)
                .clipShape(Capsule())
        }
        .coorditPressFeedback()
    }
}

struct CoorditClosetGarmentCard: View {
    let item: CoorditClosetItem
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: metrics.value(3)) {
                CoorditClosetGarmentArtwork(imageData: item.imageData, category: item.category, metrics: metrics)
                    .aspectRatio(3 / 4, contentMode: .fit)
                HStack(alignment: .firstTextBaseline, spacing: metrics.value(6)) {
                    Text(item.exactCategory.koreanTitle)
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(6)))
                        .foregroundStyle(item.category == .top ? CoorditClosetColors.blue : .white)
                        .padding(.horizontal, metrics.value(6))
                        .frame(height: metrics.value(13))
                        .background(item.category == .top ? Color(red: 226 / 255, green: 232 / 255, blue: 242 / 255) : CoorditClosetColors.navy)
                        .clipShape(Capsule())
                    Text(item.name)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(12)))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                HStack(alignment: .firstTextBaseline, spacing: metrics.value(4)) {
                    Text(CoorditFitLabResultMeasurement.score(item.score))
                        .font(CoorditTypography.gmarketBold(size: metrics.value(15)))
                        .foregroundStyle(item.scoreColor)
                    Text("fit score")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(7.5)))
                        .foregroundStyle(CoorditClosetColors.navy.opacity(0.48))
                }
            }
            .padding(metrics.value(6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoorditClosetColors.card)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
        }
        .coorditPressFeedback()
        .accessibilityIdentifier(item.name)
    }
}

struct CoorditClosetGarmentArtwork: View {
    let imageData: Data?
    let category: CoorditClosetCategory
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 226 / 255, green: 230 / 255, blue: 238 / 255),
                        Color(red: 239 / 255, green: 242 / 255, blue: 247 / 255),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if category == .top {
                    Image(systemName: "tshirt")
                        .font(.system(size: metrics.value(22), weight: .medium))
                        .foregroundStyle(CoorditClosetColors.navy.opacity(0.18))
                } else {
                    CoorditPantsPlaceholderShape()
                        .fill(CoorditClosetColors.navy.opacity(0.18))
                        .frame(width: metrics.value(24), height: metrics.value(28))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(8))
                .stroke(Color(red: 213 / 255, green: 219 / 255, blue: 231 / 255), lineWidth: metrics.value(0.7))
        )
        .accessibilityLabel(category == .top ? "상의 사진 없음" : "하의 사진 없음")
        .accessibilityIdentifier("closet-placeholder-\(category == .top ? "top" : "bottom")")
    }
}

private struct CoorditPantsPlaceholderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.43))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
#endif
