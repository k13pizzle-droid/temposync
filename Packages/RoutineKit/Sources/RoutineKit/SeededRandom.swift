import Foundation

/// Deterministic PRNG (SplitMix64). Given the same seed it produces the same stream on every
/// machine and every process — this is what makes routines *learnable* ("same song, same class").
///
/// Do NOT use the system RNG anywhere in generation: it is nondeterministic by design.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Stable string hash (FNV-1a, 64-bit). `String.hashValue` is randomized per process, so we cannot
/// use it to derive the seed — this gives a process-independent hash of the track key.
public func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
}

extension SplitMix64 {
    /// Weighted pick over `(item, weight)` pairs. Weights need not sum to 1. Deterministic.
    /// Returns nil only if `items` is empty or all weights are non-positive.
    mutating func weightedPick<T>(_ items: [(T, Double)]) -> T? {
        let total = items.reduce(0.0) { $0 + max($1.1, 0) }
        guard total > 0 else { return items.first?.0 }
        var r = Double.random(in: 0..<total, using: &self)
        for (item, weight) in items {
            let w = max(weight, 0)
            if r < w { return item }
            r -= w
        }
        return items.last?.0
    }
}
