import SwiftUI

struct TimelineComponent: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    private let hourHeight: CGFloat = 100
    private let startHour = 6
    private let endHour = 23
    
    // Separate all-day events from timed events
    private var allDayEvents: [GoogleCalendarEvent] {
        let filtered = events.filter { $0.isAllDay }
        print("📅 TimelineComponent Debug:")
        print("  Total events: \(events.count)")
        print("  All-day events found: \(filtered.count)")
        for event in events {
            print("  Event: '\(event.summary)' - isAllDay: \(event.isAllDay)")
            print("    Start.date: \(event.start.date?.description ?? "nil")")
            print("    Start.dateTime: \(event.start.dateTime?.description ?? "nil")")
        }
        return filtered
    }
    
    private var timedEvents: [GoogleCalendarEvent] {
        return events.filter { !$0.isAllDay }
    }
    
    init(date: Date, events: [GoogleCalendarEvent], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self.date = date
        self.events = events
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                // All-day events section (only show if there are any)
                if !allDayEvents.isEmpty {
                    allDayEventsSection
                        .padding(.bottom, 8)
                }
                
                // Main timeline with hour grid and timed events
                ZStack(alignment: .topLeading) {
                    // Background grid
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            timeSlot(hour: hour)
                                .frame(height: hourHeight)
                        }
                    }
                    
                    // Timed events overlay
                    ForEach(timedEvents, id: \.id) { event in
                        eventView(for: event)
                    }
                    
                    // Current time line (only show if date is today)
                    if Calendar.current.isDate(date, inSameDayAs: Date()) {
                        currentTimeLine
                    }
                }
            }
        }
        .onAppear {
            startCurrentTimeTimer()
        }
        .onDisappear {
            stopCurrentTimeTimer()
        }
    }
    
    // All-day events section at the top
    private var allDayEventsSection: some View {
        VStack(spacing: 0) {
            // All-day events list
            HStack(spacing: 0) {
                // Time column spacer to align with hour grid
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 60)
                
                // Events column
                VStack(spacing: 4) {
                    ForEach(allDayEvents, id: \.id) { event in
                        allDayEventBlock(event: event)
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.1))
            
            // Divider to separate from timed events
            Divider()
                .background(Color(.systemGray4))
        }
    }
    
    // Individual all-day event block
    private func allDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 8) {
            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(eventColor.opacity(0.1))
        )
        .onTapGesture { onEventTap?(event) }
        .onLongPressGesture { onEventTap?(event) }
    }
    
    private func timeSlot(hour: Int) -> some View {
        HStack(spacing: 0) {
            // Time label
            VStack {
                Text(formatHour(hour))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Spacer()
            }
            
            // Hour line and background
            Rectangle()
                .fill(Color(.systemGray6).opacity(0.3))
                .frame(height: hourHeight - 1)
                .overlay(
                    // Half-hour line
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 0.5)
                        .offset(y: hourHeight / 2)
                )
                .overlay(
                    // Hour line
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 1)
                        .offset(y: -0.5),
                    alignment: .top
                )
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    @ViewBuilder
    private func eventView(for event: GoogleCalendarEvent) -> some View {
        if let startTime = event.startTime,
           let endTime = event.endTime {
            
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            
            if let startHour = startComponents.hour,
               let startMinute = startComponents.minute,
               startHour >= self.startHour && startHour <= self.endHour {
                
                // Calculate position and height
                let topOffset = CGFloat(startHour - self.startHour) * hourHeight + CGFloat(startMinute) * (hourHeight / 60.0)
                let duration = endTime.timeIntervalSince(startTime)
                let durationMinutes = duration / 60.0
                let height = max(30.0, CGFloat(durationMinutes) * (hourHeight / 60.0))
                
                let isPersonal = personalEvents.contains { $0.id == event.id }
                let backgroundColor = isPersonal ? personalColor : professionalColor
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summary)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(height > 40 ? 3 : 2)
                    
                    if height > 40 {
                        Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                    .offset(x: 60, y: topOffset)
                    .padding(.trailing, 8)
                    .onTapGesture { onEventTap?(event) }
                    .onLongPressGesture { onEventTap?(event) }
            }
        }
    }
    
    private var currentTimeLine: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
        
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: 46)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .offset(x: 50)
        }
        .offset(y: yOffset)
        .opacity(hour >= startHour && hour <= endHour ? 1 : 0)
    }
    
    private func startCurrentTimeTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
}

// MARK: - Preview
struct TimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        TimelineComponent(
            date: Date(),
            events: [],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green
        )
        .previewLayout(.sizeThatFits)
    }
} 