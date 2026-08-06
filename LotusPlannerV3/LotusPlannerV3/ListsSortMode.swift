import SwiftUI

// MARK: - Lists Sort Mode

/// User-selectable secondary sort order in the Lists view. Completion
/// status is always the primary sort (incomplete first); this enum picks
/// the tiebreaker among open tasks (and among completed tasks).
enum ListsSortMode: String, CaseIterable, Identifiable {
    case dueDate
    case priority
    case alphabetical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dueDate:      return "Due Date"
        case .priority:     return "Priority"
        case .alphabetical: return "Alphabetical"
        }
    }

    var systemImage: String {
        switch self {
        case .dueDate:      return "calendar"
        case .priority:     return "exclamationmark.triangle"
        case .alphabetical: return "textformat.abc"
        }
    }
}
