import Foundation

/// Independent validators for every grammar rule in spec §B4. These deliberately re-derive the
/// rules from the emitted `Routine` (rather than trusting the generator's internal bookkeeping),
/// so they are a genuine check. Each returns a list of human-readable violations — empty means pass.
///
/// Used by both the XCTest suite (`swift test`) and the runnable `RoutineKitCheck` harness.
public enum Grammar {

    public static let dwellMinimum = 8
    public static let leadLegSpacing = 64     // ~2 phrases

    /// Longest CONTINUOUS stretch of upper-body work before the ride must return to the legs.
    /// 32 counts ≈ 15 s ≈ 8 push-ups at 128 BPM — an instructor's set, not an arm workout.
    public static let maxUpperBodyRun = 32
    /// Legs-only counts required after an upper-body run before the next one.
    public static let minUpperBodyGap = 16

    // MARK: Rule 1 — boundary alignment & no 2-counts

    public static func checkBoundaries(_ events: [MoveEvent]) -> [String] {
        var problems: [String] = []
        for e in events {
            if e.startCount % 4 != 0 {
                problems.append("Move '\(e.move.name)' at \(e.startCount) is off the 4-count grid")
            }
            if !e.move.allowedCounts.contains(e.counts) {
                problems.append("Move '\(e.move.name)' length \(e.counts) not in allowedCounts \(e.move.allowedCounts)")
            }
        }
        return problems
    }

    public static func checkNoTwoCounts(_ events: [MoveEvent]) -> [String] {
        events.compactMap { e in
            e.counts < dwellMinimum || e.counts % 4 != 0
                ? "Move '\(e.move.name)' has illegal length \(e.counts) (min \(dwellMinimum), multiple of 4)"
                : nil
        }
    }

    // MARK: Rule 4 — dwell minimum

    public static func checkDwellMinimum(_ events: [MoveEvent]) -> [String] {
        events.compactMap { e in
            e.counts < dwellMinimum ? "Move '\(e.move.name)' dwell \(e.counts) < \(dwellMinimum)" : nil
        }
    }

    // MARK: Rule 3 — resistance-floor precedence

    public static func checkResistanceFloor(_ events: [MoveEvent]) -> [String] {
        var problems: [String] = []
        var resistanceUp = false
        for e in events {
            // Apply this event's resistance-up cues first (they fire at/just before the move start).
            if e.cues.contains(where: { $0.type == .resistanceUp }) { resistanceUp = true }
            if e.move.needsResistance && !resistanceUp {
                problems.append("Move '\(e.move.name)' at \(e.startCount) needs resistance but none was cued first")
            }
            if e.cues.contains(where: { $0.type == .resistanceDown }) { resistanceUp = false }
        }
        return problems
    }

    // MARK: Rule 5 — upper-body density cap
    //
    // Spec amendment (2026-07-23, Kevin's choreography feedback): the original rule required every
    // pair of upper-body blocks to start ≥64 counts apart, which made SUSTAINED choreography
    // structurally illegal — push-ups and press-downs could only ever appear as one 16-count stab
    // (~7 s), while in a real SoulCycle/Peloton-style class a tap-back or push-up sequence is
    // routinely a song's main event. The cap now limits how long the rider works the upper body
    // CONTINUOUSLY, and demands legs in between, instead of forbidding repetition:
    //   · a continuous upper-body run may not exceed `maxUpperBodyRun`
    //   · consecutive runs are separated by ≥ `minUpperBodyGap` counts of leg work
    // Sustained choreography is now expressed as alternating sets ("8 push-ups, back to the beat"),
    // which is both what instructors actually cue and what keeps the legs turning.

    public static func checkDensityCap(_ events: [MoveEvent]) -> [String] {
        let sorted = events.sorted { $0.startCount < $1.startCount }
        var problems: [String] = []

        // Merge contiguous upper-body events into runs (tiled blocks of the same set are one run).
        var runs: [(start: Int, end: Int)] = []
        for event in sorted where event.move.upperBody {
            if let last = runs.last, event.startCount <= last.end {
                runs[runs.count - 1].end = max(last.end, event.endCount)
            } else {
                runs.append((event.startCount, event.endCount))
            }
        }

        for run in runs where run.end - run.start > maxUpperBodyRun {
            problems.append("Upper-body run at \(run.start) lasts \(run.end - run.start) counts (> \(maxUpperBodyRun))")
        }
        for i in 1..<max(runs.count, 1) where runs.count > 1 {
            let gap = runs[i].start - runs[i - 1].end
            if gap < minUpperBodyGap {
                problems.append("Only \(gap) counts of leg work between upper-body runs at \(runs[i-1].end) and \(runs[i].start) (< \(minUpperBodyGap))")
            }
        }
        return problems
    }

