import SwiftUI

struct AddLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss
    
    private func getFirstAvailableLogType() -> LogType {
        if appPrefs.showFoodLogs { return .food }
        if appPrefs.showSleepLogs { return .sleep }
        if appPrefs.showWaterLogs { return .water }
        if appPrefs.showWeightLogs { return .weight }
        if appPrefs.showWorkoutLogs { return .workout }
        return .food // Fallback, though this case shouldn't happen as the + button should be hidden
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
                            case .food where appPrefs.showFoodLogs:
                                viewModel.selectedLogType = .food
                            case .sleep where appPrefs.showSleepLogs:
                                viewModel.selectedLogType = .sleep
                            case .water where appPrefs.showWaterLogs:
                                viewModel.selectedLogType = .water
                            case .weight where appPrefs.showWeightLogs:
                                viewModel.selectedLogType = .weight
                            case .workout where appPrefs.showWorkoutLogs:
                                viewModel.selectedLogType = .workout
                            default:
                                // If trying to select a disabled type, select the first available one
                                viewModel.selectedLogType = getFirstAvailableLogType()
                            }
                        }
                    )) {
                        if appPrefs.showFoodLogs {
                            Label(LogType.food.displayName, systemImage: LogType.food.icon)
                                .tag(LogType.food)
                        }
                        if appPrefs.showSleepLogs {
                            Label(LogType.sleep.displayName, systemImage: LogType.sleep.icon)
                                .tag(LogType.sleep)
                        }
                        if appPrefs.showWaterLogs {
                            Label(LogType.water.displayName, systemImage: LogType.water.icon)
                                .tag(LogType.water)
                        }
                        if appPrefs.showWeightLogs {
                            Label(LogType.weight.displayName, systemImage: LogType.weight.icon)
                                .tag(LogType.weight)
                        }
                        if appPrefs.showWorkoutLogs {
                            Label(LogType.workout.displayName, systemImage: LogType.workout.icon)
                                .tag(LogType.workout)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onAppear {
                        // When view appears, make sure selected type is available
                        switch viewModel.selectedLogType {
                        case .food where !appPrefs.showFoodLogs,
                             .sleep where !appPrefs.showSleepLogs,
                             .water where !appPrefs.showWaterLogs,
                             .weight where !appPrefs.showWeightLogs,
                             .workout where !appPrefs.showWorkoutLogs:
                            viewModel.selectedLogType = getFirstAvailableLogType()
                        default:
                            break
                        }
                    }
                }

                // Form fields based on log type and visibility settings
                if case .food = viewModel.selectedLogType, appPrefs.showFoodLogs {
                    foodForm
                } else if case .sleep = viewModel.selectedLogType, appPrefs.showSleepLogs {
                    sleepForm
                } else if case .water = viewModel.selectedLogType, appPrefs.showWaterLogs {
                    waterForm
                } else if case .weight = viewModel.selectedLogType, appPrefs.showWeightLogs {
                    weightForm
                } else if case .workout = viewModel.selectedLogType, appPrefs.showWorkoutLogs {
                    workoutForm
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
            viewModel.waterDate = currentDateTime
            // Set water cups to current count for today (if exists), otherwise 0
            let todayWaterLogs = viewModel.waterLogs(on: currentDateTime)
            viewModel.waterCupsConsumed = todayWaterLogs.first?.cupsConsumed ?? 0
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
                .environment(\.calendar, Calendar.mondayFirst)
        }
    }

    private var workoutForm: some View {
        Section("Workout Details") {
            Picker("Workout Type", selection: $viewModel.selectedWorkoutType) {
                ForEach(appPrefs.sortedSelectedWorkoutTypes) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            TextField("Description (optional)", text: $viewModel.workoutName)
            DatePicker("Date", selection: $viewModel.workoutDate, displayedComponents: [.date, .hourAndMinute])
                .environment(\.calendar, Calendar.mondayFirst)
        }
    }

    private var foodForm: some View {
        Section("Food Details") {
            TextField("Food name", text: $viewModel.foodName)
            DatePicker("Date", selection: $viewModel.foodDate, displayedComponents: [.date, .hourAndMinute])
                .environment(\.calendar, Calendar.mondayFirst)
        }
    }

    private var waterForm: some View {
        Section("Water Details") {
            Stepper("Cups: \(viewModel.waterCupsConsumed)", value: $viewModel.waterCupsConsumed, in: 0...20)
            DatePicker("Date", selection: $viewModel.waterDate, displayedComponents: [.date])
                .environment(\.calendar, Calendar.mondayFirst)
        }
    }

    private var sleepForm: some View {
        Section("Sleep Details") {
            // Bed Time row
            HStack {
                Text("Bed Time")
                Spacer()
                if viewModel.sleepBedTime != nil {
                    DatePicker("", selection: Binding(
                        get: { viewModel.sleepBedTime ?? defaultBedTime },
                        set: { viewModel.sleepBedTime = $0 }
                    ), displayedComponents: [.date])
                    .labelsHidden()
                    .environment(\.calendar, Calendar.mondayFirst)

                    DatePicker("", selection: Binding(
                        get: { viewModel.sleepBedTime ?? defaultBedTime },
                        set: { viewModel.sleepBedTime = $0 }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()

                    Button(action: { viewModel.sleepBedTime = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set") {
                        viewModel.sleepBedTime = defaultBedTime
                    }
                    .foregroundColor(.accentColor)
                }
            }

            // Wake Time row
            HStack {
                Text("Wake Time")
                Spacer()
                if viewModel.sleepWakeUpTime != nil {
                    DatePicker("", selection: Binding(
                        get: { viewModel.sleepWakeUpTime ?? defaultWakeTime },
                        set: { viewModel.sleepWakeUpTime = $0 }
                    ), displayedComponents: [.date])
                    .labelsHidden()
                    .environment(\.calendar, Calendar.mondayFirst)

                    DatePicker("", selection: Binding(
                        get: { viewModel.sleepWakeUpTime ?? defaultWakeTime },
                        set: { viewModel.sleepWakeUpTime = $0 }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()

                    Button(action: { viewModel.sleepWakeUpTime = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set") {
                        viewModel.sleepWakeUpTime = defaultWakeTime
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
    }

    private var defaultBedTime: Date {
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: viewModel.sleepDate) ?? viewModel.sleepDate
        return calendar.date(bySettingHour: 23, minute: 0, second: 0, of: dayBefore) ?? Date()
    }

    private var defaultWakeTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: viewModel.sleepDate) ?? Date()
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
