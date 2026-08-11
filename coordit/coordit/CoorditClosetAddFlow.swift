import PhotosUI
import SwiftUI

#if os(iOS)
import AVFoundation
enum CoorditClosetAddMethod: String, CaseIterable, Identifiable {
    case link
    case photo
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .link: "링크로 불러오기"
        case .photo: "사진으로 첨부하기"
        case .manual: "직접 입력하기"
        }
    }

    var description: String {
        switch self {
        case .link: "상품 링크에서 사이즈 정보를 불러와요."
        case .photo: "사이즈표 사진을 분석해요."
        case .manual: "실측 사이즈를 직접 입력해요."
        }
    }

    var symbolName: String {
        switch self {
        case .link: "link"
        case .photo: "photo.on.rectangle.angled"
        case .manual: "ruler"
        }
    }

    var route: CoorditFrameRoute {
        switch self {
        case .link: .closetAddLink
        case .photo: .closetAddPhoto
        case .manual: .closetAddManual
        }
    }
}

struct CoorditClosetDraft {
    var method: CoorditClosetAddMethod?
    var name = ""
    var category: CoorditClosetCategory = .top
    var exactCategory: CoorditFitLabCategory = .tshirt
    var productLink = ""
    var garmentImageData: Data?
    var sizeChartImageData: Data?
    var extractedSizeRows: [CoorditClosetOCRSizeRow] = []
    var selectedSizeRowID: UUID?
    var measurement1 = ""
    var measurement2 = ""
    var measurement3 = ""
    var measurement4 = ""

    var selectedSizeRow: CoorditClosetOCRSizeRow? {
        extractedSizeRows.first { $0.id == selectedSizeRowID }
    }

    var score: Int {
        switch method {
        case .link: 93
        case .photo: 91
        case .manual: 96
        case nil: 92
        }
    }

    var previewItem: CoorditClosetItem {
        CoorditClosetItem(
            id: "closet-draft-preview",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "새로운 의류" : name,
            category: category,
            exactCategory: exactCategory,
            score: Double(score),
            scoreColor: CoorditClosetColors.blue,
            route: .closetAddResult,
            imageData: garmentImageData,
            sizeChart: CoorditClosetSizeChart(
                sizeLabel: selectedSizeRow?.label,
                measurements: clothingSizeRequest.measurements
            )
        )
    }
}

extension CoorditClosetFamilyView {
    func addMethodScreen(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditClosetAddMethodScreen(metrics: metrics) {
            resetPendingSave()
            onRouteChange(.closetOverview)
        } onSelect: { method in
            resetPendingSave()
            draft.method = method
            onRouteChange(method.route)
        }
    }

    func addLinkScreen(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditClosetLinkInputScreen(draft: $draft, metrics: metrics) {
            resetPendingSave()
            onRouteChange(.closetAddMethod)
        } onSubmit: {
            submitDraft()
        } onSwitchToPhoto: {
            draft.method = .photo
            onRouteChange(.closetAddPhoto)
        } onSwitchToManual: {
            draft.method = .manual
            onRouteChange(.closetAddManual)
        }
    }

    func addPhotoScreen(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditClosetPhotoInputScreen(draft: $draft, metrics: metrics) {
            resetPendingSave()
            onRouteChange(.closetAddMethod)
        } onSubmit: {
            submitDraft()
        } onSwitchToManual: {
            draft.method = .manual
            onRouteChange(.closetAddManual)
        }
    }

    func addManualScreen(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditClosetManualInputScreen(draft: $draft, metrics: metrics) {
            resetPendingSave()
            onRouteChange(.closetAddMethod)
        } onSubmit: {
            submitDraft()
        }
    }

    func addLoadingScreen(metrics: CoorditResponsiveMetrics) -> some View {
        CoorditClosetAddLoadingScreen(
            metrics: metrics,
            isSaving: addSaveState.isSaving,
            errorMessage: addSaveState.errorMessage
        ) {
            resetPendingSave()
            onRouteChange(.closetOverview)
        } onRetry: {
            submitDraft()
        }
    }

