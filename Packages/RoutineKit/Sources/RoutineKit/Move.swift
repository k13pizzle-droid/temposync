import Foundation

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
