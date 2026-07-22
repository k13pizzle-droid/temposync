import SwiftUI
import SwiftData
import RhythmCoachCore

/// Saved classes: name a built class once, re-ride the identical class any time (same songs, same
/// roles, same seeds — learnable, like a real studio class).
struct SavedClassesView: View {
    @State private var records: [SavedClassRecord] = []
    @State private var rideStarted = false

    var body: some View {
        List {
            if records.isEmpty {
                Text("No saved classes yet — build one and tap \"Save this class\".")
                    .foregroundStyle(.secondary)
            }
            ForEach(records, id: \.name) { record in
                Button {
                    start(record)
                } label: {
                    HStack {
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
        makePlaylistProvider().startPlayback(trackKeys: plan.songs.map { $0.song.trackKey })
        rideStarted = true
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
