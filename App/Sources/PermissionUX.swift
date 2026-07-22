import SwiftUI
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Honest permission states. Silent fallbacks made a denied permission look like an app bug:
/// calibration "listened" to a dead mic and failed every song, and a denied music library quietly
/// served the demo fixture playlist as if it were the user's music.
enum PermissionUX {
    /// True when media-library access is explicitly off (the user can fix it in Settings).
    static var mediaLibraryDenied: Bool {
        #if canImport(MediaPlayer)
        let status = MPMediaLibrary.authorizationStatus()
        return status == .denied || status == .restricted
        #else
        return false
        #endif
    }

    static func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

/// Shared inline explainer row for a denied permission, with the one action that fixes it.
struct PermissionDeniedRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lock.slash")
                .font(Theme.bold(15))
            Text(message)
                .font(Theme.regular(13))
                .foregroundStyle(.secondary)
            Button("Allow in Settings") { PermissionUX.openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}
