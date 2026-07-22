import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

@main
struct TempoSyncWidgets: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// The ride on the Lock Screen and in the Dynamic Island: current move, cadence target, countdown.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen banner.
            HStack(spacing: 14) {
                Image(systemName: "figure.indoor.cycle").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    if let countdown = context.state.countdown {
                        Text(countdown).font(.headline.bold()).foregroundStyle(.yellow)
                    }
                    Text(context.state.move).font(.title3.bold()).lineLimit(1)
                    Text("~\(context.state.rpm) RPM · \(context.state.bpm) BPM")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Image(systemName: context.state.resistanceUp ? "dial.high.fill" : "dial.low.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.resistanceUp ? .orange : .secondary)
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.indoor.cycle").font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if let countdown = context.state.countdown {
                            Text(countdown).font(.footnote.bold()).foregroundStyle(.yellow)
                        }
                        Text(context.state.move).font(.headline).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("~\(context.state.rpm)").font(.headline).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "figure.indoor.cycle")
            } compactTrailing: {
                Text("~\(context.state.rpm)").monospacedDigit().font(.caption2)
            } minimal: {
                Image(systemName: "figure.indoor.cycle")
            }
        }
    }
}
#endif
