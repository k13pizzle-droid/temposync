import SwiftUI
import RoutineKit

/// The 5-level class difficulty. One knob drives BOTH the intensity dial and the skill gate —
/// crank it to Super Hard and the advanced vocabulary (corners, big signatures) comes out to play.
enum ClassDifficulty: Int, CaseIterable, Identifiable {
    case superEasy = 0, easy, medium, difficult, superHard

    var id: Int { rawValue }
    static let defaultsKey = "class_difficulty"

    var name: String {
        switch self {
        case .superEasy: return "Super Easy"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .difficult: return "Difficult"
        case .superHard: return "Super Hard"
        }
    }

    var blurb: String {
        switch self {
        case .superEasy: return "Recovery pace. Spin easy and breathe."
        case .easy: return "Light work, simple choreography."
        case .medium: return "The standard class."
        case .difficult: return "Heavy climbs and honest sprints."
        case .superHard: return "Everything unlocked. Pace yourself."
        }
    }

    var color: Color {
        switch self {
        case .superEasy: return .blue
        case .easy: return .teal
        case .medium: return .green
        case .difficult: return .orange
        case .superHard: return .red
        }
    }

    /// Intensity dial position (0, .25, .5, .75, 1 → tier shift −2…+2 in the generator).
    var intensity: IntensityDial { IntensityDial(Double(rawValue) / 4.0) }

    /// Skill gate: the top of the dial unlocks the advanced moves.
    var skill: SkillTier {
        switch self {
        case .superEasy, .easy: return .one
        case .medium, .difficult: return .two
        case .superHard: return .three
        }
    }
}

/// The dial control: drag through five detents; the bolt meter and color track the level.
struct DifficultyDial: View {
    @Binding var difficulty: ClassDifficulty

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(0..<5) { i in
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(i <= difficulty.rawValue
                                             ? difficulty.color : Color.white.opacity(0.15))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(difficulty.name).font(Theme.bold(17)).foregroundStyle(difficulty.color)
                    Text(difficulty.blurb).font(Theme.regular(12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Slider(
                value: Binding(
                    get: { Double(difficulty.rawValue) },
                    set: { difficulty = ClassDifficulty(rawValue: Int($0.rounded())) ?? .medium }
                ),
                in: 0...4, step: 1
            )
            .tint(difficulty.color)
        }
    }
}
