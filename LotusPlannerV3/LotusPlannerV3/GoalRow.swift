import SwiftUI

// MARK: - Goal Row
struct GoalRow: View {
    let goal: GoalData
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let showTags: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 8
    }

    private var adaptiveVerticalPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 4
    }

    // Computed properties for better performance
    private var isOverdue: Bool {
        goal.dueDate < Date() && !goal.isCompleted
    }

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: goal.dueDate)
        let components = calendar.dateComponents([.day], from: today, to: dueDate)
        return components.day ?? 0
    }

    private func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // Helper to get task from linked task data — searches all lists
    private func getTask(from linkedTask: LinkedTaskData) -> GoogleTask? {
        // First try the stored list
        let tasksDict = linkedTask.accountKindEnum == .account1 ? tasksVM.account1Tasks : tasksVM.account2Tasks
        if let task = tasksDict[linkedTask.listId]?.first(where: { $0.id == linkedTask.taskId }) {
            return task
        }
        // Search all lists in case the task was moved
        for (_, tasks) in tasksVM.account1Tasks {
            if let task = tasks.first(where: { $0.id == linkedTask.taskId }) { return task }
        }
        for (_, tasks) in tasksVM.account2Tasks {
            if let task = tasks.first(where: { $0.id == linkedTask.taskId }) { return task }
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox (larger tap target) - aligned to top
            Button(action: onTap) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3) // Slightly larger for better tap target
                    .foregroundColor(goal.isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())

            // Goal content
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.body)
                    .strikethrough(goal.isCompleted)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                if showTags {
                    HStack(spacing: 4) {
                        Text(goal.targetTimeframe.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Text(formatDueDate(goal.dueDate))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isOverdue ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(isOverdue ? .red : .green)
                            .cornerRadius(4)

                        Spacer()
                    }
                }

                // Linked tasks section
                if !goal.linkedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(goal.linkedTasks, id: \.taskId) { linkedTask in
                            let task = getTask(from: linkedTask)
                            HStack(spacing: 6) {
                                Image(systemName: task?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundColor(task?.isCompleted == true ? .green : .secondary)
                                Text(task?.title ?? linkedTask.taskTitle ?? "Task")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .strikethrough(task?.isCompleted == true)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit()
            }

            Spacer()
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, adaptiveVerticalPadding)
    }
}

