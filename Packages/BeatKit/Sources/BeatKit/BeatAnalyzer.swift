import Foundation

/// The full offline result for a track: tempo, beat grid, and section boundaries.
public struct BeatAnalysis: Sendable {
    public let tempo: TempoEstimate
    public let grid: BeatGrid
    public let sections: [SectionBoundary]
    public let onsetFrameRate: Double
}

/// Top-level offline pipeline (the kickoff-prompt spike): buffer → onset envelope → tempo → beat
/// grid → sections. `knownBPM` (from the GetSongBPM cache) disambiguates half/double when available.
public struct BeatAnalyzer: Sendable {
    public let onsetDetector: OnsetDetector
    public let tempoEstimator: TempoEstimator
    public let beatTracker: BeatTracker
    public let sectionDetector: SectionDetector

    public init(onsetDetector: OnsetDetector = OnsetDetector(),
                tempoEstimator: TempoEstimator = TempoEstimator(),
                beatTracker: BeatTracker = BeatTracker(),
                sectionDetector: SectionDetector = SectionDetector()) {
        self.onsetDetector = onsetDetector
        self.tempoEstimator = tempoEstimator
        self.beatTracker = beatTracker
        self.sectionDetector = sectionDetector
    }

    public func analyze(_ buffer: AudioBuffer, knownBPM: Double? = nil) -> BeatAnalysis {
        let envelope = onsetDetector.onsetEnvelope(buffer)
        let tempo = tempoEstimator.estimate(envelope, knownBPM: knownBPM)
        let grid = beatTracker.track(envelope, bpm: tempo.bpm)
        let sections = sectionDetector.detect(buffer, beatGrid: grid)
        return BeatAnalysis(tempo: tempo, grid: grid, sections: sections, onsetFrameRate: envelope.frameRate)
    }

    /// Convenience: analyze a WAV file on disk.
    public func analyzeWAV(at url: URL, knownBPM: Double? = nil) throws -> BeatAnalysis {
        let buffer = try WAVFile.read(url)
        return analyze(buffer, knownBPM: knownBPM)
    }
}
