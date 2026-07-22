import SwiftUI
import SwiftData
import RoutineKit
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// Build a class from a playlist: pick playlist → duration → reorder toggle → preview the arc →
/// start (queues the songs on the system player and opens the live ride).
struct ClassSetupView: View {
    @State private var provider: PlaylistProvider?
    @State private var playlists: [PlaylistSummary] = []
    @State private var selectedPlaylist: PlaylistSummary?
    @State private var songs: [ClassSong] = []
    @State private var includedKeys: Set<String> = []
    @State private var showingSongPicker = false
    @State private var showingLibraryPicker = false
    @State private var customSource = false
    @State private var format: ClassFormat = .thirty
    @State private var reorder = true
    @State private var plan: ClassPlan?
    @State private var roleOverrides: [String: SongRole] = [:]
    @State private var rideStarted = false
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var savedToast: String?
    @State private var difficulty: ClassDifficulty = AppServices.difficulty
    @State private var style: ClassStyle = .standard
    @State private var learnedKeys: Set<String> = []

    /// The plan with any manual role overrides applied — what actually rides.
    private var effectivePlan: ClassPlan? {
        guard let plan else { return nil }
        guard !roleOverrides.isEmpty else { return plan }
        let adjusted = plan.songs.map { planned in
            roleOverrides[planned.song.trackKey].map { PlannedSong(song: planned.song, role: $0) } ?? planned
        }
        return ClassPlan(format: plan.format, songs: adjusted, reordered: plan.reordered)
    }

