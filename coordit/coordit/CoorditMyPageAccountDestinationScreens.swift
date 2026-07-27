import SwiftUI

#if os(iOS)
extension CoorditMyPageFamilyView {
    func profileEdit(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(15)) {
                    Image(systemName: profileAvatarSymbol)
                        .font(.system(size: metrics.value(34), weight: .light))
                        .foregroundStyle(CoorditSettingsStyle.ink)
                        .frame(width: metrics.value(76), height: metrics.value(76))
                        .background(CoorditSettingsStyle.field)
                        .clipShape(Circle())

                    Button("기본 이미지 바꾸기") {
                        profileAvatarIndex = (profileAvatarIndex + 1) % profileAvatarSymbols.count
                        profileSaved = false
                    }
                    .font(CoorditTypography.gmarketBold(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                    .coorditPressFeedback()

                    CoorditSettingsTextField(
                        title: "이름",
                        placeholder: "이름을 입력하세요",
                        text: $profileName,
                        identifier: "mypage-profile-name",
                        metrics: metrics
                    )

                    CoorditSettingsTextField(
                        title: "기본 소개",
                        placeholder: "나를 소개하는 한 줄을 적어주세요",
                        text: $profileBio,
                        identifier: "mypage-profile-bio",
                        metrics: metrics,
                        multiline: true
                    )
                }
                .padding(.horizontal, metrics.value(13))
            }

            if profileSaved {
                CoorditSettingsStatusBanner(
                    text: backendSession.isAuthenticated ? "프로필이 백엔드에 저장됐어요." : "백엔드 저장은 로그인이 필요해요.",
                    identifier: "mypage-profile-saved",
                    metrics: metrics,
                    isWarning: !backendSession.isAuthenticated
                )
            }

            CoorditSettingsPrimaryButton(
                title: "프로필 저장",
                identifier: "mypage-profile-save",
                metrics: metrics,
                isEnabled: !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task {
                    await backendSession.saveProfile(displayName: profileName.trimmingCharacters(in: .whitespacesAndNewlines))
                    profileSaved = true
                    syncBackendProfile()
                }
            }
        }
    }

    func passwordChange(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsCard(metrics: metrics) {
                VStack(spacing: metrics.value(13)) {
                    CoorditSettingsTextField(
                        title: "현재 비밀번호",
                        placeholder: "현재 비밀번호",
                        text: $currentPassword,
                        identifier: "mypage-password-current",
                        metrics: metrics,
                        isSecure: true
                    )
                    CoorditSettingsTextField(
                        title: "새 비밀번호",
                        placeholder: "8자 이상 입력하세요",
                        text: $newPassword,
                        identifier: "mypage-password-new",
                        metrics: metrics,
                        isSecure: true
                    )
                    CoorditSettingsTextField(
                        title: "새 비밀번호 확인",
                        placeholder: "한 번 더 입력하세요",
                        text: $confirmedPassword,
                        identifier: "mypage-password-confirm",
                        metrics: metrics,
                        isSecure: true
                    )
                }
                .padding(.horizontal, metrics.value(13))
            }

            if passwordChanged {
                CoorditSettingsStatusBanner(
                    text: "비밀번호 변경 준비가 완료됐어요.",
                    identifier: "mypage-password-changed",
                    metrics: metrics
                )
            } else if !confirmedPassword.isEmpty && newPassword != confirmedPassword {
                CoorditSettingsStatusBanner(
                    text: "새 비밀번호가 서로 일치하지 않아요.",
                    identifier: "mypage-password-mismatch",
                    metrics: metrics,
                    isWarning: true
                )
            }

            CoorditSettingsPrimaryButton(
                title: "비밀번호 변경",
                identifier: "mypage-password-submit",
                metrics: metrics,
                isEnabled: canChangePassword
            ) {
                passwordChanged = true
            }
        }
    }

    func logout(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "rectangle.portrait.and.arrow.right",
                title: "이 기기에서 로그아웃할까요?",
                detail: "옷장과 핏 기록은 계정에 그대로 보관됩니다. 다시 로그인하면 이어서 사용할 수 있어요.",
                metrics: metrics
            )

            if logoutCompleted {
                CoorditSettingsStatusBanner(
                    text: "이 기기의 백엔드 세션을 정리했어요.",
                    identifier: "mypage-logout-complete",
                    metrics: metrics
                )
            }

            CoorditSettingsPrimaryButton(
                title: "로그아웃 확인",
                identifier: "mypage-logout-confirm",
                metrics: metrics
            ) {
                backendSession.logout()
                logoutCompleted = true
            }
        }
    }

    func accountDeletion(metrics: CoorditResponsiveMetrics) -> some View {
        VStack(spacing: metrics.value(18)) {
            CoorditSettingsInfoPanel(
                symbol: "exclamationmark.triangle.fill",
                title: "계정과 데이터를 삭제합니다",
                detail: "탈퇴하면 저장한 신체 정보, 옷장, 핏 리포트를 복구할 수 없습니다. 실제 삭제는 계정 API 연결 후 실행됩니다.",
                metrics: metrics,
                isDanger: true
            )

            CoorditSettingsConfirmationToggle(
                title: "삭제되는 데이터와 복구 불가 안내를 확인했습니다.",
                isOn: $deletionAcknowledged,
                metrics: metrics
            )

            if deletionCompleted {
                CoorditSettingsStatusBanner(
                    text: "탈퇴 확인을 접수했어요. 현재는 미리보기 상태입니다.",
                    identifier: "mypage-account-deletion-complete",
                    metrics: metrics,
                    isWarning: true
                )
            }

            CoorditSettingsPrimaryButton(
                title: "회원 탈퇴 확인",
                identifier: "mypage-account-deletion-confirm",
                metrics: metrics,
                isEnabled: deletionAcknowledged,
                isDanger: true
            ) {
                deletionCompleted = true
            }
        }
    }

    private var profileAvatarSymbols: [String] {
        ["person.crop.circle", "person.crop.circle.fill", "person.crop.square"]
    }

    private var profileAvatarSymbol: String {
        profileAvatarSymbols[profileAvatarIndex]
    }

    private var canChangePassword: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmedPassword
    }
}
#endif
