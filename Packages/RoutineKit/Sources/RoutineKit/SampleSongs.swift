import Foundation

/// Canned song structures for demos and tests. Every section is phrase-aligned (multiples of 32).
public enum SampleSongs {

    /// A ~4-minute EDM/pop arc with clear verses, choruses and a drop — the "rave" framing from §B1.
    /// 128 BPM, sections in 32-count phrases.
    public static func edmAnthem(seed: UInt64 = 42,
                                 skill: SkillTier = .three,
                                 intensity: IntensityDial = .hard,
                                 confidence: MapConfidence = .learned) -> RoutineRequest {
        var sections: [Section] = []
        var c = 0
        func add(_ type: SectionType, phrases: Int, energy: Double) {
            sections.append(Section(type: type, startCount: c, counts: phrases * 32, energy: energy))
            c += phrases * 32
        }
        add(.intro, phrases: 2, energy: 0.2)
        add(.verse, phrases: 4, energy: 0.4)
        add(.preChorus, phrases: 2, energy: 0.6)
        add(.chorus, phrases: 4, energy: 0.9)
        add(.breakdown, phrases: 2, energy: 0.3)
        add(.verse, phrases: 4, energy: 0.5)
        add(.preChorus, phrases: 2, energy: 0.7)
        add(.drop, phrases: 4, energy: 1.0)
        add(.chorus, phrases: 4, energy: 0.9)
        add(.bridge, phrases: 2, energy: 0.4)
        add(.chorus, phrases: 4, energy: 0.95)
        add(.outro, phrases: 2, energy: 0.2)

        return RoutineRequest(
            trackKey: "sample:edm-anthem",
            bpm: 128,
            sections: sections,
            confidence: confidence,
            skillLevel: skill,
            intensity: intensity,
            seed: seed
        )
    }
}
