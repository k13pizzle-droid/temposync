import SwiftUI
import RoutineKit
import RhythmCoachCore

/// TempoSync for Apple TV — the living-room class screen.
///
/// v1 scaffold: runs the demo ride full-screen so the whole experience is visible on the big
/// display. The full at-home story (phone controls playback + calibrated maps, TV mirrors the live
/// class over the local network) is designed in ROADMAP.md — this target proves the render layer:
/// RoutineKit/RhythmCoachCore/MovePictogram all run natively on tvOS.
@main
struct TempoSyncTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVRideView()
        }
    }
}

struct TVRideView: View {
    private let coach: LiveCoach
    private let start = Date.now

    init() {
        let request = SampleSongs.edmAnthem(seed: 7, skill: .three, intensity: .hard, confidence: .learned)
        coach = LiveCoach(routine: RoutineGenerator().generate(request),
                          clock: BeatClock(bpm: request.bpm, beatOffset: 0),
                          sections: request.sections, confidence: .learned)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let frame = coach.frame(at: context.date.timeIntervalSince(start))
            ZStack {
                background(frame.currentIntensity).ignoresSafeArea()
                HStack(spacing: 60) {
                    // Left: the rider, big.
                    VStack(spacing: 10) {
                        MovePictogram(moveName: frame.currentMoveName, beatTime: frame.beatTime,
                                      countsIntoMove: frame.countsIntoMove,
                                      cadenceRevsPerBeat: frame.currentCadence.revsPerBeat,
                                      bikeStyle: .spin)
                            .frame(width: 420, height: 420)
                        Text(frame.currentMoveName)
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                    }
                    // Right: cadence + what's next + phrase dots.
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("~\(frame.suggestedRPM) RPM")
                                .font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text("\(Int(frame.bpm)) BPM · \(frame.sectionType?.rawValue.uppercased() ?? "")")
                                .font(.title3).opacity(0.7)
                        }
                        if let countdown = frame.countdownText {
                            Text(countdown)
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundStyle(.yellow)
                        } else if let next = frame.nextMoveName, let counts = frame.countsUntilNext {
                            Text("Next: \(next) in \(counts)")
                                .font(.title2).opacity(0.85).monospacedDigit()
                        }
                        HStack(spacing: 14) {
                            ForEach(0..<8, id: \.self) { i in
                                Circle()
                                    .fill(i == frame.countInPhrase / 4 ? .white : .white.opacity(0.3))
                                    .frame(width: i == frame.countInPhrase / 4 ? 18 : 12,
                                           height: i == frame.countInPhrase / 4 ? 18 : 12)
                            }
                        }
                        Label(frame.resistanceUp ? "Resistance UP" : "Light resistance",
                              systemImage: frame.resistanceUp ? "dial.high.fill" : "dial.low.fill")
                            .font(.title3)
                            .opacity(frame.resistanceUp ? 1 : 0.6)
                    }
                }
                .foregroundStyle(.white)
            }
        }
    }

    private func background(_ tier: IntensityTier) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .recovery: colors = [.blue.opacity(0.7), .indigo]
        case .moderate: colors = [.teal, .blue]
        case .high:     colors = [.orange, .pink]
        case .peak:     colors = [.red, .purple]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
