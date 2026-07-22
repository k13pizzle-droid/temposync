import Foundation
import RoutineKit
import BeatKit

/// The Mode S / calibration learning-loop output (spec §B3): a per-track map derived from a mic
/// playthrough — beat-grid offset, tempo, and typed, phrase-aligned sections ready for RoutineKit.
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

/// Turns beat analysis (tempo + beat grid + energy-step boundaries) into typed, phrase-aligned
/// `Section`s. Labeling is energy-rank heuristic for Phase 0 (genre-tuned labeling is Phase 2);
/// the output is always valid input for the generator.
public struct SectionCapture: Sendable {
    public let sectionDetector: SectionDetector

    public init(sectionDetector: SectionDetector = SectionDetector()) {
        self.sectionDetector = sectionDetector
    }

    /// Offline path: capture from a full audio buffer.
    public func capture(trackKey: String, buffer: AudioBuffer, analysis: BeatAnalysis) -> CapturedMap {
        let (energy, fr) = sectionDetector.energyEnvelope(buffer)
        return capture(trackKey: trackKey, analysis: analysis, durationSeconds: buffer.durationSeconds,
                       energy: energy, energyFrameRate: fr)
    }

    /// Streaming path: capture from a calibration ride's accumulated envelopes (no raw audio).
    public func capture(trackKey: String, streamed: StreamingAnalyzer.Result) -> CapturedMap {
        capture(trackKey: trackKey, analysis: streamed.analysis, durationSeconds: streamed.durationSeconds,
                energy: streamed.energy, energyFrameRate: streamed.energyFrameRate)
    }

    // MARK: - Shared core

    public func capture(trackKey: String, analysis: BeatAnalysis, durationSeconds: Double,
                        energy: [Double], energyFrameRate fr: Double) -> CapturedMap {
        let bpm = analysis.tempo.bpm
        let phraseLen = Routine.phraseLength
        let duration = durationSeconds

        func meanEnergy(_ start: Double, _ end: Double) -> Double {
            guard fr > 0, !energy.isEmpty else { return 0 }
            let lo = max(0, Int(start * fr)), hi = min(energy.count, Int(end * fr))
            guard hi > lo else { return 0 }
            var sum = 0.0
            for i in lo..<hi { sum += energy[i] }
            return sum / Double(hi - lo)
        }

        // Convert seconds → counts, snapped to whole phrases.
        func counts(_ seconds: Double) -> Int {
            let beats = seconds * bpm / 60.0
            let phrases = (beats / Double(phraseLen)).rounded()
            return Int(phrases) * phraseLen
        }

        // Segment edges: snap to the phrase grid FIRST, then dedup. The old order deduped raw
        // seconds by float equality, so near-duplicate boundaries survived, and the ≥1-phrase
        // inflation guard then padded each into a phantom phrase that pushed the map past the
        // song's real end. Snapped edges that collide now simply merge.
        let rawEdges = [0.0] + analysis.sections.map { $0.timeSeconds } + [duration]
        var countEdges = Set(rawEdges.map(counts)).sorted()
        let totalCounts = max(counts(duration), phraseLen)
        if countEdges.count < 2 { countEdges = [0, totalCounts] }   // degenerate capture → one section

        let secondsPerCount = 60.0 / bpm
        let energies = (0..<(countEdges.count - 1)).map {
            meanEnergy(Double(countEdges[$0]) * secondsPerCount,
                       Double(countEdges[$0 + 1]) * secondsPerCount)
        }
        let maxE = max(energies.max() ?? 1, 1e-9)

        var raw: [(type: SectionType, start: Int, end: Int, energy: Double)] = []
        for i in 0..<(countEdges.count - 1) {
            let start = countEdges[i], end = countEdges[i + 1]
            let norm = energies[i] / maxE
            let isFirst = (i == 0), isLast = (i == countEdges.count - 2)
            let late = Double(start) / Double(totalCounts) > 0.55
            let type = label(norm: norm, isFirst: isFirst, isLast: isLast, late: late)
            raw.append((type, start, end, norm))
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
