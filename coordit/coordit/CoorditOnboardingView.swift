import SwiftUI

#if os(iOS)
struct CoorditOnboardingView: View {
    private enum Step: Int, CaseIterable {
        case profile = 1
        case measurements
        case consent

        var label: String {
            switch self {
            case .profile: "프로필"
            case .measurements: "핏 정보"
            case .consent: "약관 동의"
            }
        }

        var detail: String {
            switch self {
            case .profile: "내 옷장에 표시할 기본 정보를 입력해 주세요."
            case .measurements: "키와 몸무게는 선택이에요. 나중에 입력해도 괜찮아요."
            case .consent: "필수 약관에 동의하면 내 기록을 안전하게 저장합니다."
            }
        }
    }

    private enum LegalDocument: String, Identifiable {
        case terms
        case privacy

        var id: Self { self }

        var title: String {
            switch self {
            case .terms: "서비스 이용약관"
            case .privacy: "개인정보 처리방침"
            }
        }

        var sections: [(String, String)] {
            switch self {
            case .terms:
                [
                    ("서비스 이용", "Coordit은 기준 의류와 제품 사이즈 정보를 비교해,\n핏 추천을 돕는 서비스입니다."),
                    ("추천의 성격", "추천은 참고 정보이며 소재, 세탁 상태, 브랜드 설계와 개인 선호에 따라 실제 착용감은 달라질 수 있습니다."),
                    ("이용 제한", "타인의 계정을 사용하거나 서비스의 정상 동작을 방해하는 행위는 허용되지 않습니다."),
                ]
            case .privacy:
                [
                    ("수집하는 정보", "소셜 로그인 이메일, 프로필, 그리고 사용자가 직접 선택해 입력한 신체·의류 정보를 처리합니다."),
                    ("이용 목적", "계정 식별, 개인 핏 프로필 구성, 저장한 의류·사이즈 정보 관리에 사용합니다."),
                    ("보관과 삭제", "정보는 서비스 이용 기간 동안 보관하며, 사용자는 계정 설정에서 열람·수정·삭제를 요청할 수 있습니다."),
                ]
            }
        }
    }

    private enum Field: Hashable {
        case name
        case birthYear
        case birthMonth
        case birthDay
    }

    private static let consentVersion = "2026-07-07"

    let onFinished: () -> Void

