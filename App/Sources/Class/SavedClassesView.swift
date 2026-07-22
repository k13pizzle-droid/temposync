import SwiftUI
import SwiftData
import RhythmCoachCore

/// Saved classes: name a built class once, re-ride the identical class any time (same songs, same
/// roles, same seeds — learnable, like a real studio class).
struct SavedClassesView: View {
    @State private var records: [SavedClassRecord] = []
    @State private var rideStarted = false
    @State private var renaming: SavedClassRecord?
    @State private var renameText = ""

    var body: some View {
        List {
            if records.isEmpty {
                Text("No saved classes yet. Build one and tap Save this class.")
                    .foregroundStyle(.secondary)
            }
            // Identity by model ID, not name — a rename collision briefly gave two rows the same
            // identity, which is undefined behavior for List.
            ForEach(records, id: \.persistentModelID) { record in
                Button {
                    start(record)
                } label: {
                    HStack(spacing: 12) {
                        collage(record)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.name).font(.headline)
                            Text("\(record.formatMinutes)-min · \(record.songCount) songs · \(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.tint)
                    }
                }
                .tint(.primary)
                .contextMenu {
                    Button {
                        renameText = record.name
                        renaming = record
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button {
                        duplicate(record)
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    AppServices.context.delete(records[index])
                }
                try? AppServices.context.save()
                load()
            }
        }
        .navigationTitle("Saved classes")
        .alert("Rename class", isPresented: Binding(get: { renaming != nil },
                                                    set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let record = renaming {
                    let base = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !base.isEmpty {
                        // Names are unique (saves upsert by name) — renaming onto an existing name
                        // gets the duplicate-style suffix instead of colliding.
                        var name = base
                        var counter = 2
                        while records.contains(where: { $0 !== record && $0.name == name }) {
                            name = "\(base) \(counter)"
                            counter += 1
                        }
                        record.name = name
                        try? AppServices.context.save()
                        load()
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .navigationDestination(isPresented: $rideStarted) {
            liveView().navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { load() }
    }

    private func load() {
        let descriptor = FetchDescriptor<SavedClassRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        records = (try? AppServices.context.fetch(descriptor)) ?? []
    }

    private func start(_ record: SavedClassRecord) {
        guard let plan = try? record.plan() else { return }
        AppServices.activeClassPlan = plan
        AppServices.sharedProvider.startPlayback(trackKeys: plan.songs.map { $0.song.trackKey })
        rideStarted = true
    }

    /// 2×2 artwork collage from the class's first four songs (async cache-backed cells — this used
    /// to decode up to four images synchronously per row per render).
    @ViewBuilder
    private func collage(_ record: SavedClassRecord) -> some View {
        let keys = (try? record.decodedSongs().prefix(4).map { $0.trackKey }) ?? []
        if keys.isEmpty {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note.list").font(.caption).foregroundStyle(.secondary))
        } else {
            let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(0..<4, id: \.self) { i in
                    if i < keys.count {
                        ArtworkThumb(trackKey: keys[i], provider: AppServices.sharedProvider,
                                     size: 21, querySide: 44, cornerRadius: 0)
                    } else {
                        Color.white.opacity(0.06).frame(width: 21, height: 21)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func duplicate(_ record: SavedClassRecord) {
        guard let plan = try? record.plan() else { return }
        var name = record.name + " copy"
        var counter = 2
        while records.contains(where: { $0.name == name }) { name = record.name + " copy \(counter)"; counter += 1 }
        if let copy = try? SavedClassRecord(name: name, plan: plan) {
            AppServices.context.insert(copy)
            try? AppServices.context.save()
            load()
        }
    }

    private func liveView() -> LiveCoachView {
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
