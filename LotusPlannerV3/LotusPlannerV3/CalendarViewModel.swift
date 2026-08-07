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

    @Published var account1Calendars: [GoogleCalendar] = []
    @Published var account2Calendars: [GoogleCalendar] = []
    @Published var account1Events: [GoogleCalendarEvent] = [] {
        didSet { account1EventsByDay = buildEventsByDay(from: account1Events) }
    }
    @Published var account2Events: [GoogleCalendarEvent] = [] {
        didSet { account2EventsByDay = buildEventsByDay(from: account2Events) }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var loadingStatusMessage = ""
    @Published var lastSuccessfulFetch: [GoogleAuthManager.AccountKind: Date] = [:]
    @Published var lastFetchError: [GoogleAuthManager.AccountKind: String] = [:]
    private var errorCheckTask: Task<Void, Never>?
    private var dismissedErrorMessage: String?
    private var currentLoadID = 0
    private var errorEligibleForAlert = false
    private var account1EventsByDay: [Date: [GoogleCalendarEvent]] = [:]
    private var account2EventsByDay: [Date: [GoogleCalendarEvent]] = [:]
    private let appPrefs = AppPreferences.shared
    let dayFetchPaddingDays = 7

    func scheduleErrorCheck(for loadID: Int) {
        // Cancel any existing error check task
        errorCheckTask?.cancel()

        // Schedule a new error check after a delay so transient overlapping refreshes
        // do not immediately throw a modal alert over the calendar.
        errorCheckTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)

            // Only show error if we're not loading and there's an error message
            if !Task.isCancelled && !isLoading && errorMessage != nil && loadID == currentLoadID {
                await MainActor.run {
                    presentErrorIfNeeded()
                }
            }
        }
    }

    @discardableResult
    func beginCalendarLoad(statusMessage: String) -> Int {
        errorCheckTask?.cancel()
        currentLoadID += 1
        errorEligibleForAlert = false
        isLoading = true
        if !showError {
            errorMessage = nil
        }
        loadingStatusMessage = statusMessage
        return currentLoadID
    }

    func finishCalendarLoad(loadID: Int, account1Error: Error?, account2Error: Error?) {
        guard loadID == currentLoadID else {
            return
        }

        let account1Linked = authManager.isLinked(kind: .account1)
        let account2Linked = authManager.isLinked(kind: .account2)
        let account1Failed = account1Linked && account1Error != nil
        let account2Failed = account2Linked && account2Error != nil
        let linkedAccountCount = [account1Linked, account2Linked].filter { $0 }.count
        let failedLinkedAccountCount = [account1Failed, account2Failed].filter { $0 }.count

        if account1Linked && account2Linked {
            let firstName = GoogleAuthManager.AccountKind.account1.displayName
            let secondName = GoogleAuthManager.AccountKind.account2.displayName
            if account1Failed && account2Failed {
                errorMessage = "Failed to load calendar data for both accounts"
            } else if account1Failed {
                errorMessage = "\(firstName) failed, \(secondName) loaded"
            } else if account2Failed {
                errorMessage = "\(secondName) failed, \(firstName) loaded"
            }
        } else if account1Linked, let account1Error {
            errorMessage = account1Error.localizedDescription
        } else if account2Linked, let account2Error {
            errorMessage = account2Error.localizedDescription
        }

        errorEligibleForAlert = linkedAccountCount > 0 && failedLinkedAccountCount == linkedAccountCount

        updateCalendarFetchStatus(account1Error: account1Error, account2Error: account2Error)

        isLoading = false
        loadingStatusMessage = ""

        if errorMessage == nil {
            dismissedErrorMessage = nil
            showError = false
        }

        scheduleErrorCheck(for: loadID)
    }

    func dismissError() {
        dismissedErrorMessage = errorMessage
        showError = false
        errorMessage = nil
    }

    private func presentErrorIfNeeded() {
        guard errorEligibleForAlert, let errorMessage, errorMessage != dismissedErrorMessage else {
            return
        }
        showError = true
    }

    func retryCurrentLoad() async {
        dismissedErrorMessage = nil
        showError = false
        await refreshDataForCurrentView()
    }

    /// Status text for the Diagnostics screen. The caller labels the row with
    /// the account's user-chosen name, so this omits it.
    func qualitySummary(for kind: GoogleAuthManager.AccountKind) -> String {
        if let error = lastFetchError[kind] {
            return "Failed: \(error)"
        }
        if let lastFetch = lastSuccessfulFetch[kind] {
            return "Loaded \(lastFetch.formatted(date: .omitted, time: .shortened))"
        }
        return GoogleAuthManager.shared.isLinked(kind: kind) ? "Not loaded yet" : "Not linked"
    }

    func updateCalendarFetchStatus(account1Error: Error?, account2Error: Error?) {
        let now = Date()

        if GoogleAuthManager.shared.isLinked(kind: .account1) {
            if let account1Error {
                lastFetchError[.account1] = account1Error.localizedDescription
            } else {
                lastFetchError.removeValue(forKey: .account1)
                lastSuccessfulFetch[.account1] = now
            }
        }

        if GoogleAuthManager.shared.isLinked(kind: .account2) {
            if let account2Error {
                lastFetchError[.account2] = account2Error.localizedDescription
            } else {
                lastFetchError.removeValue(forKey: .account2)
                lastSuccessfulFetch[.account2] = now
            }
        }

        if errorMessage == nil {
            dismissedErrorMessage = nil
        }
    }

    func newestCacheAgeDescription() -> String {
        guard let newest = cacheTimestamps.values.max() else { return "No cached calendar data" }
        return Self.relativeAgeDescription(since: newest)
    }

    static func relativeAgeDescription(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
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
    /// result. Called whenever we assign `account1Events` /
    /// `account2Events` so that an event whose `calendarId` matches
    /// the opposite account's saved email never sneaks into the wrong
    /// array via cross-account calendar subscription. Without this, an
    /// event the user created on account 2 ends up duplicated in
    /// account1Events and the account-1-only views show it as an
    /// account 1 event — including events created directly in Google
    /// Calendar's web UI.
    func eventsOwned(by kind: GoogleAuthManager.AccountKind, from events: [GoogleCalendarEvent]) -> [GoogleCalendarEvent] {
        let auth = GoogleAuthManager.shared
        let otherKind: GoogleAuthManager.AccountKind = (kind == .account1) ? .account2 : .account1
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
        let account2Email = auth.getEmail(for: .account2).lowercased()
        let account1Email = auth.getEmail(for: .account1).lowercased()

        if !account2Email.isEmpty, owner == account2Email {
            return .account2
        }
        if !account1Email.isEmpty, owner == account1Email {
            return .account1
        }

        // Fallback when calendarId is a non-primary calendar (e.g. a
        // shared "Family" calendar or a holiday calendar). Trust the
        // array that uniquely owns the event id.
        let inAccount1 = account1Events.contains { $0.id == event.id }
        let inAccount2 = account2Events.contains { $0.id == event.id }
        if inAccount2 && !inAccount1 { return .account2 }
        if inAccount1 && !inAccount2 { return .account1 }
        return event.ownerAccountKind
    }

    func events(for date: Date, account: GoogleAuthManager.AccountKind? = nil) -> [GoogleCalendarEvent] {
        let key = normalizedDay(date)
        let result: [GoogleCalendarEvent]
        switch account {
        case .some(.account1):
            result = account1EventsByDay[key] ?? []
        case .some(.account2):
            result = account2EventsByDay[key] ?? []
        case .none:
            let account1 = account1EventsByDay[key] ?? []
            let account2 = account2EventsByDay[key] ?? []
            if account1.isEmpty {
                result = account2
            } else if account2.isEmpty {
                result = account1
            } else {
                // Dedupe by event id so a single Google event that
                // appears in both accounts' fetches (via Workspace
                // calendar sharing or one account subscribing to the
                // other's calendar) doesn't render twice. Account 1
                // wins on collision so the card keeps its color.
                var seen = Set<String>()
                var merged: [GoogleCalendarEvent] = []
                merged.reserveCapacity(account1.count + account2.count)
                for event in account1 where seen.insert(event.id).inserted {
                    merged.append(event)
                }
                for event in account2 where seen.insert(event.id).inserted {
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

        let loadID = beginCalendarLoad(statusMessage: "Loading calendar month...")

        // Debug: Check account linking status
        let account1Linked = authManager.isLinked(kind: .account1)
        let account2Linked = authManager.isLinked(kind: .account2)

        var account1Error: Error?
        var account2Error: Error?

        await withTaskGroup(of: Void.self) { group in
            if account1Linked {
                group.addTask {
                    do {
                        let events = try await CalendarManager.shared.fetchEvents(for: .account1, startDate: monthStart, endDate: monthEnd)
                        let calendars = try await CalendarManager.shared.fetchCalendars(for: .account1)
                        await MainActor.run {
                            self.account1Events = self.eventsOwned(by: .account1, from: events)
                            self.account1Calendars = calendars
                        }
                    } catch {
                        account1Error = error
                    }
                }
            }
            if account2Linked {
                group.addTask {
                    do {
                        let events = try await CalendarManager.shared.fetchEvents(for: .account2, startDate: monthStart, endDate: monthEnd)
                        let calendars = try await CalendarManager.shared.fetchCalendars(for: .account2)
                        await MainActor.run {
                            self.account2Events = self.eventsOwned(by: .account2, from: events)
                            self.account2Calendars = calendars
                        }
                    } catch {
                        account2Error = error
                    }
                }
            }
        }

        finishCalendarLoad(loadID: loadID, account1Error: account1Error, account2Error: account2Error)
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
        account1Events = []
        account2Events = []
        account1Calendars = []
        account2Calendars = []
        // Clear disk cache keys as well
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(diskCacheKeyPrefix) || key.hasPrefix(diskCacheTimestampPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // Clear cache for a specific month
    func clearCacheForMonth(containing date: Date) {
        let account1Key = monthCacheKey(for: date, accountKind: .account1)
        let account2Key = monthCacheKey(for: date, accountKind: .account2)

        cachedEvents.removeValue(forKey: account1Key)
        cachedEvents.removeValue(forKey: account2Key)
        cachedCalendars.removeValue(forKey: account1Key)
        cachedCalendars.removeValue(forKey: account2Key)
        cacheTimestamps.removeValue(forKey: account1Key)
        cacheTimestamps.removeValue(forKey: account2Key)
        cacheAccessOrder.removeValue(forKey: account1Key)
        cacheAccessOrder.removeValue(forKey: account2Key)
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
