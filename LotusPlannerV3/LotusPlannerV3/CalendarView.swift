import SwiftUI
import PencilKit
import PhotosUI
import Foundation
import Photos

// Custom calendar that starts week on Monday
extension Calendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday = 2, Sunday = 1
        return calendar
    }
}

// Extension for custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}



// MARK: - Google Calendar Data Models
struct GoogleCalendar: Identifiable, Codable {
    let id: String
    let summary: String
    let description: String?
    let backgroundColor: String?
    let foregroundColor: String?
    let primary: Bool?
}

struct GoogleCalendarEvent: Identifiable, Codable {
    let id: String
    let summary: String
    let description: String?
    let start: EventDateTime
    let end: EventDateTime
    let location: String?
    let calendarId: String?
    let recurringEventId: String? // Present if this is an instance of a recurring event
    let recurrence: [String]? // Array of RRULE strings if this is the master recurring event
    
    var startTime: Date? {
        return start.dateTime ?? start.date
    }
    
    var endTime: Date? {
        return end.dateTime ?? end.date
    }
    
    var isAllDay: Bool {
        return start.date != nil
    }
    
    // Function to identify recurring events using official Google Calendar API fields
    func isLikelyRecurring(among allEvents: [GoogleCalendarEvent]) -> Bool {
        // Check if this event is an instance of a recurring event
        if recurringEventId != nil {
            return true
        }
        
        // Check if this event has recurrence rules (making it the master recurring event)
        if let recurrence = recurrence, !recurrence.isEmpty {
            return true
        }
        
        return false
    }
}

struct EventDateTime: Codable {
    let date: Date?
    let dateTime: Date?
    let timeZone: String?
    
    private enum CodingKeys: String, CodingKey {
        case date, dateTime, timeZone
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle date string
        if let dateString = try? container.decode(String.self, forKey: .date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.date = formatter.date(from: dateString)
            self.dateTime = nil
        } else {
            self.date = nil
            // Handle dateTime string
            if let dateTimeString = try? container.decode(String.self, forKey: .dateTime) {
                let formatter = ISO8601DateFormatter()
                self.dateTime = formatter.date(from: dateTimeString)
            } else {
                self.dateTime = nil
            }
        }
        
        self.timeZone = try? container.decode(String.self, forKey: .timeZone)
    }
}

struct GoogleCalendarListResponse: Codable {
    let items: [GoogleCalendar]?
}

struct GoogleCalendarEventsResponse: Codable {
    let items: [GoogleCalendarEvent]?
}



// MARK: - Calendar View Model
@MainActor
class CalendarViewModel: ObservableObject {
    @Published var personalCalendars: [GoogleCalendar] = []
    @Published var professionalCalendars: [GoogleCalendar] = []
    @Published var personalEvents: [GoogleCalendarEvent] = []
    @Published var professionalEvents: [GoogleCalendarEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let authManager = GoogleAuthManager.shared
    
    // MARK: - Memory Cache
    private var cachedEvents: [String: [GoogleCalendarEvent]] = [:]
    private var cachedCalendars: [String: [GoogleCalendar]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTimeout: TimeInterval = 1800 // 30 minutes - longer cache for better performance
    
    // MARK: - Persistent Cache Keys
    private let diskCacheKeyPrefix = "CalendarCache_"
    private let diskCacheTimestampPrefix = "CacheTimestamp_"
    
    // Track current loaded range to avoid unnecessary reloads
    private var currentLoadedRange: (start: Date, end: Date, accountKind: GoogleAuthManager.AccountKind)?
    
    // MARK: - Cache Helper Methods
    private func cacheKey(for accountKind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(accountKind.rawValue)_\(formatter.string(from: startDate))_\(formatter.string(from: endDate))"
    }

    // Expose a way to clear all caches and published arrays
    func clearAllData() {
        cachedEvents.removeAll()
        cachedCalendars.removeAll()
        cacheTimestamps.removeAll()
        personalEvents = []
        professionalEvents = []
        personalCalendars = []
        professionalCalendars = []
        // Clear disk cache keys as well
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(diskCacheKeyPrefix) || key.hasPrefix(diskCacheTimestampPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
    
    private func monthCacheKey(for date: Date, accountKind: GoogleAuthManager.AccountKind) -> String {
        let calendar = Calendar.mondayFirst
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date
        return cacheKey(for: accountKind, startDate: monthStart, endDate: monthEnd)
    }
    
    private func isCacheValid(for key: String) -> Bool {
        guard let timestamp = cacheTimestamps[key] else { return false }
        return Date().timeIntervalSince(timestamp) < cacheTimeout
    }
    
    private func getCachedEvents(for key: String) -> [GoogleCalendarEvent]? {
        // First check memory cache
        if isCacheValid(for: key), let memoryCache = cachedEvents[key] {
            return memoryCache
        }
        
        // Then check disk cache - FUNCTIONALITY PRESERVED: Only if memory cache invalid
        if let diskCache = loadEventsFromDisk(for: key), isDiskCacheValid(for: key) {
            // Restore to memory cache for faster access
            cachedEvents[key] = diskCache
            cacheTimestamps[key] = Date()
            return diskCache
        }
        
        // Clean up invalid cache
        cachedEvents.removeValue(forKey: key)
        cacheTimestamps.removeValue(forKey: key)
        clearDiskCache(for: key)
        return nil
    }
    
    private func cacheEvents(_ events: [GoogleCalendarEvent], for key: String) {
        // FUNCTIONALITY PRESERVED: Same memory caching behavior
        cachedEvents[key] = events
        cacheTimestamps[key] = Date()
        
        // PERFORMANCE ENHANCEMENT: Also save to disk for persistence
        saveEventsToDisk(events, for: key)
    }
    
    private func getCachedCalendars(for key: String) -> [GoogleCalendar]? {
        guard isCacheValid(for: key) else {
            cachedCalendars.removeValue(forKey: key)
            return nil
        }
        return cachedCalendars[key]
    }
    
    private func cacheCalendars(_ calendars: [GoogleCalendar], for key: String) {
        cachedCalendars[key] = calendars
        cacheTimestamps[key] = Date()
    }
    
    // MARK: - Persistent Disk Cache Methods
    private func saveEventsToDisk(_ events: [GoogleCalendarEvent], for key: String) {
        guard !events.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(events)
            UserDefaults.standard.set(data, forKey: diskCacheKeyPrefix + key)
            UserDefaults.standard.set(Date(), forKey: diskCacheTimestampPrefix + key)
        } catch {
        }
    }
    
    private func loadEventsFromDisk(for key: String) -> [GoogleCalendarEvent]? {
        guard let data = UserDefaults.standard.data(forKey: diskCacheKeyPrefix + key) else {
            return nil
        }
        
        do {
            let events = try JSONDecoder().decode([GoogleCalendarEvent].self, from: data)
            return events
        } catch {
            // Clean up corrupted cache
            clearDiskCache(for: key)
            return nil
        }
    }
    
    private func isDiskCacheValid(for key: String) -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: diskCacheTimestampPrefix + key) as? Date else {
            return false
        }
        // Disk cache valid for 24 hours (longer than memory cache)
        return Date().timeIntervalSince(timestamp) < 86400
    }
    
    private func clearDiskCache(for key: String) {
        UserDefaults.standard.removeObject(forKey: diskCacheKeyPrefix + key)
        UserDefaults.standard.removeObject(forKey: diskCacheTimestampPrefix + key)
    }
    
    // MARK: - Preloading Methods
    func preloadAdjacentMonths(around date: Date) async {
        let calendar = Calendar.mondayFirst
        
        await withTaskGroup(of: Void.self) { group in
            // Preload previous month (cache-only; do not mutate live arrays)
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: date) {
                group.addTask {
                    await self.preloadMonthIntoCache(containing: prevMonth)
                }
            }
            
            // Preload next month (cache-only)
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) {
                group.addTask {
                    await self.preloadMonthIntoCache(containing: nextMonth)
                }
            }
        }
        
    }

    // Preload a month's calendars/events into cache without updating published state
    func preloadMonthIntoCache(containing date: Date) async {
        let calendar = Calendar.mondayFirst
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return
        }
        
        // PERFORMANCE OPTIMIZATION: Check cache first to avoid unnecessary API calls
        let personalKey = monthCacheKey(for: date, accountKind: .personal)
        let professionalKey = monthCacheKey(for: date, accountKind: .professional)
        
        let needsPersonalPreload = authManager.isLinked(kind: .personal) && !isCacheValid(for: personalKey)
        let needsProfessionalPreload = authManager.isLinked(kind: .professional) && !isCacheValid(for: professionalKey)
        
        guard needsPersonalPreload || needsProfessionalPreload else {
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            if needsPersonalPreload {
                group.addTask {
                    do {
                        // Fetch calendars and events in parallel
                        async let calendars = CalendarManager.shared.fetchCalendars(for: .personal)
                        async let events = CalendarManager.shared.fetchEvents(for: .personal, startDate: monthStart, endDate: monthEnd)
                        
                        let (fetchedCalendars, fetchedEvents) = try await (calendars, events)
                        
                        await MainActor.run {
                            self.cacheCalendars(fetchedCalendars, for: personalKey)
                            self.cacheEvents(fetchedEvents, for: personalKey)
                        }
                    } catch {
                    }
                }
            }
            if needsProfessionalPreload {
                group.addTask {
                    do {
                        // Fetch calendars and events in parallel
                        async let calendars = CalendarManager.shared.fetchCalendars(for: .professional)
                        async let events = CalendarManager.shared.fetchEvents(for: .professional, startDate: monthStart, endDate: monthEnd)
                        
                        let (fetchedCalendars, fetchedEvents) = try await (calendars, events)
                        
                        await MainActor.run {
                            self.cacheCalendars(fetchedCalendars, for: professionalKey)
                            self.cacheEvents(fetchedEvents, for: professionalKey)
                        }
                    } catch {
                    }
                }
            }
        }
    }
    
    func loadCalendarData(for date: Date) async {
        isLoading = true
        errorMessage = nil
        
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadCalendarDataForAccount(.personal, date: date)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadCalendarDataForAccount(.professional, date: date)
                }
            }
        }
        
        isLoading = false
    }
    
    func loadCalendarDataForWeek(containing date: Date) async {
        isLoading = true
        errorMessage = nil
        
        // Get the week range using Monday-first calendar
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            isLoading = false
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadCalendarDataForWeekRange(.personal, startDate: weekStart, endDate: weekEnd)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadCalendarDataForWeekRange(.professional, startDate: weekStart, endDate: weekEnd)
                }
            }
        }
        
        isLoading = false
    }
    
    func loadCalendarDataForMonth(containing date: Date) async {
        let calendar = Calendar.mondayFirst
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return
        }
        
        
        // removed hasValidCache unused flag
        
        // Check cache first - if we have valid cached data, use it immediately
        if authManager.isLinked(kind: .personal) {
            let personalKey = monthCacheKey(for: date, accountKind: .personal)
            if let cachedEvents = getCachedEvents(for: personalKey),
               let cachedCalendars = getCachedCalendars(for: personalKey) {
                personalEvents = cachedEvents
                personalCalendars = cachedCalendars
            }
        }
        
        if authManager.isLinked(kind: .professional) {
            let professionalKey = monthCacheKey(for: date, accountKind: .professional)
            if let cachedEvents = getCachedEvents(for: professionalKey),
               let cachedCalendars = getCachedCalendars(for: professionalKey) {
                professionalEvents = cachedEvents
                professionalCalendars = cachedCalendars
            }
        }
        
        // If we have valid cache for all linked accounts, return early
        let needsPersonalRefresh = authManager.isLinked(kind: .personal) && getCachedEvents(for: monthCacheKey(for: date, accountKind: .personal)) == nil
        let needsProfessionalRefresh = authManager.isLinked(kind: .professional) && getCachedEvents(for: monthCacheKey(for: date, accountKind: .professional)) == nil
        
        if !needsPersonalRefresh && !needsProfessionalRefresh {
            return
        }
        
        // Load fresh data for accounts that need it
        isLoading = true
        errorMessage = nil
        
        var personalError: Error?
        var professionalError: Error?
        
        await withTaskGroup(of: Void.self) { group in
            if needsPersonalRefresh {
                group.addTask {
                    do {
                        let events = try await CalendarManager.shared.fetchEvents(for: .personal, startDate: monthStart, endDate: monthEnd)
                        let calendars = try await CalendarManager.shared.fetchCalendars(for: .personal)
                        await MainActor.run {
                            self.personalEvents = events
                            self.personalCalendars = calendars
                        }
                    } catch {
                        personalError = error
                    }
                }
            }
            if needsProfessionalRefresh {
                group.addTask {
                    do {
                        let events = try await CalendarManager.shared.fetchEvents(for: .professional, startDate: monthStart, endDate: monthEnd)
                        let calendars = try await CalendarManager.shared.fetchCalendars(for: .professional)
                        await MainActor.run {
                            self.professionalEvents = events
                            self.professionalCalendars = calendars
                        }
                    } catch {
                        professionalError = error
                    }
                }
            }
        }
        
        // Only show error if both accounts failed (if both are linked) or if the only linked account failed
        await MainActor.run {
            let personalLinked = authManager.isLinked(kind: .personal)
            let professionalLinked = authManager.isLinked(kind: .professional)
            
            if personalLinked && professionalLinked {
                // Both accounts linked - only show error if both failed
                if personalError != nil && professionalError != nil {
                    self.errorMessage = "Failed to load calendar data for both accounts"
                }
            } else if personalLinked && personalError != nil {
                // Only personal linked and it failed
                self.errorMessage = personalError!.localizedDescription
            } else if professionalLinked && professionalError != nil {
                // Only professional linked and it failed
                self.errorMessage = professionalError!.localizedDescription
            }
        }
        
        
        isLoading = false
    }
    
    private func loadCalendarDataForAccount(_ kind: GoogleAuthManager.AccountKind, date: Date) async {
        do {
            let calendars = try await fetchCalendars(for: kind)
            let events = try await fetchEventsForDate(date, calendars: calendars, for: kind)
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalCalendars = calendars
                    self.personalEvents = events
                case .professional:
                    self.professionalCalendars = calendars
                    self.professionalEvents = events
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) calendar data: \(error.localizedDescription)"
            }
        }
    }
    
    private func fetchCalendars(for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleCalendar] {
        
        do {
            let accessToken = try await authManager.getAccessToken(for: kind)
            
            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            
            if let response = httpResponse as? HTTPURLResponse {
                if response.statusCode != 200 {
                    if let responseString = String(data: data, encoding: .utf8) {
                    }
                    
                    // Handle HTTP errors
                    if response.statusCode != 200 {
                        throw CalendarManager.shared.handleHttpError(response.statusCode)
                    }
                }
            }
            
            let response = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
            let calendars = response.items ?? []
            
            // Debug: Print calendar details
            for calendar in calendars {
            }
            
            return calendars
        } catch {
            
            // Add more specific error information
            if let urlError = error as? URLError {
            }
            
            throw error
        }
    }
    
    private func fetchEventsForDate(_ date: Date, calendars: [GoogleCalendar], for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleCalendarEvent] {
        let accessToken = try await authManager.getAccessToken(for: kind)
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: startOfDay)
        let timeMax = formatter.string(from: endOfDay)
        
        var allEvents: [GoogleCalendarEvent] = []
        
        // Fetch events from all calendars
        for calendarItem in calendars {
            let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(calendarItem.id)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime"
            
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
                
                if let events = response.items {
                    let eventsWithCalendarId = events.map { event in
                        GoogleCalendarEvent(
                            id: event.id,
                            summary: event.summary,
                            description: event.description,
                            start: event.start,
                            end: event.end,
                            location: event.location,
                            calendarId: calendarItem.id,
                            recurringEventId: event.recurringEventId,
                            recurrence: event.recurrence
                        )
                    }
                    allEvents.append(contentsOf: eventsWithCalendarId)
                }
            } catch {
            }
        }
        
        return allEvents.sorted { event1, event2 in
            guard let start1 = event1.startTime, let start2 = event2.startTime else {
                return false
            }
            return start1 < start2
        }
    }
    
    private func loadCalendarDataForWeekRange(_ kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async {
        do {
            let calendars = try await fetchCalendars(for: kind)
            let events = try await fetchEventsForDateRange(startDate: startDate, endDate: endDate, calendars: calendars, for: kind)
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalCalendars = calendars
                    self.personalEvents = events
                case .professional:
                    self.professionalCalendars = calendars
                    self.professionalEvents = events
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) calendar data for week: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadCalendarDataForMonthRange(_ kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async {
        do {
            let calendars = try await fetchCalendars(for: kind)
            
            let events = try await fetchEventsForDateRange(startDate: startDate, endDate: endDate, calendars: calendars, for: kind)
            
            // Cache the fresh data
            let cacheKey = self.cacheKey(for: kind, startDate: startDate, endDate: endDate)
            cacheEvents(events, for: cacheKey)
            cacheCalendars(calendars, for: cacheKey)
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalCalendars = calendars
                    self.personalEvents = events
                case .professional:
                    self.professionalCalendars = calendars
                    self.professionalEvents = events
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) calendar data for month: \(error.localizedDescription)"
            }
        }
    }
    
    private func fetchEventsForDateRange(startDate: Date, endDate: Date, calendars: [GoogleCalendar], for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleCalendarEvent] {
        let accessToken = try await authManager.getAccessToken(for: kind)
        
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: startDate)
        let timeMax = formatter.string(from: endDate)
        
        var allEvents: [GoogleCalendarEvent] = []
        
        // Fetch events from all calendars
        for calendarItem in calendars {
            let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(calendarItem.id)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime"
            
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
                
                if let events = response.items {
                    let eventsWithCalendarId = events.map { event in
                        GoogleCalendarEvent(
                            id: event.id,
                            summary: event.summary,
                            description: event.description,
                            start: event.start,
                            end: event.end,
                            location: event.location,
                            calendarId: calendarItem.id,
                            recurringEventId: event.recurringEventId,
                            recurrence: event.recurrence
                        )
                    }
                    allEvents.append(contentsOf: eventsWithCalendarId)
                }
            } catch {
            }
        }
        
        return allEvents.sorted { event1, event2 in
            guard let start1 = event1.startTime, let start2 = event2.startTime else {
                return false
            }
            return start1 < start2
        }
    }
}



