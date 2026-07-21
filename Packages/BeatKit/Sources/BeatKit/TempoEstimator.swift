import Foundation

public struct TempoEstimate: Sendable {
    public let bpm: Double
    /// Autocorrelation strength at the winning lag, normalized to lag-0 energy (0...1). A rough
    /// confidence proxy — feeds the signal-quality gate in §B6 (fall back to prior cues if low).
    public let strength: Double
}

/// Estimates tempo by autocorrelating the onset envelope and picking the strongest lag in a BPM
/// range, then resolving the classic half/double ambiguity (spec §B6.2) — optionally snapping to a
/// known BPM from the GetSongBPM cache when the track identity is known.
public struct TempoEstimator: Sendable {
    public let minBPM: Double
    public let maxBPM: Double
    /// Preferred fold range: octave-ambiguous estimates are pulled into this window.
    public let preferredLow: Double
    public let preferredHigh: Double

    public init(minBPM: Double = 60, maxBPM: Double = 200,
                preferredLow: Double = 90, preferredHigh: Double = 180) {
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.preferredLow = preferredLow
        self.preferredHigh = preferredHigh
    }

    public func estimate(_ envelope: OnsetEnvelope, knownBPM: Double? = nil) -> TempoEstimate {
        let x = envelope.values
        let fr = envelope.frameRate
        guard x.count > 8, fr > 0 else { return TempoEstimate(bpm: 0, strength: 0) }

        func lag(forBPM bpm: Double) -> Int { Int((60.0 * fr / bpm).rounded()) }
        let minLag = max(1, lag(forBPM: maxBPM))
        let maxLag = min(x.count - 1, lag(forBPM: minBPM))
        guard maxLag > minLag else { return TempoEstimate(bpm: 0, strength: 0) }

        // Autocorrelation energy at lag 0 (for normalizing strength).
        var energy0: Double = 0
        for v in x { energy0 += Double(v) * Double(v) }
        if energy0 == 0 { return TempoEstimate(bpm: 0, strength: 0) }

        func autocorr(_ l: Int) -> Double {
            var sum: Double = 0
            var i = 0
            let limit = x.count - l
            while i < limit { sum += Double(x[i]) * Double(x[i + l]); i += 1 }
            return sum
        }

        var bestLag = minLag
        var bestValue = -Double.infinity
        for l in minLag...maxLag {
            let v = autocorr(l)
            if v > bestValue { bestValue = v; bestLag = l }
        }

        // Sub-lag refinement: parabolic interpolation around the peak recovers a fractional lag, so
        // tempo resolution is no longer limited by the integer frame grid (critical at high BPM,
        // where one lag step is ~2 BPM and the resulting drift blows the beat-phase budget).
        var refinedLag = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let ym1 = autocorr(bestLag - 1)
            let y0 = bestValue
            let yp1 = autocorr(bestLag + 1)
            let denom = ym1 - 2 * y0 + yp1
            if denom != 0 {
                let delta = 0.5 * (ym1 - yp1) / denom     // in [-1, 1]
                if delta.magnitude <= 1 { refinedLag = Double(bestLag) + delta }
            }
        }

        var bpm = 60.0 * fr / refinedLag
        let strength = min(max(bestValue / energy0, 0), 1)

        if let known = knownBPM {
            // Snap to whichever octave of the estimate is closest to the known BPM.
            bpm = closestOctave(of: bpm, to: known)
        } else {
            // Fold into the preferred range, but only if the folded lag is also a strong peak —
            // avoids halving a genuinely fast track.
            bpm = foldIntoPreferred(bpm, autocorr: autocorr, fr: fr, energy0: energy0)
        }

        return TempoEstimate(bpm: bpm, strength: strength)
    }

    private func closestOctave(of bpm: Double, to target: Double) -> Double {
        let candidates = [bpm * 0.5, bpm, bpm * 2.0]
        return candidates.min(by: { abs($0 - target) < abs($1 - target) }) ?? bpm
    }

    private func foldIntoPreferred(_ bpm: Double, autocorr: (Int) -> Double, fr: Double, energy0: Double) -> Double {
        var result = bpm
        func lag(_ b: Double) -> Int { Int((60.0 * fr / b).rounded()) }
        func strengthAt(_ b: Double) -> Double {
            let l = lag(b)
            guard l >= 1 else { return -1 }
            return autocorr(l) / energy0
        }
        // If below preferred low, try doubling while the doubled tempo is a comparably strong peak.
        while result < preferredLow {
            let doubled = result * 2
            guard doubled <= maxBPM, strengthAt(doubled) > 0.5 * strengthAt(result) else { break }
            result = doubled
        }
        // If above preferred high, try halving.
        while result > preferredHigh {
            let halved = result / 2
            guard halved >= minBPM, strengthAt(halved) > 0.5 * strengthAt(result) else { break }
            result = halved
        }
        return result
    }
}
