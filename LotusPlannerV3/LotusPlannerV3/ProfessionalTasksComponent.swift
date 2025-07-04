import SwiftUI

struct ProfessionalTasksComponent: View {
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accentColor: Color
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Professional Tasks")
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(taskLists, id: \.id) { taskList in
                        if let tasks = tasksDict[taskList.id], !tasks.isEmpty {
                            ProfessionalTaskListCard(
                                taskList: taskList,
                                tasks: tasks,
                                accentColor: accentColor,
                                onTaskToggle: { task in
                                    onTaskToggle(task, taskList.id)
                                },
                                onTaskDetails: { task in
                                    onTaskDetails(task, taskList.id)
                                }
                            )
                        }
                    }
                    
                    if tasksDict.allSatisfy({ $0.value.isEmpty }) {
                        Text("No tasks for today")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

struct ProfessionalTaskListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accentColor: Color
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask) -> Void
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    private func isDueDateOverdue(_ dueDate: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return dueDate < startOfToday
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task list header
            HStack {
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                
                Spacer()
                
                let completedTasks = tasks.filter { $0.isCompleted }.count
                Text("\(completedTasks)/\(tasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    ProfessionalTaskRow(
                        task: task,
                        accentColor: accentColor,
                        onToggle: { onTaskToggle(task) },
                        onDetails: { onTaskDetails(task) }
                    )
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ProfessionalTaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    let onToggle: () -> Void
    let onDetails: () -> Void
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    private func isDueDateOverdue(_ dueDate: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return dueDate < startOfToday
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Recurring task indicator
                if task.isRecurringInstance {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(dueDate, formatter: Self.dateFormatter)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDueDateOverdue(dueDate) && !task.isCompleted ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate) && !task.isCompleted ? .red : .secondary)
                }
            }
        }
        .onLongPressGesture {
            onDetails()
        }
    }
}

// MARK: - Preview
struct ProfessionalTasksComponent_Previews: PreviewProvider {
    static var previews: some View {
        ProfessionalTasksComponent(
            taskLists: [],
            tasksDict: [:],
            accentColor: .green,
            onTaskToggle: { _, _ in },
            onTaskDetails: { _, _ in }
        )
        .previewLayout(.sizeThatFits)
    }
} 