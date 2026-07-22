import Foundation
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MediaPlayer)
import MediaPlayer
#endif

struct PlaylistSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int
}

/// Reads the user's playlists and starts class playback. Backed by the media library on device;
/// a fixture provider stands in on the simulator (no library there).
/// Sendable so artwork/asset lookups can run off the main thread (see ArtworkStore).
protocol PlaylistProvider: Sendable {
    func playlists() -> [PlaylistSummary]
    func songs(in playlistID: String) -> [ClassSong]
    /// Queue the given tracks (by trackKey, in class order) on the system player and start playing.
    func startPlayback(trackKeys: [String])
    #if canImport(UIKit)
    /// Album artwork for a track, if the library has it.
    func artwork(for trackKey: String, side: CGFloat) -> UIImage?
    #endif
    /// Direct audio-file URL for a track (downloaded/purchased/DRM-free items only) — enables
    /// in-house tempo analysis with no network.
    func assetURL(for trackKey: String) -> URL?
    /// Every song in the library (deduped) — feeds the batch tempo analyzer.
    func allSongs() -> [ClassSong]
}

extension PlaylistProvider {
    func assetURL(for trackKey: String) -> URL? { nil }
    func allSongs() -> [ClassSong] { [] }
}

#if canImport(UIKit)
extension PlaylistProvider {
    func artwork(for trackKey: String, side: CGFloat) -> UIImage? { nil }
}
#endif

#if canImport(MediaPlayer)
/// Real adapter: `MPMediaQuery` reads Apple Music playlists under the existing media-library
/// permission (no MusicKit entitlement needed); playback queues on the same system player the
/// transport bar already controls.
final class MediaLibraryPlaylistProvider: PlaylistProvider, @unchecked Sendable {
    // Guarded by `lock`: item lookups run off-main for artwork loads (ArtworkStore).
    private let lock = NSLock()
    private var itemsByKey: [String: MPMediaItem] = [:]
    private var cachedCollections: [MPMediaPlaylist]?
    private var changeObserver: (any NSObjectProtocol)?

    init() {
        // Fire-and-forget authorization; first open may show the permission prompt.
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { _ in }
        }
        // Library queries are expensive main-thread media-store work — cache the collections and
        // invalidate only when the library actually changes.
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.cachedCollections = nil
            self.itemsByKey.removeAll()
            self.lock.unlock()
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
    }

    private func collections() -> [MPMediaPlaylist] {
        lock.lock()
        if let cachedCollections {
            lock.unlock()
            return cachedCollections
        }
        lock.unlock()
        let fresh = (MPMediaQuery.playlists().collections ?? []).compactMap { $0 as? MPMediaPlaylist }
        lock.lock()
        cachedCollections = fresh
        lock.unlock()
        return fresh
    }

    func playlists() -> [PlaylistSummary] {
        collections().map { playlist in
            let name = (playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String) ?? "Playlist"
            return PlaylistSummary(id: String(playlist.persistentID), name: name,
                                   songCount: playlist.items.count)
        }
    }

    func songs(in playlistID: String) -> [ClassSong] {
        guard let playlist = collections().first(where: { String($0.persistentID) == playlistID })
        else { return [] }
        return playlist.items.map { item in
            let key = "mp:\(item.persistentID)"
            cache(item, forKey: key)
            return ClassSong(trackKey: key,
                             title: item.title ?? "Unknown",
                             artist: item.artist ?? "Unknown",
                             durationSeconds: item.playbackDuration,
                             bpm: nil)
        }
    }

    func startPlayback(trackKeys: [String]) {
        let items = items(forTrackKeys: trackKeys)
        guard !items.isEmpty else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.play()
    }

    /// Resolve items by trackKey — cached from a playlist read, or looked up by persistent ID
    /// (saved classes start without a prior playlist browse).
    func items(forTrackKeys keys: [String]) -> [MPMediaItem] {
        keys.compactMap { key in
            lock.lock()
            let cached = itemsByKey[key]
            lock.unlock()
            if let cached { return cached }
            guard key.hasPrefix("mp:"), let id = UInt64(key.dropFirst(3)) else { return nil }
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: id, forProperty: MPMediaItemPropertyPersistentID))
            let item = query.items?.first
            if let item { cache(item, forKey: key) }
            return item
        }
    }

    private func cache(_ item: MPMediaItem, forKey key: String) {
        lock.lock()
        itemsByKey[key] = item
        lock.unlock()
    }

    func artwork(for trackKey: String, side: CGFloat) -> UIImage? {
        items(forTrackKeys: [trackKey]).first?.artwork?.image(at: CGSize(width: side, height: side))
    }

    func assetURL(for trackKey: String) -> URL? {
        items(forTrackKeys: [trackKey]).first?.assetURL
    }

    func allSongs() -> [ClassSong] {
        // Deliberately does NOT warm itemsByKey: a full library scan used to pin an MPMediaItem
        // per song in the shared provider forever. Item lookups cache lazily, on demand.
        var seen = Set<UInt64>()
        return (MPMediaQuery.songs().items ?? []).compactMap { item in
            guard seen.insert(item.persistentID).inserted else { return nil }
            return ClassSong(trackKey: "mp:\(item.persistentID)", title: item.title ?? "Unknown",
                             artist: item.artist ?? "Unknown",
                             durationSeconds: item.playbackDuration, bpm: nil)
        }
    }
}
#endif

