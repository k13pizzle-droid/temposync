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
        // Transitions stay on the order of the section count, not the phrase count. A choreography
        // song adds some — alternating a phrase of the set with a phrase back on the beat — but the
        // ride is still deliberate blocks (well under one transition per phrase), not churn.
        XCTAssertLessThanOrEqual(blocks.count, 32, "36-phrase song had \(blocks.count) move blocks")
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

    // MARK: Resistance eases off (round-9 regression)

    func testResistanceEasesOffAfterDemandingWork() {
        // The down-cue used to key on the `.recovery` tier, which no move has carried since
        // Recovery Spin merged into Seated Flat — resistance went up and never came down, and the
        // fuzz sweep can't see it (the floor rule never fires on a stuck-high state). Ease-off
        // must fire when easy seated work follows resistance-requiring blocks.
        var sawDown = false
        for seed in UInt64(1)...30 {
            let request = SampleSongs.edmAnthem(seed: seed)
            let routine = gen.generate(request)
            var up = false
            for event in routine.events {
                for cue in event.cues {
                    if cue.type == .resistanceUp {
                        XCTAssertFalse(up, "seed \(seed): up-cue while already up at \(cue.atCount)")
                        up = true
                    }
                    if cue.type == .resistanceDown {
                        XCTAssertTrue(up, "seed \(seed): down-cue while already down at \(cue.atCount)")
                        up = false
                        sawDown = true
                    }
                }
            }
            // The floor rule must still hold with the down-cue back in play.
            XCTAssertEqual(Grammar.checkResistanceFloor(routine.events), [], "seed \(seed)")
        }
        XCTAssertTrue(sawDown, "no resistanceDown cue across 30 seeds — the ease-off path is dead again")
    }

    // MARK: Choreography balance (2026-07-23 — Kevin: "mostly a stand/sprint class")

    /// Share of a song's counts spent on upper-body work.
    private func upperBodyShare(_ routine: Routine) -> Double {
        let total = routine.events.reduce(0) { $0 + $1.counts }
        guard total > 0 else { return 0 }
        let upper = routine.events.filter { $0.move.upperBody }.reduce(0) { $0 + $1.counts }
        return Double(upper) / Double(total)
    }

    func testArmsTrackIsActuallyAnArmsTrack() {
        // An arms song must FEATURE arms, not garnish with one 7-second stab.
        for seed in UInt64(1)...20 {
            let request = SampleSongs.edmAnthem(seed: seed, skill: .three)
            let armsRequest = RoutineRequest(
                trackKey: "arms-\(seed)", bpm: request.bpm, sections: request.sections,
                confidence: .learned, skillLevel: .three, intensity: .medium,
                seed: seed, classRole: .arms)
            let share = upperBodyShare(gen.generate(armsRequest))
            XCTAssertGreaterThanOrEqual(share, 0.20,
                "arms track (seed \(seed)) is only \(Int(share * 100))% upper-body work")
        }
    }

    func testChoreographyCanBeASongsMainEvent() {
        // Upper-body work used to be hard-capped at ONE 16-count accent (~7 s) per song, because
        // it could never be a section primary. Across a spread of songs, choreography must now
        // carry real weight on a meaningful number of them — a "moves" song, not a garnish.
        var choreoLed = 0
        for seed in UInt64(1)...30 {
            let base = SampleSongs.edmAnthem(seed: seed, skill: .three)
            let request = RoutineRequest(
                trackKey: "song-\(seed)", bpm: base.bpm, sections: base.sections,
                confidence: .learned, skillLevel: .three, intensity: .medium,
                seed: seed, classRole: .run)
            if upperBodyShare(gen.generate(request)) >= 0.15 { choreoLed += 1 }
        }
        XCTAssertGreaterThanOrEqual(choreoLed, 3, "choreography rarely carried a song (\(choreoLed)/30)")
    }

    func testUpperBodyRunsStayInsideTheSafetyCap() {
        // The flip side: sustained is allowed, endless is not. Legs must get the ride back.
        for seed in UInt64(1)...30 {
            for role in [SongRole.arms, .run, .recovery] {
                let base = SampleSongs.edmAnthem(seed: seed, skill: .three)
                let request = RoutineRequest(
                    trackKey: "cap-\(seed)-\(role.rawValue)", bpm: base.bpm, sections: base.sections,
                    confidence: .learned, skillLevel: .three, intensity: .medium,
                    seed: seed, classRole: role)
                XCTAssertEqual(Grammar.checkDensityCap(gen.generate(request).events), [],
                               "seed \(seed) role \(role.rawValue)")
            }
        }
    }

    func testSongRolesKeepTheirSignature() {
        // Choreography must not hijack a song whose whole job is something else.
        for seed in UInt64(1)...20 {
            let base = SampleSongs.edmAnthem(seed: seed, skill: .three)
            func routine(_ role: SongRole) -> Routine {
                gen.generate(RoutineRequest(
                    trackKey: "role-\(seed)-\(role.rawValue)", bpm: base.bpm, sections: base.sections,
                    confidence: .learned, skillLevel: .three, intensity: .medium,
                    seed: seed, classRole: role))
            }
            // Bookends stay simple: no upper-body choreography at all.
            XCTAssertEqual(upperBodyShare(routine(.warmup)), 0, "warm-up (seed \(seed)) has choreography")
            XCTAssertEqual(upperBodyShare(routine(.cooldown)), 0, "cooldown (seed \(seed)) has choreography")
            // Effort songs keep the legs as the story.
            XCTAssertLessThan(upperBodyShare(routine(.sprint)), 0.15, "sprint song (seed \(seed)) over-choreographed")
            XCTAssertLessThan(upperBodyShare(routine(.jumps)), 0.15, "jumps song (seed \(seed)) over-choreographed")
        }
    }

    // MARK: Cadence & new moves (2026-07-23)

    func testCadenceIsAssignedCorrectly() {
        // Sprints ride the beat, heavy grinds cut it in half, everything else is base cadence.
        for move in MoveLibrary.v1 {
            switch move.name {
            case "Seated Sprint", "Standing Sprint":
                XCTAssertEqual(move.cadence, .sprint, move.name)
            case "Heavy Climb", "Standing Heavy Climb":
                XCTAssertEqual(move.cadence, .grind, move.name)
            default:
                XCTAssertEqual(move.cadence, .standard, move.name)
            }
        }
    }

    func testHeavyAndComboMovesCanAppear() {
        // The new vocabulary must actually reach the rider: heavy grinds on climb songs, the
        // combo on advanced choreography songs.
        var sawHeavy = false, sawCombo = false
        for seed in UInt64(1)...40 {
            let base = SampleSongs.edmAnthem(seed: seed, skill: .three)
            let climb = gen.generate(RoutineRequest(
                trackKey: "climb-\(seed)", bpm: base.bpm, sections: base.sections,
                confidence: .learned, skillLevel: .three, intensity: .medium,
                seed: seed, classRole: .climb))
            if climb.events.contains(where: { $0.move.cadence == .grind }) { sawHeavy = true }
            let choreo = gen.generate(RoutineRequest(
                trackKey: "choreo-\(seed)", bpm: base.bpm, sections: base.sections,
                confidence: .learned, skillLevel: .three, intensity: .medium,
                seed: seed, classRole: .run))
            if choreo.events.contains(where: { $0.move.name == "64-Count Combo" }) { sawCombo = true }
        }
        XCTAssertTrue(sawHeavy, "no half-time heavy grind ever appeared on a climb song")
        XCTAssertTrue(sawCombo, "the 64-count combo never appeared on a choreography song")
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
