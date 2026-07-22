import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Starts/updates/ends the ride's Live Activity. Fire-and-forget: if Live Activities are disabled
/// the whole thing is a silent no-op. Updates go through ActivityKit's static registry so no
/// main-actor state ever crosses into the update tasks (Swift 6 sendability).
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var started = false
    private var lastState: RideActivityAttributes.ContentState?

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !started else { return }
        let initial = RideActivityAttributes.ContentState(
            move: "Warming up", rpm: 0, bpm: 0, countdown: nil, resistanceUp: false)
        _ = try? Activity.request(
            attributes: RideActivityAttributes(startedAt: .now),
            content: .init(state: initial, staleDate: .now + 20)
        )
        started = true
        lastState = initial
    }

    func update(move: String, rpm: Int, bpm: Int, countdown: String?, resistanceUp: Bool) {
        guard started else { return }
        let state = RideActivityAttributes.ContentState(
            move: move, rpm: rpm, bpm: bpm, countdown: countdown, resistanceUp: resistanceUp)
        guard state != lastState else { return }          // only push real changes
        lastState = state
        Task.detached {
            for activity in Activity<RideActivityAttributes>.activities {
                // staleDate: if the app dies mid-ride, the Lock Screen stops showing a live-looking
                // move within seconds instead of indefinitely.
                await activity.update(.init(state: state, staleDate: .now + 20))
            }
        }
    }

    func end() {
        guard started else { return }
        started = false
        lastState = nil
        Task.detached {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
