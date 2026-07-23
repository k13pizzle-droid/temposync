import Foundation

/// How fast the legs turn relative to the beat — the difference between a light spin, a base ride,
/// and a heavy half-time grind. The rider's downstroke always lands on a beat; this sets which beats.
public enum Cadence: String, Sendable, Hashable, Codable {
    /// Half-time heavy grind: one crank revolution every 4 beats. Cutting the beat in half — the
    /// snare-on-3 feel — with heavy resistance. A 128 BPM song grinds at ~32 RPM.
    case grind
    /// The base ride: one revolution every 2 beats, downstroke on alternating beats. ~64 RPM @128.
    case standard
    /// Sprint: one revolution per beat, riding the beat itself. ~128 RPM @128.
    case sprint

    /// Crank revolutions per beat — drives both the suggested RPM and the pictogram's leg speed.
    public var revsPerBeat: Double {
        switch self {
        case .grind:    return 0.25
        case .standard: return 0.5
        case .sprint:   return 1.0
        }
    }
}

/// A single entry in the rhythm-riding vocabulary (spec §B4 "Move library").
///
/// `allowedCounts` holds the *block lengths* a move may occupy, drawn from {8, 16, 32}.
/// (The spec's field domain is {4,8,16,32}; the 4-count value is excluded here because the
/// dwell-minimum rule forbids any emitted block shorter than 8 counts. A "4-count jump" is a
/// beat cadence *inside* an 8+ count block, not a 4-count block.)
public struct Move: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }

    /// Display name, also the stable identity.
    public let name: String
    /// Legal block lengths in counts. Every value must be a multiple of 4 and ≥ 8.
    public let allowedCounts: [Int]
    /// Effort tier — used for intensity biasing and peak/recovery bookkeeping.
    public let intensityTier: IntensityTier
    /// Saddle position — anything non-seated triggers the resistance floor.
    public let position: Position
    /// Song sections this move belongs in.
    public let sectionAffinity: Set<SectionType>
    /// If true, the move needs adequate flywheel resistance even while seated (e.g. climbs, sprints).
    public let requiresResistanceFloor: Bool
    /// Upper-body / hand choreography — gated by the density cap (≤1 block per 2 phrases).
    public let upperBody: Bool
    /// Minimum rider skill to be offered this move.
    public let skillTier: SkillTier
    /// Leg speed relative to the beat (base / sprint / heavy grind). Defaults to `.standard`.
    public let cadence: Cadence
    /// One-line form coaching cue shown on the live screen (spec §B5).
    public let formCue: String

    public init(
        name: String,
        allowedCounts: [Int],
        intensityTier: IntensityTier,
        position: Position,
        sectionAffinity: Set<SectionType>,
        requiresResistanceFloor: Bool,
        upperBody: Bool,
        skillTier: SkillTier,
        cadence: Cadence = .standard,
        formCue: String
    ) {
        self.name = name
        self.allowedCounts = allowedCounts
        self.intensityTier = intensityTier
        self.position = position
        self.sectionAffinity = sectionAffinity
        self.requiresResistanceFloor = requiresResistanceFloor
        self.upperBody = upperBody
        self.skillTier = skillTier
        self.cadence = cadence
        self.formCue = formCue
    }

    /// True when the move is out of the saddle (standing or hybrid).
    public var isOutOfSaddle: Bool { position != .seated }

    /// True when the move must be preceded by an "add resistance" cue:
    /// any out-of-saddle move, any upper-body move, or a move that explicitly needs a resistance floor.
    public var needsResistance: Bool {
        isOutOfSaddle || upperBody || requiresResistanceFloor
    }
}
