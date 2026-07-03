import SwiftUI

/// In-memory decoded-image cache shared by every thumbnail in the app.
/// SwiftUI's stock `AsyncImage` keeps NO cache and restarts its load every
/// time a row reappears, so scrolling a long list re-downloads + re-decodes
/// each cover and flashes a placeholder. `NSCache` fixes both: a revisited
/// URL resolves synchronously to the already-decoded image.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 300
        // Bound by BYTES too — a few hundred 544px now-playing covers at ~1MB
        // each would otherwise balloon memory. NSCache evicts LRU past this.
        cache.totalCostLimit = 96 * 1024 * 1024 // ~96 MB of decoded images
    }

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// Drop-in replacement for `AsyncImage(url:) { phase in … }` that reads from
/// (and populates) `ImageCache`. Same phase-based API, so call sites only
/// change the type name. A cache hit renders immediately with no `.empty`
/// flash; a miss loads via URLSession, decodes once, and caches.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            // `id: url` restarts the task (and cancels the old one) whenever a
            // recycled row is handed a new URL — exactly AsyncImage's behavior.
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { phase = .empty; return }
        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(Image(nsImage: cached))
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let image = NSImage(data: data) {
                ImageCache.shared.insert(image, for: url)
                phase = .success(Image(nsImage: image))
            } else {
                phase = .failure(URLError(.cannotDecodeContentData))
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}
