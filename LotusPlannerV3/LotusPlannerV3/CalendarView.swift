import SwiftUI
import UIKit
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

enum CalendarError: Error {
    case noAccessToken
    case authenticationFailed
    case accessDenied
    case apiError(Int)
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
        isLoading = true
        errorMessage = nil
        
        print("🔄 Loading month calendar data...")
        print("  Personal account linked: \(authManager.isLinked(kind: .personal))")
        print("  Professional account linked: \(authManager.isLinked(kind: .professional))")
        
        // Get the month range
        let calendar = Calendar.mondayFirst
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            isLoading = false
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadCalendarDataForMonthRange(.personal, startDate: monthStart, endDate: monthEnd)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadCalendarDataForMonthRange(.professional, startDate: monthStart, endDate: monthEnd)
                }
            }
        }
        
        print("✅ Finished loading month calendar data")
        print("  Final personal events: \(personalEvents.count)")
        print("  Final professional events: \(professionalEvents.count)")
        
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
        print("📅 Fetching calendars for \(kind) account...")
        print("  🔍 Account linked status: \(authManager.isLinked(kind: kind))")
        print("  📧 Account email: \(authManager.getEmail(for: kind))")
        
        do {
            let accessToken = try await authManager.getAccessToken(for: kind)
            print("🔑 Got access token for \(kind): \(accessToken.prefix(20))...")
            
            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            print("🌐 Making calendar API request for \(kind)...")
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            
            if let response = httpResponse as? HTTPURLResponse {
                print("📊 Calendar API response status for \(kind): \(response.statusCode)")
                if response.statusCode != 200 {
                    print("❌ Calendar API error for \(kind) - Status: \(response.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📄 Response body: \(responseString)")
                    }
                    
                    // Throw a more specific error for different status codes
                    if response.statusCode == 401 {
                        throw CalendarError.authenticationFailed
                    } else if response.statusCode == 403 {
                        throw CalendarError.accessDenied
                    } else {
                        throw CalendarError.apiError(response.statusCode)
                    }
                }
            }
            
            let response = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
            let calendars = response.items ?? []
            print("✅ Successfully fetched \(calendars.count) calendars for \(kind)")
            
            // Debug: Print calendar details
            for calendar in calendars {
                print("  📅 Calendar: \(calendar.summary) (ID: \(calendar.id))")
            }
            
            return calendars
        } catch {
            print("❌ Error fetching calendars for \(kind): \(error)")
            print("  🔍 Error details: \(error.localizedDescription)")
            
            // Add more specific error information
            if let urlError = error as? URLError {
                print("  🌐 Network error: \(urlError.localizedDescription)")
                print("  📡 Network code: \(urlError.code.rawValue)")
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
                print("Failed to fetch events for calendar \(calendarItem.summary): \(error)")
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
            print("📅 Loading \(kind.rawValue) calendar data for month range...")
            let calendars = try await fetchCalendars(for: kind)
            print("  Found \(calendars.count) \(kind.rawValue) calendars")
            
            let events = try await fetchEventsForDateRange(startDate: startDate, endDate: endDate, calendars: calendars, for: kind)
            print("  Found \(events.count) \(kind.rawValue) events")
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalCalendars = calendars
                    self.personalEvents = events
                    print("  ✅ Set \(events.count) personal events")
                case .professional:
                    self.professionalCalendars = calendars
                    self.professionalEvents = events
                    print("  ✅ Set \(events.count) professional events")
                }
            }
        } catch {
            print("  ❌ Error loading \(kind.rawValue) calendar data: \(error)")
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
                print("Failed to fetch events for calendar \(calendarItem.summary): \(error)")
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



// Common interval types for timeline navigation
private enum TimelineInterval: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year"

    var id: String { rawValue }

    fileprivate var calendarComponent: Calendar.Component {
        switch self {
        case .day:     return .day
        case .week:    return .weekOfYear
        case .month:   return .month
        case .year:    return .year
        }
    }
}

