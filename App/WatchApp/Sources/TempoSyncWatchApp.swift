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
        VStack(spacing: 6) {
            if session.moveName.isEmpty {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title2).foregroundStyle(.secondary)
                Text("Start a ride on your iPhone")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                if let countdown = session.countdownText {
                    Text(countdown)
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .foregroundStyle(.yellow)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(session.moveName)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                if !session.cadenceLine.isEmpty {
                    Text(session.cadenceLine)
                        .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
                Label(session.resistanceUp ? "Resistance UP" : "Light",
                      systemImage: session.resistanceUp ? "dial.high.fill" : "dial.low.fill")
                    .font(.caption2)
                    .foregroundStyle(session.resistanceUp ? .orange : .secondary)
                    .padding(.top, 2)
            }
        }
        .padding()
    }
}

/// Receives ride cues from the phone and turns them into wrist haptics + display state.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published var moveName = ""
    @Published var cadenceLine = ""
    @Published var countdownText: String?
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
        let text = message["text"] as? String
        let rpm = message["rpm"] as? Int
        let bpm = message["bpm"] as? Int
        let up = message["up"] as? Bool
        Task { @MainActor in
            WatchSessionManager.shared.apply(event: event, name: name, text: text, rpm: rpm, bpm: bpm, up: up)
        }
    }

    private func apply(event: String, name: String?, text: String?, rpm: Int?, bpm: Int?, up: Bool?) {
        switch event {
        case "move":
            if let name { moveName = name }
            if let rpm, let bpm { cadenceLine = "~\(rpm) RPM · \(bpm) BPM" }
            countdownText = nil
            WKInterfaceDevice.current().play(.notification)          // transition buzz
        case "countdown":
            countdownText = text
            WKInterfaceDevice.current().play(.start)                 // heads-up tick
        case "resistance":
            resistanceUp = up ?? false
            WKInterfaceDevice.current().play((up ?? false) ? .directionUp : .directionDown)
        case "idle":
            moveName = ""; cadenceLine = ""; countdownText = nil; resistanceUp = false
        default:
            break
        }
    }
}
