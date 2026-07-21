import Foundation

/// Minimal 16-bit PCM mono WAV reader/writer — enough to persist and reload fixtures, and to prove
/// the "given a WAV fixture, output tempo/grid/sections" API from the kickoff prompt.
/// (Production audio comes from AVAudioEngine in the iOS app; this is for the offline spike.)
public enum WAVFile {

    public enum WAVError: Error, CustomStringConvertible {
        case notRIFF, notWAVE, missingFmt, missingData, unsupported(String)
        public var description: String {
            switch self {
            case .notRIFF: return "Not a RIFF file"
            case .notWAVE: return "Not a WAVE file"
            case .missingFmt: return "Missing fmt chunk"
            case .missingData: return "Missing data chunk"
            case .unsupported(let s): return "Unsupported WAV: \(s)"
            }
        }
    }

    // MARK: Write

    /// Write a mono 16-bit PCM WAV. Samples are clamped to [-1, 1].
    public static func write(_ buffer: AudioBuffer, to url: URL) throws {
        let sampleRate = UInt32(buffer.sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(buffer.samples.count * 2)

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }

        appendASCII("RIFF")
        append(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append(UInt32(16))              // PCM fmt chunk size
        append(UInt16(1))               // audio format = PCM
        append(numChannels)
        append(sampleRate)
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)
        appendASCII("data")
        append(dataSize)
        for s in buffer.samples {
            let clamped = max(-1.0, min(1.0, s))
            append(Int16(clamped * 32767))
        }
        try data.write(to: url)
    }

    // MARK: Read

    /// Read a mono/stereo 16-bit PCM WAV into a mono `AudioBuffer` (channels averaged).
    public static func read(_ url: URL) throws -> AudioBuffer {
        let data = try Data(contentsOf: url)
        func u32(_ offset: Int) -> UInt32 {
            UInt32(data[offset]) | UInt32(data[offset+1]) << 8 | UInt32(data[offset+2]) << 16 | UInt32(data[offset+3]) << 24
        }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | UInt16(data[offset+1]) << 8
        }
        func ascii(_ offset: Int, _ len: Int) -> String {
            String(bytes: data[offset..<offset+len], encoding: .ascii) ?? ""
        }

        guard data.count > 12, ascii(0, 4) == "RIFF" else { throw WAVError.notRIFF }
        guard ascii(8, 4) == "WAVE" else { throw WAVError.notWAVE }

        var offset = 12
        var channels: UInt16 = 1
        var sampleRate: UInt32 = 44100
        var bits: UInt16 = 16
        var pcm: Data? = nil

        while offset + 8 <= data.count {
            let chunkID = ascii(offset, 4)
            let chunkSize = Int(u32(offset + 4))
            let body = offset + 8
            if chunkID == "fmt " {
                channels = u16(body + 2)
                sampleRate = u32(body + 4)
                bits = u16(body + 14)
            } else if chunkID == "data" {
                let end = min(body + chunkSize, data.count)
                pcm = data.subdata(in: body..<end)
            }
            offset = body + chunkSize + (chunkSize % 2)   // chunks are word-aligned
        }

        guard bits == 16 else { throw WAVError.unsupported("\(bits)-bit (only 16-bit supported)") }
        guard let pcm else { throw WAVError.missingData }

        let frameCount = pcm.count / (2 * Int(channels))
        var samples = [Float](repeating: 0, count: frameCount)
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let ints = raw.bindMemory(to: Int16.self)
            for frame in 0..<frameCount {
                var acc: Int32 = 0
                for ch in 0..<Int(channels) {
                    acc += Int32(Int16(littleEndian: ints[frame * Int(channels) + ch]))
                }
                samples[frame] = Float(acc) / Float(channels) / 32768.0
            }
        }
        return AudioBuffer(samples: samples, sampleRate: Double(sampleRate))
    }
}
