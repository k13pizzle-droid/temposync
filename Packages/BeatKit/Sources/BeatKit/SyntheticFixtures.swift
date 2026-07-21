import Foundation

/// Ground-truth-labeled synthetic audio for the scoring harness. Per the kickoff prompt, these come
/// *before* any real songs: click tracks at known BPM with a known energy jump, so tempo/phase/
/// section detection can be scored objectively.
public struct SyntheticFixture: Sendable {
    public let name: String
    public let buffer: AudioBuffer
    public let trueBPM: Double
    public let trueBeatTimes: [Double]
    /// Time of the energy jump (the one section boundary), if any.
    public let trueSectionBoundary: Double?
}

public enum SyntheticFixtures {

    /// A click track: a short decaying sine burst on every beat. The click amplitude steps up at
    /// `energyJumpAt` to create a detectable section boundary. Fully deterministic.
    public static func clickTrack(
        name: String,
        bpm: Double,
        durationSeconds: Double,
        sampleRate: Double = 44100,
        energyJumpAt: Double? = nil,
        quietGain: Float = 0.25,
        loudGain: Float = 0.9,
        clickFrequency: Double = 1000,
        clickDecaySeconds: Double = 0.03
    ) -> SyntheticFixture {
        let total = Int(durationSeconds * sampleRate)
        var samples = [Float](repeating: 0, count: total)
        let period = 60.0 / bpm

        var beatTimes: [Double] = []
        var t = 0.0
        while t < durationSeconds {
            beatTimes.append(t)
            let gain: Float = (energyJumpAt != nil && t >= energyJumpAt!) ? loudGain : quietGain
            renderClick(into: &samples, atSeconds: t, sampleRate: sampleRate,
                        frequency: clickFrequency, decaySeconds: clickDecaySeconds, gain: gain)
            t += period
        }

        return SyntheticFixture(
            name: name,
            buffer: AudioBuffer(samples: samples, sampleRate: sampleRate),
            trueBPM: bpm,
            trueBeatTimes: beatTimes,
            trueSectionBoundary: energyJumpAt
        )
    }

    private static func renderClick(
        into samples: inout [Float],
        atSeconds: Double,
        sampleRate: Double,
        frequency: Double,
        decaySeconds: Double,
        gain: Float
    ) {
        let start = Int(atSeconds * sampleRate)
        let length = Int(decaySeconds * sampleRate * 4)   // render to ~4 time-constants
        let omega = 2.0 * Double.pi * frequency / sampleRate
        for i in 0..<length {
            let idx = start + i
            guard idx >= 0, idx < samples.count else { break }
            let env = exp(-Double(i) / (decaySeconds * sampleRate))
            let value = Float(env * sin(omega * Double(i))) * gain
            samples[idx] += value
        }
    }

    /// The three canonical fixtures from the kickoff prompt: 100 / 128 / 174 BPM, each with an
    /// energy jump partway through.
    public static func canonicalThree(durationSeconds: Double = 30) -> [SyntheticFixture] {
        [
            clickTrack(name: "click-100bpm", bpm: 100, durationSeconds: durationSeconds,
                       energyJumpAt: durationSeconds * 0.5),
            clickTrack(name: "click-128bpm", bpm: 128, durationSeconds: durationSeconds,
                       energyJumpAt: durationSeconds * 0.5),
            clickTrack(name: "click-174bpm", bpm: 174, durationSeconds: durationSeconds,
                       energyJumpAt: durationSeconds * 0.5),
        ]
    }
}