    private func submitDraft() {
        guard !addSaveState.isSaving else { return }
        let submittedDraft = draft
        let trimmedName = submittedDraft.trimmedName
        guard !trimmedName.isEmpty else { return }

        let item = CoorditClosetItem(
            id: UUID().uuidString,
            name: trimmedName,
            category: submittedDraft.category,
            exactCategory: submittedDraft.exactCategory,
            score: Double(submittedDraft.score),
            scoreColor: CoorditClosetColors.blue,
            route: .closetAddResult,
            imageData: submittedDraft.garmentImageData,
            sizeChart: CoorditClosetSizeChart(
                sizeLabel: submittedDraft.selectedSizeRow?.label,
                measurements: submittedDraft.clothingSizeRequest.measurements
            )
        )

        let idempotencyKey = addSaveState.idempotencyKey ?? UUID().uuidString
        addSaveState.idempotencyKey = idempotencyKey
        let requestGeneration = addSaveState.beginSave()
        onRouteChange(.closetAddLoading)

        Task { @MainActor in
            guard let saved = await backendSession.saveClothing(
                from: submittedDraft,
                idempotencyKey: idempotencyKey
            ) else {
                guard addSaveState.isCurrent(requestGeneration) else { return }
                addSaveState.isSaving = false
                addSaveState.errorMessage = backendSession.statusText.isEmpty
                    ? "보유 의류를 저장하지 못했어요. 연결을 확인한 뒤 다시 시도해 주세요."
                    : backendSession.statusText
                return
            }
            guard addSaveState.isCurrent(requestGeneration) else { return }
            addSaveState.isSaving = false
            var savedItem = item
            savedItem.backendClothingItemId = saved.clothingItemId
            savedItem.sizeChart = saved.sizeChart
            items.insert(savedItem, at: 0)
            selectedItemID = savedItem.id
            selectedCategory = savedItem.category
            resetPendingSave()
            onRouteChange(.closetAddResult)
        }
    }

    private func resetPendingSave() {
        addSaveState.reset()
    }
}

private struct CoorditClosetAddMethodScreen: View {
    let metrics: CoorditResponsiveMetrics
    let onBack: () -> Void
    let onSelect: (CoorditClosetAddMethod) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "ADD CLOTHES", metrics: metrics, horizontalOutset: 6, onBack: onBack)
                .padding(.horizontal, metrics.value(22))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(18)) {
                VStack(alignment: .leading, spacing: metrics.value(5)) {
                    Text("어떻게 추가할까요?")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(20)))
                        .foregroundStyle(CoorditClosetColors.navy)
                    Text("가지고 있는 정보에 맞는 방식을 선택해주세요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(11)))
                        .foregroundStyle(CoorditClosetColors.navy.opacity(0.46))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.value(5))

                VStack(spacing: metrics.value(11)) {
                    ForEach(CoorditClosetAddMethod.allCases) { method in
                        Button {
                            onSelect(method)
                        } label: {
                            HStack(spacing: metrics.value(14)) {
                                Image(systemName: method.symbolName)
                                    .font(.system(size: metrics.value(23), weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: metrics.value(50), height: metrics.value(50))
                                    .background(CoorditClosetColors.navy)
                                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(9)))

                                VStack(alignment: .leading, spacing: metrics.value(5)) {
                                    Text(method.title)
                                        .font(CoorditTypography.gmarketBold(size: metrics.value(15)))
                                        .foregroundStyle(.black)
                                    Text(method.description)
                                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                                        .foregroundStyle(CoorditClosetColors.navy.opacity(0.48))
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: metrics.value(16), weight: .bold))
                                    .foregroundStyle(CoorditClosetColors.navy.opacity(0.34))
                            }
                            .padding(metrics.value(13))
                            .frame(maxWidth: .infinity, minHeight: metrics.value(84))
                            .background(CoorditClosetColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(9)))
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.value(9))
                                    .stroke(CoorditClosetColors.navy.opacity(0.08), lineWidth: metrics.value(0.8))
                            )
                            .shadow(color: .black.opacity(0.06), radius: metrics.value(8), y: metrics.value(3))
                        }
                        .coorditPressFeedback()
                        .accessibilityIdentifier("closet-add-method-\(method.rawValue)")
                    }
                }
                }
                .padding(.top, metrics.value(18))
                .padding(.horizontal, metrics.value(22))
                .padding(
                    .bottom,
                    metrics.value(Main01DesignTokens.Metrics.navHeight + 28)
                )
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
        }
        .accessibilityIdentifier("coordit-screen-closet-add-method")
    }
}

private struct CoorditClosetLinkInputScreen: View {
    @Binding var draft: CoorditClosetDraft
    let metrics: CoorditResponsiveMetrics
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onSwitchToPhoto: () -> Void
    let onSwitchToManual: () -> Void

    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @State private var isExtracting = false
    @State private var extractionError: String?

    @FocusState private var isLinkFocused: Bool

