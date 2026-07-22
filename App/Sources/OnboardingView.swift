import SwiftUI

/// First-launch explainer: what the app does, what it'll ask for, and the two power moves
/// (library analysis + calibration). Three swipes, one button.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    static let defaultsKey = "onboarded_v1"

    var body: some View {
        TabView {
            page(icon: "figure.indoor.cycle",
                 title: "Your music.\nYour instructor.",
                 text: "TempoSync turns any playlist into a coached spin class — moves, sprints, and recovery choreographed to every song's beat, right on your handlebars.")
            page(icon: "music.note.list",
                 title: "It needs two things",
                 text: "Access to Apple Music (to see what's playing and queue your class) — and nothing else. All analysis runs on your phone. Nothing is recorded or uploaded, ever.")
            VStack(spacing: 24) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 64)).foregroundStyle(.tint)
                Text("Two power moves").font(.title.bold()).multilineTextAlignment(.center)
                Text("**Analyze my library** (Settings) measures every downloaded song's BPM from its own audio.\n\n**Calibrate a playlist** listens to one out-loud playthrough and learns each song's real drops and choruses — forever.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    UserDefaults.standard.set(true, forKey: Self.defaultsKey)
                    dismiss()
                } label: {
                    Text("Let's ride").font(.headline).frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
        .tabViewStyle(.page)
        .interactiveDismissDisabled()
    }

    private func page(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.tint)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
