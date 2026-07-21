import Foundation
import SwiftData

/// A resolved tempo and where it came from — the UI shows the source honestly
/// ("126 BPM" vs "BPM est.").
public struct ResolvedBPM: Sendable, Equatable {
    public let bpm: Double
    public let source: Source
    public enum Source: String, Sendable { case cache, seed, api }
}

/// The BPM Resolver waterfall (spec): SwiftData cache → seeded reference table → remote services in
/// order (Deezer first: popularity-ranked search, no key; then GetSongBPM: different coverage).
/// A successful remote hit is persisted to the cache, so each song hits the network at most once.
@MainActor
public final class BPMWaterfall {
    private let seed: TrackTempoResolver
    private let services: [BPMLookupService]
    private let context: ModelContext?

    public init(seed: TrackTempoResolver = TrackTempoResolver(),
                services: [BPMLookupService],
                context: ModelContext?) {
        self.seed = seed
        self.services = services
        self.context = context
    }

    /// Convenience for the single-service case (tests).
    public convenience init(seed: TrackTempoResolver = TrackTempoResolver(),
                            service: BPMLookupService?,
                            context: ModelContext?) {
        self.init(seed: seed, services: service.map { [$0] } ?? [], context: context)
    }

    public static func cacheKey(title: String, artist: String) -> String {
        "meta:\(TrackTempoResolver.normalize(title))|\(TrackTempoResolver.normalize(artist))"
    }

    /// Fast, synchronous rungs only (cache + seed) — what `resolve` checks before going async.
    public func resolveLocally(title: String, artist: String) -> ResolvedBPM? {
        if let context {
            let key = Self.cacheKey(title: title, artist: artist)
            if let record = try? context.fetch(
                FetchDescriptor<TrackTempoRecord>(predicate: #Predicate { $0.trackKey == key })
            ).first {
                return ResolvedBPM(bpm: record.bpm, source: .cache)
            }
        }
        if let ref = seed.lookup(title: title, artist: artist), let bpm = ref.referenceBPM {
            return ResolvedBPM(bpm: bpm, source: .seed)
        }
        return nil
    }

    /// Full waterfall. Each service is tried in order; failures and misses fall through. Network
    /// errors degrade to nil rather than throwing — the caller keeps its default-BPM routine and
    /// stays honest about it.
    public func resolve(title: String, artist: String) async -> ResolvedBPM? {
        if let local = resolveLocally(title: title, artist: artist) { return local }
        for service in services {
            guard let bpm = try? await service.lookupBPM(title: title, artist: artist), bpm > 0 else {
                continue
            }
            // Persist so this song never hits the network again.
            if let context {
                let record = TrackTempoRecord(
                    trackKey: Self.cacheKey(title: title, artist: artist),
                    artist: artist, title: title, bpm: bpm,
                    source: String(describing: type(of: service))
                )
                context.insert(record)
                try? context.save()
            }
            return ResolvedBPM(bpm: bpm, source: .api)
        }
        return nil
    }
}
