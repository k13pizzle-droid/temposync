import XCTest
import SwiftData
@testable import RhythmCoachCore
import RoutineKit
import BeatKit

final class RhythmCoachCoreTests: XCTestCase {

    // MARK: BeatClock

    func testBeatClockPositionMath() {
        let clock = BeatClock(bpm: 120, beatOffset: 0)   // 0.5 s/beat
        let p0 = clock.position(at: 0)
        XCTAssertEqual(p0.beatIndex, 0)
        let p = clock.position(at: 16.25)                // beat 32.5
        XCTAssertEqual(p.beatIndex, 32)
        XCTAssertEqual(p.phraseIndex, 1)
        XCTAssertEqual(p.countInPhrase, 0)
        XCTAssertEqual(p.phase, 0.5, accuracy: 0.001)
    }

    func testBeatClockOffset() {
        let clock = BeatClock(bpm: 120, beatOffset: 1.0)
        XCTAssertEqual(clock.position(at: 0.5).beatIndex, 0)   // before offset clamps to 0
        XCTAssertEqual(clock.position(at: 1.0).beatIndex, 0)
        XCTAssertEqual(clock.position(at: 2.0).beatIndex, 2)
    }

    // MARK: RoutinePlayer

    private func standardRoutine() -> (Routine, RoutineRequest) {
        let req = SampleSongs.edmAnthem()
        return (RoutineGenerator().generate(req), req)
    }

    func testRoutinePlayerCurrentAndNext() {
        let (routine, _) = standardRoutine()
        let player = RoutinePlayer(routine: routine)
        let first = routine.events[0]
        let s = player.state(atCount: first.startCount)
        XCTAssertEqual(s.currentEvent, first)
        XCTAssertNotNil(s.nextEvent)
        XCTAssertEqual(s.countsUntilNext, s.nextEvent!.startCount - first.startCount)
    }

    func testRoutinePlayerResistanceTracking() {
        let (routine, _) = standardRoutine()
        let player = RoutinePlayer(routine: routine)
        // Find a move that needs resistance and confirm the player reports resistance up during it.
        if let resEvent = routine.events.first(where: { $0.move.needsResistance }) {
            let s = player.state(atCount: resEvent.startCount)
            XCTAssertTrue(s.resistanceUp)
        }
    }

    // MARK: LiveCoach — cue confidence

