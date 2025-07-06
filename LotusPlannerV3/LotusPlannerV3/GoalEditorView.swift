import SwiftUI

struct GoalEditorView: View {
    enum Mode: Equatable {
        case new
        case edit(Goal)
        static func ==(lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.new, .new): return true
            case (.edit(let a), .edit(let b)): return a.id == b.id
            default: return false
            }
        }
    }
    
    let mode: Mode
    let category: GoalCategory
    let onSave: (String, Date?, UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var descriptionText: String
    @State private var dueDate: Date?
    @State private var showingDatePicker = false
    @State private var selectedCategoryId: UUID
    @EnvironmentObject private var viewModel: GoalsViewModel
    
    init(mode: Mode, category: GoalCategory, onSave: @escaping (String, Date?, UUID) -> Void) {
        self.mode = mode
        self.category = category
        self.onSave = onSave
        switch mode {
        case .new:
            _descriptionText = State(initialValue: "")
            _dueDate = State(initialValue: nil)
        case .edit(let goal):
            _descriptionText = State(initialValue: goal.description)
            _dueDate = State(initialValue: goal.dueDate)
        }
        _selectedCategoryId = State(initialValue: category.id)
    }
    
    private var canSave: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        ForEach(viewModel.categories) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Due Date") {
                    HStack {
                        Text(dueDate != nil ? dueDate!.formatted(date: .complete, time: .omitted) : "None")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Choose") { showingDatePicker.toggle() }
                    }
                    if dueDate != nil {
                        Button("Remove Date", role: .destructive) { dueDate = nil }
                    }
                }
            }
            .navigationTitle(mode == .new ? "New Goal" : "Edit Goal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines), dueDate, selectedCategoryId)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Due Date", selection: Binding(get: { dueDate ?? Date() }, set: { dueDate = $0 }), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .navigationTitle("Select Date")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showingDatePicker = false } }
                    }
            }
            .presentationDetents([.medium])
        }
    }
} 