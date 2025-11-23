import SwiftUI

struct EditLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Form fields based on log type
                switch viewModel.selectedLogType {
                case .weight:
                    weightForm
                case .workout:
                    workoutForm
                case .food:
                    foodForm
                }
            }
            .navigationTitle("Edit \(viewModel.selectedLogType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.updateCurrentLogEntry()
                        dismiss()
                    }
                    .disabled(!viewModel.canSaveEdit)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.canSaveEdit ? viewModel.accentColor : .secondary)
                    .opacity(viewModel.canSaveEdit ? 1.0 : 0.5)
                }
            }
            // Add Delete section at bottom for editing log entry
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Text("Delete \(viewModel.selectedLogType.displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .alert("Delete \(viewModel.selectedLogType.displayName)", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentEntry()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this \(viewModel.selectedLogType.displayName.lowercased()) entry? This action cannot be undone.")
        }
    }
    
    private func deleteCurrentEntry() {
        guard let editingEntry = viewModel.editingEntry else { return }
        
        switch editingEntry.type {
        case .weight:
            if let entry = viewModel.weightEntries.first(where: { $0.id == editingEntry.id }) {
                viewModel.deleteWeightEntry(entry)
            }
        case .workout:
            if let entry = viewModel.workoutEntries.first(where: { $0.id == editingEntry.id }) {
                viewModel.deleteWorkoutEntry(entry)
            }
        case .food:
            if let entry = viewModel.foodEntries.first(where: { $0.id == editingEntry.id }) {
                viewModel.deleteFoodEntry(entry)
            }
        }
    }
    
    private var weightForm: some View {
        Section("Weight Details") {
            Group {
                HStack {
                    TextField("Weight", text: $viewModel.weightValue)
                        .keyboardType(.decimalPad)
                    
                    Picker("", selection: $viewModel.selectedWeightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
            }
            
            DatePicker("Date", selection: $viewModel.weightDate, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var workoutForm: some View {
        Section("Workout Details") {
            TextField("Workout name", text: $viewModel.workoutName)
            DatePicker("Date", selection: $viewModel.workoutDate, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var foodForm: some View {
        Section("Food Details") {
            TextField("Food name", text: $viewModel.foodName)
            DatePicker("Date", selection: $viewModel.foodDate, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
}
