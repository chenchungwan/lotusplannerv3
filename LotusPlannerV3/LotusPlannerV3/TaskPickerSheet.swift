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

    private var availableAccounts: [GoogleAuthManager.AccountKind] {
        var accounts: [GoogleAuthManager.AccountKind] = []
        if !tasksVM.personalTaskLists.isEmpty { accounts.append(.personal) }
        if !tasksVM.professionalTaskLists.isEmpty { accounts.append(.professional) }
        return accounts
    }

    private var listsForAccount: [GoogleTaskList] {
        guard let account = selectedAccount else { return [] }
        return account == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
    }

    private var tasksForList: [GoogleTask] {
        guard let account = selectedAccount, let listId = selectedListId else { return [] }
        let dict = account == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        return (dict[listId] ?? []).filter { !alreadyLinkedIds.contains($0.id) }
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
                                        Image(systemName: account == .personal ? "person.fill" : "briefcase.fill")
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
                                        onSelect(task, selectedListId!, selectedAccount!)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(task.isCompleted ? .green : .secondary)
                                                .font(.caption)
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
            }
        }
        .onAppear {
            // Auto-select first account
            if let first = availableAccounts.first {
                selectedAccount = first
            }
        }
    }
}

