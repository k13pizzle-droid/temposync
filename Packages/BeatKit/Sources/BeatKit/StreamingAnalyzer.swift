import Foundation

/// Incremental full-song analysis for calibration rides (spec §B3 learning loop).
///
/// Feed mic chunks as they arrive; it maintains the spectral-flux onset envelope and the RMS energy
/// curve incrementally — raw audio is never kept (privacy stance + a 4-minute song reduces to ~20k
/// envelope floats instead of ~10M samples). At song end, `finalize()` runs the standard offline
/// pipeline (tempo → beat grid → section boundaries) over the accumulated envelopes.
///
/// Not thread-safe: feed from one actor/queue.
public final class StreamingAnalyzer {
    public let sampleRate: Double
    private let frameSize = 1024
    private let hopSize = 512

    private let window: [Float]
    private let fft: FFTProcessor
    private var previousMags: [Float]?
    private var pending: [Float] = []
    private var flux: [Float] = []

    // RMS energy, one value per 0.25 s window (matches SectionDetector's default).
    private let energyWindowSamples: Int
    private var energyAccumulator: Double = 0
    private var energySampleCount = 0
    private var energy: [Double] = []

    private var totalSamples = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.window = hannWindow(frameSize)
        self.fft = FFTProcessor(n: frameSize)
        self.energyWindowSamples = max(1, Int(0.25 * sampleRate))
    }

    public var durationSeconds: Double { Double(totalSamples) / sampleRate }

    // MARK: Feed

    public func feed(_ samples: [Float]) {
        totalSamples += samples.count

        // Energy curve.
        for s in samples {
            energyAccumulator += Double(s) * Double(s)
            energySampleCount += 1
            if energySampleCount == energyWindowSamples {
                energy.append((energyAccumulator / Double(energyWindowSamples)).squareRoot())
                energyAccumulator = 0
                energySampleCount = 0
            }
        }

        // Onset flux, frame by frame with hop continuity across chunk boundaries.
        pending.append(contentsOf: samples)
        var frame = [Float](repeating: 0, count: frameSize)
        while pending.count >= frameSize {
            for i in 0..<frameSize { frame[i] = pending[i] * window[i] }
            let mags = fft.magnitudes(frame)
            if let previous = previousMags {
                var sum: Float = 0
                for i in 0..<mags.count {
                    let diff = mags[i] - previous[i]
                    if diff > 0 { sum += diff }
                }
                flux.append(sum)
            } else {
                flux.append(0)
            }
            previousMags = mags
            pending.removeFirst(hopSize)
        }
    }

    // MARK: Finalize

    public struct Result {
        public let analysis: BeatAnalysis
        public let energy: [Double]
        public let energyFrameRate: Double
        public let durationSeconds: Double
    }

    /// Run the standard pipeline over everything heard so far. `knownBPM` (resolver) snaps octave.
    public func finalize(knownBPM: Double? = nil) -> Result {
        let frameRate = sampleRate / Double(hopSize)
        // Mean-subtract + rectify, same normalization the offline OnsetDetector applies.
        let mean = flux.isEmpty ? 0 : flux.reduce(0, +) / Float(flux.count)
        let envelope = OnsetEnvelope(values: flux.map { max($0 - mean, 0) }, frameRate: frameRate)

        let tempo = TempoEstimator().estimate(envelope, knownBPM: knownBPM)
        let grid = BeatTracker().track(envelope, bpm: tempo.bpm)
        let energyRate = sampleRate / Double(energyWindowSamples)
        let sections = SectionDetector().boundaries(energy: energy, frameRate: energyRate, beatGrid: grid)

        return Result(
            analysis: BeatAnalysis(tempo: tempo, grid: grid, sections: sections, onsetFrameRate: frameRate),
            energy: energy,
            energyFrameRate: energyRate,
            durationSeconds: durationSeconds
        )
    }
}
