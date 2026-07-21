import Foundation

/// A song's job within a class arc (research: SoulCycle/Origin Fitness class formats — warm-up →
/// mixed main ride with jumps early, an arms song late, the biggest sprint near the end → cooldown).
/// Steers the generator's per-song plan: which signatures get favored, how hard the ceiling is,
/// and how dense the upper-body accents run.
public enum SongRole: String, Sendable, Codable, CaseIterable, Hashable {
    case warmup      // easy spin, effort capped at moderate
    case jumps       // the early blood-pumper — jumps favored as the chorus signature
    case run         // standing-run focused builder
    case climb       // heavy-resistance song (low-BPM songs fit best)
    case sprint      // peak effort — sprints favored as the signature
    case recovery    // active flush between waves
    case arms        // upper-body song — accents on every section (density cap still applies)
    case cooldown    // easy spin out, effort capped at moderate
}
