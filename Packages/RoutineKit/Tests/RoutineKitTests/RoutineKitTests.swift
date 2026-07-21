import XCTest
@testable import RoutineKit

/// XCTest mirror of the RoutineKitCheck harness. Runs with `swift test` once full Xcode is
/// installed. Every rule in spec §B4 has a dedicated test, plus a fuzz sweep.
final class RoutineKitTests: XCTestCase {

    let gen = RoutineGenerator()

    private func standardRoutine() -> (Routine, RoutineRequest) {
        let request = SampleSongs.edmAnthem()
        return (gen.generate(request), request)
    }

    // MARK: §B4 grammar rules

    func testBoundaryAlignment() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkBoundaries(routine.events), [])
    }

    func testNoTwoCounts() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkNoTwoCounts(routine.events), [])
        XCTAssertFalse(routine.events.contains { $0.counts < 8 })
    }

    func testSectionAffinity() {
        let (routine, request) = standardRoutine()
        XCTAssertEqual(Grammar.checkSectionAffinity(routine.events, sections: request.sections), [])
    }

    func testResistanceFloorPrecedence() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkResistanceFloor(routine.events), [])
    }

    func testDwellMinimum() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkDwellMinimum(routine.events), [])
    }

    func testDensityCap() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkDensityCap(routine.events), [])
    }

    func testRecoveryInsertion() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkRecovery(routine), [])
        // Assert no 3 consecutive peak phrases directly, too.
        let phrases = Grammar.phraseGrid(routine)
        for i in 0..<phrases.count where i + 2 < phrases.count {
            XCTAssertFalse(phrases[i].isPeak && phrases[i + 1].isPeak && phrases[i + 2].isPeak,
                           "3 consecutive peak phrases at \(phrases[i].start)")
        }
    }

    func testLeadLegAlternation() {
        let (routine, _) = standardRoutine()
        XCTAssertEqual(Grammar.checkLeadLeg(routine.events), [])
        let switches = routine.events.flatMap { $0.cues }.filter { $0.type == .leadLegSwitch }
        XCTAssertGreaterThan(switches.count, 1, "expected multiple lead-leg switch cues")
    }

    func testSkillGating() {
        let (routine, request) = standardRoutine()
        XCTAssertEqual(Grammar.checkSkillGating(routine.events, skill: request.skillLevel), [])

        let novice = gen.generate(SampleSongs.edmAnthem(seed: 7, skill: .one))
        XCTAssertEqual(novice.events.map { $0.move.skillTier.rawValue }.max(), 1,
                       "a skill-1 rider should never be offered a skill-2+ move")
    }

    // MARK: §B4 rule 8 — determinism

    func testDeterminismSameSeedSameRoutine() {
        let request = SampleSongs.edmAnthem()
        XCTAssertEqual(gen.generate(request), gen.generate(request))
    }

    func testDifferentSeedDifferentRoutine() {
        XCTAssertNotEqual(gen.generate(SampleSongs.edmAnthem(seed: 1)),
                          gen.generate(SampleSongs.edmAnthem(seed: 2)))
    }

    func testTrackKeyFoldsIntoSeed() {
        let base = SampleSongs.edmAnthem(seed: 42)
        let other = RoutineRequest(trackKey: "sample:other", bpm: base.bpm, sections: base.sections,
                                   confidence: base.confidence, skillLevel: base.skillLevel,
                                   intensity: base.intensity, seed: base.seed)
        XCTAssertNotEqual(gen.generate(base), gen.generate(other))
    }

    // MARK: §B4 rule 9 — intensity dial & skill

    func testIntensityDialBiasesEffort() {
        func avg(_ r: Routine) -> Double {
            let total = r.events.reduce(0) { $0 + $1.counts }
            guard total > 0 else { return 0 }
            return r.events.reduce(0.0) { $0 + Double($1.move.intensityTier.rawValue * $1.counts) } / Double(total)
        }
        let easy = avg(gen.generate(SampleSongs.edmAnthem(seed: 7, intensity: .easy)))
        let hard = avg(gen.generate(SampleSongs.edmAnthem(seed: 7, intensity: .hard)))
        XCTAssertGreaterThan(hard, easy, "hard dial should raise average effort")
    }

    // MARK: §B3 — cue confidence

    func testLearnedMapEmitsCountdowns() {
        let (routine, _) = standardRoutine()   // learned by default
        XCTAssertTrue(routine.events.flatMap { $0.cues }.contains { $0.type == .countdown })
    }

    func testPriorMapSuppressesCountdowns() {
        let prior = gen.generate(SampleSongs.edmAnthem(confidence: .prior))
        XCTAssertFalse(prior.events.flatMap { $0.cues }.contains { $0.type == .countdown })
    }

    // MARK: Class-style pacing (round-2 feedback: 1–3 major moves per song, not constant churn)

    /// Merge consecutive same-move events into blocks (how a rider experiences the routine).
    private func moveBlocks(_ routine: Routine) -> [(name: String, counts: Int)] {
        var blocks: [(String, Int)] = []
        for e in routine.events {
            if let last = blocks.last, last.0 == e.move.name {
                blocks[blocks.count - 1].1 += e.counts
            } else {
                blocks.append((e.move.name, e.counts))
            }
        }
        return blocks
    }

    func testClassPacingFewDistinctMoves() {
        let (routine, _) = standardRoutine()
        let names = Set(routine.events.map { $0.move.name })
        XCTAssertLessThanOrEqual(names.count, 6,
            "a song should carry a handful of moves, got \(names.sorted())")
    }

    func testClassPacingLongDwell() {
        let (routine, _) = standardRoutine()
        let blocks = moveBlocks(routine)
        let avg = Double(blocks.reduce(0) { $0 + $1.counts }) / Double(blocks.count)
        XCTAssertGreaterThanOrEqual(avg, 24,
            "average move block should be most of a phrase, got \(avg) counts over \(blocks.count) blocks")
        // And transitions should be on the order of the section count, not the phrase count.
        XCTAssertLessThanOrEqual(blocks.count, 24, "36-phrase song had \(blocks.count) move blocks")
    }

    func testChorusSignatureIsConsistent() {
        let (routine, request) = standardRoutine()
        // The non-build, non-recovery move ridden inside chorus sections must be the same every time.
        let chorusSections = request.sections.filter { $0.type == .chorus }
        var signatures = Set<String>()
        for section in chorusSections {
            for e in routine.events where e.startCount >= section.startCount && e.endCount <= section.endCount {
                let name = e.move.name
                // Exclude the base ride and the build/step-down move — the signature is what's left.
                if name != "Seated Flat" && name != "Standing Run" { signatures.insert(name) }
            }
        }
        XCTAssertEqual(signatures.count, 1, "chorus signature should recur, got \(signatures.sorted())")
    }

    // MARK: Fuzz — grammar holds across the settings space

    func testGrammarHoldsUnderFuzz() {
        for seed in UInt64(0)..<60 {
            for skill in SkillTier.allCases {
                for dial in [IntensityDial.easy, .medium, .hard] {
                    for conf in MapConfidence.allCases {
                        let req = SampleSongs.edmAnthem(seed: seed, skill: skill, intensity: dial, confidence: conf)
                        let problems = Grammar.validate(gen.generate(req), request: req)
                        XCTAssertEqual(problems, [],
                                       "seed \(seed) skill \(skill.rawValue) dial \(dial.value) \(conf.rawValue)")
                    }
                }
            }
        }
    }
}
