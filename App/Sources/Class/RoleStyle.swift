import SwiftUI
import RoutineKit
import RhythmCoachCore

/// Shared color language for roles and effort tiers (setup rows, storyboard, saved classes).
enum RoleStyle {
    static func color(_ role: SongRole) -> Color {
        switch role {
        case .warmup, .cooldown: return .blue
        case .jumps: return .orange
        case .run: return .teal
        case .climb: return .brown
        case .sprint: return .red
        case .recovery: return .indigo
        case .arms: return .purple
        }
    }

    static func color(tier: IntensityTier) -> Color {
        switch tier {
        case .recovery: return .blue
        case .moderate: return .teal
        case .high: return .orange
        case .peak: return .red
        }
    }

    static func tier(forMoveNamed name: String) -> IntensityTier {
        MoveLibrary.v1.first(where: { $0.name == name })?.intensityTier ?? .moderate
    }
}
