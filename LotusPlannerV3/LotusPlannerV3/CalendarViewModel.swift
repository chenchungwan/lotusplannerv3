//
//  CalendarViewModel.swift
//  LotusPlannerV3
//
//  Created by refactoring from CalendarView.swift
//

import Foundation
import SwiftUI

// MARK: - Calendar View Model
@MainActor
class CalendarViewModel: ObservableObject {
    @Published var personalCalendars: [GoogleCalendar] = []
    @Published var professionalCalendars: [GoogleCalendar] = []
    @Published var personalEvents: [GoogleCalendarEvent] = [] {
        didSet { personalEventsByDay = buildEventsByDay(from: personalEvents) }
    }
    @Published var professionalEvents: [GoogleCalendarEvent] = [] {
        didSet { professionalEventsByDay = buildEventsByDay(from: professionalEvents) }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    private var errorCheckTask: Task<Void, Never>?
    private var personalEventsByDay: [Date: [GoogleCalendarEvent]] = [:]
    private var professionalEventsByDay: [Date: [GoogleCalendarEvent]] = [:]
    private let appPrefs = AppPreferences.shared

    private func scheduleErrorCheck() {
        // Cancel any existing error check task
        errorCheckTask?.cancel()

        // Schedule a new error check after a delay
        errorCheckTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second delay - increased to avoid premature errors

            // Only show error if we're not loading and there's an error message
            if !Task.isCancelled && !isLoading && errorMessage != nil {
                await MainActor.run {
                    showError = true
                }
            }
        }
    }

    func refreshDataForCurrentView() async {
        let navigationManager = NavigationManager.shared
        switch navigationManager.currentInterval {
        case .month:
            await forceLoadCalendarDataForMonth(containing: navigationManager.currentDate)
        case .week:
            await loadCalendarDataForWeek(containing: navigationManager.currentDate)
        case .day:
            await loadCalendarData(for: navigationManager.currentDate)
        case .year:
            await forceLoadCalendarDataForMonth(containing: navigationManager.currentDate)
        }

    }

    func events(for date: Date, account: GoogleAuthManager.AccountKind? = nil) -> [GoogleCalendarEvent] {
        let key = normalizedDay(date)
        let result: [GoogleCalendarEvent]
        switch account {
        case .some(.personal):
            result = personalEventsByDay[key] ?? []
        case .some(.professional):
            result = professionalEventsByDay[key] ?? []
        case .none:
            let personal = personalEventsByDay[key] ?? []
            let professional = professionalEventsByDay[key] ?? []
            if personal.isEmpty {
                result = professional
            } else if professional.isEmpty {
                result = personal
            } else {
                result = (personal + professional).sorted(by: eventSortComparator)
            }
        }

        if appPrefs.verboseLoggingEnabled {
            let formatter = ISO8601DateFormatter()
            let keyString = formatter.string(from: key)
            let summaries = result.filter { $0.isAllDay }.map { $0.summary }.joined(separator: ", ")
            devLog(
                "📅 events(for:) \(keyString) account=\(account?.rawValue ?? "both") count=\(result.count) allDay=[\(summaries)]",
                level: .info,
                category: .calendar
            )
        }

        return result
    }

    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func buildEventsByDay(from events: [GoogleCalendarEvent]) -> [Date: [GoogleCalendarEvent]] {
        var map: [Date: [GoogleCalendarEvent]] = [:]
        for event in events {
            enumerateDays(for: event) { day in
                map[day, default: []].append(event)
            }
        }
        for key in map.keys {
            map[key]?.sort(by: eventSortComparator)
        }
        return map
    }

