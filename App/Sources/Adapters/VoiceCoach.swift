import Foundation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// Optional spoken cues ("Standing sprint in 8") that duck the music while speaking.
/// Off by default — the visual-first design stays primary.
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCoach()
    static let defaultsKey = "voice_cues_enabled"

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }

    /// True while a microphone session owns the shared audio session (calibration / Mode S).
    /// Spoken cues would both flip the session category under the live engine AND leak TTS into
    /// the capture the analyzer is listening to — so they are silenced for the duration.
    var suppressed = false

    private var sessionConfigured = false

    func speak(_ text: String) {
        guard enabled, !suppressed, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            // Category set once, not per utterance (re-categorizing churns the shared session).
            sessionConfigured = true
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        }
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        // Un-duck the music once the cue lands — but never yank the session out from under a live
        // mic engine.
        Task { @MainActor in
            guard !VoiceCoach.shared.suppressed else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
#endif
