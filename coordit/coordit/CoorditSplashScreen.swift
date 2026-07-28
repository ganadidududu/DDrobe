import SwiftUI

#if os(iOS)
struct CoorditSplashScreen: View {
    let onRouteChange: (CoorditFrameRoute) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taglineVisible = false
    @State private var dividerProgress: CGFloat = 0
    @State private var logoVisible = false

    init(onRouteChange: @escaping (CoorditFrameRoute) -> Void = { _ in }) {
        self.onRouteChange = onRouteChange
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            ZStack {
                CoorditSplashBackground()

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: metrics.value(232))

                    Text("당신을 위한 디지털 옷장")
                        .font(CoorditTypography.gmarketMedium(size: metrics.value(24.462), relativeTo: .title2))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .opacity(taglineVisible ? 1 : 0)
                        .offset(y: taglineVisible ? 0 : metrics.value(12))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("당신을 위한 디지털 옷장")
                        .accessibilityIdentifier("coordit-splash-tagline")

                    CoorditSplashDivider(progress: dividerProgress, metrics: metrics)
                        .padding(.top, metrics.value(48))

                    CoorditSplashLogo(scale: metrics.scale)
                        .frame(width: metrics.value(199.032), height: metrics.value(55.574))
                        .padding(.top, metrics.value(35))
                        .opacity(logoVisible ? 1 : 0)
                        .scaleEffect(logoVisible ? 1 : 0.94)
                        .accessibilityIdentifier("coordit-splash-logo")

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    onRouteChange(.main04)
                }
                .accessibilityAction {
                    onRouteChange(.main04)
                }
                .accessibilityIdentifier("coordit-screen-splash")

                Text("화면을 클릭해주세요")
                    .font(CoorditTypography.gmarketMedium(size: metrics.value(14), relativeTo: .caption))
                    .foregroundStyle(Main01DesignTokens.Colors.chrome.opacity(0.62))
                    .shadow(color: .white.opacity(0.22), radius: metrics.value(3), x: 0, y: metrics.value(1))
                    .opacity(logoVisible ? 1 : 0)
                    .offset(y: logoVisible ? 0 : metrics.value(8))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.82)
                    .allowsHitTesting(false)
                    .accessibilityLabel("화면을 클릭해주세요")
                    .accessibilityIdentifier("coordit-splash-tap-hint")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear(perform: startEntranceAnimation)
    }

    private func startEntranceAnimation() {
        taglineVisible = false
        dividerProgress = 0
        logoVisible = false

        guard !reduceMotion else {
            taglineVisible = true
            dividerProgress = 1
            logoVisible = true
            return
        }

        withAnimation(.easeOut(duration: 0.52)) {
            taglineVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.easeInOut(duration: 0.86)) {
                dividerProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.24) {
            withAnimation(.easeOut(duration: 0.22)) {
                logoVisible = true
            }
        }
    }
}

private struct CoorditSplashBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image(CoorditAssetNames.splashReference)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .background(Main01DesignTokens.Colors.chrome)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CoorditSplashDivider: View {
    let progress: CGFloat
    let metrics: CoorditResponsiveMetrics

    var body: some View {
        let lineWidth = max(metrics.value(0.8), 0.5)
        let lineHeight = metrics.value(100)
        let visibleHeight = max(lineWidth, lineHeight * progress)

        Capsule(style: .continuous)
            .fill(.white.opacity(0.92))
            .frame(width: lineWidth, height: visibleHeight)
            .frame(height: lineHeight, alignment: .top)
            .opacity(progress > 0 ? 1 : 0)
            .accessibilityHidden(true)
    }
}

private struct CoorditSplashLogo: View {
    let scale: CGFloat

    var body: some View {
        let logoScale = scale * 1.432

        ZStack(alignment: .topLeading) {
            logoText(sizeScale: logoScale)
                .offset(x: 3.159 * logoScale, y: 9.159 * logoScale)

            logoTail(sizeScale: logoScale)
                .offset(x: 63.159 * logoScale, y: 9.159 * logoScale)

            logoO(assetName: "FigmaLogoO1", sizeScale: logoScale)
                .offset(x: 26.1815 * logoScale, y: 12.1851 * logoScale)

            logoO(assetName: "FigmaLogoO2", sizeScale: logoScale)
                .offset(x: 45.5812 * logoScale, y: 12.1851 * logoScale)
        }
        .frame(
            width: 139 * logoScale,
            height: 38.8087 * logoScale,
            alignment: .topLeading
        )
        .offset(x: 4.08 * logoScale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("COORDIT"))
    }

    private func logoText(sizeScale: CGFloat) -> Text {
        Text("C")
            .font(CoorditTypography.climate2019(size: 22.565 * sizeScale, relativeTo: .title))
            .kerning(-4.513 * sizeScale)
            .foregroundColor(.white)
    }

    private func logoTail(sizeScale: CGFloat) -> Text {
        let r = Text("R")
            .font(CoorditTypography.climate2019(size: 22.565 * sizeScale, relativeTo: .title))
            .kerning(-4.513 * sizeScale)
            .foregroundColor(.white)
        let d = Text("D")
            .font(CoorditTypography.climate2030(size: 23.016 * sizeScale, relativeTo: .title))
            .kerning(-4.1429 * sizeScale)
            .foregroundColor(.white)
        let i = Text("I")
            .font(CoorditTypography.climate2019(size: 22.565 * sizeScale, relativeTo: .title))
            .kerning(-3.3847 * sizeScale)
            .foregroundColor(.white)
        let t = Text("T")
            .font(CoorditTypography.climate2019(size: 22.565 * sizeScale, relativeTo: .title))
            .kerning(-4.513 * sizeScale)
            .foregroundColor(.white)
        return Text("\(r)\(d)\(i)\(t)")
    }

    private func logoO(assetName: String, sizeScale: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(.white)
            .frame(width: 18.5032 * sizeScale, height: 14.8932 * sizeScale)
    }
}
#endif
