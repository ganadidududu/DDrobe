import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func bodyMeasurements(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    measurementField("키", unit: "cm", text: $heightMeasurement, identifier: "mypage-measurement-height", metrics: metrics)
                    measurementField("몸무게", unit: "kg", text: $weightMeasurement, identifier: "mypage-measurement-weight", metrics: metrics)
                }
                .padding(.horizontal, metrics.value(13))
            }

            if bodyMeasurementsSaved {
                CoorditSettingsStatusBanner(
                    text: backendSession.isAuthenticated ? "키와 몸무게를 백엔드에 저장했어요." : "백엔드 저장은 로그인이 필요해요.",
                    identifier: "mypage-body-measurements-saved",
                    metrics: metrics,
                    isWarning: !backendSession.isAuthenticated
                )
            } else if !bodyMeasurementSaveError.isEmpty {
                CoorditSettingsStatusBanner(
                    text: bodyMeasurementSaveError,
                    identifier: "mypage-body-measurements-save-error",
                    metrics: metrics,
                    isWarning: true
                )
            }

            CoorditSettingsPrimaryButton(
                title: "키와 몸무게 저장",
                identifier: "mypage-body-measurements-save",
                metrics: metrics,
                isEnabled: hasBodyMeasurementInput
            ) {
                Task {
                    if await backendSession.saveBodyMeasurement(bodyMeasurementRequest) {
                        bodyMeasurementsSaved = true
                        bodyMeasurementSaveError = ""
                        syncBackendBodyMeasurement()
                    } else {
                        bodyMeasurementsSaved = false
                        bodyMeasurementSaveError = backendSession.statusText
                    }
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
                    bodyText: "사용자는 자신의 정보를 열람, 수정, 삭제하거나 처리 정지를 요청할 수 있습니다. 문의 이메일을 통해 개인정보 관련 요청을 접수할 수 있습니다.",
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

    private var hasBodyMeasurementInput: Bool {
        Double(heightMeasurement) != nil || Double(weightMeasurement) != nil
    }

    private var bodyMeasurementRequest: BodyMeasurementRequest {
        BodyMeasurementRequest(
            heightCm: Double(heightMeasurement),
            weightKg: Double(weightMeasurement),
            rawData: .init(source: "ios-mypage")
        )
    }
}
#endif
