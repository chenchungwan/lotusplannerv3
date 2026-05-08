import SwiftUI

// MARK: - Create Goal View (3-Step Flow)
struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    let editingGoal: GoalData?
    let onDismiss: () -> Void
    let defaultTimeframe: TimelineInterval?
    let defaultDate: Date?

    @State private var title = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedTimeframe: GoalTimeframe = .year
    @State private var selectedDate = Date()
    @State private var notes = ""

    @State private var taskItems: [PendingTask] = []
    @State private var selectedGoalAccountKind: GoogleAuthManager.AccountKind = .personal
    @State private var selectedGoalListId: String = ""

    // Editing
    @State private var showingDeleteAlert = false
    @State private var showingTaskPicker = false
    @State private var selectedTaskForDetail: TaskDetailSelection?
    @State private var showingUnlinkTaskAlert = false
    @State private var pendingUnlinkTask: PendingTask?

    struct TaskDetailSelection: Identifiable {
        let id: String
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }

    struct PendingTask: Identifiable {
        let id = UUID()
        var title: String
        var dueDate: Date
        var accountKind: GoogleAuthManager.AccountKind = .personal
        var listId: String = ""
        var existingTaskId: String? = nil // Non-nil if this is an already-created task
    }

    init(editingGoal: GoalData? = nil, defaultTimeframe: TimelineInterval? = nil, defaultDate: Date? = nil, onDismiss: @escaping () -> Void = {}) {
        self.editingGoal = editingGoal
        self.onDismiss = onDismiss
        self.defaultTimeframe = defaultTimeframe
        self.defaultDate = defaultDate
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategoryId != nil
    }

    private var availableTaskLists: [(list: GoogleTaskList, kind: GoogleAuthManager.AccountKind)] {
        var result: [(GoogleTaskList, GoogleAuthManager.AccountKind)] = []
        for list in tasksVM.personalTaskLists {
            result.append((list, .personal))
        }
        for list in tasksVM.professionalTaskLists {
            result.append((list, .professional))
        }
        return result
    }

    private var defaultListId: String {
        tasksVM.personalTaskLists.first?.id ?? tasksVM.professionalTaskLists.first?.id ?? ""
    }

    private var defaultAccountKind: GoogleAuthManager.AccountKind {
        if !tasksVM.personalTaskLists.isEmpty { return .personal }
        return .professional
    }

    @ViewBuilder
    private var formContent: some View {
        // Goal Details
        goalDetailsSection

        // Tasks
        tasksSection

        // Notes
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("Optional notes...", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }

        // Delete
        if editingGoal != nil {
            Button(action: { showingDeleteAlert = true }) {
                HStack {
                    Spacer()
                    Text("Delete Goal")
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            .padding(.top, 8)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                #if targetEnvironment(macCatalyst)
                // Form is bridged to NSStackView under Mac Catalyst's Mac idiom
                // and produces stable, deterministic layout. ScrollView+VStack
                // with the nested HStacks/Menus in this view triggers an Auto
                // Layout cycle that locks the main thread (CreateCategoryView,
                // which uses Form, doesn't exhibit the freeze; this view did).
                Form {
                    formContent
                }
                #else
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        formContent
                    }
                    .padding()
                }
                #endif
            }
            .navigationTitle(editingGoal != nil ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveGoal()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(editingGoal != nil ? "Save" : "Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .confirmationDialog("Delete Goal", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
                let taskCount = taskItems.filter { $0.existingTaskId != nil }.count
                if taskCount > 0 {
                    Button("Delete Goal & \(taskCount) Task\(taskCount == 1 ? "" : "s")", role: .destructive) {
                        deleteGoalWithTasks()
                    }
                    Button("Delete Goal Only (keep tasks)") {
                        deleteGoalOnly()
                    }
                } else {
                    Button("Delete Goal", role: .destructive) {
                        deleteGoalOnly()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let taskCount = taskItems.filter { $0.existingTaskId != nil }.count
                if taskCount > 0 {
                    Text("Do you also want to delete the \(taskCount) linked task\(taskCount == 1 ? "" : "s") from Google Tasks?")
                } else {
                    Text("Are you sure you want to delete '\(title)'?")
                }
            }
            .confirmationDialog("Remove Task", isPresented: $showingUnlinkTaskAlert, titleVisibility: .visible) {
                Button("Unlink Only (keep task)") {
                    if let task = pendingUnlinkTask {
                        taskItems.removeAll { $0.id == task.id }
                    }
                    pendingUnlinkTask = nil
                }
                Button("Unlink & Delete Task", role: .destructive) {
                    if let task = pendingUnlinkTask {
                        // Delete from Google Tasks
                        if let result = lookupTask(task) {
                            Task {
                                await tasksVM.deleteTask(result.task, from: result.listId, for: result.kind)
                            }
                        }
                        taskItems.removeAll { $0.id == task.id }
                    }
                    pendingUnlinkTask = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnlinkTask = nil
                }
            } message: {
                Text("Do you want to also delete this task from Google Tasks, or just remove it from this goal?")
            }
        }
        .onAppear { populateForm() }
    }

    // MARK: - Goal Details Section

    private var goalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. Run a 5K race by September", text: $title, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Category", selection: Binding(
                    get: { selectedCategoryId },
                    set: { selectedCategoryId = $0 }
                )) {
                    Text("Select a category").tag(nil as UUID?)
                    ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }), id: \.id) { category in
                        Text(category.title).tag(category.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([GoalTimeframe.year, GoalTimeframe.month, GoalTimeframe.week], id: \.self) { timeframe in
                            Button {
                                selectedTimeframe = timeframe
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedTimeframe == timeframe ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedTimeframe == timeframe ? .accentColor : .secondary)
                                    Text(timeframe.displayName)
                                        .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        #if targetEnvironment(macCatalyst)
                        // The custom Year/Month/Week picker views use `.menu` style
                        // on Catalyst (wheel pickers crash under the Mac idiom),
                        // and stacking several `NSPopUpButton`-backed pickers inside
                        // the ScrollView triggers a layout feedback loop that locks
                        // the main thread. The native compact DatePicker is bridged
                        // to a lightweight popover and avoids that path entirely;
                        // calculateDueDate() still snaps to the selected timeframe.
                        DatePicker(
                            "Due Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.calendar, Calendar.mondayFirst)
                        #else
                        Group {
                            switch selectedTimeframe {
                            case .year: YearPickerView(selectedDate: $selectedDate)
                            case .month: MonthPickerView(selectedDate: $selectedDate)
                            case .week: WeekPickerView(selectedDate: $selectedDate)
                            }
                        }
                        .frame(height: 100)
                        .clipped()
                        #endif

                        Text("Due: \(calculateDueDate().formatted(date: .abbreviated, time: .omitted))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            // Default Task List
            VStack(alignment: .leading, spacing: 8) {
                Text("Task List")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("New tasks for this goal will be created in this list")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach([GoogleAuthManager.AccountKind.personal, .professional], id: \.self) { kind in
                        if authManager.isLinked(kind: kind) {
                            let lists = kind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
                            if !lists.isEmpty {
                                Menu {
                                    ForEach(lists) { list in
                                        Button {
                                            selectedGoalAccountKind = kind
                                            selectedGoalListId = list.id
                                        } label: {
                                            HStack {
                                                Text(list.title)
                                                if selectedGoalAccountKind == kind && selectedGoalListId == list.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    let currentList = lists.first(where: { $0.id == selectedGoalListId && selectedGoalAccountKind == kind })
                                    HStack(spacing: 4) {
                                        Image(systemName: selectedGoalAccountKind == kind ? "largecircle.fill.circle" : "circle")
                                            .font(.caption)
                                            .foregroundColor(selectedGoalAccountKind == kind ? (kind == .personal ? appPrefs.personalColor : appPrefs.professionalColor) : .secondary)
                                        Text(appPrefs.accountName(for: kind))
                                            .font(.subheadline)
                                        if let currentList, selectedGoalAccountKind == kind {
                                            Text("/ \(currentList.title)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.subheadline)
                .fontWeight(.semibold)

            let sortedIndices = taskItems.indices.sorted { a, b in
                let aDate = resolvedDueDate(taskItems[a])
                let bDate = resolvedDueDate(taskItems[b])
                return aDate < bDate
            }
            ForEach(sortedIndices, id: \.self) { index in
                if taskItems[index].existingTaskId != nil {
                    existingTaskRow(taskItems[index])
                } else {
                    newTaskRow($taskItems[index])
                }
            }

            HStack(spacing: 16) {
                Button {
                    addTaskItem()
                } label: {
                    Label("New Task", systemImage: "plus.circle.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    showingTaskPicker = true
                } label: {
                    Label("Link Existing", systemImage: "link.circle.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingTaskPicker) {
            TaskPickerSheet(
                tasksVM: tasksVM,
                alreadyLinkedIds: Set(taskItems.compactMap { $0.existingTaskId }),
                onSelect: { task, listId, kind in
                    // `task.dueDate` already handles both date-only ("yyyy-MM-dd")
                    // and full-ISO formats Google can return. The previous
                    // inline formatter only matched full-ISO and silently fell
                    // through to "today" for date-only `due` strings — which
                    // is most of them.
                    let dueDate = task.dueDate ?? Date()
                    taskItems.append(PendingTask(
                        title: task.title,
                        dueDate: dueDate,
                        accountKind: kind,
                        listId: listId,
                        existingTaskId: task.id
                    ))
                }
            )
        }
        .sheet(item: $selectedTaskForDetail, onDismiss: {
            // Refresh taskItems from goal's current linkedTasks after task detail changes
            if let goal = editingGoal, let currentGoal = goalsManager.goals.first(where: { $0.id == goal.id }) {
                refreshTaskItems(from: currentGoal)
            }
        }) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksVM,
                onSave: { updatedTask in
                    Task {
                        await tasksVM.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        await tasksVM.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        // Remove from local taskItems
                        taskItems.removeAll { $0.existingTaskId == sel.task.id }
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksVM.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksVM.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }

    // MARK: - Task Row Helpers

    private func existingTaskRow(_ item: PendingTask) -> some View {
        let result = lookupTask(item)
        let task = result?.task
        let isCompleted = task?.isCompleted ?? false
        let listName = listNameForTask(item)

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .secondary)
                .font(.body)

            Text(task?.title ?? item.title)
                .font(.body)
                .strikethrough(isCompleted)
                .foregroundColor(isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if !listName.isEmpty {
                Text(listName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            let tag = dueDateTagStyle(task?.dueDate ?? item.dueDate, isCompleted: isCompleted)
            Text(tag.text)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tag.bgColor)
                .foregroundColor(tag.textColor)
                .cornerRadius(4)

            Button {
                pendingUnlinkTask = item
                showingUnlinkTaskAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let result = lookupTask(item) {
                selectedTaskForDetail = TaskDetailSelection(
                    id: result.task.id,
                    task: result.task,
                    listId: result.listId,
                    accountKind: result.kind
                )
            }
        }
    }

    private func newTaskRow(_ item: Binding<PendingTask>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.body)
                TextField("Task name", text: item.title)
                    .textFieldStyle(.roundedBorder)
                Button {
                    taskItems.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                DatePicker("Due", selection: item.dueDate, in: ...calculateDueDate(), displayedComponents: .date)
                    .environment(\.calendar, Calendar.mondayFirst)
                    .font(.caption)

                if availableTaskLists.count > 1 {
                    Picker("List", selection: Binding(
                        get: { "\(item.wrappedValue.accountKind == .personal ? "p" : "w"):\(item.wrappedValue.listId)" },
                        set: { newValue in
                            let parts = newValue.split(separator: ":")
                            if parts.count == 2 {
                                item.wrappedValue.accountKind = parts[0] == "p" ? .personal : .professional
                                item.wrappedValue.listId = String(parts[1])
                            }
                        }
                    )) {
                        ForEach(availableTaskLists, id: \.list.id) { entry in
                            let prefix = appPrefs.accountName(for: entry.kind)
                            Text("\(prefix): \(entry.list.title)")
                                .tag("\(entry.kind == .personal ? "p" : "w"):\(entry.list.id)")
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func lookupTask(_ item: PendingTask) -> (task: GoogleTask, listId: String, kind: GoogleAuthManager.AccountKind)? {
        guard let taskId = item.existingTaskId else { return nil }
        // First try stored list
        let tasksDict = item.accountKind == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        if let task = tasksDict[item.listId]?.first(where: { $0.id == taskId }) {
            return (task, item.listId, item.accountKind)
        }
        // Search all lists in case the task was moved
        for (listId, tasks) in tasksVM.personalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return (task, listId, .personal) }
        }
        for (listId, tasks) in tasksVM.professionalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return (task, listId, .professional) }
        }
        return nil
    }

    private func listNameForTask(_ item: PendingTask) -> String {
        // Use actual list from lookup, not stored list ID
        if let result = lookupTask(item) {
            let lists = result.kind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            return lists.first(where: { $0.id == result.listId })?.title ?? ""
        }
        let lists = item.accountKind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        return lists.first(where: { $0.id == item.listId })?.title ?? ""
    }

    // MARK: - Helpers

    private func addTaskItem() {
        let dueDate = calculateDueDate()
        taskItems.append(PendingTask(
            title: "",
            dueDate: dueDate,
            accountKind: selectedGoalAccountKind,
            listId: selectedGoalListId
        ))
    }

    private func calculateDueDate() -> Date {
        let calendar = Calendar.mondayFirst
        switch selectedTimeframe {
        case .week:
            // End of Monday-first week = Sunday
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) {
                return calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? selectedDate
            }
            return selectedDate
        case .month:
            if let end = calendar.dateInterval(of: .month, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
            }
            return selectedDate
        case .year:
            if let end = calendar.dateInterval(of: .year, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
            }
            return selectedDate
        }
    }

    private func populateForm() {
        // Use fresh goal data from GoalsManager (not stale copy passed in)
        let goal: GoalData? = editingGoal.flatMap { eg in
            goalsManager.goals.first(where: { $0.id == eg.id })
        } ?? editingGoal

        // Set default task list
        selectedGoalAccountKind = defaultAccountKind
        selectedGoalListId = defaultListId

        if let goal {
            title = goal.title
            selectedCategoryId = goal.categoryId
            selectedTimeframe = goal.targetTimeframe
            selectedDate = goal.dueDate
            notes = goal.extendedData?.notes ?? ""

            // Restore saved default list, or fall back to first linked task's list
            if let savedListId = goal.extendedData?.defaultListId, !savedListId.isEmpty {
                selectedGoalListId = savedListId
                if goal.extendedData?.defaultAccountKind == "professional" {
                    selectedGoalAccountKind = .professional
                } else {
                    selectedGoalAccountKind = .personal
                }
            } else if let firstLinked = goal.linkedTasks.first {
                selectedGoalAccountKind = firstLinked.accountKindEnum
                selectedGoalListId = firstLinked.listId
            }

            // Populate linked tasks as PendingTask items for editing
            for linked in goal.linkedTasks {
                // Search all lists to find the task (may have been moved)
                var foundTask: GoogleTask? = nil
                var foundListId = linked.listId
                var foundKind = linked.accountKindEnum

                // Try stored list first
                let tasksDict = linked.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
                if let task = tasksDict[linked.listId]?.first(where: { $0.id == linked.taskId }) {
                    foundTask = task
                } else {
                    // Search all lists
                    for (listId, tasks) in tasksVM.personalTasks {
                        if let task = tasks.first(where: { $0.id == linked.taskId }) {
                            foundTask = task; foundListId = listId; foundKind = .personal; break
                        }
                    }
                    if foundTask == nil {
                        for (listId, tasks) in tasksVM.professionalTasks {
                            if let task = tasks.first(where: { $0.id == linked.taskId }) {
                                foundTask = task; foundListId = listId; foundKind = .professional; break
                            }
                        }
                    }
                }

                // `dueDate` on GoogleTask handles both date-only and full-ISO
                // formats; fall back to today when the task has no `due`.
                let dueDate = foundTask?.dueDate ?? Date()

                taskItems.append(PendingTask(
                    title: foundTask?.title ?? linked.taskTitle ?? "Task",
                    dueDate: dueDate,
                    accountKind: foundKind,
                    listId: foundListId,
                    existingTaskId: linked.taskId
                ))
            }
        } else {
            selectedCategoryId = goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }).first?.id

            if let defaultInterval = defaultTimeframe, let date = defaultDate {
                let calendar = Calendar.mondayFirst
                switch defaultInterval {
                case .day, .week:
                    selectedTimeframe = .week
                    if let i = calendar.dateInterval(of: .weekOfYear, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .month:
                    selectedTimeframe = .month
                    if let i = calendar.dateInterval(of: .month, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .year:
                    selectedTimeframe = .year
                    if let i = calendar.dateInterval(of: .year, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                }
            } else {
                selectedTimeframe = .year
                selectedDate = Date()
            }
        }
    }

    private func refreshTaskItems(from goal: GoalData) {
        // Keep any new (unsaved) tasks, rebuild existing task items from goal's current links
        let newTasks = taskItems.filter { $0.existingTaskId == nil }
        var existingTasks: [PendingTask] = []

        for linked in goal.linkedTasks {
            var foundTask: GoogleTask? = nil
            var foundListId = linked.listId
            var foundKind = linked.accountKindEnum

            // Search all lists to find the task
            for (listId, tasks) in tasksVM.personalTasks {
                if let task = tasks.first(where: { $0.id == linked.taskId }) {
                    foundTask = task; foundListId = listId; foundKind = .personal; break
                }
            }
            if foundTask == nil {
                for (listId, tasks) in tasksVM.professionalTasks {
                    if let task = tasks.first(where: { $0.id == linked.taskId }) {
                        foundTask = task; foundListId = listId; foundKind = .professional; break
                    }
                }
            }

            let dueDate = foundTask?.dueDate ?? Date()
            existingTasks.append(PendingTask(
                title: foundTask?.title ?? linked.taskTitle ?? "Task",
                dueDate: dueDate,
                accountKind: foundKind,
                listId: foundListId,
                existingTaskId: linked.taskId
            ))
        }

        taskItems = existingTasks + newTasks
    }

    @State private var isSaving = false

    private func saveGoal() {
        guard let categoryId = selectedCategoryId, !isSaving else { return }
        isSaving = true

        let extData = GoalExtendedData(
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultListId: selectedGoalListId.isEmpty ? nil : selectedGoalListId,
            defaultAccountKind: selectedGoalAccountKind == .personal ? "personal" : "professional"
        )

        let dueDate = calculateDueDate()
        let goalTitle = title
        // Separate existing tasks (already created) from new ones
        let filledTasks = taskItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let newTasks = filledTasks.filter { $0.existingTaskId == nil }
        let existingTasks = filledTasks.filter { $0.existingTaskId != nil }
        let defListId = selectedGoalListId.isEmpty ? defaultListId : selectedGoalListId

        Task {
            // Keep existing linked tasks
            var linkedTasks: [LinkedTaskData] = existingTasks.map { item in
                LinkedTaskData(
                    taskId: item.existingTaskId!,
                    listId: item.listId,
                    accountKind: item.accountKind,
                    taskTitle: item.title
                )
            }

            // Create only new tasks
            for item in newTasks {
                let listId = item.listId.isEmpty ? defListId : item.listId
                let kind = item.accountKind

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let dueDateStr = formatter.string(from: item.dueDate)

                let tempTask = GoogleTask(
                    id: UUID().uuidString,
                    title: item.title,
                    notes: nil,
                    status: "needsAction",
                    due: dueDateStr
                )

                do {
                    let createdTask = try await tasksVM.createTaskOnServer(tempTask, in: listId, for: kind)
                    // Add to local state properly
                    await MainActor.run {
                        switch kind {
                        case .personal:
                            if tasksVM.personalTasks[listId] != nil {
                                // Avoid duplicate — check if already present
                                if !tasksVM.personalTasks[listId]!.contains(where: { $0.id == createdTask.id }) {
                                    tasksVM.personalTasks[listId]?.append(createdTask)
                                }
                            } else {
                                tasksVM.personalTasks[listId] = [createdTask]
                            }
                        case .professional:
                            if tasksVM.professionalTasks[listId] != nil {
                                if !tasksVM.professionalTasks[listId]!.contains(where: { $0.id == createdTask.id }) {
                                    tasksVM.professionalTasks[listId]?.append(createdTask)
                                }
                            } else {
                                tasksVM.professionalTasks[listId] = [createdTask]
                            }
                        }
                    }
                    linkedTasks.append(LinkedTaskData(
                        taskId: createdTask.id,
                        listId: listId,
                        accountKind: kind,
                        taskTitle: createdTask.title
                    ))
                } catch {
                    devLog("Failed to create task '\(item.title)': \(error)", level: .error, category: .tasks)
                }
            }

            await MainActor.run {
                if let existingGoal = editingGoal {
                    var updatedGoal = existingGoal
                    updatedGoal.title = title
                    updatedGoal.categoryId = categoryId
                    updatedGoal.targetTimeframe = selectedTimeframe
                    updatedGoal.dueDate = dueDate
                    updatedGoal.updatedAt = Date()
                    updatedGoal.extendedData = extData
                    updatedGoal.linkedTasks = linkedTasks
                    goalsManager.updateGoal(updatedGoal)
                } else {
                    devLog("Creating goal '\(title)' with \(linkedTasks.count) linked tasks: \(linkedTasks.map { $0.taskId })", level: .info, category: .goals)
                    let newGoal = GoalData(
                        title: title,
                        categoryId: categoryId,
                        targetTimeframe: selectedTimeframe,
                        dueDate: dueDate,
                        linkedTasks: linkedTasks,
                        extendedData: extData
                    )
                    goalsManager.addGoal(newGoal)
                }

                onDismiss()
                dismiss()
            }
        }
    }

    private func deleteGoalWithTasks() {
        if let goal = editingGoal {
            // Delete linked Google Tasks
            for linked in goal.linkedTasks {
                // Search all lists to find the task
                var found = false
                for (listId, tasks) in tasksVM.personalTasks {
                    if let task = tasks.first(where: { $0.id == linked.taskId }) {
                        Task { await tasksVM.deleteTask(task, from: listId, for: .personal) }
                        found = true; break
                    }
                }
                if !found {
                    for (listId, tasks) in tasksVM.professionalTasks {
                        if let task = tasks.first(where: { $0.id == linked.taskId }) {
                            Task { await tasksVM.deleteTask(task, from: listId, for: .professional) }
                            break
                        }
                    }
                }
            }
            goalsManager.deleteGoal(goal.id)
        }
        onDismiss()
        dismiss()
    }

    private func deleteGoalOnly() {
        if let goal = editingGoal {
            goalsManager.deleteGoal(goal.id)
        }
        onDismiss()
        dismiss()
    }

    private func resolvedDueDate(_ item: PendingTask) -> Date {
        if let existingId = item.existingTaskId {
            let result = lookupTask(item)
            return result?.task.dueDate ?? item.dueDate
        }
        return item.dueDate
    }

    private func dueDateTagStyle(_ date: Date, isCompleted: Bool) -> (text: String, textColor: Color, bgColor: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)

        if isCompleted {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        } else if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, .accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        }
    }
}

