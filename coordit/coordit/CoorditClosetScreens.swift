import SwiftUI

#if os(iOS)
import PhotosUI
import UIKit

enum CoorditClosetCategory: CaseIterable, Equatable {
    case top
    case bottom

    var title: String {
        switch self {
        case .top: "상의"
        case .bottom: "하의"
        }
    }
}

struct CoorditClosetSizeChart: Equatable {
    let sizeLabel: String?
    let measurements: CoorditMeasurementMap
}

struct CoorditClosetAddSaveState: Equatable {
    var isSaving = false
    var errorMessage: String?
    var idempotencyKey: String?
    private(set) var requestGeneration = 0

    mutating func beginSave() -> Int {
        requestGeneration &+= 1
        errorMessage = nil
        isSaving = true
        return requestGeneration
    }

    mutating func reset() {
        requestGeneration &+= 1
        isSaving = false
        errorMessage = nil
        idempotencyKey = nil
    }

    func isCurrent(_ generation: Int) -> Bool {
        requestGeneration == generation
    }
}

struct CoorditClosetItem: Identifiable {
    let id: String
    var name: String
    let category: CoorditClosetCategory
    let exactCategory: CoorditFitLabCategory
    var score: Double
    let scoreColor: Color
    let route: CoorditFrameRoute
    var imageData: Data?
    var fitDiffs: CoorditMeasurementMap? = nil
    var sizeChart: CoorditClosetSizeChart? = nil
    var backendClothingItemId: String? = nil
    var backendReferenceClothingId: String? = nil

    init(
        id: String,
        name: String,
        category: CoorditClosetCategory,
        exactCategory: CoorditFitLabCategory? = nil,
        score: Double,
        scoreColor: Color,
        route: CoorditFrameRoute,
        imageData: Data?,
        fitDiffs: CoorditMeasurementMap? = nil,
        sizeChart: CoorditClosetSizeChart? = nil,
        backendClothingItemId: String? = nil,
        backendReferenceClothingId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.exactCategory = exactCategory ?? (category == .top ? .shirt : .pants)
        self.score = score
        self.scoreColor = scoreColor
        self.route = route
        self.imageData = imageData
        self.fitDiffs = fitDiffs
        self.sizeChart = sizeChart
        self.backendClothingItemId = backendClothingItemId
        self.backendReferenceClothingId = backendReferenceClothingId
    }

    static let seedItems = [
        CoorditClosetItem(
            id: "oxford",
            name: "Oxford Shirt",
            category: .top,
            exactCategory: .shirt,
            score: 94,
            scoreColor: CoorditClosetColors.blue,
            route: .closetDetailTop,
            imageData: nil,
            fitDiffs: CoorditMeasurementMap(
                totalLength: 1.5,
                shoulderWidth: -1,
                chestWidth: 2,
                sleeveLength: -0.5,
                waistWidth: nil,
                hipWidth: nil,
                rise: nil,
                outseam: nil
            )
        ),
        CoorditClosetItem(id: "knit", name: "Relaxed Knit", category: .top, exactCategory: .knit, score: 88, scoreColor: CoorditClosetColors.cyan, route: .closetDetailTop, imageData: nil),
        CoorditClosetItem(
            id: "denim",
            name: "Wide Denim",
            category: .bottom,
            exactCategory: .jeans,
            score: 91,
            scoreColor: CoorditClosetColors.blue,
            route: .closetDetailBottom,
            imageData: nil,
            fitDiffs: CoorditMeasurementMap(
                totalLength: nil,
                shoulderWidth: nil,
                chestWidth: nil,
                sleeveLength: nil,
                waistWidth: -3,
                hipWidth: 1,
                rise: -0.5,
                outseam: 2
            ),
            sizeChart: CoorditClosetSizeChart(
                sizeLabel: "M",
                measurements: CoorditMeasurementMap(
                    totalLength: nil,
                    shoulderWidth: nil,
                    chestWidth: nil,
                    sleeveLength: nil,
                    waistWidth: 40,
                    hipWidth: 53,
                    rise: 30,
                    outseam: 101
                )
            )
        ),
        CoorditClosetItem(id: "slacks", name: "Black Slacks", category: .bottom, exactCategory: .pants, score: 0, scoreColor: CoorditClosetColors.navy, route: .closetDetailBottom, imageData: nil),
    ]
}

