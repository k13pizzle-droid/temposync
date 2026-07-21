import SwiftUI
import RoutineKit
import RhythmCoachCore

/// Build a class from a playlist: pick playlist → duration → reorder toggle → preview the arc →
/// start (queues the songs on the system player and opens the live ride).
struct ClassSetupView: View {
    @State private var provider: PlaylistProvider?
    @State private var playlists: [PlaylistSummary] = []
    @State private var selectedPlaylist: PlaylistSummary?
    @State private var songs: [ClassSong] = []
    @State private var format: ClassFormat = .thirty
    @State private var reorder = true
    @State private var plan: ClassPlan?
    @State private var rideStarted = false

    var body: some View {
        List {
            playlistSection
            if selectedPlaylist != nil {
                formatSection
                planSection
            }
        }
        .navigationTitle("Build a class")
        .navigationDestination(isPresented: $rideStarted) {
            modeHView().navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { loadPlaylists() }
    }

    // MARK: Sections

    private var playlistSection: some View {
        Section("Playlist") {
            if playlists.isEmpty {
                Text("No playlists found — build one in the Music app first.")
                    .foregroundStyle(.secondary)
            }
            ForEach(playlists) { playlist in
                Button {
                    select(playlist)
                } label: {
                    HStack {
                        Text(playlist.name)
                        Spacer()
                        Text("\(playlist.songCount) songs").foregroundStyle(.secondary)
                        if selectedPlaylist?.id == playlist.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .tint(.primary)
            }
        }
    }

    private var formatSection: some View {
        Section("Class") {
            Picker("Length", selection: $format) {
                ForEach(ClassFormat.allCases) { f in
                    Text("\(f.minutes) min").tag(f)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Reorder songs to fit the class arc", isOn: $reorder)
        }
        .onChange(of: format) { rebuildPlan() }
        .onChange(of: reorder) { rebuildPlan() }
    }

    @ViewBuilder
    private var planSection: some View {
        if let plan {
            Section {
                ForEach(Array(plan.songs.enumerated()), id: \.element.id) { index, planned in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.song.title).lineLimit(1)
                            Text(planned.song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let bpm = planned.song.bpm {
                            Text("\(Int(bpm))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        roleBadge(planned.role)
                    }
                    // Swipe to drop a song from this class — the plan re-fits around what's left.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removeSong(planned.song)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
                Button {
                    startClass(plan)
                } label: {
                    Label("Start class (\(Int(plan.totalSeconds / 60)) min)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("The ride")
            } footer: {
                Text(plan.reordered
                     ? "Songs reordered to fit the arc — climbs get the slow songs, the anthem takes the final sprint."
                     : "Playlist order respected — roles adapt to your order.")
            }
        }
    }

    private func roleBadge(_ role: SongRole) -> some View {
        Text(role.rawValue.uppercased())
            .font(.caption2).bold()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(roleColor(role).opacity(0.2), in: Capsule())
            .foregroundStyle(roleColor(role))
    }

    private func roleColor(_ role: SongRole) -> Color {
        switch role {
        case .warmup, .cooldown: return .blue
        case .jumps: return .orange
        case .run: return .teal
        case .climb: return .brown
        case .sprint: return .red
        case .recovery: return .indigo
        case .arms: return .purple
        }
    }

    // MARK: Actions

    private func loadPlaylists() {
        let p = makePlaylistProvider()
        provider = p
        playlists = p.playlists()
        // One playlist → no reason to make the rider tap it.
        if playlists.count == 1, selectedPlaylist == nil {
            select(playlists[0])
        }
    }

    private func select(_ playlist: PlaylistSummary) {
        selectedPlaylist = playlist
        songs = provider?.songs(in: playlist.id) ?? []
        resolveBPMs()
        rebuildPlan()
    }

    /// Fill in missing BPMs: seed/cache immediately, API asynchronously (plan refreshes as they land).
    private func resolveBPMs() {
        let waterfall = AppServices.makeBPMWaterfall()
        // Local rungs, synchronous.
        songs = songs.map { song in
            guard song.bpm == nil,
                  let hit = waterfall.resolveLocally(title: song.title, artist: song.artist) else { return song }
            return ClassSong(trackKey: song.trackKey, title: song.title, artist: song.artist,
                             durationSeconds: song.durationSeconds, bpm: hit.bpm)
        }
        // Network rung for the rest.
        for song in songs where song.bpm == nil {
            Task { @MainActor in
                guard let hit = await waterfall.resolve(title: song.title, artist: song.artist) else { return }
                if let idx = songs.firstIndex(where: { $0.trackKey == song.trackKey }) {
                    songs[idx] = ClassSong(trackKey: song.trackKey, title: song.title, artist: song.artist,
                                           durationSeconds: song.durationSeconds, bpm: hit.bpm)
                    rebuildPlan()
                }
            }
        }
    }

    private func rebuildPlan() {
        guard !songs.isEmpty else { plan = nil; return }
        plan = ClassPlanner().plan(songs: songs, format: format, reorder: reorder)
    }

    /// Swipe-remove: excluded for this class only (the playlist itself is untouched).
    private func removeSong(_ song: ClassSong) {
        songs.removeAll { $0.trackKey == song.trackKey }
        rebuildPlan()
    }

    private func startClass(_ plan: ClassPlan) {
        AppServices.activeClassPlan = plan
        provider?.startPlayback(trackKeys: plan.songs.map { $0.song.trackKey })
        rideStarted = true
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
