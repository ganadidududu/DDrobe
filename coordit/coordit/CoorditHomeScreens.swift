import Combine
import SwiftUI

#if os(iOS)
struct CoorditMain04Screen: View {
    let onRouteChange: (CoorditFrameRoute) -> Void
    @Binding var closetItems: [CoorditClosetItem]
    @Binding var selectedReferenceIDs: Set<String>
    let fitLabHistory: [CoorditFitLabHistorySnapshot]
    let onOpenFitLabHistory: (CoorditFitLabHistorySnapshot) -> Void
    let onReferenceCommit: (Set<String>) -> Void
    @State private var showsReferenceSelection = false
    @EnvironmentObject private var backendSession: CoorditBackendSessionStore

    init(
        closetItems: Binding<[CoorditClosetItem]>,
        selectedReferenceIDs: Binding<Set<String>>,
        fitLabHistory: [CoorditFitLabHistorySnapshot] = [],
        onOpenFitLabHistory: @escaping (CoorditFitLabHistorySnapshot) -> Void = { _ in },
        onReferenceCommit: @escaping (Set<String>) -> Void,
        onRouteChange: @escaping (CoorditFrameRoute) -> Void = { _ in }
    ) {
        _closetItems = closetItems
        _selectedReferenceIDs = selectedReferenceIDs
        self.fitLabHistory = fitLabHistory
        self.onOpenFitLabHistory = onOpenFitLabHistory
        self.onReferenceCommit = onReferenceCommit
        self.onRouteChange = onRouteChange
    }

    var body: some View {
        CoorditScreenScaffold(route: .main04, onRouteChange: onRouteChange, contentTop: 121) { metrics in
            VStack(spacing: metrics.value(16)) {
                CoorditBannerCard(metrics: metrics)

                CoorditFitLabHistoryCard(
                    history: fitLabHistory,
                    metrics: metrics,
                    onOpenHistory: onOpenFitLabHistory,
                    onRouteChange: onRouteChange
                )

                CoorditHomeReferenceCard(
                    items: closetItems,
                    selectedIDs: selectedReferenceIDs,
                    metrics: metrics,
                    onSelect: { showsReferenceSelection = true }
                )

                if backendSession.isWarning {
                    Text("일부 기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9.5)))
                        .foregroundStyle(CoorditDesignTokens.ColorToken.danger)
                        .frame(width: metrics.value(361), alignment: .leading)
                        .accessibilityIdentifier("home-reference-sync-status")
                }

                CoorditClosetEntryCard(metrics: metrics) {
                    onRouteChange(.closetOverview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("coordit-screen-main04")
        }
        .sheet(isPresented: $showsReferenceSelection) {
            CoorditHomeReferenceSelectionSheet(
                items: closetItems,
                initialSelection: selectedReferenceIDs,
                onCommit: { selection in
                    onReferenceCommit(selection)
                },
                onAddGarment: { onRouteChange(.closetAddMethod) }
            )
        }
    }
}

private struct CoorditBannerCard: View {
    let metrics: CoorditResponsiveMetrics
    @State private var selectedIssue = 0

    private let issues = CoorditFashionMagazineIssue.homeIssues
    private let autoAdvanceTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.value(7)) {
                Text("MAGAZINE")
                    .font(CoorditTypography.climate2019(size: metrics.value(17), relativeTo: .headline))
                    .tracking(-0.6 * metrics.scale)
                    .foregroundStyle(CoorditHomePalette.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.top, metrics.value(15))
            .padding(.horizontal, metrics.value(14))

            TabView(selection: $selectedIssue) {
                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    CoorditFashionMagazinePage(issue: issue, metrics: metrics)
                        .tag(index)
                        .padding(.horizontal, metrics.value(14))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: metrics.value(186))
            .accessibilityIdentifier("coordit-main04-fashion-magazine-carousel")

            HStack(spacing: metrics.value(5)) {
                ForEach(issues.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIssue ? CoorditHomePalette.ink : CoorditHomePalette.ink.opacity(0.18))
                        .frame(width: metrics.value(index == selectedIssue ? 18 : 6), height: metrics.value(6))
                        .animation(.snappy(duration: 0.24), value: selectedIssue)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.value(15))
            .padding(.bottom, metrics.value(12))
        }
        .frame(width: metrics.value(361), height: metrics.value(259), alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    CoorditHomePalette.card,
                    Main01DesignTokens.Colors.rgb(238, 242, 250),
                    Main01DesignTokens.Colors.rgb(228, 233, 246),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(10), style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: metrics.value(12), y: metrics.value(4))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coordit-main04-banner")
        .onReceive(autoAdvanceTimer) { _ in
            withAnimation(.snappy(duration: 0.36)) {
                selectedIssue = (selectedIssue + 1) % issues.count
            }
        }
    }
}

private struct CoorditFashionMagazinePage: View {
    let issue: CoorditFashionMagazineIssue
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(9)) {
            HStack(spacing: metrics.value(7)) {
                Text(issue.kicker)
                    .font(CoorditTypography.mona12(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.value(8))
                    .frame(height: metrics.value(20))
                    .background(issue.tint)
                    .clipShape(Capsule())

                Text(issue.status)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(8.5), relativeTo: .caption2))
                    .foregroundStyle(issue.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(issue.title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(25), relativeTo: .title3))
                .foregroundStyle(CoorditHomePalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)

            Text(issue.body)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10.5), relativeTo: .caption))
                .foregroundStyle(CoorditHomePalette.ink.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: metrics.value(6)) {
                ForEach(issue.tags, id: \.self) { tag in
                    Text(tag)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(8), relativeTo: .caption2))
                        .foregroundStyle(CoorditHomePalette.ink.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, metrics.value(7))
                        .frame(height: metrics.value(21))
                        .background(.white.opacity(0.55))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }
        }
        .padding(metrics.value(15))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                .fill(.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: metrics.value(0.8))
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
    }
}

