import Foundation
#if canImport(HealthKit)
import HealthKit

/// Saves completed rides to Apple Health as indoor-cycling workouts (opt-in via Settings).
/// Write-only: the app never reads Health data.
@MainActor
final class HealthLogger {
    static let shared = HealthLogger()
    static let defaultsKey = "health_logging_enabled"

    private let store = HKHealthStore()

    var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.defaultsKey) && HKHealthStore.isHealthDataAvailable()
    }

    /// True once the user has actually granted workout writing — the Settings toggle uses this to
    /// stay honest instead of staying on after a denied prompt.
    var workoutWriteAuthorized: Bool {
        HKHealthStore.isHealthDataAvailable()
            && store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    /// Ask for workout + cycling-distance write permission (called when the Settings toggle turns on).
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(
            toShare: [.workoutType(), HKQuantityType(.distanceCycling)], read: [])
    }

    /// Log a finished ride, optionally with console-read distance. Silent no-op when disabled
    /// or unauthorized.
    func logRide(start: Date, end: Date, distanceMiles: Double? = nil) async {
        guard enabled, end.timeIntervalSince(start) > 120 else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let miles = distanceMiles, miles > 0 {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.distanceCycling),
                    quantity: HKQuantity(unit: .mile(), doubleValue: miles),
                    start: start, end: end)
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Authorization denied or Health unavailable — the ride still logs to in-app history.
        }
    }
}
#endif
