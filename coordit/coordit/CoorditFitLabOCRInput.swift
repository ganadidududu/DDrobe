import SwiftUI

#if os(iOS) && canImport(UIKit)
import AVFoundation
import PhotosUI
import UIKit

struct CoorditFitLabOCRInputView: View {
    let metrics: CoorditResponsiveMetrics
    @Binding var draft: CoorditFitLabDraft
    let fixtureName: String?
    let apiRequestLedger: [String]
    let onSwitchToManual: () -> Void

    @Environment(\.dynamicTypeSize) private var inheritedDynamicTypeSize
    @State private var phase: Phase = .chooser
    @State private var result: CoorditFitLabOCRResult?
    @State private var rows: [EditableRow] = []
    @State private var productName = ""
    @State private var kind: CoorditFitLabGarmentKind = .upper
    @State private var category: CoorditFitLabCategory = .tshirt
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var isCameraPresented = false
    @State private var message: String?
    @State private var rowErrors: [UUID: [String]] = [:]
    @State private var globalError: String?
    @State private var cameraAuthorizationProbe = "not-checked"
    @State private var cameraCancellationProbe = "not-invoked"
    @State private var operationGeneration = 0
    @State private var operationTask: Task<Void, Never>?
    @State private var isFlowActive = false
    @State private var visionExecutionProbe = "idle"
    @State private var heartbeatProbe = "idle"
    @FocusState private var focusedField: String?

