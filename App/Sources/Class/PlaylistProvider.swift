import Foundation
import RhythmCoachCore
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
protocol PlaylistProvider {
    func playlists() -> [PlaylistSummary]
    func songs(in playlistID: String) -> [ClassSong]
    /// Queue the given tracks (by trackKey, in class order) on the system player and start playing.
    func startPlayback(trackKeys: [String])
}

#if canImport(MediaPlayer)
/// Real adapter: `MPMediaQuery` reads Apple Music playlists under the existing media-library
/// permission (no MusicKit entitlement needed); playback queues on the same system player the
/// transport bar already controls.
final class MediaLibraryPlaylistProvider: PlaylistProvider {
    private var itemsByKey: [String: MPMediaItem] = [:]

    init() {
        // Fire-and-forget authorization; first open may show the permission prompt.
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { _ in }
        }
    }

    func playlists() -> [PlaylistSummary] {
        let collections = MPMediaQuery.playlists().collections ?? []
        return collections.compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist else { return nil }
            let name = (playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String) ?? "Playlist"
            return PlaylistSummary(id: String(playlist.persistentID), name: name,
                                   songCount: playlist.items.count)
        }
    }

    func songs(in playlistID: String) -> [ClassSong] {
        let collections = MPMediaQuery.playlists().collections ?? []
        guard let playlist = collections.first(where: {
            String(($0 as? MPMediaPlaylist)?.persistentID ?? 0) == playlistID
        }) else { return [] }
        return playlist.items.map { item in
            let key = "mp:\(item.persistentID)"
            itemsByKey[key] = item
            return ClassSong(trackKey: key,
                             title: item.title ?? "Unknown",
                             artist: item.artist ?? "Unknown",
                             durationSeconds: item.playbackDuration,
                             bpm: nil)
        }
    }

    func startPlayback(trackKeys: [String]) {
        let items = trackKeys.compactMap { itemsByKey[$0] }
        guard !items.isEmpty else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.play()
    }
}
#endif

/// Simulator / preview stand-in: Kevin's fixture set as a fake playlist. Playback is a no-op.
final class PreviewPlaylistProvider: PlaylistProvider {
    func playlists() -> [PlaylistSummary] {
        [PlaylistSummary(id: "fixtures", name: "Spin Fixtures (demo)", songCount: RealTrackFixturesSongs.count)]
    }

    func songs(in playlistID: String) -> [ClassSong] { RealTrackFixturesSongs }

    func startPlayback(trackKeys: [String]) {}

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
