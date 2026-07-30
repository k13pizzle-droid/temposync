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

    /// Called on the main actor when the channel becomes usable (activation completed, or the
    /// watch became reachable again after a wrist-down stretch). The ride loop resets its diff
    /// state here and re-sends full state — without this, cues dropped while unreachable were
    /// marked delivered and the wrist showed a stale move/resistance until the NEXT change.
    var onReconnect: (@MainActor () -> Void)?

    private func fireReconnect() {
        Task { @MainActor in self.onReconnect?() }
    }

    private func canSend(bypassToggle: Bool) -> Bool {
        (bypassToggle || Self.cuesEnabled)
            && WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isReachable
    }

    private func send(_ payload: [String: Any], bypassToggle: Bool = false) {
        guard canSend(bypassToggle: bypassToggle) else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: Events

    func moveChanged(name: String, rpm: Int, bpm: Int, revsPerBeat: Double, formCue: String) {
        send(["event": "move", "name": name, "rpm": rpm, "bpm": bpm,
              "revs": revsPerBeat, "cue": formCue])
    }

    /// One message per countdown window — the wrist buzzes once and counts down locally from
    /// `seconds` (per-tick sends made the watch buzz every second of the window).
    func countdown(move: String, seconds: Double) {
        send(["event": "countdown", "name": move, "seconds": seconds])
    }

    func resistance(up: Bool) {
        send(["event": "resistance", "up": up])
    }

    /// Clearing the wrist bypasses the cues toggle — switching cues off must never freeze the
    /// watch on a stale ride.
    func idle() {
        send(["event": "idle"], bypassToggle: true)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if activationState == .activated { fireReconnect() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { fireReconnect() }
    }
}
#endif