struct CoorditClosetFamilyView: View {
    let route: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void
    let onSavedItem: (CoorditClosetItem) async -> CoorditFrameRoute?

    @Binding var items: [CoorditClosetItem]
    @Binding var selectedItemID: String?
    @Binding var draft: CoorditClosetDraft
    @Binding var selectedReferenceIDs: Set<String>
    @Binding var addSaveState: CoorditClosetAddSaveState

    @EnvironmentObject var backendSession: CoorditBackendSessionStore
    @State var selectedCategory: CoorditClosetCategory = .top
    @State private var searchText = ""
    @State private var selectedExactCategory: CoorditFitLabCategory?
    @State var detailVariant: CoorditClosetCategory
    @State var detailPhotoSelection: PhotosPickerItem?
    @State var detailPhotoGenerations: [String: Int]
    @State var isRenamingDetailItem: Bool
    @State var pendingDetailName: String
    @State var showsDeleteConfirmation: Bool
    @State var isDeletingDetailItem: Bool
    @State var detailFitComparison: CoorditClosetFitComparisonResponse?

    #if DEBUG
    @State var detailPhotoTestStates: [String: String]
    @State var detailPhotoTestRejections: [String: String]
    @State var detailPhotoScenarioAppearances: [String: Int]
    #endif

    init(
        route: CoorditFrameRoute,
        items: Binding<[CoorditClosetItem]>,
        selectedItemID: Binding<String?>,
        draft: Binding<CoorditClosetDraft>,
        selectedReferenceIDs: Binding<Set<String>>,
        addSaveState: Binding<CoorditClosetAddSaveState>,
        onSavedItem: @escaping (CoorditClosetItem) async -> CoorditFrameRoute?,
        onRouteChange: @escaping (CoorditFrameRoute) -> Void
    ) {
        self.route = route
        _items = items
        _selectedItemID = selectedItemID
        _draft = draft
        _selectedReferenceIDs = selectedReferenceIDs
        _addSaveState = addSaveState
        self.onSavedItem = onSavedItem
        self.onRouteChange = onRouteChange
        _detailVariant = State(initialValue: route == .closetDetailBottom ? .bottom : .top)
        _detailPhotoSelection = State(initialValue: nil)
        _detailPhotoGenerations = State(initialValue: [:])
        _isRenamingDetailItem = State(initialValue: false)
        _pendingDetailName = State(initialValue: "")
        _showsDeleteConfirmation = State(initialValue: false)
        _isDeletingDetailItem = State(initialValue: false)
        _detailFitComparison = State(initialValue: nil)
        #if DEBUG
        _detailPhotoTestStates = State(initialValue: [:])
        _detailPhotoTestRejections = State(initialValue: [:])
        _detailPhotoScenarioAppearances = State(initialValue: [:])
        #endif
    }

