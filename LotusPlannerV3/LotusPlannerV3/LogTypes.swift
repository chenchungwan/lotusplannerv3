import Foundation

// MARK: - Day View Layout Option

/// Identifies one of the day-view rendering modes the user can pick in
/// Settings. Raw values are persisted, so existing assignments must not
/// change. New layouts append a new case + raw value.
enum DayViewLayoutOption: Int, CaseIterable, Identifiable {
    case compact = 0
    case mobile = 4
    case timebox = 6
    case newClassic = 8
    case custom = 10

    var id: Int { rawValue }
    static var allCases: [DayViewLayoutOption] { [.newClassic, .compact, .timebox, .mobile, .custom] }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .mobile: "Mobile"
        case .timebox: "Expanded"
        case .newClassic: "Classic"
        case .custom: "Custom"
        }
    }

    var description: String {
        switch self {
        case .compact: "Events and Tasks on left with collapsible logs, Journal on right"
        case .mobile: "Single column: Events, then tasks for each linked account, then Logs"
        case .timebox: "Timebox timeline on left with collapsible logs, Journal on right (swipe for 2nd page)"
        case .newClassic: "Timebox timeline with collapsible logs on left, Tasks and Journal on right (1 page)"
        case .custom: "A blank day view you can configure yourself."
        }
    }

    var isBeta: Bool {
        false
    }
}

// MARK: - Shared Timeline Interval

/// Day / Week / Month / Year — the four periods the calendar / goals /
/// timeline navigation can show. Persisted as the raw string.
enum TimelineInterval: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day:     return .day
        case .week:    return .weekOfYear
        case .month:   return .month
        case .year:    return .year
        }
    }

    /// SF Symbol used in nav-bar interval pickers.
    var sfSymbol: String {
        switch self {
        case .day:   return "d.circle"
        case .week:  return "w.circle"
        case .month: return "m.circle"
        case .year:  return "y.circle"
        }
    }

    /// Map to the parallel `TaskFilter` value (Tasks-side enum).
    var taskFilter: TaskFilter {
        switch self {
        case .day:   return .day
        case .week:  return .week
        case .month: return .month
        case .year:  return .year
        }
    }
}

extension TaskFilter {
    /// Bridge for code that has a `TaskFilter` and wants the matching
    /// timeline interval. `.all` returns `nil` because there is no
    /// timeline equivalent.
    var timelineInterval: TimelineInterval? {
        switch self {
        case .day:   return .day
        case .week:  return .week
        case .month: return .month
        case .year:  return .year
        case .all:   return nil
        }
    }
}

// MARK: - Built-in Log Type

enum BuiltInLogType: String, CaseIterable, Codable, Identifiable {
    case food, sleep, water, weight, workout

    var id: String { rawValue }
}

// MARK: - Log Display Entry

/// A single entry in the user-reorderable list of log sections. Custom
/// log sections are first-class entries alongside the built-in log
/// types so users can drag any of them anywhere in the list. `.custom`
/// references custom-log collection 0 (legacy); `.custom2` references
/// collection 1.
enum LogDisplayEntry: Hashable, Identifiable {
    case builtIn(BuiltInLogType)
    case custom
    case custom2

    var id: String { stringValue }

    var stringValue: String {
        switch self {
        case .builtIn(let t): return "builtin.\(t.rawValue)"
        case .custom:         return "custom"
        case .custom2:        return "custom2"
        }
    }

    init?(stringValue: String) {
        if stringValue == "custom" {
            self = .custom
            return
        }
        if stringValue == "custom2" {
            self = .custom2
            return
        }
        if stringValue.hasPrefix("builtin."),
           let t = BuiltInLogType(rawValue: String(stringValue.dropFirst("builtin.".count))) {
            self = .builtIn(t)
            return
        }
        return nil
    }

    static let defaultOrder: [LogDisplayEntry] =
        BuiltInLogType.allCases.map { .builtIn($0) } + [.custom, .custom2]
}
