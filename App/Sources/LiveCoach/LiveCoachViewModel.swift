import Foundation
import QuartzCore
import RoutineKit
import BeatKit
import RhythmCoachCore

/// Drives the live screen. Publishes only low-frequency state (status, mode); the per-frame
/// `LiveFrame` is *pulled* by the view via `currentFrame()` inside a `TimelineView(.animation)`,
/// so the pulse renders at display refresh rate with no timer jitter (the old 30 Hz published-frame
/// loop is what made the ride feel choppy).
@MainActor
final class LiveCoachViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var modeSState: ModeSState? = nil     // non-nil only in Mode S
    @Published private(set) var hasContent = false

    // Current render inputs (read by currentFrame(), swapped atomically on the main actor).
    private var coach: LiveCoach?

    // Mode H: anchor + extrapolation over the coarse (3 Hz) playback-position polls, so the pulse
    // doesn't judder with polling jitter (spec §B3: poll 2–4 Hz, smoothed).
    private var playbackAnchor: (position: Double, wall: Double)?
    private var pollTask: Task<Void, Never>?

    // Mode S plumbing.
    private var mic: MicAudioSource?
    private var ring = RollingBuffer(seconds: 10, sampleRate: 44_100)
    private var estimator: ModeSClockEstimator?
    private var analyzeTask: Task<Void, Never>?
    private var knownBPM: Double?
    private var recentRawBPMs: [Double] = []

    /// Autocorrelation strength below this → don't trust the analysis at all.
    private let qualityFloor = 0.15
    /// If recent raw tempo estimates disagree by more than this, the room is too messy to re-lock —
    /// coast and say so instead of chasing noise (§B6.3: a wrong SPRINT NOW is worse than a soft cue).
    private let bpmStabilitySpread = 5.0

    private func now() -> Double { CACurrentMediaTime() }

    // MARK: Frame pull (called by TimelineView at display refresh rate)

    func currentFrame() -> LiveFrame {
        guard let coach else { return .idle }
        let t: Double
        if let anchor = playbackAnchor {
            // Mode H: extrapolated playback position; frozen while paused (the pulse holds still).
            t = isPlayingNow ? anchor.position + (now() - anchor.wall) : anchor.position
        } else {
            t = now()                                       // Demo / Mode S: wall clock
        }
        return coach.frame(at: t)
    }

    /// Current playback position in seconds (Mode H) — drives the scrubber.
    var playbackPosition: Double {
        guard let anchor = playbackAnchor else { return 0 }
        return isPlayingNow ? anchor.position + (now() - anchor.wall) : anchor.position
    }

    var playbackDuration: Double { currentInfo?.durationSeconds ?? 0 }

    // MARK: Demo (simulated)

    func startDemo() {
        let request = SampleSongs.edmAnthem(seed: 7, skill: .three, intensity: .hard, confidence: .learned)
        let routine = RoutineGenerator().generate(request)
        coach = LiveCoach(routine: routine, clock: BeatClock(bpm: request.bpm, beatOffset: now()),
                          sections: request.sections, confidence: .learned)
        statusLine = "Demo ride"
        hasContent = true
        isRunning = true
        startWatchCues()
    }

    // MARK: Mode H — headphones (metadata-driven)

    private var nowPlayingSource: NowPlayingSource?
    private var controls: PlaybackControls?
    private var currentTrackKey: String?
    private var currentInfo: NowPlayingInfo?
    private var waterfall: BPMWaterfall?
    @Published private(set) var isPlayingNow = true

    // Ride-history bookkeeping.
    private var sessionStart: Date?
    private var songsSeen = 0

    // Watch cue diffing (1 Hz): send only on state CHANGES so the wrist buzzes at transitions,
    // never continuously.
    private var watchTask: Task<Void, Never>?
    private var lastWatchMove = ""
    private var lastWatchResistance = false
    private var lastWatchCountdown: String?

    private func startWatchCues() {
        #if canImport(WatchConnectivity)
        watchTask?.cancel()
        lastWatchMove = ""; lastWatchResistance = false; lastWatchCountdown = nil
        watchTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                try? await Task.sleep(for: .seconds(1))
                pushWatchState()
            }
        }
        #endif
    }

    private func pushWatchState() {
        #if canImport(WatchConnectivity)
        let frame = currentFrame()
        guard frame.bpm > 0 else { return }
        if frame.currentMoveName != lastWatchMove, frame.currentMoveName != "—" {
            lastWatchMove = frame.currentMoveName
            WatchCueSender.shared.moveChanged(name: frame.currentMoveName,
                                              rpm: frame.suggestedRPM, bpm: Int(frame.bpm))
        }
        if frame.resistanceUp != lastWatchResistance {
            lastWatchResistance = frame.resistanceUp
            WatchCueSender.shared.resistance(up: frame.resistanceUp)
        }
        if let countdown = frame.countdownText, countdown != lastWatchCountdown {
            lastWatchCountdown = countdown
            WatchCueSender.shared.countdown(text: countdown)
        } else if frame.countdownText == nil {
            lastWatchCountdown = nil
        }
        #endif
    }

    var hasTransport: Bool { controls != nil }

    func startModeH(nowPlaying: NowPlayingSource, controls: PlaybackControls?, waterfall: BPMWaterfall) {
        self.nowPlayingSource = nowPlaying
        self.controls = controls
        self.waterfall = waterfall
        sessionStart = .now
        songsSeen = 0
        isRunning = true
        startWatchCues()

        if let info = nowPlaying.nowPlaying {
            configureModeH(for: info)
        } else {
            statusLine = "Nothing playing — start a song in the Music app"
        }

        // 3 Hz poll: play-state + track-change detection + playback-position anchor smoothing.
        pollTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                try? await Task.sleep(for: .milliseconds(333))
                guard let source = nowPlayingSource else { continue }

                let playing = source.isPlaying()
                if playing != isPlayingNow { isPlayingNow = playing }

                // Track changed (or started/stopped)? Rebuild for the new song.
                let info = source.nowPlaying
                if info?.trackKey != currentTrackKey {
                    if let info {
                        configureModeH(for: info)
                    } else {
                        currentTrackKey = nil
                        currentInfo = nil
                        coach = nil
                        hasContent = false
                        statusLine = "Nothing playing"
                    }
                    continue
                }

                // Paused → hold the anchor at the measured position (frozen pulse, honest scrubber).
                guard playing else {
                    playbackAnchor = (source.currentTime(), now())
                    continue
                }

                // Anchor smoothing: snap on a scrub, micro-correct otherwise (no judder).
                let measured = source.currentTime()
                guard let anchor = playbackAnchor else { continue }
                let expected = anchor.position + (now() - anchor.wall)
                let error = measured - expected
                if abs(error) > 0.4 {
                    playbackAnchor = (measured, now())
                } else {
                    playbackAnchor = (expected + error * 0.2, now())
                }
            }
        }
    }

    // MARK: Transport (Mode H remote)

    func togglePlayPause() {
        guard let controls else { return }
        if isPlayingNow { controls.pause() } else { controls.play() }
        isPlayingNow.toggle()                      // optimistic; the poll confirms within 333 ms
    }

    func nextTrack() { controls?.nextTrack() }     // poll picks up the new track ≤333 ms later
    func previousTrack() { controls?.previousTrack() }

    /// Seek relative (e.g. ±15 s), clamped to the track.
    func skip(by seconds: Double) {
        scrub(to: playbackPosition + seconds)
    }

    /// Seek absolute — used by the scrubber on drag end.
    func scrub(to seconds: Double) {
        guard let controls else { return }
        let clamped = min(max(seconds, 0), max(playbackDuration - 1, 0))
        controls.seek(to: clamped)
        playbackAnchor = (clamped, now())          // snap immediately; poll reconciles after
    }

    /// (Re)build the routine for a track: learned SectionMap if one exists, BPM via the waterfall
    /// (cache/seed immediately; the API rung fills in asynchronously and rebuilds at the true tempo).
    private func configureModeH(for info: NowPlayingInfo) {
        currentTrackKey = info.trackKey
        currentInfo = info
        songsSeen += 1
        playbackAnchor = (nowPlayingSource?.currentTime() ?? 0, now())

        let learnedMap = try? SectionMapStore.map(for: info.trackKey, in: AppServices.context)
        let local = waterfall?.resolveLocally(title: info.title, artist: info.artist)

        buildModeHRoutine(info: info, map: learnedMap, bpm: learnedMap?.bpm ?? local?.bpm,
                          bpmKnown: learnedMap != nil || local != nil)

        // No local answer → ask the API (once per song, ever — result is cached).
        if learnedMap == nil, local == nil, let waterfall {
            let trackKey = info.trackKey
            Task { @MainActor in
                guard let resolved = await waterfall.resolve(title: info.title, artist: info.artist),
                      self.currentTrackKey == trackKey else { return }
                self.buildModeHRoutine(info: info, map: nil, bpm: resolved.bpm, bpmKnown: true)
            }
        }
    }

    private func buildModeHRoutine(info: NowPlayingInfo, map: CapturedMap?, bpm: Double?, bpmKnown: Bool) {
        let bpmValue = bpm ?? 128
        let confidence: MapConfidence = map != nil ? .learned : .prior
        let sections = map?.sections
            ?? StructurePrior().sections(bpm: bpmValue, durationSeconds: info.durationSeconds, genre: .edmPop)
        // In a built class, this song's arc role steers the plan (jumps early, arms late, etc.).
        // Effort + skill come from Settings → Ride.
        let role = AppServices.activeClassPlan?.role(for: info.trackKey)
        let request = RoutineRequest(trackKey: info.trackKey, bpm: bpmValue, sections: sections,
                                     confidence: confidence, skillLevel: AppServices.skill,
                                     intensity: AppServices.effort, seed: 1, classRole: role)
        coach = LiveCoach(routine: RoutineGenerator().generate(request),
                          clock: BeatClock(bpm: bpmValue, beatOffset: 0),  // grid origin = position 0
                          sections: sections, confidence: confidence)
        hasContent = true

        let bpmLabel: String
        if map != nil { bpmLabel = "learned map" }
        else if bpmKnown { bpmLabel = "\(Int(bpmValue)) BPM" }
        else { bpmLabel = "BPM est." }   // both tempo services missed this song — honest default
        statusLine = "\(info.title) — \(bpmLabel)"
    }

    // MARK: Mode S — speaker (mic-driven, live)

    /// `nowPlaying` is optional but powerful: if the song is playing from this phone's Music app,
    /// its identity gives us the reference BPM (killing half/double errors) and a stable track key.
    func startModeS(mic: MicAudioSource, nowPlaying: NowPlayingSource? = nil) {
        self.mic = mic
        ring = RollingBuffer(seconds: 10, sampleRate: mic.sampleRate)
        modeSState = .calibrating
        statusLine = "Listening for the beat…"

        if let info = nowPlaying?.nowPlaying,
           let ref = TrackTempoResolver().lookup(title: info.title, artist: info.artist) {
            knownBPM = ref.referenceBPM
            statusLine = "Listening — expecting ~\(Int(ref.referenceBPM ?? 0)) BPM (\(info.title))"
        }

        do {
            try mic.start { [weak self] samples, captureTime in
                Task { @MainActor in self?.ring.append(samples, endingAt: captureTime) }
            }
        } catch {
            statusLine = "Mic error: \(error.localizedDescription)"
            return
        }
        isRunning = true
        analyzeTask = Task { @MainActor in
            let analyzer = BeatAnalyzer()
            while !Task.isCancelled && isRunning {
                try? await Task.sleep(for: .milliseconds(1500))
                analyzeOnce(analyzer)
            }
        }
    }

    private func analyzeOnce(_ analyzer: BeatAnalyzer) {
        let (buffer, bufferEndWall) = ring.snapshot()
        guard buffer.samples.count > Int(buffer.sampleRate * 4), bufferEndWall > 0 else { return }
        let analysis = analyzer.analyze(buffer, knownBPM: knownBPM)

        // Gate 1 — raw quality floor.
        guard analysis.tempo.bpm > 60, analysis.tempo.strength >= qualityFloor else {
            markNoisy()
            return
        }

        // Gate 2 — stability: recent raw estimates must agree before we (re)trust the tempo.
        recentRawBPMs.append(analysis.tempo.bpm)
        if recentRawBPMs.count > 4 { recentRawBPMs.removeFirst() }
        if recentRawBPMs.count >= 3 {
            let lo = recentRawBPMs.min()!, hi = recentRawBPMs.max()!
            if hi - lo > bpmStabilitySpread {
                markNoisy()
                return
            }
        } else if estimator == nil {
            statusLine = "Locking on… \(Int(analysis.tempo.bpm)) BPM?"
            return   // need agreement before the first lock
        }

        // Wall-clock time of the last detected beat: capture-timestamped, so this is accurate.
        let lastBeat = analysis.grid.beatTimes.last ?? 0
        let beatWall = bufferEndWall - (buffer.durationSeconds - lastBeat)

        if estimator == nil {
            estimator = ModeSClockEstimator(bpm: analysis.tempo.bpm, firstBeatWallTime: beatWall)
            estimator!.bpmAlpha = 0.25
            estimator!.phaseCorrectionGain = 0.35
            buildModeSRoutine(bpm: analysis.tempo.bpm)
        } else {
            estimator!.ingest(bpm: analysis.tempo.bpm, detectedBeatWallTime: beatWall)
            refreshModeSClock()
        }
        modeSState = .locked(bpm: Int(estimator!.bpm.rounded()))
        statusLine = "Locked \(Int(estimator!.bpm.rounded())) BPM"
    }

    private func markNoisy() {
        recentRawBPMs.removeAll()
        if estimator != nil {
            modeSState = .noisy
            statusLine = "Signal noisy — soft cues, coasting"
        } else {
            statusLine = "Can't hear a beat yet — is the music close enough?"
        }
    }

    private func buildModeSRoutine(bpm: Double) {
        // Beat/tempo are live-locked, but structure is heuristic on a first listen → prior cues.
        let sections = StructurePrior().sections(bpm: bpm, durationSeconds: 360, genre: .edmPop)
        let request = RoutineRequest(trackKey: "modeS:live", bpm: bpm, sections: sections,
                                     confidence: .prior, skillLevel: .two, intensity: .hard, seed: 3)
        coach = LiveCoach(routine: RoutineGenerator().generate(request),
                          clock: estimator!.clock(), sections: sections, confidence: .prior)
        hasContent = true
    }

    private func refreshModeSClock() {
        guard let coach, let estimator else { return }
        self.coach = LiveCoach(routine: coach.routine, clock: estimator.clock(),
                               sections: coach.sections, confidence: coach.confidence)
    }

    /// "Tap the 1" — align the pulse to where the rider feels the downbeat.
    func tapOne() {
        guard estimator != nil else { return }
        estimator!.tap(wallTime: now())
        refreshModeSClock()
        statusLine = "Re-synced to your tap"
    }

    func stop() {
        // Log rides over 2 minutes to history before tearing the session down.
        if let start = sessionStart {
            let elapsed = Date.now.timeIntervalSince(start)
            if elapsed > 120 {
                let record = RideLogRecord(
                    startedAt: start,
                    durationMinutes: elapsed / 60,
                    songsPlayed: songsSeen,
                    formatMinutes: AppServices.activeClassPlan?.format.minutes,
                    reordered: AppServices.activeClassPlan?.reordered
                )
                AppServices.context.insert(record)
                try? AppServices.context.save()
            }
        }
        sessionStart = nil
        songsSeen = 0
        AppServices.activeClassPlan = nil

        isRunning = false
        watchTask?.cancel(); watchTask = nil
        #if canImport(WatchConnectivity)
        WatchCueSender.shared.idle()
        #endif
        analyzeTask?.cancel(); analyzeTask = nil
        pollTask?.cancel(); pollTask = nil
        mic?.stop(); mic = nil
        estimator = nil
        knownBPM = nil
        recentRawBPMs.removeAll()
        playbackAnchor = nil
        nowPlayingSource = nil
        controls = nil
        currentTrackKey = nil
        currentInfo = nil
        isPlayingNow = true
        waterfall = nil
        modeSState = nil
        coach = nil
        hasContent = false
        statusLine = "Stopped"
    }
}

/// Fixed-duration ring of mono samples whose end is pinned to a capture timestamp, so any sample's
/// wall-clock time can be recovered exactly.
struct RollingBuffer {
    private var samples: [Float] = []
    private var endWall: Double = 0
    private let capacity: Int
    let sampleRate: Double

    init(seconds: Double, sampleRate: Double) {
        self.sampleRate = sampleRate
        self.capacity = max(1, Int(seconds * sampleRate))
    }

    /// `captureTime` is the host time of the FIRST sample in `new`.
    mutating func append(_ new: [Float], endingAt captureTime: Double) {
        samples.append(contentsOf: new)
        endWall = captureTime + Double(new.count) / sampleRate
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    /// The buffer plus the wall-clock time of its final sample.
    func snapshot() -> (AudioBuffer, endWall: Double) {
        (AudioBuffer(samples: samples, sampleRate: sampleRate), endWall)
    }
}
