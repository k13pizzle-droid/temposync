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
    @State private var ridesThisWeek = 0
    @State private var streakWeeks = 0
    @State private var rideAgainStarted = false
    @AppStorage(OnboardingView.defaultsKey) private var onboarded = false
    @AppStorage(WatchCueSender.enabledDefaultsKey) private var watchCues = true
    @State private var showOnboarding = false

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
                            subtitle: "Listen once out loud, keep the timing for good",
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

                    // Weekly progress and streak.
                    if ridesThisWeek > 0 || streakWeeks > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("This week: \(ridesThisWeek) of 3 rides").font(Theme.bold(14))
                                ProgressView(value: Double(min(ridesThisWeek, 3)), total: 3)
                                    .tint(.orange)
                            }
                            if streakWeeks > 1 {
                                Spacer()
                                Text("\(streakWeeks)-week streak")
                                    .font(Theme.bold(12)).foregroundStyle(.orange)
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }

                    // Footprint.
                    if let ride = lastRide {
                        Text("Last ride: \(Int(ride.durationMinutes.rounded())) min · \(ride.songsPlayed) songs · \(ride.startedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: 640)                    // iPad: keep the cards readable
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("TempoSync")
            .sheet(item: $summaries.pending) { summary in
                RideSummaryView(summary: summary)
            }
            .navigationDestination(isPresented: $rideAgainStarted) {
                modeHView().navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                #if canImport(WatchConnectivity)
                if WatchCueSender.shared.isPaired {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            watchCues.toggle()
                        } label: {
                            Image(systemName: watchCues ? "applewatch" : "applewatch.slash")
                                .foregroundStyle(watchCues ? Color.accentColor : .secondary)
                        }
                    }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                loadShortcuts()
                if !onboarded { showOnboarding = true }
            }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
        }
    }

    // MARK: Cards

    private func heroCard(title: String, subtitle: String, icon: String, colors: [Color]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.black(27))
                Text(subtitle).font(Theme.regular(14)).opacity(0.85)
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
                Text(title).font(Theme.bold(16)).lineLimit(1)
                Text(subtitle).font(Theme.regular(12)).opacity(0.85)
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
            Text(title).font(Theme.bold(14)).multilineTextAlignment(.leading)
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
            Text(title).font(Theme.bold(14))
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

        let rideDescriptor = FetchDescriptor<RideLogRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let rides = (try? AppServices.context.fetch(rideDescriptor)) ?? []
        lastRide = rides.first

        // Weekly count plus consecutive-week streak.
        let calendar = Calendar.current
        let now = Date.now
        ridesThisWeek = rides.filter { calendar.isDate($0.startedAt, equalTo: now, toGranularity: .weekOfYear) }.count
        var streak = 0
        var reference = now
        while rides.contains(where: { calendar.isDate($0.startedAt, equalTo: reference, toGranularity: .weekOfYear) }) {
            streak += 1
            reference = calendar.date(byAdding: .weekOfYear, value: -1, to: reference) ?? reference
        }
        streakWeeks = streak
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