private struct CoorditFashionMagazineIssue {
    let kicker: String
    let status: String
    let title: String
    let body: String
    let tags: [String]
    let tint: Color

    static let homeIssues = [
        CoorditFashionMagazineIssue(
            kicker: "SALE RADAR",
            status: "지난 세일 체크",
            title: "무진장·직잭팟은 끝. 다음은 장바구니 정리",
            body: "여름 대형 세일은 대부분 6월 말에 종료. 지금은 위시템 사이즈를 먼저 검증할 타이밍.",
            tags: ["MUSINSA", "ZIGZAG", "SIZE CHECK"],
            tint: Main01DesignTokens.Colors.rgb(55, 75, 156)
        ),
        CoorditFashionMagazineIssue(
            kicker: "NEXT DROP",
            status: "곧 볼 구간",
            title: "에이블리 여름 클리어런스는 7월 말부터 주시",
            body: "플랫폼별 시즌오프가 이어지는 구간. 인기 옵션은 빠르게 빠지니 대체 사이즈까지 준비.",
            tags: ["ABLY", "CLEARANCE", "WISHLIST"],
            tint: Main01DesignTokens.Colors.rgb(24, 132, 122)
        ),
        CoorditFashionMagazineIssue(
            kicker: "TREND NOW",
            status: "2026 S/S",
            title: "레드 포인트, 포엣 코어, 가벼운 로맨틱 무드",
            body: "작은 포인트가 쉬운 시즌. 키링, 셔츠, 얇은 레이어로 시작.",
            tags: ["RED", "POET CORE", "LAYER"],
            tint: Main01DesignTokens.Colors.rgb(177, 51, 68)
        ),
    ]
}

private struct CoorditHomeFitLabHistoryItem: Identifiable {
    let snapshot: CoorditFitLabHistorySnapshot
    let id: String
    let name: String
    let category: String
    let sizeSummary: String
    let score: String
    let tint: Color

    init(snapshot: CoorditFitLabHistorySnapshot) {
        self.snapshot = snapshot
        self.id = snapshot.analysisID
        self.name = snapshot.product.name
        self.category = snapshot.garmentKind == .upper ? "TOP" : "BOTTOM"
        self.sizeSummary = "\(snapshot.recommendation.recommendedSize) 추천"
        self.score = CoorditFitLabResultMeasurement.score(snapshot.recommendation.fitScore)
        self.tint = snapshot.garmentKind == .upper
            ? Main01DesignTokens.Colors.rgb(54, 93, 168)
            : Main01DesignTokens.Colors.rgb(24, 132, 120)
    }
}

private struct CoorditFitLabHistoryCard: View {
    let history: [CoorditFitLabHistorySnapshot]
    let metrics: CoorditResponsiveMetrics
    let onOpenHistory: (CoorditFitLabHistorySnapshot) -> Void
    let onRouteChange: (CoorditFrameRoute) -> Void

    private var recentItems: [CoorditHomeFitLabHistoryItem] {
        history
            .sorted {
                if $0.savedAt == $1.savedAt { return $0.analysisID > $1.analysisID }
                return $0.savedAt > $1.savedAt
            }
            .prefix(2)
            .map { CoorditHomeFitLabHistoryItem(snapshot: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: metrics.value(7)) {
                Text("FIT LAB")
                    .font(CoorditTypography.climate2019(size: metrics.value(18.6), relativeTo: .headline))
                    .tracking(-0.93 * metrics.scale)
                    .foregroundStyle(.black)
                    .lineLimit(1)

                Text("당신에게 꼭 맞는 사이즈 설계")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(8.8), relativeTo: .caption2))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, metrics.value(14))
            .padding(.horizontal, metrics.value(16))

