import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// Phone → Watch cue channel. Sends transition/countdown/resistance events (spec §B5); the Watch
/// renders them as haptics + display state. Fire-and-forget: if no Watch is paired/reachable,
/// every send is a silent no-op — the phone experience never depends on the wrist.
final class WatchCueSender: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchCueSender()
    static let enabledDefaultsKey = "watch_cues_enabled"

    /// User toggle (default on). The home toolbar and Settings both drive this.
    static var cuesEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) == nil
            ? true : UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    /// Whether a Watch is paired at all (drives whether the toggle is shown).
    var isPaired: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call once early (app start) so the session is live before the first ride.
    func activate() {}

    private var canSend: Bool {
        Self.cuesEnabled
            && WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isReachable
    }

    private func send(_ payload: [String: Any]) {
        guard canSend else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: Events

    func moveChanged(name: String, rpm: Int, bpm: Int) {
        send(["event": "move", "name": name, "rpm": rpm, "bpm": bpm])
    }

    /// One message per countdown window — the wrist buzzes once and counts down locally from
    /// `seconds` (per-tick sends made the watch buzz every second of the window).
    func countdown(move: String, seconds: Double) {
        send(["event": "countdown", "name": move, "seconds": seconds])
    }

    func resistance(up: Bool) {
        send(["event": "resistance", "up": up])
    }

    func idle() {
        send(["event": "idle"])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
