import SwiftUI

#if os(iOS)
enum CoorditFitLabInputDestination: Equatable {
    case sources
    case manual
    case ocr
    case url
}

struct CoorditFitLabInputScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let metrics: CoorditResponsiveMetrics
    @Binding var draft: CoorditFitLabDraft
    @Binding var destination: CoorditFitLabInputDestination
    let navigationDirection: CoorditNavigationDirection
    let fixtureName: String?
    let apiRequestLedger: [String]
    let urlRequestLedger: () -> [String]
    let urlPrefill: (URL, CoorditFitLabCategory) async throws -> CoorditFitLabURLPrefillResponse
    let urlReferences: (CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow]
    let sharedImportURL: URL?
    let savedHistory: [CoorditFitLabHistorySnapshot]
    let historyRecoveryNotice: String?
    let onOpenHistory: (CoorditFitLabHistorySnapshot) -> Void

    init(
        metrics: CoorditResponsiveMetrics,
        draft: Binding<CoorditFitLabDraft>,
        destination: Binding<CoorditFitLabInputDestination>,
        navigationDirection: CoorditNavigationDirection = .forward,
        fixtureName: String? = nil,
        apiRequestLedger: [String] = [],
        urlRequestLedger: @escaping () -> [String] = { [] },
        urlPrefill: @escaping (URL, CoorditFitLabCategory) async throws -> CoorditFitLabURLPrefillResponse = { _, _ in
            throw CoorditFitLabError.transport("상품 링크 API를 준비할 수 없어요.")
        },
        urlReferences: @escaping (CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow] = { _ in
            throw CoorditFitLabError.transport("기준 옷 API를 준비할 수 없어요.")
        },
        sharedImportURL: URL? = nil,
        savedHistory: [CoorditFitLabHistorySnapshot] = [],
        historyRecoveryNotice: String? = nil,
        onOpenHistory: @escaping (CoorditFitLabHistorySnapshot) -> Void = { _ in }
    ) {
        self.metrics = metrics
        _draft = draft
        _destination = destination
        self.navigationDirection = navigationDirection
        self.fixtureName = fixtureName
        self.apiRequestLedger = apiRequestLedger
        self.urlRequestLedger = urlRequestLedger
        self.urlPrefill = urlPrefill
        self.urlReferences = urlReferences
        self.sharedImportURL = sharedImportURL
        self.savedHistory = savedHistory
        self.historyRecoveryNotice = historyRecoveryNotice
        self.onOpenHistory = onOpenHistory
    }

    var body: some View {
        ZStack(alignment: .top) {
            destinationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(destination)
                .transition(destinationTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .compositingGroup()
    }

    @ViewBuilder
    private var destinationContent: some View {
        Group {
            switch destination {
            case .sources:
                sourceSelection
            case .manual:
                CoorditFitLabManualDraftView(metrics: metrics, draft: $draft)
            case .ocr:
                CoorditFitLabOCRInputView(
                    metrics: metrics,
                    draft: $draft,
                    fixtureName: fixtureName,
                    apiRequestLedger: apiRequestLedger,
                    onSwitchToManual: {
                        draft.source = .manual
                        destination = .manual
                    }
                )
            case .url:
                CoorditFitLabURLInputView(
                    metrics: metrics,
                    draft: $draft,
                    requestLedger: urlRequestLedger,
                    prefill: urlPrefill,
                    loadReferences: urlReferences,
                    initialURL: sharedImportURL,
                    onSwitchToOCR: {
                        draft.source = .ocr
                        destination = .ocr
                    },
                    onSwitchToManual: {
                        draft.source = .manual
                        destination = .manual
                    }
                )
            }
        }
    }

    private var destinationTransition: AnyTransition {
        .coorditMenuPush(direction: navigationDirection, reduceMotion: reduceMotion)
    }

    private var sourceSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(16)) {
                VStack(alignment: .leading, spacing: metrics.value(5)) {
                    Text("사이즈표를 어떻게 가져올까요?")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(18), relativeTo: .headline))
                        .foregroundStyle(Color.black)
                    Text("입력한 값은 확인 전까지 저장되거나 분석되지 않아요.")
                        .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .footnote))
                        .foregroundStyle(Color.black.opacity(0.64))
                }

                VStack(alignment: .leading, spacing: metrics.value(8)) {
                    sourceCard(
                        title: "링크로 불러오기",
                        subtitle: "링크에서 베타 추출",
                        symbol: "link",
                        identifier: "fitlab-source-url"
                    ) {
                        draft.source = .url
                        destination = .url
                    }
                    sourceCard(
                        title: "사진으로 첨부하기",
                        subtitle: "캡처를 읽고 수정",
                        symbol: "viewfinder",
                        identifier: "fitlab-source-ocr"
                    ) {
                        draft.source = .ocr
                        destination = .ocr
                    }
                    sourceCard(
                        title: "직접 입력하기",
                        subtitle: "표를 직접 작성",
                        symbol: "tablecells",
                        identifier: "fitlab-source-manual"
                    ) {
                        draft.source = .manual
                        destination = .manual
                    }
                }
                .padding(metrics.value(8))
                .background(CoorditFitLabTexturedPanel(cornerRadius: metrics.value(8), intensity: 1))
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))

                VStack(alignment: .leading, spacing: metrics.value(11)) {
                    Text("최근 핏 분석")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(15), relativeTo: .headline))
                        .foregroundStyle(Color.black)
                    if let historyRecoveryNotice {
                        Label(historyRecoveryNotice, systemImage: "exclamationmark.triangle")
                            .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .footnote))
                            .foregroundStyle(Color.black.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(metrics.value(11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                            .accessibilityIdentifier("fitlab-history-recovery-notice")
                    }
                    if savedHistory.isEmpty {
                        VStack(spacing: metrics.value(8)) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(CoorditFitLabPalette.ink.opacity(0.5))
                            Text("저장한 핏 분석이 아직 없어요")
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(13), relativeTo: .body))
                                .foregroundStyle(Color.black.opacity(0.7))
                            Text("분석 리포트에서 히스토리 저장을 누르면 여기에 표시돼요.")
                                .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .caption))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, metrics.value(30))
                        .background(CoorditFitLabPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("fitlab-history-empty")
                    } else {
                        LazyVStack(spacing: metrics.value(8)) {
                            ForEach(savedHistory) { snapshot in
                                historyCard(snapshot)
                            }
                        }
                    }
                }
                .padding(metrics.value(14))
                .background(
                    LinearGradient(
                        colors: [CoorditFitLabPalette.surface, CoorditFitLabPalette.empty.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                )
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func historyCard(_ snapshot: CoorditFitLabHistorySnapshot) -> some View {
        Button {
            onOpenHistory(snapshot)
        } label: {
            HStack(spacing: metrics.value(11)) {
                Image(systemName: snapshot.garmentKind == .upper ? "tshirt" : "figure.walk")
                    .font(.title3)
                    .foregroundStyle(Color.black)
                    .frame(width: metrics.value(34), height: metrics.value(34))
                    .background(CoorditFitLabPalette.empty)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text(snapshot.product.name)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                        .foregroundStyle(Color.black)
                        .lineLimit(2)
                    Text("\(snapshot.recommendation.recommendedSize) · \(snapshot.recommendation.fitScore.formatted(.number.precision(.fractionLength(0...1))))점 · \(sourceLabel(snapshot.originalSource))")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                        .foregroundStyle(Color.black.opacity(0.62))
                    Text(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(CoorditTypography.gmarketLight(size: metrics.value(9), relativeTo: .caption2))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.48))
            }
            .padding(metrics.value(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoorditFitLabPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
        }
        .coorditPressFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.product.name), 추천 \(snapshot.recommendation.recommendedSize), \(snapshot.recommendation.fitScore.formatted(.number.precision(.fractionLength(0...1))))점")
        .accessibilityIdentifier("fitlab-history-card-\(snapshot.analysisID)")
    }

    private func sourceLabel(_ source: CoorditFitLabSource) -> String {
        switch source {
        case .manual: "수동 입력"
        case .ocr: "OCR 입력"
        case .url: "링크 입력"
        }
    }

    private func sourceCard(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: metrics.value(11)) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.value(19), weight: .semibold))
                    .foregroundStyle(CoorditFitLabPalette.ink)
                    .frame(width: metrics.value(36), height: metrics.value(36))
                    .background(CoorditFitLabPalette.field.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))

                VStack(alignment: .leading, spacing: metrics.value(3)) {
                    Text(title)
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .caption))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: metrics.value(60), alignment: .leading)
            .padding(.horizontal, metrics.value(12))
            .padding(.vertical, metrics.value(7))
            .background(
                LinearGradient(
                    colors: [.white, CoorditFitLabPalette.empty],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                    .stroke(.white.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: metrics.value(7), y: metrics.value(3))
        }
        .coorditPressFeedback()
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

}

