import SwiftUI

#if os(iOS)
struct CoorditFitLabSubmissionView: View {
    let metrics: CoorditResponsiveMetrics
    @ObservedObject var coordinator: CoorditFitLabCoordinator
    let requestLedger: () -> [String]
    let loadReferences: () async -> Void
    let manageReferences: () -> Void
    let submit: () -> Void

    @State private var showsDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                if coordinator.recommendation != nil {
                    resultPanel
                } else {
                    selectionPanel
                }
                ledgerProbe
            }
            .padding(.horizontal, metrics.value(33))
            .padding(.bottom, metrics.value(120))
        }
        .coorditScrollEdgeTreatment(topFade: metrics.value(14))
        .task {
            if coordinator.references.isEmpty, coordinator.recommendation == nil {
                await loadReferences()
            }
        }
        .alert("입력부터 다시 시작할까요?", isPresented: $showsDiscardConfirmation) {
            Button("취소", role: .cancel) { }
            Button("다시 시작", role: .destructive) {
                coordinator.discardAndRestart()
            }
        } message: {
            Text("완료된 API 기록은 서버에 남지만, 이 화면의 제출 체크포인트와 선택은 초기화돼요.")
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: metrics.value(14)) {
            Text("비교할 기준 옷을 선택해 주세요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(19), relativeTo: .title3))
                .foregroundStyle(Color.black)
                .accessibilityIdentifier("fitlab-reference-selection")
            Text("\(coordinator.draft.garmentKind == .upper ? "상의" : "하의") 기준 의류예요. 한 개 이상 골라야 분석할 수 있어요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .body))
                .foregroundStyle(Color.black.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: metrics.value(10)) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: metrics.value(17), weight: .semibold))
                    .foregroundStyle(CoorditFitLabPalette.noticeAccent)
                    .padding(.top, metrics.value(1))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: metrics.value(5)) {
                    Text("같은 종류·길이의 기준 옷을 골라 주세요")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                        .foregroundStyle(.white)
                    Text("사이즈표 실측끼리 비교하므로, 구조가 비슷해야 정확해요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .caption))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineSpacing(metrics.value(2))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("반팔↔반팔 · 긴팔↔긴팔 · 아우터↔아우터\n반바지↔반바지 · 긴바지↔긴바지")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(10.5), relativeTo: .caption))
                        .foregroundStyle(CoorditFitLabPalette.noticeAccent)
                        .lineSpacing(metrics.value(3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, metrics.value(13))
            .padding(.vertical, metrics.value(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoorditFitLabPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fitlab-similar-reference-notice")

            if coordinator.submissionStep == .loadingReferences, coordinator.loadState == .loading {
                ProgressView("기준 옷을 불러오는 중")
                    .tint(CoorditFitLabPalette.ink)
            } else if coordinator.references.isEmpty {
                Text(coordinator.error?.errorDescription ?? "선택할 수 있는 기준 옷이 없어요.")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(13), relativeTo: .body))
                    .foregroundStyle(Color.black)
            } else {
                ForEach(coordinator.references) { reference in
                    referenceButton(reference)
                }
            }

            if coordinator.draft.selectedReferenceIDs.isEmpty {
                Button(action: manageReferences) {
                    Text("기준 의류 선택·등록하기")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: metrics.value(44))
                        .background(CoorditFitLabPalette.ink)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
                }
                .coorditPressFeedback()
                .disabled(coordinator.loadState == .loading)
                .accessibilityIdentifier("fitlab-manage-references")
            }

            Text("선택한 기준 옷 \(coordinator.draft.selectedReferenceIDs.count)개")
                .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
                .foregroundStyle(Color.black)
                .accessibilityIdentifier("fitlab-selected-reference-count")

            if let error = coordinator.error,
               coordinator.submissionStep != .loadingReferences {
                errorPanel(error)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if coordinator.loadState == .loading {
                        ProgressView().tint(.white)
                    }
                    Text(coordinator.retryStep == nil ? "핏 분석 시작" : "완료된 단계부터 다시 시도")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(14), relativeTo: .headline))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: metrics.value(48))
                .background(coordinator.canSubmit ? CoorditFitLabPalette.ink : Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
            }
            .coorditPressFeedback()
            .disabled(!coordinator.canSubmit || coordinator.loadState == .loading)
            .accessibilityIdentifier(coordinator.retryStep == nil ? "fitlab-submit-analysis" : "fitlab-retry-submission")

            Text("다른 탭으로 이동해도 계산은 계속돼요. 완료되면 앱에서 알려드릴게요.")
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(Color.black.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fitlab-background-analysis-guide")

            Button("입력과 선택 버리기") {
                showsDiscardConfirmation = true
            }
            .buttonStyle(
                CoorditContentActionButtonStyle(
                    prominence: .secondary,
                    height: metrics.value(48),
                    cornerRadius: metrics.value(7),
                    fontSize: metrics.value(13)
                )
            )
            .disabled(coordinator.loadState == .loading)
            .accessibilityIdentifier("fitlab-discard-submission")
        }
        .padding(metrics.value(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: metrics.value(8)).stroke(Color.black.opacity(0.12)))
    }

    private func referenceButton(_ reference: CoorditFitLabReferenceRow) -> some View {
        let selected = coordinator.draft.selectedReferenceIDs.contains(reference.id)
        return Button {
            coordinator.toggleReference(reference)
        } label: {
            HStack(spacing: metrics.value(12)) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(CoorditFitLabPalette.ink)
                VStack(alignment: .leading, spacing: metrics.value(3)) {
                    Text(reference.nickname ?? "기준 옷")
                        .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .body))
                    Text(reference.fitType)
                        .font(CoorditTypography.gmarketLight(size: metrics.value(11), relativeTo: .caption))
                }
                Spacer()
            }
            .foregroundStyle(Color.black)
            .padding(metrics.value(12))
            .background(selected ? CoorditFitLabPalette.empty : CoorditFitLabPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
        }
        .coorditPressFeedback()
        .disabled(coordinator.loadState == .loading)
        .accessibilityIdentifier("fitlab-reference-\(reference.id)")
        .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: metrics.value(14)) {
            if let recommendation = coordinator.recommendation {
                Text("핏 분석이 준비됐어요")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(20), relativeTo: .title3))
                    .foregroundStyle(Color.black)
                Text("추천 \(recommendation.recommendedSize) · \(recommendation.fitScore.formatted(.number.precision(.fractionLength(0))))점")
                    .font(CoorditTypography.gmarketBold(size: metrics.value(17), relativeTo: .headline))
                    .foregroundStyle(Color.black)
                    .accessibilityLabel("추천 \(recommendation.recommendedSize) · \(recommendation.fitScore.formatted(.number.precision(.fractionLength(0))))점")
                    .accessibilityIdentifier("fitlab-submission-result")

                let variant: CoorditFitLabResultVariant = coordinator.draft.garmentKind == .upper ? .top : .bottom
                let scoreCard = CoorditFitLabScoreCard(
                    variant: variant,
                    recommendation: recommendation,
                    report: coordinator.report,
                    metrics: metrics
                )
                scoreCard
                CoorditFitLabMannequinPanel(
                    assetName: variant.assetName,
                    metrics: metrics,
                    measurements: scoreCard.measurements
                )
                .frame(height: metrics.value(270))
                CoorditFitLabOverlayLegend(metrics: metrics)
                CoorditFitLabSizeScoreChart(
                    report: coordinator.report,
                    recommendation: recommendation,
                    metrics: metrics
                )
                CoorditFitLabDifferenceChart(measurements: scoreCard.measurements, metrics: metrics)
                CoorditFitLabReportCard(
                    report: coordinator.report,
                    fallbackMessage: coordinator.reportNeedsRetry ? "상세 리포트를 불러오지 못해 기본 설명을 표시해요." : nil,
                    metrics: metrics
                )
            }

            if coordinator.reportNeedsRetry {
                VStack(alignment: .leading, spacing: metrics.value(8)) {
                    Text("상세 리포트를 불러오지 못해 추천 결과로 임시 설명을 만들었어요.")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fitlab-report-fallback")
                    Button("리포트 다시 시도") {
                        submit()
                    }
                    .buttonStyle(
                        CoorditContentActionButtonStyle(
                            prominence: .primary,
                            height: metrics.value(48),
                            cornerRadius: metrics.value(7),
                            fontSize: metrics.value(13)
                        )
                    )
                    .disabled(coordinator.loadState == .loading)
                }
                .padding(metrics.value(12))
                .background(CoorditFitLabPalette.empty.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
            }

            Button("입력과 선택 버리기") {
                showsDiscardConfirmation = true
            }
            .buttonStyle(
                CoorditContentActionButtonStyle(
                    prominence: .secondary,
                    height: metrics.value(48),
                    cornerRadius: metrics.value(7),
                    fontSize: metrics.value(13)
                )
            )
            .disabled(coordinator.loadState == .loading)
            .accessibilityIdentifier("fitlab-discard-submission")
        }
        .padding(metrics.value(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditFitLabPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(8)))
        .overlay(RoundedRectangle(cornerRadius: metrics.value(8)).stroke(Color.black.opacity(0.12)))
    }

    private func errorPanel(_ error: CoorditFitLabError) -> some View {
        VStack(alignment: .leading, spacing: metrics.value(5)) {
            Text("\(stepTitle) 단계에서 멈췄어요")
                .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
            Text(error.errorDescription ?? "다시 시도해 주세요.")
                .font(CoorditTypography.gmarketLight(size: metrics.value(12), relativeTo: .body))
        }
        .foregroundStyle(Color.black)
        .padding(metrics.value(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoorditFitLabPalette.empty.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fitlab-submission-error")
    }

    private var stepTitle: String {
        switch coordinator.retryStep {
        case .creatingProduct: "상품 저장"
        case .creatingSizes: "사이즈 저장"
        case .recommending: "핏 추천"
        case .generatingReport: "상세 리포트"
        case .loadingReferences: "기준 옷 불러오기"
        default: "핏 분석"
        }
    }

    @ViewBuilder
    private var ledgerProbe: some View {
        #if DEBUG
        VStack {
            Text(ledgerSummary)
                .accessibilityIdentifier("fitlab-submission-ledger")
            Text(requestLedger().joined(separator: "|"))
                .accessibilityIdentifier("fitlab-submission-ledger-detail")
        }
        .font(.system(size: 1))
        .frame(width: 1, height: 1)
        .opacity(0.01)
        #endif
    }

    private var ledgerSummary: String {
        let ledger = requestLedger()
        func count(_ exact: String) -> Int { ledger.filter { $0 == exact }.count }
        return [
            "references=\(ledger.filter { $0.hasPrefix("references:") }.count)",
            "product=\(count("create-product"))",
            "M-attempts=\(count("create-size:M:attempt"))",
            "M-success=\(count("create-size:M:success"))",
            "L-attempts=\(count("create-size:L:attempt"))",
            "L-success=\(count("create-size:L:success"))",
            "recommend=\(count("recommend"))",
            "report=\(ledger.filter { $0.hasPrefix("report:") }.count)",
        ].joined(separator: "|")
    }
}
#endif