struct CalendarView: View {
    @StateObject private var calendarViewModel = CalendarViewModel()
    @StateObject private var tasksViewModel = TasksViewModel()
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var currentDate = Date()
    @State private var interval: TimelineInterval = .day
    @State private var topSectionHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    @State private var rightSectionTopHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    @State private var leftTimelineHeight: CGFloat = UIScreen.main.bounds.height * 0.75
    @State private var isDragging = false
    @State private var isRightDividerDragging = false
    @State private var isLeftDividerDragging = false
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
    @State private var showingAddItem = false
    @State private var currentTimeTimer: Timer?
    @State private var currentTimeSlot: Double = 0
    @State private var movablePhotos: [MovablePhoto] = []
    @State private var cachedPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var weekTasksSectionWidth: CGFloat = UIScreen.main.bounds.width * 0.6
    @State private var isWeekTasksDividerDragging = false
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
    
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    
    var body: some View {
        GeometryReader { geometry in
            splitScreenContent(geometry: geometry)
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarButtons
            }

            ToolbarItemGroup(placement: .principal) {
                principalToolbarContent
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                trailingToolbarButtons
            }
        }
    }
    
    private func splitScreenContent(geometry: GeometryProxy) -> some View {
        // Just show the main content without any overlay panels
        mainContentView
    }
    

    
    private var leadingToolbarButtons: some View {
        Group {
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            Button("Today") { currentDate = Date() }
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    private var principalToolbarContent: some View {
        Group {
            if interval == .year {
                Text(String(Calendar.current.component(.year, from: currentDate)))
                    .font(.title2)
                    .fontWeight(.semibold)
            } else if interval == .month {
                Text(monthYearTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
            } else if interval == .week {
                Text(weekTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
            } else if interval == .day {
                Text(dayTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
    }
    
    private var trailingToolbarButtons: some View {
        Group {
            // Add button for tasks/events (available in all views)
            Button(action: {
                showingAddItem = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            
            ForEach(TimelineInterval.allCases) { item in
                Button(item.rawValue) { interval = item }
                    .fontWeight(item == interval ? .bold : .regular)
            }
        }
    }
    
    private var mainContentView: some View {
        Group {
            if interval == .year {
                yearView
            } else if interval == .month {
                monthView
            } else if interval == .week {
                weekView
            } else if interval == .day {
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
        if let newDate = Calendar.current.date(byAdding: interval.calendarComponent,
                                               value: direction,
                                               to: currentDate) {
            currentDate = newDate
        }
    }
    
    private var yearView: some View {
        monthsSection
            .background(Color(.systemBackground))
    }
    
    private var monthsSection: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(1...12, id: \.self) { month in
                    MonthCardView(
                        month: month,
                        year: Calendar.current.component(.year, from: currentDate),
                        currentDate: Date()
                    )
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
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
            PersonalTasksComponent(
                taskLists: tasksViewModel.personalTaskLists,
                tasksDict: cachedMonthPersonalTasks,
                accentColor: appPrefs.personalColor,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    selectedTask = task
                    selectedTaskListId = listId
                    selectedAccountKind = .personal
                    DispatchQueue.main.async {
                        showingTaskDetails = true
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.all, 8)
            
            // Professional Tasks Component  
            ProfessionalTasksComponent(
                taskLists: tasksViewModel.professionalTaskLists,
                tasksDict: cachedMonthProfessionalTasks,
                accentColor: appPrefs.professionalColor,
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
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.all, 8)
            
            // Scrapbook Component
            ScrapbookComponent(canvasView: $monthCanvasView, currentDate: currentDate, accountKind: .personal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.all, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Week Bottom Section
    
    private var weekBottomSection: some View {
        GeometryReader { geometry in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var weekTasksSection: some View {
        VStack {
            Text("Week Tasks")
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            Text("Week tasks coming soon...")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private var weekTasksDivider: some View {
        Rectangle()
            .fill(isWeekTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isWeekTasksDividerDragging ? .white : .gray)
                    .rotationEffect(.degrees(90))
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isWeekTasksDividerDragging = true
                        let newWidth = weekTasksSectionWidth + value.translation.width
                        weekTasksSectionWidth = max(200, min(UIScreen.main.bounds.width - 200, newWidth))
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
                // Top section - Single month calendar
                singleMonthSection
                    .frame(height: weekTopSectionHeight)
                
                // Draggable divider  
                weekDivider
                
                // Bottom section - Tasks side by side
                HStack(alignment: .top, spacing: 0) {
                    // Personal Tasks
                    PersonalTasksComponent(
                        taskLists: tasksViewModel.personalTaskLists,
                        tasksDict: cachedMonthPersonalTasks,
                        accentColor: appPrefs.personalColor,
                        onTaskToggle: { task, listId in
                            Task {
                                await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                updateCachedTasks()
                            }
                        },
                        onTaskDetails: { task, listId in
                            selectedTask = task
                            selectedTaskListId = listId
                            selectedAccountKind = .personal
                            DispatchQueue.main.async {
                                showingTaskDetails = true
                            }
                        }
                    )
                    .frame(width: geometry.size.width / 2)
                    
                    // Professional Tasks
                    ProfessionalTasksComponent(
                        taskLists: tasksViewModel.professionalTaskLists,
                        tasksDict: cachedMonthProfessionalTasks,
                        accentColor: appPrefs.professionalColor,
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
                        }
                    )
                    .frame(width: geometry.size.width / 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
    }

    private var monthYearTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }
    
    private var weekTitle: String {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Week"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startString = formatter.string(from: weekStart)
        let endString = formatter.string(from: weekEnd)
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: currentDate)
        
        return "\(startString) - \(endString), \(year)"
    }
    
    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: currentDate)
    }
    
    private var weekView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top section - Week Calendar
                weekCalendarSection
                    .frame(height: weekTopSectionHeight)
                
                // Draggable divider
                weekDivider
                
                // Bottom section - Tasks side by side
                HStack(alignment: .top, spacing: 0) {
                    // Personal Tasks
                    PersonalTasksComponent(
                        taskLists: tasksViewModel.personalTaskLists,
                        tasksDict: cachedWeekPersonalTasks,
                        accentColor: appPrefs.personalColor,
                        onTaskToggle: { task, listId in
                            Task {
                                await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                updateCachedTasks()
                            }
                        },
                        onTaskDetails: { task, listId in
                            selectedTask = task
                            selectedTaskListId = listId
                            selectedAccountKind = .personal
                            DispatchQueue.main.async {
                                showingTaskDetails = true
                            }
                        }
                    )
                    .frame(width: geometry.size.width / 2)
                    
                    // Professional Tasks
                    ProfessionalTasksComponent(
                        taskLists: tasksViewModel.professionalTaskLists,
                        tasksDict: cachedWeekProfessionalTasks,
                        accentColor: appPrefs.professionalColor,
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
                        }
                    )
                    .frame(width: geometry.size.width / 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .task {
            await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
            await tasksViewModel.loadTasks()
            updateCachedTasks()
        }
        .onChange(of: currentDate) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
            }
            updateCachedTasks()
        }
        .onChange(of: tasksViewModel.personalTasks) { oldValue, newValue in
            updateCachedTasks()
        }
        .onChange(of: tasksViewModel.professionalTasks) { oldValue, newValue in
            updateCachedTasks()
        }
        .onChange(of: appPrefs.hideRecurringEventsInMonth) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarDataForMonth(containing: currentDate)
            }
        }
    }
    
    private var weekCalendarSection: some View {
        Group {
            WeekTimelineComponent(
                currentDate: currentDate,
                weekEvents: getWeekEventsGroupedByDate(),
                personalEvents: calendarViewModel.personalEvents,
                professionalEvents: calendarViewModel.professionalEvents,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor
            )
        }
        .task {
            await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
        }
        .onChange(of: currentDate) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
            }
        }
    }
    
    private var singleMonthSection: some View {
        MonthTimelineComponent(
            currentDate: currentDate,
            monthEvents: getMonthEventsGroupedByDate(),
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor
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
                updateCachedTasks()
            }
            .onChange(of: currentDate) { oldValue, newValue in
                Task {
                    await calendarViewModel.loadCalendarData(for: newValue)
                }
                updateCachedTasks()
            }
            .onChange(of: tasksViewModel.personalTasks) { oldValue, newValue in
                updateCachedTasks()
            }
            .onChange(of: tasksViewModel.professionalTasks) { oldValue, newValue in
                updateCachedTasks()
            }
            .onChange(of: appPrefs.hideCompletedTasks) { oldValue, newValue in
                updateCachedTasks()
            }

            .onAppear {
                startCurrentTimeTimer()
            }
            .onDisappear {
                stopCurrentTimeTimer()
            }
    }
    
    private var dayViewBase: some View {
        GeometryReader { geometry in
            dayViewContent(geometry: geometry)
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
        .sheet(isPresented: $showingTaskDetails) {
            taskDetailsSheet
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs
            )
        }
        .sheet(isPresented: $showingEventDetails) {
            eventDetailsSheet
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
            CalendarEventDetailsView(event: ev) {
                // Delete action placeholder: remove from local arrays
                calendarViewModel.personalEvents.removeAll { $0.id == ev.id }
                calendarViewModel.professionalEvents.removeAll { $0.id == ev.id }
            }
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
    
    private func dayViewContent(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left section (dynamic width)
            leftDaySectionWithDivider(geometry: geometry)
                .frame(width: dayLeftSectionWidth)
            
            // Vertical divider
            dayVerticalDivider
            
            // Right section (remaining width)
            rightDaySection(geometry: geometry)
                .frame(width: geometry.size.width - dayLeftSectionWidth - 8) // 8 for divider width
        }
    }
    
    private func rightDaySection(geometry: GeometryProxy) -> some View {
        let rightSectionWidth = geometry.size.width - dayLeftSectionWidth - 8 // 8 for divider width
        
        return VStack(spacing: 0) {
            // Top section of right side - split into two columns for tasks
            HStack(alignment: .top, spacing: 0) {
                // Personal tasks (left column)
                topLeftDaySection
                    .frame(width: rightSectionWidth / 2, alignment: .topLeading)
                
                // Professional tasks (right column)
                topRightDaySection
                    .frame(width: rightSectionWidth / 2, alignment: .topLeading)
            }
            .frame(height: rightSectionTopHeight, alignment: .top)
            .padding(.all, 8)
            
            // Draggable divider
            rightSectionDivider
            
            // Bottom section - Scrapbook
            ScrapbookComponent(canvasView: $pencilKitCanvasView, currentDate: currentDate, accountKind: .personal)
                .frame(maxHeight: .infinity)
                .padding(.all, 8)
        }
    }
    
    private func setupDayView() -> some View {
        dayView
    }
    
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Timeline section (3/4 of left section height)
            leftTimelineSection
                .frame(height: leftTimelineHeight)
                .padding(.all, 8)
            
            // Left section divider
            leftSectionDivider
            
            // Bottom section (1/4 of left section height)
            leftBottomSection
                .frame(height: max(200, geometry.size.height - leftTimelineHeight - 8))
                .padding(.all, 8)
        }
    }
    
    private var leftTimelineSection: some View {
        TimelineComponent(
            date: currentDate,
            events: getAllEventsForDate(currentDate),
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor
        )
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
    
    private var leftSectionDivider: some View {
        Rectangle()
            .fill(isLeftDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLeftDividerDragging ? .white : .gray)
            )

            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLeftDividerDragging = true
                        let newHeight = leftTimelineHeight + value.translation.height
                        leftTimelineHeight = max(200, min(UIScreen.main.bounds.height - 200, newHeight))
                    }
                    .onEnded { _ in
                        isLeftDividerDragging = false
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
    
    private var leftBottomSection: some View {
        LogsComponent(currentDate: currentDate)
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
                            // Temporarily removed drag gesture due to compilation issues
                // TODO: Implement moveable photos later
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
                        .fontWeight(.medium)
                        .foregroundColor(color)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                    
                    if event.height >= 50 { // Show time only if event is tall enough
                        Text(formatEventTime(event.event))
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.7))
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
    private func miniDayEventView(event: GoogleCalendarEvent, dayWidth: CGFloat) -> some View {
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
        
        return AnyView(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor.opacity(0.8))
                .frame(height: height)
                .overlay(
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.summary)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(height > 40 ? 2 : 1)
                        
                        if height > 30 {
                            Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
                .offset(y: topOffset)
                .padding(.horizontal, 1) // Small padding to prevent events from touching edges
        )
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
    
    // Group week events by date for the WeekTimelineComponent
    private func getWeekEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        let weekDates = getWeekDates()
        var eventsGroupedByDate: [Date: [GoogleCalendarEvent]] = [:]
        
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
        for date in weekDates {
            let calendar = Calendar.current
            let eventsForDate = allEvents.filter { event in
                guard let startTime = event.startTime else { return false }
                return calendar.isDate(startTime, inSameDayAs: date)
            }
            eventsGroupedByDate[date] = eventsForDate
        }
        
        return eventsGroupedByDate
    }
    
    // Group month events by date for the MonthTimelineComponent
    private func getMonthEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        let monthDates = getMonthDates()
        var eventsGroupedByDate: [Date: [GoogleCalendarEvent]] = [:]
        
        var allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
        // Debug: Print event counts to help diagnose the issue
        print("🗓️ Month Events Debug:")
        print("  Personal events count: \(calendarViewModel.personalEvents.count)")
        print("  Professional events count: \(calendarViewModel.professionalEvents.count)")
        print("  Total combined events: \(allEvents.count)")
        
        // Filter out recurring events if the setting is enabled
        if appPrefs.hideRecurringEventsInMonth {
            let allEventsForRecurringDetection = allEvents
            let recurringEvents = allEvents.filter { $0.isLikelyRecurring(among: allEventsForRecurringDetection) }
            print("  Found \(recurringEvents.count) recurring events:")
            for event in recurringEvents {
                print("    - '\(event.summary)' (recurringEventId: \(event.recurringEventId ?? "nil"), recurrence: \(event.recurrence?.isEmpty == false ? "has rules" : "nil"))")
            }
            allEvents = allEvents.filter { !$0.isLikelyRecurring(among: allEventsForRecurringDetection) }
            print("  After recurring filter: \(allEvents.count)")
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
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
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
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
        return allEvents.filter { event in
            guard let startTime = event.startTime else { return false }
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }
    
    private func getAllDayEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
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
    
    private func weekEventBlock(event: GoogleCalendarEvent, date: Date) -> some View {
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
        
        return AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .frame(height: height)
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        
                        if height > 60 {
                            Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
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
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
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
        PersonalTasksComponent(
            taskLists: tasksViewModel.personalTaskLists,
            tasksDict: cachedPersonalTasks,
            accentColor: appPrefs.personalColor,
            onTaskToggle: { task, listId in
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                    updateCachedTasks()
                }
            },
            onTaskDetails: { task, listId in
                selectedTask = task
                selectedTaskListId = listId
                selectedAccountKind = .personal
                DispatchQueue.main.async {
                    showingTaskDetails = true
                }
            }
        )
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
                
                let completedTasks = tasks.filter { $0.isCompleted }.count
                Text("\(completedTasks)/\(tasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
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
                        Image(systemName: "calendar")
                            .font(.caption2)
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
        ProfessionalTasksComponent(
            taskLists: tasksViewModel.professionalTaskLists,
            tasksDict: cachedProfessionalTasks,
            accentColor: appPrefs.professionalColor,
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
            }
        )
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
                
                let completedTasks = tasks.filter { $0.isCompleted }.count
                Text("\(completedTasks)/\(tasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
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
                        Image(systemName: "calendar")
                            .font(.caption2)
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
                    print("📸 Photo selected and loaded successfully")
                    
                    // Reset the selection for next time
                    selectedPhoto = nil
                }
            }
        }
    }
    

    
    // MARK: - Helper Methods for Real Tasks
    private func updateCachedTasks() {
        cachedPersonalTasks = filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate)
        cachedProfessionalTasks = filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate)
        updateWeekCachedTasks() // Also update week cached tasks
        updateMonthCachedTasks() // Also update month cached tasks
    }
    
    private func updateWeekCachedTasks() {
        cachedWeekPersonalTasks = filteredTasksForWeek(tasksViewModel.personalTasks, date: currentDate)
        cachedWeekProfessionalTasks = filteredTasksForWeek(tasksViewModel.professionalTasks, date: currentDate)
    }
    
    private func updateMonthCachedTasks() {
        cachedMonthPersonalTasks = filteredTasksForMonth(tasksViewModel.personalTasks, date: currentDate)
        cachedMonthProfessionalTasks = filteredTasksForMonth(tasksViewModel.professionalTasks, date: currentDate)
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
                    return calendar.isDate(completionDate, inSameDayAs: date) ? task : nil
                } else {
                    // For incomplete tasks, only show them on their exact due date
                    guard let dueDate = task.dueDate else { return nil }
                    
                    // Only show tasks on their exact due date (not on future dates)
                    return calendar.isDate(dueDate, inSameDayAs: date) ? task : nil
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

struct WeekCalendarView: View {
    let currentDate: Date
    
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    private var weekNumber: String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: currentDate)
        return "Week \(weekOfYear)"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Days of week header
            HStack(spacing: 4) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Week dates
            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    weekDayCell(date: date)
                }
            }
            
            // Time slots (simplified version)
            VStack(spacing: 8) {
                ForEach(["9:00 AM", "10:00 AM", "11:00 AM", "12:00 PM", "1:00 PM", "2:00 PM", "3:00 PM", "4:00 PM", "5:00 PM"], id: \.self) { time in
                    HStack {
                        Text(time)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func weekDayCell(date: Date) -> some View {
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: date)
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(isToday ? Color.red : Color.clear)
                .clipShape(Circle())
            
            // Placeholder for events/appointments
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray4))
                .frame(height: 60)
                .overlay(
                    Text("Events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

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
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isCurrentMonth ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrentMonth ? Color.blue : Color.clear)
                .cornerRadius(6)
            
            // Week headers
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 20)
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
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
    }
    
    private func weekRow(week: Int) -> some View {
        HStack(spacing: 2) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
            
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
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(Circle())
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
}

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
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
    
    let currentDate: Date
    let tasksViewModel: TasksViewModel
    let calendarViewModel: CalendarViewModel
    let appPrefs: AppPreferences
    
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
        selectedAccountKind != nil
    }
    
    private var accentColor: Color {
        guard let accountKind = selectedAccountKind else { return .accentColor }
        return accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Type", selection: $selectedTab) {
                    Text("Task").tag(0)
                    Text("Calendar Event").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
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
                            }
                        }
                    } else {
                        // Calendar event-specific fields
                        Section("Event Time") {
                            DatePicker("Start Date", selection: Binding(
                                get: { dueDate ?? currentDate },
                                set: { dueDate = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                            
                            Text("Calendar events will be created in your selected Google Calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "New Task" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selectedTab == 0 ? "Create Task" : "Create Event") {
                        if selectedTab == 0 {
                            createTask()
                        } else {
                            createEvent()
                        }
                    }
                    .disabled(selectedTab == 0 ? !canCreateTask : !canCreateEvent)
                    .foregroundColor(accentColor)
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
                    print("Failed to create task: \(error)")
                }
            }
        }
    }
    
    private func createEvent() {
        // Calendar event creation would require Google Calendar API integration
        // For now, just dismiss
        print("Calendar event creation not yet implemented")
        dismiss()
    }
}

#Preview {
    CalendarView()
} 