    private func enumerateDays(for event: GoogleCalendarEvent, handler: (Date) -> Void) {
        let calendar = Calendar.mondayFirst
        guard let startComponent = event.start.dateTime ?? event.start.date ?? event.startTime else {
            return
        }
        let startDay = calendar.startOfDay(for: startComponent)

        if event.isAllDay {
            let rawEnd = event.end.date ?? event.end.dateTime ?? event.endTime ?? startComponent
            let exclusiveEndDay = calendar.startOfDay(for: rawEnd)
            let lastInclusiveDay: Date
            if exclusiveEndDay > startDay {
                lastInclusiveDay = calendar.date(byAdding: .day, value: -1, to: exclusiveEndDay) ?? startDay
            } else {
                lastInclusiveDay = startDay
            }
            if appPrefs.verboseLoggingEnabled {
                let formatter = ISO8601DateFormatter()
                devLog(
                    "📅 enumerateDays all-day",
                    event.summary,
                    "start:", formatter.string(from: startDay),
                    "rawEnd:", formatter.string(from: rawEnd),
                    "exclusiveEnd:", formatter.string(from: exclusiveEndDay),
                    "lastInclusive:", formatter.string(from: lastInclusiveDay),
                    level: .info,
                    category: .calendar
                )
            }
            var current = startDay
            while current <= lastInclusiveDay {
                handler(current)
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
        } else {
            let rawEnd = event.end.dateTime ?? event.end.date ?? event.endTime ?? startComponent
            let endDay = calendar.startOfDay(for: rawEnd)
            var current = startDay
            while true {
                handler(current)
                if current >= endDay { break }
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
        }
    }

    private func eventSortComparator(_ lhs: GoogleCalendarEvent, _ rhs: GoogleCalendarEvent) -> Bool {
        let lStart = lhs.startTime ?? lhs.start.date ?? Date.distantPast
        let rStart = rhs.startTime ?? rhs.start.date ?? Date.distantPast
        if lStart == rStart {
            let lEnd = lhs.endTime ?? lhs.end.date ?? Date.distantFuture
            let rEnd = rhs.endTime ?? rhs.end.date ?? Date.distantFuture
            return lEnd < rEnd
        }
        return lStart < rStart
    }

    func forceLoadCalendarDataForMonth(containing date: Date) async {
        let calendar = Calendar.mondayFirst
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return
        }

        isLoading = true
        errorMessage = nil
        showError = false

        // Debug: Check account linking status
        let personalLinked = authManager.isLinked(kind: .personal)
        let professionalLinked = authManager.isLinked(kind: .professional)

        var personalError: Error?
        var professionalError: Error?

        await withTaskGroup(of: Void.self) { group in
            if personalLinked {
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
            if professionalLinked {
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

        // Schedule error check after loading completes
        scheduleErrorCheck()
    }

    private let authManager = GoogleAuthManager.shared

    // MARK: - Memory Cache
    private var cachedEvents: [String: [GoogleCalendarEvent]] = [:]
    private var cachedCalendars: [String: [GoogleCalendar]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTimeout: TimeInterval = 1800 // 30 minutes - longer cache for better performance

    // MARK: - Cache Size Management
    private var cacheAccessOrder: [String: Date] = [:] // Track last access time for LRU eviction
    private let maxCacheEntries = 6 // Max number of month entries (e.g., 3 months * 2 accounts)
    private var estimatedCacheSize: Int = 0 // Rough estimate in bytes

    // MARK: - Smart Prefetching
    private var lastNavigatedDate: Date?
    private var navigationDirection: Int = 0 // -1 for backward, 0 for neutral, 1 for forward
    private var prefetchTask: Task<Void, Never>?

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
        cacheAccessOrder.removeAll()
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

    // Clear cache for a specific month
    func clearCacheForMonth(containing date: Date) {
        let personalKey = monthCacheKey(for: date, accountKind: .personal)
        let professionalKey = monthCacheKey(for: date, accountKind: .professional)

        cachedEvents.removeValue(forKey: personalKey)
        cachedEvents.removeValue(forKey: professionalKey)
        cachedCalendars.removeValue(forKey: personalKey)
        cachedCalendars.removeValue(forKey: professionalKey)
        cacheTimestamps.removeValue(forKey: personalKey)
        cacheTimestamps.removeValue(forKey: professionalKey)
        cacheAccessOrder.removeValue(forKey: personalKey)
        cacheAccessOrder.removeValue(forKey: professionalKey)
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
            // Update access time for LRU tracking
            cacheAccessOrder[key] = Date()
            return memoryCache
        }

        // Then check disk cache - FUNCTIONALITY PRESERVED: Only if memory cache invalid
        if let diskCache = loadEventsFromDisk(for: key), isDiskCacheValid(for: key) {
            // Restore to memory cache for faster access
            cachedEvents[key] = diskCache
            cacheTimestamps[key] = Date()
            cacheAccessOrder[key] = Date()

            // Check if we need to evict old entries after adding this one
            evictOldCacheEntriesIfNeeded()

            return diskCache
        }

        // Clean up invalid cache
        cachedEvents.removeValue(forKey: key)
        cacheTimestamps.removeValue(forKey: key)
        cacheAccessOrder.removeValue(forKey: key)
        clearDiskCache(for: key)
        return nil
    }

    private func cacheEvents(_ events: [GoogleCalendarEvent], for key: String) {
        cachedEvents[key] = events
        cacheTimestamps[key] = Date()
        cacheAccessOrder[key] = Date()

        // Check if we need to evict old entries
        evictOldCacheEntriesIfNeeded()

        // PERFORMANCE ENHANCEMENT: Also save to disk for persistence
        saveEventsToDisk(events, for: key)
    }

    // MARK: - Cache Eviction (LRU Policy)
    private func evictOldCacheEntriesIfNeeded() {
        guard cachedEvents.count > maxCacheEntries else { return }

        // Sort cache keys by last access time (oldest first)
        let sortedKeys = cacheAccessOrder.sorted { $0.value < $1.value }.map { $0.key }

        // Evict oldest entries until we're under the limit
        let keysToEvict = sortedKeys.prefix(cachedEvents.count - maxCacheEntries)
        for key in keysToEvict {
            cachedEvents.removeValue(forKey: key)
            cachedCalendars.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
            cacheAccessOrder.removeValue(forKey: key)
            // Note: We keep disk cache intact for potential future restoration
        }
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

    // MARK: - Smart Prefetching
    private func smartPrefetch(around date: Date) async {
        let calendar = Calendar.mondayFirst

        // Prioritize prefetching based on navigation direction
        if navigationDirection > 0 {
            // User is moving forward - prioritize future months
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) {
                await preloadMonthIntoCache(containing: nextMonth)

                // Also prefetch the month after that with lower priority
                if let nextNextMonth = calendar.date(byAdding: .month, value: 2, to: date) {
                    await preloadMonthIntoCache(containing: nextNextMonth)
                }
            }

            // Then prefetch previous month
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: date) {
                await preloadMonthIntoCache(containing: prevMonth)
            }
        } else if navigationDirection < 0 {
            // User is moving backward - prioritize past months
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: date) {
                await preloadMonthIntoCache(containing: prevMonth)

                // Also prefetch the month before that
                if let prevPrevMonth = calendar.date(byAdding: .month, value: -2, to: date) {
                    await preloadMonthIntoCache(containing: prevPrevMonth)
                }
            }

            // Then prefetch next month
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) {
                await preloadMonthIntoCache(containing: nextMonth)
            }
        } else {
            // Neutral - prefetch both adjacent months equally
            await preloadAdjacentMonths(around: date)
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
        showError = false

        var personalError: Error?
        var professionalError: Error?

        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForAccountThrowing(.personal, date: date)
                    } catch {
                        personalError = error
                    }
                }
            }

            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForAccountThrowing(.professional, date: date)
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

