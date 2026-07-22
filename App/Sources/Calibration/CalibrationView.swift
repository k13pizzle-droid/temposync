import SwiftUI
import RhythmCoachCore
#if canImport(UIKit)
import UIKit
#endif

/// Calibration ride: play a playlist out loud once, the app learns each song's real structure.
/// After calibration, classes on that playlist show "learned map" and get hard countdowns with
/// true chorus timing.
struct CalibrationView: View {
    @StateObject private var vm = CalibrationViewModel()
    @State private var provider: PlaylistProvider?
    @State private var playlists: [PlaylistSummary] = []
    @State private var selectedPlaylist: PlaylistSummary?
    @State private var songs: [ClassSong] = []

    var body: some View {
        List {
            if vm.micDenied {
                Section {
                    PermissionDeniedRow(
                        title: "Microphone access is off",
                        message: "Calibration listens to one out-loud playthrough to learn each song's real structure. Nothing is recorded or kept. Allow the microphone to run a calibration ride."
                    )
                }
            }
            if PermissionUX.mediaLibraryDenied {
                Section {
                    PermissionDeniedRow(
                        title: "Music library access is off",
                        message: "Calibration plays a playlist from your library. Allow music access to pick one."
                    )
                }
            }
            if !vm.isRunning && !vm.isComplete && !PermissionUX.mediaLibraryDenied {
                Section {
                    ForEach(playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                            songs = provider?.songs(in: playlist.id) ?? []
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
                } header: {
                    Text("Playlist")
                } footer: {
                    Text("Play through once with the sound out loud, from the phone speaker or a speaker nearby. The app listens and learns each song's real structure: drops, choruses, builds. One pass per playlist, stored for good.")
                }

                if selectedPlaylist != nil {
                    Section {
                        Button {
                            startCalibration()
                        } label: {
                            Label("Start calibration ride", systemImage: "waveform.badge.mic")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            if vm.isRunning || vm.isComplete {
                Section {
                    ForEach(vm.songs) { song in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            stateBadge(vm.states[song.trackKey] ?? .pending)
                        }
                    }
                } header: {
                    Text(vm.statusLine)
                }

                if vm.isRunning {
                    Section {
                        Button(role: .destructive) { vm.stop() } label: {
                            Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .navigationTitle("Calibrate")
        .onAppear {
            let p = makePlaylistProvider()
            provider = p
            playlists = p.playlists()
            if playlists.count == 1 { selectedPlaylist = playlists[0]; songs = p.songs(in: playlists[0].id) }
            setIdleTimer(disabled: true)
        }
        .onDisappear {
            vm.stop()
            setIdleTimer(disabled: false)
        }
    }

    @ViewBuilder
    private func stateBadge(_ state: CalibrationViewModel.SongState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .listening:
            Image(systemName: "waveform").foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .learned(let quality):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(Int(quality * 100))%").font(.caption).foregroundStyle(.secondary)
            }
        case .skipped(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func startCalibration() {
        guard let provider else { return }
        #if canImport(MediaPlayer)
        let nowPlaying = NowPlayingSourceMP()
        #else
        let nowPlaying = PreviewNowPlaying()
        #endif
        vm.start(songs: songs, provider: provider, nowPlaying: nowPlaying, mic: MicAudioSourceAV())
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
