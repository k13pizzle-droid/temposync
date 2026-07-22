import Foundation
import RhythmCoachCore
#if canImport(UIKit)
import UIKit

/// Anything that can supply the current track's album artwork.
protocol ArtworkProviding {
    func currentArtwork(side: CGFloat) -> UIImage?
}
#endif
#if canImport(MediaPlayer)
import MediaPlayer

/// Mode H adapter: reads the system music player's current item + position (spec §B3) — track
/// identity and where we are, without ever hearing the audio — and controls transport so the
/// handlebar screen doubles as the music remote.
final class NowPlayingSourceMP: NowPlayingSource, PlaybackControls, @unchecked Sendable {
    private let player = MPMusicPlayerController.systemMusicPlayer

    // MARK: NowPlayingSource

    var nowPlaying: NowPlayingInfo? {
        guard let item = player.nowPlayingItem else { return nil }
        return NowPlayingInfo(
            trackKey: "mp:\(item.persistentID)",
            title: item.title ?? "Unknown",
            artist: item.artist ?? "Unknown",
            durationSeconds: item.playbackDuration
        )
    }

    func currentTime() -> Double { player.currentPlaybackTime }

    func isPlaying() -> Bool { player.playbackState == .playing }

    // MARK: PlaybackControls

    func play() { player.play() }
    func pause() { player.pause() }
    func nextTrack() { player.skipToNextItem() }
    func previousTrack() { player.skipToPreviousItem() }
    func seek(to seconds: Double) { player.currentPlaybackTime = max(0, seconds) }
}

extension NowPlayingSourceMP: ArtworkProviding {
    func currentArtwork(side: CGFloat) -> UIImage? {
        player.nowPlayingItem?.artwork?.image(at: CGSize(width: side, height: side))
    }
}
#endif
