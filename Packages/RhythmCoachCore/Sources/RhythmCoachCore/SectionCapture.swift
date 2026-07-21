import Foundation
import RoutineKit
import BeatKit

/// The Mode S learning-loop output (spec §B3): a per-track map derived from a mic playthrough —
/// beat-grid offset, tempo, and typed, phrase-aligned sections ready for RoutineKit.
public struct CapturedMap: Sendable, Equatable, Codable {
    public let trackKey: String
    public let bpm: Double
    public let beatGridOffset: Double
    public let sections: [Section]
    /// 0...1 quality of the capture (drives the learned/prior confidence tier).
    public let captureQuality: Double

    public init(trackKey: String, bpm: Double, beatGridOffset: Double, sections: [Section], captureQuality: Double) {
        self.trackKey = trackKey
        self.bpm = bpm
        self.beatGridOffset = beatGridOffset
        self.sections = sections
        self.captureQuality = captureQuality
    }
}

/// Turns a BeatKit `BeatAnalysis` (tempo + beat grid + energy-step boundaries) into typed,
/// phrase-aligned `Section`s. Labeling is energy-rank heuristic for Phase 0 (genre-tuned labeling is
/// Phase 2); the output is always valid input for the generator.
public struct SectionCapture: Sendable {
    public let sectionDetector: SectionDetector

    public init(sectionDetector: SectionDetector = SectionDetector()) {
        self.sectionDetector = sectionDetector
    }

    public func capture(trackKey: String, buffer: AudioBuffer, analysis: BeatAnalysis) -> CapturedMap {
        let bpm = analysis.tempo.bpm
        let phraseLen = Routine.phraseLength
        let duration = buffer.durationSeconds

        // Segment edges in seconds: 0, each boundary, end.
        var edges = [0.0] + analysis.sections.map { $0.timeSeconds } + [duration]
        edges = Array(Set(edges)).sorted()

        // Mean energy per segment (from the detector's short-term RMS envelope).
        let (energy, fr) = sectionDetector.energyEnvelope(buffer)
        func meanEnergy(_ start: Double, _ end: Double) -> Double {
            guard fr > 0, !energy.isEmpty else { return 0 }
            let lo = max(0, Int(start * fr)), hi = min(energy.count, Int(end * fr))
            guard hi > lo else { return 0 }
            var sum = 0.0
            for i in lo..<hi { sum += energy[i] }
            return sum / Double(hi - lo)
        }

        // Convert seconds → counts, snapped to whole phrases, and keep segments monotonic & non-empty.
        func counts(_ seconds: Double) -> Int {
            let beats = seconds * bpm / 60.0
            let phrases = (beats / Double(phraseLen)).rounded()
            return Int(phrases) * phraseLen
        }

        var raw: [(type: SectionType, start: Int, end: Int, energy: Double)] = []
        let energies = (0..<(edges.count - 1)).map { meanEnergy(edges[$0], edges[$0 + 1]) }
        let maxE = max(energies.max() ?? 1, 1e-9)

        var cursor = 0
        for i in 0..<(edges.count - 1) {
            var end = counts(edges[i + 1])
            if end <= cursor { end = cursor + phraseLen }      // guarantee ≥ 1 phrase
            let norm = energies[i] / maxE
            let isFirst = (i == 0), isLast = (i == edges.count - 2)
            let late = Double(cursor) / Double(max(counts(duration), phraseLen)) > 0.55
            let type = label(norm: norm, isFirst: isFirst, isLast: isLast, late: late)
            raw.append((type, cursor, end, norm))
            cursor = end
        }

        // Coalesce neighbors of the same type.
        var sections: [Section] = []
        for seg in raw {
            if let last = sections.last, last.type == seg.type {
                sections[sections.count - 1] = Section(type: last.type, startCount: last.startCount,
                                                       counts: last.counts + (seg.end - seg.start),
                                                       energy: max(last.energy, seg.energy))
            } else {
                sections.append(Section(type: seg.type, startCount: seg.start,
                                        counts: seg.end - seg.start, energy: seg.energy))
            }
        }

        let quality = min(max(analysis.tempo.strength, 0), 1)
        return CapturedMap(trackKey: trackKey, bpm: bpm,
                           beatGridOffset: analysis.grid.offsetSeconds,
                           sections: sections, captureQuality: quality)
    }

    private func label(norm: Double, isFirst: Bool, isLast: Bool, late: Bool) -> SectionType {
        if isFirst { return .intro }
        if isLast { return .outro }
        switch norm {
        case 0.85...:      return late ? .drop : .chorus
        case 0.65..<0.85:  return .chorus
        case 0.45..<0.65:  return .verse
        case 0.25..<0.45:  return .bridge
        default:           return .breakdown
        }
    }
}