    var body: some View {
        List {
            playlistSection
            if !songs.isEmpty {
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
        Section("Music") {
            Button {
                showingLibraryPicker = true
            } label: {
                HStack {
                    Label("Pick from my library", systemImage: "magnifyingglass")
                    Spacer()
                    if customSource {
                        Text("\(songs.count) songs").foregroundStyle(.secondary)
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .tint(.primary)
            if playlists.isEmpty && !customSource {
                Text("No playlists found. Search your library above, or build a playlist in the Music app.")
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

    private static let templates: [(name: String, icon: String, style: ClassStyle, difficulty: ClassDifficulty)] = [
        ("Classic", "figure.indoor.cycle", .standard, .medium),
        ("Intervals", "bolt.fill", .intervals, .difficult),
        ("Climb day", "mountain.2.fill", .climbs, .difficult),
        ("Recovery", "wind", .recovery, .superEasy),
    ]

    private var formatSection: some View {
        Section("Class") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.templates, id: \.name) { template in
                        Button {
                            style = template.style
                            difficulty = template.difficulty
                            AppServices.difficultyOverride = template.difficulty
                            rebuildPlan()
                        } label: {
                            Label(template.name, systemImage: template.icon)
                                .font(Theme.bold(13))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(style == template.style ? Color.accentColor.opacity(0.25)
                                            : Color.white.opacity(0.08),
                                            in: Capsule())
                                .foregroundStyle(style == template.style ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Picker("Length", selection: $format) {
                ForEach(ClassFormat.allCases) { f in
                    Text("\(f.minutes) min").tag(f)
                }
            }
            .pickerStyle(.segmented)
            DifficultyDial(difficulty: $difficulty)
                .onChange(of: difficulty) { AppServices.difficultyOverride = difficulty }
            Toggle("Reorder songs to fit the class arc", isOn: $reorder)
            Button {
                showingSongPicker = true
            } label: {
                HStack {
                    Label("Choose songs", systemImage: "checklist")
                    Spacer()
                    Text("\(includedKeys.count) of \(songs.count)").foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
        .onChange(of: format) { rebuildPlan() }
        .onChange(of: reorder) { rebuildPlan() }
        .sheet(isPresented: $showingSongPicker, onDismiss: { rebuildPlan() }) {
            SongPickerView(songs: songs, included: $includedKeys, provider: provider)
        }
        .sheet(isPresented: $showingLibraryPicker) {
            LibraryPickerView(provider: provider,
                              initialSelection: customSource ? includedKeys : []) { chosen in
                customSource = true
                selectedPlaylist = nil
                songs = chosen
                includedKeys = Set(chosen.map { $0.trackKey })
                resolveBPMs()
                rebuildPlan()
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if let plan = effectivePlan {
            Section {
                ForEach(Array(plan.songs.enumerated()), id: \.element.id) { index, planned in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 20)
                        artworkThumb(planned.song.trackKey)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.song.title).lineLimit(1)
                            Text(planned.song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if learnedKeys.contains(planned.song.trackKey) {
                            Image(systemName: "waveform.badge.checkmark")
                                .font(.system(size: 11)).foregroundStyle(.green)
                        }
                        Spacer()
                        Text(planned.song.bpm.map { "\(Int($0))" } ?? "—")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
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
                    // Long-press to override this song's role in the arc.
                    .contextMenu {
                        Picker("Role", selection: Binding(
                            get: { roleOverrides[planned.song.trackKey] ?? planned.role },
                            set: { roleOverrides[planned.song.trackKey] = $0 }
                        )) {
                            ForEach(SongRole.allCases, id: \.self) { role in
                                Text(role.rawValue.capitalized).tag(role)
                            }
                        }
                        if roleOverrides[planned.song.trackKey] != nil {
                            Button("Reset to auto") {
                                roleOverrides.removeValue(forKey: planned.song.trackKey)
                            }
                        }
                    }
                }
                .onMove { from, to in moveSongs(from: from, to: to) }

                NavigationLink {
                    RideStoryboardView(plan: plan)
                } label: {
                    Label("Preview the whole ride", systemImage: "list.bullet.rectangle")
                }
                Button {
                    startClass(plan)
                } label: {
                    Label("Start class (\(Int(plan.totalSeconds / 60)) min)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    saveName = selectedPlaylist.map { "\($0.name) · \(format.minutes) min" } ?? ""
                    showingSave = true
                } label: {
                    Label(savedToast ?? "Save this class", systemImage: savedToast == nil ? "bookmark" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .alert("Name this class", isPresented: $showingSave) {
                    TextField("Name", text: $saveName)
                    Button("Save") { saveClass(plan) }
                    Button("Cancel", role: .cancel) {}
                }
            } header: {
                HStack {
                    Text("The ride")
                    Spacer()
                    EditButton()   // enables drag-to-reorder handles
                }
            } footer: {
                Text(plan.reordered
                     ? "Songs reordered to fit the arc. Climbs get the slow songs; the anthem takes the final sprint."
                     : "Playlist order respected. Roles adapt to your order.")
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
        customSource = false
        selectedPlaylist = playlist
        songs = provider?.songs(in: playlist.id) ?? []
        includedKeys = Set(songs.map { $0.trackKey })
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
        // In-house analysis of each track's own audio first (no network); API rungs only for
        // streamed-only tracks. Results cache forever either way.
        for song in songs where song.bpm == nil {
            Task { @MainActor in
                var bpm = await AppServices.onDeviceBPM(trackKey: song.trackKey, title: song.title,
                                                        artist: song.artist)
                if bpm == nil {
                    bpm = await waterfall.resolve(title: song.title, artist: song.artist)?.bpm
                }
                guard let bpm, let idx = songs.firstIndex(where: { $0.trackKey == song.trackKey }) else { return }
                songs[idx] = ClassSong(trackKey: song.trackKey, title: song.title, artist: song.artist,
                                       durationSeconds: song.durationSeconds, bpm: bpm)
                rebuildPlan()
            }
        }
    }

    private var includedSongs: [ClassSong] { songs.filter { includedKeys.contains($0.trackKey) } }

    private func rebuildPlan() {
        // Enrich with learned data: measured energy sharpens role fitting; badges show coverage.
        learnedKeys = Set(songs.map { $0.trackKey }.filter { AppServices.hasLearnedMap($0) })
        let pool = includedSongs.map { song in
            ClassSong(trackKey: song.trackKey, title: song.title, artist: song.artist,
                      durationSeconds: song.durationSeconds, bpm: song.bpm,
                      energy: AppServices.learnedEnergy(song.trackKey))
        }
        guard pool.count >= 2 else { plan = nil; return }
        plan = ClassPlanner().plan(songs: pool, format: format, reorder: reorder, style: style)
    }

    /// Swipe-remove: excluded for this class only (the playlist itself is untouched).
    private func removeSong(_ song: ClassSong) {
        includedKeys.remove(song.trackKey)
        rebuildPlan()
    }

    /// Drag-to-reorder: the rider takes manual control — auto-reorder switches off and the arc's
    /// roles map onto the order they chose.
    private func moveSongs(from source: IndexSet, to destination: Int) {
        guard let current = effectivePlan else { return }
        var ordered = current.songs.map { $0.song }
        ordered.move(fromOffsets: source, toOffset: destination)
        // Manual order wins: respect it (plus any songs not in the plan stay available at the end).
        let planKeys = Set(ordered.map { $0.trackKey })
        songs = ordered + songs.filter { !planKeys.contains($0.trackKey) }
        reorder = false
        rebuildPlan()
    }

    private func startClass(_ plan: ClassPlan) {
        AppServices.difficultyOverride = difficulty
        AppServices.activeClassPlan = plan
        provider?.startPlayback(trackKeys: plan.songs.map { $0.song.trackKey })
        rideStarted = true
    }

    @ViewBuilder
    private func artworkThumb(_ trackKey: String) -> some View {
        #if canImport(UIKit)
        if let image = provider?.artwork(for: trackKey, side: 72) {
            Image(uiImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.08))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary))
        }
        #endif
    }

    /// Upsert by name: re-saving a class with the same name replaces it.
    private func saveClass(_ plan: ClassPlan) {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let descriptor = FetchDescriptor<SavedClassRecord>(predicate: #Predicate { $0.name == name })
        if let existing = try? AppServices.context.fetch(descriptor).first {
            AppServices.context.delete(existing)
        }
        if let record = try? SavedClassRecord(name: name, plan: plan) {
            AppServices.context.insert(record)
            try? AppServices.context.save()
            savedToast = "Saved \"\(name)\""
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
