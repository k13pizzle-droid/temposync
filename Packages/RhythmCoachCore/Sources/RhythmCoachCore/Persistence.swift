import Foundation
import SwiftData
import RoutineKit

/// Shared BPM/key cache (spec Data Models: `TrackTempo`). Seeded from the resolver / RealTrackFixtures.
@Model
public final class TrackTempoRecord {
    @Attribute(.unique) public var trackKey: String
    public var artist: String
    public var title: String
    public var bpm: Double
    public var key: String?
    public var camelot: String?
    public var source: String
    public var updatedAt: Date

    public init(trackKey: String, artist: String, title: String, bpm: Double,
                key: String? = nil, camelot: String? = nil, source: String = "", updatedAt: Date = .now) {
        self.trackKey = trackKey
        self.artist = artist
        self.title = title
        self.bpm = bpm
        self.key = key
        self.camelot = camelot
        self.source = source
        self.updatedAt = updatedAt
    }
}

/// Per-track learned structure (spec Data Models: `SectionMap`). Written after each Mode S ride,
/// consumed at full fidelity by later Mode H sessions.
@Model
public final class SectionMapRecord {
    @Attribute(.unique) public var trackKey: String
    public var bpm: Double
    public var beatGridOffset: Double
    /// Codable value type stored by SwiftData.
    public var sections: [Section]
    public var captureQuality: Double
    public var capturedAt: Date

    public init(trackKey: String, bpm: Double, beatGridOffset: Double,
                sections: [Section], captureQuality: Double, capturedAt: Date = .now) {
        self.trackKey = trackKey
        self.bpm = bpm
        self.beatGridOffset = beatGridOffset
        self.sections = sections
        self.captureQuality = captureQuality
        self.capturedAt = capturedAt
    }

    public convenience init(_ map: CapturedMap, capturedAt: Date = .now) {
        self.init(trackKey: map.trackKey, bpm: map.bpm, beatGridOffset: map.beatGridOffset,
                  sections: map.sections, captureQuality: map.captureQuality, capturedAt: capturedAt)
    }

    public var asCapturedMap: CapturedMap {
        CapturedMap(trackKey: trackKey, bpm: bpm, beatGridOffset: beatGridOffset,
                    sections: sections, captureQuality: captureQuality)
    }
}

/// One completed ride session (Mode H / class). Logged automatically when a session over 2 minutes
/// ends — the seed of ride history ("you've ridden this class 4×").
@Model
public final class RideLogRecord {
    public var startedAt: Date
    public var durationMinutes: Double
    public var songsPlayed: Int
    /// Class format minutes if this was a built class (nil = freestyle ride).
    public var formatMinutes: Int?
    public var reordered: Bool?

    public init(startedAt: Date, durationMinutes: Double, songsPlayed: Int,
                formatMinutes: Int? = nil, reordered: Bool? = nil) {
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.songsPlayed = songsPlayed
        self.formatMinutes = formatMinutes
        self.reordered = reordered
    }
}

/// One song inside a saved class (Codable payload for `SavedClassRecord`).
public struct SavedClassSong: Codable, Sendable {
    public let trackKey: String
    public let title: String
    public let artist: String
    public let durationSeconds: Double
    public let bpm: Double?
    public let role: String

    public init(_ planned: PlannedSong) {
        self.trackKey = planned.song.trackKey
        self.title = planned.song.title
        self.artist = planned.song.artist
        self.durationSeconds = planned.song.durationSeconds
        self.bpm = planned.song.bpm
        self.role = planned.role.rawValue
    }

    public var asPlanned: PlannedSong {
        PlannedSong(
            song: ClassSong(trackKey: trackKey, title: title, artist: artist,
                            durationSeconds: durationSeconds, bpm: bpm),
            role: SongRole(rawValue: role) ?? .run
        )
    }
}

/// A named, re-rideable class. Same songs + same roles + same seeds = the identical class every
/// time — which is the point: rides become learnable, like a real studio class.
@Model
public final class SavedClassRecord {
    @Attribute(.unique) public var name: String
    public var createdAt: Date
    public var formatMinutes: Int
    public var reordered: Bool
    public var songsData: Data

    public init(name: String, createdAt: Date, formatMinutes: Int, reordered: Bool, songsData: Data) {
        self.name = name
        self.createdAt = createdAt
        self.formatMinutes = formatMinutes
        self.reordered = reordered
        self.songsData = songsData
    }

    public convenience init(name: String, plan: ClassPlan) throws {
        let data = try JSONEncoder().encode(plan.songs.map(SavedClassSong.init))
        self.init(name: name, createdAt: .now, formatMinutes: plan.format.minutes,
                  reordered: plan.reordered, songsData: data)
    }

    /// Decode memo — `songsData` never mutates after creation (records are replaced wholesale),
    /// and List rows read `songCount`/`decodedSongs()` on every render.
    @Transient private var cachedSongs: [SavedClassSong]? = nil

    public var songCount: Int { (try? decodedSongs().count) ?? 0 }

    public func decodedSongs() throws -> [SavedClassSong] {
        if let cachedSongs { return cachedSongs }
        let songs = try JSONDecoder().decode([SavedClassSong].self, from: songsData)
        cachedSongs = songs
        return songs
    }

    public func plan() throws -> ClassPlan {
        ClassPlan(format: ClassFormat(rawValue: formatMinutes) ?? .thirty,
                  songs: try decodedSongs().map { $0.asPlanned },
                  reordered: reordered)
    }
}

/// Thin persistence helpers over a SwiftData `ModelContext`. `@MainActor` because `ModelContext` is
/// main-actor bound in app use; tests drive it on the main actor with an in-memory container.
@MainActor
public enum SectionMapStore {

    public static let schema = Schema([TrackTempoRecord.self, SectionMapRecord.self,
                                       RideLogRecord.self, SavedClassRecord.self])

    /// In-memory container for tests / previews.
    public static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: schema,
                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    /// Upsert a captured map, keeping the higher-quality capture (spec §B3: "average/replace on
    /// higher-quality capture").
    public static func upsert(_ map: CapturedMap, in context: ModelContext) throws {
        let key = map.trackKey
        let existing = try context.fetch(
            FetchDescriptor<SectionMapRecord>(predicate: #Predicate { $0.trackKey == key })
        ).first
        if let existing {
            if map.captureQuality >= existing.captureQuality {
                existing.bpm = map.bpm
                existing.beatGridOffset = map.beatGridOffset
                existing.sections = map.sections
                existing.captureQuality = map.captureQuality
                existing.capturedAt = .now
            }
        } else {
            context.insert(SectionMapRecord(map))
        }
        try context.save()
    }

    public static func map(for trackKey: String, in context: ModelContext) throws -> CapturedMap? {
        try context.fetch(
            FetchDescriptor<SectionMapRecord>(predicate: #Predicate { $0.trackKey == trackKey })
        ).first?.asCapturedMap
    }

    /// Every learned map, keyed by track — one fetch for screens that need per-song lookups
    /// (class plan fitting, storyboards, pickers), instead of a store round-trip per song.
    public static func allMaps(in context: ModelContext) throws -> [String: CapturedMap] {
        let records = try context.fetch(FetchDescriptor<SectionMapRecord>())
        return Dictionary(uniqueKeysWithValues: records.map { ($0.trackKey, $0.asCapturedMap) })
    }
}
