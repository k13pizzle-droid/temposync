import SwiftUI
import RoutineKit
import RhythmCoachCore

/// Pre-ride storyboard: every move block of the whole class, song by song, before you clip in.
/// Mirrors the live generation exactly (same seeds, learned maps, effort/skill settings), so what
/// you preview is what you ride.
struct RideStoryboardView: View {
    let plan: ClassPlan

    private struct SongBoard: Identifiable {
        let id: String
        let title: String
        let role: SongRole
        let bpm: Double
        let learned: Bool
        let blocks: [(name: String, seconds: Int)]
    }

    /// Computed once on appear — as a computed property this regenerated every song's full routine
    /// (plus a SwiftData fetch each) on every body evaluation. The plan is immutable.
    @State private var boards: [SongBoard] = []

    var body: some View {
        List {
            ForEach(boards) { board in
                Section {
                    ForEach(Array(board.blocks.enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(block.name)
                                Spacer()
                                Text("\(block.seconds)s").monospacedDigit().foregroundStyle(.secondary)
                            }
                            // Effort bar: width ∝ duration, color = the move's effort tier.
                            Capsule()
                                .fill(RoleStyle.color(tier: RoleStyle.tier(forMoveNamed: block.name)).opacity(0.85))
                                .frame(width: max(24, CGFloat(block.seconds) * 2.4), height: 5)
                                .accessibilityHidden(true)   // duration is already spoken above
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    HStack {
                        Text(board.title).lineLimit(1)
                        Spacer()
                        Text("\(board.role.rawValue.uppercased()) · \(Int(board.bpm)) BPM"
                             + (board.learned ? " · learned" : ""))
                            .foregroundStyle(RoleStyle.color(board.role))
                    }
                }
            }
        }
        .navigationTitle("Ride preview")
        .onAppear { if boards.isEmpty { boards = buildBoards() } }
    }

    private func buildBoards() -> [SongBoard] {
        // One fetch for every learned map, instead of a store round-trip per song.
        let learnedMaps = (try? SectionMapStore.allMaps(in: AppServices.context)) ?? [:]
        return plan.songs.map { planned in
            let song = planned.song
            let bpm: Double
            let sections: [RoutineKit.Section]
            let learnedMap = learnedMaps[song.trackKey]
            if let learnedMap {
                bpm = learnedMap.bpm
                sections = learnedMap.sections
            } else {
                bpm = song.bpm ?? 128
                sections = StructurePrior().sections(bpm: bpm, durationSeconds: song.durationSeconds,
                                                     genre: .edmPop)
            }
            // EXACTLY the live request (seed 1, settings-driven effort/skill) — preview = ride.
            let request = RoutineRequest(trackKey: song.trackKey, bpm: bpm, sections: sections,
                                         confidence: learnedMap != nil ? .learned : .prior,
                                         skillLevel: AppServices.skill, intensity: AppServices.effort,
                                         seed: 1, classRole: planned.role)
            let routine = RoutineGenerator().generate(request)

            // Merge tiled same-move events into rider-visible blocks.
            var blocks: [(String, Int)] = []
            for event in routine.events {
                if let last = blocks.last, last.0 == event.move.name {
                    blocks[blocks.count - 1].1 += event.counts
                } else {
                    blocks.append((event.move.name, event.counts))
                }
            }
            let secondsPerCount = 60.0 / bpm
            return SongBoard(
                id: song.trackKey,
                title: song.title,
                role: planned.role,
                bpm: bpm,
                learned: learnedMap != nil,
                blocks: blocks.map { ($0.0, Int((Double($0.1) * secondsPerCount).rounded())) }
            )
        }
    }
}
