import SwiftUI
import Foundation



@MainActor
class CalendarManager {
    static let shared = CalendarManager()
    
    private init() {}
    
    // MARK: - Event Loading
    func loadEvents(for kind: GoogleAuthManager.AccountKind, from startDate: Date, to endDate: Date) async throws -> [GoogleCalendarEvent]? {
        guard let accessToken = try await getAccessToken(for: kind) else {
            throw PlannerCalendarError.noAccessToken
        }
        
        // Format dates for API request
        let dateFormatter = ISO8601DateFormatter()
        let timeMin = dateFormatter.string(from: startDate)
        let timeMax = dateFormatter.string(from: endDate)
        
        // Build URL with query parameters
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlannerCalendarError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 {
                throw PlannerCalendarError.accessDenied
            }
            
            if httpResponse.statusCode != 200 {
                throw PlannerCalendarError.apiError(httpResponse.statusCode)
            }
            
            // Parse response using shared models defined in CalendarView.swift
            let decoder = JSONDecoder()
            let calendarResponse = try decoder.decode(GoogleCalendarEventsResponse.self, from: data)
            return calendarResponse.items
        } catch {
            print("Failed to load calendar events: \(error)")
            throw PlannerCalendarError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    private func getAccessToken(for kind: GoogleAuthManager.AccountKind) async throws -> String? {
        return try await GoogleAuthManager.shared.getAccessToken(for: kind)
    }
    
    func handleHttpError(_ statusCode: Int) -> PlannerCalendarError {
        switch statusCode {
        case 401:
            return .accessDenied
        case 403:
            return .accessDenied
        default:
            return .apiError(statusCode)
        }
    }

    // MARK: - Calendar List Loading
    func fetchCalendars(for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleCalendar] {
        guard let accessToken = try await getAccessToken(for: kind) else {
            throw PlannerCalendarError.noAccessToken
        }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw PlannerCalendarError.invalidResponse }
        guard httpResponse.statusCode == 200 else { throw handleHttpError(httpResponse.statusCode) }

        let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        return decoded.items ?? []
    }

    // MARK: - Events Across All Calendars
    func fetchEvents(for kind: GoogleAuthManager.AccountKind, startDate: Date, endDate: Date) async throws -> [GoogleCalendarEvent] {
        guard let accessToken = try await getAccessToken(for: kind) else {
            throw PlannerCalendarError.noAccessToken
        }

        let calendars = try await fetchCalendars(for: kind)
        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: startDate)
        let timeMax = iso.string(from: endDate)

        // PERFORMANCE OPTIMIZATION: Parallelize calendar API calls
        let allEvents = try await withThrowingTaskGroup(of: [GoogleCalendarEvent].self) { group in
            // Add a task for each calendar
            for cal in calendars {
                group.addTask { [weak self] in
                    let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(cal.id)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=2500"
                    guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { 
                        return []
                    }
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else { throw PlannerCalendarError.invalidResponse }
                    
                    // Handle HTTP errors inline to avoid async issues
                    if httpResponse.statusCode != 200 {
                        switch httpResponse.statusCode {
                        case 401, 403:
                            throw PlannerCalendarError.accessDenied
                        default:
                            throw PlannerCalendarError.apiError(httpResponse.statusCode)
                        }
                    }

                    let resp = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
                    if let items = resp.items {
                        return items.map { ev in
                            GoogleCalendarEvent(
                                id: ev.id,
                                summary: ev.summary,
                                description: ev.description,
                                start: ev.start,
                                end: ev.end,
                                location: ev.location,
                                calendarId: cal.id,
                                recurringEventId: ev.recurringEventId,
                                recurrence: ev.recurrence
                            )
                        }
                    }
                    return []
                }
            }
            
            // Collect results from all parallel tasks
            var combinedEvents: [GoogleCalendarEvent] = []
            for try await events in group {
                combinedEvents.append(contentsOf: events)
            }
            return combinedEvents
        }

        return allEvents.sorted { a, b in
            guard let startA = a.startTime, let startB = b.startTime else { return false }
            return startA < startB
        }
    }
}
