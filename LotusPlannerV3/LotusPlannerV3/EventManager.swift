import SwiftUI

// MARK: - Event Filter Options
struct EventFilterOptions {
    var hideRecurringEvents: Bool = false
    var includeAllDayEvents: Bool = true
    var includeTimedEvents: Bool = true
    var startHour: Int? = nil
    var endHour: Int? = nil
}

// MARK: - Event Range Type
enum EventRangeType {
    case day(Date)
    case week(Date)
    case month(Date)
    case custom(start: Date, end: Date)
    
    var dateInterval: DateInterval? {
        let calendar = Calendar.mondayFirst
        switch self {
        case .day(let date):
            return calendar.dateInterval(of: .day, for: date)
        case .week(let date):
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month(let date):
            return calendar.dateInterval(of: .month, for: date)
        case .custom(let start, let end):
            return DateInterval(start: start, end: end)
        }
    }
}

// MARK: - Event Manager
@MainActor
class EventManager: ObservableObject {
    static let shared = EventManager()
    
    // MARK: - Properties
    @Published private var personalEvents: [GoogleCalendarEvent] = []
    @Published private var professionalEvents: [GoogleCalendarEvent] = []
    @Published private var eventCache: [String: [GoogleCalendarEvent]] = [:]
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Fetches events for a specific date range
    /// - Parameters:
    ///   - range: The date range to fetch events for
    ///   - options: Optional filtering options
    /// - Returns: A dictionary of dates mapped to their events
    func getEvents(for range: EventRangeType, options: EventFilterOptions = EventFilterOptions()) async -> [Date: [GoogleCalendarEvent]] {
        guard let interval = range.dateInterval else { return [:] }
        
        // DEBUG: Print range information
        if case .week(_) = range {
            print("📅 EventManager.getEvents for week:")
            print("  Interval: \(interval.start) to \(interval.end)")
            print("  Duration: \(interval.duration / (24*3600)) days")
        }
        
        // Check cache first
        let cacheKey = generateCacheKey(for: range, options: options)
        if let cachedEvents = eventCache[cacheKey] {
            let grouped = groupEventsByDate(cachedEvents, in: interval)
            if case .week(_) = range {
                print("  Using cached events: \(cachedEvents.count) total, grouped into \(grouped.count) days")
            }
            return grouped
        }
        
        // Load events if needed
        await loadEventsIfNeeded(for: interval)
        
        // Filter and process events
        let events = filterEvents(in: interval, options: options)
        
        // Cache the results
        eventCache[cacheKey] = events
        
        // Group by date and return
        let grouped = groupEventsByDate(events, in: interval)
        if case .week(_) = range {
            print("  Loaded fresh events: \(events.count) total, grouped into \(grouped.count) days")
        }
        return grouped
    }
    
    /// Gets all events for a specific date
    /// - Parameters:
    ///   - date: The date to get events for
    ///   - options: Optional filtering options
    /// - Returns: Array of events for the specified date
    func getEventsForDate(_ date: Date, options: EventFilterOptions = EventFilterOptions()) async -> [GoogleCalendarEvent] {
        let events = await getEvents(for: .day(date), options: options)
        // FIX: Use mondayFirst calendar to match other calendar views
        return events[Calendar.mondayFirst.startOfDay(for: date)] ?? []
    }
    
    /// Gets all personal events within a date range
    func getPersonalEvents(for range: EventRangeType, options: EventFilterOptions = EventFilterOptions()) async -> [GoogleCalendarEvent] {
        let events = await getEvents(for: range, options: options)
        return events.values.flatMap { $0 }.filter { isPersonalEvent($0) }
    }
    
    /// Gets all professional events within a date range
    func getProfessionalEvents(for range: EventRangeType, options: EventFilterOptions = EventFilterOptions()) async -> [GoogleCalendarEvent] {
        let events = await getEvents(for: range, options: options)
        return events.values.flatMap { $0 }.filter { !isPersonalEvent($0) }
    }
    
