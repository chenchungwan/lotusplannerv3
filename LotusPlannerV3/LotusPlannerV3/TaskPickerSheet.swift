import SwiftUI

// MARK: - Task Picker Sheet (3-column: Account → List → Tasks)
struct TaskPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    let alreadyLinkedIds: Set<String>
    let onSelect: (GoogleTask, String, GoogleAuthManager.AccountKind) -> Void

    @State private var selectedAccount: GoogleAuthManager.AccountKind? = nil
    @State private var selectedListId: String? = nil
    @State private var selectedTasks: [SelectedTask] = []

    private struct SelectedTask: Identifiable, Equatable {
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind

        var id: String {
            "\(accountKind.rawValue)|\(listId)|\(task.id)"
        }
    }

    private var availableAccounts: [GoogleAuthManager.AccountKind] {
        var accounts: [GoogleAuthManager.AccountKind] = []
        if !tasksVM.account1TaskLists.isEmpty { accounts.append(.account1) }
        if !tasksVM.account2TaskLists.isEmpty { accounts.append(.account2) }
        return accounts
    }

    private var listsForAccount: [GoogleTaskList] {
        guard let account = selectedAccount else { return [] }
        return account == .account1 ? tasksVM.account1TaskLists : tasksVM.account2TaskLists
    }

    private var tasksForList: [GoogleTask] {
        guard let account = selectedAccount, let listId = selectedListId else { return [] }
        let dict = account == .account1 ? tasksVM.account1Tasks : tasksVM.account2Tasks
        return (dict[listId] ?? []).filter { !alreadyLinkedIds.contains($0.id) }
    }

    private var selectedCount: Int {
        selectedTasks.count
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Column 1: Accounts
                VStack(alignment: .leading, spacing: 0) {
                    Text("Account")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(availableAccounts, id: \.self) { account in
                                Button {
                                    selectedAccount = account
                                    selectedListId = nil
                                } label: {
                                    HStack {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                        Text(appPrefs.accountName(for: account))
                                            .font(.callout)
                                        Spacer()
                                        if selectedAccount == account {
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedAccount == account ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .frame(minWidth: 120, maxWidth: 140)
                .background(Color(.systemGray6))

                Divider()

                // Column 2: Lists
                VStack(alignment: .leading, spacing: 0) {
                    Text("List")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if selectedAccount == nil {
                        Spacer()
                        Text("Select an account")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(listsForAccount) { list in
                                    Button {
                                        selectedListId = list.id
                                    } label: {
                                        HStack {
                                            Text(list.title)
                                                .font(.callout)
                                                .lineLimit(1)
                                            Spacer()
                                            if selectedListId == list.id {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(selectedListId == list.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(minWidth: 140, maxWidth: 180)
                .background(Color(.systemGray6).opacity(0.5))

                Divider()

                // Column 3: Tasks
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tasks")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if selectedListId == nil {
                        Spacer()
                        Text("Select a list")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if tasksForList.isEmpty {
                        Spacer()
                        Text("No tasks available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(tasksForList) { task in
                                    Button {
                                        toggleSelection(task)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: isSelected(task) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isSelected(task) ? .accentColor : .secondary)
                                                .font(.title3)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.title)
                                                    .font(.callout)
                                                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                                                    .strikethrough(task.isCompleted)
                                                    .lineLimit(2)
                                                if let due = task.due {
                                                    Text(String(due.prefix(10)))
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Link Existing Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if selectedCount > 0 {
                        Text("\(selectedCount) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        for selection in selectedTasks {
                            onSelect(selection.task, selection.listId, selection.accountKind)
                        }
                        dismiss()
                    }
                    .disabled(selectedTasks.isEmpty)
                }
            }
        }
        .onAppear {
            // Auto-select first account
            if let first = availableAccounts.first {
                selectedAccount = first
            }
        }
    }

    private func isSelected(_ task: GoogleTask) -> Bool {
        guard let selectedAccount, let selectedListId else { return false }
        let id = "\(selectedAccount.rawValue)|\(selectedListId)|\(task.id)"
        return selectedTasks.contains { $0.id == id }
    }

    private func toggleSelection(_ task: GoogleTask) {
        guard let selectedAccount, let selectedListId else { return }
        let selection = SelectedTask(task: task, listId: selectedListId, accountKind: selectedAccount)
        if let index = selectedTasks.firstIndex(where: { $0.id == selection.id }) {
            selectedTasks.remove(at: index)
        } else {
            selectedTasks.append(selection)
        }
    }
}
