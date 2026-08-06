import SwiftUI

// MARK: - New List Sheet
struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appPrefs: AppPreferences
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
                                        Text(appPrefs.personalAccountName)
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
                                        Text(appPrefs.professionalAccountName)
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

// MARK: - Edit List Sheet
struct RenameListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appPrefs: AppPreferences
    let listName: String
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let hasPersonal: Bool
    let hasProfessional: Bool
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
        hasPersonal && hasProfessional
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
        newAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor
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
                            ForEach([GoogleAuthManager.AccountKind.personal, .professional], id: \.self) { kind in
                                HStack {
                                    Image(systemName: kind == .personal ? "person.circle.fill" : "briefcase.circle.fill")
                                    Text(appPrefs.accountName(for: kind))
                                }
                                .tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        HStack {
                            Image(systemName: accountKind == .personal ? "person.circle.fill" : "briefcase.circle.fill")
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
    let personalColor: Color
    let professionalColor: Color
    let hasPersonal: Bool
    let hasProfessional: Bool
    let onMove: (String, GoogleAuthManager.AccountKind) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Personal Account Lists
                if hasPersonal && !tasksVM.personalTaskLists.isEmpty {
                    Section {
                        ForEach(tasksVM.personalTaskLists) { list in
                            // Don't show the source list
                            if !(list.id == sourceListId && sourceAccountKind == .personal) {
                                Button {
                                    onMove(list.id, .personal)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .foregroundColor(personalColor)
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
                                .foregroundColor(personalColor)
                            Text(appPrefs.personalAccountName)
                        }
                    }
                }

                // Professional Account Lists
                if hasProfessional && !tasksVM.professionalTaskLists.isEmpty {
                    Section {
                        ForEach(tasksVM.professionalTaskLists) { list in
                            // Don't show the source list
                            if !(list.id == sourceListId && sourceAccountKind == .professional) {
                                Button {
                                    onMove(list.id, .professional)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "briefcase.circle.fill")
                                            .foregroundColor(professionalColor)
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
                            Image(systemName: "briefcase.circle.fill")
                                .foregroundColor(professionalColor)
                            Text(appPrefs.professionalAccountName)
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
