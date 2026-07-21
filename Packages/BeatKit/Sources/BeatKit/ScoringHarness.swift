import Foundation

/// Objective score of an analysis against a fixture's ground truth (spec §B6.1 / open question 1).
public struct FixtureScore: Sendable {
    public let name: String
    public let trueBPM: Double
    public let estimatedBPM: Double
    /// True if the estimate matches within tolerance, allowing exact half/double (the spec's
    /// "within half/double resolution").
    public let tempoCorrect: Bool
    /// True if the estimate matches the *exact* BPM within tolerance (stricter than tempoCorrect).
    public let tempoExact: Bool
    /// Median distance from each true beat to the nearest estimated beat, in milliseconds.
    public let beatPhaseErrorMs: Double
    /// Whether beat phase meets the ±50 ms bar.
    public let phaseWithinTarget: Bool
    /// Detected section boundary error (seconds) against the true energy jump, if applicable.
    public let sectionErrorSeconds: Double?

    public var passes: Bool { tempoCorrect && phaseWithinTarget }
}

public enum ScoringHarness {

    public static let bpmTolerance = 2.0        // ±2 BPM counts as correct
    public static let phaseTargetMs = 50.0      // spec §B3 beat phase target
    public static let sectionToleranceSeconds = 1.0

    public static func score(_ analysis: BeatAnalysis, against fixture: SyntheticFixture) -> FixtureScore {
        let est = analysis.tempo.bpm
        let truth = fixture.trueBPM

        let exact = abs(est - truth) <= bpmTolerance
        let halfDouble = abs(est - truth * 2) <= bpmTolerance || abs(est - truth / 2) <= bpmTolerance
        let tempoCorrect = exact || halfDouble

        // Beat-phase error: median nearest-neighbor distance from truth beats to estimated beats.
        let phaseMs = medianBeatError(estimated: analysis.grid.beatTimes,
                                      truth: fixture.trueBeatTimes) * 1000.0

        // Section boundary error against the single energy jump.
        var sectionError: Double? = nil
        if let trueBoundary = fixture.trueSectionBoundary {
            if let nearest = analysis.sections.min(by: {
                abs($0.timeSeconds - trueBoundary) < abs($1.timeSeconds - trueBoundary)
            }) {
                sectionError = abs(nearest.timeSeconds - trueBoundary)
            }
        }

        return FixtureScore(
            name: fixture.name,
            trueBPM: truth,
            estimatedBPM: est,
            tempoCorrect: tempoCorrect,
            tempoExact: exact,
            beatPhaseErrorMs: phaseMs,
            phaseWithinTarget: phaseMs <= phaseTargetMs,
            sectionErrorSeconds: sectionError
        )
    }

    private static func medianBeatError(estimated: [Double], truth: [Double]) -> Double {
        guard !estimated.isEmpty, !truth.isEmpty else { return .infinity }
        var errors: [Double] = []
        errors.reserveCapacity(truth.count)
        for beat in truth {
            let nearest = estimated.min(by: { abs($0 - beat) < abs($1 - beat) })!
            errors.append(abs(nearest - beat))
        }
        errors.sort()
        let mid = errors.count / 2
        return errors.count % 2 == 0 ? (errors[mid - 1] + errors[mid]) / 2 : errors[mid]
    }

    /// Half/double-aware tempo match, for scoring against a reference BPM (real songs have no
    /// ground-truth beat grid, so we validate tempo against GetSongBPM/Tunebat).
    public static func tempoMatches(estimated: Double, reference: Double, tolerance: Double = bpmTolerance) -> Bool {
        abs(estimated - reference) <= tolerance ||
        abs(estimated - reference * 2) <= tolerance ||
        abs(estimated - reference / 2) <= tolerance
    }

    /// Aggregate pass rate across a fixture set.
    public static func summarize(_ scores: [FixtureScore]) -> (tempoAccuracy: Double, phaseAccuracy: Double) {
        guard !scores.isEmpty else { return (0, 0) }
        let tempo = Double(scores.filter { $0.tempoCorrect }.count) / Double(scores.count)
        let phase = Double(scores.filter { $0.phaseWithinTarget }.count) / Double(scores.count)
        return (tempo, phase)
    }
}
