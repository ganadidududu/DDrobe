import SwiftUI

#if os(iOS)
private struct CoorditShowsScreenChromeKey: EnvironmentKey {
    static let defaultValue = true
}

private struct CoorditShowsScreenBackgroundKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var coorditShowsScreenChrome: Bool {
        get { self[CoorditShowsScreenChromeKey.self] }
        set { self[CoorditShowsScreenChromeKey.self] = newValue }
    }

    var coorditShowsScreenBackground: Bool {
        get { self[CoorditShowsScreenBackgroundKey.self] }
        set { self[CoorditShowsScreenBackgroundKey.self] = newValue }
    }
}

struct CoorditSharedAppBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            ZStack {
                Main01DesignTokens.Colors.surface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Main01ChromeBackground(scale: metrics.scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container, edges: .all)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("coordit-shared-app-background")
    }
}

private struct CoorditScrollEdgeTreatment: ViewModifier {
    let topFade: CGFloat

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, topFade + 6, for: .scrollContent)
            .padding(.top, -topFade)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topFade)

                    Rectangle()
                        .fill(.black)
                }
            }
    }
}

extension View {
    func coorditScrollEdgeTreatment(topFade: CGFloat) -> some View {
        modifier(CoorditScrollEdgeTreatment(topFade: topFade))
    }
}

struct CoorditScreenChrome: View {
    let route: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void
    var showsHeader = true

    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            VStack(spacing: 0) {
                if showsHeader {
                    Main01Header(scale: metrics.scale) {
                        onRouteChange(.myPage)
                    }
                    .padding(.top, Main01DesignTokens.Metrics.headerTop * metrics.scale)
                }

                Spacer(minLength: 0)

                CoorditBottomNavigation(
                    selectedTab: route.selectedTab,
                    scale: metrics.scale
                ) { selectedTab in
                    onRouteChange(CoorditFrameRoute.route(for: selectedTab, from: route))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container, edges: .all)
    }
}

struct CoorditScreenScaffold<Content: View>: View {
    let route: CoorditFrameRoute
    let onRouteChange: (CoorditFrameRoute) -> Void
    let contentTop: CGFloat
    let contentBottom: CGFloat
    @ViewBuilder let content: (CoorditResponsiveMetrics) -> Content
    @Environment(\.coorditShowsScreenChrome) private var showsScreenChrome
    @Environment(\.coorditShowsScreenBackground) private var showsScreenBackground

    init(
        route: CoorditFrameRoute,
        onRouteChange: @escaping (CoorditFrameRoute) -> Void,
        contentTop: CGFloat = 120,
        contentBottom: CGFloat = 80,
        @ViewBuilder content: @escaping (CoorditResponsiveMetrics) -> Content
    ) {
        self.route = route
        self.onRouteChange = onRouteChange
        self.contentTop = contentTop
        self.contentBottom = contentBottom
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = CoorditResponsiveMetrics(size: geometry.size)

            ZStack(alignment: .top) {
                if showsScreenBackground {
                    CoorditSharedAppBackground()
                }

                content(metrics)
                    .padding(.top, metrics.value(contentTop))
                    .padding(.bottom, metrics.value(contentBottom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if showsScreenChrome {
                    CoorditScreenChrome(route: route, onRouteChange: onRouteChange)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .all)
        .preferredColorScheme(.light)
    }
}
#endif
