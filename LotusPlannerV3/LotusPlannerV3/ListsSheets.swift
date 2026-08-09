import SwiftUI

// MARK: - New List Sheet
struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appPrefs: AppPreferences
    let accountKind: GoogleAuthManager.AccountKind?
    let hasAccount1: Bool
    let hasAccount2: Bool
    let account1Color: Color
    let account2Color: Color
    @Binding var listName: String
    @Binding var selectedAccount: GoogleAuthManager.AccountKind?
    let onCreate: () -> Void
    /// True when hosted inside `CreateItemSheet`, which owns the
    /// NavigationStack so the tab strip can sit above the form.
    var isEmbedded: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    
    private var showAccountPicker: Bool {
        // Always show picker if both accounts are available
        return hasAccount1 && hasAccount2
    }
    
    private var accentColor: Color {
        if let account = selectedAccount ?? accountKind {
            return account == .account1 ? account1Color : account2Color
        }
        return .accentColor
    }
    
    private var canCreate: Bool {
        !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!showAccountPicker || selectedAccount != nil)
    }
    
    var body: some View {
        if isEmbedded {
            formContent
        } else {
            NavigationStack {
                formContent
            }
        }
    }

    /// The form plus its navigation chrome (title, Cancel/Create). Split out
    /// of `body` so `CreateItemSheet` can host it inside its own
    /// NavigationStack — the toolbar items surface in that stack's bar.
    @ViewBuilder
    private var formContent: some View {
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
                            if hasAccount1 {
                                Button(action: {
                                    selectedAccount = .account1
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text(appPrefs.account1Name)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccount == .account1 ? account1Color.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccount == .account1 ? account1Color : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccount == .account1 ? account1Color : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if hasAccount2 {
                                Button(action: {
                                    selectedAccount = .account2
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text(appPrefs.account2Name)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccount == .account2 ? account2Color.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccount == .account2 ? account2Color : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccount == .account2 ? account2Color : Color.clear, lineWidth: 2)
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
                // Always set default account to Account 1 if not already set
                if selectedAccount == nil {
                    selectedAccount = .account1
                }
                isTextFieldFocused = true
            }
    }
}

// MARK: - Edit List Sheet
struct RenameListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appPrefs: AppPreferences
    let listName: String
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let hasAccount1: Bool
    let hasAccount2: Bool
    @Binding var newName: String
    @Binding var newAccount: GoogleAuthManager.AccountKind
    /// Called with the (possibly trimmed) new name and selected account.
    /// The caller decides whether the change is name-only or also includes
    /// an account move; the move-confirmation alert is presented here so
    /// the user must explicitly approve before the save fires.
    let onSave: () -> Void
    /// Called when the user wants to delete completed tasks for this list.
    /// The sheet dismisses; the caller surfaces its own confirmation alert.
    let onDeleteCompletedTasks: () -> Void
    /// Called when the user wants to delete the entire list. The sheet
    /// dismisses; the caller surfaces its own confirmation alert.
    let onDeleteList: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingMoveConfirmation = false

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canBothAccounts: Bool {
        hasAccount1 && hasAccount2
    }

    private var nameChanged: Bool {
        !trimmedNewName.isEmpty && trimmedNewName != listName
    }

    private var accountChanged: Bool {
        newAccount != accountKind
    }

    private var canSave: Bool {
        !trimmedNewName.isEmpty && (nameChanged || accountChanged)
    }

    private var newAccentColor: Color {
        newAccount == .account1 ? appPrefs.account1Color : appPrefs.account2Color
    }

    private func attemptSave() {
        guard canSave else { return }
        if accountChanged {
            showingMoveConfirmation = true
        } else {
            onSave()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if canBothAccounts {
                        Picker("Account", selection: $newAccount) {
                            ForEach([GoogleAuthManager.AccountKind.account1, .account2], id: \.self) { kind in
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                    Text(appPrefs.accountName(for: kind))
                                }
                                .tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(accentColor)
                            Text(appPrefs.accountName(for: accountKind))
                                .foregroundColor(accentColor)
                                .fontWeight(.medium)
                        }
                    }
                }

                Section("List Name") {
                    TextField("Enter new name", text: $newName)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            attemptSave()
                        }
                }

                Section("Danger Zone") {
                    Button(role: .destructive) {
                        onDeleteCompletedTasks()
                        dismiss()
                    } label: {
                        Label("Delete Completed Tasks", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        onDeleteList()
                        dismiss()
                    } label: {
                        Label("Delete List", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        attemptSave()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? newAccentColor : .secondary)
                    .opacity(canSave ? 1.0 : 0.5)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
            .alert("Move list to \(appPrefs.accountName(for: newAccount))?", isPresented: $showingMoveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Move", role: .destructive) {
                    onSave()
                }
            } message: {
                Text("This will move all tasks in “\(trimmedNewName)” from \(appPrefs.accountName(for: accountKind)) to \(appPrefs.accountName(for: newAccount)).")
            }
        }
    }
}

// MARK: - Move Tasks Destination Picker
struct MoveTasksDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appPrefs: AppPreferences
    @ObservedObject var tasksVM: TasksViewModel
    let sourceListId: String
    let sourceAccountKind: GoogleAuthManager.AccountKind
    let selectedTaskIds: Set<String>
    let account1Color: Color
    let account2Color: Color
    let hasAccount1: Bool
    let hasAccount2: Bool
    let onMove: (String, GoogleAuthManager.AccountKind) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Account 1 Lists
                if hasAccount1 && !tasksVM.account1TaskLists.isEmpty {
                    Section {
                        ForEach(tasksVM.account1TaskLists) { list in
                            // Don't show the source list
                            if !(list.id == sourceListId && sourceAccountKind == .account1) {
                                Button {
                                    onMove(list.id, .account1)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .foregroundColor(account1Color)
                                        Text(list.title)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(account1Color)
                            Text(appPrefs.account1Name)
                        }
                    }
                }

                // Account 2 Lists
                if hasAccount2 && !tasksVM.account2TaskLists.isEmpty {
                    Section {
                        ForEach(tasksVM.account2TaskLists) { list in
                            // Don't show the source list
                            if !(list.id == sourceListId && sourceAccountKind == .account2) {
                                Button {
                                    onMove(list.id, .account2)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .foregroundColor(account2Color)
                                        Text(list.title)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(account2Color)
                            Text(appPrefs.account2Name)
                        }
                    }
                }
            }
            .navigationTitle("Move \(selectedTaskIds.count) Task\(selectedTaskIds.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
