import Foundation

/// Mono PCM audio as normalized float samples in [-1, 1] plus a sample rate.
/// The common currency between the WAV loader, the fixture generator, and the DSP stages.
public struct AudioBuffer: Sendable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}
