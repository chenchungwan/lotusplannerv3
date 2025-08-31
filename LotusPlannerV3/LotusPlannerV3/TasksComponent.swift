import SwiftUI

struct TasksComponent: View {
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accentColor: Color
    let accountType: GoogleAuthManager.AccountKind
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    let onListRename: ((String, String) -> Void)? // listId, newName
    let onOrderChanged: (([GoogleTaskList]) -> Void)? // callback to update parent state
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @State private var localTaskLists: [GoogleTaskList] = []
    @State private var dragOver = false
    
    init(taskLists: [GoogleTaskList], tasksDict: [String: [GoogleTask]], accentColor: Color, accountType: GoogleAuthManager.AccountKind, onTaskToggle: @escaping (GoogleTask, String) -> Void, onTaskDetails: @escaping (GoogleTask, String) -> Void, onListRename: ((String, String) -> Void)?, onOrderChanged: (([GoogleTaskList]) -> Void)? = nil) {
        self.taskLists = taskLists
        self.tasksDict = tasksDict
        self.accentColor = accentColor
        self.accountType = accountType
        self.onTaskToggle = onTaskToggle
        self.onTaskDetails = onTaskDetails
        self.onListRename = onListRename
        self.onOrderChanged = onOrderChanged
        self._localTaskLists = State(initialValue: taskLists)
    }
    
    // Account title removed as requested
    
