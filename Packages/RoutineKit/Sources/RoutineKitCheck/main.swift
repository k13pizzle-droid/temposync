import Foundation
import RoutineKit

// Runnable assertion harness — mirrors RoutineKitTests so the §B4 grammar can be verified with only
// the Command Line Tools installed (`swift run RoutineKitCheck`). Exits non-zero on any failure.

final class Reporter {
    var failures = 0
    func check(_ name: String, _ problems: [String]) {
        if problems.isEmpty {
            print("  ✅ \(name)")
        } else {
            failures += problems.count
            print("  ❌ \(name)")
            for p in problems.prefix(6) { print("       - \(p)") }
            if problems.count > 6 { print("       … and \(problems.count - 6) more") }
        }
    }
    func expect(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition { print("  ✅ \(name)") }
        else { failures += 1; print("  ❌ \(name)  \(detail)") }
    }
}

let r = Reporter()
let gen = RoutineGenerator()

print("RoutineKit — grammar verification (spec §B4)\n")

// Representative song, most demanding settings (skill 3, hard intensity, learned map).
let request = SampleSongs.edmAnthem()
let routine = gen.generate(request)
print("Generated \(routine.events.count) move events over \(routine.endCount) counts "
      + "(\(routine.endCount / 32) phrases) at \(Int(request.bpm)) BPM\n")

print("§B4 grammar rules:")
r.check("Rule 1 — boundary alignment (starts on 4-count grid, length in allowedCounts)",
        Grammar.checkBoundaries(routine.events))
r.check("Rule 1 — never a 2-count move",
        Grammar.checkNoTwoCounts(routine.events))
r.check("Rule 2 — section affinity",
        Grammar.checkSectionAffinity(routine.events, sections: request.sections))
r.check("Rule 3 — resistance-floor precedence",
        Grammar.checkResistanceFloor(routine.events))
r.check("Rule 4 — dwell minimum (≥ 8 counts)",
        Grammar.checkDwellMinimum(routine.events))
r.check("Rule 5 — upper-body density cap (≤ 1 / 2 phrases)",
        Grammar.checkDensityCap(routine.events))
r.check("Rule 6 — step-down after 2 peak phrases (never 3 consecutive)",
        Grammar.checkRecovery(routine))
r.check("Rule 7 — lead-leg alternation (~every 2 phrases)",
        Grammar.checkLeadLeg(routine.events))
r.check("Rule 9 — skill gating (no move above rider skill)",
        Grammar.checkSkillGating(routine.events, skill: request.skillLevel))

print("\n§B4 rule 8 — determinism & reshuffle:")
let a = gen.generate(request)
let b = gen.generate(request)
r.expect("same (track, seed) → identical routine", a == b)

let reshuffled = gen.generate(SampleSongs.edmAnthem(seed: 43))
r.expect("different seed → different routine", reshuffled != a)

// Same seed, different track key ⇒ the key must fold into the RNG and change the routine.
let diffTrack = RoutineRequest(trackKey: "sample:other-track", bpm: request.bpm,
                               sections: request.sections, confidence: request.confidence,
                               skillLevel: request.skillLevel, intensity: request.intensity,
                               seed: request.seed)
r.expect("same seed, different track key → different routine", gen.generate(diffTrack) != a)

print("\n§B4 rule 9 — intensity dial biases effort:")
func avgIntensity(_ routine: Routine) -> Double {
    let total = routine.events.reduce(0) { $0 + $1.counts }
    guard total > 0 else { return 0 }
    let weighted = routine.events.reduce(0.0) { $0 + Double($1.move.intensityTier.rawValue * $1.counts) }
    return weighted / Double(total)
}
let easy = gen.generate(SampleSongs.edmAnthem(seed: 7, intensity: .easy))
let hard = gen.generate(SampleSongs.edmAnthem(seed: 7, intensity: .hard))
let easyAvg = avgIntensity(easy), hardAvg = avgIntensity(hard)
r.expect("hard dial average effort > easy dial average effort",
         hardAvg > easyAvg, String(format: "(easy %.2f vs hard %.2f)", easyAvg, hardAvg))
