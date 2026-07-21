import Foundation

/// A labeled span of the song, in *counts* (beats) from the start of the routine.
/// `startCount` and `counts` are expected to be multiples of 4 (ideally 32, a full phrase).
public struct Section: Sendable, Hashable, Codable {
    public let type: SectionType
    /// Absolute count (beat index) where the section begins.
    public let startCount: Int
    /// Length of the section in counts.
    public let counts: Int
    /// Normalized energy 0...1 (from the SectionMap / StructurePrior). Advisory for now.
    public let energy: Double

    public init(type: SectionType, startCount: Int, counts: Int, energy: Double = 0.5) {
        self.type = type
        self.startCount = startCount
        self.counts = counts
        self.energy = energy
    }

    public var endCount: Int { startCount + counts }
}

/// The intensity dial (spec §B4) — 0 = easy, 1 = brutal. Biases which tier of move gets picked.
public struct IntensityDial: Sendable, Hashable, Codable {
    public let value: Double   // clamped to 0...1
    public init(_ value: Double) { self.value = min(max(value, 0), 1) }
    public static let easy = IntensityDial(0.15)
    public static let medium = IntensityDial(0.5)
    public static let hard = IntensityDial(0.85)
}

/// Everything the generator needs to produce a routine. Deterministic in `(trackKey, seed)`.
public struct RoutineRequest: Sendable, Hashable, Codable {
    /// Stable per-track identity (matches the SectionMap key). Also folded into the RNG seed.
    public let trackKey: String
    public let bpm: Double
    /// Ordered (or unordered — the generator sorts) section labels covering the song.
    public let sections: [Section]
    public let confidence: MapConfidence
    /// Hard gate: no emitted move exceeds this skill tier.
    public let skillLevel: SkillTier
    public let intensity: IntensityDial
    /// Reshuffle knob — same seed replays the same class; bump it to get a fresh routine.
    public let seed: UInt64
    /// This song's job in the class arc (nil = standalone song, no steering).
    public let classRole: SongRole?

    public init(
        trackKey: String,
        bpm: Double,
        sections: [Section],
        confidence: MapConfidence,
        skillLevel: SkillTier,
        intensity: IntensityDial,
        seed: UInt64,
        classRole: SongRole? = nil
    ) {
        self.trackKey = trackKey
        self.bpm = bpm
        self.sections = sections
        self.confidence = confidence
        self.skillLevel = skillLevel
        self.intensity = intensity
        self.seed = seed
        self.classRole = classRole
    }
}
