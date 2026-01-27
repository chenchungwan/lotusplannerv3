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
    let isSingleDayView: Bool
    let showTitle: Bool
    let showTaskStartTime: Bool
    let isBulkEditMode: Bool
    let selectedTaskIds: Set<String>
    let onTaskSelectionToggle: ((String) -> Void)?
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var localTaskLists: [GoogleTaskList] = []

    init(taskLists: [GoogleTaskList], tasksDict: [String: [GoogleTask]], accentColor: Color, accountType: GoogleAuthManager.AccountKind, onTaskToggle: @escaping (GoogleTask, String) -> Void, onTaskDetails: @escaping (GoogleTask, String) -> Void, onListRename: ((String, String) -> Void)?, onOrderChanged: (([GoogleTaskList]) -> Void)? = nil, hideDueDateTag: Bool = false, showEmptyState: Bool = true, horizontalCards: Bool = false, isSingleDayView: Bool = false, showTitle: Bool = true, showTaskStartTime: Bool = false, isBulkEditMode: Bool = false, selectedTaskIds: Set<String> = [], onTaskSelectionToggle: ((String) -> Void)? = nil) {
        self.taskLists = taskLists
        self.tasksDict = tasksDict
        self.accentColor = accentColor
        self.accountType = accountType
        self.onTaskToggle = onTaskToggle
        self.onTaskDetails = { task, listId in
            onTaskDetails(task, listId)
        }
        self.onListRename = onListRename
        self.onOrderChanged = onOrderChanged
        self.hideDueDateTag = hideDueDateTag
        self.showEmptyState = showEmptyState
        self.horizontalCards = horizontalCards
        self.isSingleDayView = isSingleDayView
        self.showTitle = showTitle
        self.showTaskStartTime = showTaskStartTime
        self.isBulkEditMode = isBulkEditMode
        self.selectedTaskIds = selectedTaskIds
        self.onTaskSelectionToggle = onTaskSelectionToggle
        self._localTaskLists = State(initialValue: taskLists)
    }
    
    // Account-specific title
    private var accountTitle: String {
        accountType == .personal ? "\(appPrefs.personalAccountName) Tasks" : "\(appPrefs.professionalAccountName) Tasks"
    }
    
    var body: some View {
        // Hide entirely if the corresponding account is not linked
        if !authManager.isLinked(kind: accountType) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Account-specific title (conditionally shown)
                if showTitle {
                    Text(accountTitle)
                        .font(.headline)
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 8)
                }

                contentView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        
        // Filter out completed tasks if hideCompletedTasks is enabled
        let filtered = appPrefs.hideCompletedTasks ? tasks.filter { !$0.isCompleted } : tasks
        
        // Sort by: 1) completion status, 2) due date, 3) alphabetically
        let sorted: [GoogleTask] = filtered.sorted { (a, b) in
            // 1. Sort by completion status (incomplete first)
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted // incomplete (false) comes before completed (true)
            }
            
            // 2. Sort by due date (soonest first, no due date goes last)
            switch (a.dueDate, b.dueDate) {
            case let (dateA?, dateB?):
                if dateA != dateB {
                    return dateA < dateB
                }
            case (_?, nil):
                return true // tasks with due dates come before tasks without
            case (nil, _?):
                return false // tasks without due dates come after tasks with
            case (nil, nil):
                break // both have no due date, continue to alphabetical sort
            }
            
            // 3. Sort alphabetically by title
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        
        return sorted
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
                onTaskDetails: { task, listId in
                    onTaskDetails(task, listId)
                },
                onListRename: { newName in onListRename?(taskList.id, newName) },
                hideDueDateTag: hideDueDateTag,
                enableScroll: enableScroll,
                maxTasksAreaHeight: maxHeight,
                isSingleDayView: isSingleDayView,
                showTaskStartTime: showTaskStartTime,
                isBulkEditMode: isBulkEditMode,
                selectedTaskIds: selectedTaskIds,
                onTaskSelectionToggle: { taskId in
                    onTaskSelectionToggle?(taskId)
                }
            )
        }
    }

    @ViewBuilder
    private var horizontalCardsView: some View {
        if showEmptyState && noVisibleTasks {
            Text("No tasks")
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(localTaskLists, id: \.id) { list in
                        card(for: list, enableScroll: true, maxHeight: 300) // Use reasonable default height
                            .frame(width: 200, alignment: .top) // Use reasonable default width
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    @ViewBuilder
    private var verticalCardsView: some View {
        if isSingleDayView {
            // In single day view, no ScrollView - flexible height
            // Note: Not using LazyVStack here as content is typically visible
            VStack(alignment: .leading, spacing: 3) {
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
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            // In other views, use ScrollView with LazyVStack for better performance
            VStack(alignment: .leading, spacing: 3) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
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
    }

    private var noVisibleTasks: Bool {
        // Check if all task lists have no visible tasks (after filtering)
        localTaskLists.allSatisfy { taskList in
            let _ = tasksDict[taskList.id] ?? []
            let filteredTasks = filteredTasksForList(taskList)
            return filteredTasks.isEmpty
        }
    }
}

private struct TaskComponentListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accentColor: Color
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    let onListRename: (String) -> Void
    let hideDueDateTag: Bool
    let enableScroll: Bool
    let maxTasksAreaHeight: CGFloat?
    let isSingleDayView: Bool
    let showTaskStartTime: Bool
    let isBulkEditMode: Bool
    let selectedTaskIds: Set<String>
    let onTaskSelectionToggle: (String) -> Void
    
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
        onTaskDetails: @escaping (GoogleTask, String) -> Void,
        onListRename: @escaping (String) -> Void,
        hideDueDateTag: Bool,
        enableScroll: Bool = false,
        maxTasksAreaHeight: CGFloat? = nil,
        isSingleDayView: Bool = false,
        showTaskStartTime: Bool = false,
        isBulkEditMode: Bool = false,
        selectedTaskIds: Set<String> = [],
        onTaskSelectionToggle: @escaping (String) -> Void = { _ in }
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
        self.isSingleDayView = isSingleDayView
        self.showTaskStartTime = showTaskStartTime
        self.isBulkEditMode = isBulkEditMode
        self.selectedTaskIds = selectedTaskIds
        self.onTaskSelectionToggle = onTaskSelectionToggle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            tasksView
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(overlayView)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onDrag {
            NSItemProvider(object: taskList.id as NSString)
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            if isEditingTitle {
                editingTitleView
            } else {
                titleView
            }
            
            Spacer()
            
            if isEditingTitle {
                editingButtonsView
            }
        }
    }
    
    @ViewBuilder
    private var editingTitleView: some View {
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
    }
    
    @ViewBuilder
    private var titleView: some View {
        Text(taskList.title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(accentColor)
            .onTapGesture {
                startEditing()
            }
    }
    
    @ViewBuilder
    private var editingButtonsView: some View {
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
    
    @ViewBuilder
    private var tasksView: some View {
        if enableScroll {
            scrollableTasksView
        } else {
            staticTasksView
        }
    }
    
    @ViewBuilder
    private var scrollableTasksView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    TaskComponentRow(
                        task: task,
                        listId: taskList.id,
                        accentColor: accentColor,
                        onToggle: { onTaskToggle(task) },
                        onDetails: { task, listId in
                            onTaskDetails(task, listId)
                        },
                        isSingleDayView: isSingleDayView,
                        showTaskStartTime: showTaskStartTime,
                        isBulkEditMode: isBulkEditMode,
                        isSelected: selectedTaskIds.contains(task.id),
                        onSelectionToggle: {
                            onTaskSelectionToggle(task.id)
                        }
                    )
                    .environment(\.hideDueDate, hideDueDateTag)
                }
            }
        }
        .frame(height: (maxTasksAreaHeight ?? 260))
        .clipped()
    }
    
    @ViewBuilder
    private var staticTasksView: some View {
        VStack(spacing: 4) {
            ForEach(tasks, id: \.id) { task in
                TaskComponentRow(
                    task: task,
                    listId: taskList.id,
                    accentColor: accentColor,
                    onToggle: { onTaskToggle(task) },
                    onDetails: { task, listId in
                        onTaskDetails(task, listId)
                    },
                    isSingleDayView: isSingleDayView,
                    showTaskStartTime: showTaskStartTime,
                    isBulkEditMode: isBulkEditMode,
                    isSelected: selectedTaskIds.contains(task.id),
                    onSelectionToggle: {
                        onTaskSelectionToggle(task.id)
                    }
                )
                .environment(\.hideDueDate, hideDueDateTag)
            }
        }
    }
    
    @ViewBuilder
    private var overlayView: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.clear, lineWidth: 1)
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
    let listId: String
    let accentColor: Color
    let onToggle: () -> Void
    let onDetails: (GoogleTask, String) -> Void
    let isSingleDayView: Bool
    let showTaskStartTime: Bool
    let isBulkEditMode: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    @Environment(\.hideDueDate) private var hideDueDate: Bool
    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 8) {
            // In bulk edit mode: show selection checkbox (square)
            // In normal mode: show completion checkbox (circle)
            if isBulkEditMode && !task.isCompleted {
                // Square selection checkbox for incomplete tasks in bulk edit mode
                Button(action: onSelectionToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundColor(isSelected ? accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Regular circular checkbox - tappable to toggle completion
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(task.isCompleted ? (isBulkEditMode ? .secondary : accentColor) : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 8) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 4) {
                    // Priority indicator
                    if let priority = task.priority {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(priority.color)
                                .frame(width: 8, height: 8)
                            Text(priority.displayText)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(priority.color)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(priority.color.opacity(0.15))
                        )
                        .fixedSize()
                    }

                    if showTaskStartTime, let startText = startTimeTagText(for: task) {
                        Text(startText)
                            .font(.caption)
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accentColor.opacity(0.15))
                            )
                            .fixedSize()
                    }

                    // Due date tags (only show if not hidden and tag is available) - aligned to the right
                    if !hideDueDate, let tagInfo = dueDateTag(for: task) {
                        Text(tagInfo.text)
                            .font(.caption)
                            .foregroundColor(tagInfo.textColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(tagInfo.backgroundColor)
                            )
                            .fixedSize()
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // In bulk edit mode: tap on task to toggle selection
                // In normal mode: tap on task to show details
                if isBulkEditMode && !task.isCompleted {
                    onSelectionToggle()
                } else {
                    onDetails(task, listId)
                }
            }
        }
    }
    
    private func startTimeTagText(for task: GoogleTask) -> String? {
        // Only show time if task has a time window (and it's not all-day)
        guard let window = timeWindowManager.getTimeWindow(for: task.id) else {
            return nil
        }

        // Don't show time for all-day tasks
        if window.isAllDay {
            return nil
        }

        return TaskComponentRow.timeFormatter.string(from: window.startTime)
    }

    private func dueDateTag(for task: GoogleTask) -> (text: String, textColor: Color, backgroundColor: Color)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if task.isCompleted {
            // In single day view, don't show date for completed tasks
            if isSingleDayView {
                return nil
            }
            // Show completion date for completed tasks (same colors as future due tasks) in other views
            guard let completionDate = task.completionDate else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: completionDate), .primary, Color(.systemGray5))
        } else {
            // Show due date for incomplete tasks
            guard let dueDate = task.dueDate else { return nil }
            let dueDay = calendar.startOfDay(for: dueDate)
            
            if isSingleDayView {
                // In single day view, only show overdue tasks
                if dueDay < today {
                    return ("Overdue", .white, .red)
                } else {
                    // Don't show future due dates or today's due dates in single day view
                    return nil
                }
            } else {
                // In other views (week, month, year, all), show all due dates
                if calendar.isDate(dueDay, inSameDayAs: today) {
                    return ("Today", .white, accentColor)
                } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                          calendar.isDate(dueDay, inSameDayAs: tomorrow) {
                    return ("Tomorrow", .white, .cyan)
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
