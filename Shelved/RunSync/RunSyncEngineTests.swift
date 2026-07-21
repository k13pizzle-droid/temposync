// Extracted from RhythmCoachCoreTests when RunSync was shelved (2026-07-21).
// Re-add to the future RunSync app's test target alongside RunSyncEngine.swift.

import XCTest

final class RunSyncEngineTests: XCTestCase {

    func testRunSyncFirstTrackAndHalfDoubleMatch() {
        let lib = [
            RunTrack(id: "a", title: "A", artist: "x", bpm: 85),   // matches 170 spm at double-time
            RunTrack(id: "b", title: "B", artist: "x", bpm: 128),
        ]
        let engine = RunSyncEngine(library: lib)
        let decision = engine.ingest(cadence: 170, at: 0)
        guard case .switchTo(let t) = decision else { return XCTFail("expected first-track switch") }
        XCTAssertEqual(t.id, "a", "170 spm should match the 85 BPM track via double-time")
    }

    func testRunSyncDeadBandSuppressesSmallChange() {
        let lib = [RunTrack(id: "a", title: "A", artist: "x", bpm: 160),
                   RunTrack(id: "b", title: "B", artist: "x", bpm: 175)]
        let engine = RunSyncEngine(library: lib)
        _ = engine.ingest(cadence: 160, at: 0)
        for (i, c) in [162.0, 158, 161, 163].enumerated() {
            XCTAssertEqual(engine.ingest(cadence: c, at: Double(i + 1) * 5), .keepCurrent)
        }
    }

    func testRunSyncSwitchesOnSustainedChange() {
        let lib = [RunTrack(id: "slow", title: "S", artist: "x", bpm: 155),
                   RunTrack(id: "fast", title: "F", artist: "x", bpm: 180)]
        let engine = RunSyncEngine(library: lib)
        engine.emaAlpha = 1.0
        _ = engine.ingest(cadence: 155, at: 0)
        var last: RunDecision = .keepCurrent
        for t in stride(from: 100.0, through: 130, by: 5) {
            last = engine.ingest(cadence: 180, at: t)
            if case .switchTo = last { break }
        }
        guard case .switchTo(let t) = last else { return XCTFail("expected a switch to the fast track") }
        XCTAssertEqual(t.id, "fast")
    }
}