    private var isReady: Bool {
        if draft.extractedSizeRows.isEmpty {
            return !draft.productLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return draft.selectedSizeRow != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "LINK INPUT", metrics: metrics, horizontalOutset: 6, onBack: onBack)
                .padding(.horizontal, metrics.value(22))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(16)) {
                CoorditClosetBasicsCard(draft: $draft, metrics: metrics, showsName: false)

                CoorditClosetFormCard(title: "상품 링크", subtitle: "사이즈 정보가 있는 상품 페이지 주소를 붙여넣어 주세요.", metrics: metrics) {
                    HStack(spacing: metrics.value(10)) {
                        Image(systemName: "link")
                            .foregroundStyle(CoorditClosetColors.navy.opacity(0.56))
                        TextField("https://", text: $draft.productLink)
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isLinkFocused)
                            .onTapGesture { isLinkFocused = true }
                            .accessibilityIdentifier("closet-product-link")
                    }
                    .padding(.horizontal, metrics.value(13))
                    .frame(height: metrics.value(45))
                    .background(CoorditClosetColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
                }

                if let extractionError {
                    CoorditClosetFormCard(title: "링크에서 표를 찾지 못했어요", subtitle: extractionError, metrics: metrics) {
                        HStack(spacing: metrics.value(8)) {
                            Button("사진 OCR로 입력", action: onSwitchToPhoto)
                                .buttonStyle(
                                    CoorditContentActionButtonStyle(
                                        prominence: .primary,
                                        height: metrics.value(48),
                                        cornerRadius: metrics.value(7),
                                        fontSize: metrics.value(12)
                                    )
                                )
                            Button("직접 입력", action: onSwitchToManual)
                                .buttonStyle(
                                    CoorditContentActionButtonStyle(
                                        prominence: .secondary,
                                        height: metrics.value(48),
                                        cornerRadius: metrics.value(7),
                                        fontSize: metrics.value(12)
                                    )
                                )
                        }
                    }
                    .accessibilityIdentifier("closet-link-extraction-error")
                }

                if !draft.extractedSizeRows.isEmpty {
                    CoorditClosetFormCard(
                        title: "불러온 상품",
                        subtitle: "상품명은 링크에서 자동으로 가져왔어요.",
                        metrics: metrics
                    ) {
                        Text(draft.name)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(14)))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, metrics.value(13))
                            .frame(minHeight: metrics.value(45))
                            .background(CoorditClosetColors.field)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
                            .accessibilityIdentifier("closet-link-product-name")
                    }

                    CoorditClosetFormCard(
                        title: "내 사이즈 선택",
                        subtitle: "구매해서 보유 중인 사이즈 한 개를 선택해 주세요.",
                        metrics: metrics
                    ) {
                        VStack(spacing: metrics.value(8)) {
                            ForEach(draft.extractedSizeRows) { row in
                                linkSizeRow(row)
                            }
                        }
                    }
                }

                Text(draft.selectedSizeRow?.label ?? "")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityLabel(draft.selectedSizeRow?.label ?? "")
                    .accessibilityIdentifier("closet-selected-size-label")

                CoorditClosetSubmitButton(
                    title: submitTitle,
                    isEnabled: isReady && !isExtracting,
                    metrics: metrics,
                    action: draft.extractedSizeRows.isEmpty ? extractLink : onSubmit
                )
                }
                .padding(.top, metrics.value(16))
                .padding(.horizontal, metrics.value(22))
                .padding(
                    .bottom,
                    metrics.value(Main01DesignTokens.Metrics.navHeight + 28)
                )
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
            .scrollDismissesKeyboard(.immediately)
        }
        .accessibilityIdentifier("coordit-screen-closet-add-link")
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--coordit-test-link-extraction-failure") {
                draft.name = "Link Shirt"
                draft.productLink = "https://shop.example/not-readable"
            }
