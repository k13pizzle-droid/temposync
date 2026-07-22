import SwiftUI

/// Stats for one completed ride, shown as a sheet the moment the rider ends a session.
struct RideSummary: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Double
    let songs: Int
    let moves: [String]
    let sprintSeconds: Int
    let formatMinutes: Int?
    let healthLogged: Bool
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

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Ride complete").font(.title2.bold())
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
                    Text("MOVES RIDDEN").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(summary.moves.joined(separator: " · "))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            if summary.healthLogged {
                Label("Saved to Apple Health", systemImage: "heart.fill")
                    .font(.footnote).foregroundStyle(.pink)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title, design: .rounded).weight(.heavy)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