    // MARK: Rule 6 — mandatory step-down after 2 consecutive peak phrases
    //
    // Spec amendment (2026-07-21, Kevin's round-3 feedback): the original rule forced a full
    // RECOVERY phrase after 2 peak phrases, which parked the rider mid-chorus. Real classes step
    // down to sub-peak work (standing run) and keep the chorus as the workout's center of gravity.
    // The safety floor that remains: never 3 consecutive peak phrases — the phrase after 2 peaks
    // must be non-peak.

    public static func checkRecovery(_ routine: Routine) -> [String] {
        let phrases = phraseGrid(routine)
        var problems: [String] = []
        for i in 0..<phrases.count where i + 2 < phrases.count {
            if phrases[i].isPeak && phrases[i + 1].isPeak && phrases[i + 2].isPeak {
                problems.append("3 consecutive peak phrases starting at count \(phrases[i].start) — phrase after 2 peaks must step down")
            }
        }
        return problems
    }

    // MARK: Rule 2 — section affinity

    public static func checkSectionAffinity(_ events: [MoveEvent], sections: [Section]) -> [String] {
        let sorted = sections.sorted { $0.startCount < $1.startCount }
        var problems: [String] = []
        for e in events {
            guard let section = sectionCovering(e.startCount, in: sorted) else { continue }
            if !e.move.sectionAffinity.contains(section.type) {
                problems.append("Move '\(e.move.name)' at \(e.startCount) has no affinity for section '\(section.type.rawValue)'")
            }
        }
        return problems
    }

    // MARK: Rule 9 (hard part) — skill gating

    public static func checkSkillGating(_ events: [MoveEvent], skill: SkillTier) -> [String] {
        events.compactMap { e in
            e.move.skillTier > skill
                ? "Move '\(e.move.name)' (skill \(e.move.skillTier.rawValue)) exceeds rider skill \(skill.rawValue)"
                : nil
        }
    }

    // MARK: Rule 7 — lead-leg alternation

    public static func checkLeadLeg(_ events: [MoveEvent]) -> [String] {
        let switches = events.flatMap { $0.cues }.filter { $0.type == .leadLegSwitch }.map { $0.atCount }.sorted()
        guard switches.count > 1 else { return [] }
        var problems: [String] = []
        for i in 1..<switches.count {
            let gap = switches[i] - switches[i - 1]
            if gap < 48 || gap > 80 {   // ~2 phrases (64) with tolerance
                problems.append("Lead-leg switches at \(switches[i-1]) and \(switches[i]) are \(gap) counts apart (expected ~\(leadLegSpacing))")
            }
        }
        return problems
    }

    // MARK: Full pass

    public static func validate(_ routine: Routine, request: RoutineRequest) -> [String] {
        var problems: [String] = []
        problems += checkBoundaries(routine.events)
        problems += checkNoTwoCounts(routine.events)
        problems += checkDwellMinimum(routine.events)
        problems += checkResistanceFloor(routine.events)
        problems += checkDensityCap(routine.events)
        problems += checkRecovery(routine)
        problems += checkSectionAffinity(routine.events, sections: request.sections)
        problems += checkSkillGating(routine.events, skill: request.skillLevel)
        problems += checkLeadLeg(routine.events)
        return problems
    }

    // MARK: - Phrase grid helpers

    public struct PhraseSummary {
        public let start: Int
        public let isPeak: Bool
        public let isRecovery: Bool
    }

    /// Reconstruct the 32-count phrase grid and classify each phrase by the moves overlapping it.
    public static func phraseGrid(_ routine: Routine) -> [PhraseSummary] {
        let phraseLen = Routine.phraseLength
        var result: [PhraseSummary] = []
        var start = routine.startCount
        while start + phraseLen <= routine.endCount {
            let overlapping = routine.events.filter { $0.startCount < start + phraseLen && $0.endCount > start }
            let isPeak = overlapping.contains { $0.move.intensityTier == .peak }
            let isRecovery = !overlapping.isEmpty && overlapping.allSatisfy { $0.move.intensityTier == .recovery }
            result.append(PhraseSummary(start: start, isPeak: isPeak, isRecovery: isRecovery))
            start += phraseLen
        }
        return result
    }

    static func sectionCovering(_ count: Int, in sorted: [Section]) -> Section? {
        var result: Section? = nil
        for section in sorted where section.startCount <= count && count < section.endCount { result = section }
        if result == nil {
            for section in sorted where section.startCount <= count { result = section }
        }
        return result
    }
}
