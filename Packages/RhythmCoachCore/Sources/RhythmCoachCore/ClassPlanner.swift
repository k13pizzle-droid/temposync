import Foundation
import RoutineKit

/// A playlist track as the planner sees it.
public struct ClassSong: Sendable, Equatable, Identifiable {
    public var id: String { trackKey }
    public let trackKey: String
    public let title: String
    public let artist: String
    public let durationSeconds: Double
    public let bpm: Double?

    public init(trackKey: String, title: String, artist: String, durationSeconds: Double, bpm: Double?) {
        self.trackKey = trackKey
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.bpm = bpm
    }
}

public struct PlannedSong: Sendable, Equatable, Identifiable {
    public var id: String { song.trackKey }
    public let song: ClassSong
    public let role: SongRole

    public init(song: ClassSong, role: SongRole) {
        self.song = song
        self.role = role
    }
}

public enum ClassFormat: Int, Sendable, CaseIterable, Identifiable {
    case fifteen = 15, thirty = 30, fortyFive = 45, sixty = 60
    public var id: Int { rawValue }
    public var minutes: Int { rawValue }
}

public struct ClassPlan: Sendable, Equatable {
    public let format: ClassFormat
    public let songs: [PlannedSong]
    public let reordered: Bool

    public init(format: ClassFormat, songs: [PlannedSong], reordered: Bool) {
        self.format = format
        self.songs = songs
        self.reordered = reordered
    }

    public var totalSeconds: Double { songs.reduce(0) { $0 + $1.song.durationSeconds } }

    public func role(for trackKey: String) -> SongRole? {
        songs.first(where: { $0.song.trackKey == trackKey })?.role
    }
}

/// Builds a class from a playlist (research-grounded: SoulCycle/Origin Fitness formats — warm-up
/// ~12%, main arc with jumps early / arms song late / biggest sprint near the end, cooldown ~8%).
///
/// Two modes:
///  · `reorder: true` — songs are ASSIGNED to arc slots by BPM fit (climbs get the slow songs,
///    the sprint anthem gets the high-energy tempo), then played in arc order.
///  · `reorder: false` — the playlist's own order is respected; arc roles map onto it 1:1.
public struct ClassPlanner: Sendable {
    public init() {}

    /// Preferred BPM per role — used only for reorder-mode fitting (distance scoring).
    static let roleTargetBPM: [SongRole: Double] = [
        .warmup: 95, .jumps: 126, .run: 122, .climb: 105,
        .sprint: 127, .recovery: 105, .arms: 118, .cooldown: 90,
    ]

    // MARK: Arc templates

    /// The role sequence for a class of `count` songs. Anchors: warm-up first, cooldown last,
    /// jumps second (early blood-pumper), arms third-from-last, biggest sprint second-from-last.
    public func arc(count: Int) -> [SongRole] {
        precondition(count >= 2)
        if count == 2 { return [.warmup, .cooldown] }
        if count == 3 { return [.warmup, .sprint, .cooldown] }
        if count == 4 { return [.warmup, .jumps, .sprint, .cooldown] }
        if count == 5 { return [.warmup, .jumps, .climb, .sprint, .cooldown] }

        var roles: [SongRole] = [.warmup, .jumps]
        // Middle fill: run → climb → sprint → recovery waves until the final three slots.
        let middleCount = count - 5     // minus warmup, jumps, arms, final sprint, cooldown
        let wave: [SongRole] = [.run, .climb, .sprint, .recovery]
        for i in 0..<middleCount { roles.append(wave[i % wave.count]) }
        roles.append(.arms)
        roles.append(.sprint)
        roles.append(.cooldown)
        return roles
    }

    // MARK: Planning

    public func plan(songs: [ClassSong], format: ClassFormat, reorder: Bool) -> ClassPlan {
        guard songs.count >= 2 else {
            let fallback = songs.map { PlannedSong(song: $0, role: .run) }
            return ClassPlan(format: format, songs: fallback, reordered: false)
        }

        // How many songs fit the duration? Use the actual average length of the provided songs.
        let avgLength = max(songs.map { $0.durationSeconds }.reduce(0, +) / Double(songs.count), 120)
        let targetCount = min(max(Int((Double(format.minutes) * 60 / avgLength).rounded()), 2), songs.count)
        let roles = arc(count: targetCount)

        if !reorder {
            // Respect playlist order: first N songs, roles mapped 1:1.
            let chosen = Array(songs.prefix(targetCount))
            return ClassPlan(format: format,
                             songs: zip(chosen, roles).map { PlannedSong(song: $0, role: $1) },
                             reordered: false)
        }

        // Reorder mode: fill the most BPM-constrained slots first so they get the best-fitting songs.
        let assignmentOrder: [SongRole] = [.climb, .warmup, .cooldown, .sprint, .jumps,
                                           .arms, .run, .recovery]
        var remaining = songs
        var assignment: [Int: ClassSong] = [:]   // arc index → song

        for role in assignmentOrder {
            let slots = roles.indices.filter { roles[$0] == role && assignment[$0] == nil }
            for slot in slots {
                guard !remaining.isEmpty else { break }
                let target = Self.roleTargetBPM[role] ?? 120
                let best = remaining.min(by: { fitScore($0, target) < fitScore($1, target) })!
                assignment[slot] = best
                remaining.removeAll { $0.trackKey == best.trackKey }
            }
        }

        let planned = roles.indices.compactMap { index -> PlannedSong? in
            assignment[index].map { PlannedSong(song: $0, role: roles[index]) }
        }
        return ClassPlan(format: format, songs: planned, reordered: true)
    }

    /// Lower = better fit. Songs with unknown BPM are treated as mid-tempo and slightly penalized,
    /// so known-BPM songs win the constrained slots.
    private func fitScore(_ song: ClassSong, _ targetBPM: Double) -> Double {
        guard let bpm = song.bpm else { return abs(120 - targetBPM) + 15 }
        return abs(bpm - targetBPM)
    }
}
