// swift-tools-version: 6.0
import PackageDescription

// RoutineKit — the Rhythm Coach routine generator (core IP, spec §B4).
//
// ZERO platform imports. Pure Swift. Runs anywhere Swift runs (iOS, macOS, Linux),
// which is exactly why it can be unit-tested from the command line without Xcode.
//
// Targets:
//   RoutineKit       — the library.
//   RoutineKitCheck  — a runnable assertion harness (`swift run RoutineKitCheck`)
//                      that mirrors the XCTest suite so the grammar can be verified
//                      with only the Command Line Tools installed (no full Xcode).
//   RoutineKitTests  — the real XCTest suite (`swift test`, needs full Xcode).
let package = Package(
    name: "RoutineKit",
    products: [
        .library(name: "RoutineKit", targets: ["RoutineKit"]),
    ],
    targets: [
        .target(name: "RoutineKit"),
        .executableTarget(name: "RoutineKitCheck", dependencies: ["RoutineKit"]),
        .testTarget(name: "RoutineKitTests", dependencies: ["RoutineKit"]),
    ]
)