#endif
        }
    }

    private func extractLink() {
        isLinkFocused = false
        extractionError = nil
        guard let url = validatedURL else {
            extractionError = "HTTP 또는 HTTPS 상품 링크인지 확인해 주세요."
            return
        }
        isExtracting = true
        Task { @MainActor in
            defer { isExtracting = false }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--coordit-test-link-extraction-failure") {
                extractionError = "이 페이지의 사이즈표 형식을 읽지 못했어요."
                return
            }
#endif
            do {
                let response = try await backendSession.prefillClosetProduct(
                    from: url,
                    category: draft.exactCategory
                )
                draft.name = response.productName
                draft.category = response.category.garmentKind == .upper ? .top : .bottom
                draft.exactCategory = response.category
                draft.extractedSizeRows = response.sizes.map { size in
                    CoorditClosetOCRSizeRow(
                        label: size.sizeLabel,
                        measurements: [
                            .shoulderWidth: size.shoulderWidth,
                            .chestWidth: size.chestWidth,
                            .totalLength: size.totalLength,
                            .sleeveLength: size.sleeveLength,
                            .waistWidth: size.waistWidth,
                            .hipWidth: size.hipWidth,
                            .rise: size.rise,
                            .outseam: size.outseam,
                        ].compactMapValues { $0 }
                    )
                }
                draft.selectedSizeRowID = nil
                guard !draft.extractedSizeRows.isEmpty else {
                    extractionError = "링크에서 사이즈 행을 찾지 못했어요."
                    return
                }
            } catch {
                extractionError = "추출에 실패했어요. 사진 OCR이나 직접 입력으로 계속할 수 있어요."
            }
        }
    }

    private var submitTitle: String {
        if isExtracting { return "링크 분석 중…" }
        return draft.extractedSizeRows.isEmpty ? "링크 분석하기" : "선택한 사이즈로 등록"
    }

    private func linkSizeRow(_ row: CoorditClosetOCRSizeRow) -> some View {
        let isSelected = draft.selectedSizeRowID == row.id
        return Button {
            draft.selectedSizeRowID = row.id
        } label: {
            HStack(spacing: metrics.value(10)) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: metrics.value(20), weight: .semibold))
                    .foregroundStyle(CoorditClosetColors.navy)
                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text(row.label)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14)))
                        .foregroundStyle(.black)
                    Text(row.measurements.map { key, value in
                        "\(measurementTitle(key)) \(value.formatted(.number.precision(.fractionLength(0...1))))"
                    }.sorted().joined(separator: " · "))
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                        .foregroundStyle(CoorditClosetColors.navy.opacity(0.55))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(metrics.value(11))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CoorditClosetColors.navy.opacity(0.08) : CoorditClosetColors.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(8))
                    .stroke(isSelected ? CoorditClosetColors.navy : .clear, lineWidth: 1.2)
            )
        }
        .coorditPressFeedback()
        .accessibilityIdentifier("closet-link-size-row-\(row.label)")
    }

    private func measurementTitle(_ key: CoorditFitLabMeasurementKey) -> String {
        switch key {
        case .shoulderWidth: "어깨"
        case .chestWidth: "가슴단면"
        case .totalLength: "총장"
        case .sleeveLength: "소매"
        case .waistWidth: "허리단면"
        case .hipWidth: "엉덩이단면"
        case .rise: "밑위"
        case .outseam: "총장"
        }
    }

    private var validatedURL: URL? {
        let trimmed = draft.productLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else { return nil }
        return components.url
    }
}

private struct CoorditClosetPhotoInputScreen: View {
    @Binding var draft: CoorditClosetDraft
    let metrics: CoorditResponsiveMetrics
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onSwitchToManual: () -> Void

    @State private var pendingCropImage: UIImage?
    @State private var isCameraPresented = false
    @State private var isRecognizing = false
    @State private var recognitionError: String?