    var body: some View {
        Group {
            switch phase {
            case .chooser: chooser
            case .processing: processing
            case .review: review
            case .confirmed: confirmed
            case .denied: recovery(identifier: "fitlab-ocr-camera-denied", title: "카메라 접근이 허용되지 않았어요")
            case .unavailable: recovery(identifier: "fitlab-ocr-camera-unavailable", title: "카메라를 사용할 수 없어요")
            }
        }
        .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
        .overlay(alignment: .bottomTrailing) {
            #if DEBUG
            VStack {
                Text(cameraAuthorizationProbe)
                    .accessibilityLabel(cameraAuthorizationProbe)
                    .accessibilityIdentifier("fitlab-ocr-camera-authorization-probe")
                    .frame(width: 1, height: 1)
                Text(cameraCancellationProbe)
                    .accessibilityLabel(cameraCancellationProbe)
                    .accessibilityIdentifier("fitlab-ocr-camera-cancellation-probe")
                    .frame(width: 1, height: 1)
                Text(visionExecutionProbe)
                    .accessibilityLabel(visionExecutionProbe)
                    .accessibilityIdentifier("fitlab-ocr-execution-probe")
                    .frame(width: 1, height: 1)
                Text(heartbeatProbe)
                    .accessibilityLabel(heartbeatProbe)
                    .accessibilityIdentifier("fitlab-ocr-heartbeat-probe")
                    .frame(width: 1, height: 1)
            }
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityElement(children: .contain)
            #endif
        }
        .sheet(isPresented: $isCameraPresented) {
            CoorditFitLabCameraPicker { image in
                isCameraPresented = false
                guard let image else {
                    returnToPriorDraft()
                    return
                }
                pendingCropImage = image
            }
            .ignoresSafeArea()
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
                    returnToPriorDraft()
                } onConfirm: { cropped in
                    self.pendingCropImage = nil
                    recognize(cropped.jpegData(compressionQuality: 0.96) ?? Data())
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            phase = .processing
            beginOperation { generation in
                do {
                    let data = try await item.loadTransferable(type: Data.self) ?? Data()
                    guard !Task.isCancelled, generation == operationGeneration, phase == .processing else { return }
                    guard let image = UIImage(data: data) else {
                        throw CoorditFitLabError.transport("사진을 열지 못했어요.")
                    }
                    invalidateOperation()
                    phase = .chooser
                    pendingCropImage = image
                } catch {
                    guard !Task.isCancelled, generation == operationGeneration, phase == .processing else { return }
                    message = "사진을 읽지 못했어요. 다시 선택하거나 수동으로 입력해 주세요."
                    returnToPriorDraft()
                }
            }
        }
        .onAppear { isFlowActive = true }
        .onDisappear {
            isFlowActive = false
            invalidateOperation()
        }
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coordit-fitlab-accessibility-xxxl") {
            return .accessibility5
        }
        #endif
        return inheritedDynamicTypeSize
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                Text("사이즈표 이미지 가져오기")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(19), relativeTo: .title3))
                    .foregroundStyle(Color.black)
                Text("사진은 기기 안에서만 Vision으로 읽으며 서버에 업로드하지 않아요.")
                    .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .footnote))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    sourceButton(title: "사진에서 선택", symbol: "photo.on.rectangle")
                }
                .coorditPressFeedback()
                .accessibilityIdentifier("fitlab-ocr-photo-library")

                Button(action: requestCamera) {
                    sourceButton(title: "카메라로 촬영", symbol: "camera")
                }
                .coorditPressFeedback()
                .accessibilityIdentifier("fitlab-ocr-camera")

                #if DEBUG
                if fixtureName?.hasPrefix("ocr-") == true {
                    Divider()
                    Text("시뮬레이터 검증")
                        .font(.caption.weight(.semibold))
                    Button("결정적 OCR 표 불러오기") { loadFixture() }
                        .buttonStyle(
                            CoorditContentActionButtonStyle(
                                prominence: .primary,
                                height: metrics.value(48),
                                cornerRadius: metrics.value(7),
                                fontSize: metrics.value(13)
                            )
                        )
                        .accessibilityIdentifier("fitlab-ocr-simulator-fixture")
                    if fixtureName == "ocr-late-response" {
                        Button("지연 OCR 시작") { loadDelayedFixture() }
                            .accessibilityIdentifier("fitlab-ocr-start-late-response")
                    }
                    if fixtureName == "ocr-vision-production" || fixtureName == "ocr-vision-threading" {
                        Button("렌더링 표를 실제 Vision으로 읽기") { loadRenderedVisionFixture() }
                            .buttonStyle(
                                CoorditContentActionButtonStyle(
                                    prominence: .primary,
                                    height: metrics.value(48),
                                    cornerRadius: metrics.value(7),
                                    fontSize: metrics.value(13)
                                )
                            )
                            .accessibilityIdentifier("fitlab-ocr-production-vision-fixture")
                    }
                    if fixtureName == "ocr-errors" {
                        Button("권한 거부 상태") { phase = .denied }
                            .accessibilityIdentifier("fitlab-ocr-simulate-denied")
                        Button("카메라 없음 상태") { phase = .unavailable }
                            .accessibilityIdentifier("fitlab-ocr-simulate-unavailable")
                        Button("표 인식 실패 상태") { loadFixture(unparseable: true) }
                            .accessibilityIdentifier("fitlab-ocr-simulate-unparseable")
                        Button("실제 카메라 취소 콜백 검증") { invokeProductionCameraCancellation() }
                            .accessibilityIdentifier("fitlab-ocr-camera-delegate-cancel")
                    }
                }
                #endif
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .accessibilityIdentifier("fitlab-ocr-source-chooser")
    }

    private var processing: some View {
        VStack(spacing: metrics.value(16)) {
            ProgressView()
                .accessibilityIdentifier("fitlab-ocr-processing")
            Text("사이즈표를 기기에서 읽고 있어요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(16), relativeTo: .headline))
            Text("이미지는 업로드되지 않아요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .footnote))
                .foregroundStyle(CoorditFitLabPalette.muted)
            Button("OCR 취소") {
                invalidateOperation()
                returnToPriorDraft()
            }
            .buttonStyle(
                CoorditContentActionButtonStyle(
                    prominence: .secondary,
                    height: metrics.value(48),
                    cornerRadius: metrics.value(7),
                    fontSize: metrics.value(13)
                )
            )
            .accessibilityIdentifier("fitlab-ocr-cancel-processing")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        .task(id: operationGeneration) {
            guard fixtureName == "ocr-vision-threading" else { return }
            do {
                while !Task.isCancelled, phase == .processing {
                    if heartbeatProbe != "tick" {
                        heartbeatProbe = "tick"
                    }
                    if visionExecutionProbe == "idle",
                       let wasOnMain = await CoorditFitLabVisionExecutionProbe.shared.value() {
                        visionExecutionProbe = wasOnMain ? "main" : "off-main"
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        #endif
    }

    private var review: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.value(14)) {
                Text("OCR 검토")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("fitlab-ocr-review")
                HStack {
                    Button {
                        invalidateOperation()
                        phase = .chooser
                    } label: {
                        compactActionLabel(title: "다시 캡처", symbol: "arrow.counterclockwise")
                    }
                        .coorditPressFeedback()
                        .accessibilityIdentifier("fitlab-ocr-recapture")
                    Spacer()
                    Text("저장 전 확인 필요")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .caption))
                }

                if result?.didFindTable == false {
                    Text("표를 완전히 읽지 못했어요. 원문을 보며 값을 직접 채워 주세요.")
                        .font(.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                        Text("OCR 원문")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(15), relativeTo: .headline))
                    Text(result?.rawText.isEmpty == false ? result?.rawText ?? "" : "인식된 텍스트가 없어요.")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fitlab-ocr-raw-text")
                    Text("신뢰도 \(((result?.confidence ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%")
                        .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .caption))
                        .accessibilityIdentifier("fitlab-ocr-confidence")
                }
                .panelStyle()

                Picker("의류 구분", selection: kindBinding) {
                    Text("상의").tag(CoorditFitLabGarmentKind.upper)
                    Text("하의").tag(CoorditFitLabGarmentKind.lower)
                }
                .pickerStyle(.segmented)
                .tint(CoorditFitLabPalette.ink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("상품 정보")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(15), relativeTo: .headline))
                    TextField("상품명", text: $productName)
                        .fieldStyle()
                        .focused($focusedField, equals: "product-name")
                        .accessibilityIdentifier("fitlab-ocr-product-name")
                    Picker("카테고리", selection: categoryBinding) {
                        ForEach(availableCategories) { option in
                            Text(option.ocrKoreanTitle)
                                .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
                    .accessibilityIdentifier("fitlab-ocr-category-picker")
                }
                .panelStyle()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    editableRow(row, index: index)
                }

                if let globalError {
                    Text(globalError)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fitlab-ocr-global-error")
                }

                Button {
                    rows.append(EditableRow())
                } label: {
                    compactActionLabel(title: "사이즈 행 추가", symbol: "plus.circle")
                }
                .coorditPressFeedback()

                CoorditFitLabPrimaryButton(title: "수정한 사이즈표 확인", metrics: metrics, action: confirm)
                    .accessibilityIdentifier("fitlab-ocr-confirm")
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { focusedField = nil }
            }
        }
    }

    private var confirmed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(CoorditFitLabPalette.ink)
                Text("OCR 사이즈표를 확인했어요")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(19), relativeTo: .title3))
                Text(confirmedSummary)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(15), relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fitlab-ocr-confirmed")
                Text("아직 상품이나 사이즈를 저장하지 않았어요. 다음 단계에서 기준 옷을 선택한 뒤 분석합니다.")
                    .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .footnote))
                    .foregroundStyle(CoorditFitLabPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { phase = .review } label: {
                    compactActionLabel(title: "다시 편집", symbol: "pencil")
                }
                .coorditPressFeedback()
                CoorditFitLabPrimaryButton(title: "기준 옷 선택으로", metrics: metrics) {
                    draft.isSourceConfirmed = true
                }
                .accessibilityIdentifier("fitlab-ocr-continue-to-references")
            }
            .panelStyle()
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
    }

    private func recovery(identifier: String, title: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(CoorditFitLabPalette.ink)
                Text(title)
                    .font(CoorditTypography.gmarketBold(size: metrics.value(19), relativeTo: .title3))
                    .accessibilityIdentifier(identifier)
                Text("사진을 선택하거나 수동으로 입력해 주세요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(15), relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    prominentActionLabel(title: "사진에서 선택", symbol: "photo")
                }
                .coorditPressFeedback()
                Button(action: switchToManual) {
                    compactActionLabel(title: "수동 입력으로 전환", symbol: "square.and.pencil")
                }
                .coorditPressFeedback()
                Button { phase = .chooser } label: {
                    compactActionLabel(title: "다른 방법 보기", symbol: "arrow.left")
                }
                .coorditPressFeedback()
                .accessibilityIdentifier("fitlab-ocr-reopen-chooser")
            }
            .panelStyle()
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
    }

    private func sourceButton(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(CoorditTypography.gmarketBold(size: metrics.value(15), relativeTo: .headline))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: metrics.value(58), alignment: .leading)
            .padding(.horizontal, metrics.value(16))
            .background(CoorditFitLabPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
            .overlay(RoundedRectangle(cornerRadius: metrics.value(8)).stroke(Color.black.opacity(0.14)))
    }

    private func compactActionLabel(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(CoorditTypography.gmarketMedium(size: metrics.value(14), relativeTo: .body))
            .foregroundStyle(CoorditFitLabPalette.ink)
            .padding(.horizontal, metrics.value(13))
            .padding(.vertical, metrics.value(9))
            .background(CoorditFitLabPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
    }

    private func prominentActionLabel(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.value(11))
            .background(
                LinearGradient(
                    colors: [Color(red: 49 / 255, green: 69 / 255, blue: 146 / 255), CoorditFitLabPalette.ink],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
    }

    private func editableRow(_ row: EditableRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("사이즈", text: rowBinding(row.id, keyPath: \.label))
                .textInputAutocapitalization(.characters)
                .fieldStyle()
                .focused($focusedField, equals: "ocr-row-\(row.id.uuidString)-label")
                .accessibilityIdentifier("fitlab-ocr-size-label-row-\(index)")
            ForEach(measurementKeys) { key in
                HStack {
                    Text(key.ocrKoreanTitle)
                        .font(.footnote)
                    Spacer()
                    TextField("cm", text: measurementBinding(row.id, key: key))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: metrics.value(112))
                        .fieldStyle()
                        .focused($focusedField, equals: "\(index)-\(key.rawValue)")
                        .accessibilityIdentifier("fitlab-ocr-measurement-\(key.rawValue)-row-\(index)")
                }
            }
            ForEach(rowErrors[row.id] ?? [], id: \.self) { error in
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fitlab-ocr-row-error-\(index)")
            }
        }
        .panelStyle()
    }

    private var kindBinding: Binding<CoorditFitLabGarmentKind> {
        Binding(
            get: { kind },
            set: { newKind in
                kind = newKind
                category = newKind == .upper ? .tshirt : .pants
                rows = [EditableRow()]
            }
        )
    }

    private var categoryBinding: Binding<CoorditFitLabCategory> {
        Binding(get: { category }, set: { category = $0 })
    }

    private var availableCategories: [CoorditFitLabCategory] {
        CoorditFitLabCategory.allCases.filter { $0.garmentKind == kind }
    }

    private var measurementKeys: [CoorditFitLabMeasurementKey] {
        CoorditFitLabMeasurementKey.allCases.filter { $0.garmentKind == kind }
    }

    private var confirmedSummary: String {
        let first = draft.sizes.first
        let chest = first?.measurements[.chestWidth]
        let firstLine = chest.map { "\(first?.label ?? "-") 가슴 단면 \($0.formatted(.number.precision(.fractionLength(0...2))))" }
            ?? "\(first?.label ?? "-") \(kind == .upper ? "상의" : "하의")"
        return "\(productName) · \(firstLine) · \(draft.sizes.count)개 사이즈 · 원문 포함 · 신뢰도 포함"
    }

    private var confirmedRequestProbe: String {
        guard let request = draft.confirmedSizeRequests.first else { return "none" }
        let chest = request.measurements[.chestWidth]?.formatted(.number.precision(.fractionLength(0...3))) ?? "nil"
        let confidence = request.extractionConfidence?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
        return "count=\(draft.confirmedSizeRequests.count)|label=\(request.sizeLabel)|chest=\(chest)|text=\(request.extractedText ?? "nil")|confidence=\(confidence)"
    }

    private func requestCamera() {
        #if DEBUG
        let forceAvailable = ProcessInfo.processInfo.arguments.contains("--coordit-ocr-force-camera-available")
        #else
        let forceAvailable = false
        #endif
        guard UIImagePickerController.isSourceTypeAvailable(.camera) || forceAvailable else {
            phase = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorizationProbe = "authorized"
            isCameraPresented = true
        case .notDetermined:
            cameraAuthorizationProbe = "not-determined"
            beginOperation { generation in
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled, generation == operationGeneration, phase == .chooser else { return }
                cameraAuthorizationProbe = allowed ? "requestAccess=true" : "requestAccess=false"
                allowed ? (isCameraPresented = true) : (phase = .denied)
            }
        case .denied:
            cameraAuthorizationProbe = "denied"
            phase = .denied
        case .restricted:
            cameraAuthorizationProbe = "restricted"
            phase = .denied
        @unknown default:
            cameraAuthorizationProbe = "unknown"
            phase = .unavailable
        }
    }

    #if DEBUG
    private func invokeProductionCameraCancellation() {
        let wrapper = CoorditFitLabCameraPicker { image in
            cameraCancellationProbe = image == nil ? "delegate-cancelled:nil-image" : "delegate-cancelled:unexpected-image"
            returnToPriorDraft()
        }
        let coordinator = wrapper.makeCoordinator()
        let controller = UIImagePickerController()
        controller.delegate = coordinator
        coordinator.imagePickerControllerDidCancel(controller)
    }
    #endif

    private func recognize(_ data: Data) {
        phase = .processing
        heartbeatProbe = "idle"
        beginOperation { generation in
            #if DEBUG
            if fixtureName == "ocr-vision-threading" {
                await CoorditFitLabVisionExecutionProbe.shared.reset()
                guard !Task.isCancelled, generation == operationGeneration else { return }
                visionExecutionProbe = "idle"
            }
            #endif
            await recognize(data, generation: generation)
        }
    }

    @MainActor
    private func recognize(_ data: Data, generation: Int) async {
        do {
            let service = CoorditFitLabVisionOCRService()
            #if DEBUG
            let recognized = try await service.recognizeSizeChart(
                imageData: data,
                debugDelayNanoseconds: fixtureName == "ocr-vision-threading" ? 5_000_000_000 : 0
            )
            #else
            let recognized = try await service.recognizeSizeChart(imageData: data)
            #endif
            guard !Task.isCancelled, generation == operationGeneration, phase == .processing else { return }
            visionExecutionProbe = recognized.visionExecutionWasOnMainThread == false ? "off-main" : "main"
            apply(recognized)
        } catch {
            guard !Task.isCancelled, generation == operationGeneration, phase == .processing else { return }
            message = error.localizedDescription
            returnToPriorDraft()
        }
    }

    private func beginOperation(_ work: @escaping @MainActor (Int) async -> Void) {
        guard isFlowActive else { return }
        invalidateOperation()
        let generation = operationGeneration
        operationTask = Task { @MainActor in await work(generation) }
    }

    private func invalidateOperation() {
        operationGeneration += 1
        operationTask?.cancel()
        operationTask = nil
    }

    private func switchToManual() {
        invalidateOperation()
        onSwitchToManual()
    }

    private func apply(_ recognized: CoorditFitLabOCRResult) {
        result = recognized
        kind = recognized.draft.garmentKind
        category = recognized.draft.category
        productName = ""
        rows.removeAll(keepingCapacity: true)
        for source in recognized.draft.sizes {
            rows.append(EditableRow(source))
        }
        if rows.isEmpty { rows = [EditableRow()] }
        rowErrors = [:]
        globalError = nil
        message = nil
        phase = .review
    }

    #if DEBUG
    private func loadDelayedFixture() {
        beginOperation { generation in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, generation == operationGeneration, phase == .chooser else { return }
            loadFixture()
        }
    }
    #endif

    private func confirm() {
        focusedField = nil
        rowErrors = [:]
        globalError = nil
        let trimmedProductName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProductName.isEmpty else {
            globalError = "상품명을 입력해 주세요."
            return
        }
        guard !rows.isEmpty else {
            globalError = "사이즈 행을 하나 이상 추가해 주세요."
            return
        }
        let normalizedLabels = rows.map { CoorditFitLabDraftValidation.normalizedSizeLabel($0.label) }
        let duplicateLabels = CoorditFitLabDraftValidation.duplicateSizeLabels(in: rows.map(\.label))
        var parsed: [CoorditFitLabSizeDraft] = []
        var hasError = false

        for (index, row) in rows.enumerated() {
            var errors: [String] = []
            let label = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty {
                errors.append("사이즈명을 입력해 주세요.")
            } else if duplicateLabels.contains(normalizedLabels[index]) {
                errors.append("사이즈명은 중복될 수 없어요.")
            }

            var measurements: [CoorditFitLabMeasurementKey: Double] = [:]
            var enteredValue = false
            for key in measurementKeys {
                let raw = row.measurements[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                enteredValue = true
                let normalized = raw.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized), value.isFinite, value > 0 else {
                    if !errors.contains("측정값은 0보다 큰 유한한 cm 숫자여야 해요.") {
                        errors.append("측정값은 0보다 큰 유한한 cm 숫자여야 해요.")
                    }
                    continue
                }
                measurements[key] = value
            }
            if !enteredValue {
                errors.append("측정값을 하나 이상 입력해 주세요.")
            }
            if !errors.isEmpty {
                hasError = true
                rowErrors[row.id] = errors
            }
            parsed.append(CoorditFitLabSizeDraft(id: row.id, label: label, measurements: measurements))
        }

        guard !hasError else {
            globalError = "표시된 항목을 확인해 주세요."
            return
        }
        draft.source = .ocr
        draft.garmentKind = kind
        draft.category = category
        draft.productName = trimmedProductName
        draft.brand = nil
        draft.mallName = nil
        draft.productURL = nil
        draft.sizes = parsed
        draft.ocrMetadata = result.map { CoorditFitLabOCRMetadata(extractedText: $0.rawText, confidence: $0.confidence) }
        draft.isSourceConfirmed = false
        draft.selectedReferenceIDs.removeAll()
        phase = .confirmed
    }

    private func returnToPriorDraft() {
        phase = result == nil ? .chooser : .review
    }

    private func rowBinding(_ id: UUID, keyPath: WritableKeyPath<EditableRow, String>) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = value
                rowErrors[id] = nil
                globalError = nil
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
                globalError = nil
            }
        )
    }

    #if DEBUG
    private func loadRenderedVisionFixture() {
        guard let data = CoorditFitLabRenderedOCRFixture.upperChartPNG() else {
            message = "검증 이미지를 만들지 못했어요."
            return
        }
        recognize(data)
    }

    private func loadFixture(unparseable: Bool = false) {
        let observations: [CoorditFitLabOCRObservation]
        if unparseable {
            observations = [fixtureObservation("배송 무료 오늘 출발", x: 0.1, y: 0.8, width: 0.7)]
        } else if fixtureName == "ocr-parser-upper-adversarial" {
            observations = upperAdversarialFixture
        } else if fixtureName == "ocr-parser-lower-adversarial" {
            observations = lowerAdversarialFixture
        } else if fixtureName == "ocr-parser-mixed-labels" {
            observations = mixedLabelFixture
        } else if fixtureName == "ocr-lower" {
            observations = lowerFixture
        } else {
            observations = upperFixture
        }
        apply(CoorditFitLabSizeChartOCRParser().parse(observations: observations))
        if fixtureName == "ocr-validation-invalid", rows.count >= 2 {
            rows[1].label = " m "
            rows[0].measurements[.shoulderWidth] = "-1"
            rows[1].measurements[.chestWidth] = "nan"
        }
    }

    private var upperFixture: [CoorditFitLabOCRObservation] {
        fixtureTable([
            ["SIZE", "SHOULDER", "CHEST", "LENGTH", "SLEEVE"],
            ["M", "45", "999", "70", "61"],
            ["L", "47", "58", "72", "63"],
        ])
    }

    private var lowerFixture: [CoorditFitLabOCRObservation] {
        fixtureTable([
            ["사이즈", "허리", "엉덩이", "밑위", "아웃심"],
            ["30", "39", "50", "29", "101"],
            ["32", "41", "52", "30", "103"],
        ])
    }

    private var mixedLabelFixture: [CoorditFitLabOCRObservation] {
        fixtureTable([
            ["SIZE", "SHOULDER", "CHEST", "LENGTH", "SLEEVE"],
            ["85", "41", "50", "65", "58"],
            ["W32", "43", "53", "68", "60"],
            ["FREE", "45", "56", "70", "61"],
        ])
    }

    private var upperAdversarialFixture: [CoorditFitLabOCRObservation] {
        let cells: [(String, Double, Double, Double)] = [
            ("SIZE", 0.04, 0.82, 0.12),
            ("어깨", 0.21, 0.813, 0.08),
            ("SHOULDER", 0.25, 0.827, 0.14),
            ("가슴", 0.40, 0.818, 0.08),
            ("CHEST", 0.44, 0.829, 0.10),
            ("LENGTH", 0.61, 0.814, 0.13),
            ("SLEEVE", 0.80, 0.826, 0.13),
            ("M", 0.04, 0.69, 0.12), ("45", 0.23, 0.681, 0.12),
            ("56", 0.42, 0.696, 0.12), ("70", 0.61, 0.685, 0.12), ("61", 0.80, 0.699, 0.12),
            ("L", 0.04, 0.56, 0.12), ("47", 0.23, 0.552, 0.12),
            ("58", 0.42, 0.568, 0.12), ("72", 0.61, 0.551, 0.12), ("63", 0.80, 0.565, 0.12),
            ("XL", 0.04, 0.43, 0.12), ("-1", 0.23, 0.421, 0.12),
            ("NaN", 0.42, 0.437, 0.12), ("74cm", 0.61, 0.419, 0.12), ("65", 0.80, 0.434, 0.12),
        ]
        return cells.reversed().map { fixtureObservation($0.0, x: $0.1, y: $0.2, width: $0.3) }
    }

    private var lowerAdversarialFixture: [CoorditFitLabOCRObservation] {
        let cells: [(String, Double, Double, Double)] = [
            ("사이즈", 0.04, 0.82, 0.13),
            ("WAIST", 0.22, 0.811, 0.12), ("허리", 0.25, 0.829, 0.08),
            ("HIP", 0.42, 0.817, 0.10), ("엉덩이", 0.45, 0.828, 0.10),
            ("RISE", 0.61, 0.812, 0.12), ("OUTSEAM", 0.80, 0.827, 0.14),
            ("30", 0.04, 0.69, 0.12), ("39", 0.23, 0.681, 0.12),
            ("50", 0.43, 0.698, 0.12), ("29", 0.61, 0.684, 0.12), ("101", 0.80, 0.696, 0.12),
            ("32", 0.04, 0.56, 0.12), ("41", 0.23, 0.551, 0.12),
            ("52", 0.43, 0.567, 0.12), ("30", 0.61, 0.553, 0.12), ("103", 0.80, 0.566, 0.12),
        ]
        var generator = DeterministicGenerator(seed: 42)
        return cells.shuffled(using: &generator).map {
            fixtureObservation($0.0, x: $0.1, y: $0.2, width: $0.3)
        }
    }

    private func fixtureTable(_ rows: [[String]]) -> [CoorditFitLabOCRObservation] {
        rows.enumerated().flatMap { rowIndex, row in
            row.enumerated().map { columnIndex, value in
                fixtureObservation(
                    value,
                    x: 0.04 + Double(columnIndex) * 0.19,
                    y: 0.82 - Double(rowIndex) * 0.13,
                    width: 0.16
                )
            }
        }
    }

    private func fixtureObservation(_ text: String, x: Double, y: Double, width: Double) -> CoorditFitLabOCRObservation {
        CoorditFitLabOCRObservation(
            text: text,
            confidence: text == "999" ? 0.42 : 0.96,
            box: CoorditFitLabOCRBox(CGRect(x: x, y: y, width: width, height: 0.06))
        )
    }
    #endif

    private struct EditableRow: Identifiable, Equatable {
        var id = UUID()
        var label = ""
        var measurements: [CoorditFitLabMeasurementKey: String] = [:]

        init() { }
        init(_ source: CoorditFitLabSizeDraft) {
            id = source.id
            label = source.label
            measurements = source.measurements.mapValues { $0.formatted(.number.precision(.fractionLength(0...2))) }
        }
    }

    private struct DeterministicGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private enum Phase: Equatable {
        case chooser, processing, review, confirmed, denied, unavailable
    }
}

