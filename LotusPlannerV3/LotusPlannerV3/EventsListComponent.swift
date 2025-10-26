import SwiftUI

struct EventsListComponent: View {
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: (GoogleCalendarEvent) -> Void
    let date: Date

    private var sortedEvents: [GoogleCalendarEvent] {
        events.sorted { (a, b) in
            // All-day events always come first
            if a.isAllDay && !b.isAllDay {
                return true
            }
            if !a.isAllDay && b.isAllDay {
                return false
            }
            
            // For events of the same type, sort by time
            let aDate = a.startTime ?? Date.distantPast
            let bDate = b.startTime ?? Date.distantPast
            return aDate < bDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sortedEvents.isEmpty {
                Text("No events")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(sortedEvents.enumerated()), id: \.element.id) { index, ev in
                    // Draw red line above event if current time is before event's end time
                    if shouldShowCurrentTimeLineAbove(event: ev, atIndex: index) {
                        currentTimeLine
                    }
                    
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
                    
                    // Draw red line below event if it's the last event and is completely in the past
                    if shouldShowCurrentTimeLineBelow(event: ev, atIndex: index) {
                        currentTimeLine
                    }
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
    
    // MARK: - Current Time Line Logic
    
    private var currentTimeLine: some View {
        HStack(spacing: 4) {
            Text(currentTimeString)
                .font(.caption2)
                .foregroundColor(.red)
                .fontWeight(.semibold)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
    }
    
    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    private func shouldShowCurrentTimeLineAbove(event: GoogleCalendarEvent, atIndex index: Int) -> Bool {
        // Only show red line if this is the current day
        guard Calendar.current.isDate(date, inSameDayAs: Date()) else {
            return false
        }
        
        let now = Date()
        
        // NEVER show line above all-day events
        if event.isAllDay {
            return false
        }
        
        // Only show line above this event if:
        // 1. Current time is before the event's end time
        // 2. This is the first TIMED event whose end time is after current time
        // 3. All previous events (all-day or timed) have ended or are all-day
        
        guard let endTime = event.endTime else { return false }
        
        // If current time is >= event's end time, don't show line above
        if now >= endTime {
            return false
        }
        
        // Check if all previous events have ended (or are all-day)
        for i in 0..<index {
            let prevEvent = sortedEvents[i]
            
            // Skip all-day events - they don't affect line placement
            if prevEvent.isAllDay {
                continue
            }
            
            // If any previous timed event hasn't ended, don't show line above this event
            if let prevEndTime = prevEvent.endTime, now < prevEndTime {
                return false
            }
        }
        
        return true
    }
    
    private func shouldShowCurrentTimeLineBelow(event: GoogleCalendarEvent, atIndex index: Int) -> Bool {
        // Only show red line if this is the current day
        guard Calendar.current.isDate(date, inSameDayAs: Date()) else {
            return false
        }
        
        let now = Date()
        
        // Only show line below if this is the last event
        guard index == sortedEvents.count - 1 else { return false }
        
        // Special case: If the last event is an all-day event
        if event.isAllDay {
            // Check if there are any timed events in the list
            let hasTimedEvents = sortedEvents.contains { !$0.isAllDay }
            
            // If there are no timed events at all, show the line below the last all-day event
            if !hasTimedEvents {
                return true
            }
            
            // If there are timed events but this all-day is last (shouldn't happen with our sorting),
            // don't show line here
            return false
        }
        
        // For timed events at the end, only show if the event has ended
        guard let endTime = event.endTime else { return false }
        
        return now >= endTime
    }
}