    private var isReady: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.sizeChartImageData != nil &&
        draft.selectedSizeRow != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "PHOTO INPUT", metrics: metrics, horizontalOutset: 6, onBack: onBack)
                .padding(.horizontal, metrics.value(22))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(16)) {
                CoorditClosetBasicsCard(draft: $draft, metrics: metrics)

                CoorditClosetFormCard(title: "사진 첨부", subtitle: "사진을 고른 다음 표 부분만 정확히 잘라주세요.", metrics: metrics) {
                    VStack(spacing: metrics.value(9)) {
                        CoorditClosetPhotoPickerSlot(
                            title: "사이즈표",
                            subtitle: "선택 후 표 영역 자르기",
                            imageData: $draft.sizeChartImageData,
                            metrics: metrics,
                            identifier: "closet-size-chart-photo",
                            onImageSelected: { pendingCropImage = $0 }
                        )
                        Button(action: requestCamera) {
                            Label("카메라로 촬영", systemImage: "camera")
                        }
                        .buttonStyle(
                            CoorditContentActionButtonStyle(
                                prominence: .secondary,
                                height: metrics.value(48),
                                cornerRadius: metrics.value(7),
                                fontSize: metrics.value(12)
                            )
                        )
                        .accessibilityIdentifier("closet-size-chart-camera")
                    }
                }

                if isRecognizing {
                    ProgressView("사이즈별 표를 읽는 중…")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(11)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let recognitionError {
                    CoorditClosetFormCard(title: "표를 읽지 못했어요", subtitle: recognitionError, metrics: metrics) {
                        VStack(alignment: .leading, spacing: metrics.value(8)) {
                            Text("표의 첫 행과 모든 사이즈 행이 포함되게 다시 잘라보거나 직접 입력해 주세요.")
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(10)))
                                .foregroundStyle(CoorditClosetColors.navy.opacity(0.58))
                            Button("직접 입력으로 전환", action: onSwitchToManual)
                                .buttonStyle(
                                    CoorditContentActionButtonStyle(
                                        prominence: .secondary,
                                        height: metrics.value(48),
                                        cornerRadius: metrics.value(7),
                                        fontSize: metrics.value(12)
                                    )
                                )
                        }
                    }
                }

                if !draft.extractedSizeRows.isEmpty {
                    CoorditClosetFormCard(
                        title: "내 사이즈 선택",
                        subtitle: "표에서 등록할 사이즈 한 개를 골라주세요. 표기명은 원문 그대로 저장돼요.",
                        metrics: metrics
                    ) {
                        VStack(spacing: metrics.value(8)) {
                            ForEach(draft.extractedSizeRows) { row in
                                sizeRow(row)
                            }
                        }
                        Button("OCR 값이 다르면 직접 입력", action: onSwitchToManual)
                            .buttonStyle(
                                CoorditContentActionButtonStyle(
                                    prominence: .secondary,
                                    height: metrics.value(48),
                                    cornerRadius: metrics.value(7),
                                    fontSize: metrics.value(12)
                                )
                            )
                    }
                }

                Text(draft.selectedSizeRow?.label ?? "")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityLabel(draft.selectedSizeRow?.label ?? "")
                    .accessibilityIdentifier("closet-selected-size-label")

                CoorditClosetSubmitButton(title: "사진 분석하기", isEnabled: isReady, metrics: metrics, action: onSubmit)
                }
                .padding(.top, metrics.value(16))
                .padding(.horizontal, metrics.value(22))
                .padding(.bottom, metrics.value(128))
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
            .scrollDismissesKeyboard(.immediately)
        }
        .accessibilityIdentifier("coordit-screen-closet-add-photo")
        .task {
            injectSizeChartFixtureIfRequested()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { pendingCropImage != nil },
                set: { if !$0 { pendingCropImage = nil } }
            )
        ) {
            if let pendingCropImage {
                CoorditSizeChartCropView(image: pendingCropImage) {
                    self.pendingCropImage = nil
                } onConfirm: { cropped in
                    self.pendingCropImage = nil
                    acceptCroppedImage(cropped)
                }
            }
        }
        .sheet(isPresented: $isCameraPresented) {
            CoorditFitLabCameraPicker { image in
                isCameraPresented = false
                if let image {
                    pendingCropImage = image
                }
            }
            .ignoresSafeArea()
        }
    }

    private func sizeRow(_ row: CoorditClosetOCRSizeRow) -> some View {
        let isSelected = draft.selectedSizeRowID == row.id
        return Button {
            draft.selectedSizeRowID = row.id
        } label: {
            HStack(spacing: metrics.value(10)) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: metrics.value(20), weight: .semibold))
                    .foregroundStyle(CoorditClosetColors.navy)
                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text(row.label)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14)))
                        .foregroundStyle(.black)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: metrics.value(3)
                    ) {
                        ForEach(row.measurements.sorted(by: { measurementTitle($0.key) < measurementTitle($1.key) }), id: \.key) { key, value in
                            Text("\(measurementTitle(key)) \(value.formatted(.number.precision(.fractionLength(0...1))))")
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                                .foregroundStyle(CoorditClosetColors.navy.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(metrics.value(11))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CoorditClosetColors.navy.opacity(0.08) : CoorditClosetColors.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
            .overlay(RoundedRectangle(cornerRadius: metrics.value(8)).stroke(isSelected ? CoorditClosetColors.navy : .clear, lineWidth: 1.2))
        }
        .coorditPressFeedback()
        .accessibilityIdentifier("closet-ocr-size-row-\(row.label)")
    }

    private func acceptCroppedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.96) else {
            recognitionError = "잘라낸 이미지를 처리하지 못했어요."
            return
        }
        draft.sizeChartImageData = data
        draft.extractedSizeRows = []
        draft.selectedSizeRowID = nil
        recognitionError = nil

        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                let rows = try await CoorditFitLabSizeExtractor.closetRows(from: data)
                guard !rows.isEmpty else {
                    recognitionError = "사이즈 행을 찾지 못했어요."
                    return
                }
                draft.extractedSizeRows = rows
                if let kind = rows.first?.measurements.keys.first?.garmentKind {
                    draft.category = kind == .upper ? .top : .bottom
                    if draft.exactCategory.garmentKind != kind {
                        draft.exactCategory = kind == .upper ? .tshirt : .pants
                    }
                }
            } catch {
                recognitionError = "표 머리글과 숫자가 선명하게 보이도록 다시 잘라주세요."
            }
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            recognitionError = "이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함에서 선택해 주세요."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            Task { @MainActor in
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                if allowed {
                    isCameraPresented = true
                } else {
                    recognitionError = "카메라 권한이 필요해요. 사진 보관함 선택이나 직접 입력을 이용해 주세요."
                }
            }
        case .denied, .restricted:
            recognitionError = "카메라 권한이 필요해요. 사진 보관함 선택이나 직접 입력을 이용해 주세요."
        @unknown default:
            recognitionError = "카메라를 열지 못했어요. 사진 보관함에서 선택해 주세요."
        }
    }

    private func injectSizeChartFixtureIfRequested() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--coordit-test-ocr-crop-and-rows"), pendingCropImage == nil, draft.sizeChartImageData == nil {
            draft.name = "OCR Pants"
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
            pendingCropImage = renderer.image { context in
                UIColor.systemGray6.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                UIColor.white.setFill()
                context.fill(CGRect(x: 70, y: 250, width: 760, height: 650))
                let columns: [CGFloat] = [70, 220, 380, 540, 690, 830]
                let rows: [CGFloat] = [250, 410, 570, 730, 900]
                context.cgContext.setStrokeColor(UIColor.systemGray3.cgColor)
                context.cgContext.setLineWidth(3)
                for x in columns {
                    context.cgContext.move(to: CGPoint(x: x, y: 250))
                    context.cgContext.addLine(to: CGPoint(x: x, y: 900))
                }
                for y in rows {
                    context.cgContext.move(to: CGPoint(x: 70, y: y))
                    context.cgContext.addLine(to: CGPoint(x: 830, y: y))
                }
                context.cgContext.strokePath()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: UIColor.black,
                ]
                let labels = [
                    ["SIZE", "WAIST", "HIP", "RISE", "OUT"],
                    ["W32", "41", "52", "30", "103"],
                    ["FREE", "43", "54", "31", "104"],
                ]
                for (rowIndex, labelsRow) in labels.enumerated() {
                    for (columnIndex, label) in labelsRow.enumerated() {
                        (label as NSString).draw(
                            at: CGPoint(x: columns[columnIndex] + 18, y: rows[rowIndex] + 58),
                            withAttributes: attributes
                        )
                    }
                }
            }
            return
        }
        guard arguments.contains("--coordit-ui-testing"),
              arguments.contains("--coordit-test-valid-size-chart"),
              draft.sizeChartImageData == nil,
              let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="),
              UIImage(data: data) != nil else { return }
        draft.sizeChartImageData = data
        draft.extractedSizeRows = Self.testRows
        draft.selectedSizeRowID = draft.extractedSizeRows.first?.id
