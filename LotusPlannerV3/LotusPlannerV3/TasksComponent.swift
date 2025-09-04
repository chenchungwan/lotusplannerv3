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
    let horizontalCards: Bool
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var localTaskLists: [GoogleTaskList] = []
    
    init(taskLists: [GoogleTaskList], tasksDict: [String: [GoogleTask]], accentColor: Color, accountType: GoogleAuthManager.AccountKind, onTaskToggle: @escaping (GoogleTask, String) -> Void, onTaskDetails: @escaping (GoogleTask, String) -> Void, onListRename: ((String, String) -> Void)?, onOrderChanged: (([GoogleTaskList]) -> Void)? = nil, hideDueDateTag: Bool = false, showEmptyState: Bool = true, horizontalCards: Bool = false) {
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
        self.horizontalCards = horizontalCards
        self._localTaskLists = State(initialValue: taskLists)
    }
    
    // Account title removed as requested
    
    var body: some View {
        // Hide entirely if the corresponding account is not linked
        if !authManager.isLinked(kind: accountType) {
            EmptyView()
        } else {
            contentView
            .onAppear {
                // Sync local copy with upstream lists on first render
                localTaskLists = taskLists
            }
            .onChange(of: taskLists) { oldValue, newValue in
                // Keep local ordering in sync when parent updates task lists (e.g., after initial load)
                localTaskLists = newValue
            }
        }
    }
    
    // Drag-and-drop removed per request
}

// MARK: - Decomposition to simplify type-checker
extension TasksComponent {
    @ViewBuilder
    private var contentView: some View {
        if horizontalCards {
            horizontalCardsView
        } else {
            verticalCardsView
        }
    }

    private func filteredTasksForList(_ taskList: GoogleTaskList) -> [GoogleTask] {
        let tasks = tasksDict[taskList.id] ?? []
        let sortedByPosition: [GoogleTask] = tasks.sorted { (a, b) in
            switch (a.position, b.position) {
            case let (pa?, pb?): return pa < pb
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return a.id < b.id
            }
        }
        return appPrefs.hideCompletedTasks ? sortedByPosition.filter { !$0.isCompleted } : sortedByPosition
    }

    @ViewBuilder
    private func card(for taskList: GoogleTaskList, enableScroll: Bool, maxHeight: CGFloat?) -> some View {
        let filtered = filteredTasksForList(taskList)
        if !filtered.isEmpty {
            TaskComponentListCard(
                taskList: taskList,
                tasks: filtered,
                accentColor: accentColor,
                onTaskToggle: { task in onTaskToggle(task, taskList.id) },
                onTaskDetails: { task in onTaskDetails(task, taskList.id) },
                onListRename: { newName in onListRename?(taskList.id, newName) },
                hideDueDateTag: hideDueDateTag,
                enableScroll: enableScroll,
                maxTasksAreaHeight: maxHeight
            )
        }
    }

    @ViewBuilder
    private var horizontalCardsView: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(localTaskLists, id: \.id) { list in
                    card(for: list, enableScroll: true, maxHeight: UIScreen.main.bounds.height * 0.35)
                        .frame(width: UIScreen.main.bounds.width * 0.3, alignment: .top)
                }
            }
            .padding(.horizontal, 3)
        }
    }

    @ViewBuilder
    private var verticalCardsView: some View {
        VStack(spacing: 3) {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(localTaskLists, id: \.id) { list in
                        card(for: list, enableScroll: false, maxHeight: nil)
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
        .padding(3)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private var noVisibleTasks: Bool {
        tasksDict.allSatisfy { entry in
            let visible = appPrefs.hideCompletedTasks ? entry.value.filter { !$0.isCompleted } : entry.value
            return visible.isEmpty
        }
    }
}

private struct TaskComponentListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accentColor: Color
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask) -> Void
    let onListRename: (String) -> Void
    let hideDueDateTag: Bool
    let enableScroll: Bool
    let maxTasksAreaHeight: CGFloat?
    
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
    
    init(
        taskList: GoogleTaskList,
        tasks: [GoogleTask],
        accentColor: Color,
        onTaskToggle: @escaping (GoogleTask) -> Void,
        onTaskDetails: @escaping (GoogleTask) -> Void,
        onListRename: @escaping (String) -> Void,
        hideDueDateTag: Bool,
        enableScroll: Bool = false,
        maxTasksAreaHeight: CGFloat? = nil
    ) {
        self.taskList = taskList
        self.tasks = tasks
        self.accentColor = accentColor
        self.onTaskToggle = onTaskToggle
        self.onTaskDetails = onTaskDetails
        self.onListRename = onListRename
        self.hideDueDateTag = hideDueDateTag
        self.enableScroll = enableScroll
        self.maxTasksAreaHeight = maxTasksAreaHeight
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
            Group {
                if enableScroll {
                    ScrollView(.vertical, showsIndicators: true) {
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
                    .frame(height: (maxTasksAreaHeight ?? 260))
                    .clipped()
                } else {
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
