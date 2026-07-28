import SwiftUI

#if os(iOS)
import PhotosUI

extension CoorditClosetFamilyView {
    func detailScreen(
        metrics: CoorditResponsiveMetrics,
        variant: CoorditClosetCategory,
        item: CoorditClosetItem,
        screenIdentifier: String
    ) -> some View {
        VStack(spacing: 0) {
            CoorditClosetTitleBar(title: "FIT DETAIL", metrics: metrics, horizontalOutset: 11) {
                onRouteChange(.closetOverview)
            }
            .padding(.horizontal, metrics.value(27))

            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.value(20)) {
                HStack(alignment: .top, spacing: metrics.value(13)) {
                    CoorditClosetGarmentArtwork(imageData: item.imageData, category: item.category, metrics: metrics)
                        .frame(width: metrics.value(126), height: metrics.value(168))
                        .clipped()
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: metrics.value(8)) {
                        Text(item.name)
                            .font(CoorditTypography.gmarketBold(size: metrics.value(19)))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: metrics.value(45), alignment: .topLeading)

                        detailAction("옷 이름 수정하기", metrics: metrics) {
                            beginDetailRename(item)
                        }
                        .accessibilityIdentifier("closet-detail-rename")

                        PhotosPicker(selection: $detailPhotoSelection, matching: .images) {
                            detailActionLabel(
                                item.imageData == nil ? "옷 사진 추가하기" : "옷 사진 수정하기",
                                metrics: metrics
                            )
                        }
                        .coorditPressFeedback()
                        .accessibilityLabel(item.imageData == nil ? "옷 사진 추가하기" : "옷 사진 수정하기")
                        .accessibilityIdentifier("closet-detail-garment-photo")
                        .accessibilityValue(item.imageData == nil ? "empty" : "selected")
                        .onChange(of: detailPhotoSelection) { _, newItem in
                            guard let newItem else { return }
                            loadDetailPhoto(newItem, for: item.id)
                        }

                        detailAction("내 옷장에서 삭제하기", metrics: metrics) {
                            showsDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("closet-detail-delete")
                        .disabled(isDeletingDetailItem)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.value(168), alignment: .top)
                }
                .padding(.top, metrics.value(18))

                if let sizeChart = item.sizeChart {
                    sizeChartCard(sizeChart, category: item.category, metrics: metrics)
                }

                #if DEBUG
                if detailPhotoTestScenario != nil {
                    VStack {
                        Text("Detail photo test state")
                            .accessibilityIdentifier("closet-detail-photo-test-state")
                            .accessibilityValue(detailPhotoTestStates[item.id] ?? "empty")
                        Text("Detail photo test rejection")
                            .accessibilityIdentifier("closet-detail-photo-test-rejection")
                            .accessibilityValue(detailPhotoTestRejections[item.id] ?? "none")
                    }
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                }
                #endif

                VStack(spacing: metrics.value(9)) {
                    CoorditFitLabMannequinPanel(
                        assetName: variant == .top ? CoorditAssetNames.fitUpper : CoorditAssetNames.fitLower,
                        metrics: metrics,
                        measurements: mannequinMeasurements(for: item),
                        accessibilityIdentifier: variant == .top
                            ? "closet-mannequin-top"
                            : "closet-mannequin-bottom",
                        overlayIdentifierPrefix: "closet-overlay"
                    )
                    .frame(height: metrics.value(286))

                    CoorditFitLabOverlayLegend(metrics: metrics)

                    scorePanel(metrics: metrics, item: item)
                }
                .padding(.top, metrics.value(6))

                HStack {
                    Text("Score Description")
                        .font(CoorditTypography.mona12(size: metrics.value(17)))
                        .foregroundStyle(.black)
                    Spacer(minLength: 0)
                    detailInfoButton(metrics: metrics)
                }
                .padding(.horizontal, metrics.value(18))
                .frame(height: metrics.value(43))
                .background(CoorditClosetColors.card)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                .padding(.top, metrics.value(1))

                CoorditClosetPrimaryButton(title: "현재 기준치로 재평가", metrics: metrics, height: 39) {
                    Task { await reassessSelectedItem(item) }
                }
                .accessibilityIdentifier("closet-reevaluate")
                .disabled(reassessingItemID == item.id)
                .padding(.top, metrics.value(2))

                if let reassessmentMessage {
                    Text(reassessmentMessage)
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(10)))
                        .foregroundStyle(CoorditClosetColors.navy)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("closet-reassessment-status")
                }
                }
                .padding(.top, metrics.value(20))
                .padding(.horizontal, metrics.value(27))
                .padding(
                    .bottom,
                    metrics.value(Main01DesignTokens.Metrics.navHeight + 28)
                )
            }
            .coorditScrollEdgeTreatment(topFade: metrics.value(18))
        }
        .accessibilityIdentifier("coordit-screen-\(screenIdentifier)")
        .task(id: detailAssessmentTaskID(for: item)) {
            engineScoredItemIDs.remove(item.id)
            await reassessSelectedItem(item, announcesProgress: false)
        }
        .onAppear {
            #if DEBUG
            runDetailPhotoTestScenario(for: item.id)
            #endif
        }
        .onDisappear {
            invalidateDetailPhotoLoad(for: item.id)
        }
        .alert("옷 이름 수정하기", isPresented: $isRenamingDetailItem) {
            TextField("옷 이름", text: $pendingDetailName)
            Button("취소", role: .cancel) {}
            Button("저장") { commitDetailName(for: item.id) }
                .disabled(pendingDetailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("옷장에 표시할 이름을 입력해 주세요.")
        }
        .confirmationDialog(
            "옷장에서 삭제할까요?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task { await deleteDetailItem(item) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\"\(item.name)\"과 저장된 사이즈 정보를 함께 삭제합니다.")
        }
    }

    private func sizeChartCard(
        _ sizeChart: CoorditClosetSizeChart,
        category: CoorditClosetCategory,
        metrics: CoorditResponsiveMetrics
    ) -> some View {
        let values: [(key: String, label: String, value: Double?)] = category == .top
            ? [
                ("shoulder-width", "어깨", sizeChart.measurements.shoulderWidth),
                ("chest-width", "가슴단면", sizeChart.measurements.chestWidth),
                ("total-length", "총장", sizeChart.measurements.totalLength),
                ("sleeve-length", "소매", sizeChart.measurements.sleeveLength),
            ]
            : [
                ("waist-width", "허리단면", sizeChart.measurements.waistWidth),
                ("hip-width", "엉덩이단면", sizeChart.measurements.hipWidth),
                ("rise", "밑위", sizeChart.measurements.rise),
                ("outseam", "총장", sizeChart.measurements.outseam),
            ]

        return VStack(alignment: .leading, spacing: metrics.value(12)) {
            HStack {
                Text("등록 사이즈표")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(14)))
                    .foregroundStyle(CoorditClosetColors.navy)
                Spacer(minLength: 0)
                Text(sizeChart.sizeLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "단일 사이즈")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(11)))
                    .foregroundStyle(CoorditClosetColors.navy.opacity(0.62))
                    .accessibilityIdentifier("closet-detail-size-label")
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: metrics.value(8)), count: 2),
                spacing: metrics.value(8)
            ) {
                ForEach(values, id: \.key) { measurement in
                    VStack(alignment: .leading, spacing: metrics.value(3)) {
                        Text(measurement.label)
                            .font(CoorditTypography.gmarketLight(size: metrics.value(9)))
                            .foregroundStyle(CoorditClosetColors.navy.opacity(0.55))
                        Text(detailFormattedMeasurement(measurement.value))
                            .font(CoorditTypography.gmarketBold(size: metrics.value(13)))
                            .foregroundStyle(CoorditClosetColors.navy)
                            .accessibilityIdentifier("closet-detail-measurement-\(measurement.key)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(metrics.value(10))
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                }
            }
        }
        .padding(metrics.value(14))
        .background(CoorditClosetColors.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(9)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closet-detail-size-chart")
    }

    private func detailFormattedMeasurement(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) cm"
    }

    private func deleteDetailItem(_ item: CoorditClosetItem) async {
        isDeletingDetailItem = true
        defer { isDeletingDetailItem = false }

        if let backendID = item.backendClothingItemId {
            guard await backendSession.deleteClothingItem(id: backendID) else { return }
        }
        items.removeAll { $0.id == item.id }
        selectedReferenceIDs.remove(item.id)
        selectedItemID = nil
        onRouteChange(.closetOverview)
    }

    private func scorePanel(metrics: CoorditResponsiveMetrics, item: CoorditClosetItem) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            Text("현재 기준 의류 기준")
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10)))
                .foregroundStyle(CoorditClosetColors.navy.opacity(0.42))
            Text("FIT SCORE")
                .font(CoorditTypography.climate2019(size: metrics.value(22)))
                .foregroundStyle(CoorditClosetColors.navy)
            metricsGrid(metrics: metrics, values: scoreMetrics(for: item))
            CoorditClosetPrimaryButton(title: detailScoreTitle(for: item), metrics: metrics, height: 38) {}
                .accessibilityIdentifier("closet-detail-total-score")
        }
        .padding(metrics.value(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditClosetColors.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
    }

    private func scoreMetrics(for item: CoorditClosetItem) -> [(String, String, Color)] {
        let diffs = item.fitDiffs
        let values: [(Double?, String)] = item.category == .top
            ? [
                (diffs?.shoulderWidth, "어깨"),
                (diffs?.chestWidth, "가슴"),
                (diffs?.totalLength, "총장"),
                (diffs?.sleeveLength, "소매"),
            ]
            : [
                (diffs?.waistWidth, "허리"),
                (diffs?.hipWidth, "엉덩이"),
                (diffs?.rise, "밑위"),
                (diffs?.outseam, "총장"),
            ]
        return values.map { value, label in
            (formattedDifference(value), label, CoorditClosetColors.navy)
        }
    }

    private func mannequinMeasurements(for item: CoorditClosetItem) -> [CoorditFitLabResultMeasurement] {
        let diffs = item.fitDiffs
        let values: [(key: CoorditFitLabMeasurementKey, title: String, diff: Double?)] = item.category == .top
            ? [
                (.shoulderWidth, "어깨", diffs?.shoulderWidth),
                (.chestWidth, "가슴", diffs?.chestWidth),
                (.totalLength, "총장", diffs?.totalLength),
                (.sleeveLength, "소매", diffs?.sleeveLength),
            ]
            : [
                (.waistWidth, "허리", diffs?.waistWidth),
                (.hipWidth, "힙", diffs?.hipWidth),
                (.rise, "밑위", diffs?.rise),
                (.outseam, "총장", diffs?.outseam),
            ]

        return values.map { value in
            CoorditFitLabResultMeasurement(
                key: value.key,
                title: value.title,
                comparison: value.diff.map {
                    CoorditFitLabReportResponse.ChartData.Comparison(
                        measurement: value.key,
                        label: value.title,
                        ideal: 0,
                        product: $0,
                        diff: $0,
                        status: nil
                    )
                }
            )
        }
    }

    private func formattedDifference(_ value: Double?) -> String {
        guard let value else { return "—" }
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(0...1)))) cm"
    }

    private func detailScoreTitle(for item: CoorditClosetItem) -> String {
        if reassessingItemID == item.id, !engineScoredItemIDs.contains(item.id) {
            return "총점 | 계산 중"
        }
        return engineScoredItemIDs.contains(item.id) ? "총점 | \(item.score)" : "총점 | -"
    }

    private func detailAssessmentTaskID(for item: CoorditClosetItem) -> String {
        let referenceKey = selectedReferenceIDs.sorted().joined(separator: ",")
        return "\(item.id)|\(item.backendClothingItemId ?? "local")|\(referenceKey)"
    }

    private func reassessSelectedItem(
        _ item: CoorditClosetItem,
        announcesProgress: Bool = true
    ) async {
        reassessingItemID = item.id
        reassessmentMessage = announcesProgress
            ? "선택한 의류의 핏 스코어를 계산하고 있어요."
            : nil
        defer { reassessingItemID = nil }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coordit-ui-testing"),
           item.backendClothingItemId == nil {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].score = item.category == .top ? 89 : 92
            items[index].fitDiffs = fixtureDiffs(for: item.category)
            engineScoredItemIDs.insert(item.id)
            reassessmentMessage = announcesProgress
                ? "선택한 의류의 핏 스코어를 다시 계산했어요."
                : nil
            return
        }
        #endif

        guard let clothingItemID = item.backendClothingItemId else {
            reassessmentMessage = "서버에 저장된 의류만 재평가할 수 있어요."
            return
        }
        guard let assessment = await backendSession.reassessClothingItem(id: clothingItemID) else {
            reassessmentMessage = backendSession.statusText
            return
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].score = Int(assessment.fitScore.rounded())
        items[index].fitDiffs = assessment.diffs
        engineScoredItemIDs.insert(item.id)
        reassessmentMessage = announcesProgress
            ? "선택한 의류의 핏 스코어를 다시 계산했어요."
            : nil
    }

    #if DEBUG
    private func fixtureDiffs(for category: CoorditClosetCategory) -> CoorditMeasurementMap {
        category == .top
            ? CoorditMeasurementMap(
                totalLength: -3, shoulderWidth: 1, chestWidth: -5, sleeveLength: 0.5,
                waistWidth: nil, hipWidth: nil, rise: nil, outseam: nil
            )
            : CoorditMeasurementMap(
                totalLength: nil, shoulderWidth: nil, chestWidth: nil, sleeveLength: nil,
                waistWidth: 0.5, hipWidth: -2, rise: 1, outseam: -3
            )
    }
    #endif

    private func detailAction(_ title: String, metrics: CoorditResponsiveMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            detailActionLabel(title, metrics: metrics)
        }
        .coorditPressFeedback()
    }

    private func detailActionLabel(_ title: String, metrics: CoorditResponsiveMetrics) -> some View {
        Text(title)
            .font(CoorditTypography.gmarketMedium(size: metrics.value(10)))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.value(33))
            .background(CoorditClosetColors.card)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
    }

    private func detailInfoButton(metrics: CoorditResponsiveMetrics) -> some View {
        Button("자세히 보기") {}
            .font(CoorditTypography.gmarketMedium(size: metrics.value(12)))
            .foregroundStyle(.white)
            .frame(width: metrics.value(96), height: metrics.value(32))
            .background(CoorditClosetColors.navy)
            .clipShape(Capsule())
            .coorditPressFeedback()
    }
}
#endif
