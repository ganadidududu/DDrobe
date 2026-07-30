import SwiftUI
import Darwin

#if os(iOS)
struct CoorditFitLabURLInputView: View {
    let metrics: CoorditResponsiveMetrics
    @Binding var draft: CoorditFitLabDraft
    let requestLedger: () -> [String]
    let prefill: (URL, CoorditFitLabCategory) async throws -> CoorditFitLabURLPrefillResponse
    let loadReferences: (CoorditFitLabCategory) async throws -> [CoorditFitLabReferenceRow]
    let initialURL: URL?
    let onSwitchToOCR: () -> Void
    let onSwitchToManual: () -> Void

    @State private var stage: Stage = .entry
    @State private var urlText = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var kind: CoorditFitLabGarmentKind = .upper
    @State private var category: CoorditFitLabCategory = .tshirt
    @State private var productName = ""
    @State private var brand = ""
    @State private var rows: [EditableRow] = []
    @State private var validationMessage: String?
    @State private var referenceRefreshIntent: CoorditFitLabCategory?
    @State private var compatibleReferences: [CoorditFitLabReferenceRow] = []
    @State private var referenceErrorMessage: String?
    @State private var discardedReferenceCategory: CoorditFitLabCategory?
    @State private var referenceRequestGeneration = 0
    @State private var referenceRequest: Task<Void, Never>?
    @State private var importGeneration = 0
    @State private var importRequest: Task<Void, Never>?
    @FocusState private var focusedField: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                switch stage {
                case .entry:
                    entry
                case .review:
                    review
                case .confirmed:
                    confirmed
                }

