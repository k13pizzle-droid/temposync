import SwiftUI
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// Search the ENTIRE library and hand-pick the songs a class is built from. No playlist required:
/// this is the "build my dream class from scratch" path.
struct LibraryPickerView: View {
    let provider: PlaylistProvider?
    let initialSelection: Set<String>
    let onConfirm: ([ClassSong]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allSongs: [ClassSong] = []
    @State private var selection: Set<String> = []
    @State private var query = ""

    private var filtered: [ClassSong] {
        guard !query.isEmpty else { return allSongs }
        let q = query.lowercased()
        return allSongs.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if allSongs.isEmpty {
                    Text("Your library looks empty. Download some music in the Music app first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { song in
                    Button {
                        toggle(song)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.contains(song.trackKey)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection.contains(song.trackKey)
                                                 ? Color.accentColor : .secondary)
                            thumb(song.trackKey)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                Text(song.artist).font(Theme.regular(12))
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if AppServices.hasLearnedMap(song.trackKey) {
                                Image(systemName: "waveform.badge.checkmark")
                                    .font(.system(size: 11)).foregroundStyle(.green)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $query, prompt: "Search songs or artists")
            .navigationTitle("My library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use \(selection.count)") {
                        let chosen = allSongs.filter { selection.contains($0.trackKey) }
                        onConfirm(chosen)
                        dismiss()
                    }
                    .bold()
                    .disabled(selection.count < 2)
                }
            }
        }
        .onAppear {
            allSongs = provider?.allSongs() ?? []
            selection = initialSelection
        }
    }

    private func toggle(_ song: ClassSong) {
        if selection.contains(song.trackKey) {
            selection.remove(song.trackKey)
        } else {
            selection.insert(song.trackKey)
        }
    }

    @ViewBuilder
    private func thumb(_ trackKey: String) -> some View {
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
}
