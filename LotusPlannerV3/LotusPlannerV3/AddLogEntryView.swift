import SwiftUI

struct AddLogEntryView: View {
    @ObservedObject var viewModel: LogsViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss

    /// True when at least one enabled section has data valid enough to
    /// submit — drives the Create button's enabled state.
    private var hasAnyValidEntry: Bool {
        (appPrefs.showFoodLogs && viewModel.canAddFood) ||
        (appPrefs.showSleepLogs && viewModel.canAddSleep) ||
        (appPrefs.showWaterLogs && viewModel.waterCupsConsumed > 0) ||
        (appPrefs.showWeightLogs && viewModel.canAddWeight) ||
        (appPrefs.showWorkoutLogs && viewModel.canAddWorkout)
    }

    /// Submits every section that has valid data; untouched sections are
    /// silently skipped. Water uses cups > 0 explicitly because
    /// `canAddWater` returns true even at zero cups (legacy behavior from
    /// the old single-type flow).
    private func addAllValidEntries() {
        if appPrefs.showFoodLogs && viewModel.canAddFood {
            viewModel.addFoodEntry()
        }
        if appPrefs.showSleepLogs && viewModel.canAddSleep {
            viewModel.addSleepEntry()
        }
        if appPrefs.showWaterLogs && viewModel.waterCupsConsumed > 0 {
            viewModel.addWaterEntry()
        }
        if appPrefs.showWeightLogs && viewModel.canAddWeight {
            viewModel.addWeightEntry()
        }
        if appPrefs.showWorkoutLogs && viewModel.canAddWorkout {
            viewModel.addWorkoutEntry()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Show every enabled log type at once. The user can fill in
                // any subset; Create submits all valid sections in one tap.
                if appPrefs.showFoodLogs { foodForm }
                if appPrefs.showSleepLogs { sleepForm }
                if appPrefs.showWaterLogs { waterForm }
                if appPrefs.showWeightLogs { weightForm }
                if appPrefs.showWorkoutLogs { workoutForm }
            }
            .navigationTitle("Add Log Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        addAllValidEntries()
                        dismiss()
                    }
                    .disabled(!hasAnyValidEntry)
                    .fontWeight(.semibold)
                    .foregroundColor(hasAnyValidEntry ? viewModel.accentColor : .secondary)
                    .opacity(hasAnyValidEntry ? 1.0 : 0.5)
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
            TextField("Description", text: $viewModel.workoutName)
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
