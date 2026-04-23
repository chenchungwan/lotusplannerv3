import SwiftUI

/// Single-line horizontally-scrollable strip listing the goals whose
/// `targetTimeframe == .week` and whose `dueDate` falls in the week
/// containing `currentDate`. Pins to the top of its cell (same layout
/// convention as the Health Bar) and hosts the section title + all
/// weekly goals on one row so the user can scan them at a glance and
/// scroll for the rest when the content overflows.
struct WeeklyGoalsBarComponent: View {
    let currentDate: Date

    @ObservedObject private var goalsManager = GoalsManager.shared

    /// Weekly goals for the week containing `currentDate`, ordered to
    /// match the user's Goals view arrangement (category display
    /// position, then goal display order within the category).
    private var goals: [GoalData] {
        let calendar = Calendar.mondayFirst
        let matching = goalsManager.goals.filter { goal in
            goal.targetTimeframe == .week &&
            calendar.isDate(goal.dueDate, equalTo: currentDate, toGranularity: .weekOfYear)
        }
        let positionByCategory: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: goalsManager.categories.map { ($0.id, $0.displayPosition) }
        )
        return matching.sorted { lhs, rhs in
            let lPos = positionByCategory[lhs.categoryId] ?? Int.max
            let rPos = positionByCategory[rhs.categoryId] ?? Int.max
            if lPos != rPos { return lPos < rPos }
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        // Stay pinned to the top of whatever cell this is dropped into and
        // match the Health Bar's one-line-tall aesthetic.
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("This Week's Goals")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: true, vertical: false)

                    if goals.isEmpty {
                        Text("— no goals this week")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        ForEach(goals) { goal in
                            goalChip(goal)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }

    private func goalChip(_ goal: GoalData) -> some View {
        HStack(spacing: 4) {
            Text(goal.isCompleted ? "🚀" : "🎯")
                .font(.body)

            Text(goal.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                goal.isCompleted
                    ? Color.green.opacity(0.25)
                    : Color(.systemBackground)
            )
        )
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }
}

#Preview {
    WeeklyGoalsBarComponent(currentDate: Date())
        .frame(width: 360, height: 48)
}
