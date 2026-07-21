import Foundation

/// A candidate track for cadence matching (spec §A). BPM comes from the shared resolver cache.
public struct RunTrack: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let bpm: Double
    public let camelot: String?
    public init(id: String, title: String, artist: String, bpm: Double, camelot: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.camelot = camelot
    }
}

public enum RunDecision: Sendable, Equatable {
    case keepCurrent
    case switchTo(RunTrack)
}

/// Minimal RunSync tempo engine — the documented v1 behaviors (spec §A / v1 §7): EMA cadence
/// smoothing, a ±6 BPM / 20 s dead band before re-targeting, half/double-time equivalence, a
/// no-repeat window, and ≤ 1 forced switch per 90 s. Pure and deterministic; feed it cadence
/// samples and it returns whether to change tracks.
public final class RunSyncEngine {
    // Tunables (v1 defaults).
    public var emaAlpha: Double = 0.2
    public var deadBandBPM: Double = 6
    public var deadBandSeconds: Double = 20
    public var minSecondsBetweenSwitches: Double = 90
    public var noRepeatWindow: Int = 3

    private let library: [RunTrack]
    private var smoothed: Double? = nil
    private var currentTrack: RunTrack? = nil
    private var currentTargetBPM: Double? = nil
    private var lastSwitchTime: Double = -.infinity
    private var deviationSince: Double? = nil
    private var recentIDs: [String] = []

    public init(library: [RunTrack]) {
        // Sort for deterministic tie-breaking.
        self.library = library.sorted { $0.id < $1.id }
    }

    public var smoothedCadence: Double? { smoothed }
    public var nowPlaying: RunTrack? { currentTrack }

    /// Ingest a cadence sample (steps/min) at time `now` (seconds). Returns a switch decision.
    @discardableResult
    public func ingest(cadence: Double, at now: Double) -> RunDecision {
        // 1. EMA smoothing.
        if let s = smoothed {
            smoothed = emaAlpha * cadence + (1 - emaAlpha) * s
        } else {
            smoothed = cadence
        }
        let target = smoothed!

        // 2. First track: pick immediately.
        guard let currentTargetBPM else {
            return startFirstTrack(target: target, now: now)
        }

        // 3. Dead band: ignore small cadence changes; require sustained deviation from the cadence
        //    we last committed a track at.
        let deviation = abs(target - currentTargetBPM)
        if deviation < deadBandBPM {
            deviationSince = nil
            return .keepCurrent
        }
        if deviationSince == nil { deviationSince = now }
        guard let since = deviationSince, now - since >= deadBandSeconds else {
            return .keepCurrent
        }

        // 4. Rate-limit forced switches.
        guard now - lastSwitchTime >= minSecondsBetweenSwitches else { return .keepCurrent }

        // 5. Pick the best fresh track for the new cadence.
        guard let pick = bestTrack(for: target) else { return .keepCurrent }
        if pick.id == currentTrack?.id { deviationSince = nil; return .keepCurrent }
        commit(pick, target: target, now: now)
        return .switchTo(pick)
    }

    private func startFirstTrack(target: Double, now: Double) -> RunDecision {
        guard let pick = bestTrack(for: target) else { return .keepCurrent }
        commit(pick, target: target, now: now)
        return .switchTo(pick)
    }

    private func commit(_ track: RunTrack, target: Double, now: Double) {
        currentTrack = track
        currentTargetBPM = target
        lastSwitchTime = now
        deviationSince = nil
        recentIDs.append(track.id)
        if recentIDs.count > noRepeatWindow { recentIDs.removeFirst(recentIDs.count - noRepeatWindow) }
    }

    /// Half/double-time-aware distance between a cadence and a track BPM: a track at the cadence, or
    /// at half or double it, all count as matches (spec §A "half/double-time equivalence").
    private func matchError(cadence: Double, trackBPM: Double) -> Double {
        let candidates = [trackBPM, trackBPM * 2, trackBPM / 2]
        return candidates.map { $0 - cadence }.min(by: { abs($0) < abs($1) }) ?? (trackBPM - cadence)
    }

    private func bestTrack(for cadence: Double) -> RunTrack? {
        let fresh = library.filter { !recentIDs.contains($0.id) }
        let pool = fresh.isEmpty ? library : fresh
        return pool.min(by: {
            abs(matchError(cadence: cadence, trackBPM: $0.bpm)) < abs(matchError(cadence: cadence, trackBPM: $1.bpm))
        })
    }
}
