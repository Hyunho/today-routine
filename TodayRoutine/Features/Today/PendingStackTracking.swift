import SwiftUI

/// Emphasize central rows through size alone, keeping all text upright.
struct TodayCylinderEffect: ViewModifier {
    let enabled: Bool
    var fixedViewportHeight: CGFloat? = nil
    @AppStorage("today.cylinderSize") private var cylinderSize = 100.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            // Pinned rows live outside the scroll content, but share its cylinder.
            let viewportHeight = fixedViewportHeight
                ?? geometry.bounds(of: .scrollView(axis: .vertical))?.height ?? 0
            let midpoint = fixedViewportHeight != nil
                ? geometry.frame(in: .named("todayCylinderViewport")).midY
                : geometry.frame(in: .scrollView(axis: .vertical)).midY
            // Scale the radius after adapting the default to the viewport,
            // so larger sizes still soften the curve on small screens.
            let size = cylinderSize.isFinite ? max(50, min(200, cylinderSize)) : 100
            let radius = min(viewportHeight / 2, 320) * size / 100
            let distance = enabled && !reduceMotion && viewportHeight > 0
                ? max(-1, min(1, (midpoint - viewportHeight / 2) / radius))
                : 0
            let scale = 1 - 0.24 * abs(distance)

            return effect
                .scaleEffect(scale)
        }
    }
}

struct PendingStackTracking: ViewModifier {
    let id: String
    let enabled: Bool
    let update: (String, Bool) -> Void
    func body(content: Content) -> some View {
        content
            .id(id)
            .onGeometryChange(for: Bool.self) { geometry in
                enabled && geometry.frame(in: .named("todayListViewport")).maxY <= 0
            } action: { above in update(id, above) }
    }
}

struct TodayListSection<Content: View>: View {
    private let title: String?
    private let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