    @EnvironmentObject private var backendSession: CoorditBackendSessionStore
    @FocusState private var focusedField: Field?
    @State private var step: Step = .profile
    @State private var displayName = ""
    @State private var gender = ""
    @State private var birthYear = ""
    @State private var birthMonth = ""
    @State private var birthDay = ""
    @State private var heightCm = ""
    @State private var weightKg = ""
    @State private var acceptsTerms = false
    @State private var acceptsPrivacy = false
    @State private var acceptsFitData = false
    @State private var acceptsMarketing = false
    @State private var legalDocument: LegalDocument?
    @State private var validationMessage = ""

    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            ZStack(alignment: .top) {
                CoorditSharedAppBackground()

                VStack(spacing: 0) {
                    CoorditSettingsHeaderCard(title: "회원가입", metrics: metrics) {
                        returnToPreviousScreen()
                    }
                    .frame(width: metrics.value(370))
                    .padding(.top, metrics.value(20))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            stepIndicator
                                .padding(.top, metrics.value(24))

                            Group {
                                switch step {
                                case .profile:
                                    profileContent
                                case .measurements:
                                    measurementContent
                                case .consent:
                                    consentContent
                                }
                            }
                            .padding(.top, metrics.value(22))
                        }
                        .padding(.horizontal, metrics.value(16))
                        .padding(.bottom, metrics.value(116))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            footer
                .background(CoorditSettingsStyle.panel.opacity(0.97))
        }
        .sheet(item: $legalDocument) { document in
            legalSheet(document)
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = backendSession.profile?.displayName ?? ""
            }
            if gender.isEmpty {
                gender = backendSession.profile?.gender ?? ""
            }
            if let savedBirthDate = backendSession.profile?.birthDate {
                setBirthDateParts(from: savedBirthDate)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(step.label)
                .font(CoorditTypography.gmarketBold(size: 22, relativeTo: .title2))
                .foregroundStyle(CoorditSettingsStyle.ink)
                .accessibilityIdentifier("coordit-onboarding-title")

            Text(step.detail)
                .font(CoorditTypography.gmarketMedium(size: 12, relativeTo: .subheadline))
                .foregroundStyle(CoorditSettingsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%02d", item.rawValue))
                        .font(CoorditTypography.gmarketMedium(size: 9, relativeTo: .caption))
                    Text(item.label)
                        .font(CoorditTypography.gmarketMedium(size: 11, relativeTo: .caption))
                }
                .foregroundStyle(item.rawValue <= step.rawValue ? CoorditSettingsStyle.ink : CoorditSettingsStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(item.rawValue <= step.rawValue ? CoorditSettingsStyle.ink : CoorditSettingsStyle.line)
                        .frame(height: 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("초기 설정 (step.rawValue)단계, (step.label)")
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingField(title: "이름 또는 별명", hint: "필수") {
                TextField("예: 민아", text: $displayName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { advanceToMeasurements() }
                    .accessibilityIdentifier("onboarding-display-name")
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("성별", hint: "선택")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(genderOptions, id: \.value) { option in
                        Button(option.label) { gender = option.value }
                            .font(CoorditTypography.gmarketMedium(size: 12, relativeTo: .body))
                            .foregroundStyle(gender == option.value ? .white : CoorditSettingsStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(gender == option.value ? CoorditSettingsStyle.ink : CoorditSettingsStyle.field)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(gender == option.value ? CoorditSettingsStyle.ink : CoorditSettingsStyle.line, lineWidth: 1)
                            }
                            .accessibilityIdentifier("onboarding-gender-\(option.value)")
                    }
                }
            }

            onboardingField(title: "생일", hint: "선택") {
                HStack(spacing: 8) {
                    birthdayTextField("1998", text: $birthYear, field: .birthYear, identifier: "year", unit: "년", width: 78)
                    birthdayTextField("05", text: $birthMonth, field: .birthMonth, identifier: "month", unit: "월", width: 45)
                    birthdayTextField("17", text: $birthDay, field: .birthDay, identifier: "day", unit: "일", width: 45)
                }
            }
        }
        .onboardingContentCard()
    }

    private var measurementContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                measurementField("키", value: $heightCm, identifier: "height", placeholder: "170")
                measurementField("몸무게", value: $weightKg, identifier: "weight", placeholder: "58", unit: "kg")
            }