private struct CoorditFitLabManualDraftView: View {
    let metrics: CoorditResponsiveMetrics
    @Binding var draft: CoorditFitLabDraft

    @State private var kind: CoorditFitLabGarmentKind
    @State private var category: CoorditFitLabCategory
    @State private var productName: String
    @State private var brand: String
    @State private var rows: [EditableRow]
    @State private var rowErrors: [UUID: [String]] = [:]
    @State private var globalError: String?
    @State private var productError: String?
    @State private var isReviewing = false
    @State private var pendingChange: PendingChange?
    @FocusState private var focusedField: String?

    init(
        metrics: CoorditResponsiveMetrics,
        draft: Binding<CoorditFitLabDraft>
    ) {
        self.metrics = metrics
        _draft = draft
        let current = draft.wrappedValue
        _kind = State(initialValue: current.garmentKind)
        _category = State(initialValue: current.category)
        _productName = State(initialValue: current.productName)
        _brand = State(initialValue: current.brand ?? "")
        _rows = State(initialValue: current.sizes.map(EditableRow.init) )
    }

    var body: some View {
        Group {
            if isReviewing {
                review
            } else {
                form
            }
        }
        .alert("입력값을 변경할까요?", isPresented: pendingAlertBinding, presenting: pendingChange) { change in
            Button("취소", role: .cancel) { pendingChange = nil }
            Button("변경", role: .destructive) { apply(change) }
        } message: { _ in
            Text("호환되지 않는 측정값과 선택한 기준 옷이 삭제돼요.")
        }
    }

