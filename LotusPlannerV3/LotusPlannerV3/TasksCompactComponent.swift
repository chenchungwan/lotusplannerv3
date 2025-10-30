import SwiftUI

struct TasksCompactComponent: View {
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accentColor: Color
    let accountType: GoogleAuthManager.AccountKind
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    
    var body: some View {
        // Hide entirely if the corresponding account is not linked
        if !authManager.isLinked(kind: accountType) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Account title
                Text(accountType == .personal ? "Personal Tasks" : "Professional Tasks")
                    .font(.headline)
                    .foregroundColor(accentColor)
                
                // Tasks list
                if allTasks.isEmpty {
                    Text("No tasks")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sortedTasksWithLists) { item in
                            TaskCompactRow(
                                task: item.task,
                                listName: item.listName,
                                accentColor: accentColor,
                                onToggle: { onTaskToggle(item.task, item.listId) },
                                onDetails: { onTaskDetails(item.task, item.listId) }
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var allTasks: [GoogleTask] {
        tasksDict.values.flatMap { $0 }
    }
    
    private var sortedTasksWithLists: [TaskWithList] {
        // Build array of tasks with their list info and list position
        var tasksWithLists: [TaskWithList] = []
        for (listId, tasks) in tasksDict {
            let listName = taskLists.first(where: { $0.id == listId })?.title ?? "Unknown List"
            // Find the position of this list in the taskLists array
            let listPosition = taskLists.firstIndex(where: { $0.id == listId }) ?? Int.max
            for task in tasks {
                tasksWithLists.append(TaskWithList(task: task, listId: listId, listName: listName, listPosition: listPosition))
            }
        }
        
        // Filter out completed tasks if hideCompletedTasks is enabled
        let filtered = appPrefs.hideCompletedTasks ? tasksWithLists.filter { !$0.task.isCompleted } : tasksWithLists
        
        // Sort by: 1) completion status, 2) task list position, 3) alphabetically
        return filtered.sorted { (a, b) in
            // 1. Sort by completion status (incomplete first)
            if a.task.isCompleted != b.task.isCompleted {
                return !a.task.isCompleted
            }
            
            // 2. Sort by task list position (earlier lists first)
            if a.listPosition != b.listPosition {
                return a.listPosition < b.listPosition
            }
            
            // 3. Sort alphabetically by title
            return a.task.title.localizedCaseInsensitiveCompare(b.task.title) == .orderedAscending
        }
    }
}

struct TaskWithList: Identifiable {
    let task: GoogleTask
    let listId: String
    let listName: String
    let listPosition: Int
    
    var id: String { task.id }
}

private struct TaskCompactRow: View {
    let task: GoogleTask
    let listName: String
    let accentColor: Color
    let onToggle: () -> Void
    let onDetails: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkable circle
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Task title - allow it to shrink and truncate
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0)
                .layoutPriority(0)
            
            Spacer()
            
            // List name tag - fixed size, higher priority to prevent wrapping, right-aligned
            Text(listName.count > 12 ? String(listName.prefix(12)) + "..." : listName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                )
                .fixedSize()
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDetails()
        }
    }
}

#Preview {
    TasksCompactComponent(
        taskLists: [],
        tasksDict: [:],
        accentColor: .purple,
        accountType: .personal,
        onTaskToggle: { _, _ in },
        onTaskDetails: { _, _ in }
    )
}