// TimelineInterval is now defined in SettingsView.swift (shared)

struct CalendarView: View {
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var currentDate = Date()
    @State private var topSectionHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    @State private var rightSectionTopHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    // Vertical layout row height
    @State private var verticalTopRowHeight: CGFloat = UIScreen.main.bounds.height * 0.55
    // Vertical layout column widths and drag states
    @State private var verticalTopLeftWidth: CGFloat = UIScreen.main.bounds.width * 0.5
    @State private var isVerticalTopDividerDragging: Bool = false
    @State private var verticalBottomLeftWidth: CGFloat = UIScreen.main.bounds.width * 0.5
    @State private var isVerticalBottomDividerDragging: Bool = false
    @State private var isDragging = false
    @State private var isRightDividerDragging = false
    @State private var pencilKitCanvasView = PKCanvasView()

    @State private var canvasView = PKCanvasView()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPermissionAlert = false
    @State private var showingPhotoPicker = false
    @State private var photoLibraryAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var selectedImages: [UIImage] = []
    @State private var showingTaskDetails = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct CalendarTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: CalendarTaskSelection?
    @State private var showingAddItem = false
    @State private var currentTimeTimer: Timer?
    @State private var currentTimeSlot: Double = 0
    @State private var movablePhotos: [MovablePhoto] = []
    @State private var cachedPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var weekTasksSectionWidth: CGFloat = UIScreen.main.bounds.width * 0.6
    @State private var weekCanvasView = PKCanvasView()
    @State private var cachedWeekPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedWeekProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var weekTopSectionHeight: CGFloat = 400
    @State private var isWeekDividerDragging = false
    @State private var monthCanvasView = PKCanvasView()
    @State private var cachedMonthPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedMonthProfessionalTasks: [String: [GoogleTask]] = [:]
    
    // Day view vertical slider state
    @State private var dayLeftSectionWidth: CGFloat = UIScreen.main.bounds.width * 0.25 // Default 1/4 width
    @State private var isDayVerticalDividerDragging = false
    // Left section divider state (timeline vs logs)
    @State private var leftTimelineHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    @State private var isLeftTimelineDividerDragging = false
    

    
    // Day view right section column widths and divider state
    @State private var dayRightColumn2Width: CGFloat = UIScreen.main.bounds.width * 0.25
    @State private var isDayRightColumnDividerDragging = false
    
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    
    // Personal/Professional task divider widths for all views
    @State private var weekTasksPersonalWidth: CGFloat = UIScreen.main.bounds.width * 0.3
    @State private var isWeekTasksDividerDragging = false
    
    // Long layout adjustable sizes and drag states
    @State private var longTopRowHeight: CGFloat = UIScreen.main.bounds.height * 0.35
    @State private var isLongHorizontalDividerDragging: Bool = false
    @State private var longEventsLeftWidth: CGFloat = UIScreen.main.bounds.width * 0.5
    @State private var isLongVerticalDividerDragging: Bool = false
    
    // Date picker state
    @State private var showingDatePicker = false
    @State private var selectedDateForPicker = Date()
    @State private var showingAddEvent = false
    @State private var showingNewTask = false
    