/// Simulator / preview stand-in: fixture set as a fake playlist. Playback is a no-op.
final class PreviewPlaylistProvider: PlaylistProvider, Sendable {
    func playlists() -> [PlaylistSummary] {
        [PlaylistSummary(id: "fixtures", name: "Spin Fixtures (demo)", songCount: RealTrackFixturesSongs.count)]
    }

    func songs(in playlistID: String) -> [ClassSong] { RealTrackFixturesSongs }

    func startPlayback(trackKeys: [String]) {}

    func allSongs() -> [ClassSong] { RealTrackFixturesSongs }

    private var RealTrackFixturesSongs: [ClassSong] {
        [
            ClassSong(trackKey: "fx:wish", title: "Wish It Was You", artist: "Audien", durationSeconds: 204, bpm: 125),
            ClassSong(trackKey: "fx:cook", title: "COOK", artist: "SOFI TUKKER", durationSeconds: 170, bpm: 108),
            ClassSong(trackKey: "fx:bad", title: "Bad Angel", artist: "Anyma", durationSeconds: 222, bpm: 128),
            ClassSong(trackKey: "fx:broke", title: "No Broke Boys", artist: "Disco Lines", durationSeconds: 164, bpm: 131),
            ClassSong(trackKey: "fx:chem", title: "Love is a Chemical", artist: "ILLENIUM", durationSeconds: 218, bpm: 128),
            ClassSong(trackKey: "fx:strange", title: "Something Strange", artist: "Vicetone", durationSeconds: 190, bpm: 119),
            ClassSong(trackKey: "fx:lose", title: "If I Lose Myself", artist: "Alesso", durationSeconds: 206, bpm: 126),
            ClassSong(trackKey: "fx:pressure", title: "Pressure (Alesso Remix)", artist: "Nadia Ali", durationSeconds: 245, bpm: 128),
            ClassSong(trackKey: "fx:calling", title: "Calling (Lose My Mind)", artist: "Alesso", durationSeconds: 218, bpm: 125),
            ClassSong(trackKey: "fx:levels", title: "Levels", artist: "Avicii", durationSeconds: 213, bpm: 126),
        ]
    }
}

/// Picks the real provider when the library has playlists WITH SONGS; falls back to fixtures
/// (the simulator ships built-in empty playlists that would otherwise mask the demo).
@MainActor
func makePlaylistProvider() -> PlaylistProvider {
    #if canImport(MediaPlayer)
    let real = MediaLibraryPlaylistProvider()
    if real.playlists().contains(where: { $0.songCount > 0 }) { return real }
    #endif
    return PreviewPlaylistProvider()
}
