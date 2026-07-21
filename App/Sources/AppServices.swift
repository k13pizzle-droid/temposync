import Foundation
import SwiftData
import RoutineKit
import RhythmCoachCore

/// App-wide singletons: the SwiftData container backing the TrackTempo cache (+ future SectionMaps),
/// and the BPM waterfall built from the user's GetSongBPM key (Settings).
@MainActor
enum AppServices {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: SectionMapStore.schema)
        } catch {
            // Never brick the app over a cache store — fall back to in-memory.
            return try! ModelContainer(
                for: SectionMapStore.schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        }
    }()

    static var context: ModelContext { container.mainContext }

    /// The class currently being ridden (nil = freestyle). Set by ClassSetupView on start; the live
    /// view model reads per-track roles from it and clears it when the session ends.
    static var activeClassPlan: ClassPlan?

    static let apiKeyDefaultsKey = "getsongbpm_api_key"
    static let effortDefaultsKey = "effort_level"      // "easy" | "medium" | "hard"
    static let skillDefaultsKey = "skill_tier"         // 1 | 2 | 3

    /// The rider's configured effort dial (Settings → Ride).
    static var effort: IntensityDial {
        switch UserDefaults.standard.string(forKey: effortDefaultsKey) {
        case "easy": return .easy
        case "hard": return .hard
        default:     return .medium
        }
    }

    /// The rider's configured skill tier (Settings → Ride). Defaults to 2.
    static var skill: SkillTier {
        SkillTier(rawValue: UserDefaults.standard.integer(forKey: skillDefaultsKey)) ?? .two
    }

    /// Waterfall: SwiftData cache → seeded fixture table → Deezer (no key, popularity-ranked
    /// search) → GetSongBPM (different coverage). GetSongBPM key precedence: Settings override →
    /// the app's built-in key (Secrets.swift, gitignored).
    static func makeBPMWaterfall() -> BPMWaterfall {
        let override = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = override.isEmpty ? Secrets.defaultGetSongBPMKey : override
        var services: [BPMLookupService] = [DeezerBPMService()]
        if !key.isEmpty { services.append(GetSongBPMService(apiKey: key)) }
        return BPMWaterfall(services: services, context: context)
    }
}