    private var baseContent: some View {
        GeometryReader { geometry in
            splitScreenContent(geometry: geometry)
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                principalToolbarContent
            }

            ToolbarItemGroup(placement: .principal) { EmptyView() }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                trailingToolbarButtons
            }
        }
    }

    private var toolbarAndSheetsContent: some View {
        baseContent
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarViewModel.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                        updateCachedTasks()
                    }
                }
            )
        }
        .onChange(of: authManager.linkedStates) { oldValue, newValue in
            // When an account is unlinked, clear associated tasks and refresh caches
            if !(newValue[.personal] ?? false) {
                tasksViewModel.clearTasks(for: .personal)
            }
            if !(newValue[.professional] ?? false) {
                tasksViewModel.clearTasks(for: .professional)
            }
            // When an account becomes linked, load tasks immediately
            let personalJustLinked = (newValue[.personal] ?? false) && !(oldValue[.personal] ?? false)
            let professionalJustLinked = (newValue[.professional] ?? false) && !(oldValue[.professional] ?? false)
            if personalJustLinked || professionalJustLinked {
                Task {
                    await tasksViewModel.loadTasks()
                    await MainActor.run {
                        updateCachedTasks()
                        updateMonthCachedTasks()
                    }
                }
            } else {
                updateCachedTasks()
                updateMonthCachedTasks()
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: GoogleAuthManager.AccountKind.personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? GoogleAuthManager.AccountKind.personal : GoogleAuthManager.AccountKind.professional
            let defaultLists = defaultAccount == GoogleAuthManager.AccountKind.personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == GoogleAuthManager.AccountKind.personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            navigateToDate(selectedDateForPicker)
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var finalContent: some View {
        toolbarAndSheetsContent
        .onChange(of: authManager.linkedStates) { oldValue, newValue in
            // When an account is unlinked, clear associated tasks and refresh caches
            if !(newValue[.personal] ?? false) {
                tasksViewModel.clearTasks(for: .personal)
            }
            if !(newValue[.professional] ?? false) {
                tasksViewModel.clearTasks(for: .professional)
            }
            // When an account becomes linked, load tasks immediately
            let personalJustLinked = (newValue[.personal] ?? false) && !(oldValue[.personal] ?? false)
            let professionalJustLinked = (newValue[.professional] ?? false) && !(oldValue[.professional] ?? false)
            if personalJustLinked || professionalJustLinked {
                Task {
                    await tasksViewModel.loadTasks()
                    await MainActor.run {
                        updateCachedTasks()
                        updateMonthCachedTasks()
                    }
                }
            } else {
                updateCachedTasks()
                updateMonthCachedTasks()
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: GoogleAuthManager.AccountKind.personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? GoogleAuthManager.AccountKind.personal : GoogleAuthManager.AccountKind.professional
            let defaultLists = defaultAccount == GoogleAuthManager.AccountKind.personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == GoogleAuthManager.AccountKind.personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .sheet(isPresented: $showingTaskDetails) {
            if let task = selectedTask, let taskListId = selectedTaskListId, let accountKind = selectedAccountKind {
                TaskDetailsView(
                    task: task,
                    taskListId: taskListId,
                    accountKind: accountKind,
                    accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksViewModel.personalTaskLists,
                    professionalTaskLists: tasksViewModel.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksViewModel,
                    onSave: { updatedTask in
                        Task {
                            await tasksViewModel.updateTask(updatedTask, in: taskListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onDelete: {
                        Task {
                            await tasksViewModel.deleteTask(task, from: taskListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksViewModel.moveTask(updatedTask, from: taskListId, to: targetListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                        Task {
                            await tasksViewModel.crossAccountMoveTask(updatedTask, from: (accountKind, taskListId), to: (targetAccountKind, targetListId))
                            updateCachedTasks()
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            navigateToDate(selectedDateForPicker)
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    var body: some View {
        finalContent
    }

    private func splitScreenContent(geometry: GeometryProxy) -> some View {
        // Just show the main content without any overlay panels
        mainContentView
    }
    

    
    private var leadingToolbarButtons: some View {
        EmptyView() // arrows moved to principal, Today moved to trailing
    }
    
    private var principalToolbarContent: some View {
        HStack(spacing: 8) {
            SharedNavigationToolbar()
            
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            if navigationManager.currentInterval == .year {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(String(Calendar.current.component(.year, from: currentDate)))
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentYear ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .month {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(monthYearTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentMonth ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .week {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(weekTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentWeek ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .day {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(dayTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            }
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Day button
            Button(action: {
                navigationManager.updateInterval(.day, date: Date())
                currentDate = Date()
            }) {
                Image(systemName: "d.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .weeklyView ? .accentColor : .secondary)
            }
            
            // WeeklyView button
            Button(action: {
                let now = Date()
                navigationManager.switchToWeeklyView()
                navigationManager.updateInterval(.week, date: now)
            }) {
                Image(systemName: "w.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .weeklyView ? .accentColor : .secondary)
            }
            
            // g.circle removed
            
            // Show eye and plus only in Day view
            if navigationManager.currentInterval == .day {
                // Hide Completed toggle
                Button(action: { appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks) }) {
                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Refresh button
                Button(action: {
                    Task {
                        await calendarViewModel.loadCalendarData(for: currentDate)
                        await tasksViewModel.loadTasks()
                        await MainActor.run { updateCachedTasks() }
                    }
                }) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Add menu (Event or Task) for Day view
                Menu {
                    Button("Event") { 
                        showingAddEvent = true
                    }
                    Button("Task") {
                        showingNewTask = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var mainContentView: some View {
        Group {
            if navigationManager.currentInterval == .year {
                yearView
            } else if navigationManager.currentInterval == .month {
                monthView
            } else if navigationManager.currentInterval == .day {
                setupDayView()
            } else {
                Text("Calendar View")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
    }

    private func step(_ direction: Int) {
        if let newDate = Calendar.current.date(byAdding: navigationManager.currentInterval.calendarComponent,
                                               value: direction,
                                               to: currentDate) {
            currentDate = newDate
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
        }
    }
    
    private var yearView: some View {
        monthsSection
            .background(Color(.systemBackground))
    }
    
    private var monthsSection: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 16
            let gridSpacing: CGFloat = 16
            let columnSpacing: CGFloat = 12
            let availableHeight = geometry.size.height - (padding * 2)
            let rows = 4 // 12 months ÷ 3 columns = 4 rows
            let monthCardHeight = (availableHeight - (gridSpacing * CGFloat(rows - 1))) / CGFloat(rows)
            
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 3), spacing: gridSpacing) {
                    ForEach(1...12, id: \.self) { month in
                        MonthCardView(
                            month: month,
                            year: Calendar.current.component(.year, from: currentDate),
                            currentDate: currentDate,
                            onDayTap: { date in
                                currentDate = date
                                navigationManager.updateInterval(.day, date: date)
                            },
                            onMonthTap: {
                                let cal = Calendar.mondayFirst
                                if let first = cal.date(from: DateComponents(year: Calendar.current.component(.year, from: currentDate), month: month, day: 1)) {
                                    currentDate = first
                                    navigationManager.updateInterval(.month, date: first)
                                }
                            },
                            onWeekTap: { date in
                                currentDate = date
                                navigationManager.updateInterval(.week, date: date)
                            }
                        )
                        .frame(height: monthCardHeight)
                    }
                }
                .padding(padding)
            }
        }
    }
    
    private var dividerSection: some View {
        Rectangle()
            .fill(isDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newHeight = topSectionHeight + value.translation.height
                        topSectionHeight = max(300, min(UIScreen.main.bounds.height - 150, newHeight))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
    
    private var bottomSection: some View {
        HStack(spacing: 0) {
            // Personal Tasks Component
            TasksComponent(
                taskLists: tasksViewModel.personalTaskLists,
                tasksDict: cachedMonthPersonalTasks,
                accentColor: appPrefs.personalColor,
                accountType: .personal,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.all, 8)
            
            // Professional Tasks Component  
            TasksComponent(
                taskLists: tasksViewModel.professionalTaskLists,
                tasksDict: cachedMonthProfessionalTasks,
                accentColor: appPrefs.professionalColor,
                accountType: .professional,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            // Bottom section - Journal (always visible)
            JournalView(currentDate: currentDate, embedded: true)
                .id(currentDate)
                .frame(maxHeight: .infinity)
                .padding(.all, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Week Bottom Section
    
    private var weekBottomSection: some View {
        GeometryReader { geometry in
            if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                // Centered empty state for weekly view
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view weekly tasks")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            } else {
                HStack(spacing: 0) {
                    // Tasks section (personal and professional columns)
                    weekTasksSection
                        .frame(width: weekTasksSectionWidth)
                    
                    // Resizable divider
                    weekTasksDivider
                    
                    // Apple Pencil section
                    weekPencilSection
                        .frame(width: geometry.size.width - weekTasksSectionWidth - 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var weekTasksSection: some View {
        HStack(spacing: 0) {
            // Personal Tasks
            TasksComponent(
                taskLists: tasksViewModel.personalTaskLists,
                tasksDict: cachedWeekPersonalTasks,
                accentColor: appPrefs.personalColor,
                accountType: .personal,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                    }
                }
            )
            .frame(width: weekTasksPersonalWidth, alignment: .topLeading)
            
            // Vertical divider
            weekTasksDivider
            
            // Professional Tasks
            TasksComponent(
                taskLists: tasksViewModel.professionalTaskLists,
                tasksDict: cachedWeekProfessionalTasks,
                accentColor: appPrefs.professionalColor,
                accountType: .professional,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                    }
                }
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    private var weekTasksDivider: some View {
        Rectangle()
            .fill(isWeekTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.vertical")
                    .font(.caption)
                    .foregroundColor(isWeekTasksDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isWeekTasksDividerDragging = true
                        let newWidth = weekTasksPersonalWidth + value.translation.width
                        weekTasksPersonalWidth = max(150, min(UIScreen.main.bounds.width * 0.6, newWidth))
                    }
                    .onEnded { _ in
                        isWeekTasksDividerDragging = false
                    }
            )
    }
    
    private var weekPencilSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes & Sketches")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    weekCanvasView.drawing = PKDrawing()
                }) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Canvas area
            WeekPencilKitView(canvasView: $weekCanvasView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.all, 8)
    }

    private var monthView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Single month calendar takes up full space
                singleMonthSection
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
    }

    private var monthYearTitle: String {
        // Updated format: January 2025
        return DateFormatter.standardMonthYear.string(from: currentDate)
    }
    

    
    private var weekTitle: String {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Week"
        }
        
        // Standardized format: 12/25/24 - 12/31/24
        let startString = DateFormatter.standardDate.string(from: weekStart)
        let endString = DateFormatter.standardDate.string(from: weekEnd)
        let result = "\(startString) - \(endString)"
        
        return result
    }
    
    private var dayTitle: String {
        // Standardized format: MON 12/25/24
        let dayOfWeek = DateFormatter.standardDayOfWeek.string(from: currentDate).uppercased()
        let date = DateFormatter.standardDate.string(from: currentDate)
        return "\(dayOfWeek) \(date)"
    }

    private var isToday: Bool {
        Calendar.current.isDate(currentDate, inSameDayAs: Date())
    }
    private var isCurrentWeek: Bool {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return false }
        return currentDate >= weekStart && currentDate <= weekEnd
    }
    private var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month], from: Date())
        let currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
        return todayComponents.year == currentComponents.year && todayComponents.month == currentComponents.month
    }
    private var isCurrentYear: Bool {
        Calendar.current.component(.year, from: Date()) == Calendar.current.component(.year, from: currentDate)
    }
    
    private func navigateToDate(_ selectedDate: Date) {
        let newDate: Date
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, navigate directly to the selected date
            newDate = selectedDate
        case .week:
            // For week view, navigate to the week containing the selected date
            let calendar = Calendar.mondayFirst
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start {
                newDate = weekStart
            } else {
                newDate = selectedDate
            }
        case .month:
            // For month view, navigate to the month containing the selected date
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            if let firstOfMonth = calendar.date(from: components) {
                newDate = firstOfMonth
            } else {
                newDate = selectedDate
            }
        case .year:
            // For year view, navigate to the year containing the selected date
            let calendar = Calendar.current
            let year = calendar.component(.year, from: selectedDate)
            if let firstOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                newDate = firstOfYear
            } else {
                newDate = selectedDate
            }
        }
        
        currentDate = newDate
        navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
    }
    

    

    

    

    



    

    
    private var singleMonthSection: some View {
        MonthTimelineComponent(
            currentDate: currentDate,
            monthEvents: getMonthEventsGroupedByDate(),
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            },
            onDayTap: { date in
                currentDate = date
                navigationManager.updateInterval(.day, date: date)
            }
        )
        .task {
            await calendarViewModel.loadCalendarDataForMonth(containing: currentDate)
        }
        .onChange(of: currentDate) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarDataForMonth(containing: newValue)
            }
        }
    }
    
    private var dayView: some View {
        dayViewBase
            .task {
                
                await calendarViewModel.loadCalendarData(for: currentDate)
                await tasksViewModel.loadTasks()
                await MainActor.run {
                    updateCachedTasks()
                }
            }
            .onChange(of: currentDate) { oldValue, newValue in
                Task {
                    await calendarViewModel.loadCalendarData(for: newValue)
                    await MainActor.run {
                        updateCachedTasks()
                    }
                }
            }
            .onChange(of: tasksViewModel.personalTasks) { oldValue, newValue in
                updateCachedTasks()
            }
            .onChange(of: tasksViewModel.professionalTasks) { oldValue, newValue in
                updateCachedTasks()
            }
            .onChange(of: dataManager.isInitializing) { oldValue, newValue in
                if !newValue {
                    updateCachedTasks()
                }
            }
            .onChange(of: appPrefs.hideCompletedTasks) { oldValue, newValue in
                updateCachedTasks()
            }

            .onAppear {
                startCurrentTimeTimer()
                // Ensure tasks are cached when view appears
                updateCachedTasks()
                // Listen for external add requests
                NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddTask"), object: nil, queue: .main) { _ in
                    navigationManager.switchToTasks()
                }
                NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddEvent"), object: nil, queue: .main) { _ in
                    showingAddItem = true
                }
            }
            .onDisappear {
                stopCurrentTimeTimer()
            }
    }
    
    private var dayViewBase: some View {
        GeometryReader { outerGeometry in
            ScrollView(.horizontal, showsIndicators: true) {
                dayViewContent(geometry: outerGeometry)
                    .frame(width: (appPrefs.dayViewLayout == .expanded ? outerGeometry.size.width * 2 : outerGeometry.size.width)) // 100% of device width
            }
        }
        .background(Color(.systemBackground))
        .overlay(loadingOverlay)
        .alert("Calendar Error", isPresented: .constant(calendarViewModel.errorMessage != nil)) {
            Button("OK") {
                calendarViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = calendarViewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .alert("Photo Library Access", isPresented: $showingPhotoPermissionAlert) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("LotusPlannerV3 needs access to your photo library to add photos to your daily notes. You can enable this in Settings > Privacy & Security > Photos.")
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            if let newPhoto = newValue {
                handleSelectedPhoto(newPhoto)
            }
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if calendarViewModel.isLoading {
            ProgressView("Loading calendar events...")
                .padding()
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var taskDetailsSheet: some View {
        if let task = selectedTask, 
           let listId = selectedTaskListId,
           let accountKind = selectedAccountKind {
            TaskDetailsView(
                task: task,
                taskListId: listId,
                accountKind: accountKind,
                accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: listId, for: accountKind)
                        updateCachedTasks()
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(task, from: listId, for: accountKind)
                        updateCachedTasks()
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: listId, to: targetListId, for: accountKind)
                        updateCachedTasks() // Refresh cached tasks after move
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (accountKind, listId), to: (targetAccountKind, targetListId))
                        updateCachedTasks()
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var eventDetailsSheet: some View {
        if let ev = selectedCalendarEvent {
            let accountKind: GoogleAuthManager.AccountKind = calendarViewModel.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind
            )
        }
    }
    
    // MARK: - Current Time Timer Functions
    private func startCurrentTimeTimer() {
        // Update every 5 minutes instead of every minute to reduce performance impact
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            updateCurrentTimeSlot()
        }
        updateCurrentTimeSlot() // Initial update
    }
    
    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
    
    private func updateCurrentTimeSlot() {
        let currentTime = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        currentTimeSlot = Double(hour) * 2.0 + Double(minute) / 30.0
    }
    
    @ViewBuilder
    private func dayViewContent(geometry: GeometryProxy) -> some View {
        switch appPrefs.dayViewLayout {
        case .expanded:
            dayViewContentExpanded(geometry: geometry)
        case .defaultNew:
            DayViewDefault(onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            })
        case .compactTwo:
            DayViewAlt(onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            })
        case .mobile:
            dayViewContentMobile(geometry: geometry)
        default:
            dayViewContentCompact(geometry: geometry)
        }
    }
    
    private func dayViewContentCompact(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left section (dynamic width)
            leftDaySectionWithDivider(geometry: geometry)
                .frame(width: dayLeftSectionWidth)
            
            // Vertical divider
            dayVerticalDivider

            // Right section expands to fill remaining space
            rightDaySection(geometry: geometry)
                .frame(maxWidth: .infinity)
        }
    }
    
    private func dayViewContentExpanded(geometry: GeometryProxy) -> some View {
        let deviceWidth = UIScreen.main.bounds.width
        let dividerWidth: CGFloat = 8
        // Make column widths responsive to the draggable divider state
        let column1Width = dayLeftSectionWidth
        let column2Width = max(200, deviceWidth - column1Width - dividerWidth)
        let column3Width = deviceWidth         // Journal: fixed to device width

        return HStack(alignment: .top, spacing: 0) {
            // Column 1 – timeline (25% device width)
            eventsTimelineCard()
                .frame(width: column1Width)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.trailing, 8)
                .padding(.leading, 16 + geometry.safeAreaInsets.leading)

            dayVerticalDivider

            // Column 2 – Tasks + Logs (75% device width)
            VStack(spacing: 0) {
                topLeftDaySection
                    .frame(height: rightSectionTopHeight)
                    .padding(.all, 8)

                rightSectionDivider

                LogsComponent(currentDate: currentDate, horizontal: true)
                    .frame(maxHeight: .infinity)
                    .padding(.all, 8)
            }
            .frame(width: column2Width)

            dayVerticalDivider

            // Column 3 – Journal (100% device width)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.headline)
                    .padding(.horizontal, 8)
                JournalView(currentDate: currentDate, embedded: true, layoutType: .expanded)
            }
            .id(currentDate)
            .frame(width: column3Width)
            .padding(.all, 8)
        }
    }

    // MARK: - Vertical Layout
    private func dayViewContentVertical(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top row: HStack of Tasks (left) and Logs (right) with vertical divider
            HStack(spacing: 0) {
                // Tasks content (reuse topLeftDaySection)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tasks")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    topLeftDaySection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(width: verticalTopLeftWidth, alignment: .topLeading)
                .padding(.all, 8)
                .background(Color(.systemBackground))
                .cornerRadius(12)

                // Vertical divider between Tasks and Logs
                Rectangle()
                    .fill(isVerticalTopDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                    .frame(width: 8)
                    .overlay(
                        Image(systemName: "line.3.vertical")
                            .font(.caption)
                            .foregroundColor(isVerticalTopDividerDragging ? .white : .gray)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isVerticalTopDividerDragging = true
                                let minWidth: CGFloat = 200
                                let maxWidth: CGFloat = max(minWidth, geometry.size.width - 8 - 200)
                                let newWidth = verticalTopLeftWidth + value.translation.width
                                verticalTopLeftWidth = max(minWidth, min(maxWidth, newWidth))
                            }
                            .onEnded { _ in
                                isVerticalTopDividerDragging = false
                            }
                    )

                // Logs on the right with weight, workout, food in a column
                LogsComponent(currentDate: currentDate, horizontal: false)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: verticalTopRowHeight, alignment: .top)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Draggable divider between top and bottom rows
            Rectangle()
                .fill(isWeekDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                .frame(height: 8)
                .overlay(
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(isWeekDividerDragging ? .white : .gray)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isWeekDividerDragging = true
                            let newHeight = verticalTopRowHeight + value.translation.height
                            let minHeight: CGFloat = 200
                            let maxHeight: CGFloat = max(250, geometry.size.height - 250)
                            verticalTopRowHeight = max(minHeight, min(maxHeight, newHeight))
                        }
                        .onEnded { _ in
                            isWeekDividerDragging = false
                        }
                )

            // Bottom row: HStack of Events (left) and Notes (right) with vertical divider
            HStack(alignment: .top, spacing: 0) {
                // Timeline on the left
                eventsTimelineCard()
                    .frame(width: verticalBottomLeftWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)

                // Vertical divider between Events and Notes
                Rectangle()
                    .fill(isVerticalBottomDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                    .frame(width: 8)
                    .overlay(
                        Image(systemName: "line.3.vertical")
                            .font(.caption)
                            .foregroundColor(isVerticalBottomDividerDragging ? .white : .gray)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isVerticalBottomDividerDragging = true
                                let minWidth: CGFloat = 200
                                let maxWidth: CGFloat = max(minWidth, geometry.size.width - 8 - 200)
                                let newWidth = verticalBottomLeftWidth + value.translation.width
                                verticalBottomLeftWidth = max(minWidth, min(maxWidth, newWidth))
                            }
                            .onEnded { _ in
                                isVerticalBottomDividerDragging = false
                            }
                    )

                // Notes (Journal) on the right
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    JournalView(currentDate: currentDate, embedded: true, layoutType: .compact)
                        .id(currentDate)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.all, 8)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
    
    // vertical layout removed
    
    // MARK: - Mobile Layout (single column: Events, Personal Tasks, Professional Tasks, Logs)
    private func dayViewContentMobile(geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                // Events list (always list in Mobile layout)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Events")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    dayEventsList
                }
                .padding(.vertical, 8)

                // Personal tasks
                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal Tasks")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    TasksComponent(
                        taskLists: tasksViewModel.personalTaskLists,
                        tasksDict: filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate),
                        accentColor: appPrefs.personalColor,
                        accountType: .personal,
                        onTaskToggle: { task, listId in
                            Task {
                                await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                updateCachedTasks()
                            }
                        },
                        onTaskDetails: { task, listId in
                            taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                        },
                        onListRename: { listId, newName in
                            Task {
                                await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                            }
                        },
                        onOrderChanged: { newOrder in
                            Task {
                                await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                            }
                        },
                        hideDueDateTag: false,
                        showEmptyState: true,
                        horizontalCards: false
                    )
                }

                // Professional tasks
                VStack(alignment: .leading, spacing: 6) {
                    Text("Professional Tasks")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    TasksComponent(
                        taskLists: tasksViewModel.professionalTaskLists,
                        tasksDict: filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate),
                        accentColor: appPrefs.professionalColor,
                        accountType: .professional,
                        onTaskToggle: { task, listId in
                            Task {
                                await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                updateCachedTasks()
                            }
                        },
                        onTaskDetails: { task, listId in
                            selectedTask = task
                            selectedTaskListId = listId
                            selectedAccountKind = .professional
                            DispatchQueue.main.async { showingTaskDetails = true }
                        },
                        onListRename: { listId, newName in
                            Task {
                                await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                            }
                        },
                        onOrderChanged: { newOrder in
                            Task {
                                await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                            }
                        },
                        hideDueDateTag: false,
                        showEmptyState: true,
                        horizontalCards: false
                    )
                }

                // Logs (no label in Mobile layout)
                VStack(alignment: .leading, spacing: 6) {
                    LogsComponent(currentDate: currentDate, horizontal: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(Color(.systemBackground))
    }

    // MARK: - Long Layout
    // Three rows: 1) Tasks, 2) HStack(Events list, Logs side-by-side), 3) Notes full screen below accessible via swipe
    private func dayViewContentLong(geometry: GeometryProxy) -> some View {
        // Use a vertical ScrollView so users can swipe up to reach the full-screen Notes area
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                // Row 1: Tasks (Personal + Professional stacked vertically)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    // Reuse existing day tasks section which renders personal and professional
                    topLeftDaySection
                }
                .padding(.horizontal, 8)

                // Row 2: Events list and Logs side-by-side, top aligned
                HStack(alignment: .top, spacing: 0) {
                    // Events as list
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Events")
                            .font(.headline)
                            .padding(.horizontal, 12)
                        dayEventsList
                    }
                    .frame(width: longEventsLeftWidth, alignment: .topLeading)

                    // Vertical draggable divider between Events and Logs
                    Rectangle()
                        .fill(isLongVerticalDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: 8)
                        .overlay(
                            Image(systemName: "line.3.vertical")
                                .font(.caption)
                                .foregroundColor(isLongVerticalDividerDragging ? .white : .gray)
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isLongVerticalDividerDragging = true
                                    let minWidth: CGFloat = 180
                                    let maxWidth: CGFloat = max(minWidth, geometry.size.width - 8 - 200)
                                    let newWidth = longEventsLeftWidth + value.translation.width
                                    longEventsLeftWidth = max(minWidth, min(maxWidth, newWidth))
                                }
                                .onEnded { _ in
                                    isLongVerticalDividerDragging = false
                                }
                        )

                    // Logs with weight, workout, and food laid out side-by-side
                    VStack(alignment: .leading, spacing: 6) {
                        // No label per latest style
                        // Reuse LogsComponent in horizontal mode to display categories side-by-side
                        LogsComponent(currentDate: currentDate, horizontal: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 8)

                // Row 3: Notes full-screen width and height; make it tall so it occupies screen when reached
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    JournalView(currentDate: currentDate, embedded: true, layoutType: .expanded)
                        .id(currentDate)
                        .frame(minHeight: UIScreen.main.bounds.height * 0.9)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .padding(.top, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Long Layout 2
    // Four rows: 1) Events, 2) Tasks, 3) Logs, 4) Notes full screen below
    private func dayViewContentLong2(geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                // Row 1: Events (full width)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Events")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    dayEventsList
                }
                .padding(.horizontal, 8)

                // Row 2: Tasks (Personal + Professional stacked vertically)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    topLeftDaySection
                }
                .padding(.horizontal, 8)

                // Row 3: Logs (full width)
                VStack(alignment: .leading, spacing: 6) {
                    LogsComponent(currentDate: currentDate, horizontal: false)
                }
                .padding(.horizontal, 8)

                // Row 4: Notes full-screen below
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    JournalView(currentDate: currentDate, embedded: true, layoutType: .expanded)
                        .frame(maxWidth: .infinity, minHeight: 600)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
    
    private func rightDaySection(geometry: GeometryProxy) -> some View {
        // The total content width is 100% of device width
        let totalWidth = geometry.size.width
        let rightSectionWidth: CGFloat = totalWidth - dayLeftSectionWidth - 8 // divider width
        
        return VStack(spacing: 0) {
            // Top section - Tasks
            VStack(spacing: 6) {
                HStack {
                    Text("Tasks")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 8)
                // Personal & Professional tasks (full width)
                topLeftDaySection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: rightSectionTopHeight, alignment: .top)
            .padding(.all, 8)
            
            // Draggable divider
            rightSectionDivider
            
            // Bottom section - Journal
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Notes")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 8)
                JournalView(currentDate: currentDate, embedded: true, layoutType: .compact)
            }
            .id(currentDate)
            .frame(maxHeight: .infinity)
            .padding(.all, 8)
        }
    }
    
        private func setupDayView() -> some View {
        dayView
    }
    
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Timeline section – reuse the same card as expanded
            eventsTimelineCard(height: leftTimelineHeight)
                .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                .padding(.trailing, 8)

            // Draggable divider between timeline and logs
            leftTimelineDivider
            
            // Logs section (always visible)
            LogsComponent(currentDate: currentDate, horizontal: false)
                .frame(maxHeight: .infinity)
                .padding(.all, 8)
        }
        .frame(height: geometry.size.height)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    private var leftTimelineSection: some View {
        Group {
            if appPrefs.showEventsAsListInDay {
                dayEventsList
            } else {
                TimelineComponent(
                    date: currentDate,
                    events: getAllEventsForDate(currentDate),
                    personalEvents: calendarViewModel.personalEvents,
                    professionalEvents: calendarViewModel.professionalEvents,
                    personalColor: appPrefs.personalColor,
                    professionalColor: appPrefs.professionalColor,
                    onEventTap: { ev in
                        selectedCalendarEvent = ev
                        showingEventDetails = true
                    }
                )
            }
        }
    }

    // Shared Events timeline card used by both compact and expanded layouts
    private func eventsTimelineCard(height: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Events")
                .font(.headline)
                .padding(.leading, 12)
                .padding(.trailing, 8)
            leftTimelineSection
        }
        .frame(height: height, alignment: .topLeading)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.leading, 8)
        // remove background and border for a flat look
    }
    
    private var dayEventsList: some View {
        let events = getAllEventsForDate(currentDate)
            .sorted { (a, b) in
                let aDate = a.startTime ?? Date.distantPast
                let bDate = b.startTime ?? Date.distantPast
                return aDate < bDate
            }
        return EventsListComponent(
            events: events,
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            }
        )
    }
    
    private var rightSectionDivider: some View {
        Rectangle()
            .fill(isRightDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isRightDividerDragging ? .white : .gray)
            )

            .gesture(
                DragGesture()
                    .onChanged { value in
                        isRightDividerDragging = true
                        let newHeight = rightSectionTopHeight + value.translation.height
                        rightSectionTopHeight = max(200, min(UIScreen.main.bounds.height - 300, newHeight))
                    }
                    .onEnded { _ in
                        isRightDividerDragging = false
                    }
            )
    }
    
    private var leftTimelineDivider: some View {
        Rectangle()
            .fill(isLeftTimelineDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLeftTimelineDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLeftTimelineDividerDragging = true
                        let newHeight = leftTimelineHeight + value.translation.height
                        leftTimelineHeight = max(200, min(UIScreen.main.bounds.height - 200, newHeight))
                    }
                    .onEnded { _ in
                        isLeftTimelineDividerDragging = false
                    }
            )
    }
    
    private var weekDivider: some View {
        Rectangle()
            .fill(isWeekDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isWeekDividerDragging ? .white : .gray)
            )

            .gesture(
                DragGesture()
                    .onChanged { value in
                        isWeekDividerDragging = true
                        let newHeight = weekTopSectionHeight + value.translation.height
                        weekTopSectionHeight = max(200, min(UIScreen.main.bounds.height - 200, newHeight))
                    }
                    .onEnded { _ in
                        isWeekDividerDragging = false
                    }
            )
    }
    
    private var dayVerticalDivider: some View {
        Rectangle()
            .fill(isDayVerticalDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.vertical")
                    .font(.caption)
                    .foregroundColor(isDayVerticalDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDayVerticalDividerDragging = true
                        let newWidth = dayLeftSectionWidth + value.translation.width
                        // Constrain to reasonable bounds: minimum 200pt, maximum 80% of screen width
                        dayLeftSectionWidth = max(200, min(UIScreen.main.bounds.width * 0.8, newWidth))
                    }
                    .onEnded { _ in
                        isDayVerticalDividerDragging = false
                    }
            )
    }
    
    private var dayRightColumnDivider: some View {
        Rectangle()
            .fill(isDayRightColumnDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.vertical")
                    .font(.caption)
                    .foregroundColor(isDayRightColumnDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDayRightColumnDividerDragging = true
                        let newWidth = dayRightColumn2Width + value.translation.width
                        // Constrain to reasonable bounds: minimum 150pt, maximum to leave space for other columns
                        dayRightColumn2Width = max(150, min(UIScreen.main.bounds.width * 0.4, newWidth))
                    }
                    .onEnded { _ in
                        isDayRightColumnDividerDragging = false
                    }
            )
    }
    

    
    private var timelineWithEvents: some View {
        ZStack(alignment: .topLeading) {
            // Background timeline grid
            VStack(spacing: 0) {
                ForEach(0..<48, id: \.self) { slot in
                    timelineSlot(slot: slot, showEvents: false)
                }
            }
            
            // Current time red line
            if Calendar.current.isDate(currentDate, inSameDayAs: Date()) {
                currentTimeRedLine
            }
            
            // Overlay events with smart positioning
            eventLayoutView
        }
    }
    
    private var currentTimeRedLine: some View {
        let currentTime = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // Calculate position using same precise logic as events
        // Each hour = 100pt, each minute = 100pt / 60min = 1.667pt per minute
        let hourOffset = CGFloat(hour) * 100.0
        let minuteOffset = CGFloat(minute) * (100.0 / 60.0)
        let yOffset = hourOffset + minuteOffset
        
        return HStack(spacing: 0) {
            Spacer().frame(width: 43) // Space for time labels (35pt + 8pt spacing)
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
            Spacer().frame(width: 8)
        }
        .offset(y: yOffset)
        .zIndex(100)
    }
    
    private var eventLayoutView: some View {
        let timelineEvents = getTimelineEvents()
        
        return GeometryReader { geometry in
            // The geometry here is for the timelineWithEvents view, which already accounts for the timeline column
            // Available width = total width - time labels (43) - spacing (8)
            let availableWidth = geometry.size.width - 43 - 8
            
            ForEach(timelineEvents, id: \.id) { event in
                let overlappingEvents = getOverlappingEvents(for: event, in: timelineEvents)
                let eventIndex = overlappingEvents.firstIndex(where: { $0.id == event.id }) ?? 0
                let totalOverlapping = overlappingEvents.count
                let eventWidth = totalOverlapping == 1 ? availableWidth : availableWidth / CGFloat(totalOverlapping)
                
                eventBlockView(event: event)
                    .frame(width: eventWidth)
                    .frame(height: event.height)
                    .offset(x: 43 + CGFloat(eventIndex) * eventWidth, 
                           y: event.topOffset)
            }
        }
    }
    

    
    private func timelineSlot(slot: Int, showEvents: Bool = true) -> some View {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        let time = String(format: "%02d:%02d", hour, minute)
        let isHour = minute == 0
        _ = hour >= 7 && hour < 19 // 7am to 7pm default view
        
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Time label
                if isHour {
                    Text(time)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                } else {
                    Text(time)
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 35, alignment: .trailing)
                }
                
                // Timeline line and events
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isHour ? Color(.systemGray3) : Color(.systemGray5))
                        .frame(height: isHour ? 1 : 0.5)
                    
                    // Event slots (only show when showEvents is true - for old implementation)
                    if showEvents {
                        HStack(spacing: 2) {
                            // Personal events column
                            if let personalEvent = getPersonalEvent(for: slot) {
                                eventBlock(event: personalEvent, color: .blue, isPersonal: true)
                            } else {
                                Spacer()
                                    .frame(height: 20)
                            }
                            
                            // Professional events column  
                            if let professionalEvent = getProfessionalEvent(for: slot) {
                                eventBlock(event: professionalEvent, color: .green, isPersonal: false)
                            } else {
                                Spacer()
                                    .frame(height: 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Just show empty space for timeline grid
                        Spacer()
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 50) // Doubled from 25 to 50
        }
        .id(slot)
    }
    
    private func eventBlock(event: String, color: Color, isPersonal: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Text(event)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1)
            )
            // No long-press action for placeholder string events
    }
    
    

    
    private var pencilKitSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Background canvas
                VStack(spacing: 12) {
                    HStack {
                        Text("Notes & Sketches")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        // Photo picker button
                        Button(action: {
                            requestPhotoLibraryAccess()
                        }) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // PencilKit Canvas
                    PencilKitView(canvasView: $canvasView)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .frame(minHeight: 200)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                
                // Moveable photos overlay
                ForEach(movablePhotos.indices, id: \.self) { index in
                    MovablePhotoView(
                        photo: $movablePhotos[index],
                        containerSize: geometry.size,
                        onDelete: {
                            movablePhotos.remove(at: index)
                        }
                    )
                }
            }
        }
        .padding(.all, 8)
        .onChange(of: selectedImages) { oldValue, newValue in
            // Convert new images to movable photos
            for (i, image) in newValue.enumerated() {
                if i >= oldValue.count {
                    // This is a new image
                    let position = CGPoint(
                        x: CGFloat.random(in: 50...200),
                        y: CGFloat.random(in: 80...150)
                    )
                    movablePhotos.append(MovablePhoto(image: image, position: position))
                }
            }
            // Clear the selectedImages array after converting
            if !newValue.isEmpty {
                selectedImages.removeAll()
            }
        }
    }
    
    // MARK: - Movable Photo View
    struct MovablePhotoView: View {
        @Binding var photo: MovablePhoto
        let containerSize: CGSize
        let onDelete: () -> Void
        @State private var isDragging = false
        
        var body: some View {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photo.size.width, height: photo.size.height)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 8 : 4)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }
                .offset(x: 8, y: -8)
            }
            .position(photo.position)
            .animation(.easeOut(duration: 0.2), value: isDragging)
        }
    }
    
    // MARK: - Data Structures
    struct MovablePhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        var position: CGPoint
        var size: CGSize = CGSize(width: 100, height: 100)
    }
    
    struct TimelineEvent: Identifiable, Hashable {
        let id = UUID()
        let event: GoogleCalendarEvent
        let startSlot: Int
        let endSlot: Int
        let isPersonal: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
            return lhs.id == rhs.id
        }
        
        var topOffset: CGFloat {
            // Calculate precise position based on actual start time
            guard let startTime = event.startTime else { return 0 }
            
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            
            // Each hour = 2 slots = 100pt (50pt per 30-min slot)
            // Each minute = 100pt / 60min = 1.667pt per minute
            let hourOffset = CGFloat(hour) * 100.0 // 2 slots * 50pt per slot
            let minuteOffset = CGFloat(minute) * (100.0 / 60.0) // Precise minute positioning
            
            return hourOffset + minuteOffset
        }
        
        var height: CGFloat {
            // Calculate precise height based on actual duration
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { 
                return 50.0 // Default minimum height
            }
            
            let duration = endTime.timeIntervalSince(startTime)
            let durationMinutes = duration / 60.0 // Convert seconds to minutes
            
            // Each minute = 100pt / 60min = 1.667pt per minute
            let calculatedHeight = CGFloat(durationMinutes) * (100.0 / 60.0)
            
            // Minimum height of 25pt for very short events
            return max(25.0, calculatedHeight)
        }
    }
    
    private func getTimelineEvents() -> [TimelineEvent] {
        var timelineEvents: [TimelineEvent] = []
        
        // Process personal events
        for event in calendarViewModel.personalEvents {
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            let startSlot = timeToSlot(startTime, isEndTime: false)
            let endSlot = timeToSlot(endTime, isEndTime: true)
            
            if startSlot < 48 && endSlot > 0 { // Event is within our 24-hour view
                timelineEvents.append(TimelineEvent(
                    event: event,
                    startSlot: max(0, startSlot),
                    endSlot: min(48, endSlot),
                    isPersonal: true
                ))
            }
        }
        
        // Process professional events
        for event in calendarViewModel.professionalEvents {
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            let startSlot = timeToSlot(startTime, isEndTime: false)
            let endSlot = timeToSlot(endTime, isEndTime: true)
            
            if startSlot < 48 && endSlot > 0 { // Event is within our 24-hour view
                timelineEvents.append(TimelineEvent(
                    event: event,
                    startSlot: max(0, startSlot),
                    endSlot: min(48, endSlot),
                    isPersonal: false
                ))
            }
        }
        
        return timelineEvents.sorted { $0.startSlot < $1.startSlot }
    }
    
    private func getOverlappingEvents(for event: TimelineEvent, in events: [TimelineEvent]) -> [TimelineEvent] {
        return events.filter { otherEvent in
            eventsOverlap(event, otherEvent)
        }.sorted { $0.startSlot < $1.startSlot }
    }
    
    private func eventsOverlap(_ event1: TimelineEvent, _ event2: TimelineEvent) -> Bool {
        return event1.startSlot < event2.endSlot && event2.startSlot < event1.endSlot
    }
    
    private func timeToSlot(_ time: Date, isEndTime: Bool = false) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // For start times, round down to the nearest 30-minute slot
        // For end times, round up to ensure events show up even if they're shorter than 30 minutes
        if isEndTime {
            // If minute is > 0, round up to the next 30-minute slot
            return hour * 2 + (minute > 0 ? (minute >= 30 ? 2 : 1) : 0)
        } else {
            // For start times, round down as before
            return hour * 2 + (minute >= 30 ? 1 : 0)
        }
    }
    
    private func eventBlockView(event: TimelineEvent) -> some View {
        let color: Color = event.isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.2))
            .overlay(
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.event.summary)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                    
                    if event.height >= 50 { // Show time only if event is tall enough
                        Text(formatEventTime(event.event))
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1.5)
            )
            // No long-press action for placeholder string events
            .onLongPressGesture {
                selectedCalendarEvent = event.event
                showingEventDetails = true
            }
    }
    
    private func formatEventTime(_ event: GoogleCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        guard let startTime = event.startTime,
              let endTime = event.endTime else { return "" }
        
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    // MARK: - Week Timeline View (7 Mini Day Views Side by Side)
    private var weekTimelineView: some View {
        let weekDates = getWeekDates()
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let timeColumnWidth: CGFloat = 50
            let dayColumnWidth = (availableWidth - timeColumnWidth) / 7
            
            ScrollView(.vertical, showsIndicators: true) {
                HStack(spacing: 0) {
                    // Time labels column (same as day view)
                    VStack(spacing: 0) {
                        // Header spacer
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 40)
                            .overlay(
                                Text("Time")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            )
                        
                        ForEach(0..<24, id: \.self) { hour in
                            HStack {
                                Text(String(format: "%02d:00", hour))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(height: 100) // Same as day view: 100pt per hour
                            .padding(.horizontal, 4)
                        }
                    }
                    .frame(width: timeColumnWidth)
                    .background(Color(.systemGray6).opacity(0.3))
                    
                    // 7 mini day-view timelines side by side
                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                        miniDayTimeline(date: date, width: dayColumnWidth)
                            .overlay(
                                // Right border between days
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                    }
                }
            }
        }
    }
    
    // Mini day timeline for week view
    private func miniDayTimeline(date: Date, width: CGFloat) -> some View {
        let dayEvents = getEventsForDate(date)
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        
        // Formatters for day display
        let dayOfWeekFormatter = DateFormatter()
        dayOfWeekFormatter.dateFormat = "E" // Mon, Tue, etc.
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d" // 1, 2, 3, etc.
        
        return VStack(spacing: 0) {
            // Day header
            VStack(spacing: 2) {
                Text(dayOfWeekFormatter.string(from: date))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(isToday ? .white : .primary)
                
                Text(dayFormatter.string(from: date))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isToday ? .white : .primary)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(isToday ? Color.blue : Color(.systemGray5))
            
            // Mini timeline (exactly like day view but narrower)
            ZStack(alignment: .topLeading) {
                // Hour grid background (same as day view)
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Rectangle()
                            .fill(Color(.systemGray6).opacity(0.3))
                            .frame(height: 100) // Same as day view: 100pt per hour
                            .overlay(
                                // Half-hour line
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 0.5)
                                    .offset(y: 50)
                            )
                    }
                }
                
                // Events for this day (same positioning as day view)
                ForEach(dayEvents, id: \.id) { event in
                    miniDayEventView(event: event, dayWidth: width)
                }
                
                // Current time indicator (only for today)
                if isToday {
                    miniCurrentTimeLine()
                }
            }
        }
        .frame(width: width)
    }
    
    // Mini event view for week timeline (same positioning as day view)
    private func miniDayEventView(event: GoogleCalendarEvent, dayWidth: CGFloat) -> AnyView {
        guard let startTime = event.startTime,
              let endTime = event.endTime else {
            return AnyView(EmptyView())
        }
        
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let _ = calendar.dateComponents([.hour, .minute], from: endTime)
        
        let startHour = startComponents.hour ?? 0
        let startMinute = startComponents.minute ?? 0
        
        // Calculate position and height (same as day view: 100pt per hour)
        let topOffset = CGFloat(startHour) * 100.0 + CGFloat(startMinute) * (100.0 / 60.0)
        let duration = endTime.timeIntervalSince(startTime)
        let durationMinutes = duration / 60.0
        let height = max(20.0, CGFloat(durationMinutes) * (100.0 / 60.0)) // Minimum 20pt for narrow columns
        
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let backgroundColor = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        let view = AnyView(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor.opacity(0.8))
                .frame(height: height)
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(height > 40 ? 2 : 1)
                        
                        if height > 30 {
                            Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
                .offset(y: topOffset)
                .padding(.horizontal, 1) // Small padding to prevent events from touching edges
        )
        let modified = view
            .onTapGesture { onEventLongPress(event) }
            .onLongPressGesture { onEventLongPress(event) }
        return AnyView(modified)
    }
    
    // Mini current time line for week view
    private func miniCurrentTimeLine() -> some View {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour) * 100.0 + CGFloat(minute) * (100.0 / 60.0)
        
        return Rectangle()
            .fill(Color.red)
            .frame(height: 2)
            .offset(y: yOffset)
            .overlay(
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: -3),
                alignment: .leading
            )
    }
    
    private func getWeekDates() -> [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    

    
    // Group month events by date for the MonthTimelineComponent
    private func getMonthEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        let monthDates = getMonthDates()
        var eventsGroupedByDate: [Date: [GoogleCalendarEvent]] = [:]
        
        var allEvents: [GoogleCalendarEvent] = []
        if authManager.isLinked(kind: .personal) {
            allEvents += calendarViewModel.personalEvents
        }
        if authManager.isLinked(kind: .professional) {
            allEvents += calendarViewModel.professionalEvents
        }
        
        // Debug: Print event counts to help diagnose the issue
        
        // Filter out recurring events if the setting is enabled
        if appPrefs.hideRecurringEventsInMonth {
            let allEventsForRecurringDetection = allEvents
            let recurringEvents = allEvents.filter { $0.isLikelyRecurring(among: allEventsForRecurringDetection) }
            for event in recurringEvents {
            }
            allEvents = allEvents.filter { !$0.isLikelyRecurring(among: allEventsForRecurringDetection) }
        }
        
        for date in monthDates {
            let calendar = Calendar.current
            let eventsForDate = allEvents.filter { event in
                guard let startTime = event.startTime else { return false }
                return calendar.isDate(startTime, inSameDayAs: date)
            }
            eventsGroupedByDate[date] = eventsForDate
        }
        
        return eventsGroupedByDate
    }
    
    private func getMonthDates() -> [Date] {
        let calendar = Calendar.mondayFirst
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else {
            return []
        }
        
        var dates: [Date] = []
        var date = monthInterval.start
        
        while date < monthInterval.end {
            dates.append(date)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        
        return dates
    }
    
    private func weekDayHeader(date: Date) -> some View {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E" // Mon, Tue, etc.
        let dayName = dayFormatter.string(from: date)
        
        let dayNumber = calendar.component(.day, from: date)
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 4) {
            Text(dayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("\(dayNumber)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isToday ? Color.red : Color.clear)
                .clipShape(Circle())
        }
    }
    
    private func weekTimeSlot(hour: Int) -> some View {
        let time = String(format: "%02d:00", hour)
        let isBusinessHour = hour >= 8 && hour < 18 // 8am to 6pm
        
        return VStack(spacing: 0) {
            Text(time)
                .font(.caption)
                .fontWeight(isBusinessHour ? .medium : .regular)
                .foregroundColor(isBusinessHour ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
            
            Spacer()
        }
    }
    
    private func weekDayColumn(date: Date) -> some View {
        let dayEvents = getEventsForDate(date)
        
        return ZStack(alignment: .topLeading) {
            // Background grid
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    VStack(spacing: 0) {
                        // Hour line
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                        
                        // Hour background with vertical grid lines
                        Rectangle()
                            .fill(Color(.systemGray6).opacity(0.3))
                            .frame(height: 99)
                            .overlay(
                                // Add subtle vertical dividers for column separation
                                VStack {
                                    Spacer()
                                }
                                .background(Color(.systemGray6).opacity(0.2))
                            )
                            .overlay(
                                // Add horizontal half-hour line
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 0.5)
                                    .offset(y: 49.5)
                            )
                    }
                }
            }
            
            // Events overlay
            ForEach(dayEvents, id: \.id) { event in
                weekEventBlock(event: event, date: date)
            }
            
            // Current time line (only for today)
            if Calendar.current.isDate(date, inSameDayAs: Date()) {
                weekCurrentTimeLine
            }
        }
    }
    
    private func getEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = (authManager.isLinked(kind: .personal) ? calendarViewModel.personalEvents : []) +
                        (authManager.isLinked(kind: .professional) ? calendarViewModel.professionalEvents : [])
        
        return allEvents.filter { event in
            // Skip all-day events for now (they are shown in the header)
            guard !event.isAllDay,
                  let startTime = event.startTime else { return false }
            
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }
    
    // New function that includes ALL events (both all-day and timed) for the TimelineComponent
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = (authManager.isLinked(kind: .personal) ? calendarViewModel.personalEvents : []) +
                        (authManager.isLinked(kind: .professional) ? calendarViewModel.professionalEvents : [])
        
        return allEvents.filter { event in
            guard let startTime = event.startTime else { return false }
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }
    
    private func getAllDayEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = (authManager.isLinked(kind: .personal) ? calendarViewModel.personalEvents : []) +
                        (authManager.isLinked(kind: .professional) ? calendarViewModel.professionalEvents : [])
        
        return allEvents.filter { event in
            guard event.isAllDay else { return false }
            
            // For all-day events, check if the date falls within the event's date range
            if let startTime = event.startTime {
                return calendar.isDate(startTime, inSameDayAs: date)
            }
            
            return false
        }
    }
    
    private func weekAllDayEventsSection(weekDates: [Date]) -> some View {
        let hasAnyAllDayEvents = weekDates.contains { date in
            !getAllDayEventsForDate(date).isEmpty
        }
        
        guard hasAnyAllDayEvents else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Time column placeholder
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 60)
                    
                    // All-day events for each day
                    ForEach(weekDates, id: \.self) { date in
                        weekAllDayEventsColumn(date: date)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.systemGray6).opacity(0.1))
                
                Divider()
            }
        )
    }
    
    private func weekAllDayEventsColumn(date: Date) -> some View {
        let allDayEvents = getAllDayEventsForDate(date)
        
        return VStack(spacing: 2) {
            ForEach(allDayEvents, id: \.id) { event in
                weekAllDayEventBlock(event: event)
            }
            
            if allDayEvents.isEmpty {
                // Empty space to maintain consistent height
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, 2)
    }
    
    private func weekAllDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let backgroundColor = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor.opacity(0.8))
            .frame(height: 20)
            .overlay(
                Text(event.summary)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            )
    }
    
    private func weekEventBlock(event: GoogleCalendarEvent, date: Date) -> AnyView {
        guard let startTime = event.startTime,
              let endTime = event.endTime else {
            return AnyView(EmptyView())
        }
        
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        let startHour = startComponents.hour ?? 0
        let startMinute = startComponents.minute ?? 0
        let _ = endComponents.hour ?? 0  // End hour not needed for current calculation
        let _ = endComponents.minute ?? 0  // End minute not needed for current calculation
        
        // Calculate position and height (100pt per hour - same as day view)
        let topOffset = CGFloat(startHour) * 100.0 + CGFloat(startMinute) * (100.0 / 60.0) // 1.67pt per minute
        let duration = endTime.timeIntervalSince(startTime)
        let durationMinutes = duration / 60.0
        // Use same scale as day view for consistency
        let height = max(30.0, CGFloat(durationMinutes) * (100.0 / 60.0)) // Minimum 30pt height, 1.67pt per minute
        
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let backgroundColor = isPersonal ? appPrefs.personalColor.opacity(0.7) : appPrefs.professionalColor.opacity(0.7)
        
        let view = AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .frame(height: height)
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        
                        if height > 60 {
                            Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
                .offset(y: topOffset)
                .padding(.horizontal, 2)
                // No long-press action for placeholder string events
        )
        let mod = view
            .onTapGesture { onEventLongPress(event) }
            .onLongPressGesture { onEventLongPress(event) }
        return AnyView(mod)
    }
    
    private var weekCurrentTimeLine: some View {
        let currentTime = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour) * 100.0 + CGFloat(minute) * (100.0 / 60.0)
        
        return Rectangle()
            .fill(Color.red)
            .frame(height: 2)
            .offset(y: yOffset)
            .zIndex(100)
    }

    // Real event data from Google Calendar
    private func getPersonalEvent(for slot: Int) -> String? {
        return getEventForTimeSlot(slot, events: calendarViewModel.personalEvents)
    }
    
    private func getProfessionalEvent(for slot: Int) -> String? {
        return getEventForTimeSlot(slot, events: calendarViewModel.professionalEvents)
    }
    
    private func getEventForTimeSlot(_ slot: Int, events: [GoogleCalendarEvent]) -> String? {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        
        let calendar = Calendar.current
        let slotTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: currentDate) ?? currentDate
        
        // Find events that overlap with this time slot (excluding all-day events)
        for event in events {
            // Skip all-day events (they are shown separately at the top)
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            // Check if the slot time falls within the event duration
            if slotTime >= startTime && slotTime < endTime {
                return event.summary
            }
        }
        
        return nil
    }
    
    private func getAllDayEvents() -> [GoogleCalendarEvent] {
        let allEvents = (authManager.isLinked(kind: .personal) ? calendarViewModel.personalEvents : []) +
                        (authManager.isLinked(kind: .professional) ? calendarViewModel.professionalEvents : [])
        return allEvents.filter { $0.isAllDay }
    }
    
    private func allDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let color: Color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var topLeftDaySection: some View {
        HStack(spacing: 8) {
            // Personal Tasks
            let personalFiltered = filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate)
            if authManager.isLinked(kind: .personal) && !personalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksViewModel.personalTaskLists,
                    tasksDict: personalFiltered,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                            updateCachedTasks()
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                // Empty state in Day view, placed in Tasks area
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view and manage your tasks")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Professional Tasks
            let professionalFiltered = filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate)
            if authManager.isLinked(kind: .professional) && !professionalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksViewModel.professionalTaskLists,
                    tasksDict: professionalFiltered,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                            updateCachedTasks()
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    

    
    private func personalTaskListCard(taskList: GoogleTaskList, tasks: [GoogleTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task list header
            HStack {
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(appPrefs.personalColor)
                
                Spacer()
                
                // Removed task count display
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    personalTaskRow(task: task, taskListId: taskList.id)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    private func isDueDateOverdue(_ dueDate: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return dueDate < startOfToday
    }
    

    
    private func personalTaskRow(task: GoogleTask, taskListId: String) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: taskListId, for: .personal)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? appPrefs.personalColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Text(dueDate, formatter: Self.dateFormatter)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDueDateOverdue(dueDate) && !task.isCompleted ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate) && !task.isCompleted ? .red : .secondary)
                }
            }
        }
        .onLongPressGesture {
            selectedTask = task
            selectedTaskListId = taskListId
            selectedAccountKind = .personal
            DispatchQueue.main.async {
                showingTaskDetails = true
            }
        }
    }
    
    private var topRightDaySection: some View {
        TasksComponent(
            taskLists: tasksViewModel.professionalTaskLists,
            tasksDict: filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate),
            accentColor: appPrefs.professionalColor,
            accountType: .professional,
            onTaskToggle: { task, listId in
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                    updateCachedTasks()
                }
            },
            onTaskDetails: { task, listId in
                selectedTask = task
                selectedTaskListId = listId
                selectedAccountKind = .professional
                DispatchQueue.main.async {
                    showingTaskDetails = true
                }
            },
            onListRename: { listId, newName in
                Task {
                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                }
            },
            onOrderChanged: { newOrder in
                Task {
                    await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                }
            }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var topThirdDaySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Third Column")
                    .font(.headline)
                Spacer()
                Text("Available for future features")
                    .foregroundColor(.secondary)
                Spacer()
             }
         }
        .frame(maxHeight: .infinity)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func professionalTaskListCard(taskList: GoogleTaskList, tasks: [GoogleTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task list header
            HStack {
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(appPrefs.professionalColor)
                
                Spacer()
                
                // Removed task count display
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    professionalTaskRow(task: task, taskListId: taskList.id)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private func professionalTaskRow(task: GoogleTask, taskListId: String) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: taskListId, for: .professional)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? appPrefs.professionalColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Text(dueDate, formatter: Self.dateFormatter)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDueDateOverdue(dueDate) && !task.isCompleted ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate) && !task.isCompleted ? .red : .secondary)
                }
            }
        }
        .onLongPressGesture {
            selectedTask = task
            selectedTaskListId = taskListId
            selectedAccountKind = .professional
            DispatchQueue.main.async {
                showingTaskDetails = true
            }
        }
    }
    

    
    // MARK: - Photo Library Permission Methods
    private func requestPhotoLibraryAccess() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch currentStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.photoLibraryAuthorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.showingPhotoPicker = true
                    } else {
                        self.showingPhotoPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingPhotoPermissionAlert = true
        case .authorized, .limited:
            showingPhotoPicker = true
        @unknown default:
            showingPhotoPermissionAlert = true
        }
    }
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private func handleSelectedPhoto(_ photo: PhotosPickerItem) {
        Task {
            if let data = try? await photo.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    // Add the image to our array of selected images
                    selectedImages.append(uiImage)
                    
                    // Reset the selection for next time
                    selectedPhoto = nil
                }
            }
        }
    }
    

    
    // MARK: - Helper Methods for Real Tasks
    private func updateCachedTasks() {
        
        cachedPersonalTasks = authManager.isLinked(kind: .personal) ? filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate) : [:]
        cachedProfessionalTasks = authManager.isLinked(kind: .professional) ? filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate) : [:]
        
        
        // Debug: Print first few task titles to verify content
        let personalTaskTitles = cachedPersonalTasks.values.flatMap { $0 }.prefix(3).map { $0.title }
        let professionalTaskTitles = cachedProfessionalTasks.values.flatMap { $0 }.prefix(3).map { $0.title }
        
        // Force UI update
        DispatchQueue.main.async {
            // This should trigger a UI refresh
        }
        
        updateMonthCachedTasks() // Also update month cached tasks
    }
    

    
    private func updateMonthCachedTasks() {
        cachedMonthPersonalTasks = authManager.isLinked(kind: .personal) ? filteredTasksForMonth(tasksViewModel.personalTasks, date: currentDate) : [:]
        cachedMonthProfessionalTasks = authManager.isLinked(kind: .professional) ? filteredTasksForMonth(tasksViewModel.professionalTasks, date: currentDate) : [:]
    }
    
    private func filteredTasksForDate(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.current
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // First, filter by hide completed tasks setting if enabled
            if appPrefs.hideCompletedTasks {
                filteredTasks = filteredTasks.filter { !$0.isCompleted }
            }
            
            // Then filter tasks based on date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    let isOnSameDay = calendar.isDate(completionDate, inSameDayAs: date)
                    
                    // Debug logging for completion date issues
                    if !isOnSameDay {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                    }
                    
                    return isOnSameDay ? task : nil
                } else {
                    // For incomplete tasks, show them on due date OR, if viewing today, show overdue
                    guard let dueDate = task.dueDate else { return nil }

                    let startOfViewedDate = calendar.startOfDay(for: date)
                    let startOfDueDate = calendar.startOfDay(for: dueDate)
                    let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: date)
                    let isViewingToday = calendar.isDate(date, inSameDayAs: Date())
                    let startOfToday = calendar.startOfDay(for: Date())
                    let isOverdueRelativeToToday = startOfDueDate < startOfToday

                    // Include if due on the viewed date, or if we're looking at today and the task is overdue relative to today
                    let include = isDueOnViewedDate || (isViewingToday && isOverdueRelativeToToday)

                    if include {
                    } else {
                    }

                    return include ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func filteredTasksForWeek(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return [:]
        }
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // First, filter by hide completed tasks setting if enabled
            if appPrefs.hideCompletedTasks {
                filteredTasks = filteredTasks.filter { !$0.isCompleted }
            }
            
            // Then filter tasks based on week date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    return completionDate >= weekStart && completionDate < weekEnd ? task : nil
                } else {
                    // For incomplete tasks, only show them if their due date is within the week
                    guard let dueDate = task.dueDate else { return nil }
                    
                    // Only include tasks with due dates within the week (no overdue tasks from previous weeks)
                    return dueDate >= weekStart && dueDate < weekEnd ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func filteredTasksForMonth(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return [:]
        }
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // First, filter by hide completed tasks setting if enabled
            if appPrefs.hideCompletedTasks {
                filteredTasks = filteredTasks.filter { !$0.isCompleted }
            }
            
            // Then filter tasks based on month date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    return completionDate >= monthStart && completionDate < monthEnd ? task : nil
                } else {
                    // For incomplete tasks, only show them if their due date is within the month
                    guard let dueDate = task.dueDate else { return nil }
                    
                    // Only include tasks with due dates within the month (no overdue tasks from previous months)
                    return dueDate >= monthStart && dueDate < monthEnd ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func onEventLongPress(_ ev: GoogleCalendarEvent) {
        selectedCalendarEvent = ev
        showingEventDetails = true
    }
}

