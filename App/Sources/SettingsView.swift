import SwiftUI
import RhythmCoachCore

/// App settings, off the home screen (gear in the toolbar): tempo-data key override + about info.
struct SettingsView: View {
    @AppStorage(AppServices.apiKeyDefaultsKey) private var apiKey = ""
    @AppStorage(AppServices.effortDefaultsKey) private var effort = "medium"
    @AppStorage(AppServices.skillDefaultsKey) private var skill = 2
    @AppStorage(HealthLogger.defaultsKey) private var healthLogging = false
    @AppStorage(PictogramStyle.defaultsKey) private var bikeStyleRaw = PictogramStyle.spin.rawValue

    var body: some View {
        List {
            Section {
                Picker("Effort", selection: $effort) {
                    Text("Easy").tag("easy")
                    Text("Medium").tag("medium")
                    Text("Hard").tag("hard")
                }
                .pickerStyle(.segmented)
                Picker("Skill level", selection: $skill) {
                    Text("1 · New").tag(1)
                    Text("2 · Regular").tag(2)
                    Text("3 · Advanced").tag(3)
                }
                Picker("Figure style", selection: $bikeStyleRaw) {
                    ForEach(PictogramStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
            } header: {
                Text("Ride")
            } footer: {
                Text("Effort biases how hard the choreography pushes; skill gates the advanced moves (corners unlock at 3). Applies to your next ride.")
            }

            #if canImport(HealthKit)
            Section {
                Toggle("Save rides to Apple Health", isOn: $healthLogging)
                    .onChange(of: healthLogging) { _, on in
                        if on { Task { await HealthLogger.shared.requestAuthorization() } }
                    }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Rides over 2 minutes save as indoor-cycling workouts. Write-only — the app never reads your Health data.")
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
                         ? "Built-in key active — nothing to paste. BPM resolves via Deezer, then GetSongBPM; each song is looked up once, then cached."
                         : "Using your override key instead of the built-in one.")
                    Link("Tempo data by GetSongBPM", destination: URL(string: "https://getsongbpm.com")!)
                }
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
