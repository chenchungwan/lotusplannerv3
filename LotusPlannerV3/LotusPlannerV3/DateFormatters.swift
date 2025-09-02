import Foundation
import SwiftUI

// MARK: - Standardized Date Formatters
extension DateFormatter {
    
    /// Standard date format: m/d/yy (e.g., "12/25/24")
    static let standardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter
    }()
    
    /// Standard day of week format: MON, TUE, etc.
    static let standardDayOfWeek: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    /// Combined day and date format: MON 12/25
    static let standardDayAndDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE M/d"
        return formatter
    }()
    
    /// Month and year format: January 2025
    static let standardMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    /// Full date format for headers: Monday, December 25, 2024
    static let standardFullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
}

// MARK: - Standardized Date Display Styles
struct DateDisplayStyle {
    static let titleFont: Font = .title2
    static let subtitleFont: Font = .caption
    static let bodyFont: Font = .body
    
    static let primaryColor: Color = .primary
    static let secondaryColor: Color = .secondary
    static let currentPeriodColor: Color = Color(red: 0.306, green: 0.647, blue: 0.0) // Green #4EA500 for current period
    static let todayColor: Color = .white // White text on blue background for today
    
    static func dateColor(isToday: Bool, isCurrentPeriod: Bool) -> Color {
        if isToday {
            return todayColor
        } else if isCurrentPeriod {
            return currentPeriodColor
        } else {
            return primaryColor
        }
    }
}


