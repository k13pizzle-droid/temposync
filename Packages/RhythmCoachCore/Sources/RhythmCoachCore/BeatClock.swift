import Foundation
import RoutineKit

/// Where we are on the beat grid at a given moment. `beatIndex` is the absolute count from the start
/// of the routine, so it maps 1:1 onto RoutineKit's `MoveEvent.startCount`.
public struct BeatPosition: Sendable, Equatable {
    public let beatIndex: Int      // 0-based count from the grid origin
    public let phase: Double       // 0...1 within the current beat (drives the pulse ring)
    public let countInPhrase: Int  // beatIndex % 32  (0...31)
    public let phraseIndex: Int    // beatIndex / 32
}

/// A predictive beat grid: given a tempo and the phase offset of beat 0, it extrapolates which beat
/// (and where within it) any wall-clock time falls on. In Mode S the mic analysis periodically
/// refreshes `bpm`/`beatOffset`; between refreshes the clock coasts, so the pulse stays smooth.
public struct BeatClock: Sendable, Equatable {
    public let bpm: Double
    /// Seconds (in the same timebase as the query) at which beat 0 lands.
    public let beatOffset: Double

    public init(bpm: Double, beatOffset: Double = 0) {
        self.bpm = bpm
        self.beatOffset = beatOffset
    }

    public var periodSeconds: Double { bpm > 0 ? 60.0 / bpm : 0 }

    public func position(at time: Double) -> BeatPosition {
        guard bpm > 0 else { return BeatPosition(beatIndex: 0, phase: 0, countInPhrase: 0, phraseIndex: 0) }
        let elapsed = time - beatOffset
        let beats = elapsed / periodSeconds
        let index = max(0, Int(beats.rounded(.down)))
        let phase = beats < 0 ? 0 : beats - beats.rounded(.down)
        let phraseLen = Routine.phraseLength   // 32
        return BeatPosition(
            beatIndex: index,
            phase: phase,
            countInPhrase: ((index % phraseLen) + phraseLen) % phraseLen,
            phraseIndex: index / phraseLen
        )
    }

    /// Wall-clock time of a given beat index (used to schedule Watch haptics / cue firing).
    public func time(ofBeat index: Int) -> Double {
        beatOffset + Double(index) * periodSeconds
    }
}