#if DEBUG
private enum CoorditFitLabRenderedOCRFixture {
    static func upperChartPNG() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 620))
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 620))
            let font = UIFont.monospacedSystemFont(ofSize: 58, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
            ]
            let rows = [
                ["SIZE", "SHOULDER", "CHEST", "LENGTH", "SLEEVE"],
                ["M", "45", "56", "70.0", "61"],
                ["L", "47", "58", "72", "63"],
            ]
            let xPositions: [CGFloat] = [70, 300, 700, 1010, 1290]
            for (rowIndex, row) in rows.enumerated() {
                let y = CGFloat(85 + rowIndex * 180)
                for (columnIndex, value) in row.enumerated() {
                    value.draw(at: CGPoint(x: xPositions[columnIndex], y: y), withAttributes: attributes)
                }
            }
        }
    }
}
#endif

struct CoorditFitLabCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}

private extension CoorditFitLabMeasurementKey {
    var ocrKoreanTitle: String {
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

private extension CoorditFitLabCategory {
    var ocrKoreanTitle: String {
        switch self {
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
}

private extension View {
    func panelStyle() -> some View {
        padding(14)
            .background(CoorditFitLabPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12)))
    }

    func fieldStyle() -> some View {
        padding(10)
            .background(CoorditFitLabPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