        // Schedule error check after loading completes
        scheduleErrorCheck()
    }

    func loadCalendarDataForWeek(containing date: Date) async {
        isLoading = true
        errorMessage = nil
        showError = false

        // Get the week range using Monday-first calendar
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            isLoading = false
            return
        }

        var personalError: Error?
        var professionalError: Error?

        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForWeekRangeThrowing(.personal, startDate: weekStart, endDate: weekEnd)
                    } catch {
                        personalError = error
                    }
                }
            }

            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForWeekRangeThrowing(.professional, startDate: weekStart, endDate: weekEnd)
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

        // Schedule error check after loading completes
        scheduleErrorCheck()
    }

    func loadCalendarDataForMonth(containing date: Date) async {
        let calendar = Calendar.mondayFirst
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return
        }

        // Track navigation direction for smart prefetching
        if let lastDate = lastNavigatedDate {
            if monthStart > lastDate {
                navigationDirection = 1 // Moving forward
            } else if monthStart < lastDate {
                navigationDirection = -1 // Moving backward
            }
        }
        lastNavigatedDate = monthStart

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

        // Only set loading state if we actually need to load fresh data
        // This prevents the UI from flickering when we have cached data
        isLoading = true
        errorMessage = nil
        showError = false

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

        // Schedule error check after loading completes
        scheduleErrorCheck()

        // PROGRESSIVE LOADING: Smart prefetch based on navigation direction
        prefetchTask?.cancel() // Cancel any ongoing prefetch
        prefetchTask = Task.detached(priority: .low) {
            await self.smartPrefetch(around: date)
        }
    }

    private func loadCalendarDataForAccountThrowing(_ kind: GoogleAuthManager.AccountKind, date: Date) async throws {
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
                    if String(data: data, encoding: .utf8) != nil {
                        // Response string available for debugging if needed
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
            if error is URLError {
                // URL error detected for debugging if needed
            }

            throw error
        }
    }

    private let dayFetchPaddingDays = 7

    private func fetchEventsForDate(_ date: Date, calendars: [GoogleCalendar], for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleCalendarEvent] {
        let accessToken = try await authManager.getAccessToken(for: kind)

        let calendar = Calendar.current
        let baseStartOfDay = calendar.startOfDay(for: date)
        let paddedStart = calendar.date(byAdding: .day, value: -dayFetchPaddingDays, to: baseStartOfDay) ?? baseStartOfDay
        let paddedEnd = calendar.date(byAdding: .day, value: dayFetchPaddingDays + 1, to: baseStartOfDay) ?? calendar.date(byAdding: .day, value: 1, to: baseStartOfDay)!

        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: paddedStart)
        let timeMax = formatter.string(from: paddedEnd)

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

    private func loadCalendarDataForWeekRangeThrowing(_ kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async throws {
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
    }

    private func loadCalendarDataForMonthRangeThrowing(_ kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async throws {
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
