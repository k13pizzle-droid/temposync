import SwiftUI
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// Pick which songs from a (possibly huge) playlist are in the running for this class — the planner
/// then builds the arc from your favorites only.
struct SongPickerView: View {
    let songs: [ClassSong]
    @Binding var included: Set<String>
    let provider: PlaylistProvider?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(songs) { song in
                    Button {
                        toggle(song)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: included.contains(song.trackKey)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(included.contains(song.trackKey) ? Color.accentColor : .secondary)
                            thumb(song.trackKey)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(song.bpm.map { "\(Int($0))" } ?? "—")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Choose songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(included.count == songs.count ? "None" : "All") {
                        included = included.count == songs.count ? [] : Set(songs.map { $0.trackKey })
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ song: ClassSong) {
        if included.contains(song.trackKey) {
            included.remove(song.trackKey)
        } else {
            included.insert(song.trackKey)
        }
    }

    @ViewBuilder
    private func thumb(_ trackKey: String) -> some View {
        #if canImport(UIKit)
        ArtworkThumb(trackKey: trackKey, provider: provider)
        #endif
    }
}
