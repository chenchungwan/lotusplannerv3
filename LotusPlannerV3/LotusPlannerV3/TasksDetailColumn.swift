import SwiftUI

// MARK: - Tasks Detail Column (Right Side)
struct TasksDetailColumn: View {
    let selectedListId: String?
    let selectedAccountKind: GoogleAuthManager.AccountKind?
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var appPrefs: AppPreferences
    @ObservedObject var auth: GoogleAuthManager
    @State private var selectedTask: GoogleTask?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // State for renaming list
    @State private var showingRenameSheet = false
    @State private var renameText = ""
    /// User-selected account in the Edit List sheet. When this differs from
    /// the list's current account on Save, the list (and all its tasks) is
    /// moved across accounts.
    @State private var renameAccount: GoogleAuthManager.AccountKind = .account1

    // State for deleting list
    @State private var showingDeleteConfirmation = false

    // State for deleting completed tasks
    @State private var showingDeleteCompletedConfirmation = false

    // Persisted secondary sort key for the task list. Default is
    // due-date (closest to the prior fixed behavior).
    @AppStorage("listsSortMode") private var sortModeRaw: String = ListsSortMode.dueDate.rawValue
    private var sortMode: ListsSortMode {
        ListsSortMode(rawValue: sortModeRaw) ?? .dueDate
    }

    // State for inline task creation
    @State private var isCreatingNewTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFieldFocused: Bool

    // Bulk edit manager
    @StateObject private var bulkEditManager = BulkEditManager()

    // Callback to clear selection when list is deleted
    var onListDeleted: () -> Void = {}

    // Callback to navigate to a different list
    var onNavigateToList: (String, GoogleAuthManager.AccountKind) -> Void = { _, _ in }

    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    private var rawTasks: [GoogleTask] {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else {
            return []
        }
        
        switch accountKind {
        case .account1:
            return tasksVM.account1Tasks[listId] ?? []
        case .account2:
            return tasksVM.account2Tasks[listId] ?? []
        }
    }
    
    private var totalTaskCount: Int {
        rawTasks.count
    }
    
    private var incompleteTaskCount: Int {
        rawTasks.filter { !$0.isCompleted }.count
    }
    
