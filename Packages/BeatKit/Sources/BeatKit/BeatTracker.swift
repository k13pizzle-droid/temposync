import Foundation

public struct BeatGrid: Sendable {
    public let bpm: Double
    /// Phase offset of the first beat, in seconds.
    public let offsetSeconds: Double
    /// Seconds per beat.
    public let periodSeconds: Double
    /// Absolute beat times across the analyzed span, in seconds.
    public let beatTimes: [Double]
}

/// Locks a beat grid to the onset envelope: given the tempo, find the phase offset (within one beat
/// period) that best aligns beat instants with onset peaks, then lay down the grid (spec §B3).
public struct BeatTracker: Sendable {
    public init() {}

    public func track(_ envelope: OnsetEnvelope, bpm: Double) -> BeatGrid {
        let fr = envelope.frameRate
        let x = envelope.values
        guard bpm > 0, fr > 0, !x.isEmpty else {
            return BeatGrid(bpm: bpm, offsetSeconds: 0, periodSeconds: bpm > 0 ? 60 / bpm : 0, beatTimes: [])
        }

        let periodFrames = 60.0 * fr / bpm
        let periodInt = max(1, Int(periodFrames.rounded()))

        // Search integer phase offsets in [0, period): sum onset strength at each beat instant.
        var bestOffset = 0
        var bestScore = -Double.infinity
        for offset in 0..<periodInt {
            var score: Double = 0
            var t = Double(offset)
            while t < Double(x.count) {
                score += Double(x[Int(t)])
                t += periodFrames
            }
            if score > bestScore { bestScore = score; bestOffset = offset }
        }

        let offsetSeconds = Double(bestOffset) / fr
        let periodSeconds = 60.0 / bpm
        let totalSeconds = Double(x.count) / fr

        var beats: [Double] = []
        var t = offsetSeconds
        while t < totalSeconds {
            beats.append(t)
            t += periodSeconds
        }

        return BeatGrid(bpm: bpm, offsetSeconds: offsetSeconds, periodSeconds: periodSeconds, beatTimes: beats)
    }
}
