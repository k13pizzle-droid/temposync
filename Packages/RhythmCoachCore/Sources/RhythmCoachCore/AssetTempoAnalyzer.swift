import Foundation
#if canImport(AVFoundation)
import AVFoundation
import BeatKit

/// In-house tempo analysis of an audio FILE (no mic, no network): decode via AVAudioFile, stream
/// through BeatKit's analyzer, return tempo + confidence. This is the resolver rung that removes
/// the dependency on third-party BPM APIs for any track the library exposes an asset for
/// (downloaded / purchased / DRM-free — Apple-Music-streamed tracks have no readable asset and
/// still fall back to the network rungs or a calibration ride).
public enum AssetTempoAnalyzer {

    public struct Result: Sendable {
        public let bpm: Double
        public let strength: Double
    }

    /// Analyze up to `secondsLimit` of the file (90 s is plenty for a stable tempo lock and keeps
    /// a full playlist scan fast). Runs off the main actor.
    public static func analyze(url: URL, secondsLimit: Double = 90) async throws -> Result? {
        try await Task.detached(priority: .utility) {
            try analyzeSync(url: url, secondsLimit: secondsLimit)
        }.value
    }

    /// FULL-song analysis: the complete streamed result (tempo + beat grid + section boundaries +
    /// energy curve) from the track's own audio — everything a learned SectionMap needs, with no
    /// microphone and no network. This makes the calibration ride necessary only for streamed-only
    /// tracks. Runs off the main actor; a 4-minute song takes a few seconds.
    public static func analyzeStructure(url: URL) async throws -> StreamingAnalyzer.Result? {
        try await Task.detached(priority: .utility) {
            try structureSync(url: url)
        }.value
    }

    static func structureSync(url: URL) throws -> StreamingAnalyzer.Result? {
        guard let result = try stream(url: url, secondsLimit: nil),
              result.analysis.tempo.bpm > 60 else { return nil }
        return result
    }

    static func analyzeSync(url: URL, secondsLimit: Double) throws -> Result? {
        guard let result = try stream(url: url, secondsLimit: secondsLimit),
              result.analysis.tempo.bpm > 60, result.analysis.tempo.strength > 0 else { return nil }
        return Result(bpm: result.analysis.tempo.bpm, strength: result.analysis.tempo.strength)
    }

    /// One decode-downmix-feed loop for both entry points (they used to be ~90% duplicated).
    /// The downmix buffer is allocated once for the whole file, not per chunk.
    private static func stream(url: URL, secondsLimit: Double?) throws -> StreamingAnalyzer.Result? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        guard sampleRate > 0, channels > 0 else { return nil }

        let analyzer = StreamingAnalyzer(sampleRate: sampleRate)
        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
        let endFrame = secondsLimit.map { min(file.length, AVAudioFramePosition($0 * sampleRate)) }
            ?? file.length

        var mono = [Float](repeating: 0, count: Int(chunk))
        while file.framePosition < endFrame {
            try file.read(into: buffer, frameCount: chunk)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channelData = buffer.floatChannelData else { break }
            let first = channelData[0]
            for i in 0..<frames { mono[i] = first[i] }
            if channels > 1 {
                for channel in 1..<channels {
                    let data = channelData[channel]
                    for i in 0..<frames { mono[i] += data[i] }
                }
                let scale = 1.0 / Float(channels)
                for i in 0..<frames { mono[i] *= scale }
            }
            // Full chunks feed the reused buffer directly (feed copies values, keeps no reference);
            // only the final partial chunk pays for a slice copy.
            if frames == mono.count {
                analyzer.feed(mono)
            } else {
                analyzer.feed(Array(mono[0..<frames]))
            }
        }
        return analyzer.finalize()
    }
}
#endif