    var body: some View {
        VStack(spacing: 12) {
            // Debug indicator (only show when dragging)
            if dragOver {
                HStack {
                    Spacer()
                    Text("DROP HERE")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(localTaskLists, id: \.id) { taskList in
                        if let tasks = tasksDict[taskList.id] {
                            let filteredTasks = appPrefs.hideCompletedTasks ? tasks.filter { !$0.isCompleted } : tasks
                            if !filteredTasks.isEmpty {
                                TaskComponentListCard(
                                    taskList: taskList,
                                    tasks: filteredTasks,
                                    accentColor: accentColor,
                                    onTaskToggle: { task in
                                        onTaskToggle(task, taskList.id)
                                    },
                                    onTaskDetails: { task in
                                        onTaskDetails(task, taskList.id)
                                    },
                                    onListRename: { newName in
                                        onListRename?(taskList.id, newName)
                                    }
                                )
                                .onDrag {
                                    NSItemProvider(object: taskList.id as NSString)
                                }
                                .onDrop(of: ["public.text"], isTargeted: $dragOver) { providers in
                                    print("onDrop triggered for taskList: \(taskList.title)")
                                    guard let provider = providers.first else { print("No provider found"); return false }
                                    provider.loadItem(forTypeIdentifier: "public.text", options: nil) { (item, error) in
                                        if let error = error {
                                            print("Error loading item: \(error)")
                                            return
                                        }
                                        if let data = item as? Data, let id = String(data: data, encoding: .utf8) {
                                            print("Loaded item ID: \(id)")
                                            DispatchQueue.main.async {
                                                handleDrop(from: id, to: taskList.id)
                                            }
                                        } else {
                                            print("Failed to load item as string")
                                        }
                                    }
                                    return true
                                }
                            }
                        }
                    }
                    
                    if tasksDict.allSatisfy({ tasks in
                        let filteredTasks = appPrefs.hideCompletedTasks ? tasks.value.filter { !$0.isCompleted } : tasks.value
                        return filteredTasks.isEmpty
                    }) {
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
    
    private func handleDrop(from sourceId: String, to destinationId: String) {
        print("handleDrop function triggered")
        print("Handling drop from \(sourceId) to \(destinationId)")
        guard let sourceIndex = localTaskLists.firstIndex(where: { $0.id == sourceId }),
              let destinationIndex = localTaskLists.firstIndex(where: { $0.id == destinationId }) else {
            print("Invalid indices for source or destination")
            return
        }
        
        print("Source index: \(sourceIndex), Destination index: \(destinationIndex)")
        let movedTaskList = localTaskLists.remove(at: sourceIndex)
        localTaskLists.insert(movedTaskList, at: destinationIndex)

        print("Updated localTaskLists order: \(localTaskLists.map { $0.title })")
        // Force UI update
        dragOver = false

        // Notify parent of order change
        onOrderChanged?(localTaskLists)

        // Update the order in the view model
        Task {
            await tasksViewModel.updateTaskListOrder(localTaskLists, for: accountType)
            print("Called updateTaskListOrder in viewModel with order: \(localTaskLists.map { $0.title })")
        }
        print("Moved task list from \(sourceId) to \(destinationId)")
    }
    
    private func handleCrossAccountDrop(from sourceId: String, toAccount targetAccount: GoogleAuthManager.AccountKind) {
        Task {
            await tasksViewModel.moveTaskList(sourceId, toAccount: targetAccount)
        }
        print("Moved task list \(sourceId) to \(targetAccount)")
    }
}

private struct TaskComponentListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accentColor: Color
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask) -> Void
    let onListRename: (String) -> Void
    
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    
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
                if isEditingTitle {
                    TextField("List name", text: $editedTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveTitle()
                        }
                        .onAppear {
                            editedTitle = taskList.title
                        }
                } else {
                    Text(taskList.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                        .onTapGesture {
                            startEditing()
                        }
                }
                
                Spacer()
                
                if isEditingTitle {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Button("Save") {
                        saveTitle()
                    }
                    .font(.caption)
                    .foregroundColor(accentColor)
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    TaskComponentRow(
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onDrag {
            NSItemProvider(object: taskList.id as NSString)
        }
    }
    
    private func startEditing() {
        editedTitle = taskList.title
        isEditingTitle = true
    }
    
    private func cancelEditing() {
        isEditingTitle = false
        editedTitle = ""
    }
    
    private func saveTitle() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != taskList.title {
            onListRename(trimmedTitle)
        }
        isEditingTitle = false
    }
}

private struct TaskComponentRow: View {
    let task: GoogleTask
    let accentColor: Color
    let onToggle: () -> Void
    let onDetails: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                // Due date tag
                if let dateTag = dueDateTag(for: task) {
                    Text(dateTag.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(dateTag.textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(dateTag.backgroundColor)
                        )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDetails()
        }
    }
    
    private func dueDateTag(for task: GoogleTask) -> (text: String, textColor: Color, backgroundColor: Color)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if task.isCompleted {
            // Show completion date for completed tasks
            guard let completionDate = task.completionDate else { return nil }
            let completionDay = calendar.startOfDay(for: completionDate)
            
            if calendar.isDate(completionDay, inSameDayAs: today) {
                return ("Completed Today", .white, .green)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d/yy"
                return ("Completed \(formatter.string(from: completionDate))", .white, .green)
            }
        } else {
            // Show due date for incomplete tasks
            guard let dueDate = task.dueDate else { return nil }
            let dueDay = calendar.startOfDay(for: dueDate)
            
            if calendar.isDate(dueDay, inSameDayAs: today) {
                return ("Today", .white, accentColor)
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                      calendar.isDate(dueDay, inSameDayAs: tomorrow) {
                return ("Tomorrow", .white, .orange)
            } else if dueDay < today {
                return ("Overdue", .white, .red)
            } else {
                // Future date
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d/yy"
                return (formatter.string(from: dueDate), .primary, Color(.systemGray5))
            }
        }
    }
}

// MARK: - Preview
struct TasksComponent_Previews: PreviewProvider {
    static var previews: some View {
        TasksComponent(
            taskLists: [],
            tasksDict: [:],
            accentColor: .purple,
            accountType: .personal,
            onTaskToggle: { _, _ in },
            onTaskDetails: { _, _ in },
            onListRename: { _, _ in },
            onOrderChanged: { _ in }
        )
        .previewLayout(.sizeThatFits)
    }
}