    func testLiveCoachLearnedShowsCountdown() {
        let req = SampleSongs.edmAnthem(confidence: .learned)
        let routine = RoutineGenerator().generate(req)
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: req.bpm, beatOffset: 0),
                              sections: req.sections, confidence: .learned)
        // Scan the whole track for at least one countdown frame.
        let period = 60.0 / req.bpm
        var sawCountdown = false
        var t = 0.0
        while t < routine.endCountSeconds(bpm: req.bpm) {
            if coach.frame(at: t).countdownText != nil { sawCountdown = true; break }
            t += period / 2
        }
        XCTAssertTrue(sawCountdown, "learned map should surface a countdown")
    }

    func testLiveCoachPriorHidesCountdown() {
        let req = SampleSongs.edmAnthem(confidence: .prior)
        let routine = RoutineGenerator().generate(req)
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: req.bpm, beatOffset: 0),
                              sections: req.sections, confidence: .prior)
        let period = 60.0 / req.bpm
        var t = 0.0
        while t < routine.endCountSeconds(bpm: req.bpm) {
            XCTAssertNil(coach.frame(at: t).countdownText, "prior map must not show hard countdowns")
            t += period
        }
    }

    // MARK: StructurePrior → generator integration

    func testStructurePriorProducesValidRoutine() {
        let prior = StructurePrior()
        for genre in Genre.allCases {
            let sections = prior.sections(bpm: 128, durationSeconds: 210, genre: genre)
            XCTAssertFalse(sections.isEmpty)
            // Contiguous, phrase-aligned, ordered.
            var expected = 0
            for s in sections {
                XCTAssertEqual(s.startCount, expected, "\(genre) not contiguous")
                XCTAssertEqual(s.counts % 32, 0, "\(genre) not phrase-aligned")
                expected = s.endCount
            }
            let req = RoutineRequest(trackKey: "prior-\(genre.rawValue)", bpm: 128, sections: sections,
                                     confidence: .prior, skillLevel: .three, intensity: .medium, seed: 5)
            XCTAssertEqual(Grammar.validate(RoutineGenerator().generate(req), request: req), [],
                           "generator grammar must hold on \(genre) prior sections")
        }
    }

    // MARK: SectionCapture → generator integration (the learning loop end to end)

    func testCaptureProducesValidRoutine() {
        let fixture = SyntheticFixtures.clickTrack(name: "cap", bpm: 128, durationSeconds: 60,
                                                   energyJumpAt: 30)
        let analysis = BeatAnalyzer().analyze(fixture.buffer)
        let map = SectionCapture().capture(trackKey: "cap", buffer: fixture.buffer, analysis: analysis)
        XCTAssertFalse(map.sections.isEmpty)
        var expected = 0
        for s in map.sections {
            XCTAssertEqual(s.startCount, expected, "captured sections not contiguous")
            XCTAssertEqual(s.counts % 32, 0)
            expected = s.endCount
        }
        let req = RoutineRequest(trackKey: map.trackKey, bpm: map.bpm, sections: map.sections,
                                 confidence: .learned, skillLevel: .two, intensity: .hard, seed: 9)
        XCTAssertEqual(Grammar.validate(RoutineGenerator().generate(req), request: req), [])
    }

    // MARK: In-house asset tempo analysis (the API-independence rung)

    func testAssetTempoAnalyzerMatchesTruth() throws {
        let fixture = SyntheticFixtures.clickTrack(name: "asset", bpm: 126, durationSeconds: 40)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("asset-tempo-test.wav")
        try WAVFile.write(fixture.buffer, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try AssetTempoAnalyzer.analyzeSync(url: url, secondsLimit: 40)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bpm ?? 0, 126, accuracy: 2, "own-file analysis should nail the tempo")
    }

    func testAssetStructureAnalysisYieldsLearnedMap() throws {
        let fixture = SyntheticFixtures.clickTrack(name: "structure", bpm: 128, durationSeconds: 60,
                                                   energyJumpAt: 30)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("asset-structure.wav")
        try WAVFile.write(fixture.buffer, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try AssetTempoAnalyzer.structureSync(url: url)
        XCTAssertNotNil(result)
        let map = SectionCapture().capture(trackKey: "structure", streamed: result!)
        XCTAssertEqual(map.bpm, 128, accuracy: 2)
        XCTAssertGreaterThan(map.sections.count, 1, "file analysis should find the section change")
    }

    // MARK: Calibration (streamed) capture → generator

    func testStreamedCaptureProducesValidRoutine() {
        let fixture = SyntheticFixtures.clickTrack(name: "cal", bpm: 128, durationSeconds: 60,
                                                   energyJumpAt: 30)
        let streamer = StreamingAnalyzer(sampleRate: fixture.buffer.sampleRate)
        var i = 0
        while i < fixture.buffer.samples.count {
            let n = min(2048, fixture.buffer.samples.count - i)
            streamer.feed(Array(fixture.buffer.samples[i..<i+n]))
            i += n
        }
        let map = SectionCapture().capture(trackKey: "cal", streamed: streamer.finalize())

        XCTAssertFalse(map.sections.isEmpty)
        var expected = 0
        for s in map.sections {
            XCTAssertEqual(s.startCount, expected, "streamed sections not contiguous")
            XCTAssertEqual(s.counts % 32, 0)
            expected = s.endCount
        }
        let req = RoutineRequest(trackKey: map.trackKey, bpm: map.bpm, sections: map.sections,
                                 confidence: .learned, skillLevel: .two, intensity: .hard, seed: 9)
        XCTAssertEqual(Grammar.validate(RoutineGenerator().generate(req), request: req), [])
    }

    // (RunSync engine + tests shelved 2026-07-21 → Shelved/RunSync/)

    // MARK: TrackTempoResolver

    func testResolverMatchesFixtureTracksLoosely() {
        let resolver = TrackTempoResolver()
        // Exact-ish
        XCTAssertEqual(resolver.lookup(title: "Levels", artist: "Avicii")?.referenceBPM, 126)
        // Case + decoration differences, artist as a subset
        XCTAssertEqual(resolver.lookup(title: "COOK (feat. J Balvin)", artist: "SOFI TUKKER")?.referenceBPM, 108)
        XCTAssertEqual(resolver.lookup(title: "Bad Angel (with LISA)", artist: "Anyma")?.referenceBPM, 128)
        // Miss stays a miss
        XCTAssertNil(resolver.lookup(title: "Some Unknown Song", artist: "Nobody"))
    }

    func testResolverSuggestedRPMHalvesBPM() {
        // 128 BPM song → ~64 RPM base cadence (downstroke on the beat, alternating legs).
        let req = SampleSongs.edmAnthem()
        let routine = RoutineGenerator().generate(req)
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: 128, beatOffset: 0),
                              sections: req.sections, confidence: .learned)
        XCTAssertEqual(coach.frame(at: 0).suggestedRPM, 64)
    }

    func testSprintCadenceRidesEveryBeat() {
        // Sprints are pedalled on the beat, not every other beat — the cadence readout has to
        // agree with the pictogram (which has always spun the legs twice as fast in a sprint)
        // and with real sprint cadence (90–110 RPM, not a 64 RPM climb).
        let req = SampleSongs.edmAnthem()
        let routine = RoutineGenerator().generate(req)
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: 128, beatOffset: 0),
                              sections: req.sections, confidence: .learned)
        let secondsPerCount = 60.0 / 128.0
        guard let sprint = routine.events.first(where: { $0.move.name.contains("Sprint") }) else {
            return XCTFail("sample song generated no sprint to check")
        }
        let frame = coach.frame(at: Double(sprint.startCount) * secondsPerCount + 0.05)
        XCTAssertTrue(frame.ridesEveryBeat, "sprint frame should ride every beat")
        XCTAssertEqual(frame.suggestedRPM, 128, "sprint cadence must double the base RPM")
    }

    func testHeavyGrindHalvesTheCadence() {
        // A half-time grind move reports ~BPM/4 — the heavy, slow feel — vs BPM/2 base.
        let sections = [Section(type: .chorus, startCount: 0, counts: 64)]
        let move = MoveLibrary.heavyClimb
        let routine = Routine(trackKey: "t", seed: 1, startCount: 0, endCount: 64,
                              events: [MoveEvent(startCount: 0, move: move, counts: 64, cues: [])])
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: 128, beatOffset: 0),
                              sections: sections, confidence: .prior)
        let frame = coach.frame(at: 0.05)
        XCTAssertEqual(frame.currentCadence, .grind)
        XCTAssertEqual(frame.suggestedRPM, 32, "heavy grind at 128 BPM should read ~32 RPM")
    }

    // MARK: ClassPlanner

    private func fixtureClassSongs() -> [ClassSong] {
        // Loosely modeled on Kevin's playlist: a spread of tempos + durations.
        [
            ClassSong(trackKey: "a", title: "Warm", artist: "x", durationSeconds: 200, bpm: 94),
            ClassSong(trackKey: "b", title: "Slow Heavy", artist: "x", durationSeconds: 240, bpm: 104),
            ClassSong(trackKey: "c", title: "Anthem", artist: "x", durationSeconds: 220, bpm: 128),
            ClassSong(trackKey: "d", title: "Groove", artist: "x", durationSeconds: 210, bpm: 122),
            ClassSong(trackKey: "e", title: "Jumper", artist: "x", durationSeconds: 200, bpm: 126),
            ClassSong(trackKey: "f", title: "Cool", artist: "x", durationSeconds: 230, bpm: 88),
            ClassSong(trackKey: "g", title: "Mid", artist: "x", durationSeconds: 215, bpm: 118),
            ClassSong(trackKey: "h", title: "Unknown", artist: "x", durationSeconds: 205, bpm: nil),
            ClassSong(trackKey: "i", title: "Fast", artist: "x", durationSeconds: 225, bpm: 131),
            ClassSong(trackKey: "j", title: "Flow", artist: "x", durationSeconds: 210, bpm: 108),
        ]
    }

    func testArcAnchors() {
        let planner = ClassPlanner()
        for count in 4...16 {
            let arc = planner.arc(count: count)
            XCTAssertEqual(arc.count, count)
            XCTAssertEqual(arc.first, .warmup)
            XCTAssertEqual(arc.last, .cooldown)
            XCTAssertEqual(arc[1], .jumps, "jumps song comes early (count \(count))")
            if count >= 6 {
                XCTAssertEqual(arc[count - 3], .arms, "arms song sits late (count \(count))")
                XCTAssertEqual(arc[count - 2], .sprint, "biggest sprint is second-from-last (count \(count))")
            }
        }
    }

    func testPlanReorderAssignsByBPMFit() {
        let plan = ClassPlanner().plan(songs: fixtureClassSongs(), format: .thirty, reorder: true)
        XCTAssertTrue(plan.reordered)
        XCTAssertEqual(plan.songs.first?.role, .warmup)
        XCTAssertEqual(plan.songs.last?.role, .cooldown)
        // The 94-BPM song should win warm-up; the 88-BPM song cooldown; a slow song takes the climb.
        XCTAssertEqual(plan.songs.first?.song.trackKey, "a")
        XCTAssertEqual(plan.songs.last?.song.trackKey, "f")
        if let climb = plan.songs.first(where: { $0.role == .climb }) {
            XCTAssertLessThan(climb.song.bpm ?? 999, 115, "climb should get a slow song")
        }
        // No duplicates.
        XCTAssertEqual(Set(plan.songs.map { $0.song.trackKey }).count, plan.songs.count)
        // Duration roughly fits the format (±30%).
        XCTAssertEqual(plan.totalSeconds, Double(plan.format.minutes * 60), accuracy: Double(plan.format.minutes) * 60 * 0.3)
    }

    func testPlanRespectOrderKeepsPlaylistOrder() {
        let songs = fixtureClassSongs()
        let plan = ClassPlanner().plan(songs: songs, format: .thirty, reorder: false)
        XCTAssertFalse(plan.reordered)
        let expectedKeys = songs.prefix(plan.songs.count).map { $0.trackKey }
        XCTAssertEqual(plan.songs.map { $0.song.trackKey }, Array(expectedKeys))
        XCTAssertEqual(plan.songs.first?.role, .warmup)
        XCTAssertEqual(plan.songs.last?.role, .cooldown)
    }

    func testClassStylesReshapeArc() {
        let planner = ClassPlanner()
        let intervals = planner.arc(count: 10, style: .intervals)
        XCTAssertGreaterThanOrEqual(intervals.filter { $0 == .sprint }.count, 3,
                                    "intervals style should be sprint heavy")
        let climbs = planner.arc(count: 10, style: .climbs)
        XCTAssertEqual(climbs[climbs.count - 2], .climb, "climb style peaks on a climb")
        let recovery = planner.arc(count: 10, style: .recovery)
        XCTAssertFalse(recovery.contains(.sprint), "recovery style has no sprints")
        XCTAssertFalse(recovery.contains(.jumps), "recovery style skips the jumps opener")
    }

    func testEnergyAwareSprintAssignment() {
        // Two candidates tied on BPM for the sprint slot; measured energy should break the tie.
        let songs = [
            ClassSong(trackKey: "calm", title: "Calm", artist: "x", durationSeconds: 210, bpm: 127, energy: 0.3),
            ClassSong(trackKey: "anthem", title: "Anthem", artist: "x", durationSeconds: 210, bpm: 127, energy: 0.95),
            ClassSong(trackKey: "warm", title: "Warm", artist: "x", durationSeconds: 210, bpm: 95, energy: 0.2),
            ClassSong(trackKey: "cool", title: "Cool", artist: "x", durationSeconds: 210, bpm: 88, energy: 0.2),
        ]
        let plan = ClassPlanner().plan(songs: songs, format: .fifteen, reorder: true)
        let sprint = plan.songs.first { $0.role == .sprint }
        XCTAssertEqual(sprint?.song.trackKey, "anthem", "the high-energy song should take the sprint")
    }

    // MARK: Role steering in the generator

    func testRoleSteering() {
        let gen = RoutineGenerator()
        // Jumps song → jumps signature at choruses.
        let jumpsReq = RoutineRequest(trackKey: "t", bpm: 126, sections: SampleSongs.edmAnthem().sections,
                                      confidence: .prior, skillLevel: .two, intensity: .medium,
                                      seed: 4, classRole: .jumps)
        let jumpsRoutine = gen.generate(jumpsReq)
        XCTAssertTrue(jumpsRoutine.events.contains { $0.move.name == "Jumps" },
                      "jumps role should surface jumps")
        XCTAssertEqual(Grammar.validate(jumpsRoutine, request: jumpsReq), [])

        // Warm-up song → nothing above moderate.
        let warmReq = RoutineRequest(trackKey: "t", bpm: 126, sections: SampleSongs.edmAnthem().sections,
                                     confidence: .prior, skillLevel: .two, intensity: .hard,
                                     seed: 4, classRole: .warmup)
        let warmRoutine = gen.generate(warmReq)
        XCTAssertTrue(warmRoutine.events.allSatisfy { $0.move.intensityTier <= .moderate },
                      "warm-up must stay easy even on the hard dial")
        XCTAssertEqual(Grammar.validate(warmRoutine, request: warmReq), [])

        // Arms song → upper-body accents appear beyond bridge/breakdown, still density-legal.
        let armsReq = RoutineRequest(trackKey: "t", bpm: 126, sections: SampleSongs.edmAnthem().sections,
                                     confidence: .prior, skillLevel: .two, intensity: .medium,
                                     seed: 4, classRole: .arms)
        let armsRoutine = gen.generate(armsReq)
        let upperCount = armsRoutine.events.filter { $0.move.upperBody }.count
        XCTAssertGreaterThanOrEqual(upperCount, 3, "arms song should carry several upper-body blocks")
        XCTAssertEqual(Grammar.validate(armsRoutine, request: armsReq), [])
    }

    // MARK: GetSongBPM parsing + waterfall

    func testGetSongBPMParsing() {
        let success = """
        {"search":[
          {"title":"Levels","tempo":"126","artist":{"name":"Avicii"}},
          {"title":"Levels - Remix","tempo":"140","artist":{"name":"Someone Else"}}
        ]}
        """.data(using: .utf8)!
        XCTAssertEqual(GetSongBPMService.parseBPM(from: success, title: "Levels", artist: "Avicii"), 126)
        // STRICT: no artist match → nil (their search ranks obscure covers first; a wrong tempo is
        // worse than an honest miss).
        XCTAssertNil(GetSongBPMService.parseBPM(from: success, title: "Levels", artist: "Nobody"))
        XCTAssertNil(GetSongBPMService.parseBPM(from: success, title: "Other", artist: "Avicii"))

        let error = #"{"search":{"error":"no result"}}"#.data(using: .utf8)!
        XCTAssertNil(GetSongBPMService.parseBPM(from: error, title: "Levels", artist: "Avicii"))
    }

    func testDeezerParsing() {
        let search = """
        {"data":[
          {"id": 111, "title": "Levels", "artist": {"name": "Nonpoint"}},
          {"id": 14383880, "title": "Levels (Radio Edit)", "artist": {"name": "Avicii"}}
        ]}
        """.data(using: .utf8)!
        // Skips the wrong-artist hit, takes the Avicii one.
        XCTAssertEqual(DeezerBPMService.parseFirstMatchingTrackID(from: search, title: "Levels", artist: "Avicii"),
                       14383880)
        XCTAssertNil(DeezerBPMService.parseFirstMatchingTrackID(from: search, title: "Levels", artist: "Tiesto"))

        let detail = #"{"id": 14383880, "bpm": 126.0}"#.data(using: .utf8)!
        XCTAssertEqual(DeezerBPMService.parseBPM(fromTrackDetail: detail), 126)
        let unanalyzed = #"{"id": 1457224502, "bpm": 0}"#.data(using: .utf8)!
        XCTAssertNil(DeezerBPMService.parseBPM(fromTrackDetail: unanalyzed), "bpm 0 = not analyzed = miss")
    }

    actor MockBPMService: BPMLookupService {
        private(set) var calls = 0
        func lookupBPM(title: String, artist: String) async throws -> Double? {
            calls += 1
            return 123
        }
        func callCount() async -> Int { calls }
    }

    @MainActor
    func testWaterfallSeedThenAPIThenCache() async throws {
        let container = try SectionMapStore.inMemoryContainer()
        let service = MockBPMService()
        let waterfall = BPMWaterfall(service: service, context: ModelContext(container))

        // Seed rung: fixture track resolves without touching the API.
        let seeded = await waterfall.resolve(title: "Levels", artist: "Avicii")
        XCTAssertEqual(seeded, ResolvedBPM(bpm: 126, source: .seed))
        let callsAfterSeed = await service.callCount()
        XCTAssertEqual(callsAfterSeed, 0)

        // Unknown track: API rung fires once, result is persisted…
        let first = await waterfall.resolve(title: "Mystery Song", artist: "Unknown")
        XCTAssertEqual(first, ResolvedBPM(bpm: 123, source: .api))
        // …so the second resolve is a cache hit, not a second network call.
        let second = await waterfall.resolve(title: "Mystery Song", artist: "Unknown")
        XCTAssertEqual(second, ResolvedBPM(bpm: 123, source: .cache))
        let totalCalls = await service.callCount()
        XCTAssertEqual(totalCalls, 1)
    }

    actor MissingBPMService: BPMLookupService {
        private(set) var calls = 0
        func lookupBPM(title: String, artist: String) async throws -> Double? {
            calls += 1
            return nil
        }
        func callCount() async -> Int { calls }
    }

    @MainActor
    func testWaterfallCachesMisses() async throws {
        // A song no service knows must not re-fire the network on every ride — the miss itself is
        // cached (with a TTL) and the local rungs stay honest (no fake hit from the sentinel).
        let container = try SectionMapStore.inMemoryContainer()
        let service = MissingBPMService()
        let waterfall = BPMWaterfall(service: service, context: ModelContext(container))

        let first = await waterfall.resolve(title: "Ghost Track", artist: "Nobody")
        XCTAssertNil(first)
        let second = await waterfall.resolve(title: "Ghost Track", artist: "Nobody")
        XCTAssertNil(second)
        let calls = await service.callCount()
        XCTAssertEqual(calls, 1, "second resolve must hit the miss sentinel, not the network")
        XCTAssertNil(waterfall.resolveLocally(title: "Ghost Track", artist: "Nobody"),
                     "a miss sentinel is not a BPM hit")

        // A later real result overwrites the sentinel.
        waterfall.store(bpm: 140, title: "Ghost Track", artist: "Nobody", source: "on-device")
        XCTAssertEqual(waterfall.resolveLocally(title: "Ghost Track", artist: "Nobody"),
                       ResolvedBPM(bpm: 140, source: .cache))
    }

    // MARK: Mode S clock estimator

    func testModeSTapAlignsBeatToTapTime() {
        var est = ModeSClockEstimator(bpm: 120, firstBeatWallTime: 0)   // period 0.5
        est.tap(wallTime: 10.3)
        // After tapping, a beat must land exactly on 10.3.
        XCTAssertEqual(est.phaseError(at: 10.3), 0, accuracy: 1e-9)
    }

    func testModeSPhaseConvergence() {
        // True beats sit 0.12 s ahead of the estimator's initial phase; repeated ingests should pull
        // the predicted grid onto them without ever snapping.
        var est = ModeSClockEstimator(bpm: 128, firstBeatWallTime: 0)
        let p = est.periodSeconds
        let trueOffset = 0.12
        for k in 1...12 {
            let detected = trueOffset + Double(k) * p     // a true beat k periods in
            est.ingest(bpm: 128, detectedBeatWallTime: detected)
        }
        // Predicted grid should now align to the true beats within a couple ms.
        XCTAssertLessThan(est.phaseError(at: trueOffset + 40 * p), 0.005)
    }

    func testModeSTempoSmoothing() {
        var est = ModeSClockEstimator(bpm: 120, firstBeatWallTime: 0)
        est.bpmAlpha = 0.5
        est.ingest(bpm: 128, detectedBeatWallTime: 0)
        XCTAssertEqual(est.bpm, 124, accuracy: 0.001)   // halfway to 128
    }

    // MARK: SwiftData persistence

    @MainActor
    func testSectionMapUpsertAndHigherQualityReplace() throws {
        let container = try SectionMapStore.inMemoryContainer()
        let ctx = ModelContext(container)

        let low = CapturedMap(trackKey: "k", bpm: 128, beatGridOffset: 0.1,
                              sections: [Section(type: .verse, startCount: 0, counts: 64)], captureQuality: 0.4)
        try SectionMapStore.upsert(low, in: ctx)
        XCTAssertEqual(try SectionMapStore.map(for: "k", in: ctx)?.captureQuality, 0.4)

        // Lower-quality capture must NOT replace.
        let worse = CapturedMap(trackKey: "k", bpm: 128, beatGridOffset: 0.2,
                                sections: [], captureQuality: 0.2)
        try SectionMapStore.upsert(worse, in: ctx)
        XCTAssertEqual(try SectionMapStore.map(for: "k", in: ctx)?.captureQuality, 0.4)

        // Higher-quality capture replaces.
        let better = CapturedMap(trackKey: "k", bpm: 128, beatGridOffset: 0.15,
                                 sections: [Section(type: .chorus, startCount: 0, counts: 32)], captureQuality: 0.9)
        try SectionMapStore.upsert(better, in: ctx)
        XCTAssertEqual(try SectionMapStore.map(for: "k", in: ctx)?.captureQuality, 0.9)
    }

    // MARK: LiveCoach — section label clamps past the end

    func testSectionLabelClampsToLastSectionPastTheEnd() {
        // The old fallback latched the FIRST section for counts beyond every section's end, so an
        // outro overrun displayed "INTRO" on the live header. It must clamp to the last section.
        let req = SampleSongs.edmAnthem()
        let routine = RoutineGenerator().generate(req)
        let coach = LiveCoach(routine: routine, clock: BeatClock(bpm: req.bpm, beatOffset: 0),
                              sections: req.sections, confidence: .learned)
        let lastSection = req.sections.max(by: { $0.startCount < $1.startCount })!
        let maxEnd = req.sections.map(\.endCount).max()!
        let wayPast = Double(maxEnd + 64) * 60.0 / req.bpm
        XCTAssertEqual(coach.frame(at: wayPast).sectionType, lastSection.type)
        // Still exact inside a section: the first section's own range reports itself.
        let first = req.sections.min(by: { $0.startCount < $1.startCount })!
        let inFirst = (Double(first.startCount) + 1) * 60.0 / req.bpm
        XCTAssertEqual(coach.frame(at: inFirst).sectionType, first.type)
    }
}

// Helper: routine coverage in seconds for scanning tests.
extension Routine {
    func endCountSeconds(bpm: Double) -> Double { Double(endCount) * 60.0 / bpm }
}
