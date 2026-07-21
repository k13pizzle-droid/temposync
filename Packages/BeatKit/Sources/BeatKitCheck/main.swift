import Foundation
import BeatKit

// Runnable DSP spike + scoring harness (`swift run BeatKitCheck`).
// Generates the 100/128/174 BPM synthetic fixtures, writes them as WAV, reads them back, analyzes,
// and scores against the §B3 success bar: ≥90% tempo correct (within half/double), beat phase ±50 ms.

final class Reporter {
    var failures = 0
    func expect(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("  \(ok ? "✅" : "❌") \(name)\(detail.isEmpty ? "" : "  \(detail)")")
        if !ok { failures += 1 }
    }
}

let r = Reporter()
let analyzer = BeatAnalyzer()

print("BeatKit — DSP spike & scoring harness (spec §B3, open question 1)\n")

// Where to write fixtures (cwd is the package root under `swift run`).
let fixturesDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Fixtures")
try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)

let fixtures = SyntheticFixtures.canonicalThree(durationSeconds: 30)

print("Synthetic fixtures (written as 16-bit PCM WAV, then re-read from disk):")
var scores: [FixtureScore] = []
for fixture in fixtures {
    let url = fixturesDir.appendingPathComponent("\(fixture.name).wav")
    try WAVFile.write(fixture.buffer, to: url)
    let reloaded = try WAVFile.read(url)

    // Round-trip sanity: sample count preserved.
    let sampleDelta = abs(reloaded.samples.count - fixture.buffer.samples.count)
    if sampleDelta > 1 {
        r.expect("\(fixture.name): WAV round-trip preserves length", false, "(Δ\(sampleDelta) samples)")
    }

    let analysis = analyzer.analyze(reloaded)
    let score = ScoringHarness.score(analysis, against: fixture)
    scores.append(score)

    let sectionStr = score.sectionErrorSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
    print(String(format: "  %-16@ true %6.1f  est %6.1f  tempo %@  phase %5.1fms %@  section±%@",
                 fixture.name as NSString, score.trueBPM, score.estimatedBPM,
                 score.tempoCorrect ? "OK " : "BAD",
                 score.beatPhaseErrorMs, score.phaseWithinTarget ? "OK " : "BAD",
                 sectionStr))
}

let summary = ScoringHarness.summarize(scores)
print(String(format: "\nTempo accuracy: %.0f%%   Beat-phase accuracy: %.0f%%",
             summary.tempoAccuracy * 100, summary.phaseAccuracy * 100))

print("\n§B3 success bar:")
r.expect("tempo accuracy ≥ 90% (within half/double)", summary.tempoAccuracy >= 0.90,
         String(format: "(got %.0f%%)", summary.tempoAccuracy * 100))
r.expect("every fixture beat phase ≤ 50 ms", scores.allSatisfy { $0.phaseWithinTarget })
r.expect("every fixture tempo exact (±2 BPM)", scores.allSatisfy { $0.tempoExact },
         "(exact match, not just half/double)")
r.expect("energy jump located within 1.0 s on every fixture",
         scores.allSatisfy { ($0.sectionErrorSeconds ?? .infinity) <= 1.0 })

print("\nHalf/double disambiguation (spec §B6.2) — knownBPM from GetSongBPM cache:")
// A fixture whose true tempo (85) folds ambiguously; without a prior the folder may pick 170.
// With knownBPM the estimator must snap to the correct octave.
let ambiguous = SyntheticFixtures.clickTrack(name: "click-85bpm", bpm: 85, durationSeconds: 24,
                                             energyJumpAt: 12)
let withoutPrior = analyzer.analyze(ambiguous.buffer)
let withPrior = analyzer.analyze(ambiguous.buffer, knownBPM: 85)
print(String(format: "  without prior: %.1f BPM   with knownBPM=85: %.1f BPM",
             withoutPrior.tempo.bpm, withPrior.tempo.bpm))
