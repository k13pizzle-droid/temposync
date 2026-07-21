import Foundation

/// The onset-strength envelope: one value per STFT hop, high where energy rises across the spectrum.
/// This is the input to both tempo estimation and beat-phase locking (spec §B3 Mode S).
public struct OnsetEnvelope: Sendable {
    public let values: [Float]
    /// Frames per second of the envelope (= sampleRate / hopSize).
    public let frameRate: Double

    public func timeForFrame(_ frame: Int) -> Double { Double(frame) / frameRate }
}

/// Spectral-flux onset detector. Half-wave-rectified sum of positive magnitude changes between
/// consecutive frames, then mean-subtracted so the envelope oscillates around zero.
public struct OnsetDetector: Sendable {
    public let frameSize: Int
    public let hopSize: Int

    public init(frameSize: Int = 1024, hopSize: Int = 512) {
        self.frameSize = frameSize
        self.hopSize = hopSize
    }

    public func onsetEnvelope(_ buffer: AudioBuffer) -> OnsetEnvelope {
        let samples = buffer.samples
        let frameRate = buffer.sampleRate / Double(hopSize)
        guard samples.count >= frameSize else {
            return OnsetEnvelope(values: [], frameRate: frameRate)
        }

        let window = hannWindow(frameSize)
        let fft = FFTProcessor(n: frameSize)
        let bins = frameSize / 2

        var previous = [Float](repeating: 0, count: bins)
        var flux: [Float] = []
        flux.reserveCapacity(samples.count / hopSize)

        var frame = [Float](repeating: 0, count: frameSize)
        var pos = 0
        while pos + frameSize <= samples.count {
            for i in 0..<frameSize { frame[i] = samples[pos + i] * window[i] }
            let mags = fft.magnitudes(frame)
            var sum: Float = 0
            for i in 0..<bins {
                let diff = mags[i] - previous[i]
                if diff > 0 { sum += diff }
            }
            flux.append(sum)
            previous = mags
            pos += hopSize
        }

        // Mean-subtract and half-wave-rectify so autocorrelation keys on the periodic peaks.
        let mean = flux.isEmpty ? 0 : flux.reduce(0, +) / Float(flux.count)
        let normalized = flux.map { max($0 - mean, 0) }
        return OnsetEnvelope(values: normalized, frameRate: frameRate)
    }
}
