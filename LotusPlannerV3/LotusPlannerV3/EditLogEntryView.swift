import SwiftUI

struct EditLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Log Type") {
                    Text(viewModel.selectedLogType.displayName)
                        .foregroundColor(.secondary)
                }
                
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
                    Button("Update") {
                        viewModel.updateCurrentLogEntry()
                        dismiss()
                    }
                    .disabled(!viewModel.canAddCurrentLogType)
                    .foregroundColor(viewModel.accentColor)
                }
            }
        }
    }
    
    private var weightForm: some View {
        Section("Weight Details") {
            HStack {
                TextField("Weight", text: $viewModel.weightValue)
                    .keyboardType(.decimalPad)
                
                Picker("", selection: $viewModel.selectedWeightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(MenuPickerStyle())
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
