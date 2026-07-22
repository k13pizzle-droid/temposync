import Foundation
import SwiftData
import RoutineKit
import RhythmCoachCore

/// App-wide singletons: the SwiftData container backing the TrackTempo cache (+ future SectionMaps),
/// and the BPM waterfall built from the user's GetSongBPM key (Settings).
@MainActor
enum AppServices {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: SectionMapStore.schema)
        } catch {
            // Never brick the app over a cache store — fall back to in-memory.
            return try! ModelContainer(
                for: SectionMapStore.schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        }
    }()

    static var context: ModelContext { container.mainContext }

    /// Shared library access for cross-screen lookups (asset URLs, artwork). ONE provider for the
    /// whole app — per-screen factories each re-ran a full library query and kept isolated item
    /// caches. While the choice is stuck on the fixture provider (permission not yet granted, or
    /// library empty at first touch), the next access retries the real library once more.
    static var sharedProvider: PlaylistProvider {
        if let provider = _provider, !(provider is PreviewPlaylistProvider) { return provider }
        let fresh = makePlaylistProvider()
        if _provider == nil || !(fresh is PreviewPlaylistProvider) { _provider = fresh }
        return _provider!
    }
    private static var _provider: PlaylistProvider?

    /// IN-HOUSE tempo rung: analyze the track's own audio file with BeatKit (no mic, no network).
    /// Works for downloaded/purchased/DRM-free items; streamed-only tracks return nil and fall
    /// through to the network rungs. Successful results are cached forever.
    static func onDeviceBPM(trackKey: String, title: String, artist: String) async -> Double? {
        guard let url = sharedProvider.assetURL(for: trackKey) else { return nil }
        guard let analyzed = (try? await AssetTempoAnalyzer.analyze(url: url)) ?? nil,
              analyzed.strength >= 0.03 else { return nil }
        makeBPMWaterfall().store(bpm: analyzed.bpm, title: title, artist: artist, source: "on-device")
        return analyzed.bpm
    }

    /// IN-HOUSE full learn: analyze the WHOLE file → BPM + a learned SectionMap (real chorus
    /// timing) stored under the track's key — the calibration ride, without the microphone.
    /// Returns the BPM on success. Streamed-only tracks return nil.
    static func onDeviceLearn(trackKey: String, title: String, artist: String) async -> Double? {
        guard let url = sharedProvider.assetURL(for: trackKey) else { return nil }
        guard let result = (try? await AssetTempoAnalyzer.analyzeStructure(url: url)) ?? nil,
              result.analysis.tempo.strength >= 0.03 else { return nil }
        let bpm = result.analysis.tempo.bpm
        makeBPMWaterfall().store(bpm: bpm, title: title, artist: artist, source: "on-device")
        let map = SectionCapture().capture(trackKey: trackKey, streamed: result)
        try? SectionMapStore.upsert(map, in: context)
        return bpm
    }

    /// True when a learned SectionMap exists for the track (real chorus timing available).
    static func hasLearnedMap(_ trackKey: String) -> Bool {
        (try? SectionMapStore.map(for: trackKey, in: context)) != nil
    }

    /// Duration-weighted mean energy from a learned map; nil when the track has no map.
    static func learnedEnergy(_ trackKey: String) -> Double? {
        guard let map = try? SectionMapStore.map(for: trackKey, in: context) else { return nil }
        return Self.energy(of: map)
    }

    /// Learned-map energy for EVERY learned track in one fetch — plan rebuilds and pickers used to
    /// round-trip the store twice per song per rebuild.
    static func learnedEnergyIndex() -> [String: Double] {
        ((try? SectionMapStore.allMaps(in: context)) ?? [:]).compactMapValues(Self.energy(of:))
    }

    private static func energy(of map: CapturedMap) -> Double? {
        guard !map.sections.isEmpty else { return nil }
        let totalCounts = map.sections.reduce(0) { $0 + $1.counts }
        guard totalCounts > 0 else { return nil }
        let weighted = map.sections.reduce(0.0) { $0 + $1.energy * Double($1.counts) }
        return weighted / Double(totalCounts)
    }

    /// The class currently being ridden (nil = freestyle). Set by ClassSetupView on start; the live
    /// view model reads per-track roles from it and clears it when the session ends.
    static var activeClassPlan: ClassPlan?

    static let apiKeyDefaultsKey = "getsongbpm_api_key"

    /// Per-class difficulty override (set by the class setup dial for the active ride; cleared on stop).
    static var difficultyOverride: ClassDifficulty?

    /// The effective difficulty: the active class's dial, else the Settings default.
    static var difficulty: ClassDifficulty {
        difficultyOverride
            ?? ClassDifficulty(rawValue: UserDefaults.standard.object(forKey: ClassDifficulty.defaultsKey) == nil
                               ? 2 : UserDefaults.standard.integer(forKey: ClassDifficulty.defaultsKey))
            ?? .medium
    }

    /// One dial drives both knobs the generator takes.
    static var effort: IntensityDial { difficulty.intensity }
    static var skill: SkillTier { difficulty.skill }

    /// Waterfall: SwiftData cache → seeded fixture table → Deezer (no key, popularity-ranked
    /// search) → GetSongBPM (different coverage). GetSongBPM key precedence: Settings override →
    /// the app's built-in key (Secrets.swift, gitignored).
    static func makeBPMWaterfall() -> BPMWaterfall {
        let override = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = override.isEmpty ? Secrets.defaultGetSongBPMKey : override
        var services: [BPMLookupService] = [DeezerBPMService()]
        if !key.isEmpty { services.append(GetSongBPMService(apiKey: key)) }
        return BPMWaterfall(services: services, context: context)
    }
}