            Text("선택 입력이에요. 비워 두고 나중에 마이페이지에서 입력할 수 있어요.")
                .font(CoorditTypography.gmarketMedium(size: 11, relativeTo: .caption))
                .foregroundStyle(CoorditSettingsStyle.muted)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CoorditSettingsStyle.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

        }
        .onboardingContentCard()
    }

    private var consentContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            consentRow(
                title: "[필수] 서비스 이용약관",
                detail: "계정 이용과 핏 추천 서비스의 기본 약관",
                isOn: $acceptsTerms,
                document: .terms
            )
            consentRow(
                title: "[필수] 개인정보 처리방침",
                detail: "프로필과 선택한 신체 정보의 처리 기준",
                isOn: $acceptsPrivacy,
                document: .privacy
            )
            consentRow(
                title: "[선택] 핏 데이터 개선",
                detail: "추천 품질을 높이기 위한 비식별 분석",
                isOn: $acceptsFitData,
                document: nil
            )
            consentRow(
                title: "[선택] 마케팅 수신",
                detail: "신상품과 혜택 소식 받기",
                isOn: $acceptsMarketing,
                document: nil
            )
        }
        .padding(.horizontal, 16)
        .background(CoorditSettingsStyle.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CoorditSettingsStyle.line, lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(CoorditTypography.gmarketMedium(size: 11, relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: step == .measurements ? 6 : 10) {
                if step != .profile {
                    Button("이전") { move(to: Step(rawValue: step.rawValue - 1) ?? .profile) }
                        .font(CoorditTypography.gmarketMedium(size: 14, relativeTo: .body))
                        .foregroundStyle(CoorditSettingsStyle.ink)
                        .frame(maxWidth: step == .measurements ? nil : .infinity, minHeight: 52)
                        .frame(width: step == .measurements ? 74 : nil)
                        .background(CoorditSettingsStyle.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(CoorditSettingsStyle.line, lineWidth: 1)
                        }
                }

                if step == .measurements {
                    Button("나중에 입력하기") { move(to: .consent) }
                        .font(CoorditTypography.gmarketMedium(size: 13, relativeTo: .body))
                        .foregroundStyle(CoorditSettingsStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 116, height: 52)
                        .background(CoorditSettingsStyle.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Button(step == .consent ? "설정 저장" : "다음 단계") {
                    if step == .profile {
                        advanceToMeasurements()
                    } else if step == .measurements {
                        move(to: .consent)
                    } else {
                        save()
                    }
                }
                .font(CoorditTypography.gmarketBold(size: 14, relativeTo: .body))
                .foregroundStyle(.white)
                .frame(maxWidth: step == .measurements ? nil : .infinity, minHeight: 52)
                .frame(width: step == .measurements ? 112 : nil)
                .background(CoorditSettingsStyle.ink, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(backendSession.isWorking)
                .accessibilityIdentifier(step == .consent ? "onboarding-save" : "onboarding-next")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var genderOptions: [(value: String, label: String)] {
        [
            ("female", "여성"),
            ("male", "남성"),
            ("prefer_not_to_say", "응답하지 않음"),
        ]
    }

    private func onboardingField<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(title, hint: hint)
            content()
                .font(CoorditTypography.gmarketMedium(size: 15, relativeTo: .body))
                .foregroundStyle(CoorditSettingsStyle.ink)
                .padding(.horizontal, 15)
                .frame(minHeight: 52)
                .background(CoorditSettingsStyle.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(CoorditSettingsStyle.line, lineWidth: 1)
                }
        }
    }

    private func birthdayTextField(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        identifier: String,
        unit: String,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 3) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .accessibilityIdentifier("onboarding-birth-\(identifier)")
            Text(unit)
                .font(CoorditTypography.gmarketMedium(size: 12, relativeTo: .caption))
                .foregroundStyle(CoorditSettingsStyle.muted)
        }
    }

    private func measurementField(
        _ title: String,
        value: Binding<String>,
        identifier: String,
        placeholder: String,
        unit: String = "cm"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(CoorditTypography.gmarketMedium(size: 12, relativeTo: .caption))
                .foregroundStyle(CoorditSettingsStyle.ink)
            HStack(spacing: 6) {
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
                    .font(CoorditTypography.gmarketMedium(size: 14, relativeTo: .body))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                    .accessibilityIdentifier("onboarding-measurement-\(identifier)")
                Text(unit)
                    .font(CoorditTypography.gmarketMedium(size: 11, relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.muted)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CoorditSettingsStyle.line, lineWidth: 1)
            }
        }
    }

    private func consentRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        document: LegalDocument?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(CoorditSettingsStyle.ink)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(CoorditTypography.gmarketMedium(size: 13, relativeTo: .body))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                Text(detail)
                    .font(CoorditTypography.gmarketMedium(size: 10, relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.muted)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)

            if let document {
                Button("보기") { legalDocument = document }
                    .font(CoorditTypography.gmarketMedium(size: 11, relativeTo: .caption))
                    .foregroundStyle(CoorditSettingsStyle.ink)
                    .underline()
            }
        }
        .padding(.vertical, 17)
        .overlay(alignment: .bottom) {
            if title != "[선택] 마케팅 수신" {
                Divider()
            }
        }
    }

    private func fieldLabel(_ title: String, hint: String) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(CoorditTypography.gmarketMedium(size: 13, relativeTo: .body))
                .foregroundStyle(CoorditSettingsStyle.ink)
            Text(hint)
                .font(CoorditTypography.gmarketMedium(size: 10, relativeTo: .caption))
                .foregroundStyle(hint == "필수" ? CoorditSettingsStyle.danger : CoorditSettingsStyle.muted)
        }
    }

    private func legalSheet(_ document: LegalDocument) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(document.title)
                        .font(CoorditTypography.gmarketMedium(size: 27, relativeTo: .title))
                        .foregroundStyle(CoorditSettingsStyle.ink)

                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.0)
                                .font(CoorditTypography.gmarketBold(size: 15, relativeTo: .headline))
                                .foregroundStyle(CoorditSettingsStyle.ink)
                            Text(section.1)
                                .font(CoorditTypography.gmarketMedium(size: 13, relativeTo: .body))
                                .foregroundStyle(CoorditSettingsStyle.muted)
                                .lineSpacing(5)
                        }
                    }
                }
                .padding(24)
            }
            .background(Main01DesignTokens.Colors.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { legalDocument = nil }
                }
            }
        }
    }

    private func advanceToMeasurements() {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "옷장 기록에 표시할 이름을 입력해 주세요."
            focusedField = .name
            return
        }
        guard !hasPartialBirthDate else {
            validationMessage = "생일은 연·월·일을 모두 입력해 주세요."
            return
        }
        guard !hasInvalidBirthDate else {
            validationMessage = "실제 생일을 확인해 주세요."
            return
        }
        validationMessage = ""
        move(to: .measurements)
    }

    private func move(to nextStep: Step) {
        focusedField = nil
        validationMessage = ""
        withAnimation(.easeOut(duration: 0.2)) {
            step = nextStep
        }
    }

    private func save() {
        guard acceptsTerms && acceptsPrivacy else {
            validationMessage = "서비스 이용약관과 개인정보 처리방침에 모두 동의해 주세요."
            return
        }
        validationMessage = ""

        let request = CoorditOnboardingRequest(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: gender.isEmpty ? nil : gender,
            birthDate: validBirthDate,
            bodyMeasurements: .init(
                heightCm: measurementValue(heightCm),
                weightKg: measurementValue(weightKg)
            ),
            consents: [
                "terms_of_service": .init(accepted: true, version: Self.consentVersion),
                "privacy_policy": .init(accepted: true, version: Self.consentVersion),
                "fit_data_improvement": .init(accepted: acceptsFitData, version: Self.consentVersion),
                "marketing": .init(accepted: acceptsMarketing, version: Self.consentVersion),
            ]
        )

        Task {
            if await backendSession.completeOnboarding(request) {
                onFinished()
            } else {
                validationMessage = backendSession.statusText
            }
        }
    }

    private var validBirthDate: String? {
        let parts = [birthYear, birthMonth, birthDay]
        guard parts.contains(where: { !$0.isEmpty }) else { return nil }
        guard
            let year = Int(birthYear),
            let month = Int(birthMonth),
            let day = Int(birthDay),
            (1900...Calendar.current.component(.year, from: .now)).contains(year),
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)),
            Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private var hasPartialBirthDate: Bool {
        let parts = [birthYear, birthMonth, birthDay]
        return parts.contains(where: { !$0.isEmpty }) && parts.contains(where: \.isEmpty)
    }

    private var hasInvalidBirthDate: Bool {
        !hasPartialBirthDate && [birthYear, birthMonth, birthDay].allSatisfy { !$0.isEmpty } && validBirthDate == nil
    }

    private func setBirthDateParts(from value: String) {
        let parts = value.split(separator: "-")
        guard parts.count == 3 else { return }
        birthYear = String(parts[0])
        birthMonth = String(parts[1])
        birthDay = String(parts[2])
    }

    private func returnToPreviousScreen() {
        if step == .profile {
            backendSession.logout()
            onFinished()
        } else {
            move(to: Step(rawValue: step.rawValue - 1) ?? .profile)
        }
    }

    private func measurementValue(_ value: String) -> Double? {
        guard let number = Double(value), number > 0 else { return nil }
        return number
    }
}

private extension View {
    func onboardingContentCard() -> some View {
        self
            .padding(16)
            .background(CoorditSettingsStyle.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(CoorditSettingsStyle.line, lineWidth: 1)
            }
    }
}
#endif
