import SwiftUI

struct AddLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss
    
    private func getFirstAvailableLogType() -> LogType {
        if appPrefs.showWeightLogs { return .weight }
        if appPrefs.showWorkoutLogs { return .workout }
        if appPrefs.showFoodLogs { return .food }
        if appPrefs.showSleepLogs { return .sleep }
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
                            case .sleep where appPrefs.showSleepLogs:
                                viewModel.selectedLogType = .sleep
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
                        if appPrefs.showSleepLogs {
                            Label(LogType.sleep.displayName, systemImage: LogType.sleep.icon)
                                .tag(LogType.sleep)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onAppear {
                        // When view appears, make sure selected type is available
                        switch viewModel.selectedLogType {
                        case .weight where !appPrefs.showWeightLogs,
                             .workout where !appPrefs.showWorkoutLogs,
                             .food where !appPrefs.showFoodLogs,
                             .sleep where !appPrefs.showSleepLogs:
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
                } else if case .sleep = viewModel.selectedLogType, appPrefs.showSleepLogs {
                    sleepForm
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
            viewModel.sleepDate = currentDateTime
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

    private var sleepForm: some View {
        Section("Sleep Details") {
            DatePicker("Date", selection: $viewModel.sleepDate, displayedComponents: [.date])

            HStack {
                Text("Bed Time")
                Spacer()
                if let bedTime = viewModel.sleepBedTime {
                    Text(formatDateTime(bedTime))
                        .foregroundColor(.secondary)
                    Button(action: {
                        viewModel.sleepBedTime = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button("Set") {
                        // Set to 11 PM on the day before sleepDate
                        let calendar = Calendar.current
                        let dayBefore = calendar.date(byAdding: .day, value: -1, to: viewModel.sleepDate) ?? viewModel.sleepDate
                        viewModel.sleepBedTime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: dayBefore) ?? Date()
                    }
                }
            }

            if viewModel.sleepBedTime != nil {
                DatePicker("", selection: Binding(
                    get: { viewModel.sleepBedTime ?? Date() },
                    set: { viewModel.sleepBedTime = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            HStack {
                Text("Wake Up Time")
                Spacer()
                if let wakeTime = viewModel.sleepWakeUpTime {
                    Text(formatDateTime(wakeTime))
                        .foregroundColor(.secondary)
                    Button(action: {
                        viewModel.sleepWakeUpTime = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button("Set") {
                        // Set to 7 AM on sleepDate
                        viewModel.sleepWakeUpTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: viewModel.sleepDate) ?? Date()
                    }
                }
            }

            if viewModel.sleepWakeUpTime != nil {
                DatePicker("", selection: Binding(
                    get: { viewModel.sleepWakeUpTime ?? Date() },
                    set: { viewModel.sleepWakeUpTime = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
