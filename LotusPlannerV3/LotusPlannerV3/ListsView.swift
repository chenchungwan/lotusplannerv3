import SwiftUI

struct ListsView: View {
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @State private var isLoading = false
    @State private var selectedListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Main Content
            GeometryReader { geometry in
                if isLoading {
                    ProgressView("Loading Task Lists...")
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
                    // Master-Detail Layout
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
                            hasProfessional: auth.isLinked(kind: .professional)
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
                            }
                        )
                        .frame(width: geometry.size.width * 0.65)
                    }
                }
            }
        }
        .onAppear {
            loadTaskLists()
        }
    }
    
    private func loadTaskLists() {
        isLoading = true
        Task {
            await tasksVM.loadTasks()
            await MainActor.run {
                isLoading = false
            }
        }
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
    
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    
    // State for creating new list
    @State private var showingNewListSheet = false
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?
    @State private var newListName = ""
    
    // State for collapsing/expanding sections
    @State private var isPersonalExpanded = true
    @State private var isProfessionalExpanded = true
    
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
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(personalColor.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Personal Lists
                        if isPersonalExpanded {
                            ForEach(personalLists) { taskList in
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: personalColor,
                                    taskCount: tasksVM.personalTasks[taskList.id]?.count ?? 0,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .personal,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .personal
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
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(professionalColor.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Professional Lists
                        if isProfessionalExpanded {
                            ForEach(professionalLists) { taskList in
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: professionalColor,
                                    taskCount: tasksVM.professionalTasks[taskList.id]?.count ?? 0,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .professional,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .professional
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
    
    // State for renaming list
    @State private var showingRenameSheet = false
    @State private var renameText = ""
    
    // State for deleting list
    @State private var showingDeleteConfirmation = false
    
    // State for deleting completed tasks
    @State private var showingDeleteCompletedConfirmation = false
    
    // Callback to clear selection when list is deleted
    var onListDeleted: () -> Void = {}
    
    var tasks: [GoogleTask] {
        guard let listId = selectedListId, let accountKind = selectedAccountKind else {
            return []
        }
        
        let allTasks: [GoogleTask]
        switch accountKind {
        case .personal:
            allTasks = tasksVM.personalTasks[listId] ?? []
        case .professional:
            allTasks = tasksVM.professionalTasks[listId] ?? []
        }
        
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
                    
                    Text("\(tasks.count) \(tasks.count == 1 ? "Task" : "Tasks")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Menu {
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
                .padding()
                .background(accentColor.opacity(0.1))
                
                Divider()
                
                // Tasks list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Quick "New Task" row at the top
                        Button {
                            // Create a new task with pre-filled values
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            let todayString = formatter.string(from: Calendar.current.startOfDay(for: Date()))
                            
                            let newTask = GoogleTask(
                                id: UUID().uuidString,
                                title: "",
                                notes: nil,
                                status: "needsAction",
                                due: todayString,
                                completed: nil,
                                updated: nil,
                                position: nil
                            )
                            selectedTask = newTask
                        } label: {
                            HStack(spacing: 12) {
                                // Plus icon
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(accentColor)
                                
                                // Placeholder text
                                Text("New task")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemBackground))
                        }
                        .buttonStyle(.plain)
                        
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
                                Text("This list is empty")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(tasks) { task in
                                SimpleTaskRow(
                                    task: task,
                                    accentColor: accentColor,
                                    onToggle: {
                                        toggleTask(task)
                                    },
                                    onTap: {
                                        selectedTask = task
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
                    onSave: { _ in },
                    onDelete: {
                        Task {
                            await deleteTask(task, from: listId, for: accountKind)
                        }
                    },
                    onMove: { _, _ in },
                    onCrossAccountMove: { _, _, _ in },
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
}

// MARK: - Simple Task Row (Interactive)
struct SimpleTaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    let onToggle: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox - tappable to toggle completion
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            // Task details - tappable to open edit sheet
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(formatDate(dueDate))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Task List Row
struct TaskListRow: View {
    let taskList: GoogleTaskList
    let accentColor: Color
    var taskCount: Int = 0
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // List title
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? accentColor : .primary)
                
                Spacer()
                
                // Task count
                Text("(\(taskCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Chevron
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(accentColor)
                }
            }
            .padding()
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
                    .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                             (showAccountPicker && selectedAccount == nil))
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
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
    let accentColor: Color
    @Binding var newName: String
    let onRename: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("List Name")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter new name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onRename()
                            }
                        }
                }
                .padding()
                
                Spacer()
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
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
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

