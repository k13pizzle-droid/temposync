import SwiftUI

@main
struct TempoSyncApp: App {
    /// Launch hooks for automated screenshots / smoke launches (no one to tap through):
    /// TEMPOSYNC_DEMO=1 → straight into the Demo Ride; TEMPOSYNC_MODEH=1 → straight into Mode H.
    private let launchDemo = ProcessInfo.processInfo.environment["TEMPOSYNC_DEMO"] == "1"
    private let launchModeH = ProcessInfo.processInfo.environment["TEMPOSYNC_MODEH"] == "1"
    private let launchClass = ProcessInfo.processInfo.environment["TEMPOSYNC_CLASS"] == "1"
    private let launchCal = ProcessInfo.processInfo.environment["TEMPOSYNC_CAL"] == "1"

    var body: some Scene {
        WindowGroup {
            if launchDemo {
                LiveCoachView { $0.startDemo() }
            } else if launchModeH {
                ModeHLaunchView()
            } else if launchClass {
                NavigationStack { ClassSetupView() }
            } else if launchCal {
                NavigationStack { CalibrationView() }
            } else {
                RootView()
            }
        }
    }
}

/// Direct Mode H entry for the TEMPOSYNC_MODEH launch hook.
private struct ModeHLaunchView: View {
    var body: some View {
        #if canImport(MediaPlayer)
        let source = NowPlayingSourceMP()
        LiveCoachView { $0.startModeH(nowPlaying: source, controls: source,
                                      waterfall: AppServices.makeBPMWaterfall()) }
        #else
        LiveCoachView { $0.startModeH(nowPlaying: PreviewNowPlaying(), controls: nil,
                                      waterfall: AppServices.makeBPMWaterfall()) }
        #endif
    }
}
