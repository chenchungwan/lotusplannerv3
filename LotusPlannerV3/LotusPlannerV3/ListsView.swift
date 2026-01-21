import SwiftUI

struct ListsView: View {
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @State private var isLoading = false
    @State private var selectedListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingDetailView = false // For drawer-style navigation on mobile
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // UserDefaults keys for persistence
    private let lastSelectedListIdKey = "lastSelectedTaskListId"
    private let lastSelectedAccountKindKey = "lastSelectedTaskListAccountKind"
    
    // Check if device forces stacked layout (iPhone portrait)
    private var shouldUseStackedLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Main Content
            GeometryReader { geometry in
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
                    // No accounts linked
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Google Accounts Linked")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Please link your Google account in Settings to view your task lists.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Adaptive Layout: Stacked on iPhone portrait, split otherwise
                    if shouldUseStackedLayout {
                        stackedListsView(geometry: geometry)
                    } else {
                        splitListsView(geometry: geometry)
                    }
                }
            }
        }
        .onAppear {
            loadTaskLists()
        }
        .onChange(of: shouldUseStackedLayout) { newValue in
            // Reset drawer state when switching between stacked and split layouts
            if !newValue {
                showingDetailView = false
            }
        }
    }
    
    // MARK: - Stacked Layout (iPhone Portrait) - Drawer Style
    @ViewBuilder
    private func stackedListsView(geometry: GeometryProxy) -> some View {
        ZStack {
            // List selector (always present but hidden when detail is shown)
            AllTaskListsColumn(
                personalLists: tasksVM.personalTaskLists,
                professionalLists: tasksVM.professionalTaskLists,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                selectedListId: $selectedListId,
                selectedAccountKind: $selectedAccountKind,
                hasPersonal: auth.isLinked(kind: .personal),
                hasProfessional: auth.isLinked(kind: .professional),
                onSelectionChanged: { listId, accountKind in
                    saveLastSelection(listId: listId, accountKind: accountKind)
                    // Show detail view with animation
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingDetailView = true
                    }
                },
                initialExpandedAccount: getInitialExpandedAccount()
            )
            .opacity(showingDetailView ? 0 : 1)
            
            // Detail view (slides in from right when a list is selected)
            if showingDetailView {
                VStack(spacing: 0) {
                    // Back button bar
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingDetailView = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Lists")
                                    .font(.body)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .padding(adaptivePadding)
                        
                        Spacer()
                    }
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // Detail content
                    TasksDetailColumn(
                        selectedListId: selectedListId,
                        selectedAccountKind: selectedAccountKind,
                        tasksVM: tasksVM,
                        appPrefs: appPrefs,
                        onListDeleted: {
                            selectedListId = nil
                            selectedAccountKind = nil
                            clearLastSelection()
                            // Go back to list selector when list is deleted
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingDetailView = false
                            }
                        }
                    )
                }
                .background(Color(.systemBackground))
                .transition(.move(edge: .trailing))
            }
        }
    }
    
    // MARK: - Split Layout (iPad and iPhone Landscape)
    @ViewBuilder
    private func splitListsView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left Column: All Task Lists
            AllTaskListsColumn(
                personalLists: tasksVM.personalTaskLists,
                professionalLists: tasksVM.professionalTaskLists,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                selectedListId: $selectedListId,
                selectedAccountKind: $selectedAccountKind,
                hasPersonal: auth.isLinked(kind: .personal),
                hasProfessional: auth.isLinked(kind: .professional),
                onSelectionChanged: { listId, accountKind in
                    saveLastSelection(listId: listId, accountKind: accountKind)
                },
                initialExpandedAccount: getInitialExpandedAccount()
            )
            .frame(width: geometry.size.width * 0.35)
            
            Divider()
            
            // Right Column: Selected List's Tasks
            TasksDetailColumn(
                selectedListId: selectedListId,
                selectedAccountKind: selectedAccountKind,
                tasksVM: tasksVM,
                appPrefs: appPrefs,
                onListDeleted: {
                    selectedListId = nil
                    selectedAccountKind = nil
                    clearLastSelection()
                }
            )
            .frame(width: geometry.size.width * 0.65)
        }
    }
    
    private func loadTaskLists() {
        isLoading = true
        Task {
            await tasksVM.loadTasks()
            await MainActor.run {
                isLoading = false
                // Restore last selection after tasks are loaded
                restoreLastSelection()
            }
        }
    }
    
    private func restoreLastSelection() {
        // Restore last selected list from UserDefaults
        guard let savedListId = UserDefaults.standard.string(forKey: lastSelectedListIdKey),
              let savedAccountKindRaw = UserDefaults.standard.string(forKey: lastSelectedAccountKindKey),
              let savedAccountKind = GoogleAuthManager.AccountKind(rawValue: savedAccountKindRaw) else {
            return
        }
        
        // Verify the list still exists in the loaded data
        let lists = savedAccountKind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        if lists.contains(where: { $0.id == savedListId }) {
            selectedListId = savedListId
            selectedAccountKind = savedAccountKind
            
            // Show detail view if on iPhone portrait
            if shouldUseStackedLayout {
                showingDetailView = true
            }
            
            // Collapse the other account's lists when showing the last selected list
            // This will be handled by passing the account kind to AllTaskListsColumn
        }
    }
    
    private func saveLastSelection(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        UserDefaults.standard.set(listId, forKey: lastSelectedListIdKey)
        UserDefaults.standard.set(accountKind.rawValue, forKey: lastSelectedAccountKindKey)
    }
    
    private func clearLastSelection() {
        UserDefaults.standard.removeObject(forKey: lastSelectedListIdKey)
        UserDefaults.standard.removeObject(forKey: lastSelectedAccountKindKey)
    }
    
    private func getInitialExpandedAccount() -> GoogleAuthManager.AccountKind? {
        // Check if there's a last selected list
        guard let savedListId = UserDefaults.standard.string(forKey: lastSelectedListIdKey),
              let savedAccountKindRaw = UserDefaults.standard.string(forKey: lastSelectedAccountKindKey),
              let savedAccountKind = GoogleAuthManager.AccountKind(rawValue: savedAccountKindRaw) else {
            return nil // No last selection, both sections will be expanded
        }
        
        // Verify the list still exists in the loaded data
        let lists = savedAccountKind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        if lists.contains(where: { $0.id == savedListId }) {
            return savedAccountKind // Return the account kind of the last selected list
        }
        
        return nil // List doesn't exist anymore, both sections will be expanded
    }
}

