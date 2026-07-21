import Foundation
import AVFoundation
import RhythmCoachCore

/// Mode S mic adapter: taps `AVAudioEngine`'s input and hands BeatKit mono float buffers stamped
/// with the *hardware capture time* of their first sample.
///
/// The timestamp matters more than anything else here: `AVAudioTime.hostTime` from the tap is on the
/// same clock as `CACurrentMediaTime()`, so downstream beat detections can be placed on the wall
/// clock to within a few ms. (The first implementation stamped audio at analysis time instead —
/// thread hops + ring accumulation made the pulse trail the real beat audibly. Kevin heard it.)
///
/// `@unchecked Sendable`: owns non-Sendable AV objects but has a single owner; the tap callback only
/// forwards immutable arrays + scalars.
final class MicAudioSourceAV: MicAudioSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    var sampleRate: Double { session.sampleRate > 0 ? session.sampleRate : 44_100 }

    func start(onBuffer: @escaping @Sendable (_ samples: [Float], _ captureHostTime: Double) -> Void) throws {
        // Coexist with music over the speaker or headphones (spec §B2: both environments).
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        // Hardware input latency: samples reach the tap this much after they hit the mic.
        let inputLatency = session.inputLatency

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, when in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            // hostTime == 0 means "no timestamp" — fall back to now minus the buffer span.
            let captureTime: Double
            if when.isHostTimeValid {
                captureTime = AVAudioTime.seconds(forHostTime: when.hostTime) - inputLatency
            } else {
                captureTime = CACurrentMediaTime() - Double(count) / buffer.format.sampleRate - inputLatency
            }
            onBuffer(Array(UnsafeBufferPointer(start: channel, count: count)), captureTime)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false)
    }
}
