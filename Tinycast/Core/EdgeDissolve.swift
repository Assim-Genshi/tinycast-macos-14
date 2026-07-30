import SwiftUI

/// Scroll-driven edge dissolve for a scroll view underlapping the palette's floating bars, a port of Raycast's scroll-area mask (see `docs/ui.md` → The edge dissolve).
struct EdgeDissolveMask: ViewModifier {
    /// Band lengths: 28px top dissolve below searchbar, 88px tall bottom dissolve extending higher from bottom of command bar.
    var topFade: CGFloat = 10
    var bottomFade: CGFloat = Theme.Size.bottomBarHeight + 36

    @ViewBuilder
    func body(content: Content) -> some View {
        content.mask(
            GeometryReader { geo in
                LinearGradient(
                    stops: stops(height: geo.size.height),
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .black, location: 0)] }
        let topStop = min(topFade / height, 0.15)
        let bottomStop = max(1.0 - (bottomFade / height), 0.3)
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black, location: topStop),
            .init(color: .black, location: bottomStop),
            .init(color: .black.opacity(0), location: 1.0),
        ]
    }
}

extension View {
    /// Attach to a `ScrollView` that underlaps the palette's floating bars (before `thinScrollbar`, so the scrollbar overlay stays unmasked).
    func edgeDissolve() -> some View {
        modifier(EdgeDissolveMask())
    }
}
