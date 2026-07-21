import Foundation

/// Live Mode S session state (spec §B3 / §B6.3). Drives what the screen says and how hard the cues
/// are: only `locked` runs full choreography; `noisy` coasts on the last good lock with soft cues.
public enum ModeSState: Equatable, Sendable {
    case calibrating            // listening, no tempo lock yet
    case locked(bpm: Int)       // beat-locked, riding
    case coasting(bpm: Int)     // between analyses, predicting forward
    case noisy                  // signal-quality gate tripped — soft cues only, don't trust new tempo
}

/// Maintains a predictive beat grid for live Mode S. Each mic re-analysis feeds a fresh tempo + a
/// detected beat's wall-clock time; the estimator smooths tempo (EMA) and *nudges* phase toward the
/// detection rather than snapping, so the pulse never jumps. "Tap the 1" hard-resets phase.
///
/// Pure and deterministic — all times are injected, so it unit-tests without a mic or a clock.
public struct ModeSClockEstimator: Sendable, Equatable {
    public private(set) var bpm: Double
    /// Wall-clock time at which beat index 0 lands. Beats occur at `beatOffsetWall + k·period`.
    public private(set) var beatOffsetWall: Double

    /// EMA weight for new tempo estimates.
    public var bpmAlpha: Double = 0.3
    /// Fraction of the measured phase error corrected per analysis (0 = ignore, 1 = snap).
    public var phaseCorrectionGain: Double = 0.5

    public init(bpm: Double, firstBeatWallTime: Double) {
        self.bpm = max(bpm, 1)
        self.beatOffsetWall = firstBeatWallTime
    }

    public var periodSeconds: Double { 60.0 / bpm }

    /// Fold a new analysis in: smooth tempo, then gently correct phase toward the detected beat.
    public mutating func ingest(bpm newBPM: Double, detectedBeatWallTime: Double) {
        guard newBPM > 0 else { return }
        bpm = bpmAlpha * newBPM + (1 - bpmAlpha) * bpm
        let p = periodSeconds
        let rel = detectedBeatWallTime - beatOffsetWall
        let error = rel - (rel / p).rounded() * p     // nearest-beat phase error, in [-p/2, p/2]
        beatOffsetWall += error * phaseCorrectionGain
    }

    /// Manual "tap the 1": force a beat to land exactly on `wallTime` (fixes a drifted pulse).
    public mutating func tap(wallTime: Double) {
        let p = periodSeconds
        let rel = wallTime - beatOffsetWall
        beatOffsetWall = wallTime - (rel / p).rounded() * p
    }

    public func clock() -> BeatClock {
        BeatClock(bpm: bpm, beatOffset: beatOffsetWall)
    }

    /// Distance (seconds) from `wallTime` to the nearest predicted beat — used by tests and by the
    /// signal-quality display.
    public func phaseError(at wallTime: Double) -> Double {
        let p = periodSeconds
        let rel = wallTime - beatOffsetWall
        return abs(rel - (rel / p).rounded() * p)
    }
}
