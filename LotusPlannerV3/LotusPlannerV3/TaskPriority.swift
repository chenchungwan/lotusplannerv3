import Foundation
import SwiftUI

// MARK: - Priority Data Structure
struct TaskPriorityData: Codable, Equatable, Hashable {
    let value: String

    init(value: String) {
        self.value = value
    }

    /// All possible priority values (Roadmap style: P0, P1, P2, etc.)
    static let allValues = ["P0", "P1", "P2", "P3", "P4"]

    /// Display label for empty/no priority state
    static let noPriorityLabel = "No Priority"

    /// Display text for this priority
    var displayText: String {
        return value
    }

    /// Color for this priority (lower values = higher priority = warmer colors)
    var color: Color {
        guard let index = Self.allValues.firstIndex(of: value) else { return .gray }

        // P0 = red, P1 = orange, P2 = yellow, P3 = green, P4 = blue
        switch index {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .green
        case 4: return .blue
        default: return .gray
        }
    }

    /// Encode priority as a tag for storing in task notes
    /// Format: [PRIORITY:value]
    var encodedTag: String {
        return "[PRIORITY:\(value)]"
    }

    /// Parse priority from task notes
    /// Returns nil if no priority tag found
    /// Supports both old format [PRIORITY:style:value] and new format [PRIORITY:value]
    static func parse(from notes: String?) -> TaskPriorityData? {
        guard let notes = notes else { return nil }

        // Try new format first: [PRIORITY:value]
        let newPattern = "\\[PRIORITY:([^:]+)\\]"
        if let regex = try? NSRegularExpression(pattern: newPattern, options: []) {
            let matches = regex.matches(in: notes, options: [], range: NSRange(notes.startIndex..., in: notes))

            if let match = matches.first,
               match.numberOfRanges == 2,
               let valueRange = Range(match.range(at: 1), in: notes) {
                let valueString = String(notes[valueRange])
                // Check if this is actually the new format (value should be P0, P1, etc.)
                if allValues.contains(valueString) {
                    return TaskPriorityData(value: valueString)
                }
            }
        }

        // Fall back to old format: [PRIORITY:style:value]
        let oldPattern = "\\[PRIORITY:([a-z]+):([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: oldPattern, options: []) {
            let matches = regex.matches(in: notes, options: [], range: NSRange(notes.startIndex..., in: notes))

            if let match = matches.first,
               match.numberOfRanges == 3,
               let valueRange = Range(match.range(at: 2), in: notes) {
                let valueString = String(notes[valueRange])
                return TaskPriorityData(value: valueString)
            }
        }

        return nil
    }

    /// Remove priority tag from notes string
    /// Returns cleaned notes string
    /// Supports both old format [PRIORITY:style:value] and new format [PRIORITY:value]
    static func removeTag(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        // This pattern matches both old and new formats
        let pattern = "\\[PRIORITY:[^\\]]+\\]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return notes }

        let cleanedNotes = regex.stringByReplacingMatches(
            in: notes,
            options: [],
            range: NSRange(notes.startIndex..., in: notes),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedNotes.isEmpty ? nil : cleanedNotes
    }

    /// Add or update priority tag in notes
    /// Returns updated notes string with priority tag
    static func updateNotes(_ notes: String?, with priority: TaskPriorityData?) -> String? {
        // First remove any existing priority tag
        let cleanedNotes = removeTag(from: notes) ?? ""

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
        return Self.allValues.firstIndex(of: value) ?? 999
    }
}
