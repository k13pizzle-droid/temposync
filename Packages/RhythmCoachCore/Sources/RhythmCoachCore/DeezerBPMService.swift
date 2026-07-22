import Foundation

/// Deezer public-API tempo lookup — no key required, popularity-ranked search, exact artist
/// filtering. Two requests: search → track detail (which carries `bpm`). A `bpm` of 0 means
/// "not analyzed" and is treated as a miss so the waterfall can try the next source.
public struct DeezerBPMService: BPMLookupService {
    private let session: URLSession

    public init(session: URLSession = BPMLookupSession.tuned) {
        self.session = session
    }

    public func lookupBPM(title: String, artist: String) async throws -> Double? {
        // 1. Search, artist+track scoped (Deezer ranks by popularity — first good hit wins).
        var search = URLComponents(string: "https://api.deezer.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: "artist:\"\(artist)\" track:\"\(title)\"")]
        guard let searchURL = search.url else { return nil }
        let (searchData, _) = try await session.data(from: searchURL)
        guard let trackID = Self.parseFirstMatchingTrackID(from: searchData, title: title, artist: artist)
        else { return nil }

        // 2. Track detail carries the tempo.
        guard let trackURL = URL(string: "https://api.deezer.com/track/\(trackID)") else { return nil }
        let (trackData, _) = try await session.data(from: trackURL)
        return Self.parseBPM(fromTrackDetail: trackData)
    }

    /// First search hit whose artist overlaps the query (guards against title-only collisions).
    public static func parseFirstMatchingTrackID(from data: Data, title: String, artist: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["data"] as? [[String: Any]] else { return nil }
        let queryArtistWords = Set(TrackTempoResolver.normalize(artist).split(separator: " "))
        for entry in results {
            guard let id = entry["id"] as? Int else { continue }
            let entryArtist = ((entry["artist"] as? [String: Any])?["name"] as? String) ?? ""
            let entryWords = Set(TrackTempoResolver.normalize(entryArtist).split(separator: " "))
            if queryArtistWords.isEmpty || !entryWords.isDisjoint(with: queryArtistWords) {
                return id
            }
        }
        return nil
    }

    public static func parseBPM(fromTrackDetail data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let bpm = (root["bpm"] as? Double) ?? (root["bpm"] as? NSNumber)?.doubleValue ?? 0
        return bpm > 0 ? bpm : nil     // 0 = "not analyzed" → miss, let the next rung try
    }
}
