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

        // Get the week range using Monday-first calendar, extended by 1 day on each side for all-day events
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date),
              let weekStart = calendar.date(byAdding: .day, value: -1, to: weekInterval.start),
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .day, value: 7, to: weekInterval.start) ?? weekInterval.end) else {
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
                personalEvents = eventsOwned(by: .personal, from: cachedEvents)
                personalCalendars = cachedCalendars
            }
        }

        if authManager.isLinked(kind: .professional) {
            let professionalKey = monthCacheKey(for: date, accountKind: .professional)
            if let cachedEvents = getCachedEvents(for: professionalKey),
               let cachedCalendars = getCachedCalendars(for: professionalKey) {
                professionalEvents = eventsOwned(by: .professional, from: cachedEvents)
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
                            self.personalEvents = self.eventsOwned(by: .personal, from: events)
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
                self.personalEvents = self.eventsOwned(by: .personal, from: events)
            case .professional:
                self.professionalCalendars = calendars
                self.professionalEvents = self.eventsOwned(by: .professional, from: events)
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
                self.personalEvents = self.eventsOwned(by: .personal, from: events)
            case .professional:
                self.professionalCalendars = calendars
                self.professionalEvents = self.eventsOwned(by: .professional, from: events)
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
                self.personalEvents = self.eventsOwned(by: .personal, from: events)
            case .professional:
                self.professionalCalendars = calendars
                self.professionalEvents = self.eventsOwned(by: .professional, from: events)
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
