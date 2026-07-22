import Foundation
import QuartzCore
import BeatKit
import RhythmCoachCore
#if canImport(AVFAudio)
import AVFAudio
#endif

/// Runs a calibration ride: the playlist plays out loud (phone speaker or external), the mic
/// listens, and each song's true structure is learned and stored keyed to the SAME track IDs
/// Mode H uses — so every later headphone class gets real chorus timing (spec §B6.4).
@MainActor
final class CalibrationViewModel: ObservableObject {
    enum SongState: Equatable {
        case pending
        case listening
        case learned(quality: Double)
        case skipped(String)      // heard too little / too noisy — reason shown
    }

    @Published private(set) var states: [String: SongState] = [:]
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var isRunning = false
    @Published private(set) var isComplete = false
    /// Mic permission is off: calibration cannot run (the view offers the Settings jump).
    @Published private(set) var micDenied = false

    private(set) var songs: [ClassSong] = []

    private var mic: MicAudioSource?
    private var nowPlaying: NowPlayingSource?
    private var analyzer: StreamingAnalyzer?
    private var currentKey: String?
    private var knownBPMs: [String: Double] = [:]
    private var pollTask: Task<Void, Never>?
    private var sawAnyTrack = false
    private var silentPolls = 0

    func start(songs: [ClassSong], provider: PlaylistProvider,
               nowPlaying: NowPlayingSource, mic: MicAudioSource) {
        // A denied mic used to "listen" to silence and mark every song too noisy — check first,
        // ask if never asked, and say plainly when access is off.
        #if canImport(AVFAudio)
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            micDenied = true
            statusLine = "Microphone access is off"
            return
        case .undetermined:
            // Async variant keeps everything on the main actor (the callback form would send
            // non-Sendable provider/mic values across isolation — Swift 6 rejects it).
            Task { @MainActor [weak self] in
                let granted = await AVAudioApplication.requestRecordPermission()
                guard let self else { return }
                if granted {
                    self.start(songs: songs, provider: provider, nowPlaying: nowPlaying, mic: mic)
                } else {
                    self.micDenied = true
                    self.statusLine = "Microphone access is off"
                }
            }
            return
        default:
            micDenied = false
        }
        #endif

        self.songs = songs
        self.nowPlaying = nowPlaying
        self.mic = mic
        for song in songs { states[song.trackKey] = .pending }

        // Resolve reference BPMs up front (octave insurance for every song).
        let waterfall = AppServices.makeBPMWaterfall()
        for song in songs {
            if let bpm = song.bpm { knownBPMs[song.trackKey] = bpm; continue }
            Task { @MainActor in
                if let hit = await waterfall.resolve(title: song.title, artist: song.artist) {
                    self.knownBPMs[song.trackKey] = hit.bpm
                }
            }
        }

        do {
            try mic.start { [weak self] samples, _ in
                Task { @MainActor in self?.analyzer?.feed(samples) }
            }
        } catch {
            statusLine = "Mic error: \(error.localizedDescription)"
            return
        }

        provider.startPlayback(trackKeys: songs.map { $0.trackKey })
        isRunning = true
        statusLine = "Listening — keep the phone near the speaker"

        pollTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                try? await Task.sleep(for: .seconds(1))
                pollOnce()
            }
        }
    }

    private func pollOnce() {
        guard let nowPlaying else { return }
        let info = nowPlaying.nowPlaying

        if info?.trackKey != currentKey {
            finalizeCurrent()
            if let info {
                sawAnyTrack = true
                silentPolls = 0
                currentKey = info.trackKey
                analyzer = StreamingAnalyzer(sampleRate: mic?.sampleRate ?? 44_100)
                if states[info.trackKey] != nil { states[info.trackKey] = .listening }
                statusLine = "Learning: \(info.title)"
            } else {
                currentKey = nil
                analyzer = nil
            }
            return
        }

        // Playlist finished? (a few nil polls after we've seen tracks)
        if info == nil, sawAnyTrack {
            silentPolls += 1
            if silentPolls >= 5 { complete() }
        }
    }

    private func finalizeCurrent() {
        guard let key = currentKey, let analyzer else { return }
        defer { self.analyzer = nil }

        let song = songs.first { $0.trackKey == key }
        let expected = song?.durationSeconds ?? 0

        // Must have heard most of the song for a whole-structure map to be trustworthy.
        guard expected == 0 || analyzer.durationSeconds >= expected * 0.6 else {
            states[key] = .skipped("heard too little")
            return
        }

        let result = analyzer.finalize(knownBPM: knownBPMs[key])
        guard result.analysis.tempo.bpm > 60, result.analysis.tempo.strength >= 0.08 else {
            states[key] = .skipped("too noisy")
            return
        }

        let map = SectionCapture().capture(trackKey: key, streamed: result)
        do {
            try SectionMapStore.upsert(map, in: AppServices.context)
            states[key] = .learned(quality: map.captureQuality)
        } catch {
            states[key] = .skipped("save failed")
        }
    }

    private func complete() {
        finalizeCurrent()
        isRunning = false
        isComplete = true
        let learned = states.values.filter { if case .learned = $0 { return true }; return false }.count
        statusLine = "Done — \(learned) of \(songs.count) songs learned"
        mic?.stop(); mic = nil
        pollTask?.cancel(); pollTask = nil
    }

    func stop() {
        guard isRunning || mic != nil else { return }
        complete()
    }
}
