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
    /// Shared instance. Views across the app observe the same model so
    /// a calendar event edit anywhere updates every surface. Was
    /// previously owned by `DataManager`; promoted to a singleton so
    /// views can reference it directly.
    static let shared = CalendarViewModel()

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
    let dayFetchPaddingDays = 7

    func scheduleErrorCheck() {
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

    /// Returns the account that *owns* `event` — used by edit and
    /// delete flows to know which token + calendar URL to use. Owning
    /// account is derived from the event's `calendarId` (which holds
    /// the originating Gmail when the event was fetched via a calendar
    /// subscription), falling back to whichever account's array
    /// uniquely contains it. Without this, an event that appears in
    /// both arrays via cross-account subscription gets misattributed
    /// to whichever array we check first and DELETE/PATCH calls fail
    /// with 404 because the URL is built against the wrong calendar.
    /// Strip events that belong to the *other* account from a fetch
    /// result. Called whenever we assign `personalEvents` /
    /// `professionalEvents` so that an event whose `calendarId` matches
    /// the opposite account's saved email never sneaks into the wrong
    /// array via cross-account calendar subscription. Without this, an
    /// event the user created on professional ends up duplicated in
    /// personalEvents and the personal-only views show it as a personal
    /// event — including events created directly in Google Calendar's
    /// web UI.
    func eventsOwned(by kind: GoogleAuthManager.AccountKind, from events: [GoogleCalendarEvent]) -> [GoogleCalendarEvent] {
        let auth = GoogleAuthManager.shared
        let otherKind: GoogleAuthManager.AccountKind = (kind == .personal) ? .professional : .personal
        let otherEmail = auth.getEmail(for: otherKind).lowercased()
        guard !otherEmail.isEmpty else { return events }
        return events.filter { event in
            let owner = (event.calendarId ?? "").lowercased()
            return owner != otherEmail
        }
    }

    func accountKind(for event: GoogleCalendarEvent) -> GoogleAuthManager.AccountKind {
        let auth = GoogleAuthManager.shared
        let owner = (event.calendarId ?? "").lowercased()
        let professionalEmail = auth.getEmail(for: .professional).lowercased()
        let personalEmail = auth.getEmail(for: .personal).lowercased()

        if !professionalEmail.isEmpty, owner == professionalEmail {
            return .professional
        }
        if !personalEmail.isEmpty, owner == personalEmail {
            return .personal
        }

        // Fallback when calendarId is a non-primary calendar (e.g. a
        // shared "Family" calendar or a holiday calendar). Trust the
        // array that uniquely owns the event id.
        let inPersonal = personalEvents.contains { $0.id == event.id }
        let inProfessional = professionalEvents.contains { $0.id == event.id }
        if inProfessional && !inPersonal { return .professional }
        if inPersonal && !inProfessional { return .personal }
        return event.ownerAccountKind
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
                // Dedupe by event id so a single Google event that
                // appears in both accounts' fetches (via Workspace
                // calendar sharing or one account subscribing to the
                // other's calendar) doesn't render twice. Personal
                // wins on collision so the card stays personal-colored.
                var seen = Set<String>()
                var merged: [GoogleCalendarEvent] = []
                merged.reserveCapacity(personal.count + professional.count)
                for event in personal where seen.insert(event.id).inserted {
                    merged.append(event)
                }
                for event in professional where seen.insert(event.id).inserted {
                    merged.append(event)
                }
                result = merged.sorted(by: eventSortComparator)
            }
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
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              // Extend range by 1 day on each side to capture all-day events at month boundaries
              let monthStart = calendar.date(byAdding: .day, value: -1, to: monthInterval.start),
              let monthEnd = calendar.date(byAdding: .day, value: 1, to: monthInterval.end) else {
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
                            self.personalEvents = self.eventsOwned(by: .personal, from: events)
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
                            self.professionalEvents = self.eventsOwned(by: .professional, from: events)
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

    let authManager = GoogleAuthManager.shared

    // MARK: - Memory Cache
    var cachedEvents: [String: [GoogleCalendarEvent]] = [:]
    var cachedCalendars: [String: [GoogleCalendar]] = [:]
    var cacheTimestamps: [String: Date] = [:]
    let cacheTimeout: TimeInterval = 1800 // 30 minutes - longer cache for better performance

    // MARK: - Cache Size Management
    var cacheAccessOrder: [String: Date] = [:] // Track last access time for LRU eviction
    let maxCacheEntries = 6 // Max number of month entries (e.g., 3 months * 2 accounts)
    var estimatedCacheSize: Int = 0 // Rough estimate in bytes

    // MARK: - Smart Prefetching
    var lastNavigatedDate: Date?
    var navigationDirection: Int = 0 // -1 for backward, 0 for neutral, 1 for forward
    var prefetchTask: Task<Void, Never>?

    // MARK: - Persistent Cache Keys
    let diskCacheKeyPrefix = "CalendarCache_"
    let diskCacheTimestampPrefix = "CacheTimestamp_"

    // Track current loaded range to avoid unnecessary reloads
    var currentLoadedRange: (start: Date, end: Date, accountKind: GoogleAuthManager.AccountKind)?

    // MARK: - Cache Helper Methods
    func cacheKey(for accountKind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) -> String {
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

    func monthCacheKey(for date: Date, accountKind: GoogleAuthManager.AccountKind) -> String {
        let calendar = Calendar.mondayFirst
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date
        return cacheKey(for: accountKind, startDate: monthStart, endDate: monthEnd)
    }

    func isCacheValid(for key: String) -> Bool {
        guard let timestamp = cacheTimestamps[key] else { return false }
        return Date().timeIntervalSince(timestamp) < cacheTimeout
    }

    func getCachedEvents(for key: String) -> [GoogleCalendarEvent]? {
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

    func cacheEvents(_ events: [GoogleCalendarEvent], for key: String) {
        cachedEvents[key] = events
        cacheTimestamps[key] = Date()
        cacheAccessOrder[key] = Date()

        // Check if we need to evict old entries
        evictOldCacheEntriesIfNeeded()

        // PERFORMANCE ENHANCEMENT: Also save to disk for persistence
        saveEventsToDisk(events, for: key)
    }

    // MARK: - Cache Eviction (LRU Policy)
    func evictOldCacheEntriesIfNeeded() {
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

    func getCachedCalendars(for key: String) -> [GoogleCalendar]? {
        guard isCacheValid(for: key) else {
            cachedCalendars.removeValue(forKey: key)
            return nil
        }
        return cachedCalendars[key]
    }

    func cacheCalendars(_ calendars: [GoogleCalendar], for key: String) {
        cachedCalendars[key] = calendars
        cacheTimestamps[key] = Date()
    }

    // MARK: - Persistent Disk Cache Methods
    func saveEventsToDisk(_ events: [GoogleCalendarEvent], for key: String) {
        guard !events.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(events)
            UserDefaults.standard.set(data, forKey: diskCacheKeyPrefix + key)
            UserDefaults.standard.set(Date(), forKey: diskCacheTimestampPrefix + key)
        } catch {
        }
    }

    func loadEventsFromDisk(for key: String) -> [GoogleCalendarEvent]? {
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

    func isDiskCacheValid(for key: String) -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: diskCacheTimestampPrefix + key) as? Date else {
            return false
        }
        // Disk cache valid for 24 hours (longer than memory cache)
        return Date().timeIntervalSince(timestamp) < 86400
    }

    func clearDiskCache(for key: String) {
        UserDefaults.standard.removeObject(forKey: diskCacheKeyPrefix + key)
        UserDefaults.standard.removeObject(forKey: diskCacheTimestampPrefix + key)
    }

}
