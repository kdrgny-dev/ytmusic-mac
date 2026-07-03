import SwiftUI

/// A shimmering placeholder box. A soft highlight sweeps left→right forever
/// so a loading page reads as "content arriving" instead of a dead spinner.
/// Colors use `.primary` opacity so it adapts to light/dark themes.
struct SkeletonBox: View {
    var cornerRadius: CGFloat = 6
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.10), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: animate ? geo.size.width : -geo.size.width * 0.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

/// One placeholder card matching HomeCardView's 150×150 cover + two text
/// lines, so the skeleton row occupies the same space the real cards will.
private struct SkeletonCard: View {
    var circle: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBox(cornerRadius: circle ? 75 : 6)
                .frame(width: 150, height: 150)
            SkeletonBox(cornerRadius: 3).frame(width: 120, height: 11)
            SkeletonBox(cornerRadius: 3).frame(width: 80, height: 10)
        }
        .frame(width: 150, alignment: .leading)
    }
}

/// A skeleton carousel: a title bar + a row of placeholder cards. `circle`
/// makes the covers round (for an artist-style shelf).
private struct SkeletonCarousel: View {
    var circle: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBox(cornerRadius: 4).frame(width: 180, height: 18)
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in SkeletonCard(circle: circle) }
            }
        }
    }
}

/// Full-page loading placeholder for Home / Explore — a few skeleton
/// carousels stacked, mirroring the real layout so nothing jumps when the
/// data lands.
struct HomeExploreSkeleton: View {
    var rows: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<rows, id: \.self) { i in
                SkeletonCarousel(circle: i == 1) // vary one row to look organic
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Clip the overflowing card row so it doesn't force horizontal scroll.
        .clipped()
    }
}
