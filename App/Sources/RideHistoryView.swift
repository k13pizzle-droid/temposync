import SwiftUI
import SwiftData
import RhythmCoachCore

/// Past rides, newest first. Records are written automatically when a session over 2 minutes ends.
struct RideHistoryView: View {
    @State private var rides: [RideLogRecord] = []

    var body: some View {
        List {
            if rides.isEmpty {
                Text("No rides yet. History appears after your first ride over 2 minutes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rides, id: \.startedAt) { ride in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ride.startedAt, style: .date).font(.headline)
                        Spacer()
                        Text(ride.startedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(summaryLine(ride))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ride history")
        .onAppear { load() }
    }

    private func summaryLine(_ ride: RideLogRecord) -> String {
        var parts = ["\(Int(ride.durationMinutes.rounded())) min", "\(ride.songsPlayed) songs"]
        if let miles = ride.distanceMiles, miles > 0 {
            parts.append(String(format: "%.1f mi", miles))
        }
        if let format = ride.formatMinutes {
            parts.append("\(format)-min class" + ((ride.reordered ?? false) ? " · reordered" : ""))
        }
        return parts.joined(separator: " · ")
    }

    private func load() {
        let descriptor = FetchDescriptor<RideLogRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        rides = (try? AppServices.context.fetch(descriptor)) ?? []
    }
}