// MARK: - Week PencilKit View
struct WeekPencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 15)
        canvasView.drawingPolicy = .anyInput
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update if needed
    }
}



// GameChanger removed

struct LargeMonthCardView: View {
    let month: Int
    let year: Int
    let currentDate: Date
    
    private var monthName: String {
        Calendar.mondayFirst.monthSymbols[month - 1]
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return Calendar.mondayFirst.component(.year, from: today) == year &&
               Calendar.mondayFirst.component(.month, from: today) == month
    }
    
    private var currentDay: Int {
        Calendar.mondayFirst.component(.day, from: currentDate)
    }
    
    private var monthData: (daysInMonth: Int, offsetDays: Int) {
        let calendar = Calendar.mondayFirst
        let monthDate = calendar.date(from: DateComponents(year: year, month: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let offsetDays = (firstWeekday + 5) % 7
        return (daysInMonth, offsetDays)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Week headers
            HStack(spacing: 4) {
                Text("Week")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 50)
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { week in
                    largeWeekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func largeWeekRow(week: Int) -> some View {
        HStack(spacing: 4) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 50, height: 40)
            
            // Days
            ForEach(0..<7, id: \.self) { dayOfWeek in
                largeDayCell(week: week, dayOfWeek: dayOfWeek)
            }
        }
    }
    
    private func largeDayCell(week: Int, dayOfWeek: Int) -> some View {
        let dayNumber = week * 7 + dayOfWeek - monthData.offsetDays + 1
        let isValidDay = dayNumber > 0 && dayNumber <= monthData.daysInMonth
        let isToday = isCurrentMonth && dayNumber == currentDay
        
        return Group {
            if isValidDay {
                Text("\(dayNumber)")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
        }
    }
    
    private func getWeekNumber(for week: Int) -> String {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = (firstWeekday + 5) % 7
        
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth),
              let currentWeekDate = calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek) else {
            return ""
        }
        
        let weekNumber = calendar.component(.weekOfYear, from: currentWeekDate)
        return weekNumber > 0 ? "\(weekNumber)" : ""
    }
}

struct MonthCardView: View {
    let month: Int
    let year: Int
    let currentDate: Date
    let onDayTap: (Date) -> Void
    let onMonthTap: () -> Void
    let onWeekTap: (Date) -> Void
    