// MARK: - All Task Lists Column (Left Side)
struct AllTaskListsColumn: View {
    let personalLists: [GoogleTaskList]
    let professionalLists: [GoogleTaskList]
    let personalColor: Color
    let professionalColor: Color
    @Binding var selectedListId: String?
    @Binding var selectedAccountKind: GoogleAuthManager.AccountKind?
    let hasPersonal: Bool
    let hasProfessional: Bool
    let onSelectionChanged: (String, GoogleAuthManager.AccountKind) -> Void
    let initialExpandedAccount: GoogleAuthManager.AccountKind?
    
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // State for creating new list
    @State private var showingNewListSheet = false
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?
    @State private var newListName = ""
    
    // State for collapsing/expanding sections
    @State private var isPersonalExpanded: Bool
    @State private var isProfessionalExpanded: Bool
    
    init(personalLists: [GoogleTaskList], 
         professionalLists: [GoogleTaskList], 
         personalColor: Color, 
         professionalColor: Color, 
         selectedListId: Binding<String?>, 
         selectedAccountKind: Binding<GoogleAuthManager.AccountKind?>, 
         hasPersonal: Bool, 
         hasProfessional: Bool, 
         onSelectionChanged: @escaping (String, GoogleAuthManager.AccountKind) -> Void,
         initialExpandedAccount: GoogleAuthManager.AccountKind?) {
        self.personalLists = personalLists
        self.professionalLists = professionalLists
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self._selectedListId = selectedListId
        self._selectedAccountKind = selectedAccountKind
        self.hasPersonal = hasPersonal
        self.hasProfessional = hasProfessional
        self.onSelectionChanged = onSelectionChanged
        self.initialExpandedAccount = initialExpandedAccount
        
        // Set initial expansion state based on the last selected account
        if let expandedAccount = initialExpandedAccount {
            self._isPersonalExpanded = State(initialValue: expandedAccount == .personal)
            self._isProfessionalExpanded = State(initialValue: expandedAccount == .professional)
        } else {
            // No last selection, both sections expanded by default
            self._isPersonalExpanded = State(initialValue: true)
            self._isProfessionalExpanded = State(initialValue: true)
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // All Lists
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Personal Lists Section
                    if hasPersonal {
                        // Personal Header
                        Button(action: {
                            isPersonalExpanded.toggle()
                        }) {
                            HStack {
                                Text("Personal")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(personalColor)
                                Spacer()
                                Text("\(personalLists.count) \(personalLists.count == 1 ? "List" : "Lists")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: isPersonalExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, adaptivePadding)
                            .padding(.vertical, 8)
                            .background(personalColor.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Personal Lists
                        if isPersonalExpanded {
                            ForEach(personalLists) { taskList in
                                let personalCounts = taskCounts(for: taskList.id, kind: .personal)
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: personalColor,
                                    incompleteCount: personalCounts.incomplete,
                                    totalCount: personalCounts.total,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .personal,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .personal
                                        onSelectionChanged(taskList.id, .personal)
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                    
                    // Professional Lists Section
                    if hasProfessional {
                        // Professional Header
                        Button(action: {
                            isProfessionalExpanded.toggle()
                        }) {
                            HStack {
                                Text("Professional")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(professionalColor)
                                Spacer()
                                Text("\(professionalLists.count) \(professionalLists.count == 1 ? "List" : "Lists")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: isProfessionalExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, adaptivePadding)
                            .padding(.vertical, 8)
                            .background(professionalColor.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Professional Lists
                        if isProfessionalExpanded {
                            ForEach(professionalLists) { taskList in
                                let professionalCounts = taskCounts(for: taskList.id, kind: .professional)
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: professionalColor,
                                    incompleteCount: professionalCounts.incomplete,
                                    totalCount: professionalCounts.total,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .professional,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .professional
                                        onSelectionChanged(taskList.id, .professional)
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewListSheet) {
            NewListSheet(
                accountKind: newListAccountKind,
                hasPersonal: hasPersonal,
                hasProfessional: hasProfessional,
                personalColor: personalColor,
                professionalColor: professionalColor,
                listName: $newListName,
                selectedAccount: $newListAccountKind,
                onCreate: {
                    createNewList()
                }
            )
        }
    }
    
    private func taskCounts(for listId: String, kind: GoogleAuthManager.AccountKind) -> (incomplete: Int, total: Int) {
        let tasks: [GoogleTask]
        switch kind {
        case .personal:
            tasks = tasksVM.personalTasks[listId] ?? []
        case .professional:
            tasks = tasksVM.professionalTasks[listId] ?? []
        }
        let total = tasks.count
        let incomplete = tasks.filter { !$0.isCompleted }.count
        return (incomplete, total)
    }

    private func createNewList() {
        // Determine which account to use
        let accountToUse: GoogleAuthManager.AccountKind?
        if hasPersonal && hasProfessional {
            // Use the selected account from the sheet
            accountToUse = newListAccountKind
        } else if hasPersonal {
            accountToUse = .personal
        } else if hasProfessional {
            accountToUse = .professional
        } else {
            accountToUse = nil
        }
        
        guard let accountKind = accountToUse,
              !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            await tasksVM.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
            await MainActor.run {
                showingNewListSheet = false
                newListName = ""
            }
        }
    }
}

// MARK: - Tasks Detail Column (Right Side)
struct TasksDetailColumn: View {
    let selectedListId: String?
    let selectedAccountKind: GoogleAuthManager.AccountKind?
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var appPrefs: AppPreferences
    @State private var selectedTask: GoogleTask?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // State for renaming list
    @State private var showingRenameSheet = false
    @State private var renameText = ""
    
    // State for deleting list
    @State private var showingDeleteConfirmation = false
    
    // State for deleting completed tasks
    @State private var showingDeleteCompletedConfirmation = false
    
    // State for inline task creation
    @State private var isCreatingNewTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFieldFocused: Bool

    // State for bulk edit mode
    @State private var isBulkEditMode = false
    @State private var selectedTaskIds = Set<String>()

    // Callback to clear selection when list is deleted
    var onListDeleted: () -> Void = {}
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    private var rawTasks: [GoogleTask] {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else {
            return []
        }
        
        switch accountKind {
        case .personal:
            return tasksVM.personalTasks[listId] ?? []
        case .professional:
            return tasksVM.professionalTasks[listId] ?? []
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
        
        // Filter out completed tasks if hideCompletedTasks is enabled
        let filtered = appPrefs.hideCompletedTasks ? allTasks.filter { !$0.isCompleted } : allTasks
        
        // Sort by: 1) completion status, 2) due date, 3) alphabetically
        let sorted = filtered.sorted { (a, b) in
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
    
    var selectedListTitle: String? {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else {
            return nil
        }
        
        let lists: [GoogleTaskList]
        switch accountKind {
        case .personal:
            lists = tasksVM.personalTaskLists
        case .professional:
            lists = tasksVM.professionalTaskLists
        }
        
        return lists.first { $0.id == listId }?.title
    }
    
    var accentColor: Color {
        guard let accountKind = selectedAccountKind else {
            return .gray
        }
        return accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let listTitle = selectedListTitle {
                // Header with selected list name
                HStack {
                    Button {
                        renameText = listTitle
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
                        Button {
                            isBulkEditMode.toggle()
                            if !isBulkEditMode {
                                // Exit bulk edit mode - clear selections
                                selectedTaskIds.removeAll()
                            }
                        } label: {
                            Label(isBulkEditMode ? "Cancel Bulk Edit" : "Bulk Edit", systemImage: "checklist")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteCompletedConfirmation = true
                        } label: {
                            Label("Delete Completed Tasks", systemImage: "checkmark.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
                        // Bulk Edit Menu (shown when tasks are selected)
                        if isBulkEditMode && !selectedTaskIds.isEmpty {
                            VStack(spacing: 0) {
                                HStack(spacing: 20) {
                                    Text("\(selectedTaskIds.count) selected")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    // Mark as Complete button
                                    Button {
                                        // TODO: Implement mark as complete
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.title3)
                                            Text("Complete")
                                                .font(.caption)
                                        }
                                        .foregroundColor(accentColor)
                                    }
                                    .buttonStyle(.plain)

                                    // Update Due Date button
                                    Button {
                                        // TODO: Implement update due date
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "calendar")
                                                .font(.title3)
                                            Text("Due Date")
                                                .font(.caption)
                                        }
                                        .foregroundColor(accentColor)
                                    }
                                    .buttonStyle(.plain)

                                    // Move button
                                    Button {
                                        // TODO: Implement move
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "arrow.right.square")
                                                .font(.title3)
                                            Text("Move")
                                                .font(.caption)
                                        }
                                        .foregroundColor(accentColor)
                                    }
                                    .buttonStyle(.plain)

                                    // Delete button
                                    Button {
                                        // TODO: Implement delete
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "trash")
                                                .font(.title3)
                                            Text("Delete")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(adaptivePadding)
                                .background(accentColor.opacity(0.15))

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
                                    isBulkEditMode: isBulkEditMode,
                                    isSelected: selectedTaskIds.contains(task.id),
                                    onToggle: {
                                        toggleTask(task)
                                    },
                                    onTap: {
                                        selectedTask = task
                                    },
                                    onSelectionToggle: {
                                        if selectedTaskIds.contains(task.id) {
                                            selectedTaskIds.remove(task.id)
                                        } else {
                                            selectedTaskIds.insert(task.id)
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
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
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
                    listName: listTitle,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    newName: $renameText,
                    onRename: {
                        renameList(listId: listId, accountKind: accountKind)
                    }
                )
            }
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
        .onChange(of: selectedListId) { _ in
            // Reset inline task creation when list changes
            isCreatingNewTask = false
            newTaskTitle = ""
            isNewTaskFieldFocused = false
        }
    }
    
    private func renameList(listId: String, accountKind: GoogleAuthManager.AccountKind) {
        guard !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            await tasksVM.renameTaskList(listId: listId, newTitle: renameText.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
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
        let currentDate = Date() // Current date as due date
        
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

// MARK: - Simple Task Row (Interactive)
struct SimpleTaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    let isBulkEditMode: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    let onSelectionToggle: () -> Void
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }

    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 10 : 12
    }

    var body: some View {
        HStack(spacing: adaptiveSpacing) {
            // Checkbox or Selection box
            if isBulkEditMode && !task.isCompleted {
                // Square selection checkbox for incomplete tasks in bulk edit mode
                Button(action: onSelectionToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundColor(isSelected ? accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                // Regular circular checkbox - tappable to toggle completion
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2) // Slightly larger for better tap target
                        .foregroundColor(task.isCompleted ? accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Task details - tappable to open edit sheet
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.isCompleted)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                    
                    Spacer()
                    
                    if let dueDateTag = dueDateTag(for: task) {
                        Text(dueDateTag.text)
                            .font(.caption)
                            .foregroundColor(dueDateTag.textColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(dueDateTag.backgroundColor)
                            )
                    }
                }
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            Spacer()
        }
        .padding(adaptivePadding)
        .background(Color(.systemBackground))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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
            
            // Show all due dates in Lists view
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

// MARK: - Task List Row
struct TaskListRow: View {
    let taskList: GoogleTaskList
    let accentColor: Color
    var incompleteCount: Int = 0
    var totalCount: Int = 0
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }
    
    private var incompleteTaskCountLabel: String {
        "\(incompleteCount) | \(totalCount)"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // List title
                Text(taskList.title)
                    .font(.body) // Slightly larger for better readability
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? accentColor : .primary)
                
                Spacer()
                
                // Task count
                Text(incompleteTaskCountLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray5))
                    )
                
                // Chevron
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(accentColor)
                }
            }
            .padding(adaptivePadding)
            .background(isSelected ? accentColor.opacity(0.15) : Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New List Sheet
struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountKind: GoogleAuthManager.AccountKind?
    let hasPersonal: Bool
    let hasProfessional: Bool
    let personalColor: Color
    let professionalColor: Color
    @Binding var listName: String
    @Binding var selectedAccount: GoogleAuthManager.AccountKind?
    let onCreate: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    private var showAccountPicker: Bool {
        // Always show picker if both accounts are available
        return hasPersonal && hasProfessional
    }
    
    private var accentColor: Color {
        if let account = selectedAccount ?? accountKind {
            return account == .personal ? personalColor : professionalColor
        }
        return .accentColor
    }
    
    private var canCreate: Bool {
        !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!showAccountPicker || selectedAccount != nil)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Information Section (moved to top)
                Section("Basic Information") {
                    TextField("Add list name", text: $listName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               (selectedAccount != nil || accountKind != nil) {
                                onCreate()
                            }
                        }
                }
                
                // Account Section (moved below, matching event popup style)
                if showAccountPicker {
                    Section("Account") {
                        HStack(spacing: 12) {
                            if hasPersonal {
                                Button(action: {
                                    selectedAccount = .personal
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text("Personal")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccount == .personal ? personalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccount == .personal ? personalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccount == .personal ? personalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if hasProfessional {
                                Button(action: {
                                    selectedAccount = .professional
                                }) {
                                    HStack {
                                        Image(systemName: "briefcase.circle.fill")
                                        Text("Professional")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccount == .professional ? professionalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccount == .professional ? professionalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccount == .professional ? professionalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Task List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                    }
                    .disabled(!canCreate)
                    .fontWeight(.semibold)
                    .foregroundColor(canCreate ? accentColor : .secondary)
                    .opacity(canCreate ? 1.0 : 0.5)
                }
            }
            .onAppear {
                // Always set default account to Personal if not already set
                if selectedAccount == nil {
                    selectedAccount = .personal
                }
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Rename List Sheet
struct RenameListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let listName: String
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    @Binding var newName: String
    let onRename: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    private var hasChanges: Bool {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedNewName.isEmpty && trimmedNewName != listName
    }
    
    private var canSave: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasChanges
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    HStack {
                        Image(systemName: accountKind == .personal ? "person.circle.fill" : "briefcase.circle.fill")
                            .foregroundColor(accentColor)
                        Text(accountKind == .personal ? "Personal" : "Professional")
                            .foregroundColor(accentColor)
                            .fontWeight(.medium)
                    }
                }
                
                Section("List Name") {
                    TextField("Enter new name", text: $newName)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if canSave {
                                onRename()
                            }
                        }
                }
            }
            .navigationTitle("Rename List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onRename()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? accentColor : .secondary)
                    .opacity(canSave ? 1.0 : 0.5)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ListsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

