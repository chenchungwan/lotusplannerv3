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
    /// Observed so the chip backgrounds re-fill when a linked task's
    /// completion status changes (drives the progressive green capsule).
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel

    /// Weekly goals for the week containing `currentDate`, ordered to match
    /// the user's Goals view arrangement (a global `displayOrder` set by
    /// drag-and-drop in Goals view).
    private var goals: [GoalData] {
        let calendar = Calendar.mondayFirst
        let matching = goalsManager.goals.filter { goal in
            goal.targetTimeframe == .week &&
            calendar.isDate(goal.dueDate, equalTo: currentDate, toGranularity: .weekOfYear)
        }
        return matching.sorted { lhs, rhs in
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
                // contentShape applied inside the scroll's HStack so taps
                // on empty horizontal area also register, not just on the
                // chips themselves.
                .contentShape(Rectangle())
                .onTapGesture {
                    openGoalsView(forTimeframe: .week)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }

    private func goalChip(_ goal: GoalData) -> some View {
        let progress = goalCompletionProgress(goal: goal, tasksVM: tasksVM)
        return HStack(spacing: 4) {
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
            // System-background fill below + a left-anchored green
            // overlay clipped to the capsule shape so the fill grows
            // proportionally with linked-task completion.
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemBackground))
                if progress > 0 {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.green.opacity(0.25))
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                }
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }
}

#Preview {
    WeeklyGoalsBarComponent(currentDate: Date())
        .frame(width: 360, height: 48)
}