                #if DEBUG
                ledgerProbe
                #endif
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .id(stage)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { focusedField = nil }
            }
        }
        .accessibilityIdentifier("fitlab-url-flow")
        .onDisappear {
            invalidateImport()
            referenceRequestGeneration += 1
            referenceRequest?.cancel()
        }
        .onAppear {
            applyInitialURLIfNeeded()
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: metrics.value(12)) {
            Text("상품 링크에서 사이즈표 가져오기")
                .font(CoorditTypography.gmarketBold(size: metrics.value(18), relativeTo: .headline))
                .foregroundStyle(Color.black)
            Text("링크를 입력하고 옷 종류를 먼저 선택해 주세요.\n가져온 값은 저장 전에 수정할 수 있어요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .body))
                .foregroundStyle(Color.black.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://shop.example/product", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(metrics.value(11))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
                .focused($focusedField, equals: "url")
                .accessibilityLabel("상품 링크")
                .accessibilityIdentifier("fitlab-url-field")

            Text("가져올 옷 분류")
                .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                .foregroundStyle(Color.black)

            classificationControls

            if let errorMessage {
                Text(errorMessage)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .footnote))
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fitlab-url-error")
            }

            Button(action: startImport) {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text(isLoading ? "가져오는 중" : "링크에서 가져오기")
                }
                .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.value(12))
                .background(CoorditFitLabPalette.ink)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
            }
            .coorditPressFeedback()
            .disabled(isLoading)
            .accessibilityIdentifier("fitlab-url-import")

            if errorMessage != nil {
                VStack(spacing: metrics.value(8)) {
                    urlFallbackButton(title: "다시 시도", isPrimary: true, action: startImport)

                    HStack(spacing: metrics.value(8)) {
                        urlFallbackButton(title: "사진 OCR로 전환", action: switchToOCR)
                        .accessibilityIdentifier("fitlab-url-switch-to-ocr")
                        urlFallbackButton(title: "수동 입력으로 전환", action: switchToManual)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(metrics.value(15))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func urlFallbackButton(
        title: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(11)))
                .foregroundStyle(isPrimary ? Color.white : CoorditFitLabPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(40))
                .background(isPrimary ? CoorditFitLabPalette.ink : CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                        .stroke(CoorditFitLabPalette.ink.opacity(isPrimary ? 0 : 0.14), lineWidth: metrics.value(0.8))
                }
        }
        .coorditPressFeedback()
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: metrics.value(14)) {
            #if DEBUG
            Text("URL 검토")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("fitlab-url-review")
            #endif
            Text("추출 결과 · 저장 전 확인 필요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                .foregroundStyle(Color.black)

            classificationControls

            HStack {
                Text("현재 카테고리 \(title(for: category))")
                Spacer(minLength: 0)
                Text("선택한 기준 옷 \(draft.selectedReferenceIDs.count)개")
                    .accessibilityIdentifier("fitlab-url-selected-reference-count")
            }
            .font(CoorditTypography.gmarketLight(size: metrics.value(10), relativeTo: .caption))
            .foregroundStyle(Color.black.opacity(0.62))

            #if DEBUG
            if let reference = compatibleReferences.first {
                Text("\(reference.id)|\(reference.category.rawValue)")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("fitlab-url-reference-result")
            } else if let referenceErrorMessage {
                Text(referenceErrorMessage)
                    .font(CoorditTypography.gmarketLight(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .accessibilityIdentifier("fitlab-url-reference-error")
            }
            if let discardedReferenceCategory {
                Text(discardedReferenceCategory.rawValue)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("fitlab-url-reference-stale-discarded")
            }
            #else
            if let referenceErrorMessage {
                Text(referenceErrorMessage)
                    .font(CoorditTypography.gmarketLight(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(Color.black.opacity(0.62))
            }
            #endif

            TextField("상품명", text: $productName)
                .padding(metrics.value(10))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                .focused($focusedField, equals: "product")
                .accessibilityIdentifier("fitlab-url-product-name")

            TextField("브랜드 (선택)", text: $brand)
                .padding(metrics.value(10))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                .focused($focusedField, equals: "brand")
                .accessibilityIdentifier("fitlab-url-brand")

            Text("모든 수치는 평평하게 놓고 잰 단면(cm)이에요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .footnote))
                .foregroundStyle(Color.black.opacity(0.65))

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                sizeRow(row, index: index)
            }

            Button {
                rows.append(EditableRow())
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
            .accessibilityIdentifier("fitlab-url-add-size-row")

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .accessibilityIdentifier("fitlab-url-validation-error")
            }

            Button(action: confirm) {
                Text("확인하고 기준 옷 선택으로")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.value(12))
                    .background(CoorditFitLabPalette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
            }
            .coorditPressFeedback()
            .accessibilityIdentifier("fitlab-url-confirm")

            #if DEBUG
            Text(urlText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("fitlab-url-field-preserved")

            if let referenceRefreshIntent {
                Text(referenceRefreshIntent.rawValue)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("fitlab-url-reference-refresh-intent")
            }
            #endif
        }
        .padding(metrics.value(15))
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var confirmed: some View {
        VStack(alignment: .leading, spacing: metrics.value(12)) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: metrics.value(42)))
                .foregroundStyle(CoorditFitLabPalette.ink)
            Text("링크에서 가져온 사이즈표를 확인했어요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(18), relativeTo: .headline))
                .foregroundStyle(Color.black)
            Text(confirmedSummary)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(13), relativeTo: .body))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fitlab-url-confirmed")
            Text("아직 상품, 사이즈, 추천, 리포트는 저장하거나 요청하지 않았어요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .body))
                .foregroundStyle(Color.black.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button("가져온 값 다시 편집") { stage = .review }
                .buttonStyle(
                    CoorditContentActionButtonStyle(
                        prominence: .secondary,
                        height: metrics.value(48),
                        cornerRadius: metrics.value(7),
                        fontSize: metrics.value(13)
                    )
                )
            CoorditFitLabPrimaryButton(title: "기준 옷 선택으로", metrics: metrics) {
                draft.isSourceConfirmed = true
            }
            .accessibilityIdentifier("fitlab-url-continue-to-references")
        }
        .padding(metrics.value(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
    }

    private func sizeRow(_ row: EditableRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            HStack {
                Text("사이즈 \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Color.black)
                .accessibilityLabel("사이즈 \(index + 1) 행 삭제")
            }

            TextField("사이즈명", text: rowBinding(row.id, keyPath: \.label))
                .padding(metrics.value(9))
                .background(CoorditFitLabPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                .focused($focusedField, equals: "url-row-\(row.id.uuidString)-label")
                .accessibilityIdentifier("fitlab-url-size-label-row-\(index)")

            ForEach(measurementKeys) { key in
                HStack {
                    Text(measurementTitle(for: key))
                        .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .caption))
                    Spacer(minLength: metrics.value(8))
                    TextField("cm", text: measurementBinding(row.id, key: key))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: metrics.value(92))
                        .frame(minHeight: metrics.value(52))
                        .padding(metrics.value(8))
                        .background(CoorditFitLabPalette.field)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(6), style: .continuous))
                        .focused($focusedField, equals: "url-row-\(row.id.uuidString)-\(key.rawValue)")
                        .accessibilityIdentifier("fitlab-url-measurement-\(key.rawValue)-row-\(index)")
                }
            }
        }
        .padding(metrics.value(12))
        .background(CoorditFitLabPalette.empty.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
    }

    #if DEBUG
    private var ledgerProbe: some View {
        Group {
            Text(ledgerSummary)
                .accessibilityIdentifier("fitlab-url-request-ledger")
            Text(requestLedger().joined(separator: "|"))
                .accessibilityIdentifier("fitlab-url-request-ledger-detail")
        }
        .font(.system(size: 1))
        .frame(width: 1, height: 1)
        .opacity(0.01)
    }

    private var ledgerSummary: String {
        let ledger = requestLedger()
        return [
            "prefill=\(ledger.filter { $0.hasPrefix("prefill:") }.count)",
            "references=\(ledger.filter { $0.hasPrefix("references:") }.count)",
            "product=\(ledger.filter { $0 == "create-product" }.count)",
            "size=\(ledger.filter { $0.hasPrefix("create-size:") }.count)",
            "recommend=\(ledger.filter { $0 == "recommend" }.count)",
            "report=\(ledger.filter { $0.hasPrefix("report:") }.count)",
        ].joined(separator: "|")
    }
    #endif

    private var confirmedSummary: String {
        let first = rows.first
        let chest = first?.measurements[.chestWidth] ?? "-"
        return "\(productName) · \(first?.label ?? "-") · 가슴 단면 \(chest)"
    }

    private var availableCategories: [CoorditFitLabCategory] {
        CoorditFitLabCategory.allCases.filter { $0.garmentKind == kind }
    }

    private var measurementKeys: [CoorditFitLabMeasurementKey] {
        CoorditFitLabMeasurementKey.allCases.filter { $0.garmentKind == kind }
    }

    private var classificationControls: some View {
        VStack(alignment: .leading, spacing: metrics.value(10)) {
            Picker("상의 또는 하의", selection: kindBinding) {
                Text("상의").tag(CoorditFitLabGarmentKind.upper)
                Text("하의").tag(CoorditFitLabGarmentKind.lower)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fitlab-url-kind-picker")

            Picker("세부 카테고리", selection: categoryBinding) {
                ForEach(availableCategories) { option in
                    Text(title(for: option))
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
            .accessibilityIdentifier("fitlab-url-category-picker")
        }
        .disabled(isLoading)
    }

    private var kindBinding: Binding<CoorditFitLabGarmentKind> {
        Binding(
            get: { kind },
            set: { newKind in
                guard newKind != kind else { return }
                kind = newKind
                category = newKind == .upper ? .tshirt : .pants
                if stage == .review {
                    rows = rows.map { EditableRow(id: $0.id, label: $0.label) }
                    invalidateReferences(for: category)
                }
            }
        )
    }

    private var categoryBinding: Binding<CoorditFitLabCategory> {
        Binding(
            get: { category },
            set: { newCategory in
                guard newCategory != category else { return }
                category = newCategory
                kind = newCategory.garmentKind
                if stage == .review {
                    invalidateReferences(for: newCategory)
                }
            }
        )
    }

    private func invalidateReferences(for category: CoorditFitLabCategory) {
        draft.selectedReferenceIDs.removeAll()
        referenceRefreshIntent = category
        compatibleReferences.removeAll()
        referenceErrorMessage = nil
        referenceRequestGeneration += 1
        let generation = referenceRequestGeneration
        referenceRequest?.cancel()
        referenceRequest = Task { @MainActor in
            do {
                let loaded = try await loadReferences(category)
                guard !Task.isCancelled,
                      generation == referenceRequestGeneration,
                      self.category == category
                else {
                    discardedReferenceCategory = category
                    return
                }
                compatibleReferences = loaded.filter {
                    $0.category.isCompatible(with: category) && $0.isActive
                }
            } catch {
                guard !Task.isCancelled,
                      generation == referenceRequestGeneration,
                      self.category == category
                else { return }
                referenceErrorMessage = (error as? CoorditFitLabError)?.errorDescription
                    ?? "기준 옷을 다시 불러오지 못했어요."
            }
        }
    }

    private func startImport() {
        focusedField = nil
        errorMessage = nil
        guard let url = Self.validatedURL(from: urlText) else {
            errorMessage = "HTTP 또는 HTTPS 상품 링크를 입력해 주세요."
            return
        }
        invalidateImport()
        let generation = importGeneration
        isLoading = true
        importRequest = Task { @MainActor in
            do {
                let response = try await prefill(url, category)
                guard !Task.isCancelled, generation == importGeneration, stage == .entry else { return }
                apply(response)
                stage = .review
                isLoading = false
            } catch let error as CoorditFitLabError {
                guard !Task.isCancelled, generation == importGeneration, stage == .entry else { return }
                errorMessage = error.errorDescription ?? "상품 정보를 가져오지 못했어요."
                isLoading = false
            } catch {
                guard !Task.isCancelled, generation == importGeneration, stage == .entry else { return }
                errorMessage = "상품 정보를 가져오지 못했어요."
                isLoading = false
            }
        }
    }

    private func invalidateImport() {
        importGeneration += 1
        importRequest?.cancel()
        importRequest = nil
        isLoading = false
    }

    private func switchToManual() {
        invalidateImport()
        onSwitchToManual()
    }

    private func switchToOCR() {
        invalidateImport()
        onSwitchToOCR()
    }

    private func applyInitialURLIfNeeded() {
        guard urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = initialURL ?? draft.productURL
        guard let url else { return }
        urlText = url.absoluteString
        draft.source = .url
        draft.productURL = url
        draft.isSourceConfirmed = false
        errorMessage = nil
    }

    private func apply(_ response: CoorditFitLabURLPrefillResponse) {
        kind = response.category.garmentKind
        category = response.category
        productName = response.productName
        brand = response.brand ?? ""
        rows = response.sizes.map(EditableRow.init)
        if rows.isEmpty { rows = [EditableRow()] }
        draft.source = .url
        draft.productURL = response.productUrl
        draft.mallName = response.mallName
        draft.selectedReferenceIDs.removeAll()
        draft.isSourceConfirmed = false
        invalidateReferences(for: response.category)
        validationMessage = nil
    }

    private func confirm() {
        let trimmedName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !rows.isEmpty else {
            validationMessage = "상품명과 사이즈 행을 확인해 주세요."
            return
        }

        let normalizedLabels = rows.map { CoorditFitLabDraftValidation.normalizedSizeLabel($0.label) }
        let duplicateLabels = CoorditFitLabDraftValidation.duplicateSizeLabels(in: rows.map(\.label))
        var parsedRows: [CoorditFitLabSizeDraft] = []
        for (index, row) in rows.enumerated() {
            let label = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                validationMessage = "모든 사이즈명을 입력해 주세요."
                return
            }
            guard !duplicateLabels.contains(normalizedLabels[index]) else {
                validationMessage = "사이즈명은 중복될 수 없어요."
                return
            }
            var measurements: [CoorditFitLabMeasurementKey: Double] = [:]
            for key in measurementKeys {
                let raw = row.measurements[key, default: ""].replacingOccurrences(of: ",", with: ".")
                guard raw.isEmpty || (Double(raw).map { $0.isFinite && $0 > 0 } == true) else {
                    validationMessage = "측정값은 0보다 큰 cm 숫자여야 해요."
                    return
                }
                if let value = Double(raw), value.isFinite, value > 0 { measurements[key] = value }
            }
            guard !measurements.isEmpty else {
                validationMessage = "각 사이즈에 측정값을 하나 이상 입력해 주세요."
                return
            }
            parsedRows.append(CoorditFitLabSizeDraft(id: row.id, label: label, measurements: measurements))
        }

        draft.source = .url
        draft.garmentKind = kind
        draft.category = category
        draft.productName = trimmedName
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
        draft.sizes = parsedRows
        draft.ocrMetadata = nil
        draft.isSourceConfirmed = false
        draft.selectedReferenceIDs.removeAll()
        validationMessage = nil
        stage = .confirmed
    }

    private func rowBinding(_ id: UUID, keyPath: WritableKeyPath<EditableRow, String>) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = value
                validationMessage = nil
            }
        )
    }

    private func measurementBinding(_ id: UUID, key: CoorditFitLabMeasurementKey) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?.measurements[key, default: ""] ?? "" },
            set: { value in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index].measurements[key] = value
                validationMessage = nil
            }
        )
    }

    private static func validatedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbiddenScalars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ !forbiddenScalars.contains($0) }),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let url = components.url,
              let canonicalHost = url.host(percentEncoded: false),
              Self.isValidHost(canonicalHost)
        else { return nil }
        return url
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
        }

        if host.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || $0 == "." }) {
            var address = in_addr()
            return host.withCString { inet_pton(AF_INET, $0, &address) == 1 }
        }

        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  let first = label.utf8.first,
                  let last = label.utf8.last,
                  isASCIIAlphaNumeric(first),
                  isASCIIAlphaNumeric(last)
            else { return false }
            return label.utf8.allSatisfy { isASCIIAlphaNumeric($0) || $0 == 45 }
        }
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    private func title(for category: CoorditFitLabCategory) -> String {
        switch category {
        case .tshirt: "티셔츠"
        case .shirt: "셔츠"
        case .sweatshirt: "스웨트셔츠"
        case .hoodie: "후드"
        case .knit: "니트"
        case .jacket: "재킷"
        case .coat: "코트"
        case .pants: "팬츠"
        case .jeans: "데님"
        case .shorts: "쇼츠"
        case .skirt: "스커트"
        }
    }

    private func measurementTitle(for key: CoorditFitLabMeasurementKey) -> String {
        switch key {
        case .shoulderWidth: "어깨 단면"
        case .chestWidth: "가슴 단면"
        case .totalLength: "총장"
        case .sleeveLength: "소매 길이"
        case .waistWidth: "허리 단면"
        case .hipWidth: "엉덩이 단면"
        case .rise: "밑위"
        case .outseam: "바깥 총장"
        }
    }

    private enum Stage {
        case entry
        case review
        case confirmed
    }

    private struct EditableRow: Identifiable, Equatable {
        var id = UUID()
        var label = ""
        var measurements: [CoorditFitLabMeasurementKey: String] = [:]

        init(id: UUID = UUID(), label: String = "", measurements: [CoorditFitLabMeasurementKey: String] = [:]) {
            self.id = id
            self.label = label
            self.measurements = measurements
        }

        nonisolated init(_ source: CoorditFitLabURLPrefillResponse.Size) {
            label = source.sizeLabel
            measurements = [
                .shoulderWidth: source.shoulderWidth,
                .chestWidth: source.chestWidth,
                .totalLength: source.totalLength,
                .sleeveLength: source.sleeveLength,
                .waistWidth: source.waistWidth,
                .hipWidth: source.hipWidth,
                .rise: source.rise,
                .outseam: source.outseam,
            ].compactMapValues { value in
                value?.formatted(.number.precision(.fractionLength(0...2)))
            }
        }
    }
}
#endif
