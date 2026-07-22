import SwiftUI
import SwiftData
import RhythmCoachCore

/// Home: consumer-first. One hero action (build a class), your last class one tap away, quick
/// entries for freestyle/demo, calibration as a feature card, and your riding footprint at the
/// bottom. Settings behind the gear.
/// (RunSync shelved → Shelved/RunSync/. Mic Mode S UI shelved — dormant for calibration.)
struct RootView: View {
    @StateObject private var summaries = SummaryCenter.shared
    @State private var lastSavedClass: SavedClassRecord?
    @State private var lastRide: RideLogRecord?
    @State private var rideAgainStarted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // HERO — the main event.
                    NavigationLink {
                        ClassSetupView()
                    } label: {
                        heroCard(
                            title: "Build a class",
                            subtitle: "Your playlist, coached like a studio ride",
                            icon: "figure.indoor.cycle",
                            colors: [.purple, .indigo]
                        )
                    }

                    // Ride again — the fastest path back to a class you loved.
                    if let saved = lastSavedClass {
                        Button {
                            startSaved(saved)
                        } label: {
                            wideCard(
                                title: saved.name,
                                subtitle: "Ride again · \(saved.formatMinutes) min · \(saved.songCount) songs",
                                icon: "arrow.counterclockwise.circle.fill",
                                colors: [.pink, .red]
                            )
                        }
                    }

                    // Quick actions.
                    HStack(spacing: 14) {
                        NavigationLink {
                            modeHView().navigationBarTitleDisplayMode(.inline)
                        } label: {
                            smallCard(title: "Ride to\nmy music", icon: "music.note", colors: [.teal, .blue])
                        }
                        NavigationLink {
                            LiveCoachView { $0.startDemo() }.navigationBarTitleDisplayMode(.inline)
                        } label: {
                            smallCard(title: "Demo\nride", icon: "play.circle", colors: [.orange, .pink])
                        }
                    }

                    // Calibration — the "make it smarter" feature card.
                    NavigationLink {
                        CalibrationView()
                    } label: {
                        wideCard(
                            title: "Calibrate a playlist",
                            subtitle: "One out-loud listen → real chorus timing forever",
                            icon: "waveform.badge.mic",
                            colors: [.green, .teal]
                        )
                    }

                    // Library row.
                    HStack(spacing: 14) {
                        NavigationLink {
                            SavedClassesView()
                        } label: {
                            listChip(title: "Saved classes", icon: "bookmark.fill")
                        }
                        NavigationLink {
                            RideHistoryView()
                        } label: {
                            listChip(title: "Ride history", icon: "clock.arrow.circlepath")
                        }
                    }

                    // Footprint.
                    if let ride = lastRide {
                        Text("Last ride: \(Int(ride.durationMinutes.rounded())) min · \(ride.songsPlayed) songs · \(ride.startedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("TempoSync")
            .sheet(item: $summaries.pending) { summary in
                RideSummaryView(summary: summary)
            }
            .navigationDestination(isPresented: $rideAgainStarted) {
                modeHView().navigationBarTitleDisplayMode(.inline)
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
            .onAppear { loadShortcuts() }
        }
    }

    // MARK: Cards

    private func heroCard(title: String, subtitle: String, icon: String, colors: [Color]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.bold())
                Text(subtitle).font(.subheadline).opacity(0.85)
            }
            Spacer()
            Image(systemName: icon).font(.system(size: 44))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func wideCard(title: String, subtitle: String, icon: String, colors: [Color]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).opacity(0.6)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors.map { $0.opacity(0.75) },
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func smallCard(title: String, icon: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.subheadline.bold()).multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(LinearGradient(colors: colors.map { $0.opacity(0.8) },
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func listChip(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline)
            Text(title).font(.subheadline.bold())
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Data

    private func loadShortcuts() {
        var savedDescriptor = FetchDescriptor<SavedClassRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        savedDescriptor.fetchLimit = 1
        lastSavedClass = try? AppServices.context.fetch(savedDescriptor).first

        var rideDescriptor = FetchDescriptor<RideLogRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        rideDescriptor.fetchLimit = 1
        lastRide = try? AppServices.context.fetch(rideDescriptor).first
    }

    private func startSaved(_ record: SavedClassRecord) {
        guard let plan = try? record.plan() else { return }
        AppServices.activeClassPlan = plan
        AppServices.sharedProvider.startPlayback(trackKeys: plan.songs.map { $0.song.trackKey })
        rideAgainStarted = true
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