#endif
    }

    private func measurementTitle(_ key: CoorditFitLabMeasurementKey) -> String {
        switch key {
        case .shoulderWidth: "어깨"
        case .chestWidth: "가슴"
        case .totalLength: "총장"
        case .sleeveLength: "소매"
        case .waistWidth: "허리"
        case .hipWidth: "엉덩이"
        case .rise: "밑위"
        case .outseam: "아웃심"
        }
    }

#if DEBUG
    private static var testRows: [CoorditClosetOCRSizeRow] {
        [
            CoorditClosetOCRSizeRow(label: "W32", measurements: [.waistWidth: 41, .hipWidth: 52, .rise: 30, .outseam: 103]),
            CoorditClosetOCRSizeRow(label: "FREE", measurements: [.waistWidth: 43, .hipWidth: 54, .rise: 31, .outseam: 104]),
        ]
    }
#endif
}

private struct CoorditClosetManualInputScreen: View {
    @Binding var draft: CoorditClosetDraft
    let metrics: CoorditResponsiveMetrics
    let onBack: () -> Void
    let onSubmit: () -> Void
    @FocusState private var focusedMeasurement: Int?

    private var measurementFields: [(String, WritableKeyPath<CoorditClosetDraft, String>)] {
        switch draft.category {
        case .top:
            [("어깨", \.measurement1), ("가슴", \.measurement2), ("총장", \.measurement3), ("소매", \.measurement4)]
        case .bottom:
            [("허리", \.measurement1), ("엉덩이", \.measurement2), ("밑위", \.measurement3), ("아웃심", \.measurement4)]
        }
    }

