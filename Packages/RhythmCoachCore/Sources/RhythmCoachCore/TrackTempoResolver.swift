import Foundation
import BeatKit

/// Resolves a track's reference BPM from cached data (spec: BPM Resolver waterfall, first rung).
///
/// Mode H's whole problem is that Apple exposes *no* tempo data — so without this lookup it was
/// guessing 128 for everything, and the choreography only fit by luck. This resolves the now-playing
/// title/artist against the seeded reference table (Kevin's fixture set today; the full GetSongBPM
/// cache later). Miss → caller falls back to a default and labels the tempo as estimated.
public struct TrackTempoResolver: Sendable {
    private let entries: [TrackReference]

    public init(entries: [TrackReference] = RealTrackFixtures.spinSetOne) {
        self.entries = entries
    }

    /// Case/punctuation-insensitive match: title must match (either direction of containment, so
    /// "COOK" matches "COOK (feat. J Balvin)"), and artist must overlap at least one word.
    public func lookup(title: String, artist: String) -> TrackReference? {
        let nTitle = Self.normalize(title)
        let nArtist = Self.normalize(artist)
        guard !nTitle.isEmpty else { return nil }

        return entries.first { entry in
            guard entry.referenceBPM != nil else { return false }
            let eTitle = Self.normalize(entry.title)
            let titleHit = eTitle == nTitle || eTitle.contains(nTitle) || nTitle.contains(eTitle)
            guard titleHit else { return false }
            let eArtistWords = Set(Self.normalize(entry.artist).split(separator: " "))
            let artistWords = Set(nArtist.split(separator: " "))
            return nArtist.isEmpty || !eArtistWords.isDisjoint(with: artistWords)
        }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}
