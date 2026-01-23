import Foundation
import SwiftUI

// MARK: - Priority Style Enum
enum TaskPriorityDataStyle: String, CaseIterable, Codable {
    case roadmap = "roadmap"
    case numeric = "numeric"
    case alphabetic = "alphabetic"
    case level = "level"

    var displayName: String {
        switch self {
        case .roadmap: return "Roadmap (P0, P1, P2)"
        case .numeric: return "Numeric (1, 2, 3)"
        case .alphabetic: return "Alphabetic (A, B, C)"
        case .level: return "Level (High, Medium, Low)"
        }
    }

    /// Get all possible priority values for this style
    func allValues() -> [String] {
        switch self {
        case .roadmap:
            return ["P0", "P1", "P2", "P3", "P4", "P5"]
        case .numeric:
            return ["1", "2", "3", "4", "5", "6"]
        case .alphabetic:
            return ["A", "B", "C", "D", "E", "F"]
        case .level:
            return ["High", "Medium", "Low"]
        }
    }

    /// Get display label for empty/no priority state
    var noPriorityLabel: String {
        switch self {
        case .roadmap: return "No Priority"
        case .numeric: return "No Priority"
        case .alphabetic: return "No Priority"
        case .level: return "No Priority"
        }
    }

    /// Get color for a specific priority value (lower values = higher priority = warmer colors)
    func color(for value: String) -> Color {
        let values = allValues()
        guard let index = values.firstIndex(of: value) else { return .gray }

        switch self {
        case .roadmap, .numeric, .alphabetic:
            // P0/1/A = red, P1/2/B = orange, P2/3/C = yellow, P3/4/D = green, P4+/5+/E+ = blue
            switch index {
            case 0: return .red
            case 1: return .orange
            case 2: return .yellow
            case 3: return .green
            default: return .blue
            }
        case .level:
            // High = red, Medium = orange, Low = green
            switch index {
            case 0: return .red    // High
            case 1: return .orange // Medium
            case 2: return .green  // Low
            default: return .gray
            }
        }
    }
}

// MARK: - Priority Data Structure
struct TaskPriorityData: Codable, Equatable, Hashable {
    let style: TaskPriorityDataStyle
    let value: String

    init(style: TaskPriorityDataStyle, value: String) {
        self.style = style
        self.value = value
    }

    /// Display text for this priority
    var displayText: String {
        return value
    }

    /// Color for this priority
    var color: Color {
        return style.color(for: value)
    }

    /// Encode priority as a tag for storing in task notes
    /// Format: [PRIORITY:style:value]
    var encodedTag: String {
        return "[PRIORITY:\(style.rawValue):\(value)]"
    }

    /// Parse priority from task notes
    /// Returns nil if no priority tag found
    static func parse(from notes: String?) -> TaskPriorityData? {
        guard let notes = notes else { return nil }

        // Look for [PRIORITY:style:value] pattern
        let pattern = "\\[PRIORITY:([a-z]+):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsString = notes as NSString
        let matches = regex.matches(in: notes, options: [], range: NSRange(location: 0, length: nsString.length))

        guard let match = matches.first,
              match.numberOfRanges == 3 else { return nil }

        let styleString = nsString.substring(with: match.range(at: 1))
        let valueString = nsString.substring(with: match.range(at: 2))

        guard let style = TaskPriorityDataStyle(rawValue: styleString) else { return nil }

        return TaskPriorityData(style: style, value: valueString)
    }

    /// Remove priority tag from notes string
    /// Returns cleaned notes string
    static func removeTag(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        let pattern = "\\[PRIORITY:[a-z]+:[^\\]]+\\]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return notes }

        let cleanedNotes = regex.stringByReplacingMatches(
            in: notes,
            options: [],
            range: NSRange(location: 0, length: notes.count),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedNotes.isEmpty ? nil : cleanedNotes
    }

    /// Add or update priority tag in notes
    /// Returns updated notes string with priority tag
    static func updateNotes(_ notes: String?, with priority: TaskPriorityData?) -> String? {
        // First remove any existing priority tag
        var cleanedNotes = removeTag(from: notes) ?? ""

        // If priority is nil, just return cleaned notes
        guard let priority = priority else {
            return cleanedNotes.isEmpty ? nil : cleanedNotes
        }

        // Add priority tag at the beginning
        let priorityTag = priority.encodedTag
        if cleanedNotes.isEmpty {
            return priorityTag
        } else {
            return "\(priorityTag)\n\(cleanedNotes)"
        }
    }

    /// Numerical sort order (lower = higher priority)
    var sortOrder: Int {
        let values = style.allValues()
        return values.firstIndex(of: value) ?? 999
    }
}

// MARK: - User Preference Helper
extension UserDefaults {
    private static let taskPriorityStyleKey = "taskPriorityStyle"

    var taskPriorityStyle: TaskPriorityDataStyle {
        get {
            guard let rawValue = string(forKey: Self.taskPriorityStyleKey),
                  let style = TaskPriorityDataStyle(rawValue: rawValue) else {
                return .roadmap // Default to roadmap style
            }
            return style
        }
        set {
            set(newValue.rawValue, forKey: Self.taskPriorityStyleKey)
        }
    }
}
