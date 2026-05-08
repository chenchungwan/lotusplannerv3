import Foundation

/// Display mode for the weekly view. Currently single-cased; the enum
/// stays so future modes (e.g. compact day list, two-week, etc.) can
/// be added without changing call sites that already switch on it.
enum WeeklyViewMode: String, CaseIterable, Hashable {
    case week
}

extension WeeklyViewMode {
    var displayName: String {
        switch self {
        case .week: return "Week"
        }
    }
}
