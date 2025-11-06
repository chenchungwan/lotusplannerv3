import SwiftUI

struct AddLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss
    
    private func getFirstAvailableLogType() -> LogType {
        if appPrefs.showWeightLogs { return .weight }
        if appPrefs.showWorkoutLogs { return .workout }
        if appPrefs.showFoodLogs { return .food }
        return .weight // Fallback, though this case shouldn't happen as the + button should be hidden
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Log Type") {
                    Picker("Type", selection: Binding(
                        get: { viewModel.selectedLogType },
                        set: { newValue in
                            // Only set if the corresponding log type is enabled
                            switch newValue {
                            case .weight where appPrefs.showWeightLogs:
                                viewModel.selectedLogType = .weight
                            case .workout where appPrefs.showWorkoutLogs:
                                viewModel.selectedLogType = .workout
                            case .food where appPrefs.showFoodLogs:
                                viewModel.selectedLogType = .food
                            default:
                                // If trying to select a disabled type, select the first available one
                                viewModel.selectedLogType = getFirstAvailableLogType()
                            }
                        }
                    )) {
                        if appPrefs.showWeightLogs {
                            Label(LogType.weight.displayName, systemImage: LogType.weight.icon)
                                .tag(LogType.weight)
                        }
                        if appPrefs.showWorkoutLogs {
                            Label(LogType.workout.displayName, systemImage: LogType.workout.icon)
                                .tag(LogType.workout)
                        }
                        if appPrefs.showFoodLogs {
                            Label(LogType.food.displayName, systemImage: LogType.food.icon)
                                .tag(LogType.food)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onAppear {
                        // When view appears, make sure selected type is available
                        switch viewModel.selectedLogType {
                        case .weight where !appPrefs.showWeightLogs,
                             .workout where !appPrefs.showWorkoutLogs,
                             .food where !appPrefs.showFoodLogs:
                            viewModel.selectedLogType = getFirstAvailableLogType()
                        case .water:
                            // Water is tracked via cups, not through add form
                            viewModel.selectedLogType = getFirstAvailableLogType()
                        default:
                            break
                        }
                    }
                }
                
                // Form fields based on log type and visibility settings
                if case .weight = viewModel.selectedLogType, appPrefs.showWeightLogs {
                    weightForm
                } else if case .workout = viewModel.selectedLogType, appPrefs.showWorkoutLogs {
                    workoutForm
                } else if case .food = viewModel.selectedLogType, appPrefs.showFoodLogs {
                    foodForm
                }
            }
            .navigationTitle("Add \(viewModel.selectedLogType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        viewModel.addCurrentLogEntry()
                        dismiss()
                    }
                    .disabled(!viewModel.canAddCurrentLogType)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.canAddCurrentLogType ? viewModel.accentColor : .secondary)
                    .opacity(viewModel.canAddCurrentLogType ? 1.0 : 0.5)
                }
            }
        }
        .onAppear {
            // Always refresh the date and time to current when adding a new log entry
            let currentDateTime = Date()
            viewModel.weightDate = currentDateTime
            viewModel.workoutDate = currentDateTime
            viewModel.foodDate = currentDateTime
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
