import SwiftUI

struct EventsListComponent: View {
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: (GoogleCalendarEvent) -> Void

    private var sortedEvents: [GoogleCalendarEvent] {
        events.sorted { (a, b) in
            let aDate = a.startTime ?? Date.distantPast
            let bDate = b.startTime ?? Date.distantPast
            return aDate < bDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sortedEvents.isEmpty {
                Text("No events today")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(sortedEvents, id: \.id) { ev in
                    Button(action: { onEventTap(ev) }) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(formatEventTime(ev))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 52, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ev.summary)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                if let location = ev.location, !location.isEmpty {
                                    Text(location)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            let isPersonal = personalEvents.contains { $0.id == ev.id }
                            Circle()
                                .fill(isPersonal ? personalColor : professionalColor)
                                .frame(width: 8, height: 8)
                        }
                        .padding(10)
                        .background(
                            (
                                personalEvents.contains { $0.id == ev.id }
                                ? personalColor.opacity(0.12)
                                : professionalColor.opacity(0.12)
                            )
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func formatEventTime(_ ev: GoogleCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = ev.startTime ?? Date()
        if let end = ev.endTime {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }
}


