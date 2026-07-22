import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity payload — the ride on the Lock Screen / Dynamic Island.
/// Shared between the app (which starts/updates it) and the widget extension (which renders it).
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var move: String
        var rpm: Int
        var bpm: Int
        var countdown: String?
        var resistanceUp: Bool
    }

    var startedAt: Date
}
#endif
