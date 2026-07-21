import Foundation
import RhythmCoachCore
#if canImport(CoreMotion)
import CoreMotion

/// RunSync cadence adapter (spec §A): `CMPedometer` running cadence from the iPhone in a pocket.
/// Reports steps-per-minute; `CMPedometer` gives steps-per-second, so ×60.
final class CadenceSourceCM: CadenceSource, @unchecked Sendable {
    private let pedometer = CMPedometer()

    enum CadenceError: Error { case unavailable }

    func start(onCadence: @escaping @Sendable (Double) -> Void) throws {
        guard CMPedometer.isCadenceAvailable() else { throw CadenceError.unavailable }
        pedometer.startUpdates(from: Date()) { data, _ in
            guard let stepsPerSecond = data?.currentCadence?.doubleValue else { return }
            onCadence(stepsPerSecond * 60.0)
        }
    }

    func stop() { pedometer.stopUpdates() }
}
#endif
