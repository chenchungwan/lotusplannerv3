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
}