// swift-tools-version: 6.0
import PackageDescription

// BeatKit — the audio-understanding layer for Rhythm Coach (spec §B3).
//
// The offline "spike" surface: given an audio buffer (or WAV fixture), estimate tempo, lock a beat
// grid, and detect section boundaries. Only platform import is Accelerate (vDSP FFT), per spec.
//
// Targets:
//   BeatKit       — the library (DSP + scoring + fixtures).
//   BeatKitCheck  — runnable harness (`swift run BeatKitCheck`): generates the 100/128/174 BPM
//                   synthetic fixtures, writes/reads them as WAV, analyzes, and scores against the
//                   §B3 success bar (≥90% tempo within half/double, beat phase ±50 ms).
//   BeatKitTests  — XCTest suite (`swift test`, needs full Xcode).
let package = Package(
    name: "BeatKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16)],
    products: [
        .library(name: "BeatKit", targets: ["BeatKit"]),
    ],
    targets: [
        .target(name: "BeatKit"),
        .executableTarget(name: "BeatKitCheck", dependencies: ["BeatKit"]),
        .testTarget(name: "BeatKitTests", dependencies: ["BeatKit"]),
    ]
)
