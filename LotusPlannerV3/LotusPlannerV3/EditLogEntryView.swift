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
                case .water:
                    waterForm
                case .sleep:
                    sleepForm
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
        case .water:
            if let entry = viewModel.waterEntries.first(where: { $0.id == editingEntry.id }) {
                viewModel.deleteWaterEntry(entry)
            }
        case .sleep:
            if let entry = viewModel.sleepEntries.first(where: { $0.id == editingEntry.id }) {
                viewModel.deleteSleepEntry(entry)
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

    private var waterForm: some View {
        Section("Water Details") {
            Stepper("Cups: \(viewModel.waterCupsConsumed)", value: $viewModel.waterCupsConsumed, in: 0...20)
            DatePicker("Date", selection: $viewModel.waterDate, displayedComponents: [.date])
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
