// swift-tools-version: 6.0
import PackageDescription

// RhythmCoachCore — the platform-agnostic app logic that sits between the two engines and the UI.
//
// Imports RoutineKit + BeatKit; adds the Mode S / Mode H session coordinators, the StructurePrior
// heuristic, the RunSync tempo engine, the live-coaching state model, and the SwiftData cache
// records. Platform I/O (mic, now-playing, pedometer) is abstracted behind protocols so all of this
// stays unit-testable on macOS; the app target supplies the concrete iOS adapters.
let package = Package(
    name: "RhythmCoachCore",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "RhythmCoachCore", targets: ["RhythmCoachCore"]),
    ],
    dependencies: [
        .package(path: "../RoutineKit"),
        .package(path: "../BeatKit"),
    ],
    targets: [
        .target(name: "RhythmCoachCore", dependencies: ["RoutineKit", "BeatKit"]),
        .testTarget(name: "RhythmCoachCoreTests", dependencies: ["RhythmCoachCore"]),
    ]
)
