import SwiftUI

#if os(iOS)
struct CoorditSettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let identifier: String
    let metrics: CoorditResponsiveMetrics
    var isSecure = false
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(7)) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(11), relativeTo: .caption))
                .foregroundStyle(CoorditSettingsStyle.ink)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text, axis: multiline ? .vertical : .horizontal)
                        .lineLimit(multiline ? 3...5 : 1...1)
                }
            }
            .font(CoorditTypography.gmarketMedium(size: metrics.value(12), relativeTo: .body))
            .foregroundStyle(.black)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, metrics.value(13))
            .padding(.vertical, metrics.value(12))
            .frame(maxWidth: .infinity, minHeight: metrics.value(multiline ? 92 : 48), alignment: .topLeading)
            .background(CoorditSettingsStyle.field)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                    .stroke(CoorditSettingsStyle.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

struct CoorditSettingsPrimaryButton: View {
    let title: String
    let identifier: String
    let metrics: CoorditResponsiveMetrics
    var isEnabled = true
    var isDanger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(13), relativeTo: .headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: max(metrics.value(48), 44))
                .background(isDanger ? CoorditSettingsStyle.danger : CoorditSettingsStyle.ink)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
        }
        .coorditPressFeedback(
            cornerRadius: metrics.value(7),
            pressedScale: 0.95,
            pressedOpacity: 0.84,
            overlayOpacity: 0.22
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityIdentifier(identifier)
    }
}

struct CoorditSettingsStatusBanner: View {
    let text: String
    let identifier: String
    let metrics: CoorditResponsiveMetrics
    var isWarning = false

    var body: some View {
        HStack(spacing: metrics.value(9)) {
            Image(systemName: isWarning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: metrics.value(15), weight: .semibold))
            Text(text)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isWarning ? CoorditSettingsStyle.danger : CoorditSettingsStyle.ink)
        .padding(.horizontal, metrics.value(13))
        .frame(maxWidth: .infinity, minHeight: metrics.value(42))
        .background(isWarning ? CoorditSettingsStyle.danger.opacity(0.09) : CoorditDesignTokens.ColorToken.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityIdentifier(identifier)
    }
}

struct CoorditSettingsInfoPanel: View {
    let symbol: String
    let title: String
    let detail: String
    let metrics: CoorditResponsiveMetrics
    var isDanger = false

    var body: some View {
        VStack(spacing: metrics.value(13)) {
            Image(systemName: symbol)
                .font(.system(size: metrics.value(28), weight: .medium))
                .foregroundStyle(isDanger ? CoorditSettingsStyle.danger : CoorditSettingsStyle.ink)
                .frame(width: metrics.value(56), height: metrics.value(56))
                .background(CoorditSettingsStyle.field)
                .clipShape(Circle())

            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(16), relativeTo: .headline))
                .foregroundStyle(.black)

            Text(detail)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(11), relativeTo: .body))
                .foregroundStyle(CoorditSettingsStyle.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(metrics.value(4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(metrics.value(22))
        .frame(maxWidth: .infinity)
        .background(CoorditSettingsStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous)
                .stroke(isDanger ? CoorditSettingsStyle.danger.opacity(0.28) : CoorditSettingsStyle.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

struct CoorditSettingsConfirmationToggle: View {
    let title: String
    @Binding var isOn: Bool
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: metrics.value(10)) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: metrics.value(19), weight: .semibold))
                    .foregroundStyle(isOn ? CoorditSettingsStyle.danger : CoorditSettingsStyle.muted)
                Text(title)
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .caption))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(metrics.value(13))
            .frame(maxWidth: .infinity, minHeight: metrics.value(48))
            .background(CoorditSettingsStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(7), style: .continuous))
        }
        .coorditPressFeedback()
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "확인함" : "확인 안 함")
    }
}

struct CoorditSettingsDocumentSection: View {
    let title: String
    let bodyText: String
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            Text(title)
                .font(CoorditTypography.gmarketBold(size: metrics.value(12), relativeTo: .subheadline))
                .foregroundStyle(CoorditSettingsStyle.ink)
            Text(bodyText)
                .font(CoorditTypography.gmarketMedium(size: metrics.value(10), relativeTo: .body))
                .foregroundStyle(.black.opacity(0.76))
                .lineSpacing(metrics.value(4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, metrics.value(14))
        .padding(.vertical, metrics.value(13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
