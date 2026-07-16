import SwiftUI

/// Marquee container: when its content is wider than the available space,
/// the whole block scrolls left continuously and re-enters from the right
/// (a trailing copy follows at `loopGap`). Driven by TimelineView from a
/// wall clock, so frequent parent re-renders can't desync or jump it —
/// and multi-line content (song + artist) always moves as one unit.
struct MarqueeBlock<Content: View>: View {
    var resetKey: String
    /// Scroll speed in points per second.
    var speed: Double = 14
    /// How long the block rests at the start of every loop.
    var holdSeconds: Double = 1.5
    @ViewBuilder var content: () -> Content

    private let loopGap: CGFloat = 36

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startDate = Date()

    private var overflows: Bool { contentWidth > containerWidth + 2 }
    /// One full cycle: the first copy scrolls fully out, leaving the
    /// trailing copy exactly where the first one started.
    private var cycleDistance: CGFloat { contentWidth + loopGap }

    var body: some View {
        // Invisible copy defines the height and the offered width;
        // the visible copies in the overlay scroll within it.
        content()
            .opacity(0)
            .overlay(alignment: .leading) {
                GeometryReader { container in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !overflows)) { context in
                        HStack(spacing: loopGap) {
                            measuredContent
                            if overflows {
                                content()
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .offset(x: overflows ? offset(at: context.date) : 0)
                    }
                    .onAppear { containerWidth = container.size.width }
                    .onChange(of: container.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
                }
            }
            .onPreferenceChange(WidthKey.self) { contentWidth = $0 }
            .clipped()
            .id(resetKey)
    }

    private var measuredContent: some View {
        content()
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: WidthKey.self, value: geo.size.width)
                }
            )
    }

    /// Position is a pure function of time: rest for `holdSeconds`, then
    /// glide one full cycle, wrap, repeat. Wrapping is seamless because at
    /// -cycleDistance the trailing copy sits exactly at the origin.
    private func offset(at date: Date) -> CGFloat {
        let cycleSeconds = Double(cycleDistance) / speed
        let period = holdSeconds + cycleSeconds
        let t = date.timeIntervalSince(startDate).truncatingRemainder(dividingBy: period)
        return t < holdSeconds ? 0 : -CGFloat((t - holdSeconds) * speed)
    }

}

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