    /// Checks if an event is likely recurring based on its pattern
    func isEventRecurring(_ event: GoogleCalendarEvent) -> Bool {
        // Check if this event appears multiple times in our dataset
        let allEvents = personalEvents + professionalEvents
        let matchingEvents = allEvents.filter { $0.summary == event.summary }
        
        if matchingEvents.count > 1 {
            // If we find multiple events with the same title, check their timing pattern
            let sortedEvents = matchingEvents.compactMap { $0.startTime }.sorted()
            if sortedEvents.count >= 2 {
                // Calculate time intervals between consecutive occurrences
                let intervals = zip(sortedEvents, sortedEvents.dropFirst()).map { $0.1.timeIntervalSince($0.0) }
                
                // Check if intervals are consistent (within a small margin)
                if let firstInterval = intervals.first {
                    let isConsistent = intervals.allSatisfy { abs($0 - firstInterval) < 3600 } // 1 hour tolerance
                    if isConsistent {
                        // Check if interval matches common recurring patterns (daily, weekly, monthly)
                        let dayInterval: TimeInterval = 24 * 3600
                        let weekInterval: TimeInterval = 7 * dayInterval
                        let approximateMonthInterval: TimeInterval = 30 * dayInterval
                        
                        let commonIntervals = [dayInterval, weekInterval, approximateMonthInterval]
                        return commonIntervals.contains { abs(firstInterval - $0) < dayInterval }
                    }
                }
            }
        }
        
        return false
    }
    
