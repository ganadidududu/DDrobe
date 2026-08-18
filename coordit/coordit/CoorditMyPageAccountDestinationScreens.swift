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
            CoorditSettingsInfoPanel(
                symbol: "person.badge.key.fill",
                title: "비밀번호는 사용하지 않아요",
                detail: "Coordit은 Google 또는 Apple 계정으로만 로그인합니다. 계정 접근 수단은 해당 제공자 설정에서 관리할 수 있어요.",
                metrics: metrics
            )
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
                detail: "탈퇴하면 저장한 신체 정보, 옷장, 핏 리포트를 복구할 수 없습니다.",
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
                    text: deletionLocalCleanupFailed
                        ? "계정은 삭제됐어요. 이 기기의 남은 기록 정리는 다음 실행 때 다시 시도합니다."
                        : backendSession.statusText,
                    identifier: "mypage-account-deletion-complete",
                    metrics: metrics,
                    isWarning: deletionLocalCleanupFailed || backendSession.isWarning
                )
            }

            CoorditSettingsPrimaryButton(
                title: "회원 탈퇴 확인",
                identifier: "mypage-account-deletion-confirm",
                metrics: metrics,
                isEnabled: deletionAcknowledged,
                isDanger: true
            ) {
                Task {
                    let deletedUserID = backendSession.session?.user.id
                    guard await backendSession.deleteAccount() else { return }
                    if let deletedUserID {
                        deletionLocalCleanupFailed = !(await onAccountDeleted(deletedUserID))
                    } else {
                        deletionLocalCleanupFailed = true
                    }
                    deletionCompleted = true
                }
            }
        }
    }

    private var profileAvatarSymbols: [String] {
        ["person.crop.circle", "person.crop.circle.fill", "person.crop.square"]
    }

    private var profileAvatarSymbol: String {
        profileAvatarSymbols[profileAvatarIndex]
    }

}
#endif
