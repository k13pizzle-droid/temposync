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

    /// A full-waterfall miss is remembered for this long — an unknown song used to re-fire every
    /// network rung on every ride, forever. Stale misses retry (catalogs grow).
    private static let missSource = "miss"
    private static let missTTL: TimeInterval = 7 * 24 * 60 * 60

    private func cachedRecord(title: String, artist: String) -> TrackTempoRecord? {
        guard let context else { return nil }
        let key = Self.cacheKey(title: title, artist: artist)
        return try? context.fetch(
            FetchDescriptor<TrackTempoRecord>(predicate: #Predicate { $0.trackKey == key })
        ).first
    }

    private func upsert(bpm: Double, title: String, artist: String, source: String) {
        guard let context else { return }
        if let existing = cachedRecord(title: title, artist: artist) {
            existing.bpm = bpm
            existing.source = source
            existing.updatedAt = .now
        } else {
            context.insert(TrackTempoRecord(trackKey: Self.cacheKey(title: title, artist: artist),
                                            artist: artist, title: title, bpm: bpm, source: source))
        }
        try? context.save()
    }

    /// Persist an externally obtained tempo (e.g. on-device asset analysis) so future lookups are
    /// cache hits.
    public func store(bpm: Double, title: String, artist: String, source: String) {
        guard bpm > 0 else { return }
        upsert(bpm: bpm, title: title, artist: artist, source: source)
    }

    /// Fast, synchronous rungs only (cache + seed) — what `resolve` checks before going async.
    /// Miss sentinels are not hits: the UI stays honest ("BPM est.").
    public func resolveLocally(title: String, artist: String) -> ResolvedBPM? {
        if let record = cachedRecord(title: title, artist: artist), record.bpm > 0 {
            return ResolvedBPM(bpm: record.bpm, source: .cache)
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
        if let record = cachedRecord(title: title, artist: artist), record.bpm > 0 {
            return ResolvedBPM(bpm: record.bpm, source: .cache)
        }
        // Seed BEFORE honoring a miss sentinel: an app update can ship seed rows for a track that
        // sentineled earlier, and the seed must win immediately (resolveLocally already does).
        if let ref = seed.lookup(title: title, artist: artist), let bpm = ref.referenceBPM {
            return ResolvedBPM(bpm: bpm, source: .seed)
        }
        if let record = cachedRecord(title: title, artist: artist),
           record.source == Self.missSource,
           Date.now.timeIntervalSince(record.updatedAt) < Self.missTTL {
            return nil    // known miss, still fresh — skip the network entirely
        }
        for service in services {
            guard let bpm = try? await service.lookupBPM(title: title, artist: artist), bpm > 0 else {
                continue
            }
            // Persist so this song never hits the network again (upsert: a stale miss sentinel or
            // a concurrent resolve for the same song must update, not double-insert).
            upsert(bpm: bpm, title: title, artist: artist,
                   source: String(describing: type(of: service)))
            return ResolvedBPM(bpm: bpm, source: .api)
        }
        // Every rung missed: remember that, with a TTL.
        if !services.isEmpty {
            upsert(bpm: 0, title: title, artist: artist, source: Self.missSource)
        }
        return nil
    }
}
