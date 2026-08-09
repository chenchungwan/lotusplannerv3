import Foundation

/// Calendar event loading + caching for `CalendarViewModel`. Split out
/// from the main file so the model + day-keyed accessor surface stays
/// readable independently from the much larger fetch/preload/cache
/// implementation. The on-disk + in-memory cache helpers live in the
/// main file because they're invoked from both halves; the network
/// fetch + preload orchestration lives here.
extension CalendarViewModel {

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
        let account1Key = monthCacheKey(for: date, accountKind: .account1)
        let account2Key = monthCacheKey(for: date, accountKind: .account2)

        let needsAccount1Preload = authManager.isLinked(kind: .account1) && !isCacheValid(for: account1Key)
        let needsAccount2Preload = authManager.isLinked(kind: .account2) && !isCacheValid(for: account2Key)

        guard needsAccount1Preload || needsAccount2Preload else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            if needsAccount1Preload {
                group.addTask {
                    do {
                        // Fetch calendars and events in parallel
                        async let calendars = CalendarManager.shared.fetchCalendars(for: .account1)
                        async let events = CalendarManager.shared.fetchEvents(for: .account1, startDate: monthStart, endDate: monthEnd)

                        let (fetchedCalendars, fetchedEvents) = try await (calendars, events)

                        await MainActor.run {
                            self.cacheCalendars(fetchedCalendars, for: account1Key)
                            self.cacheEvents(fetchedEvents, for: account1Key)
                        }
                    } catch {
                    }
                }
            }
            if needsAccount2Preload {
                group.addTask {
                    do {
                        // Fetch calendars and events in parallel
                        async let calendars = CalendarManager.shared.fetchCalendars(for: .account2)
                        async let events = CalendarManager.shared.fetchEvents(for: .account2, startDate: monthStart, endDate: monthEnd)

                        let (fetchedCalendars, fetchedEvents) = try await (calendars, events)

                        await MainActor.run {
                            self.cacheCalendars(fetchedCalendars, for: account2Key)
                            self.cacheEvents(fetchedEvents, for: account2Key)
                        }
                    } catch {
                    }
                }
            }
        }
    }

    func loadCalendarData(for date: Date) async {
        let loadID = beginCalendarLoad(statusMessage: "Loading calendar...")

        var account1Error: Error?
        var account2Error: Error?

        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .account1) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForAccountThrowing(.account1, date: date)
                    } catch {
                        account1Error = error
                    }
                }
            }

            if authManager.isLinked(kind: .account2) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForAccountThrowing(.account2, date: date)
                    } catch {
                        account2Error = error
                    }
                }
            }
        }

        finishCalendarLoad(loadID: loadID, account1Error: account1Error, account2Error: account2Error)
    }

    func loadCalendarDataForWeek(containing date: Date) async {
        let loadID = beginCalendarLoad(statusMessage: "Loading calendar week...")

        // Get the week range using Monday-first calendar, extended by 1 day on each side for all-day events
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date),
              let weekStart = calendar.date(byAdding: .day, value: -1, to: weekInterval.start),
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .day, value: 7, to: weekInterval.start) ?? weekInterval.end) else {
            finishCalendarLoad(loadID: loadID, account1Error: nil, account2Error: nil)
            return
        }

        var account1Error: Error?
        var account2Error: Error?

        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .account1) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForWeekRangeThrowing(.account1, startDate: weekStart, endDate: weekEnd)
                    } catch {
                        account1Error = error
                    }
                }
            }

            if authManager.isLinked(kind: .account2) {
                group.addTask {
                    do {
                        try await self.loadCalendarDataForWeekRangeThrowing(.account2, startDate: weekStart, endDate: weekEnd)
                    } catch {
                        account2Error = error
                    }
                }
            }
        }

        finishCalendarLoad(loadID: loadID, account1Error: account1Error, account2Error: account2Error)
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
        if authManager.isLinked(kind: .account1) {
            let account1Key = monthCacheKey(for: date, accountKind: .account1)
            if let cachedEvents = getCachedEvents(for: account1Key),
               let cachedCalendars = getCachedCalendars(for: account1Key) {
                account1Events = eventsOwned(by: .account1, from: cachedEvents)
                account1Calendars = cachedCalendars
            }
        }

        if authManager.isLinked(kind: .account2) {
            let account2Key = monthCacheKey(for: date, accountKind: .account2)
            if let cachedEvents = getCachedEvents(for: account2Key),
               let cachedCalendars = getCachedCalendars(for: account2Key) {
                account2Events = eventsOwned(by: .account2, from: cachedEvents)
                account2Calendars = cachedCalendars
            }
        }

        // If we have valid cache for all linked accounts, return early
        let needsAccount1Refresh = authManager.isLinked(kind: .account1) && getCachedEvents(for: monthCacheKey(for: date, accountKind: .account1)) == nil
        let needsAccount2Refresh = authManager.isLinked(kind: .account2) && getCachedEvents(for: monthCacheKey(for: date, accountKind: .account2)) == nil

        if !needsAccount1Refresh && !needsAccount2Refresh {
            loadingStatusMessage = ""
            return
        }

        // Only set loading state if we actually need to load fresh data
        // This prevents the UI from flickering when we have cached data
        let loadID = beginCalendarLoad(statusMessage: "Loading calendar month...")

        var account1Error: Error?
        var account2Error: Error?

        await withTaskGroup(of: Void.self) { group in
            if needsAccount1Refresh {
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
            if needsAccount2Refresh {
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

        // PROGRESSIVE LOADING: Smart prefetch based on navigation direction
        prefetchTask?.cancel() // Cancel any ongoing prefetch
        prefetchTask = Task.detached(priority: .low) {
            await self.smartPrefetch(around: date)
        }
    }

    private func loadCalendarDataForAccountThrowing(_ kind: GoogleAuthManager.AccountKind, date: Date) async throws {
        await MainActor.run {
            self.loadingStatusMessage = "Loading calendar for \(kind.displayName)..."
        }
        let calendars = try await fetchCalendars(for: kind)
        let events = try await fetchEventsForDate(date, calendars: calendars, for: kind)

        await MainActor.run {
            switch kind {
            case .account1:
                self.account1Calendars = calendars
                self.account1Events = self.eventsOwned(by: .account1, from: events)
            case .account2:
                self.account2Calendars = calendars
                self.account2Events = self.eventsOwned(by: .account2, from: events)
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

            return calendars
        } catch {

            // Add more specific error information
            if error is URLError {
                // URL error detected for debugging if needed
            }

            throw error
        }
    }

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
        await MainActor.run {
            self.loadingStatusMessage = "Loading calendar for \(kind.displayName)..."
        }
        let calendars = try await fetchCalendars(for: kind)
        let events = try await fetchEventsForDateRange(startDate: startDate, endDate: endDate, calendars: calendars, for: kind)

        await MainActor.run {
            switch kind {
            case .account1:
                self.account1Calendars = calendars
                self.account1Events = self.eventsOwned(by: .account1, from: events)
            case .account2:
                self.account2Calendars = calendars
                self.account2Events = self.eventsOwned(by: .account2, from: events)
            }
        }
    }

    private func loadCalendarDataForMonthRangeThrowing(_ kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async throws {
        await MainActor.run {
            self.loadingStatusMessage = "Loading calendar for \(kind.displayName)..."
        }
        let calendars = try await fetchCalendars(for: kind)

        let events = try await fetchEventsForDateRange(startDate: startDate, endDate: endDate, calendars: calendars, for: kind)

        // Cache the fresh data
        let cacheKey = self.cacheKey(for: kind, startDate: startDate, endDate: endDate)
        cacheEvents(events, for: cacheKey)
        cacheCalendars(calendars, for: cacheKey)

        await MainActor.run {
            switch kind {
            case .account1:
                self.account1Calendars = calendars
                self.account1Events = self.eventsOwned(by: .account1, from: events)
            case .account2:
                self.account2Calendars = calendars
                self.account2Events = self.eventsOwned(by: .account2, from: events)
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