    /// Invalidates the cache for a specific range
    func invalidateCache(for range: EventRangeType? = nil) {
        if let range = range {
            let key = generateCacheKey(for: range, options: EventFilterOptions())
            eventCache.removeValue(forKey: key)
        } else {
            eventCache.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadEventsIfNeeded(for interval: DateInterval) async {
        // Check if we need to load more events  
        let calendar = Calendar.mondayFirst // FIX: Use consistent calendar
        let buffer = TimeInterval(14 * 24 * 3600) // 2 week buffer for better caching
        
        let extendedStart = interval.start.addingTimeInterval(-buffer)
        let extendedEnd = interval.end.addingTimeInterval(buffer)
        
        // PERFORMANCE OPTIMIZATION: More intelligent cache checking
        let extendedInterval = DateInterval(start: extendedStart, end: extendedEnd)
        
        // Check if we have sufficient coverage for both account types
        let needsPersonalReload = needsEventReload(for: extendedInterval, accountType: .personal)
        let needsProfessionalReload = needsEventReload(for: extendedInterval, accountType: .professional)
        
        if needsPersonalReload || needsProfessionalReload {
            await loadEvents(from: extendedStart, to: extendedEnd, 
                           loadPersonal: needsPersonalReload, 
                           loadProfessional: needsProfessionalReload)
        }
    }
    
    private func needsEventReload(for interval: DateInterval) -> Bool {
        let allEvents = personalEvents + professionalEvents
        guard !allEvents.isEmpty else { return true }
        
        // Check if we have events covering the entire interval
        let eventDates = allEvents.compactMap { $0.startTime }
        guard let earliestEvent = eventDates.min(),
              let latestEvent = eventDates.max() else { return true }
        
        return earliestEvent > interval.start || latestEvent < interval.end
    }
    
    // PERFORMANCE OPTIMIZATION: Account-specific reload checking
    private func needsEventReload(for interval: DateInterval, accountType: GoogleAuthManager.AccountKind) -> Bool {
        let accountEvents = accountType == .personal ? personalEvents : professionalEvents
        guard !accountEvents.isEmpty else { return true }
        
        // Check if we have events covering the entire interval for this account
        let eventDates = accountEvents.compactMap { $0.startTime }
        guard let earliestEvent = eventDates.min(),
              let latestEvent = eventDates.max() else { return true }
        
        return earliestEvent > interval.start || latestEvent < interval.end
    }
    
    private func loadEvents(from startDate: Date, to endDate: Date) async {
        await loadEvents(from: startDate, to: endDate, loadPersonal: true, loadProfessional: true)
    }
    
    // PERFORMANCE OPTIMIZATION: Selective account loading
    private func loadEvents(from startDate: Date, to endDate: Date, loadPersonal: Bool, loadProfessional: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            if loadPersonal && GoogleAuthManager.shared.isLinked(kind: .personal) {
                group.addTask {
                    do {
                        if let personalEvents = try await CalendarManager.shared.loadEvents(for: .personal, from: startDate, to: endDate) {
                            await MainActor.run {
                                self.personalEvents = personalEvents
                            }
                        }
                    } catch {
                        print("Failed to load personal events: \(error)")
                    }
                }
            }
            
            if loadProfessional && GoogleAuthManager.shared.isLinked(kind: .professional) {
                group.addTask {
                    do {
                        if let professionalEvents = try await CalendarManager.shared.loadEvents(for: .professional, from: startDate, to: endDate) {
                            await MainActor.run {
                                self.professionalEvents = professionalEvents
                            }
                        }
                    } catch {
                        print("Failed to load professional events: \(error)")
                    }
                }
            }
        }
    }
    
    private func filterEvents(in interval: DateInterval, options: EventFilterOptions) -> [GoogleCalendarEvent] {
        let allEvents = personalEvents + professionalEvents
        
        return allEvents.filter { event in
            // Filter by date range
            guard let eventStart = event.startTime,
                  eventStart >= interval.start && eventStart <= interval.end else {
                return false
            }
            
            // Filter by event type
            if event.isAllDay {
                if !options.includeAllDayEvents { return false }
            } else {
                if !options.includeTimedEvents { return false }
            }
            
            // Filter recurring events if requested
            if options.hideRecurringEvents && isEventRecurring(event) {
                return false
            }
            
            // Filter by time range if specified
            if let startHour = options.startHour,
               let endHour = options.endHour {
                let eventHour = Calendar.mondayFirst.component(.hour, from: eventStart) // FIX: Use consistent calendar
                return eventHour >= startHour && eventHour <= endHour
            }
            
            return true
        }
    }
    
    private func groupEventsByDate(_ events: [GoogleCalendarEvent], in interval: DateInterval) -> [Date: [GoogleCalendarEvent]] {
        var groupedEvents: [Date: [GoogleCalendarEvent]] = [:]
        // FIX: Use mondayFirst calendar to match CalendarWeekView and other calendar views
        let calendar = Calendar.mondayFirst
        
        // Pre-populate all dates in the range
        var currentDate = interval.start
        while currentDate <= interval.end {
            let startOfDay = calendar.startOfDay(for: currentDate)
            groupedEvents[startOfDay] = []
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // Group events by date
        for event in events {
            if let startTime = event.startTime {
                let startOfDay = calendar.startOfDay(for: startTime)
                groupedEvents[startOfDay, default: []].append(event)
            }
        }
        
        // Sort events within each day
        for (date, _) in groupedEvents {
            groupedEvents[date]?.sort { (event1, event2) -> Bool in
                let time1 = event1.startTime ?? Date.distantFuture
                let time2 = event2.startTime ?? Date.distantFuture
                return time1 < time2
            }
        }
        
        return groupedEvents
    }
    
    private func isPersonalEvent(_ event: GoogleCalendarEvent) -> Bool {
        return personalEvents.contains { $0.id == event.id }
    }
    
    private func generateCacheKey(for range: EventRangeType, options: EventFilterOptions) -> String {
        var components: [String] = []
        
        switch range {
        case .day(let date):
            components.append("day_\(formatDate(date))")
        case .week(let date):
            components.append("week_\(formatDate(date))")
        case .month(let date):
            components.append("month_\(formatDate(date))")
        case .custom(let start, let end):
            components.append("custom_\(formatDate(start))_\(formatDate(end))")
        }
        
        if options.hideRecurringEvents { components.append("hideRecurring") }
        if !options.includeAllDayEvents { components.append("noAllDay") }
        if !options.includeTimedEvents { components.append("noTimed") }
        if let startHour = options.startHour { components.append("start\(startHour)") }
        if let endHour = options.endHour { components.append("end\(endHour)") }
        
        return components.joined(separator: "_")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