    private var monthName: String {
        Calendar.mondayFirst.monthSymbols[month - 1]
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return Calendar.mondayFirst.component(.year, from: today) == year &&
               Calendar.mondayFirst.component(.month, from: today) == month
    }
    
    private var currentDay: Int {
        Calendar.mondayFirst.component(.day, from: currentDate)
    }
    
    private var monthData: (daysInMonth: Int, offsetDays: Int) {
        let calendar = Calendar.mondayFirst
        let monthDate = calendar.date(from: DateComponents(year: year, month: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let offsetDays = (firstWeekday + 5) % 7
        return (daysInMonth, offsetDays)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Month title
            Text(monthName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isCurrentMonth ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrentMonth ? Color.blue : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { onMonthTap() }
            
            // Week headers
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 20)
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    weekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            onDayTap(currentDate)
        }
    }
    
    private func weekRow(week: Int) -> some View {
        HStack(spacing: 2) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let weekStart = getWeekStartDate(for: week) {
                        onWeekTap(weekStart)
                    }
                }
            
            // Days
            ForEach(0..<7, id: \.self) { dayOfWeek in
                dayCell(week: week, dayOfWeek: dayOfWeek)
            }
        }
    }
    
    private func dayCell(week: Int, dayOfWeek: Int) -> some View {
        let dayNumber = week * 7 + dayOfWeek - monthData.offsetDays + 1
        let isValidDay = dayNumber > 0 && dayNumber <= monthData.daysInMonth
        let isToday = isCurrentMonth && dayNumber == currentDay
        
        return Group {
            if isValidDay {
                Text("\(dayNumber)")
                    .font(.body)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let calendar = Calendar.mondayFirst
                        if let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) {
                            onDayTap(date)
                        }
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
        }
    }
    