    var body: some View {
        CoorditScreenScaffold(
            route: route,
            onRouteChange: onRouteChange,
            contentTop: 115,
            contentBottom: 0
        ) { metrics in
            switch route {
            case .closetDetailTop:
                detailScreen(
                    metrics: metrics,
                    variant: detailVariant,
                    item: selectedItem(for: .top),
                    screenIdentifier: route.rawValue
                )
                    .onAppear { detailVariant = .top }
            case .closetDetailBottom:
                detailScreen(
                    metrics: metrics,
                    variant: detailVariant,
                    item: selectedItem(for: .bottom),
                    screenIdentifier: route.rawValue
                )
                    .onAppear { detailVariant = .bottom }
            case .closetAddMethod:
                addMethodScreen(metrics: metrics)
            case .closetAddLink:
                addLinkScreen(metrics: metrics)
            case .closetAddPhoto:
                addPhotoScreen(metrics: metrics)
            case .closetAddManual:
                addManualScreen(metrics: metrics)
            case .closetAddLoading:
                addLoadingScreen(metrics: metrics)
            case .closetAddResult:
                detailScreen(
                    metrics: metrics,
                    variant: selectedItem?.category ?? draft.category,
                    item: selectedItem ?? draft.previewItem,
                    screenIdentifier: route.rawValue
                )
            default:
                overviewScreen(metrics: metrics)
            }
        }
        .task(id: referenceProfileRefreshKey) {
            await backendSession.refreshReferenceFitProfiles()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                await backendSession.refreshReferenceFitProfiles()
            }
        }
    }

    private func overviewScreen(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "CLOSET", metrics: metrics) {
                onRouteChange(.main04)
            }
            .padding(.horizontal, metrics.value(16))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(22)) {
                VStack(alignment: .leading, spacing: metrics.value(12)) {
                    VStack(alignment: .leading, spacing: metrics.value(4)) {
                        Text("\(activeReferenceProfile?.referenceCount ?? 0)개 기준 의류로 계산")
                            .font(CoorditTypography.mona12(size: metrics.value(11)))
                            .foregroundStyle(CoorditClosetColors.navy.opacity(0.48))
                            .accessibilityIdentifier("closet-best-fit-reference-count")
                        Text("100점 핏 사이즈")
                            .font(CoorditTypography.climate2010(size: metrics.value(21)))
                            .foregroundStyle(CoorditClosetColors.navy)
                            .tracking(metrics.value(-0.9))
                    }
                    CoorditClosetSegment(selected: selectedCategory, metrics: metrics) {
                        selectedCategory = $0
                        selectedExactCategory = nil
                    }
                    exactCategoryFilter(metrics: metrics)
                    bestFitMetricsGrid(metrics: metrics)
                }
                .padding(metrics.value(14))
                .background(CoorditClosetColors.card)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))

                CoorditSolidPrimaryButton(title: "보유 의류 추가하기", metrics: metrics) {
                    draft = CoorditClosetDraft()
                    addSaveState.reset()
                    onRouteChange(.closetAddMethod)
                }
                    .accessibilityIdentifier("closet-add-garment")

                searchField(metrics: metrics)
                garmentGrid(metrics: metrics)
                }
                .padding(.top, metrics.value(22))
                .padding(.horizontal, metrics.value(16))
                .padding(
                    .bottom,
                    metrics.value(Main01DesignTokens.Metrics.navHeight + 22)
                )
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
        }
        .accessibilityIdentifier("coordit-screen-closet-overview")
    }

    private var activeReferenceProfile: CoorditReferenceFitProfileResponse? {
        backendSession.referenceFitProfile(for: selectedCategory)
    }

    private var referenceProfileRefreshKey: String {
        selectedReferenceIDs.sorted().joined(separator: ",")
    }

    private var overviewMetrics: [(key: String, value: String, label: String, color: Color)] {
        let measurements = activeReferenceProfile?.measurements
        switch selectedCategory {
        case .top:
            return [
                ("shoulder_width", formattedMeasurement(measurements?.shoulderWidth), "어깨", CoorditClosetColors.navy),
                ("chest_width", formattedMeasurement(measurements?.chestWidth), "가슴단면", CoorditClosetColors.navy),
                ("total_length", formattedMeasurement(measurements?.totalLength), "총장", CoorditClosetColors.navy),
                ("sleeve_length", formattedMeasurement(measurements?.sleeveLength), "소매", CoorditClosetColors.navy),
            ]
        case .bottom:
            return [
                ("waist_width", formattedMeasurement(measurements?.waistWidth), "허리단면", CoorditClosetColors.navy),
                ("hip_width", formattedMeasurement(measurements?.hipWidth), "엉덩이단면", CoorditClosetColors.navy),
                ("rise", formattedMeasurement(measurements?.rise), "밑위", CoorditClosetColors.navy),
                ("outseam", formattedMeasurement(measurements?.outseam), "총장", CoorditClosetColors.navy),
            ]
        }
    }

    private func formattedMeasurement(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) cm"
    }

    private var filteredItems: [CoorditClosetItem] {
        items.filter { item in
            item.category == selectedCategory
                && (selectedExactCategory == nil || item.exactCategory == selectedExactCategory)
                && (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func exactCategoryFilter(metrics: CoorditResponsiveMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.value(7)) {
                categoryChip(title: "전체", category: nil, metrics: metrics)
                ForEach(CoorditFitLabCategory.allCases.filter {
                    $0.garmentKind == (selectedCategory == .top ? .upper : .lower)
                }) { category in
                    categoryChip(title: category.koreanTitle, category: category, metrics: metrics)
                }
            }
        }
        .accessibilityIdentifier("closet-exact-category-filter")
    }

    private func categoryChip(
        title: String,
        category: CoorditFitLabCategory?,
        metrics: CoorditResponsiveMetrics
    ) -> some View {
        let isSelected = selectedExactCategory == category
        return Button(title) { selectedExactCategory = category }
            .font(CoorditTypography.gmarketMedium(size: metrics.value(10)))
            .foregroundStyle(isSelected ? .white : CoorditClosetColors.navy)
            .padding(.horizontal, metrics.value(10))
            .frame(height: metrics.value(28))
            .background(isSelected ? CoorditClosetColors.navy : CoorditClosetColors.field)
            .clipShape(Capsule())
            .coorditPressFeedback()
    }

    private func bestFitMetricsGrid(metrics: CoorditResponsiveMetrics) -> some View {
        let values = overviewMetrics
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: metrics.value(8)), GridItem(.flexible())], spacing: metrics.value(8)) {
            ForEach(values.indices, id: \.self) { index in
                CoorditClosetMetricTile(
                    value: values[index].value,
                    label: values[index].label,
                    color: values[index].color,
                    metrics: metrics
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(values[index].label), \(values[index].value)")
                .accessibilityIdentifier("closet-best-fit-\(values[index].key)")
            }
        }
    }

    func metricsGrid(metrics: CoorditResponsiveMetrics, values: [(String, String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: metrics.value(8)), GridItem(.flexible())], spacing: metrics.value(8)) {
            ForEach(values.indices, id: \.self) { index in
                CoorditClosetMetricTile(
                    value: values[index].0,
                    label: values[index].1,
                    color: values[index].2,
                    metrics: metrics
                )
            }
        }
    }

    private func garmentGrid(metrics: CoorditResponsiveMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: metrics.value(10)), GridItem(.flexible())], spacing: metrics.value(8)) {
            ForEach(filteredItems) { item in
                CoorditClosetGarmentCard(item: item, metrics: metrics) {
                    selectedItemID = item.id
                    onRouteChange(item.route)
                }
            }
        }
    }

    private func searchField(metrics: CoorditResponsiveMetrics) -> some View {
        HStack(spacing: metrics.value(10)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.value(22), weight: .semibold))
                .foregroundStyle(.black)
            TextField("보유 의류를 검색해보세요.", text: $searchText)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                .foregroundStyle(CoorditClosetColors.navy)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, metrics.value(14))
        .frame(height: metrics.value(36))
        .background(CoorditClosetColors.card)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: metrics.value(8), y: metrics.value(3))
        .accessibilityIdentifier("closet-search-field")
    }

    var selectedItem: CoorditClosetItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    private func selectedItem(for category: CoorditClosetCategory) -> CoorditClosetItem {
        if let selectedItem, selectedItem.category == category {
            return selectedItem
        }
        return items.first { $0.category == category } ?? CoorditClosetItem.seedItems[0]
    }

    func loadDetailPhoto(_ pickerItem: PhotosPickerItem, for itemID: String) {
        let generation = advanceDetailPhotoGeneration(for: itemID)

        Task {
            let data = try? await pickerItem.loadTransferable(type: Data.self)
            guard detailPhotoGenerations[itemID] == generation else { return }
            detailPhotoSelection = nil
            guard let data, UIImage(data: data) != nil else { return }
            commitDetailPhoto(data, for: itemID)
        }
    }

    func invalidateDetailPhotoLoad(for itemID: String) {
        _ = advanceDetailPhotoGeneration(for: itemID)
        detailPhotoSelection = nil
    }

    private func advanceDetailPhotoGeneration(for itemID: String) -> Int {
        let generation = (detailPhotoGenerations[itemID] ?? 0) + 1
        detailPhotoGenerations[itemID] = generation
        return generation
    }

    private func commitDetailPhoto(_ data: Data, for itemID: String) {
        if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
            items[itemIndex].imageData = data
        } else if itemID == "closet-draft-preview" {
            draft.garmentImageData = data
        }
    }

    func beginDetailRename(_ item: CoorditClosetItem) {
        pendingDetailName = item.name
        isRenamingDetailItem = true
    }

    func commitDetailName(for itemID: String) {
        let name = pendingDetailName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
            items[itemIndex].name = name
        } else if itemID == "closet-draft-preview" {
            draft.name = name
        }
    }

    #if DEBUG
    var detailPhotoTestScenario: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--coordit-ui-testing") else { return nil }
        guard
            let markerIndex = arguments.firstIndex(of: "--coordit-test-detail-photo-scenario"),
            arguments.indices.contains(arguments.index(after: markerIndex))
        else {
            return nil
        }
        return arguments[arguments.index(after: markerIndex)]
    }

    func runDetailPhotoTestScenario(for itemID: String) {
        guard let scenario = detailPhotoTestScenario else { return }
        let appearance = (detailPhotoScenarioAppearances[itemID] ?? 0) + 1
        detailPhotoScenarioAppearances[itemID] = appearance

        switch scenario {
        case "displayed-item-persistence":
            guard appearance == 1 else { return }
            startDetailPhotoTestLoad(
                data: detailPhotoTestImageData(color: .systemBlue),
                token: "valid-b",
                for: itemID,
                delayNanoseconds: 50_000_000
            )
        case "corrupt-and-stale":
            if appearance == 1 {
                applyDetailPhotoTestPayload(
                    detailPhotoTestImageData(color: .systemRed),
                    token: "valid-a",
                    for: itemID,
                    generation: advanceDetailPhotoGeneration(for: itemID)
                )
                startDelayedStaleDetailPhotoTestLoad(
                    data: detailPhotoTestImageData(color: .systemRed),
                    token: "stale-a",
                    for: itemID,
                    afterCommittedToken: "valid-b"
                )
                detailPhotoTestStates[itemID] = "\(itemID)-valid-a-delayed-pending"
            } else if appearance == 2 {
                applyDetailPhotoTestPayload(
                    Data("not-an-image".utf8),
                    token: "corrupt",
                    for: itemID,
                    generation: advanceDetailPhotoGeneration(for: itemID)
                )
                startDetailPhotoTestLoad(
                    data: detailPhotoTestImageData(color: .systemBlue),
                    token: "valid-b",
                    for: itemID,
                    delayNanoseconds: 50_000_000
                )
            }
        case "draft-preview-fallback":
            guard appearance == 1 else { return }
            startDetailPhotoTestLoad(
                data: detailPhotoTestImageData(color: .systemBlue),
                token: "valid-b",
                for: itemID,
                delayNanoseconds: 50_000_000
            )
        case "real-link-add-result-item":
            guard appearance == 1,
                  itemID != "closet-draft-preview",
                  items.contains(where: { $0.id == itemID }) else { return }
            startDetailPhotoTestLoad(
                data: detailPhotoTestImageData(color: .systemBlue),
                token: "real-link-valid-b",
                for: itemID,
                delayNanoseconds: 50_000_000
            )
        default:
            break
        }
    }

    private func startDetailPhotoTestLoad(
        data: Data,
        token: String,
        for itemID: String,
        delayNanoseconds: UInt64
    ) {
        let generation = advanceDetailPhotoGeneration(for: itemID)
        Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            applyDetailPhotoTestPayload(data, token: token, for: itemID, generation: generation)
        }
    }

    private func startDelayedStaleDetailPhotoTestLoad(
        data: Data,
        token: String,
        for itemID: String,
        afterCommittedToken: String
    ) {
        let generation = advanceDetailPhotoGeneration(for: itemID)
        let committedState = "\(itemID)-\(afterCommittedToken)"

        Task {
            for _ in 0..<600 {
                if detailPhotoTestStates[itemID] == committedState {
                    applyDetailPhotoTestPayload(data, token: token, for: itemID, generation: generation)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            applyDetailPhotoTestPayload(data, token: token, for: itemID, generation: generation)
        }
    }

    private func applyDetailPhotoTestPayload(
        _ data: Data,
        token: String,
        for itemID: String,
        generation: Int
    ) {
        guard detailPhotoGenerations[itemID] == generation else {
            detailPhotoTestRejections[itemID] = "\(itemID)-\(token)-rejected"
            return
        }
        guard UIImage(data: data) != nil else { return }
        commitDetailPhoto(data, for: itemID)
        detailPhotoTestStates[itemID] = "\(itemID)-\(token)"
    }

    private func detailPhotoTestImageData(color: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 12, height: 12)))
        }
    }
    #endif

}
#endif
