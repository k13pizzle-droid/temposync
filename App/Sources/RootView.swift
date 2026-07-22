import SwiftUI
import RhythmCoachCore

/// Entry: Rhythm Coach, headphones-first. Settings live behind the toolbar gear.
/// (RunSync shelved 2026-07-21 → Shelved/RunSync/. Mode S (mic) UI shelved same day per round-2
/// feedback — the code stays dormant in LiveCoachViewModel for the future "calibration ride".)
struct RootView: View {
    @StateObject private var summaries = SummaryCenter.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Rhythm Coach") {
                    NavigationLink("Build a class") {
                        ClassSetupView()
                    }
                    NavigationLink("Ride to my music") {
                        modeHView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    NavigationLink("Demo ride") {
                        LiveCoachView { $0.startDemo() }
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                Section {
                    NavigationLink {
                        CalibrationView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calibrate a playlist")
                            Text("One out-loud listen → real chorus timing forever")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink("Saved classes") { SavedClassesView() }
                    NavigationLink("Ride history") { RideHistoryView() }
                }
            }
            .navigationTitle("TempoSync")
            .sheet(item: $summaries.pending) { summary in
                RideSummaryView(summary: summary)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private func modeHView() -> LiveCoachView {
        #if canImport(MediaPlayer)
        let source = NowPlayingSourceMP()
        return LiveCoachView { $0.startModeH(nowPlaying: source, controls: source,
                                             waterfall: AppServices.makeBPMWaterfall()) }
        #else
        return LiveCoachView { $0.startModeH(nowPlaying: PreviewNowPlaying(), controls: nil,
                                             waterfall: AppServices.makeBPMWaterfall()) }
        #endif
    }
}

/// Fallback for platforms without MediaPlayer (keeps previews/compilation happy).
final class PreviewNowPlaying: NowPlayingSource, @unchecked Sendable {
    var nowPlaying: NowPlayingInfo? {
        NowPlayingInfo(trackKey: "preview", title: "Preview Track", artist: "TempoSync", durationSeconds: 210)
    }
    func currentTime() -> Double { 0 }
    func isPlaying() -> Bool { true }
}

#Preview {
    RootView()
}
