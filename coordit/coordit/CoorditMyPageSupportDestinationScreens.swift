import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func bodyMeasurements(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    measurementField("어깨", unit: "cm", text: $shoulderMeasurement, identifier: "mypage-measurement-shoulder", metrics: metrics)
                    measurementField("가슴", unit: "cm", text: $chestMeasurement, identifier: "mypage-measurement-chest", metrics: metrics)
                    measurementField("허리", unit: "cm", text: $waistMeasurement, identifier: "mypage-measurement-waist", metrics: metrics)
                    measurementField("엉덩이", unit: "cm", text: $hipMeasurement, identifier: "mypage-measurement-hip", metrics: metrics)
                    measurementField("인심", unit: "cm", text: $inseamMeasurement, identifier: "mypage-measurement-inseam", metrics: metrics)
                }
                .padding(.horizontal, metrics.value(13))
            }

            if bodyMeasurementsSaved {
                CoorditSettingsStatusBanner(
                    text: backendSession.isAuthenticated ? "신체 치수를 백엔드에 저장했어요." : "백엔드 저장은 로그인이 필요해요.",
                    identifier: "mypage-body-measurements-saved",
                    metrics: metrics,
                    isWarning: !backendSession.isAuthenticated
                )
            }

            CoorditSettingsPrimaryButton(
                title: "신체 치수 저장",
                identifier: "mypage-body-measurements-save",
                metrics: metrics,
                isEnabled: allMeasurementsEntered
            ) {
                Task {
                    await backendSession.saveBodyMeasurement(bodyMeasurementRequest)
                    bodyMeasurementsSaved = true
                    syncBackendBodyMeasurement()
                }
            }
        }
    }

    func privacyPolicy(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "hand.raised.fill",
                title: "개인정보를 투명하게 다룹니다",
                detail: "시행일 2026.07.07 · COORDIT 서비스 기준",
                metrics: metrics
            )

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDocumentSection(
                    title: "1. 수집하는 정보",
                    bodyText: "서비스는 계정 정보, 사용자가 입력한 신체 정보, 옷장 기록과 핏 분석 결과를 수집합니다. 선택 동의 항목은 설정에서 언제든 변경할 수 있습니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "2. 이용 목적",
                    bodyText: "수집한 정보는 사이즈 추천, 옷장 관리, 핏 리포트 제공과 서비스 품질 개선에 사용합니다. 동의한 목적 밖으로 사용하지 않습니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "3. 보관과 삭제",
                    bodyText: "정보는 서비스 이용 기간 동안 보관하며 회원 탈퇴 또는 삭제 요청 시 관련 법령에서 정한 기간을 제외하고 안전하게 삭제합니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "4. 이용자의 권리",
                    bodyText: "사용자는 자신의 정보를 열람, 수정, 삭제하거나 처리 정지를 요청할 수 있습니다. 문의하기 화면을 통해 개인정보 관련 요청을 접수할 수 있습니다.",
                    metrics: metrics
                )
            }
        }
    }

    func terms(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "doc.text.fill",
                title: "COORDIT 서비스 이용약관",
                detail: "시행일 2026.07.07 · 앱 사용 전 주요 내용을 확인해 주세요.",
                metrics: metrics
            )

            CoorditSettingsCard(metrics: metrics) {
                CoorditSettingsDocumentSection(
                    title: "1. 서비스의 목적",
                    bodyText: "COORDIT은 사용자가 기록한 정보와 옷 데이터를 바탕으로 개인화된 핏 분석과 옷장 관리 기능을 제공합니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "2. 계정과 책임",
                    bodyText: "사용자는 정확한 정보를 제공하고 계정 접근 수단을 안전하게 관리해야 합니다. 다른 사람의 정보를 허가 없이 등록할 수 없습니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "3. 추천 정보",
                    bodyText: "핏 점수와 사이즈 추천은 선택을 돕기 위한 참고 정보입니다. 브랜드와 소재, 착용 선호에 따라 실제 결과가 달라질 수 있습니다.",
                    metrics: metrics
                )
                CoorditSettingsDivider(metrics: metrics)
                CoorditSettingsDocumentSection(
                    title: "4. 이용 제한과 변경",
                    bodyText: "서비스 안정성과 사용자 보호를 위해 부정 사용을 제한할 수 있으며, 중요한 약관 변경은 앱 안에서 사전에 안내합니다.",
                    metrics: metrics
                )
            }
        }
    }

    func contact(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "envelope.fill",
                title: "무엇을 도와드릴까요?",
                detail: "support@coordit.app · 입력한 문의는 현재 이 기기에만 기록됩니다.",
                metrics: metrics
            )

            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    CoorditSettingsTextField(
                        title: "문의 제목",
                        placeholder: "문의 제목을 입력하세요",
                        text: $contactSubject,
                        identifier: "mypage-contact-subject",
                        metrics: metrics
                    )
                    CoorditSettingsTextField(
                        title: "문의 내용",
                        placeholder: "도움이 필요한 내용을 자세히 적어주세요",
                        text: $contactMessage,
                        identifier: "mypage-contact-message",
                        metrics: metrics,
                        multiline: true
                    )
                }
                .padding(.horizontal, metrics.value(13))
            }

            if contactSent {
                CoorditSettingsStatusBanner(
                    text: "문의 내용을 저장했어요. 전송 API 연결 전 미리보기 상태입니다.",
                    identifier: "mypage-contact-sent",
                    metrics: metrics
                )
            }

            CoorditSettingsPrimaryButton(
                title: "문의 보내기",
                identifier: "mypage-contact-submit",
                metrics: metrics,
                isEnabled: !contactSubject.isEmpty && !contactMessage.isEmpty
            ) {
                contactSent = true
            }
        }
    }

    func bugReport(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "ladybug.fill",
                title: "문제를 알려주세요",
                detail: "발생한 화면과 재현 과정을 적어주면 더 빠르게 확인할 수 있어요.",
                metrics: metrics
            )

            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    CoorditSettingsTextField(
                        title: "문제 요약",
                        placeholder: "어떤 문제가 있었나요?",
                        text: $bugSummary,
                        identifier: "mypage-bug-summary",
                        metrics: metrics
                    )
                    CoorditSettingsTextField(
                        title: "재현 방법",
                        placeholder: "문제가 나타나기까지의 순서를 적어주세요",
                        text: $bugSteps,
                        identifier: "mypage-bug-steps",
                        metrics: metrics,
                        multiline: true
                    )
                }
                .padding(.horizontal, metrics.value(13))
            }

            if bugReportSent {
                CoorditSettingsStatusBanner(
                    text: "버그 신고 내용을 저장했어요. 전송 API 연결 전 미리보기 상태입니다.",
                    identifier: "mypage-bug-report-sent",
                    metrics: metrics
                )
            }

            CoorditSettingsPrimaryButton(
                title: "버그 신고 보내기",
                identifier: "mypage-bug-submit",
                metrics: metrics,
                isEnabled: !bugSummary.isEmpty && !bugSteps.isEmpty
            ) {
                bugReportSent = true
            }
        }
    }

    private func measurementField(
        _ title: String,
        unit: String,
        text: Binding<String>,
        identifier: String,
        metrics: CoorditResponsiveMetrics
    ) -> some View {
        HStack(alignment: .bottom, spacing: metrics.value(10)) {
            CoorditSettingsTextField(
                title: title,
                placeholder: "0.0",
                text: text,
                identifier: identifier,
                metrics: metrics
            )
            Text(unit)
                .font(CoorditTypography.gmarketBold(size: metrics.value(10), relativeTo: .caption))
                .foregroundStyle(CoorditSettingsStyle.muted)
                .frame(width: metrics.value(28), height: metrics.value(48))
        }
    }

    private var allMeasurementsEntered: Bool {
        [shoulderMeasurement, chestMeasurement, waistMeasurement, hipMeasurement, inseamMeasurement]
            .allSatisfy { Double($0) != nil }
    }

    private var bodyMeasurementRequest: BodyMeasurementRequest {
        BodyMeasurementRequest(
            shoulderWidth: Double(shoulderMeasurement),
            chestCircumference: Double(chestMeasurement),
            waistCircumference: Double(waistMeasurement),
            hipCircumference: Double(hipMeasurement),
            rawData: .init(source: "ios-mypage", inseamCm: Double(inseamMeasurement))
        )
    }
}
#endif