r.expect("knownBPM snaps estimate to the correct octave", abs(withPrior.tempo.bpm - 85) <= 2)

print("\nExtra tempo coverage (sweep across the spin range):")
var sweepScores: [FixtureScore] = []
for bpm in stride(from: 92.0, through: 178.0, by: 6.0) {
    let f = SyntheticFixtures.clickTrack(name: "sweep-\(Int(bpm))", bpm: bpm, durationSeconds: 20)
    sweepScores.append(ScoringHarness.score(analyzer.analyze(f.buffer), against: f))
}
let sweepSummary = ScoringHarness.summarize(sweepScores)
print(String(format: "  swept %d tempos → tempo accuracy %.0f%%, phase accuracy %.0f%%",
             sweepScores.count, sweepSummary.tempoAccuracy * 100, sweepSummary.phaseAccuracy * 100))
r.expect("swept tempo accuracy ≥ 90%", sweepSummary.tempoAccuracy >= 0.90,
         String(format: "(got %.0f%%)", sweepSummary.tempoAccuracy * 100))
r.expect("swept phase accuracy ≥ 90%", sweepSummary.phaseAccuracy >= 0.90,
         String(format: "(got %.0f%%)", sweepSummary.phaseAccuracy * 100))

// MARK: Real-song fixture set (spec open question 3)

print("\nReal-song fixture set (Kevin's spin playlist) — manifest loaded from RealTrackFixtures:")
for t in RealTrackFixtures.spinSetOne {
    let bpm = t.referenceBPM.map { String(format: "%6.1f", $0) } ?? "   ???"
    let key = t.key ?? "—"
    let cam = t.camelot ?? "—"
    print(String(format: "  %@ BPM  %-4@ %-12@ %@ – %@", bpm as NSString, cam as NSString, key as NSString,
                 t.artist as NSString, t.title as NSString))
}

let realDir = fixturesDir.appendingPathComponent("real")
try? FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
var present = 0
var realMismatches = 0
for t in RealTrackFixtures.spinSetOne {
    let url = realDir.appendingPathComponent("\(t.slug).wav")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    present += 1
    // Blind estimate (no knownBPM) so the score is a genuine validation, not circular.
    guard let analysis = try? analyzer.analyzeWAV(at: url) else {
        print("  ⚠️  \(t.slug): could not read WAV"); continue
    }
    if let ref = t.referenceBPM {
        let ok = ScoringHarness.tempoMatches(estimated: analysis.tempo.bpm, reference: ref)
        if !ok { realMismatches += 1 }
        print(String(format: "  %@ %-28@ est %6.1f vs ref %6.1f  (%d sections)",
                     ok ? "✅" : "❌", t.slug as NSString, analysis.tempo.bpm, ref, analysis.sections.count))
    } else {
        print(String(format: "  🎯 %-28@ est %6.1f (unresolved → seeds cache, %d sections)",
                     t.slug as NSString, analysis.tempo.bpm, analysis.sections.count))
    }
}

if present == 0 {
    print("""
      No audio files found in \(realDir.path)
      To score BeatKit on these real tracks, drop a local copy of each as <slug>.wav there.
      Convert an owned file (m4a/mp3) to the expected mono 16-bit PCM WAV with macOS' afconvert:
        afconvert -f WAVE -d LEI16@44100 -c 1 input.m4a "\(realDir.path)/<slug>.wav"
      Then re-run: swift run BeatKitCheck   (scoring is blind — reference BPM is not fed in)
      (In the iOS app the same buffers come from AVAudioFile/AVAudioEngine — no conversion needed.)
    """)
} else {
    print("     scored \(present) real track(s); \(realMismatches) tempo mismatch(es)")
}

print("")
if r.failures == 0 {
    print("ALL CHECKS PASSED ✅   (fixtures written to \(fixturesDir.path))")
} else {
    print("FAILURES: \(r.failures) ❌")
    exit(1)
}
