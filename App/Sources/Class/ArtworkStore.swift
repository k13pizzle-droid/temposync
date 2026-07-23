import SwiftUI
#if canImport(UIKit)
import UIKit

/// Decoded-artwork cache with off-main loading. List rows used to run a media-store query and
/// decode a fresh UIImage synchronously on the main thread — per row, per body evaluation, so
/// toggling one checkbox re-decoded art for every visible row.
@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: Set<String> = []
    /// Tracks that genuinely have no artwork — separate from `inFlight`, which must always empty
    /// out again: leaving keys in it permanently meant an NSCache eviction bricked that artwork
    /// for the rest of the session.
    private var knownMisses: Set<String> = []

    private func key(_ trackKey: String, _ side: CGFloat) -> String { "\(trackKey)#\(Int(side))" }

    func cached(_ trackKey: String, side: CGFloat) -> UIImage? {
        cache.object(forKey: key(trackKey, side) as NSString)
    }

    /// Query + decode run off the main thread; successes cache (and reload after eviction),
    /// artless tracks are remembered so they don't re-query on every scroll.
    func load(_ trackKey: String, side: CGFloat, provider: PlaylistProvider?) async -> UIImage? {
        if let hit = cached(trackKey, side: side) { return hit }
        guard let provider else { return nil }
        let cacheKey = key(trackKey, side)
        guard !knownMisses.contains(cacheKey), !inFlight.contains(cacheKey) else { return nil }
        inFlight.insert(cacheKey)
        let image = await Task.detached(priority: .utility) {
            provider.artwork(for: trackKey, side: side)
        }.value
        inFlight.remove(cacheKey)
        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        } else {
            knownMisses.insert(cacheKey)
        }
        return image
    }
}

/// Standard album-art thumbnail: cache-first, placeholder until the off-main load lands.
struct ArtworkThumb: View {
    let trackKey: String
    let provider: PlaylistProvider?
    var size: CGFloat = 36
    var querySide: CGFloat = 72
    var cornerRadius: CGFloat = 6

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.08))
                    .frame(width: size, height: size)
                    .overlay(Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary))
            }
        }
        .task(id: trackKey) {
            image = ArtworkStore.shared.cached(trackKey, side: querySide)
            if image == nil {
                image = await ArtworkStore.shared.load(trackKey, side: querySide, provider: provider)
            }
        }
    }
}
#endif
