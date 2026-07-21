import Foundation

/// A real song used as a scoring fixture (spec open question 3). `referenceBPM` is ground truth from
/// the BPM Resolver's primary source (GetSongBPM / Tunebat); `nil` means the track is unresolved and
/// the resolver would fall back to BeatKit's on-device estimate. The Camelot code feeds RunSync's
/// harmonic ranking (spec §A / v1 §7.4) — so this manifest also seeds the shared `TrackTempo` cache.
public struct TrackReference: Sendable, Hashable, Codable {
    public let artist: String
    public let title: String
    /// Basename of the audio file to look for during offline scoring: `<slug>.wav`.
    public let slug: String
    /// Ground-truth tempo, or nil if unresolved (resolver falls back to on-device estimation).
    public let referenceBPM: Double?
    public let key: String?
    public let camelot: String?
    public let source: String

    public init(artist: String, title: String, slug: String, referenceBPM: Double?,
                key: String?, camelot: String?, source: String) {
        self.artist = artist
        self.title = title
        self.slug = slug
        self.referenceBPM = referenceBPM
        self.key = key
        self.camelot = camelot
        self.source = source
    }
}

public enum RealTrackFixtures {

    /// Kevin's first 10-track spin-playlist fixture set (open question 3). BPM/key confirmed from
    /// GetSongBPM / Tunebat / SongBPM, July 2026, unless marked unresolved.
    public static let spinSetOne: [TrackReference] = [
        TrackReference(artist: "Audien, Cate Downey", title: "Wish It Was You", slug: "audien-wish-it-was-you",
                       referenceBPM: 125, key: "E major", camelot: "12B",
                       source: "Tunebat/Beatport (Nils Hoffmann remix is 123)"),
        TrackReference(artist: "SOFI TUKKER", title: "COOK", slug: "sofi-tukker-cook",
                       referenceBPM: 108, key: "B minor", camelot: "10A", source: "Tunebat"),
        TrackReference(artist: "Anyma", title: "Bad Angel", slug: "anyma-bad-angel",
                       referenceBPM: 128, key: "C minor", camelot: "5A", source: "Tunebat"),
        TrackReference(artist: "Disco Lines, Tinashe", title: "No Broke Boys", slug: "disco-lines-no-broke-boys",
                       referenceBPM: 131, key: "C#/Db minor", camelot: "12A", source: "SongBPM/Tunebat"),
        TrackReference(artist: "ILLENIUM", title: "Love is a Chemical", slug: "illenium-love-is-a-chemical",
                       referenceBPM: 128, key: "Eb major", camelot: "5B", source: "Beatport/SongBPM"),
        TrackReference(artist: "Vicetone", title: "Something Strange", slug: "vicetone-something-strange",
                       referenceBPM: 119, key: "E major", camelot: "12B", source: "SongBPM/Tunebat"),
        TrackReference(artist: "Alesso vs OneRepublic", title: "If I Lose Myself", slug: "alesso-if-i-lose-myself",
                       referenceBPM: 126, key: "D major", camelot: "10B",
                       source: "Tunebat (some sources 125)"),
        TrackReference(artist: "Nadia Ali, Starkillers, Alex Kenji, Alesso", title: "Pressure - Alesso Remix",
                       slug: "pressure-alesso-remix",
                       referenceBPM: 128, key: "Bb minor", camelot: "3A", source: "Tunebat"),
        TrackReference(artist: "Alesso", title: "Calling (Lose My Mind)", slug: "alesso-calling-lose-my-mind",
                       referenceBPM: 125, key: "C# minor", camelot: "12A",
                       source: "Tunebat radio edit (original in E major)"),
        TrackReference(artist: "Avicii", title: "Levels", slug: "avicii-levels",
                       referenceBPM: 126, key: "C#/Db minor", camelot: "12A", source: "Tunebat/SongBPM"),
    ]
}
