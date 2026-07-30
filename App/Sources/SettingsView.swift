import SwiftUI
import RhythmCoachCore

/// App settings, off the home screen (gear in the toolbar): tempo-data key override + about info.
struct SettingsView: View {
    @AppStorage(AppServices.apiKeyDefaultsKey) private var apiKey = ""
    @AppStorage(ClassDifficulty.defaultsKey) private var difficultyRaw = ClassDifficulty.medium.rawValue
    @AppStorage(HealthLogger.defaultsKey) private var healthLogging = false
    @State private var healthDenied = false
    @AppStorage(PictogramStyle.defaultsKey) private var bikeStyleRaw = PictogramStyle.spin.rawValue
    @AppStorage(Theme.accentDefaultsKey) private var accentID = "pulse"
    @AppStorage(WatchCueSender.enabledDefaultsKey) private var watchCues = true
    @AppStorage(VoiceCoach.defaultsKey) private var voiceCues = false

    var body: some View {
        List {
            Section {
                DifficultyDial(difficulty: Binding(
                    get: { ClassDifficulty(rawValue: difficultyRaw) ?? .medium },
                    set: { difficultyRaw = $0.rawValue }
                ))
                Picker("Figure style", selection: $bikeStyleRaw) {
                    ForEach(PictogramStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                Toggle("Voice cues (ducks the music)", isOn: $voiceCues)
                Toggle("Apple Watch cues", isOn: $watchCues)
                HStack {
                    Text("Accent")
                    Spacer()
                    ForEach(Theme.accents) { accent in
                        Button {
                            accentID = accent.id
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white, lineWidth: accentID == accent.id ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(accent.name) accent"))
                        .accessibilityAddTraits(accentID == accent.id ? [.isSelected] : [])
                    }
                }
            } header: {
                Text("Ride")
            } footer: {
                Text("Your default difficulty. One dial sets both the effort and which moves unlock; Super Hard opens the full vocabulary. Every class setup can override it.")
            }

            #if canImport(HealthKit)
            Section {
                Toggle("Save rides to Apple Health", isOn: $healthLogging)
                    .onChange(of: healthLogging) { _, on in
                        guard on else { healthDenied = false; return }
                        // Honest toggle: if the permission prompt is declined, flip back off and
                        // say why, instead of silently staying on and never saving anything.
                        Task {
                            await HealthLogger.shared.requestAuthorization()
                            if !HealthLogger.shared.workoutWriteAuthorized {
                                healthLogging = false
                                healthDenied = true
                            } else {
                                healthDenied = false
                            }
                        }
                    }
            } header: {
                Text("Apple Health")
            } footer: {
                Text(healthDenied
                     ? "Health access is off for TempoSync. Allow Workouts and Cycling Distance under Settings → Health → Data Access & Devices → TempoSync, then try again."
                     : "Rides over 2 minutes save as indoor cycling workouts, with the distance you enter on the ride summary. Write only: the app never reads your Health data.")
            }
            #endif

            Section {
                SecureField("GetSongBPM API key (override)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Tempo data")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(apiKey.isEmpty
                         ? "Built-in key active, nothing to paste. BPM resolves via Deezer, then GetSongBPM; each song is looked up once, then cached."
                         : "Using your override key instead of the built-in one.")
                    Link("Tempo data by GetSongBPM", destination: URL(string: "https://getsongbpm.com")!)
                }
            }

            Section {
                NavigationLink {
                    AnalyzeLibraryView()
                } label: {
                    Label("Analyze my library", systemImage: "waveform.badge.magnifyingglass")
                }
            } footer: {
                Text("One pass measures every downloaded song from its own audio, so class building becomes instant and offline.")
            }

            Section {
                LabeledContent("Core", value: RhythmCoachCore.version)
            } header: {
                Text("About")
            } footer: {
                Text("All processing runs on-device. Raw audio is never recorded or uploaded.")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
