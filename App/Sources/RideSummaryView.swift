import SwiftUI
import SwiftData
import RhythmCoachCore

/// Stats for one completed ride, shown as a sheet the moment the rider ends a session.
struct RideSummary: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Double
    let songs: Int
    let moves: [String]
    let sprintSeconds: Int
    let formatMinutes: Int?
    /// Whether the ride will be saved to Apple Health when this summary closes (the save is
    /// deferred to the sheet so console-read distance can ride along with the workout).
    let healthLogged: Bool

    var end: Date { date.addingTimeInterval(minutes * 60) }
}

/// Hands a finished ride's summary from the (now-dismissed) live screen to whoever is on screen.
@MainActor
final class SummaryCenter: ObservableObject {
    static let shared = SummaryCenter()
    @Published var pending: RideSummary?
}

struct RideSummaryView: View {
    let summary: RideSummary
    @Environment(\.dismiss) private var dismiss
    @State private var distanceText = ""
    @State private var finalized = false
    @FocusState private var distanceFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Ride complete").font(Theme.black(24))
                Text(summary.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
                if let format = summary.formatMinutes {
                    Text("\(format)-minute class").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)

            HStack(spacing: 14) {
                stat("\(Int(summary.minutes.rounded()))", "minutes")
                stat("\(summary.songs)", "songs")
                stat("\(summary.sprintSeconds / 60):\(String(format: "%02d", summary.sprintSeconds % 60))",
                     "peak effort")
            }

            if !summary.moves.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MOVES RIDDEN").font(Theme.bold(11)).foregroundStyle(.secondary)
                    Text(summary.moves.joined(separator: " · "))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            // Console-read distance (optional): the number off the bike's display, kept with the
            // ride and written into the Apple Health workout.
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(.secondary)
                Text("Distance").font(Theme.bold(14))
                Spacer()
                TextField("from the bike", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($distanceFocused)
                    .frame(width: 110)
                    .accessibilityLabel("Distance in miles")
                Text("mi").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            if summary.healthLogged {
                Label("Saved to Apple Health", systemImage: "heart.fill")
                    .font(.footnote).foregroundStyle(.pink)
            }

            Spacer()

            Button {
                finalize()
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium, .large])
        .onDisappear { finalize() }   // swipe-down dismissal saves too
    }

    /// One-shot: persist distance to the ride's history record and write the Apple Health workout
    /// (deferred to here so the distance sample lands inside the workout).
    private func finalize() {
        guard !finalized else { return }
        finalized = true
        let miles = Double(distanceText.replacingOccurrences(of: ",", with: "."))
        if let miles, miles > 0 {
            let key = summary.date
            let descriptor = FetchDescriptor<RideLogRecord>(predicate: #Predicate { $0.startedAt == key })
            if let record = try? AppServices.context.fetch(descriptor).first {
                record.distanceMiles = miles
                try? AppServices.context.save()
            }
        }
        #if canImport(HealthKit)
        let start = summary.date, end = summary.end
        Task { await HealthLogger.shared.logRide(start: start, end: end, distanceMiles: miles) }
        #endif
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.black(28)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
