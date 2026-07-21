import Foundation
import Accelerate

/// Thin wrapper over vDSP's real FFT. Produces the magnitude spectrum of a windowed frame.
/// Not thread-safe (owns an FFTSetup); use one instance per analysis pass on a single thread.
final class FFTProcessor {
    let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let halfN: Int

    init(n: Int) {
        precondition(n > 0 && (n & (n - 1)) == 0, "FFT size must be a power of two")
        self.n = n
        self.halfN = n / 2
        self.log2n = vDSP_Length(log2(Double(n)).rounded())
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Magnitude spectrum (length n/2) of a real frame that has already been windowed.
    func magnitudes(_ frame: [Float]) -> [Float] {
        precondition(frame.count == n, "frame must be exactly n samples")
        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)
        var magsSquared = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                frame.withUnsafeBufferPointer { framePtr in
                    framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magsSquared, 1, vDSP_Length(halfN))
            }
        }

        var mags = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvsqrtf(&mags, magsSquared, &count)
        return mags
    }
}

/// Precomputed Hann window.
func hannWindow(_ size: Int) -> [Float] {
    var w = [Float](repeating: 0, count: size)
    vDSP_hann_window(&w, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    return w
}
