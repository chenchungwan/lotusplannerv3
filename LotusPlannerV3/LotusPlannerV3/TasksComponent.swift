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
    let hideDueDateTag: Bool
    let showEmptyState: Bool
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @State private var localTaskLists: [GoogleTaskList] = []
    
    init(taskLists: [GoogleTaskList], tasksDict: [String: [GoogleTask]], accentColor: Color, accountType: GoogleAuthManager.AccountKind, onTaskToggle: @escaping (GoogleTask, String) -> Void, onTaskDetails: @escaping (GoogleTask, String) -> Void, onListRename: ((String, String) -> Void)?, onOrderChanged: (([GoogleTaskList]) -> Void)? = nil, hideDueDateTag: Bool = false, showEmptyState: Bool = true) {
        self.taskLists = taskLists
        self.tasksDict = tasksDict
        self.accentColor = accentColor
        self.accountType = accountType
        self.onTaskToggle = onTaskToggle
        self.onTaskDetails = onTaskDetails
        self.onListRename = onListRename
        self.onOrderChanged = onOrderChanged
        self.hideDueDateTag = hideDueDateTag
        self.showEmptyState = showEmptyState
        self._localTaskLists = State(initialValue: taskLists)
    }
    
    // Account title removed as requested
    
    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(localTaskLists, id: \.id) { taskList in
                        if let tasks = tasksDict[taskList.id] {
                            // Sort by Google's position string (lexicographic) to match API ordering
                            let sortedByPosition = tasks.sorted { (a, b) in
                                switch (a.position, b.position) {
                                case let (pa?, pb?):
                                    return pa < pb
                                case (nil, _?):
                                    return false // place tasks without position after those with position
                                case (_?, nil):
                                    return true
                                case (nil, nil):
                                    return a.id < b.id // stable fallback
                                }
                            }
                            let filteredTasks: [GoogleTask] = appPrefs.hideCompletedTasks ? sortedByPosition.filter { !$0.isCompleted } : sortedByPosition
                            if !filteredTasks.isEmpty {
                                TaskComponentListCard(
                                    taskList: taskList,
                                    tasks: filteredTasks,
                                    accentColor: accentColor,
                                    onTaskToggle: { task in onTaskToggle(task, taskList.id) },
                                    onTaskDetails: { task in onTaskDetails(task, taskList.id) },
                                    onListRename: { newName in onListRename?(taskList.id, newName) },
                                    hideDueDateTag: hideDueDateTag
                                )
                            }
                        }
                    }

                    let noVisibleTasks: Bool = tasksDict.allSatisfy { entry in
                        let visible = appPrefs.hideCompletedTasks ? entry.value.filter { !$0.isCompleted } : entry.value
                        return visible.isEmpty
                    }
                    if showEmptyState && noVisibleTasks {
                        Text("No tasks")
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
        .onAppear {
            // Sync local copy with upstream lists on first render
            localTaskLists = taskLists
        }
        .onChange(of: taskLists) { oldValue, newValue in
            // Keep local ordering in sync when parent updates task lists (e.g., after initial load)
            localTaskLists = newValue
        }
    }
    
    // Drag-and-drop removed per request
}

private struct TaskComponentListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accentColor: Color
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask) -> Void
    let onListRename: (String) -> Void
    let hideDueDateTag: Bool
    
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    
    private var isTopPriority: Bool {
        taskList.title.localizedCaseInsensitiveContains("Top Priority")
    }
    
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
                    .environment(\.hideDueDate, hideDueDateTag)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTopPriority ? .red : Color(.systemGray4), lineWidth: isTopPriority ? 2 : 1)
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
    @Environment(\.hideDueDate) private var hideDueDate: Bool
    
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
                if !hideDueDate, let dateTag = dueDateTag(for: task) {
                    Text(dateTag.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(dateTag.textColor)
                        .strikethrough(task.isCompleted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(dateTag.backgroundColor)
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onDetails() }
        }
    }
    
    private func dueDateTag(for task: GoogleTask) -> (text: String, textColor: Color, backgroundColor: Color)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if task.isCompleted {
            // Show completion date for completed tasks (same colors as future due tasks)
            guard let completionDate = task.completionDate else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: completionDate), .primary, Color(.systemGray5))
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

private struct HideDueDateKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var hideDueDate: Bool {
        get { self[HideDueDateKey.self] }
        set { self[HideDueDateKey.self] = newValue }
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