    private func getWeekNumber(for week: Int) -> String {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = (firstWeekday + 5) % 7
        
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth),
              let currentWeekDate = calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek) else {
            return ""
        }
        
        let weekNumber = calendar.component(.weekOfYear, from: currentWeekDate)
        return weekNumber > 0 ? "\(weekNumber)" : ""
    }
    
    private func getWeekStartDate(for week: Int) -> Date? {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let offsetDays = (firstWeekday + 5) % 7
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -offsetDays, to: firstDayOfMonth) else { return nil }
        return calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek)
    }
}

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    /// Controls whether the system PKToolPicker is visible. Defaults to `true` to
    /// keep existing behaviour for call-sites that don't specify the argument.
    var showsToolPicker: Bool = true
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear

        // Present (or hide) the system tool picker (colour, stroke, eraser …)
        if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first,
           let toolPicker = PKToolPicker.shared(for: window) {
            toolPicker.setVisible(showsToolPicker, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            if showsToolPicker {
                DispatchQueue.main.async { // ensure first responder after view attached
                    canvasView.becomeFirstResponder()
                }
            }
        }

        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update tool-picker visibility when state changes
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first,
              let toolPicker = PKToolPicker.shared(for: window) else { return }
        toolPicker.setVisible(showsToolPicker, forFirstResponder: uiView)
        if showsToolPicker {
            // Become first-responder so the picker can attach
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else {
            // Hide keyboard / resign when picker hidden
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
}



// MARK: - Add Item View
struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0 // 0 = Task, 1 = Calendar Event
    @State private var itemTitle = ""
    @State private var itemNotes = ""
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var selectedTaskListId = ""
    @State private var newTaskListName = ""
    @State private var isCreatingNewList = false
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var isCreating = false
    @State private var eventStart: Date
    @State private var eventEnd: Date
    @State private var isAllDay = false
    
    let currentDate: Date
    let tasksViewModel: TasksViewModel
    let calendarViewModel: CalendarViewModel
    let appPrefs: AppPreferences
    let existingEvent: GoogleCalendarEvent?
    let existingEventAccountKind: GoogleAuthManager.AccountKind?
    let showEventOnly: Bool
    
    private let authManager = GoogleAuthManager.shared
    
    private var availableTaskLists: [GoogleTaskList] {
        guard let accountKind = selectedAccountKind else { return [] }
        switch accountKind {
        case .personal:
            return tasksViewModel.personalTaskLists
        case .professional:
            return tasksViewModel.professionalTaskLists
        }
    }
    
    private var canCreateTask: Bool {
        !itemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedAccountKind != nil &&
        ((!isCreatingNewList && !selectedTaskListId.isEmpty) || 
         (isCreatingNewList && !newTaskListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    
    private var canCreateEvent: Bool {
        !itemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isEditingEvent || selectedAccountKind != nil) && (isAllDay || eventEnd > eventStart)
    }
    
    private var accentColor: Color {
        guard let accountKind = selectedAccountKind else { return .accentColor }
        return accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    private var isEditingEvent: Bool { existingEvent != nil }
    
    init(currentDate: Date,
         tasksViewModel: TasksViewModel,
         calendarViewModel: CalendarViewModel,
         appPrefs: AppPreferences,
         existingEvent: GoogleCalendarEvent? = nil,
         accountKind: GoogleAuthManager.AccountKind? = nil,
         showEventOnly: Bool = false) {
        self.currentDate = currentDate
        self.tasksViewModel = tasksViewModel
        self.calendarViewModel = calendarViewModel
        self.appPrefs = appPrefs
        self.existingEvent = existingEvent
        self.existingEventAccountKind = accountKind
        self.showEventOnly = showEventOnly
        // default times
        let cal = Calendar.current
        if let ev = existingEvent {
            // Editing path – prefill
            _selectedTab = State(initialValue: 1)
            _itemTitle = State(initialValue: ev.summary)
            _itemNotes = State(initialValue: ev.description ?? "")
            _selectedAccountKind = State(initialValue: accountKind)
            _eventStart = State(initialValue: ev.startTime ?? Date())
            _eventEnd   = State(initialValue: ev.endTime ?? (ev.startTime ?? Date()).addingTimeInterval(1800))
            _isAllDay = State(initialValue: ev.isAllDay)
        } else {
            let rounded = cal.nextDate(after: Date(), matching: DateComponents(minute: cal.component(.minute, from: Date()) < 30 ? 30 : 0), matchingPolicy: .nextTime, direction: .forward) ?? Date()
            _eventStart = State(initialValue: rounded)
            _eventEnd = State(initialValue: cal.date(byAdding: .minute, value: 30, to: rounded)!)
            if showEventOnly {
                _selectedTab = State(initialValue: 1)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector (hidden when creating event-only, or editing an existing event)
                if !(showEventOnly || isEditingEvent) {
                    Picker("Type", selection: $selectedTab) {
                        Text("Task").tag(0)
                        Text("Calendar Event").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                }

                Form {
                    Section("Basic Information") {
                        HStack {
                            Text(selectedTab == 0 ? "Task Title" : "Event Title")
                            TextField("Enter title", text: $itemTitle)
                                .multilineTextAlignment(.trailing)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedTab == 0 ? "Notes" : "Description")
                            TextField("Add notes (optional)", text: $itemNotes, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    Section("Account") {
                        HStack(spacing: 12) {
                            if authManager.isLinked(kind: .personal) {
                                Button(action: {
                                    selectedAccountKind = .personal
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text("Personal")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .personal ? appPrefs.personalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .personal ? appPrefs.personalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .personal ? appPrefs.personalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if authManager.isLinked(kind: .professional) {
                                Button(action: {
                                    selectedAccountKind = .professional
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                }) {
                                    HStack {
                                        Image(systemName: "briefcase.circle.fill")
                                        Text("Professional")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .professional ? appPrefs.professionalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .professional ? appPrefs.professionalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .professional ? appPrefs.professionalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }

                    if selectedTab == 0 {
                        // Task-specific fields
                        if selectedAccountKind != nil {
                            Section("Task List") {
                                VStack(spacing: 8) {
                                    // Create New List Option
                                    HStack {
                                        Button(action: {
                                            isCreatingNewList.toggle()
                                            if isCreatingNewList {
                                                selectedTaskListId = ""
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: isCreatingNewList ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(isCreatingNewList ? accentColor : .secondary)
                                                Text("Create new list")
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        Spacer()
                                    }

                                    if isCreatingNewList {
                                        TextField("New list name", text: $newTaskListName)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .padding(.leading, 28)
                                    }

                                    // Existing Lists
                                    if !isCreatingNewList && !availableTaskLists.isEmpty {
                                        ForEach(availableTaskLists) { taskList in
                                            HStack {
                                                Button(action: {
                                                    selectedTaskListId = taskList.id
                                                }) {
                                                    HStack {
                                                        Image(systemName: selectedTaskListId == taskList.id ? "checkmark.circle.fill" : "circle")
                                                            .foregroundColor(selectedTaskListId == taskList.id ? accentColor : .secondary)
                                                        Text(taskList.title)
                                                    }
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Section("Due Date") {
                            HStack {
                                Button(action: {
                                    hasDueDate.toggle()
                                    if !hasDueDate {
                                        dueDate = nil
                                    } else {
                                        dueDate = currentDate
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: hasDueDate ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(hasDueDate ? accentColor : .secondary)
                                        Text("Set due date")
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }

                            if hasDueDate {
                                DatePicker("Due Date", selection: Binding(
                                    get: { dueDate ?? currentDate },
                                    set: { dueDate = $0 }
                                ), displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .frame(maxHeight: 400)
                                .environment(\.calendar, Calendar.mondayFirst)
                            }
                        }
                    } else {
                        // Calendar event-specific fields
                        Section("Event Time") {
                            Toggle("All Day", isOn: $isAllDay)
                            DatePicker("Start", selection: $eventStart, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                .environment(\.calendar, Calendar.mondayFirst)
                            DatePicker("End", selection: $eventEnd, in: eventStart..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                .environment(\.calendar, Calendar.mondayFirst)
                        }
                    }
                }
                .onChange(of: isAllDay) { oldValue, newValue in
                    let cal = Calendar.current
                    if newValue {
                        let startDate = cal.startOfDay(for: eventStart)
                        eventStart = startDate
                        eventEnd = cal.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(24*3600)
                    } else {
                        let base = eventStart > Date.distantPast ? eventStart : Date()
                        let minute = cal.component(.minute, from: base)
                        let rounded = cal.nextDate(
                            after: base,
                            matching: DateComponents(minute: minute < 30 ? 30 : 0),
                            matchingPolicy: .nextTime,
                            direction: .forward
                        ) ?? base
                        eventStart = rounded
                        eventEnd = cal.date(byAdding: .minute, value: 30, to: rounded) ?? rounded.addingTimeInterval(1800)
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "New Task" : (isEditingEvent ? "Edit Event" : "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selectedTab == 0 ? (isEditingEvent ? "Save" : "Create Task") : (isEditingEvent ? "Save" : "Create Event")) {
                        if isEditingEvent {
                            // Always update the existing event when in edit mode, regardless of tab
                            updateEvent()
                        } else {
                            if selectedTab == 0 {
                                createTask()
                            } else {
                                createEvent()
                            }
                        }
                    }
                    .disabled(isEditingEvent ? !canCreateEvent : (selectedTab == 0 ? !canCreateTask : !canCreateEvent))
                    .foregroundColor(accentColor)
                }
                
                // Removed delete button from top toolbar
            }
            // Add Delete section at bottom for editing event
            .safeAreaInset(edge: .bottom) {
                if isEditingEvent {
                    Button(role: .destructive) {
                        deleteEvent()
                    } label: {
                        Text("Delete Event")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            }
        }
    }
    
    private func createTask() {
        guard let accountKind = selectedAccountKind else { return }
        
        isCreating = true
        
        Task {
            do {
                if isCreatingNewList {
                    // Create new task list first
                    guard let newListId = await tasksViewModel.createTaskList(
                        title: newTaskListName.trimmingCharacters(in: .whitespacesAndNewlines),
                        for: accountKind
                    ) else {
                        throw TasksError.failedToCreateTaskList
                    }
                    
                    // Create task in new list
                    await tasksViewModel.createTask(
                        title: itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: itemNotes.isEmpty ? nil : itemNotes,
                        dueDate: dueDate,
                        in: newListId,
                        for: accountKind
                    )
                } else {
                    // Create task in existing list
                    await tasksViewModel.createTask(
                        title: itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: itemNotes.isEmpty ? nil : itemNotes,
                        dueDate: dueDate,
                        in: selectedTaskListId,
                        for: accountKind
                    )
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    // Handle error (could show alert)
                }
            }
        }
    }
    
    private func createEvent() {
        guard let accountKind = selectedAccountKind else { return }
        isCreating = true

        Task {
            do {
                let accessToken = try await authManager.getAccessToken(for: accountKind)
                
                let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.timeZone = TimeZone.current

                var startDict: [String: String] = [:]
                var endDict: [String: String] = [:]
                if isAllDay {
                    let startDate = Calendar.current.startOfDay(for: eventStart)
                    let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    startDict["date"] = dateFormatter.string(from: startDate)
                    endDict["date"] = dateFormatter.string(from: endDate)
                } else {
                    startDict["dateTime"] = isoFormatter.string(from: eventStart)
                    endDict["dateTime"] = isoFormatter.string(from: eventEnd)
                    // Provide explicit timeZone to satisfy Google Calendar API
                    startDict["timeZone"] = TimeZone.current.identifier
                    endDict["timeZone"] = TimeZone.current.identifier
                }

                var body: [String: Any] = [
                    "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    "start": startDict,
                    "end": endDict
                ]
                if !itemNotes.isEmpty { body["description"] = itemNotes }

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PlannerCalendarError.invalidResponse
                }
                
                
                guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    if let responseString = String(data: data, encoding: .utf8) {
                    }
                    throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
                }

                // Refresh both original and new dates so UI reflects time/day changes
                let originalEventDate = currentDate
                let newEventDate = eventStart
                Task {
                    await calendarViewModel.loadCalendarData(for: originalEventDate)
                    await calendarViewModel.loadCalendarData(for: newEventDate)
                }

                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }
    
    // MARK: - Update existing event
    private func updateEvent() {
        guard let ev = existingEvent else { return }
        guard let originalAccountKind = existingEventAccountKind else { return }
        let targetAccountKind = selectedAccountKind ?? originalAccountKind
        
        
        isCreating = true

        Task {
            do {
                // Check if we're moving between accounts
                if originalAccountKind != targetAccountKind {
                    
                    // First create the event in the new account
                    try await createEventInAccount(targetAccountKind)
                    
                    // Then delete the event from the original account
                    try await deleteEventFromAccount(ev, from: originalAccountKind)
                    
                } else {
                    // Same account - just update the existing event
                    try await updateEventInSameAccount(ev, accountKind: originalAccountKind)
                }

                // Refresh events for the currently visible date so UI reflects change immediately
                Task {
                    await calendarViewModel.loadCalendarData(for: currentDate)
                }
                
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }
    
    private func createEventInAccount(_ accountKind: GoogleAuthManager.AccountKind) async throws {
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone.current

        var startDict: [String: String] = [:]
        var endDict: [String: String] = [:]
        if isAllDay {
            let startDate = Calendar.current.startOfDay(for: eventStart)
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            startDict["date"] = dateFormatter.string(from: startDate)
            endDict["date"] = dateFormatter.string(from: endDate)
        } else {
            startDict["dateTime"] = isoFormatter.string(from: eventStart)
            endDict["dateTime"] = isoFormatter.string(from: eventEnd)
            startDict["timeZone"] = TimeZone.current.identifier
            endDict["timeZone"] = TimeZone.current.identifier
        }

        var body: [String: Any] = [
            "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": startDict,
            "end": endDict
        ]
        if !itemNotes.isEmpty { body["description"] = itemNotes }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
    }
    
    private func deleteEventFromAccount(_ event: GoogleCalendarEvent, from accountKind: GoogleAuthManager.AccountKind) async throws {
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let calId = event.calendarId ?? "primary"
        let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*", forHTTPHeaderField: "If-Match")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
    }
    
    private func updateEventInSameAccount(_ event: GoogleCalendarEvent, accountKind: GoogleAuthManager.AccountKind) async throws {
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let calId = event.calendarId ?? "primary"
        let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*", forHTTPHeaderField: "If-Match")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        isoFormatter.timeZone = TimeZone.current

        var startDict: [String: String] = [:]
        var endDict: [String: String] = [:]
        if isAllDay {
            let startDate = Calendar.current.startOfDay(for: eventStart)
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            startDict["date"] = dateFormatter.string(from: startDate)
            endDict["date"] = dateFormatter.string(from: endDate)
        } else {
            startDict["dateTime"] = isoFormatter.string(from: eventStart)
            endDict["dateTime"] = isoFormatter.string(from: eventEnd)
            startDict["timeZone"] = TimeZone.current.identifier
            endDict["timeZone"] = TimeZone.current.identifier
        }

        var body: [String: Any] = [
            "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": startDict,
            "end": endDict,
            // Always include description so clearing notes works
            "description": itemNotes
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
    }
    
    // MARK: - Delete Event
    private func deleteEvent() {
        guard let ev = existingEvent, let accountKind = existingEventAccountKind ?? selectedAccountKind else { return }
        isCreating = true
        Task {
            do {
                let accessToken = try await authManager.getAccessToken(for: accountKind)
                let calId = ev.calendarId ?? "primary"
                let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
                let encodedEventId = ev.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ev.id
                let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("*", forHTTPHeaderField: "If-Match")

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
                    throw CalendarManager.shared.handleHttpError((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                await calendarViewModel.loadCalendarData(for: currentDate)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }
}

#Preview {
    CalendarView()
} 