import SwiftUI
import RhythmCoachCore

/// Minimal RunSync screen (spec §A): shows the cadence-matched track and lets you drive cadence from
/// the pedometer on device, or a slider in the simulator. The engine logic lives in RhythmCoachCore.
struct RunSyncView: View {
    @StateObject private var vm = RunSyncViewModel()

    var body: some View {
        Form {
            Section("Now playing") {
                if let track = vm.currentTrack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline)
                        Text("\(track.artist) · \(Int(track.bpm)) BPM"
                             + (track.camelot.map { " · \($0)" } ?? ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Start running to pick a track").foregroundStyle(.secondary)
                }
                LabeledContent("Smoothed cadence",
                               value: vm.smoothedCadence.map { "\(Int($0)) spm" } ?? "—")
            }

            Section("Live pedometer") {
                Button(vm.isTracking ? "Stop" : "Start run (pedometer)") { vm.toggleTracking() }
            }

            Section("Simulate cadence") {
                Slider(value: $vm.simulatedCadence, in: 140...190, step: 1)
                Text("\(Int(vm.simulatedCadence)) spm").monospacedDigit()
                Button("Feed cadence sample") { vm.feedSimulated() }
            }
        }
        .navigationTitle("RunSync")
        .onDisappear { vm.stop() }
    }
}

@MainActor
final class RunSyncViewModel: ObservableObject {
    @Published private(set) var currentTrack: RunTrack?
    @Published private(set) var smoothedCadence: Double?
    @Published private(set) var isTracking = false
    @Published var simulatedCadence: Double = 165

    private let engine = RunSyncEngine(library: RunSyncViewModel.demoLibrary)
    private var cadence: CadenceSource?
    private var clock: Double = 0

    func feedSimulated() {
        clock += 5
        apply(engine.ingest(cadence: simulatedCadence, at: clock))
    }

    func toggleTracking() {
        if isTracking { stop(); return }
        #if canImport(CoreMotion)
        let source = CadenceSourceCM()
        do {
            try source.start { [weak self] spm in
                Task { @MainActor in
                    guard let self else { return }
                    self.clock += 1
                    self.apply(self.engine.ingest(cadence: spm, at: self.clock))
                }
            }
            cadence = source
            isTracking = true
        } catch {
            isTracking = false
        }
        #endif
    }

    private func apply(_ decision: RunDecision) {
        smoothedCadence = engine.smoothedCadence
        if case .switchTo(let track) = decision { currentTrack = track }
    }

    func stop() {
        cadence?.stop(); cadence = nil
        isTracking = false
    }

    /// Seeded from the real-track fixture BPM/key data (shared TrackTempo cache in the full app).
    static let demoLibrary: [RunTrack] = [
        RunTrack(id: "levels", title: "Levels", artist: "Avicii", bpm: 126, camelot: "12A"),
        RunTrack(id: "cook", title: "COOK", artist: "SOFI TUKKER", bpm: 108, camelot: "10A"),
        RunTrack(id: "bad-angel", title: "Bad Angel", artist: "Anyma", bpm: 128, camelot: "5A"),
        RunTrack(id: "no-broke-boys", title: "No Broke Boys", artist: "Disco Lines, Tinashe", bpm: 131, camelot: "12A"),
        RunTrack(id: "if-i-lose-myself", title: "If I Lose Myself", artist: "Alesso vs OneRepublic", bpm: 126, camelot: "10B"),
        RunTrack(id: "wish-it-was-you", title: "Wish It Was You", artist: "Audien", bpm: 125, camelot: "12B"),
    ]
}
