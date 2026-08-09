import SwiftUI

// MARK: - All Task Lists Column (Left Side)
struct AllTaskListsColumn: View {
    let account1Lists: [GoogleTaskList]
    let account2Lists: [GoogleTaskList]
    let account1Color: Color
    let account2Color: Color
    @Binding var selectedListId: String?
    @Binding var selectedAccountKind: GoogleAuthManager.AccountKind?
    let hasAccount1: Bool
    let hasAccount2: Bool
    let onSelectionChanged: (String, GoogleAuthManager.AccountKind) -> Void
    let initialExpandedAccount: GoogleAuthManager.AccountKind?

    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // State for creating new list
    @State private var showingNewListSheet = false
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?
    @State private var newListName = ""
    
    // State for collapsing/expanding sections
    @State private var isAccount1Expanded: Bool
    @State private var isAccount2Expanded: Bool
    
    init(account1Lists: [GoogleTaskList], 
         account2Lists: [GoogleTaskList], 
         account1Color: Color, 
         account2Color: Color, 
         selectedListId: Binding<String?>, 
         selectedAccountKind: Binding<GoogleAuthManager.AccountKind?>, 
         hasAccount1: Bool, 
         hasAccount2: Bool, 
         onSelectionChanged: @escaping (String, GoogleAuthManager.AccountKind) -> Void,
         initialExpandedAccount: GoogleAuthManager.AccountKind?) {
        self.account1Lists = account1Lists
        self.account2Lists = account2Lists
        self.account1Color = account1Color
        self.account2Color = account2Color
        self._selectedListId = selectedListId
        self._selectedAccountKind = selectedAccountKind
        self.hasAccount1 = hasAccount1
        self.hasAccount2 = hasAccount2
        self.onSelectionChanged = onSelectionChanged
        self.initialExpandedAccount = initialExpandedAccount
        
        // Set initial expansion state based on the last selected account
        if let expandedAccount = initialExpandedAccount {
            self._isAccount1Expanded = State(initialValue: expandedAccount == .account1)
            self._isAccount2Expanded = State(initialValue: expandedAccount == .account2)
        } else {
            // No last selection, both sections expanded by default
            self._isAccount1Expanded = State(initialValue: true)
            self._isAccount2Expanded = State(initialValue: true)
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
                    // Account 1 Lists Section
                    if hasAccount1 {
                        // Account 1 Header
                        Button(action: {
                            isAccount1Expanded.toggle()
                        }) {
                            HStack {
                                Text(appPrefs.account1Name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(account1Color)
                                Spacer()
                                Text("\(account1Lists.count) \(account1Lists.count == 1 ? "List" : "Lists")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: isAccount1Expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, adaptivePadding)
                            .padding(.vertical, 8)
                            .background(account1Color.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Account 1 Lists
                        if isAccount1Expanded {
                            ForEach(account1Lists) { taskList in
                                let account1Counts = taskCounts(for: taskList.id, kind: .account1)
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: account1Color,
                                    incompleteCount: account1Counts.incomplete,
                                    totalCount: account1Counts.total,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .account1,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .account1
                                        onSelectionChanged(taskList.id, .account1)
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                    
                    // Account 2 Lists Section
                    if hasAccount2 {
                        // Account 2 Header
                        Button(action: {
                            isAccount2Expanded.toggle()
                        }) {
                            HStack {
                                Text(appPrefs.account2Name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(account2Color)
                                Spacer()
                                Text("\(account2Lists.count) \(account2Lists.count == 1 ? "List" : "Lists")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: isAccount2Expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, adaptivePadding)
                            .padding(.vertical, 8)
                            .background(account2Color.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        // Account 2 Lists
                        if isAccount2Expanded {
                            ForEach(account2Lists) { taskList in
                                let account2Counts = taskCounts(for: taskList.id, kind: .account2)
                                TaskListRow(
                                    taskList: taskList,
                                    accentColor: account2Color,
                                    incompleteCount: account2Counts.incomplete,
                                    totalCount: account2Counts.total,
                                    isSelected: selectedListId == taskList.id && selectedAccountKind == .account2,
                                    onTap: {
                                        selectedListId = taskList.id
                                        selectedAccountKind = .account2
                                        onSelectionChanged(taskList.id, .account2)
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
                appPrefs: appPrefs,
                accountKind: newListAccountKind,
                hasAccount1: hasAccount1,
                hasAccount2: hasAccount2,
                account1Color: account1Color,
                account2Color: account2Color,
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
        case .account1:
            tasks = tasksVM.account1Tasks[listId] ?? []
        case .account2:
            tasks = tasksVM.account2Tasks[listId] ?? []
        }
        let total = tasks.count
        let incomplete = tasks.filter { !$0.isCompleted }.count
        return (incomplete, total)
    }

    private func createNewList() {
        // Determine which account to use
        let accountToUse: GoogleAuthManager.AccountKind?
        if hasAccount1 && hasAccount2 {
            // Use the selected account from the sheet
            accountToUse = newListAccountKind
        } else if hasAccount1 {
            accountToUse = .account1
        } else if hasAccount2 {
            accountToUse = .account2
        } else {
            accountToUse = nil
        }
        
        guard let accountKind = accountToUse,
              !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            _ = await tasksVM.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
            await MainActor.run {
                showingNewListSheet = false
                newListName = ""
            }
        }
    }
}
