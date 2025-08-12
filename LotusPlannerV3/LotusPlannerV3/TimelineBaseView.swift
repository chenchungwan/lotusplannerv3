import SwiftUI

// MARK: - Timeline Configuration
struct TimelineConfig {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let timeColumnWidth: CGFloat
    let showCurrentTime: Bool
    let showAllDayEvents: Bool
    
    static let `default` = TimelineConfig(
        startHour: 6,
        endHour: 22,
        hourHeight: 80,
        timeColumnWidth: 50,
        showCurrentTime: true,
        showAllDayEvents: true
    )
}

// MARK: - Timeline Base View
struct TimelineBaseView: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let config: TimelineConfig
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    init(
        date: Date,
        events: [GoogleCalendarEvent],
        personalEvents: [GoogleCalendarEvent],
        professionalEvents: [GoogleCalendarEvent],
        personalColor: Color,
        professionalColor: Color,
        config: TimelineConfig = .default,
        onEventTap: ((GoogleCalendarEvent) -> Void)? = nil
    ) {
        self.date = date
        self.events = events
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.config = config
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if config.showAllDayEvents {
                allDayEventsSection
            }
            
            timelineSection
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - All-Day Events Section
    private var allDayEventsSection: some View {
        let allDayEvents = events.filter { $0.isAllDay }
        
        return VStack(spacing: 0) {
            if !allDayEvents.isEmpty {
                HStack(spacing: 0) {
                    // Time column with "All Day" label
                    Text("All Day")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: config.timeColumnWidth)
                        .background(Color(.systemGray6))
                    
                    // All-day events
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(allDayEvents) { event in
                                allDayEventView(event)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
                .frame(height: 40)
                
                Divider()
            }
        }
    }
    
    // MARK: - Timeline Section
    private var timelineSection: some View {
        HStack(spacing: 0) {
            // Time column
            timeColumn
                .frame(width: config.timeColumnWidth)
                .background(Color(.systemGray6))
            
            // Events area
            ZStack(alignment: .topLeading) {
                // Background grid
                timelineGrid
                
                // Events
                ForEach(events.filter { !$0.isAllDay }) { event in
                    timelineEventView(event)
                }
                
                // Current time indicator
                if config.showCurrentTime && Calendar.current.isDate(date, inSameDayAs: Date()) {
                    currentTimeIndicator
                }
            }
        }
    }
    
    // MARK: - Component Views
    private var timeColumn: some View {
        VStack(spacing: 0) {
            ForEach(config.startHour..<config.endHour, id: \.self) { hour in
                VStack {
                    Text(formatHour(hour))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                    
                    Spacer()
                }
                .frame(height: config.hourHeight)
            }
        }
    }
    
    private var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(config.startHour..<config.endHour, id: \.self) { hour in
                VStack(spacing: 0) {
                    // Hour line
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 0.5)
                    
                    // Half-hour line
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 0.5)
                        .offset(y: config.hourHeight / 2)
                    
                    Spacer()
                }
                .frame(height: config.hourHeight)
                .background(Color(.systemBackground))
            }
        }
    }
    
    private func allDayEventView(_ event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.1))
        )
        .onTapGesture {
            onEventTap?(event)
        }
    }
    
    private func timelineEventView(_ event: GoogleCalendarEvent) -> some View {
        guard let startTime = event.startTime,
              let endTime = event.endTime else { return AnyView(EmptyView()) }
        
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        guard let startHour = startComponents.hour,
              let startMinute = startComponents.minute,
              let endHour = endComponents.hour,
              let endMinute = endComponents.minute else { return AnyView(EmptyView()) }
        
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? personalColor : professionalColor
        
        let topOffset = CGFloat(startHour - config.startHour) * config.hourHeight +
                       CGFloat(startMinute) * (config.hourHeight / 60.0)
        
        let duration = endTime.timeIntervalSince(startTime)
        let height = max(20.0, CGFloat(duration / 3600.0) * config.hourHeight)
        
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if height > 40 {
                    Text(formatEventTime(startTime))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(color)
            .cornerRadius(4)
            .offset(y: topOffset)
            .onTapGesture {
                onEventTap?(event)
            }
        )
    }
    
    private var currentTimeIndicator: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour - config.startHour) * config.hourHeight +
                     CGFloat(minute) * (config.hourHeight / 60.0)
        
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .offset(y: yOffset)
    }
    
    // MARK: - Helper Methods
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    private func formatEventTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
    
    private func startTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            currentTime = Date()
        }
        currentTime = Date()
    }
    
    private func stopTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
}
