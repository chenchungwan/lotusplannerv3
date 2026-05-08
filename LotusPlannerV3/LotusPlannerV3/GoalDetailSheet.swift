import SwiftUI

// MARK: - Goal Detail Sheet
struct GoalDetailSheet: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared

    private var category: GoalCategoryData? {
        goalsManager.getCategoryById(goal.categoryId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(goal.title)
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    // Category, Due, Status
                    HStack(spacing: 12) {
                        if let cat = category {
                            tagChip(cat.title, color: .blue)
                        }
                        tagChip(goal.dueDate.formatted(date: .abbreviated, time: .omitted),
                                color: goal.isOverdue ? .red : .green)
                        tagChip(goal.isCompleted ? "Done" : "In Progress",
                                color: goal.isCompleted ? .green : .orange)
                    }

                    // Notes
                    if let ext = goal.extendedData, !ext.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(ext.notes)
                                .font(.body)
                        }
                    }

                    // Linked Tasks
                    if !goal.linkedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tasks")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            ForEach(goal.linkedTasks, id: \.taskId) { linked in
                                let task = findTask(linked.taskId)
                                HStack(spacing: 8) {
                                    Image(systemName: task?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(task?.isCompleted == true ? .green : .secondary)
                                        .font(.body)
                                    Text(task?.title ?? linked.taskTitle ?? "Task")
                                        .font(.body)
                                        .strikethrough(task?.isCompleted == true)
                                    Spacer()
                                    if let due = task?.due {
                                        Text(due.prefix(10))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Search all loaded task lists for a task by ID
    private func findTask(_ taskId: String) -> GoogleTask? {
        for (_, tasks) in tasksVM.personalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return task }
        }
        for (_, tasks) in tasksVM.professionalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return task }
        }
        return nil
    }

    private func tagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

