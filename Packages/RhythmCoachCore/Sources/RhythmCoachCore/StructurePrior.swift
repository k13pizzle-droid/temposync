import Foundation
import RoutineKit

/// Genre families for the structure heuristic. Confidence differs by genre (spec §B6.5: strong for
/// EDM/pop, weak for rock/live).
public enum Genre: String, Sendable, Codable, CaseIterable {
    case edmPop
    case hipHop
    case rock
    case generic
}

/// Mode H fallback (spec §B3): when there's no learned SectionMap, lay out a probabilistic section
/// template scaled to the track's duration + BPM, aligned to 32-count phrases with drops on phrase
/// boundaries. Returns `.prior` confidence work — the caller softens cues accordingly.
public struct StructurePrior: Sendable {
    public init() {}

    /// Relative section template (in phrases) for each genre; tiled/scaled to fill the track.
    private func template(for genre: Genre) -> [SectionType] {
        switch genre {
        case .edmPop:
            return [.intro, .verse, .verse, .preChorus, .chorus, .chorus,
                    .verse, .verse, .preChorus, .drop, .drop, .chorus, .chorus,
                    .bridge, .chorus, .chorus, .outro]
        case .hipHop:
            return [.intro, .verse, .verse, .chorus, .verse, .verse, .chorus,
                    .bridge, .verse, .chorus, .outro]
        case .rock:
            return [.intro, .verse, .verse, .chorus, .chorus, .verse, .verse,
                    .chorus, .chorus, .bridge, .chorus, .outro]
        case .generic:
            // Conservative: gentle verse/chorus alternation, no aggressive drops.
            return [.intro, .verse, .verse, .chorus, .verse, .verse, .chorus, .chorus, .outro]
        }
    }

    /// Build phrase-aligned sections covering the whole track.
    public func sections(bpm: Double, durationSeconds: Double, genre: Genre = .edmPop) -> [Section] {
        guard bpm > 0, durationSeconds > 0 else { return [] }
        let phraseLen = Routine.phraseLength                     // 32 counts
        let totalBeats = durationSeconds * bpm / 60.0
        let totalPhrases = max(1, Int((totalBeats / Double(phraseLen)).rounded()))

        let blocks = template(for: genre)
        // Each template entry is one phrase; if the track is longer, repeat the middle body; if
        // shorter, truncate but always keep at least intro + one body phrase.
        var layout: [SectionType]
        if totalPhrases <= blocks.count {
            layout = Array(blocks.prefix(totalPhrases))
        } else {
            layout = blocks
            // Repeat the body (everything except intro/outro) until we fill the track.
            let body = Array(blocks.dropFirst().dropLast())
            var i = 0
            while layout.count < totalPhrases {
                // insert before the outro
                layout.insert(body[i % body.count], at: layout.count - 1)
                i += 1
            }
        }

        // Coalesce consecutive identical labels into single sections.
        var sections: [Section] = []
        var idx = 0
        while idx < layout.count {
            let type = layout[idx]
            var span = 1
            while idx + span < layout.count && layout[idx + span] == type { span += 1 }
            let start = (sections.last?.endCount) ?? 0
            let energy = energyFor(type)
            sections.append(Section(type: type, startCount: start, counts: span * phraseLen, energy: energy))
            idx += span
        }
        return sections
    }

    private func energyFor(_ type: SectionType) -> Double {
        switch type {
        case .intro: return 0.2
        case .verse: return 0.45
        case .preChorus: return 0.65
        case .chorus: return 0.9
        case .drop: return 1.0
        case .bridge: return 0.4
        case .breakdown: return 0.3
        case .outro: return 0.2
        }
    }
}
