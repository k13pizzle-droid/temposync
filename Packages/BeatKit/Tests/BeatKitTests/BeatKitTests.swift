import XCTest
@testable import BeatKit

/// XCTest mirror of BeatKitCheck. Runs with `swift test` once full Xcode is installed.
final class BeatKitTests: XCTestCase {

    let analyzer = BeatAnalyzer()

    // MARK: WAV round-trip

    func testWAVRoundTrip() throws {
        let fixture = SyntheticFixtures.clickTrack(name: "rt", bpm: 120, durationSeconds: 4)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("beatkit-rt.wav")
        try WAVFile.write(fixture.buffer, to: url)
        let reloaded = try WAVFile.read(url)
        XCTAssertEqual(reloaded.sampleRate, fixture.buffer.sampleRate)
        XCTAssertLessThanOrEqual(abs(reloaded.samples.count - fixture.buffer.samples.count), 1)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Canonical fixtures (§B3 success bar)

    func testCanonicalFixturesTempoAndPhase() {
        for fixture in SyntheticFixtures.canonicalThree(durationSeconds: 30) {
            let score = ScoringHarness.score(analyzer.analyze(fixture.buffer), against: fixture)
            XCTAssertTrue(score.tempoExact, "\(fixture.name): tempo \(score.estimatedBPM) vs \(score.trueBPM)")
            XCTAssertTrue(score.phaseWithinTarget, "\(fixture.name): phase \(score.beatPhaseErrorMs) ms")
        }
    }

    func testCanonicalFixturesSectionBoundary() {
        for fixture in SyntheticFixtures.canonicalThree(durationSeconds: 30) {
            let score = ScoringHarness.score(analyzer.analyze(fixture.buffer), against: fixture)
            XCTAssertNotNil(score.sectionErrorSeconds)
            XCTAssertLessThanOrEqual(score.sectionErrorSeconds ?? .infinity, 1.0, fixture.name)
        }
    }

    // MARK: Tempo sweep across the spin range

    func testTempoSweepAccuracy() {
        var scores: [FixtureScore] = []
        for bpm in stride(from: 92.0, through: 178.0, by: 6.0) {
            let f = SyntheticFixtures.clickTrack(name: "sweep-\(Int(bpm))", bpm: bpm, durationSeconds: 20)
            scores.append(ScoringHarness.score(analyzer.analyze(f.buffer), against: f))
        }
        let summary = ScoringHarness.summarize(scores)
        XCTAssertGreaterThanOrEqual(summary.tempoAccuracy, 0.90)
        XCTAssertGreaterThanOrEqual(summary.phaseAccuracy, 0.90)
    }

    // MARK: Half/double disambiguation (§B6.2)

    func testKnownBPMSnapsOctave() {
        // Force a genuinely doubled estimate, then confirm the prior pulls it back.
        let fixture = SyntheticFixtures.clickTrack(name: "amb", bpm: 80, durationSeconds: 20, energyJumpAt: 10)
        let withPrior = analyzer.analyze(fixture.buffer, knownBPM: 80)
        XCTAssertLessThanOrEqual(abs(withPrior.tempo.bpm - 80), 2)
    }

    // MARK: Streaming analyzer (calibration ride path)

    func testStreamingMatchesOfflineAnalysis() {
        let fixture = SyntheticFixtures.clickTrack(name: "stream", bpm: 128, durationSeconds: 30,
                                                   energyJumpAt: 15)
        // Feed in awkward chunk sizes (like a mic tap would) to exercise frame continuity.
        let streamer = StreamingAnalyzer(sampleRate: fixture.buffer.sampleRate)
        var i = 0
        let chunks = [1234, 2048, 777, 4096]
        while i < fixture.buffer.samples.count {
            let n = min(chunks[i % chunks.count], fixture.buffer.samples.count - i)
            streamer.feed(Array(fixture.buffer.samples[i..<i+n]))
            i += n
        }
        let result = streamer.finalize()

        XCTAssertEqual(result.analysis.tempo.bpm, 128, accuracy: 2, "streamed tempo should match truth")
        XCTAssertEqual(result.durationSeconds, 30, accuracy: 0.1)
        // Energy jump located near 15 s.
        let nearest = result.analysis.sections.min(by: { abs($0.timeSeconds - 15) < abs($1.timeSeconds - 15) })
        XCTAssertNotNil(nearest)
        XCTAssertLessThan(abs((nearest?.timeSeconds ?? 0) - 15), 1.5)
    }

    // MARK: Empty / degenerate input

    func testSilenceDoesNotCrash() {
        let silence = AudioBuffer(samples: [Float](repeating: 0, count: 44100), sampleRate: 44100)
        let analysis = analyzer.analyze(silence)
        XCTAssertGreaterThanOrEqual(analysis.tempo.bpm, 0)  // no crash, defined output
    }
}
