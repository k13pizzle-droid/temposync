import Foundation

/// Where the rider is relative to the saddle. Drives the resistance-floor rule:
/// anything not `.seated` is "out of saddle" and must be preceded by added resistance.
public enum Position: String, Sendable, Codable, CaseIterable, Hashable {
    case seated
    case standing
    case hybrid   // e.g. jumps — transitions in and out of the saddle
}

/// Song structure labels. Effort convention (spec §B1):
/// verse = ride/recover · chorus/drop = peak · slow/heavy = climb · bridge/breakdown = recovery / upper body.
public enum SectionType: String, Sendable, Codable, CaseIterable, Hashable {
    case intro
    case verse
    case preChorus
    case chorus
    case drop
    case bridge
    case breakdown
    case outro
}

/// Effort tier of a move. Ordered so the generator can bias selection by the intensity dial
/// and so the "2 consecutive peak phrases → mandatory recovery" rule can be evaluated.
public enum IntensityTier: Int, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case recovery = 0
    case moderate = 1
    case high = 2
    case peak = 3

    public static func < (lhs: IntensityTier, rhs: IntensityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Rider skill gate. `SkillTier(3)` unlocks corners/cross-ups etc. The generator never emits a
/// move whose `skillTier` exceeds the rider's setting (spec §B4 "skill setting gates skillTier").
public enum SkillTier: Int, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case one = 1
    case two = 2
    case three = 3

    public static func < (lhs: SkillTier, rhs: SkillTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Confidence of the structure map feeding the generator (spec §B3 learning loop).
/// `.learned` (mic-derived SectionMap) unlocks hard countdowns; `.prior` (heuristic) softens cues.
public enum MapConfidence: String, Sendable, Codable, CaseIterable, Hashable {
    case learned
    case prior
}
