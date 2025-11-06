import Foundation

// MARK: - Calendar Error Type
enum PlannerCalendarError: Error {
    case noAccessToken
    case authenticationFailed
    case accessDenied
    case invalidResponse
    case apiError(Int)
    case networkError(Error)
    
    var localizedDescription: String {
        switch self {
        case .noAccessToken:
            return "No access token available"
        case .authenticationFailed:
            return "Failed to authenticate with Google Calendar"
        case .accessDenied:
            return "Access denied to Google Calendar"
        case .invalidResponse:
            return "Invalid response from Google Calendar API"
        case .apiError(let code):
            return "Google Calendar API error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Model convenience initializers used across the app
extension EventDateTime {
    init(date: Date?, dateTime: Date?, timeZone: String?) {
        self.date = date
        self.dateTime = dateTime
        self.timeZone = timeZone
    }
}