    private var form: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.value(14)) {
                section(title: "1. 의류 구분") {
                    Picker("상의 또는 하의", selection: kindBinding) {
                        Text("상의")
                            .accessibilityIdentifier("fitlab-kind-upper")
                            .tag(CoorditFitLabGarmentKind.upper)
                        Text("하의")
                            .accessibilityIdentifier("fitlab-kind-lower")
                            .tag(CoorditFitLabGarmentKind.lower)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fitlab-kind-picker")
                }

                section(title: "2. 카테고리와 상품") {
                    Picker("카테고리", selection: categoryBinding) {
                        ForEach(availableCategories) { option in
                            Text(option.koreanTitle)
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("fitlab-category-picker")

                    HStack(spacing: metrics.value(10)) {
                        Text("현재 카테고리 \(category.koreanTitle)")
                            .accessibilityIdentifier("fitlab-current-category")
                        Spacer(minLength: 0)
                        Text("선택한 기준 옷 \(draft.selectedReferenceIDs.count)개")
                            .accessibilityIdentifier("fitlab-selected-reference-count")
                    }
                    .font(CoorditTypography.gmarketLight(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(Color.black.opacity(0.62))

                    labeledField("상품명", placeholder: "예: 오버핏 옥스퍼드 셔츠", text: productNameBinding, identifier: "fitlab-product-name")
                    if let productError {
                        Text(productError)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .accessibilityIdentifier("fitlab-manual-product-error")
                    }
                    labeledField("브랜드 (선택)", placeholder: "예: COORDIT", text: $brand, identifier: "fitlab-product-brand")
                }

                section(title: "3. 사이즈표") {
                    Text("모든 수치는 옷을 평평하게 놓고 잰 단면(cm)이에요. 가슴·허리·엉덩이는 둘레가 아니라 단면 너비를 입력해 주세요.")
                        .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .footnote))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fitlab-flat-width-explanation")

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        sizeRow(row, index: index)
                    }

                    Button {
                        rows.append(EditableRow())
                        globalError = nil
                    } label: {
                        Label("사이즈 행 추가", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(
                        CoorditContentActionButtonStyle(
                            prominence: .secondary,
                            height: metrics.value(48),
                            cornerRadius: metrics.value(7),
                            fontSize: metrics.value(13)
                        )
                    )
                    .accessibilityIdentifier("fitlab-add-size-row")

                    if let globalError {
                        Text(globalError)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .accessibilityIdentifier("fitlab-manual-global-error")
                    }
                }

                Button {
                    validateAndReview()
                } label: {
                    Text("입력 확인하고 기준 옷 선택으로")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, metrics.value(12))
                        .background(CoorditFitLabPalette.ink)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
                }
                .coorditPressFeedback()
                .accessibilityIdentifier("fitlab-manual-continue")
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("fitlab-manual-form")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { focusedField = nil }
            }
        }
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(16)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: metrics.value(42)))
                    .foregroundStyle(CoorditFitLabPalette.ink)
                Text("사이즈표 입력을 확인했어요")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(20), relativeTo: .title3))
                    .foregroundStyle(Color.black)
                Text("\(kind.koreanTitle) · \(rows.count)개 사이즈 · \(category.koreanTitle)")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(15), relativeTo: .body))
                    .foregroundStyle(Color.black)
                    .accessibilityIdentifier("fitlab-manual-review-ready")
                Text("아직 저장하거나 분석을 시작하지 않았어요. 다음 단계에서 비교할 기준 옷을 선택하게 됩니다.")
                    .font(CoorditTypography.gmarketLight(size: metrics.value(13), relativeTo: .body))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Button("사이즈표 다시 편집") { isReviewing = false }
                    .buttonStyle(
                        CoorditContentActionButtonStyle(
                            prominence: .secondary,
                            height: metrics.value(48),
                            cornerRadius: metrics.value(7),
                            fontSize: metrics.value(13)
                        )
                    )
                    .accessibilityIdentifier("fitlab-manual-edit")
                CoorditFitLabPrimaryButton(
                    title: "기준 옷 선택으로",
                    metrics: metrics
                ) {
                    draft.isSourceConfirmed = true
                }
                .accessibilityIdentifier("fitlab-manual-confirm")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.value(24))
            .background(CoorditFitLabPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
            )
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(10)) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                .foregroundStyle(Color.black)
            content()
        }
        .padding(metrics.value(14))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(5)) {
            Text(label)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .caption))
                .foregroundStyle(Color.black.opacity(0.66))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .padding(metrics.value(10))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                .focused($focusedField, equals: identifier)
                .accessibilityIdentifier(identifier)
        }
    }

    private func sizeRow(_ row: EditableRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(9)) {
            HStack {
                Text("사이즈 \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    rows.removeAll { $0.id == row.id }
                    rowErrors[row.id] = nil
                } label: {
                    Label("행 삭제", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .foregroundStyle(Color.black)
                .accessibilityLabel("사이즈 \(index + 1) 행 삭제")
                .accessibilityIdentifier("fitlab-delete-size-row-\(index)")
            }

            TextField("사이즈명 (예: M, 30)", text: rowBinding(row.id, keyPath: \.label))
                .textInputAutocapitalization(.characters)
                .padding(metrics.value(10))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                .focused($focusedField, equals: "label-\(row.id)")
                .accessibilityIdentifier("fitlab-size-label-row-\(index)")

            ForEach(measurementKeys) { key in
                HStack(spacing: metrics.value(9)) {
                    Text(key.koreanTitle)
                        .font(.footnote)
                        .frame(width: metrics.value(78), alignment: .leading)
                    TextField("cm", text: measurementBinding(row.id, key: key))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .padding(metrics.value(9))
                        .background(CoorditFitLabPalette.field)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                        .focused($focusedField, equals: "\(key.rawValue)-\(row.id)")
                        .accessibilityLabel("\(key.koreanTitle) cm")
                        .accessibilityIdentifier("fitlab-measurement-\(key.rawValue)-row-\(index)")
                }
            }

            ForEach(rowErrors[row.id] ?? [], id: \.self) { message in
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(metrics.value(12))
        .background(CoorditFitLabPalette.empty.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                .stroke((rowErrors[row.id]?.isEmpty == false) ? Color.black : Color.clear, lineWidth: 1)
        )
    }

    private var kindBinding: Binding<CoorditFitLabGarmentKind> {
        Binding(get: { kind }, set: requestKind)
    }

    private var categoryBinding: Binding<CoorditFitLabCategory> {
        Binding(
            get: { category },
            set: { newCategory in
                guard newCategory != category else { return }
                if !hasDiscardableData {
                    category = newCategory
                } else {
                    pendingChange = .category(newCategory)
                }
            }
        )
    }

    private var pendingAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingChange != nil },
            set: { visible in if !visible { pendingChange = nil } }
        )
    }

    private var availableCategories: [CoorditFitLabCategory] {
        CoorditFitLabCategory.allCases.filter { $0.garmentKind == kind }
    }

    private var measurementKeys: [CoorditFitLabMeasurementKey] {
        CoorditFitLabMeasurementKey.allCases.filter { $0.garmentKind == kind }
    }

    private var hasDiscardableData: Bool {
        !draft.selectedReferenceIDs.isEmpty || rows.contains { row in
            !row.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            row.measurements.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private func requestKind(_ newKind: CoorditFitLabGarmentKind) {
        guard newKind != kind else { return }
        if hasDiscardableData {
            pendingChange = .kind(newKind)
        } else {
            apply(.kind(newKind))
        }
    }

    private func apply(_ change: PendingChange) {
        switch change {
        case .kind(let newKind):
            kind = newKind
            category = CoorditFitLabCategory.allCases.first { $0.garmentKind == newKind } ?? .tshirt
            rows = [EditableRow()]
            rowErrors = [:]
            globalError = nil
            productError = nil
            draft.selectedReferenceIDs.removeAll()
        case .category(let newCategory):
            category = newCategory
            rows = [EditableRow()]
            rowErrors = [:]
            globalError = nil
            productError = nil
            draft.selectedReferenceIDs.removeAll()
        }
        pendingChange = nil
    }

    private func validateAndReview() {
        focusedField = nil
        rowErrors = [:]
        globalError = nil
        productError = nil
        let trimmedProductName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProductName.isEmpty else {
            productError = "상품명을 입력해 주세요."
            return
        }
        guard !rows.isEmpty else {
            globalError = "사이즈 행을 하나 이상 추가해 주세요."
            return
        }

        let normalizedLabels = rows.map { CoorditFitLabDraftValidation.normalizedSizeLabel($0.label) }
        let duplicateLabels = CoorditFitLabDraftValidation.duplicateSizeLabels(in: rows.map(\.label))
        var parsedRows: [CoorditFitLabSizeDraft] = []
        var hasError = false

        for (index, row) in rows.enumerated() {
            var errors: [String] = []
            let trimmedLabel = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLabel.isEmpty {
                errors.append("사이즈명을 입력해 주세요.")
            } else if duplicateLabels.contains(normalizedLabels[index]) {
                errors.append("사이즈명은 중복될 수 없어요.")
            }

            var parsed: [CoorditFitLabMeasurementKey: Double] = [:]
            var enteredMeasurement = false
            for key in measurementKeys {
                let raw = row.measurements[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                enteredMeasurement = true
                let localized = raw.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(localized), value.isFinite, value > 0 else {
                    if !errors.contains("측정값은 0보다 큰 유한한 cm 숫자여야 해요.") {
                        errors.append("측정값은 0보다 큰 유한한 cm 숫자여야 해요.")
                    }
                    continue
                }
                parsed[key] = value
            }
            if !enteredMeasurement {
                errors.append("측정값을 하나 이상 입력해 주세요.")
            }
            if !errors.isEmpty {
                hasError = true
                rowErrors[row.id] = errors
            }
            parsedRows.append(CoorditFitLabSizeDraft(id: row.id, label: trimmedLabel, measurements: parsed))
        }

        guard !hasError else {
            globalError = "표시된 항목을 확인해 주세요."
            return
        }

        draft.source = .manual
        draft.garmentKind = kind
        draft.category = category
        draft.productName = trimmedProductName
        draft.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        draft.sizes = parsedRows
        draft.selectedReferenceIDs.removeAll()
        draft.isSourceConfirmed = false
        isReviewing = true
    }

    private func rowBinding(_ id: UUID, keyPath: WritableKeyPath<EditableRow, String>) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = value
                rowErrors[id] = nil
            }
        )
    }

    private func measurementBinding(_ id: UUID, key: CoorditFitLabMeasurementKey) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?.measurements[key, default: ""] ?? "" },
            set: { value in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index].measurements[key] = value
                rowErrors[id] = nil
            }
        )
    }

    private var productNameBinding: Binding<String> {
        Binding(
            get: { productName },
            set: {
                productName = $0
                productError = nil
            }
        )
    }

    private struct EditableRow: Identifiable, Equatable {
        var id = UUID()
        var label = ""
        var measurements: [CoorditFitLabMeasurementKey: String] = [:]

        init() { }

        init(_ source: CoorditFitLabSizeDraft) {
            id = source.id
            label = source.label
            measurements = source.measurements.mapValues { value in
                value.formatted(.number.precision(.fractionLength(0...2)))
            }
        }
    }

    private enum PendingChange: Equatable {
        case kind(CoorditFitLabGarmentKind)
        case category(CoorditFitLabCategory)
    }
}

private extension CoorditFitLabGarmentKind {
    var koreanTitle: String {
        switch self {
        case .upper: "상의"
        case .lower: "하의"
        }
    }
}

private extension CoorditFitLabMeasurementKey {
    var koreanTitle: String {
        switch self {
        case .shoulderWidth: "어깨 단면"
        case .chestWidth: "가슴 단면"
        case .totalLength: "총장"
        case .sleeveLength: "소매 길이"
        case .waistWidth: "허리 단면"
        case .hipWidth: "엉덩이 단면"
        case .rise: "밑위"
        case .outseam: "아웃심"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
