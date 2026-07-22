import SwiftUI
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// Batch tempo pass over the whole library using the in-house analyzer: every downloaded /
/// purchased / DRM-free track gets its BPM measured from its own audio and cached forever —
/// after one pass, class building "just knows" your music with zero network.
struct AnalyzeLibraryView: View {
    @StateObject private var vm = AnalyzeLibraryViewModel()

    var body: some View {
        List {
            Section {
                if vm.state == .idle {
                    Text("\(vm.totalCount) songs in your library")
                    Button {
                        vm.start()
                    } label: {
                        Label("Analyze my library", systemImage: "waveform.badge.magnifyingglass")
                            .frame(maxWidth: .infinity).font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if vm.state == .running {
                        ProgressView(value: Double(vm.processed), total: Double(max(vm.totalCount, 1)))
                        Text(vm.currentTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    LabeledContent("Processed", value: "\(vm.processed) of \(vm.totalCount)")
                    LabeledContent("Already known", value: "\(vm.alreadyCached)")
                    LabeledContent("Analyzed on-device", value: "\(vm.analyzed)")
                    LabeledContent("Stream-only (needs network or calibration)", value: "\(vm.streamOnly)")
                    if vm.state == .running {
                        Button("Stop", role: .destructive) { vm.cancel() }
                    } else {
                        Label("Done — tempos are cached for good", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } footer: {
                Text("Analysis reads each song's own audio on-device (about 2–4 s per track). Nothing leaves your phone. Streamed-only tracks have no readable audio — they resolve over the network or via a calibration ride.")
            }
        }
        .navigationTitle("Analyze library")
        .onAppear {
            vm.load()
            setIdleTimer(disabled: true)
        }
        .onDisappear {
            vm.cancel()
            setIdleTimer(disabled: false)
        }
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

@MainActor
final class AnalyzeLibraryViewModel: ObservableObject {
    enum State { case idle, running, done }

    @Published private(set) var state: State = .idle
    @Published private(set) var totalCount = 0
    @Published private(set) var processed = 0
    @Published private(set) var alreadyCached = 0
    @Published private(set) var analyzed = 0
    @Published private(set) var streamOnly = 0
    @Published private(set) var currentTitle = ""

    private var songs: [ClassSong] = []
    private var task: Task<Void, Never>?

    func load() {
        songs = AppServices.sharedProvider.allSongs()
        totalCount = songs.count
    }

    func start() {
        state = .running
        processed = 0; alreadyCached = 0; analyzed = 0; streamOnly = 0
        let waterfall = AppServices.makeBPMWaterfall()
        task = Task { @MainActor in
            for song in songs {
                if Task.isCancelled { break }
                currentTitle = "\(song.title) — \(song.artist)"
                if waterfall.resolveLocally(title: song.title, artist: song.artist) != nil {
                    alreadyCached += 1
                } else if await AppServices.onDeviceBPM(trackKey: song.trackKey, title: song.title,
                                                        artist: song.artist) != nil {
                    analyzed += 1
                } else {
                    streamOnly += 1
                }
                processed += 1
            }
            state = .done
            currentTitle = ""
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        if state == .running { state = .done }
    }
}
