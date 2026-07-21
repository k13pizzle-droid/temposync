import Foundation

/// Identity + position of whatever is currently playing (spec §B3 Mode H). Supplied by
/// `MPMusicPlayerController` on device; faked in tests and the simulator.
public struct NowPlayingInfo: Sendable, Equatable {
    public let trackKey: String
    public let title: String
    public let artist: String
    public let durationSeconds: Double
    public init(trackKey: String, title: String, artist: String, durationSeconds: Double) {
        self.trackKey = trackKey
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
    }
}

/// A source of "what's playing and where are we in it" for Mode H. The concrete iOS adapter polls
/// `MPMusicPlayerController.currentPlaybackTime` (spec §B3); protocol keeps Core testable.
public protocol NowPlayingSource: AnyObject, Sendable {
    var nowPlaying: NowPlayingInfo? { get }
    /// Current playback position in seconds.
    func currentTime() -> Double
    /// Whether playback is actively running (false = paused/stopped → the beat clock freezes).
    func isPlaying() -> Bool
}

/// Transport control over the system player — lets the handlebar screen double as the music remote
/// (play/pause, previous/next track, seek). Backed by `MPMusicPlayerController` on device.
public protocol PlaybackControls: AnyObject, Sendable {
    func play()
    func pause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
}

/// A source of streaming mic audio for Mode S. The iOS adapter wraps `AVAudioEngine`'s input tap.
///
/// `captureHostTime` is the host-clock time (same timebase as `CACurrentMediaTime()`) at which the
/// FIRST sample of the delivered buffer was captured by the hardware. Beat-phase accuracy depends on
/// this: stamping audio "when it happened" rather than "when we got around to processing it" is the
/// difference between a pulse that sits on the beat and one that trails it by 100–200 ms.
public protocol MicAudioSource: AnyObject, Sendable {
    var sampleRate: Double { get }
    func start(onBuffer: @escaping @Sendable (_ samples: [Float], _ captureHostTime: Double) -> Void) throws
    func stop()
}

// (CadenceSource — RunSync — shelved 2026-07-21 → Shelved/RunSync/)
