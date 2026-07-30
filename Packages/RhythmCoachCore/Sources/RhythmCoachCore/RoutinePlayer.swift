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
    /// A non-empty form-cue text fired recently enough to still show (e.g. "Find the beat").
    /// Nil once its display window passes — the move's own static cue takes over.
    public let activeFormCue: String?
    /// True if resistance is currently raised (per the most recent resistance cue at or before count).
    public let resistanceUp: Bool
    /// Start count of the contiguous same-move BLOCK containing `count` (tiled events merged) —
    /// drives progressive animations like the jump cadence ladder.
    public let currentBlockStart: Int?
}

/// Reads a generated `Routine` at any count. The app advances `count` via a `BeatClock`; this type
/// turns that count into the concrete "what now / what next" the live screen renders.
///
/// Everything derivable from the immutable routine is precomputed here, once — `state(atCount:)`
/// is called at display refresh rate for the entire ride (up to 120 Hz on ProMotion phones), so it
/// answers with a few binary searches and zero allocations. (It used to sort the event array twice
/// and make four full scans per call, per frame.)
public struct RoutinePlayer: Sendable {
    public let routine: Routine

    private let events: [MoveEvent]                       // sorted by startCount (strictly increasing)
    private let blockStarts: [Int]                        // contiguous same-move run start, per event
    private let nextDifferent: [Int?]                     // index of the next different-move event, per event
    private let countdowns: [Cue]                         // countdown cues, atCount ascending
    private let maxCountdownLead: Int
    private let resistanceToggles: [(at: Int, up: Bool)]  // resistance cues, atCount ascending
    private let formCues: [(at: Int, text: String)]       // non-empty form cues, atCount ascending
    /// How long an event-level form cue stays on screen (counts) — half a phrase, ~7 s at 128 BPM.
    private static let formCueWindow = 16

    public init(routine: Routine) {
        self.routine = routine
        let sorted = routine.events.sorted { $0.startCount < $1.startCount }
        self.events = sorted

        // Block starts: track contiguous same-move runs so tiled 16-count events read as one block.
        var starts: [Int] = []
        starts.reserveCapacity(sorted.count)
        var runStart = Int.min, previousEnd = Int.min, previousName = ""
        for event in sorted {
            if !(event.move.name == previousName && event.startCount == previousEnd) {
                runStart = event.startCount
            }
            starts.append(runStart)
            previousEnd = event.endCount
            previousName = event.move.name
        }
        self.blockStarts = starts

        // "Next" = the next *different* move (class pacing emits long same-move runs; the rider
        // cares about the next transition, not the next internal tile boundary).
        var nexts = [Int?](repeating: nil, count: sorted.count)
        if sorted.count >= 2 {
            for i in stride(from: sorted.count - 2, through: 0, by: -1) {
                nexts[i] = sorted[i + 1].move.name != sorted[i].move.name ? i + 1 : nexts[i + 1]
            }
        }
        self.nextDifferent = nexts

        // Flat cue indexes. Event iteration order keeps atCounts ascending, and "last in iteration
        // order wins" below matches the original full-scan semantics exactly.
        var cds: [Cue] = []
        var toggles: [(at: Int, up: Bool)] = []
        var forms: [(at: Int, text: String)] = []
        for event in sorted {
            for cue in event.cues {
                switch cue.type {
                case .countdown:      cds.append(cue)
                case .resistanceUp:   toggles.append((cue.atCount, true))
                case .resistanceDown: toggles.append((cue.atCount, false))
                case .form where !cue.text.isEmpty:
                    forms.append((cue.atCount, cue.text))
                default:              break
                }
            }
        }
        self.countdowns = cds
        self.maxCountdownLead = cds.compactMap { $0.leadBeats }.max() ?? 0
        self.resistanceToggles = toggles
        self.formCues = forms
    }

    public func state(atCount count: Int) -> PlaybackState {
        var current: MoveEvent? = nil
        var currentBlockStart: Int? = nil
        var next: MoveEvent? = nil

        if let idx = lastEventStartingAtOrBefore(count) {
            if count < events[idx].endCount {
                current = events[idx]
                currentBlockStart = blockStarts[idx]
                next = nextDifferent[idx].map { events[$0] }
            } else {
                // Between events (or past the end): the next event is simply the first one after.
                next = idx + 1 < events.count ? events[idx + 1] : nil
            }
        } else {
            next = events.first    // before the first event
        }

        let countsUntilNext = next.map { $0.startCount - count }

        // Active countdown: the last cue (in event order) whose lead window covers `count`. Only
        // cues starting within `maxCountdownLead` of `count` can qualify — walk back at most that far.
        var activeCountdown: Cue? = nil
        if maxCountdownLead > 0, var i = lastIndex(in: countdowns, atOrBefore: count, key: { $0.atCount }) {
            while i >= 0, countdowns[i].atCount > count - maxCountdownLead {
                let cue = countdowns[i]
                if count < cue.atCount + (cue.leadBeats ?? 0) {
                    activeCountdown = cue
                    break
                }
                i -= 1
            }
        }

        // Resistance: the last toggle at or before `count` wins.
        var resistanceUp = false
        if let i = lastIndex(in: resistanceToggles, atOrBefore: count, key: { $0.at }) {
            resistanceUp = resistanceToggles[i].up
        }

        // Form cue: the most recent non-empty one, only while its display window lasts.
        var activeFormCue: String? = nil
        if let i = lastIndex(in: formCues, atOrBefore: count, key: { $0.at }),
           count < formCues[i].at + Self.formCueWindow {
            activeFormCue = formCues[i].text
        }

        return PlaybackState(
            currentEvent: current,
            nextEvent: next,
            countsUntilNext: countsUntilNext,
            activeCountdown: activeCountdown,
            activeFormCue: activeFormCue,
            resistanceUp: resistanceUp,
            currentBlockStart: currentBlockStart
        )
    }

    // MARK: Binary searches (rightmost element with key <= count)

    private func lastEventStartingAtOrBefore(_ count: Int) -> Int? {
        lastIndex(in: events, atOrBefore: count, key: { $0.startCount })
    }

    private func lastIndex<T>(in array: [T], atOrBefore count: Int, key: (T) -> Int) -> Int? {
        var lo = 0, hi = array.count - 1
        var answer: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if key(array[mid]) <= count {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer
    }
}