    private var isReady: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        measurementFields.allSatisfy { !draft[keyPath: $0.1].isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "MANUAL INPUT", metrics: metrics, horizontalOutset: 6, onBack: onBack)
                .padding(.horizontal, metrics.value(22))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(16)) {
                CoorditClosetBasicsCard(draft: $draft, metrics: metrics)

                CoorditClosetFormCard(title: "실측 사이즈", subtitle: "단위는 cm로 입력해주세요.", metrics: metrics) {
                    VStack(spacing: metrics.value(8)) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: metrics.value(8)) {
                                measurementField(index: row * 2)
                                measurementField(index: row * 2 + 1)
                            }
                        }
                    }
                }

                CoorditClosetSubmitButton(title: "보유 의류 등록하기", isEnabled: isReady, metrics: metrics, action: onSubmit)
                }
                .padding(.top, metrics.value(16))
                .padding(.horizontal, metrics.value(22))
                .padding(
                    .bottom,
                    metrics.value(Main01DesignTokens.Metrics.navHeight + 28)
                )
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
            .scrollDismissesKeyboard(.immediately)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") {
                    focusedMeasurement = nil
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                    .accessibilityIdentifier("closet-keyboard-done")
            }
        }
        .accessibilityIdentifier("coordit-screen-closet-add-manual")
    }

    private func measurementField(index: Int) -> some View {
        let field = measurementFields[index]
        return VStack(alignment: .leading, spacing: metrics.value(5)) {
            Text(field.0)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                .foregroundStyle(CoorditClosetColors.navy.opacity(0.5))
            HStack(spacing: metrics.value(4)) {
                TextField(
                    "0.0",
                    text: Binding(
                        get: { draft[keyPath: field.1] },
                        set: { draft[keyPath: field.1] = $0 }
                    )
                )
                .font(CoorditTypography.gmarketBold(size: metrics.value(14)))
                .keyboardType(.decimalPad)
                .focused($focusedMeasurement, equals: index)
                .accessibilityIdentifier("closet-manual-measurement-\(index)")
                Text("cm")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                    .foregroundStyle(CoorditClosetColors.navy.opacity(0.36))
            }
            .padding(.horizontal, metrics.value(10))
            .frame(height: metrics.value(42))
            .background(CoorditClosetColors.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CoorditClosetAddLoadingScreen: View {
    let metrics: CoorditResponsiveMetrics
    let isSaving: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let loadingCenterY = min(
                max(proxy.size.height * 0.38, metrics.value(360)),
                proxy.size.height - metrics.value(285)
            )

            ZStack(alignment: .top) {
                CoorditClosetTitleBar(title: "FIT CHECK", metrics: metrics, horizontalOutset: 6, onBack: onBack)
                    .padding(.horizontal, metrics.value(22))

                VStack(spacing: metrics.value(13)) {
                    if isSaving {
                        CoorditOrbitLoadingIndicator(metrics: metrics)
                        Text("보유 의류를 등록하고 있어요")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(15)))
                            .foregroundStyle(Color.black.opacity(0.76))
                        Text("선택한 사이즈와 실측 정보를 옷장에 저장하고 있어요.")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                            .foregroundStyle(CoorditClosetColors.navy.opacity(0.42))
                            .multilineTextAlignment(.center)
                    } else if let errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: metrics.value(30), weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("저장하지 못했어요")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(15)))
                            .foregroundStyle(Color.black.opacity(0.76))
                        Text(errorMessage)
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                            .foregroundStyle(CoorditClosetColors.navy.opacity(0.42))
                            .multilineTextAlignment(.center)
                        Button("다시 시도", action: onRetry)
                            .buttonStyle(
                                CoorditContentActionButtonStyle(
                                    prominence: .primary,
                                    height: metrics.value(44),
                                    cornerRadius: metrics.value(7),
                                    fontSize: metrics.value(13)
                                )
                            )
                            .accessibilityIdentifier("coordit-closet-save-retry")
                    }
                }
                .frame(width: proxy.size.width - metrics.value(44))
                .position(x: proxy.size.width / 2, y: loadingCenterY)
            }
        }
        .accessibilityIdentifier("coordit-screen-closet-add-loading")
    }
}

private struct CoorditClosetBasicsCard: View {
    @Binding var draft: CoorditClosetDraft
    let metrics: CoorditResponsiveMetrics
    var showsName = true

