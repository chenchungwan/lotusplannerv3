//
//  GoogleCalendarModels.swift
//  LotusPlannerV3
//
//  Created by refactoring from CalendarView.swift
//

import Foundation

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