    var tasks: [GoogleTask] {
        let allTasks = rawTasks

        // Filter out completed tasks if hideCompletedTasks is enabled.
        let filtered = appPrefs.hideCompletedTasks ? allTasks.filter { !$0.isCompleted } : allTasks

        // Primary sort: completion status (incomplete first). Secondary
        // sort key is user-selected via the header menu; alphabetical
        // breaks remaining ties so the order is stable.
        let sorted = filtered.sorted { (a, b) in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted
            }

            switch sortMode {
            case .dueDate:
                switch (a.dueDate, b.dueDate) {
                case let (dateA?, dateB?):
                    if dateA != dateB { return dateA < dateB }
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): break
                }
            case .priority:
                let aPriority = a.priority?.sortOrder ?? Int.max
                let bPriority = b.priority?.sortOrder ?? Int.max
                if aPriority != bPriority { return aPriority < bPriority }
            case .alphabetical:
                break // primary alphabetical match below.
            }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        return sorted
    }
    
    var selectedListTitle: String? {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else {
            return nil
        }
        
        let lists: [GoogleTaskList]
        switch accountKind {
        case .account1:
            lists = tasksVM.account1TaskLists
        case .account2:
            lists = tasksVM.account2TaskLists
        }
        
        return lists.first { $0.id == listId }?.title
    }
    
    var accentColor: Color {
        guard let accountKind = selectedAccountKind else {
            return .gray
        }
        return accountKind == .account1 ? appPrefs.account1Color : appPrefs.account2Color
    }

    func getListName(for listId: String, accountKind: GoogleAuthManager.AccountKind) -> String? {
        let lists: [GoogleTaskList]
        switch accountKind {
        case .account1:
            lists = tasksVM.account1TaskLists
        case .account2:
            lists = tasksVM.account2TaskLists
        }
        return lists.first { $0.id == listId }?.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let listTitle = selectedListTitle {
                // Header with selected list name
                HStack {
                    Button {
                        renameText = listTitle
                        renameAccount = selectedAccountKind ?? .account1
                        showingRenameSheet = true
                    } label: {
                        Text(listTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()

                    Text("\(incompleteTaskCount) | \(totalTaskCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Menu {
                        ForEach(ListsSortMode.allCases) { mode in
                            Button {
                                sortModeRaw = mode.rawValue
                            } label: {
                                Label(mode.displayName, systemImage: mode.systemImage)
                                if sortMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(adaptivePadding)
                .background(accentColor.opacity(0.1))
                
                Divider()
                
                // Tasks list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Bulk Edit Menu (shown when in bulk edit mode)
                        if bulkEditManager.state.isActive {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    // Exit bulk edit button
                                    Button {
                                        bulkEditManager.state.isActive = false
                                        bulkEditManager.state.selectedTaskIds.removeAll()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                            .frame(width: 32, height: 32)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color(.systemGray5))
                                            )
                                    }
                                    .buttonStyle(.plain)

                                    Text("\(bulkEditManager.state.selectedTaskIds.count) selected")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    // Select All / Deselect All toggle
                                    let visibleOpenIds = Set(tasks.filter { !$0.isCompleted }.map { $0.id })
                                    let allVisibleSelected = !visibleOpenIds.isEmpty &&
                                        visibleOpenIds.isSubset(of: bulkEditManager.state.selectedTaskIds)
                                    Button {
                                        if allVisibleSelected {
                                            bulkEditManager.state.selectedTaskIds.subtract(visibleOpenIds)
                                        } else {
                                            bulkEditManager.state.selectedTaskIds.formUnion(visibleOpenIds)
                                        }
                                    } label: {
                                        Text(allVisibleSelected ? "Deselect All" : "Select All")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(visibleOpenIds.isEmpty)

                                    Spacer()

                                    // Action buttons
                                    HStack(spacing: 8) {
                                        // Mark as Complete button
                                        Button {
                                            bulkEditManager.state.showingCompleteConfirmation = true
                                        } label: {
                                            Image(systemName: "checkmark.circle")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)

                                        // Update Due Date button
                                        Button {
                                            bulkEditManager.state.showingDueDatePicker = true
                                        } label: {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)

                                        // Update Priority button
                                        Button {
                                            bulkEditManager.state.showingPriorityPicker = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)

                                        // Move button
                                        Button {
                                            bulkEditManager.state.showingMoveDestinationPicker = true
                                        } label: {
                                            Image(systemName: "folder")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)

                                        // Delete button
                                        Button {
                                            bulkEditManager.state.showingDeleteConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))

                                Divider()
                            }
                        }

                        // Inline "New Task" row at the top
                        if isCreatingNewTask {
                            // TextField mode - user is typing
                            HStack(spacing: 12) {
                                // Plus icon
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .foregroundColor(accentColor)
                                
                                // TextField for entering task title
                                TextField("New task", text: $newTaskTitle)
                                    .font(.body)
                                    .focused($isNewTaskFieldFocused)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        createNewTaskInline()
                                    }
                                    .onAppear {
                                        // Focus the TextField when it appears
                                        isNewTaskFieldFocused = true
                                    }
                                
                                Spacer()
                            }
                            .padding(adaptivePadding)
                            .background(Color(.systemBackground))
                        } else {
                            // Button mode - tap to start creating
                            Button {
                                isCreatingNewTask = true
                                newTaskTitle = ""
                            } label: {
                                HStack(spacing: 12) {
                                    // Plus icon
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                        .foregroundColor(accentColor)
                                    
                                    // Placeholder text
                                    Text("New task")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(adaptivePadding)
                                .background(Color(.systemBackground))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider()
                        
                        // Existing tasks
                        if tasks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No Tasks")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(tasks) { task in
                                SimpleTaskRow(
                                    task: task,
                                    accentColor: accentColor,
                                    isBulkEditMode: bulkEditManager.state.isActive,
                                    isSelected: bulkEditManager.state.selectedTaskIds.contains(task.id),
                                    onToggle: {
                                        toggleTask(task)
                                    },
                                    onTap: {
                                        selectedTask = task
                                    },
                                    onSelectionToggle: {
                                        if bulkEditManager.state.selectedTaskIds.contains(task.id) {
                                            bulkEditManager.state.selectedTaskIds.remove(task.id)
                                        } else {
                                            bulkEditManager.state.selectedTaskIds.insert(task.id)
                                        }
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                }
            } else {
                // No list selected
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Select a List")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap a task list on the left to view its tasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $selectedTask) { task in
            if let listId = selectedListId,
               let accountKind = selectedAccountKind {
                // Check if this is a new task (empty ID means new)
                let isNewTask = task.title.isEmpty && task.id.count > 30 // New UUID has length > 30
                
                TaskDetailsView(
                    task: task,
                    taskListId: listId,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    account1TaskLists: tasksVM.account1TaskLists,
                    account2TaskLists: tasksVM.account2TaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updatedTask in
                        Task {
                            await tasksVM.updateTask(updatedTask, in: listId, for: accountKind)
                        }
                    },
                    onDelete: {
                        Task {
                            await tasksVM.deleteTask(task, from: listId, for: accountKind)
                        }
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksVM.moveTask(updatedTask, from: listId, to: targetListId, for: accountKind)
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        Task {
                            await tasksVM.crossAccountMoveTask(updatedTask, from: (accountKind, listId), to: (targetAccount, targetListId))
                        }
                    },
                    isNew: isNewTask
                )
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let listTitle = selectedListTitle,
               let listId = selectedListId,
               let accountKind = selectedAccountKind {
                RenameListSheet(
                    appPrefs: appPrefs,
                    listName: listTitle,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    hasAccount1: auth.isLinked(kind: .account1),
                    hasAccount2: auth.isLinked(kind: .account2),
                    newName: $renameText,
                    newAccount: $renameAccount,
                    onSave: {
                        editList(
                            listId: listId,
                            fromAccount: accountKind,
                            originalName: listTitle,
                            newName: renameText.trimmingCharacters(in: .whitespacesAndNewlines),
                            toAccount: renameAccount
                        )
                    },
                    onDeleteCompletedTasks: {
                        // Sheet dismisses itself; the parent's existing
                        // alert (driven by `showingDeleteCompletedConfirmation`)
                        // does the actual confirm + delete.
                        showingDeleteCompletedConfirmation = true
                    },
                    onDeleteList: {
                        // Same pattern: sheet dismisses, parent alert
                        // (driven by `showingDeleteConfirmation`) handles it.
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
        .sheet(isPresented: $bulkEditManager.state.showingMoveDestinationPicker) {
            if let sourceListId = selectedListId,
               let sourceAccountKind = selectedAccountKind {
                MoveTasksDestinationPicker(
                    appPrefs: appPrefs,
                    tasksVM: tasksVM,
                    sourceListId: sourceListId,
                    sourceAccountKind: sourceAccountKind,
                    selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                    account1Color: appPrefs.account1Color,
                    account2Color: appPrefs.account2Color,
                    hasAccount1: auth.isLinked(kind: .account1),
                    hasAccount2: auth.isLinked(kind: .account2),
                    onMove: { destinationListId, destinationAccountKind in
                        // Store the pending destination and show confirmation
                        bulkEditManager.state.pendingMoveDestination = (destinationListId, destinationAccountKind)
                        bulkEditManager.state.showingMoveConfirmation = true
                    }
                )
            }
        }
        .sheet(isPresented: $bulkEditManager.state.showingDueDatePicker) {
            BulkUpdateDueDatePicker(
                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                onSave: { dueDate, isAllDay, startTime, endTime in
                    bulkEditManager.state.pendingDueDate = dueDate
                    bulkEditManager.state.pendingIsAllDay = isAllDay
                    bulkEditManager.state.pendingStartTime = startTime
                    bulkEditManager.state.pendingEndTime = endTime
                    bulkEditManager.state.showingUpdateDueDateConfirmation = true
                }
            )
        }
        .sheet(isPresented: $bulkEditManager.state.showingPriorityPicker) {
            BulkUpdatePriorityPicker(
                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                onSave: { priority in
                    bulkEditManager.state.pendingPriority = priority
                    bulkEditManager.state.showingUpdatePriorityConfirmation = true
                }
            )
        }
        .alert("Delete List", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    deleteList(listId: listId, accountKind: accountKind)
                }
            }
        } message: {
            if let listTitle = selectedListTitle {
                Text("Are you sure you want to delete '\(listTitle)'? ALL tasks in this list (completed and incomplete) will be permanently deleted. This action cannot be undone.")
            }
        }
        .alert("Delete Completed Tasks", isPresented: $showingDeleteCompletedConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    deleteCompletedTasks(listId: listId, accountKind: accountKind)
                }
            }
        } message: {
            Text("Are you sure you want to delete all completed tasks from this list? This action cannot be undone.")
        }
        .alert("Mark as Complete", isPresented: $bulkEditManager.state.showingCompleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Complete") {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    bulkCompleteTasks(listId: listId, accountKind: accountKind)
                }
            }
        } message: {
            Text("Mark \(bulkEditManager.state.selectedTaskIds.count) selected task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s") as complete?")
        }
        .alert("Delete Tasks", isPresented: $bulkEditManager.state.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    bulkDeleteTasks(listId: listId, accountKind: accountKind)
                }
            }
        } message: {
            Text("Are you sure you want to delete \(bulkEditManager.state.selectedTaskIds.count) selected task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .alert("Move Tasks", isPresented: $bulkEditManager.state.showingMoveConfirmation) {
            Button("Cancel", role: .cancel) {
                bulkEditManager.state.pendingMoveDestination = nil
            }
            Button("Move") {
                if let sourceListId = selectedListId,
                   let sourceAccountKind = selectedAccountKind,
                   let destination = bulkEditManager.state.pendingMoveDestination {
                    bulkMoveTasks(
                        sourceListId: sourceListId,
                        sourceAccountKind: sourceAccountKind,
                        destinationListId: destination.listId,
                        destinationAccountKind: destination.accountKind
                    )
                }
            }
        } message: {
            if let destination = bulkEditManager.state.pendingMoveDestination {
                let destinationListName = getListName(for: destination.listId, accountKind: destination.accountKind) ?? "selected list"
                Text("Move \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s") to '\(destinationListName)'?")
            }
        }
        .alert("Update Due Date", isPresented: $bulkEditManager.state.showingUpdateDueDateConfirmation) {
            Button("Cancel", role: .cancel) {
                bulkEditManager.state.pendingDueDate = nil
                bulkEditManager.state.pendingIsAllDay = true
                bulkEditManager.state.pendingStartTime = nil
                bulkEditManager.state.pendingEndTime = nil
            }
            Button("Update") {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    bulkUpdateDueDate(
                        listId: listId,
                        accountKind: accountKind,
                        dueDate: bulkEditManager.state.pendingDueDate,
                        isAllDay: bulkEditManager.state.pendingIsAllDay,
                        startTime: bulkEditManager.state.pendingStartTime,
                        endTime: bulkEditManager.state.pendingEndTime
                    )
                }
            }
        } message: {
            Text("Update due date for \(bulkEditManager.state.selectedTaskIds.count) selected task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")?")
        }
        .alert("Update Priority", isPresented: $bulkEditManager.state.showingUpdatePriorityConfirmation) {
            Button("Cancel", role: .cancel) {
                bulkEditManager.state.pendingPriority = nil
            }
            Button("Update") {
                if let listId = selectedListId,
                   let accountKind = selectedAccountKind {
                    bulkUpdatePriority(
                        listId: listId,
                        accountKind: accountKind,
                        priority: bulkEditManager.state.pendingPriority
                    )
                }
            }
        } message: {
            Text("Update priority for \(bulkEditManager.state.selectedTaskIds.count) selected task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")?")
        }
        .onChange(of: selectedListId) {
            // Reset inline task creation when list changes
            isCreatingNewTask = false
            newTaskTitle = ""
            isNewTaskFieldFocused = false

            // Exit bulk edit mode when switching lists
            bulkEditManager.state.isActive = false
            bulkEditManager.state.selectedTaskIds.removeAll()
        }
        .overlay(alignment: .bottom) {
            // Undo Toast
            if bulkEditManager.state.showingUndoToast, let action = bulkEditManager.state.undoAction, let data = bulkEditManager.state.undoData {
                UndoToast(
                    action: action,
                    count: data.count,
                    accentColor: accentColor,
                    onUndo: {
                        performUndo()
                    },
                    onDismiss: {
                        bulkEditManager.state.showingUndoToast = false
                        bulkEditManager.state.undoAction = nil
                        bulkEditManager.state.undoData = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: bulkEditManager.state.showingUndoToast)
                .padding(.bottom, 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleListsBulkEdit)) { _ in
            bulkEditManager.state.isActive.toggle()
            if !bulkEditManager.state.isActive {
                // Exit bulk edit mode - clear selections
                bulkEditManager.state.selectedTaskIds.removeAll()
            }
        }
    }

    /// Renames the list and/or moves it (with all its tasks) to the other
    /// linked account. Cross-account move sequence:
    ///   1. Create a new list on the target account with the (possibly new)
    ///      name.
    ///   2. Cross-account-move every task from the source list into it.
    ///   3. Delete the source list.
    ///   4. Update the local selection so the user lands on the new list.
    private func editList(
        listId: String,
        fromAccount: GoogleAuthManager.AccountKind,
        originalName: String,
        newName: String,
        toAccount: GoogleAuthManager.AccountKind
    ) {
        guard !newName.isEmpty else { return }

        let nameChanged = newName != originalName
        let accountChanged = toAccount != fromAccount

        guard nameChanged || accountChanged else {
            // Nothing to do.
            showingRenameSheet = false
            return
        }

        Task {
            if !accountChanged {
                // Simple rename inside the same account.
                await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: fromAccount)
            } else {
                // Snapshot tasks before mutating anything.
                let sourceTasks: [GoogleTask]
                switch fromAccount {
                case .account1:
                    sourceTasks = tasksVM.account1Tasks[listId] ?? []
                case .account2:
                    sourceTasks = tasksVM.account2Tasks[listId] ?? []
                }

                guard let newListId = await tasksVM.createTaskList(title: newName, for: toAccount) else {
                    return
                }

                for task in sourceTasks {
                    _ = await tasksVM.crossAccountMoveTask(
                        task,
                        from: (fromAccount, listId),
                        to: (toAccount, newListId)
                    )
                }

                await tasksVM.deleteTaskList(listId: listId, for: fromAccount)

                await MainActor.run {
                    onNavigateToList(newListId, toAccount)
                }
            }

            await MainActor.run {
                showingRenameSheet = false
                renameText = ""
            }
        }
    }
    
    private func deleteList(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        Task {
            await tasksVM.deleteTaskList(listId: listId, for: accountKind)
            await MainActor.run {
                onListDeleted()
            }
        }
    }
    
    private func deleteCompletedTasks(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        let completedTasks = tasks.filter { $0.isCompleted }

        Task {
            // Delete each completed task
            for task in completedTasks {
                await tasksVM.deleteTask(task, from: listId, for: accountKind)
            }
        }
    }

    private func bulkCompleteTasks(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        bulkEditManager.bulkComplete(tasks: tasks, in: listId, for: accountKind, tasksVM: tasksVM) { undoTaskData in
            // Show undo toast
            bulkEditManager.state.undoAction = .complete
            bulkEditManager.state.undoData = undoTaskData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if bulkEditManager.state.undoAction == .complete && bulkEditManager.state.undoData?.count == undoTaskData.count {
                        bulkEditManager.state.showingUndoToast = false
                    }
                }
            }
        }
    }

    private func bulkDeleteTasks(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        bulkEditManager.bulkDelete(tasks: tasks, in: listId, for: accountKind, tasksVM: tasksVM) { undoTaskData in
            // Show undo toast
            bulkEditManager.state.undoAction = .delete
            bulkEditManager.state.undoData = undoTaskData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if bulkEditManager.state.undoAction == .delete && bulkEditManager.state.undoData?.count == undoTaskData.count {
                        bulkEditManager.state.showingUndoToast = false
                    }
                }
            }
        }
    }

    private func bulkMoveTasks(sourceListId: String, sourceAccountKind: GoogleAuthManager.AccountKind, destinationListId: String, destinationAccountKind: GoogleAuthManager.AccountKind) {
        bulkEditManager.bulkMove(
            tasks: tasks,
            from: sourceListId,
            sourceAccountKind: sourceAccountKind,
            to: destinationListId,
            destinationAccountKind: destinationAccountKind,
            tasksVM: tasksVM
        ) { undoTaskData in
            // Navigate to the destination list
            onNavigateToList(destinationListId, destinationAccountKind)

            // Show undo toast
            bulkEditManager.state.undoAction = .move
            bulkEditManager.state.undoData = undoTaskData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if bulkEditManager.state.undoAction == .move && bulkEditManager.state.undoData?.count == undoTaskData.count {
                        bulkEditManager.state.showingUndoToast = false
                    }
                }
            }
        }
    }

    private func bulkUpdateDueDate(listId: String, accountKind: GoogleAuthManager.AccountKind, dueDate: Date?, isAllDay: Bool = true, startTime: Date? = nil, endTime: Date? = nil) {
        bulkEditManager.bulkUpdateDueDate(
            tasks: tasks,
            in: listId,
            for: accountKind,
            dueDate: dueDate,
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
            tasksVM: tasksVM
        ) { undoTaskData in
            // Show undo toast
            bulkEditManager.state.undoAction = .updateDueDate
            bulkEditManager.state.undoData = undoTaskData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if bulkEditManager.state.undoAction == .updateDueDate && bulkEditManager.state.undoData?.count == undoTaskData.count {
                        bulkEditManager.state.showingUndoToast = false
                    }
                }
            }
        }
    }

    private func bulkUpdatePriority(listId: String, accountKind: GoogleAuthManager.AccountKind, priority: TaskPriorityData?) {
        bulkEditManager.bulkUpdatePriority(
            tasks: tasks,
            in: listId,
            for: accountKind,
            priority: priority,
            tasksVM: tasksVM
        ) { undoTaskData in
            // Show undo toast
            bulkEditManager.state.undoAction = .updatePriority
            bulkEditManager.state.undoData = undoTaskData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if bulkEditManager.state.undoAction == .updatePriority && bulkEditManager.state.undoData?.count == undoTaskData.count {
                        bulkEditManager.state.showingUndoToast = false
                    }
                }
            }
        }
    }

    // MARK: - Undo Functions

    private func performUndo() {
        guard let action = bulkEditManager.state.undoAction, let data = bulkEditManager.state.undoData else { return }

        // Hide the toast immediately
        bulkEditManager.state.showingUndoToast = false

        switch action {
        case .complete:
            bulkEditManager.undoComplete(data: data, tasksVM: tasksVM)
        case .delete:
            bulkEditManager.undoDelete(data: data, tasksVM: tasksVM)
        case .move:
            bulkEditManager.undoMove(data: data, tasksVM: tasksVM)
            // Navigate back to source list after undo move
            onNavigateToList(data.listId, data.accountKind)
        case .updateDueDate:
            bulkEditManager.undoUpdateDueDate(data: data, tasksVM: tasksVM)
        case .updatePriority:
            bulkEditManager.undoUpdatePriority(data: data, tasksVM: tasksVM)
        }

        // Clear undo state
        bulkEditManager.state.undoAction = nil
        bulkEditManager.state.undoData = nil
    }

    private func toggleTask(_ task: GoogleTask) {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else { return }
        Task {
            await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
        }
    }
    
    private func deleteTask(_ task: GoogleTask, from listId: String, for accountKind: GoogleAuthManager.AccountKind) async {
        await tasksVM.deleteTask(task, from: listId, for: accountKind)
    }
    
    private func createNewTaskInline() {
        guard let listId = selectedListId,
              let accountKind = selectedAccountKind,
              !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // If title is empty, just cancel editing
            isCreatingNewTask = false
            newTaskTitle = ""
            return
        }
        
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentDate = Calendar.current.startOfDay(for: Date()) // Use start of day for all-day task

        // Clear the text field immediately for better UX
        newTaskTitle = ""
        
        // Create the task
        Task {
            await tasksVM.createTask(
                title: trimmedTitle,
                notes: nil,
                dueDate: currentDate,
                in: listId,
                for: accountKind
            )
            
            // Keep the TextField visible and focused for quick addition of another task
            await MainActor.run {
                // Keep isCreatingNewTask = true so TextField stays visible
                // Keep isNewTaskFieldFocused = true so cursor stays in place
                // Text field is already cleared above
                isNewTaskFieldFocused = true
            }
        }
    }
}
