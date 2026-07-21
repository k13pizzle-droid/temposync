import Foundation
import RoutineKit

/// What the routine says should be happening at a given count: the active move, what's next, and any
/// cue that is currently live. Pure lookup over a `Routine` — no timers, fully testable.
public struct PlaybackState: Sendable, Equatable {
    public let currentEvent: MoveEvent?
    public let nextEvent: MoveEvent?
    /// Counts remaining until `nextEvent` starts.
    public let countsUntilNext: Int?
    /// A countdown cue whose lead window covers `count` (e.g. "JUMPS in 8"). Nil if none active.
    public let activeCountdown: Cue?
    /// True if resistance is currently raised (per the most recent resistance cue at or before count).
    public let resistanceUp: Bool
    /// Start count of the contiguous same-move BLOCK containing `count` (tiled events merged) —
    /// drives progressive animations like the jump cadence ladder.
    public let currentBlockStart: Int?
}

/// Reads a generated `Routine` at any count. The app advances `count` via a `BeatClock`; this type
/// turns that count into the concrete "what now / what next" the live screen renders.
public struct RoutinePlayer: Sendable {
    public let routine: Routine

    public init(routine: Routine) {
        self.routine = routine
    }

    public func state(atCount count: Int) -> PlaybackState {
        let events = routine.events
        var current: MoveEvent? = nil
        var currentBlockStart: Int? = nil

        // Track contiguous same-move runs so tiled 16-count events read as one block.
        var runStart = Int.min
        var previousEnd = Int.min
        var previousName = ""
        for event in events.sorted(by: { $0.startCount < $1.startCount }) {
            if !(event.move.name == previousName && event.startCount == previousEnd) {
                runStart = event.startCount
            }
            if event.startCount <= count && count < event.endCount {
                current = event
                currentBlockStart = runStart
            }
            previousEnd = event.endCount
            previousName = event.move.name
        }

        // "Next" = the next *different* move. Class-style pacing emits long runs of same-move
        // blocks; the rider cares about the next transition, not the next internal block boundary.
        var next: MoveEvent? = nil
        for event in events.sorted(by: { $0.startCount < $1.startCount }) {
            guard event.startCount > count else { continue }
            if let currentMove = current?.move.name, event.move.name == currentMove { continue }
            next = event
            break
        }

        let countsUntilNext = next.map { $0.startCount - count }

        // Active countdown: a countdown cue that has fired (atCount <= count) but whose move has not
        // yet started (atCount + leadBeats > count).
        var activeCountdown: Cue? = nil
        for event in events {
            for cue in event.cues where cue.type == .countdown {
                let lead = cue.leadBeats ?? 0
                if cue.atCount <= count && count < cue.atCount + lead {
                    activeCountdown = cue
                }
            }
        }

        // Resistance state: last resistance cue at or before `count` wins.
        var resistanceUp = false
        var lastResistanceAt = Int.min
        for event in events {
            for cue in event.cues where cue.type == .resistanceUp || cue.type == .resistanceDown {
                if cue.atCount <= count && cue.atCount >= lastResistanceAt {
                    lastResistanceAt = cue.atCount
                    resistanceUp = (cue.type == .resistanceUp)
                }
            }
        }

        return PlaybackState(
            currentEvent: current,
            nextEvent: next,
            countsUntilNext: countsUntilNext,
            activeCountdown: activeCountdown,
            resistanceUp: resistanceUp,
            currentBlockStart: currentBlockStart
        )
    }
}