    @FocusState private var isNameFocused: Bool

    var body: some View {
        CoorditClosetFormCard(
            title: showsName ? "기본 정보" : "옷 종류",
            subtitle: showsName ? "옷장에 표시할 이름과 종류를 입력해주세요." : "링크를 분석하기 전에 옷 종류를 선택해 주세요.",
            metrics: metrics
        ) {
            if showsName {
                TextField("의류 이름", text: $draft.name)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFocused = false }
                    .onTapGesture { isNameFocused = true }
                    .padding(.horizontal, metrics.value(13))
                    .frame(height: metrics.value(45))
                    .background(CoorditClosetColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
                    .accessibilityIdentifier("closet-garment-name")
            }

            CoorditClosetSegment(selected: draft.category, metrics: metrics) {
                draft.category = $0
                if draft.exactCategory.garmentKind != ($0 == .top ? .upper : .lower) {
                    draft.exactCategory = $0 == .top ? .tshirt : .pants
                }
            }

            Picker("세부 카테고리", selection: $draft.exactCategory) {
                ForEach(CoorditFitLabCategory.allCases.filter {
                    $0.garmentKind == (draft.category == .top ? .upper : .lower)
                }) { category in
                    Text(category.koreanTitle)
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                        .tag(category)
                }
            }
            .pickerStyle(.menu)
            .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
            .tint(CoorditClosetColors.navy)
            .padding(.horizontal, metrics.value(13))
            .frame(maxWidth: .infinity, minHeight: metrics.value(45), alignment: .leading)
            .background(CoorditClosetColors.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
            .accessibilityIdentifier("closet-exact-category-picker")
        }
    }
}

private struct CoorditClosetFormCard<Content: View>: View {
    let title: String
    let subtitle: String
    let metrics: CoorditResponsiveMetrics
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, metrics: CoorditResponsiveMetrics, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(11)) {
            VStack(alignment: .leading, spacing: metrics.value(4)) {
                Text(title)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(15)))
                    .foregroundStyle(.black)
                Text(subtitle)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(9)))
                    .foregroundStyle(CoorditClosetColors.navy.opacity(0.44))
            }
            content
        }
        .padding(metrics.value(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditClosetColors.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(9))
                .stroke(CoorditClosetColors.navy.opacity(0.07), lineWidth: metrics.value(0.8))
        )
    }
}

private struct CoorditClosetPhotoPickerSlot: View {
    let title: String
    let subtitle: String
    @Binding var imageData: Data?
    let metrics: CoorditResponsiveMetrics
    let identifier: String
    let onImageSelected: (UIImage) -> Void

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.value(8))
                        .fill(CoorditClosetColors.field)

                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
                            .overlay(alignment: .bottom) {
                                Text("변경하기")
                                    .font(CoorditTypography.gmarketBold(size: metrics.value(9)))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, metrics.value(10))
                                    .frame(height: metrics.value(24))
                                    .background(CoorditClosetColors.navy.opacity(0.82))
                                    .clipShape(Capsule())
                                    .padding(.bottom, metrics.value(8))
                            }
                    } else {
                        VStack(spacing: metrics.value(7)) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: metrics.value(25), weight: .semibold))
                                .foregroundStyle(CoorditClosetColors.navy)
                            Text(title)
                                .font(CoorditTypography.gmarketBold(size: metrics.value(12)))
                                .foregroundStyle(.black)
                            Text(subtitle)
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(8)))
                                .foregroundStyle(CoorditClosetColors.navy.opacity(0.4))
                                .multilineTextAlignment(.center)
                        }
                        .padding(metrics.value(8))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(8))
                    .stroke(style: StrokeStyle(lineWidth: metrics.value(1), dash: [metrics.value(5)]))
                    .foregroundStyle(CoorditClosetColors.navy.opacity(0.2))
            )
        }
        .coorditPressFeedback()
        .accessibilityIdentifier(identifier)
        .accessibilityValue(imageData == nil ? "empty" : "selected")
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    guard let image = UIImage(data: data) else { return }
                    onImageSelected(image)
                }
            }
        }
    }
}

private struct CoorditClosetSubmitButton: View {
    let title: String
    let isEnabled: Bool
    let metrics: CoorditResponsiveMetrics
    let action: () -> Void

    var body: some View {
        CoorditClosetPrimaryButton(title: title, metrics: metrics, height: 44, action: action)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.38)
            .accessibilityIdentifier("closet-add-submit")
    }
}
#endif
