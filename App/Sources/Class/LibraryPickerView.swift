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
    /// Lowercased "title artist" per song, built once — filtering used to re-lowercase every song
    /// on every keystroke AND every selection toggle (body re-eval).
    @State private var haystacks: [String] = []
    @State private var learnedKeys: Set<String> = []
    @State private var selection: Set<String> = []
    @State private var query = ""

    private var filtered: [ClassSong] {
        guard !query.isEmpty else { return allSongs }
        let q = query.lowercased()
        return zip(allSongs, haystacks).filter { $0.1.contains(q) }.map { $0.0 }
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
                            if learnedKeys.contains(song.trackKey) {
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
            haystacks = allSongs.map { "\($0.title.lowercased()) \($0.artist.lowercased())" }
            // One fetch for the badges — a per-row store lookup ran on every body evaluation.
            learnedKeys = Set(AppServices.learnedEnergyIndex().keys)
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
        ArtworkThumb(trackKey: trackKey, provider: provider)
        #endif
    }
}
