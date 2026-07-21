import Foundation

public struct SectionBoundary: Sendable {
    public let timeSeconds: Double
    /// Signed relative energy change across the boundary (+ = jump up, − = drop).
    public let energyDelta: Double
}

/// Detects section changes from the energy envelope: a drop/lift is a simultaneous energy step at a
/// phrase boundary (spec §B3). For the offline spike this finds significant steps in a smoothed
/// short-term energy curve and snaps them to the nearest beat.
public struct SectionDetector: Sendable {
    public let windowSeconds: Double
    /// Minimum |relative change| in smoothed energy to count as a section boundary.
    public let threshold: Double

    public init(windowSeconds: Double = 0.25, threshold: Double = 0.35) {
        self.windowSeconds = windowSeconds
        self.threshold = threshold
    }

    /// Short-term RMS energy per window.
    public func energyEnvelope(_ buffer: AudioBuffer) -> (values: [Double], frameRate: Double) {
        let win = max(1, Int(windowSeconds * buffer.sampleRate))
        var out: [Double] = []
        var pos = 0
        while pos + win <= buffer.samples.count {
            var sum: Double = 0
            for i in pos..<pos+win { sum += Double(buffer.samples[i]) * Double(buffer.samples[i]) }
            out.append((sum / Double(win)).squareRoot())
            pos += win
        }
        return (out, buffer.sampleRate / Double(win))
    }

    public func detect(_ buffer: AudioBuffer, beatGrid: BeatGrid? = nil) -> [SectionBoundary] {
        let (energy, fr) = energyEnvelope(buffer)
        return boundaries(energy: energy, frameRate: fr, beatGrid: beatGrid)
    }

    /// Envelope-based path (used by `StreamingAnalyzer`, which never holds raw audio).
    public func boundaries(energy: [Double], frameRate fr: Double, beatGrid: BeatGrid?) -> [SectionBoundary] {
        guard energy.count > 4 else { return [] }

        // Smooth with a short moving average to suppress per-beat ripple.
        let smoothN = max(1, Int(1.0 * fr))   // ~1 second
        var smoothed = [Double](repeating: 0, count: energy.count)
        for i in 0..<energy.count {
            let lo = max(0, i - smoothN / 2)
            let hi = min(energy.count - 1, i + smoothN / 2)
            var sum: Double = 0
            for j in lo...hi { sum += energy[j] }
            smoothed[i] = sum / Double(hi - lo + 1)
        }

        let globalMean = max(smoothed.reduce(0, +) / Double(smoothed.count), 1e-9)

        // Find local steps: compare energy a bit before vs. a bit after each point.
        let gap = max(1, Int(0.5 * fr))
        var candidates: [(index: Int, delta: Double)] = []
        var i = gap
        while i < smoothed.count - gap {
            let before = smoothed[i - gap]
            let after = smoothed[i + gap]
            let delta = (after - before) / globalMean
            if abs(delta) >= threshold {
                candidates.append((i, delta))
            }
            i += 1
        }

        // Non-maximum suppression: keep the strongest step within any ~2 second neighborhood.
        candidates.sort { abs($0.delta) > abs($1.delta) }
        var chosen: [(index: Int, delta: Double)] = []
        let minSep = Int(2.0 * fr)
        for c in candidates {
            if chosen.allSatisfy({ abs($0.index - c.index) >= minSep }) {
                chosen.append(c)
            }
        }

        return chosen
            .map { c -> SectionBoundary in
                var time = Double(c.index) / fr
                if let grid = beatGrid, !grid.beatTimes.isEmpty {
                    time = grid.beatTimes.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
                }
                return SectionBoundary(timeSeconds: time, energyDelta: c.delta)
            }
            .sorted { $0.timeSeconds < $1.timeSeconds }
    }
}
