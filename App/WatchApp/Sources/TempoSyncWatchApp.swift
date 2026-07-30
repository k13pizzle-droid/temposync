import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct TempoSyncWatchApp: App {
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(session)
        }
    }
}

/// The wrist view of the ride (spec §B5 Watch secondary): current move + cadence, with distinct
/// haptics for transitions / countdowns / resistance changes. Deliberately NO per-beat pulsing —
/// Bluetooth latency would make a beat-synced buzz lie to the rider.
struct WatchRideView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        VStack(spacing: 4) {
            if session.moveName.isEmpty {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title2).foregroundStyle(.secondary)
                Text("Start a ride on your iPhone")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                if let end = session.countdownEnd, let move = session.countdownMove, end > .now {
                    // Wrist-local countdown: one message started it (one buzz); the timer text
                    // counts down here with no further radio traffic.
                    HStack(spacing: 4) {
                        Text(move)
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(.yellow)
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
                // The same rider as the phone, holding the move's pose — static (battery), crank
                // pinned so the right foot is planted on the "one".
                MovePictogram(moveName: session.moveName, beatTime: 0,
                              cadenceRevsPerBeat: session.moveRevsPerBeat,
                              frozenOnTheOne: true, bikeStyle: .spin)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(session.moveName)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                if !session.cadenceLine.isEmpty {
                    Text(session.cadenceLine)
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                Label(session.resistanceUp ? "Resistance UP" : "Light",
                      systemImage: session.resistanceUp ? "dial.high.fill" : "dial.low.fill")
                    .font(.caption2)
                    .foregroundStyle(session.resistanceUp ? .orange : .secondary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
    }
}

/// Receives ride cues from the phone and turns them into wrist haptics + display state.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published var moveName = ""
    @Published var cadenceLine = ""
    @Published var moveRevsPerBeat: Double = 0.5
    @Published var countdownMove: String?
    @Published var countdownEnd: Date?
    @Published var resistanceUp = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: WCSessionDelegate (nonisolated; typed values are extracted before hopping to main)

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let event = message["event"] as? String ?? ""
        let name = message["name"] as? String
        let seconds = message["seconds"] as? Double
        let rpm = message["rpm"] as? Int
        let bpm = message["bpm"] as? Int
        let revs = message["revs"] as? Double
        let up = message["up"] as? Bool
        Task { @MainActor in
            WatchSessionManager.shared.apply(event: event, name: name, seconds: seconds,
                                             rpm: rpm, bpm: bpm, revs: revs, up: up)
        }
    }

    private func apply(event: String, name: String?, seconds: Double?, rpm: Int?, bpm: Int?,
                       revs: Double?, up: Bool?) {
        switch event {
        case "move":
            if let name { moveName = name }
            if let rpm, let bpm { cadenceLine = "~\(rpm) RPM · \(bpm) BPM" }
            moveRevsPerBeat = revs ?? 0.5
            countdownMove = nil; countdownEnd = nil
            WKInterfaceDevice.current().play(.notification)          // transition buzz
        case "countdown":
            // One buzz per window; the display counts down locally from `seconds`.
            countdownMove = name
            countdownEnd = Date().addingTimeInterval(seconds ?? 4)
            WKInterfaceDevice.current().play(.start)                 // heads-up tick
        case "resistance":
            resistanceUp = up ?? false
            WKInterfaceDevice.current().play((up ?? false) ? .directionUp : .directionDown)
        case "idle":
            moveName = ""; cadenceLine = ""; countdownMove = nil; countdownEnd = nil; resistanceUp = false
        default:
            break
        }
    }
}
