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
                            appPrefs: appPrefs
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Task Lists")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                let totalCount = personalLists.count + professionalLists.count
                Text("\(totalCount) \(totalCount == 1 ? "List" : "Lists")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            
            Divider()
            
            // All Lists
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Personal Lists Section
                    if hasPersonal {
                        // Personal Header
                        HStack {
                            Text("Personal")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(personalColor)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(personalColor.opacity(0.1))
                        
                        // Personal Lists
                        ForEach(personalLists) { taskList in
                            TaskListRow(
                                taskList: taskList,
                                accentColor: personalColor,
                                isSelected: selectedListId == taskList.id && selectedAccountKind == .personal,
                                onTap: {
                                    selectedListId = taskList.id
                                    selectedAccountKind = .personal
                                }
                            )
                            Divider()
                        }
                    }
                    
                    // Professional Lists Section
                    if hasProfessional {
                        // Professional Header
                        HStack {
                            Text("Professional")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(professionalColor)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(professionalColor.opacity(0.1))
                        
                        // Professional Lists
                        ForEach(professionalLists) { taskList in
                            TaskListRow(
                                taskList: taskList,
                                accentColor: professionalColor,
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
}

// MARK: - Tasks Detail Column (Right Side)
struct TasksDetailColumn: View {
    let selectedListId: String?
    let selectedAccountKind: GoogleAuthManager.AccountKind?
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var appPrefs: AppPreferences
    
    var tasks: [GoogleTask] {
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
                    Text(listTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)
                    
                    Spacer()
                    
                    Text("\(tasks.count) \(tasks.count == 1 ? "Task" : "Tasks")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(accentColor.opacity(0.1))
                
                Divider()
                
                // Tasks list
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tasks) { task in
                                SimpleTaskRow(task: task, accentColor: accentColor)
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
    }
}

// MARK: - Simple Task Row (Read-only)
struct SimpleTaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(task.isCompleted ? accentColor : .secondary)
            
            // Task details
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
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
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
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // List title
                Text(taskList.title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? accentColor : .primary)
                
                Spacer()
                
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

// MARK: - Preview
#Preview {
    ListsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

