import SwiftUI
import RoutineKit
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// The handlebar-mounted live screen (spec §B5): beat pulse ring, animated move pictogram, next-move
/// countdown, phrase-position dots, and resistance state.
///
/// Rendering is driven by `TimelineView(.animation)` — each display refresh *pulls* a fresh
/// `LiveFrame` from the view model, so the pulse and pedal animation run at native refresh rate with
/// no timer jitter.
struct LiveCoachView: View {
    @StateObject private var vm = LiveCoachViewModel()
    /// Injected so the demo/Mode-S/Mode-H entry can be chosen by the caller.
    let start: (LiveCoachViewModel) -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @AppStorage(PictogramStyle.defaultsKey) private var bikeStyleRaw = PictogramStyle.spin.rawValue

    var body: some View {
        TimelineView(.animation) { context in
            let _ = context.date                       // register the per-frame dependency
            let frame = vm.currentFrame()
            ZStack {
                intensityBackground(frame.currentIntensity).ignoresSafeArea()
                VStack(spacing: 16) {
                    header(frame)
                    Spacer(minLength: 8)
                    pulse(frame)
                    Spacer(minLength: 8)
                    nextMoveBar(frame)
                    phraseDots(frame)
                    resistanceRow(frame)
                    if vm.canNudgeDifficulty { difficultyNudgeRow }
                    if vm.hasTransport { transportBar }
                    if vm.modeSState != nil { tapTheOneButton }
                }
                .padding()
            }
        }
        .onAppear {
            start(vm)
            setIdleTimer(disabled: true)     // handlebar-mounted: don't let the screen sleep
        }
        .onDisappear {
            vm.stop()
            setIdleTimer(disabled: false)
        }
        .statusBarHidden()   // whole app is dark via UIUserInterfaceStyle; no per-view override needed
    }

    // MARK: Sections

    private func header(_ f: LiveFrame) -> some View {
        HStack(alignment: .top, spacing: 10) {
            #if canImport(UIKit)
            if let art = vm.artwork {
                Image(uiImage: art)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            }
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(f.sectionType?.rawValue.uppercased() ?? "—")
                    .font(.caption).bold().foregroundStyle(.white.opacity(0.7))
                Text(vm.statusLine).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
            Spacer()
            // Cadence chip: the RPM target is what the rider actually holds; BPM is context.
            // (The learned/prior confidence distinction still exists internally — it gates hard
            // countdowns — but it earns UI space again only when calibration rides return.)
            if f.bpm > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("~\(f.suggestedRPM) RPM")
                        .font(Theme.black(19)).monospacedDigit()
                    Text("\(Int(f.bpm)) BPM")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func pulse(_ f: LiveFrame) -> some View {
        // Ring snaps to full at the top of each beat (phase→0) and eases down — a visual metronome.
        // Driven directly from continuous phase; no SwiftUI animation to fight the beat.
        let scale = 1.0 + 0.10 * (1.0 - f.beatPhase)
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 3)
                .frame(width: 300, height: 300)
            Circle()
                .stroke(.white.opacity(0.85), lineWidth: 5)
                .frame(width: 272, height: 272)
                .scaleEffect(scale)
            VStack(spacing: 4) {
                MovePictogram(moveName: f.currentMoveName, beatTime: f.beatTime,
                              countsIntoMove: f.countsIntoMove,
                              bikeStyle: PictogramStyle(rawValue: bikeStyleRaw) ?? .spin)
                    .frame(width: 150, height: 150)
                Text(f.currentMoveName)
                    .font(Theme.black(26))
                    .multilineTextAlignment(.center)
                if !f.currentFormCue.isEmpty {
                    Text(f.currentFormCue)
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 230)
        }
    }

    private func nextMoveBar(_ f: LiveFrame) -> some View {
        Group {
            if let countdown = f.countdownText {
                Text(countdown)
                    .font(Theme.black(30))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            } else if let next = f.nextMoveName, let counts = f.countsUntilNext {
                Text("Next: \(next) in \(counts)")
                    .font(.headline).foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            } else {
                Text(" ").font(.headline)
            }
        }
    }

    private func phraseDots(_ f: LiveFrame) -> some View {
        // 8 dots = the 8 groups of 4 counts in a 32-count phrase (spec §B5 "1–8 of 32").
        let active = f.countInPhrase / 4
        return HStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(i == active ? .white : .white.opacity(0.3))
                    .frame(width: i == active ? 12 : 8, height: i == active ? 12 : 8)
            }
        }
    }

    private func resistanceRow(_ f: LiveFrame) -> some View {
        HStack(spacing: 8) {
            Image(systemName: f.resistanceUp ? "dial.high.fill" : "dial.low.fill")
            Text(f.resistanceUp ? "Resistance UP" : "Light resistance")
                .font(.subheadline).bold()
        }
        .foregroundStyle(f.resistanceUp ? .white : .white.opacity(0.6))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(f.resistanceUp ? 0.2 : 0.08), in: Capsule())
    }

    /// In-ride difficulty: one tap re-biases the rest of the class.
    private var difficultyNudgeRow: some View {
        HStack(spacing: 16) {
            Button { vm.nudgeDifficulty(-1) } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            Text(vm.currentDifficultyName)
                .font(Theme.bold(13))
                .frame(minWidth: 84)
            Button { vm.nudgeDifficulty(+1) } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    /// Music remote (Mode H): scrubber + previous / −15 s / play-pause / +15 s / next.
    private var transportBar: some View {
        VStack(spacing: 6) {
            // Scrubber with elapsed / total.
            HStack(spacing: 8) {
                Text(timeString(isScrubbing ? scrubValue : vm.playbackPosition))
                    .font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : min(vm.playbackPosition, max(vm.playbackDuration, 1)) },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(vm.playbackDuration, 1)
                ) { editing in
                    if !editing { vm.scrub(to: scrubValue) }
                    isScrubbing = editing
                }
                .tint(.white)
                Text(timeString(vm.playbackDuration))
                    .font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, alignment: .leading)
            }
            // Transport buttons — big targets for a handlebar mount.
            HStack(spacing: 28) {
                Button { vm.previousTrack() } label: { Image(systemName: "backward.end.fill") }
                Button { vm.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                Button { vm.togglePlayPause() } label: {
                    Image(systemName: vm.isPlayingNow ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                Button { vm.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                Button { vm.nextTrack() } label: { Image(systemName: "forward.end.fill") }
            }
            .font(.system(size: 22))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 4)
    }

    private func timeString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "Tap the 1" — rider taps on the downbeat to re-align the pulse (spec §B3 nudge control).
    private var tapTheOneButton: some View {
        Button {
            vm.tapOne()
        } label: {
            Label("Tap the 1", systemImage: "hand.tap.fill")
                .font(.headline)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.white.opacity(0.18), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    // MARK: Style

    private func intensityBackground(_ tier: IntensityTier) -> LinearGradient {
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
