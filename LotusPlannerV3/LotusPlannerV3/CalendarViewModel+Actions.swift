import Foundation

/// Calendar event mutation actions for `CalendarViewModel`. Drag-and-drop
/// surfaces (D/W/T views) and the new-event sheet call into these to
/// move events between dates, schedule a previously all-day event at a
/// specific time, or shift an already-timed event to a new slot.
extension CalendarViewModel {


    // MARK: - Move Event to Different Date (Preserve Time)

    /// Move `event` to `targetDate`. By default, preserve the event's
    /// timed/all-day status. Pass `forceAllDay: true` (called when the
    /// user drops a timed event onto the all-day band) to convert the
    /// event to all-day on `targetDate` regardless of its prior state;
    /// in that mode we also explicitly null the `dateTime` field so
    /// Google clears the prior timed values (date and dateTime are
    /// mutually exclusive on the API).
    func moveEventToDate(_ event: GoogleCalendarEvent, to targetDate: Date, forceAllDay: Bool = false) async {
        guard let originalStart = event.startTime, let originalEnd = event.endTime else { return }

        let calendar = Calendar.current
        let originalDay = calendar.startOfDay(for: originalStart)
        let targetDay = calendar.startOfDay(for: targetDate)
        // When converting timed → all-day on the same day, the day
        // offset is zero but the event still needs a PATCH. Only short-
        // circuit when both the day matches AND we'd be re-PATCHing the
        // same all-day status.
        let sameDay = calendar.isDate(originalDay, inSameDayAs: targetDay)
        if sameDay {
            let alreadyAllDay = event.isAllDay
            let willBeAllDay = forceAllDay || alreadyAllDay
            if alreadyAllDay == willBeAllDay {
                return
            }
        }

        let dayOffset = calendar.dateComponents([.day], from: originalDay, to: targetDay).day ?? 0
        guard let newStart = calendar.date(byAdding: .day, value: dayOffset, to: originalStart),
              let newEnd = calendar.date(byAdding: .day, value: dayOffset, to: originalEnd) else { return }

        let kind: GoogleAuthManager.AccountKind = self.accountKind(for: event)

        do {
            let accessToken = try await GoogleAuthManager.shared.getAccessToken(for: kind)
            let calId = event.calendarId ?? "primary"
            let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
            let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
            let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*", forHTTPHeaderField: "If-Match")

            var body: [String: Any]
            let resultIsAllDay = forceAllDay || event.isAllDay
            if resultIsAllDay {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                // For an all-day event, Google's `end.date` is exclusive
                // (the day after the last all-day day). Single-day all-
                // day → end = start + 1 day. When converting a timed
                // event we collapse to a single-day all-day on the
                // target date.
                let baseStart: Date
                let baseEndExclusive: Date
                if event.isAllDay {
                    baseStart = newStart
                    baseEndExclusive = calendar.date(byAdding: .day, value: 1, to: newStart) ?? newEnd
                } else {
                    baseStart = calendar.startOfDay(for: targetDate)
                    baseEndExclusive = calendar.date(byAdding: .day, value: 1, to: baseStart) ?? baseStart
                }
                body = [
                    "start": [
                        "date": df.string(from: baseStart),
                        "dateTime": NSNull(),
                        "timeZone": NSNull()
                    ],
                    "end": [
                        "date": df.string(from: baseEndExclusive),
                        "dateTime": NSNull(),
                        "timeZone": NSNull()
                    ]
                ]
            } else {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                iso.timeZone = TimeZone.current
                body = [
                    "start": [
                        "dateTime": iso.string(from: newStart),
                        "timeZone": TimeZone.current.identifier,
                        "date": NSNull()
                    ],
                    "end": [
                        "dateTime": iso.string(from: newEnd),
                        "timeZone": TimeZone.current.identifier,
                        "date": NSNull()
                    ]
                ]
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                devLog("Failed to move event: bad response", level: .error, category: .calendar)
                return
            }
            await loadCalendarDataForWeek(containing: targetDate)
        } catch {
            devLog("Failed to move event: \(error)", level: .error, category: .calendar)
        }
    }

    // MARK: - Move Event to Specific Date and Time

    /// Schedule `event` at a specific start time with an explicit duration,
    /// regardless of whether it's currently timed or all-day. Use this to
    /// convert an all-day event into a timed one — `moveEventToDateTime`
    /// would compute a 24-hour duration off the all-day end exclusive
    /// boundary, which is not what the caller wants.
    func scheduleEvent(_ event: GoogleCalendarEvent, startTime: Date, duration: TimeInterval) async {
        let newEnd = startTime.addingTimeInterval(duration)
        let kind: GoogleAuthManager.AccountKind = self.accountKind(for: event)

        do {
            let accessToken = try await GoogleAuthManager.shared.getAccessToken(for: kind)
            let calId = event.calendarId ?? "primary"
            let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
            let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
            let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*", forHTTPHeaderField: "If-Match")

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            iso.timeZone = TimeZone.current
            // Google Calendar treats `date` (all-day) and `dateTime`
            // (timed) as mutually exclusive. When converting an all-day
            // event to timed we must explicitly null the existing `date`
            // field, otherwise the PATCH leaves the event as all-day.
            let body: [String: Any] = [
                "start": [
                    "dateTime": iso.string(from: startTime),
                    "timeZone": TimeZone.current.identifier,
                    "date": NSNull()
                ],
                "end": [
                    "dateTime": iso.string(from: newEnd),
                    "timeZone": TimeZone.current.identifier,
                    "date": NSNull()
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                devLog("Failed to schedule event: bad response", level: .error, category: .calendar)
                return
            }
            await loadCalendarDataForWeek(containing: startTime)
        } catch {
            devLog("Failed to schedule event: \(error)", level: .error, category: .calendar)
        }
    }

    func moveEventToDateTime(_ event: GoogleCalendarEvent, to targetDateTime: Date) async {
        guard let originalStart = event.startTime, let originalEnd = event.endTime else { return }

        let duration = originalEnd.timeIntervalSince(originalStart)
        let newEnd = targetDateTime.addingTimeInterval(duration)

        let kind: GoogleAuthManager.AccountKind = self.accountKind(for: event)

        do {
            let accessToken = try await GoogleAuthManager.shared.getAccessToken(for: kind)
            let calId = event.calendarId ?? "primary"
            let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
            let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
            let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*", forHTTPHeaderField: "If-Match")

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            iso.timeZone = TimeZone.current
            // Null the all-day `date` field so this works even when the
            // caller hands us an all-day event (defensive — see
            // `scheduleEvent` for the canonical conversion path).
            let body: [String: Any] = [
                "start": [
                    "dateTime": iso.string(from: targetDateTime),
                    "timeZone": TimeZone.current.identifier,
                    "date": NSNull()
                ],
                "end": [
                    "dateTime": iso.string(from: newEnd),
                    "timeZone": TimeZone.current.identifier,
                    "date": NSNull()
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                devLog("Failed to move event to time: bad response", level: .error, category: .calendar)
                return
            }
            await loadCalendarDataForWeek(containing: targetDateTime)
        } catch {
            devLog("Failed to move event to time: \(error)", level: .error, category: .calendar)
        }
    }
}