print(String(format: "     easy avg tier = %.2f, hard avg tier = %.2f", easyAvg, hardAvg))

print("\n§B3 — prior maps soften cues (no hard countdowns):")
let prior = gen.generate(SampleSongs.edmAnthem(seed: 7, confidence: .prior))
let priorHasCountdown = prior.events.flatMap { $0.cues }.contains { $0.type == .countdown }
let learnedHasCountdown = routine.events.flatMap { $0.cues }.contains { $0.type == .countdown }
r.expect("learned map emits countdowns", learnedHasCountdown)
r.expect("prior map emits NO countdowns", !priorHasCountdown)

print("\n§B4 rule 9 — skill gating limits vocabulary:")
let novice = gen.generate(SampleSongs.edmAnthem(seed: 7, skill: .one))
let noviceMax = novice.events.map { $0.move.skillTier.rawValue }.max() ?? 0
r.expect("skill-1 rider never gets a skill-2+ move", noviceMax == 1, "(max seen \(noviceMax))")

print("\nFull validation pass:")
r.check("all §B4 rules together", Grammar.validate(routine, request: request))

print("\nFuzz sweep — grammar must hold across many settings:")
var fuzzViolations: [String] = []
var fuzzRuns = 0
for seed in UInt64(0)..<120 {
    for skill in SkillTier.allCases {
        for dial in [IntensityDial.easy, .medium, .hard] {
            for conf in MapConfidence.allCases {
                let req = SampleSongs.edmAnthem(seed: seed, skill: skill, intensity: dial, confidence: conf)
                let rt = gen.generate(req)
                let problems = Grammar.validate(rt, request: req)
                if !problems.isEmpty {
                    fuzzViolations.append("seed \(seed) skill \(skill.rawValue) dial \(dial.value) \(conf.rawValue): \(problems.first!)")
                }
                fuzzRuns += 1
            }
        }
    }
}
print("     ran \(fuzzRuns) generations")
r.check("grammar holds across full fuzz sweep", fuzzViolations)

// Resistance eases off (round-9 regression): the down-cue must actually fire — it used to key on
// the .recovery tier, which no library move carries anymore, leaving resistance stuck high forever.
var resistanceProblems: [String] = []
var downCues = 0
for seed in UInt64(1)...30 {
    let rt = gen.generate(SampleSongs.edmAnthem(seed: seed))
    var up = false
    for e in rt.events {
        for cue in e.cues {
            if cue.type == .resistanceUp {
                if up { resistanceProblems.append("seed \(seed): double up-cue at \(cue.atCount)") }
                up = true
            }
            if cue.type == .resistanceDown {
                if !up { resistanceProblems.append("seed \(seed): down-cue while down at \(cue.atCount)") }
                up = false
                downCues += 1
            }
        }
    }
}
if downCues == 0 { resistanceProblems.append("no resistanceDown cue across 30 seeds — ease-off path is dead") }
r.check("resistance eases off after demanding work (\(downCues) down-cues/30 seeds)", resistanceProblems)

// Storyboard: the ride as the rider experiences it (consecutive same-move events merged).
print("\nRide storyboard (seed 42, hard, learned — 128 BPM, counts → ≈seconds):")
var blocks: [(name: String, start: Int, counts: Int)] = []
for e in routine.events {
    if var last = blocks.last, last.name == e.move.name {
        last.counts += e.counts
        blocks[blocks.count - 1] = last
    } else {
        blocks.append((e.move.name, e.startCount, e.counts))
    }
}
let spb = 60.0 / request.bpm
for b in blocks {
    let sec = request.sections.last(where: { $0.startCount <= b.start })?.type.rawValue ?? "?"
    print(String(format: "  %4d–%-4d %5.0fs  %-11@ %@",
                 b.start, b.start + b.counts, Double(b.counts) * spb,
                 sec as NSString, b.name as NSString))
}
print("  → \(blocks.count) move blocks, \(Set(blocks.map { $0.name }).count) distinct moves")

print("")
if r.failures == 0 {
    print("ALL CHECKS PASSED ✅")
} else {
    print("FAILURES: \(r.failures) ❌")
    exit(1)
}