            CoorditSolidPrimaryButton(title: "새로운 옷 찾기", metrics: metrics) {
                onRouteChange(.fitLabInput)
            }
            .padding(.top, metrics.value(5))
            .padding(.horizontal, metrics.value(16))
            .accessibilityIdentifier("coordit-main04-new-fit-button")

            HStack(alignment: .center, spacing: 0) {
                Text("HISTORY")
                    .font(CoorditTypography.climate2019(size: metrics.value(8.8), relativeTo: .caption2))
                    .tracking(-0.35 * metrics.scale)
                    .foregroundStyle(.black)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("최근 저장 2개")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(8.2), relativeTo: .caption2))
                    .foregroundStyle(.black.opacity(0.48))
                    .lineLimit(1)
            }
            .padding(.top, metrics.value(7))
            .padding(.leading, metrics.value(16))
            .padding(.trailing, metrics.value(16))

            Group {
                if recentItems.isEmpty {
                    Text("저장한 핏 리포트가 아직 없어요")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(.black.opacity(0.55))
                        .frame(maxWidth: .infinity, minHeight: metrics.value(54))
                        .background(Color.black.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                        .accessibilityIdentifier("coordit-main04-history-empty")
                } else {
                    HStack(spacing: metrics.value(8)) {
                        ForEach(recentItems) { item in
                            Button {
                                onOpenHistory(item.snapshot)
                            } label: {
                                CoorditFitLabHistoryPreviewCard(item: item, metrics: metrics)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityIdentifier("coordit-main04-history-card-\(item.id)")
                                    .accessibilityLabel("\(item.name), \(item.sizeSummary), \(item.score)점, 핏랩 히스토리")
                            }
                            .coorditPressFeedback()
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("coordit-main04-history-card-\(item.id)")
                            .accessibilityLabel("\(item.name), \(item.sizeSummary), \(item.score)점, 핏랩 히스토리")
                        }
                    }
                }
            }
            .padding(.top, metrics.value(6))
            .padding(.horizontal, metrics.value(16))

            Spacer(minLength: 0)
        }
        .frame(width: metrics.value(361), height: metrics.value(170), alignment: .topLeading)
        .background(CoorditHomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(10), style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: metrics.value(12), y: metrics.value(4))
        .accessibilityIdentifier("coordit-main04-fitlab-card")
    }
}

private struct CoorditFitLabHistoryPreviewCard: View {
    let item: CoorditHomeFitLabHistoryItem
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        HStack(alignment: .center, spacing: metrics.value(7)) {
            VStack(alignment: .leading, spacing: metrics.value(4)) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.value(5)) {
                    Text(item.name)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text(item.category)
                        .font(CoorditTypography.mona12(size: metrics.value(7.4), relativeTo: .caption2))
                        .foregroundStyle(item.tint.opacity(0.82))
                        .lineLimit(1)
                }

                HStack(spacing: metrics.value(5)) {
                    Text(item.sizeSummary)
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(8.2), relativeTo: .caption2))
                        .foregroundStyle(.black.opacity(0.56))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: metrics.value(4))

            VStack(alignment: .trailing, spacing: metrics.value(1)) {
                Text("SCORE")
                    .font(CoorditTypography.mona12(size: metrics.value(7.4), relativeTo: .caption2))
                    .foregroundStyle(.black.opacity(0.45))
                    .lineLimit(1)

                Text(item.score)
                    .font(CoorditTypography.mona12(size: metrics.value(19), relativeTo: .headline))
                    .foregroundStyle(CoorditHomePalette.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.value(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.value(54))
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    item.tint.opacity(0.08),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous)
                .stroke(.black.opacity(0.1), lineWidth: metrics.value(0.8))
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
    }
}

private struct CoorditClosetEntryCard: View {
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("MY CLOSET")
                    .font(CoorditTypography.climate2019(size: metrics.value(17.2), relativeTo: .headline))
                    .tracking(-0.86 * metrics.scale)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.leading, metrics.value(12))

                Spacer(minLength: 0)
            }
            .frame(width: metrics.value(361), height: metrics.value(43))
            .background(
                LinearGradient(
                    colors: [
                        CoorditHomePalette.card,
                        Main01DesignTokens.Colors.rgb(235, 238, 247),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(10), style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: metrics.value(9), y: metrics.value(3))
        }
        .coorditPressFeedback()
        .padding(.bottom, metrics.value(7))
        .accessibilityIdentifier("coordit-main04-closet-button")
    }
}

private enum CoorditHomePalette {
    static let card = CoorditDesignTokens.ColorToken.panel
    static let ink = CoorditDesignTokens.ColorToken.ink
}
#endif
