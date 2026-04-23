import SwiftUI

/// Lists the goals in the current week, month, or year. Used in the Custom
/// Day View as three distinct components (one per timeframe). Shows just
/// each goal's title + category badge and hides linked tasks.
struct GoalsTimeframeComponent: View {
    let timeframe: GoalTimeframe
    let date: Date
    /// When `false`, the "This Week's Goals" title row is omitted — useful
    /// when a wrapper (e.g. the picker variant) already shows what's
    /// selected.
    var showsHeader: Bool = true

    @ObservedObject private var goalsManager = GoalsManager.shared

    /// Goals whose target timeframe matches and whose `dueDate` falls inside
    /// the period (week / month / year) containing `date`. Ordering matches
    /// the user's Goals view arrangement: categories are laid out in a 2×3
    /// grid by `displayPosition` (0 = top-left, then reading left→right,
    /// top→bottom), and goals within each category follow the user's
    /// `displayOrder` there.
    private var filteredGoals: [GoalData] {
        let calendar = Calendar.mondayFirst
        let component = timeframe.calendarComponent
        let matching = goalsManager.goals.filter { goal in
            goal.targetTimeframe == timeframe &&
            calendar.isDate(goal.dueDate, equalTo: date, toGranularity: component)
        }
        let positionByCategory: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: goalsManager.categories.map { ($0.id, $0.displayPosition) }
        )
        return matching.sorted { lhs, rhs in
            let lhsPos = positionByCategory[lhs.categoryId] ?? Int.max
            let rhsPos = positionByCategory[rhs.categoryId] ?? Int.max
            if lhsPos != rhsPos { return lhsPos < rhsPos }
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var headerTitle: String {
        GoalsTimeframeHeaderFormatter.headerTitle(for: timeframe, on: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack {
                    Text(headerTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(filteredGoals.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            if filteredGoals.isEmpty {
                Text("No \(timeframe.displayName.lowercased())-scope goals.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredGoals) { goal in
                            goalRow(goal)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        // Only draw the outer border when this view is standalone. When a
        // wrapper (the picker variant) embeds it with `showsHeader: false`,
        // the wrapper draws its own border and an inner one would double up.
        .cornerRadius(showsHeader ? 8 : 0)
        .overlay(
            Group {
                if showsHeader {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                }
            }
        )
    }

    private func goalRow(_ goal: GoalData) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundColor(goal.isCompleted ? .accentColor : .secondary)
                .padding(.top, 1)

            Text(goal.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(goal.isCompleted ? .secondary : .primary)
                .strikethrough(goal.isCompleted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    GoalsTimeframeComponent(timeframe: .week, date: Date())
        .frame(width: 320, height: 260)
}

/// Goals component with a segmented picker at the top letting the user
/// switch between Week / Month / Year at runtime inside the component.
/// Defaults to showing the current week.
struct GoalsTimeframePickerComponent: View {
    let date: Date
    @State private var selectedTimeframe: GoalTimeframe = .week

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Goals")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                // Menu-style picker to the right of the title. Shows the
                // currently selected range and opens a dropdown with all
                // three options when tapped.
                Picker("Timeframe", selection: $selectedTimeframe) {
                    Text("Week").tag(GoalTimeframe.week)
                    Text("Month").tag(GoalTimeframe.month)
                    Text("Year").tag(GoalTimeframe.year)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Inner component handles its own padding, scroll, and
            // background. Hide its header since the picker already shows
            // what's selected.
            GoalsTimeframeComponent(
                timeframe: selectedTimeframe,
                date: date,
                showsHeader: false
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview("Picker") {
    GoalsTimeframePickerComponent(date: Date())
        .frame(width: 320, height: 300)
}

/// Builds the header title shown above the goal list, parameterized by
/// timeframe and the date being viewed.
///
/// - `.week`  → `Goals WK17: 4/20 - 4/26`
/// - `.month` → `Goals April`
/// - `.year`  → `Goals 2026`
enum GoalsTimeframeHeaderFormatter {
    /// Uses the Monday-first calendar so the week number + span lines up
    /// with the rest of the app's weekly views.
    private static let calendar = Calendar.mondayFirst

    /// Short MM/D format for the week range. Uses POSIX locale so the
    /// output format is stable regardless of the device's region.
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Full month name (e.g., "April") localized to the user's language.
    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    /// 4-digit year.
    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func headerTitle(for timeframe: GoalTimeframe, on date: Date) -> String {
        "Goals \(periodLabel(for: timeframe, on: date))"
    }

    /// Just the time-range portion (no "Goals " prefix), used as picker
    /// segment labels in the switchable variant.
    static func periodLabel(for timeframe: GoalTimeframe, on date: Date) -> String {
        switch timeframe {
        case .week:
            let weekNumber = calendar.component(.weekOfYear, from: date)
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let start = interval?.start ?? date
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "WK\(weekNumber): \(shortDateFormatter.string(from: start)) - \(shortDateFormatter.string(from: end))"
        case .month:
            return monthNameFormatter.string(from: date)
        case .year:
            return yearFormatter.string(from: date)
        }
    }
}
