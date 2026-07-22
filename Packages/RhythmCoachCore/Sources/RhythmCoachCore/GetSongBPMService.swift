import Foundation

/// A remote tempo-lookup service (the BPM Resolver's network rung).
public protocol BPMLookupService: Sendable {
    /// Returns the track's BPM, or nil if the service doesn't know it. Throws on transport errors.
    func lookupBPM(title: String, artist: String) async throws -> Double?
}

/// Short-timeout session shared by the tempo services: a dead network must degrade to "BPM est."
/// in seconds — the URLSession default of 60 s per request could hold a mid-ride track change
/// hostage for minutes across the service chain.
public enum BPMLookupSession {
    public static let tuned: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()
}

/// GetSongBPM.com client — the waterfall's LAST network rung (Deezer runs first; live probing
/// showed GetSongBPM's search ranks obscure covers above popular originals).
///
/// Requires a free API key from https://getsongbpm.com/api. Their terms require attribution with a
/// backlink to getsongbpm.com in any app using the data — the Settings screen carries it.
public struct GetSongBPMService: BPMLookupService {
    public let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = BPMLookupSession.tuned) {
        self.apiKey = apiKey
        self.session = session
    }

    public func lookupBPM(title: String, artist: String) async throws -> Double? {
        var components = URLComponents(string: "https://api.getsong.co/search/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "type", value: "both"),
            URLQueryItem(name: "lookup", value: "song:\(title) artist:\(artist)"),
        ]
        guard let url = components.url else { return nil }
        let (data, _) = try await session.data(from: url)
        return Self.parseBPM(from: data, title: title, artist: artist)
    }

    /// Parse the search response and pick the best title/artist match. STRICT: if no entry matches
    /// the artist, returns nil — live probing showed their search ranks obscure covers first (e.g.
    /// "Levels" → Nonpoint at 100 BPM before any Avicii result), so a first-result fallback would
    /// hand back confidently wrong tempos. A miss is honest; a wrong lock is not.
    /// Static + synchronous so it unit-tests without a network.
    public static func parseBPM(from data: Data, title: String, artist: String) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Error shape: {"search": {"error": "..."}} — array shape is the success case.
        guard let results = root["search"] as? [[String: Any]], !results.isEmpty else { return nil }

        struct Candidate { let bpm: Double; let title: String; let artist: String }
        let candidates: [Candidate] = results.compactMap { entry in
            guard let tempoString = entry["tempo"] as? String ?? (entry["tempo"] as? NSNumber)?.stringValue,
                  let bpm = Double(tempoString), bpm > 0 else { return nil }
            let entryTitle = (entry["title"] as? String) ?? (entry["song_title"] as? String) ?? ""
            let entryArtist = ((entry["artist"] as? [String: Any])?["name"] as? String) ?? ""
            return Candidate(bpm: bpm, title: entryTitle, artist: entryArtist)
        }
        guard !candidates.isEmpty else { return nil }

        let nTitle = TrackTempoResolver.normalize(title)
        let artistWords = Set(TrackTempoResolver.normalize(artist).split(separator: " "))
        return candidates.first(where: { candidate in
            let cTitle = TrackTempoResolver.normalize(candidate.title)
            let titleHit = cTitle == nTitle || cTitle.contains(nTitle) || nTitle.contains(cTitle)
            guard titleHit else { return false }
            let cWords = Set(TrackTempoResolver.normalize(candidate.artist).split(separator: " "))
            return artistWords.isEmpty || !cWords.isDisjoint(with: artistWords)
        })?.bpm
    }
}
