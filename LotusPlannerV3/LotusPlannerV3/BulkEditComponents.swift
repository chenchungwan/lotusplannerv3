//
//  BulkEditComponents.swift
//  LotusPlannerV3
//
//  Reusable UI components for bulk edit functionality
//

import SwiftUI

// MARK: - Bulk Update Due Date Picker

struct BulkUpdateDueDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let selectedTaskIds: Set<String>
    let onSave: (Date?, Bool, Date?, Date?) -> Void

    @State private var selectedDate: Date?
    @State private var isAllDay = true
    @State private var startTime = Date()
    @State private var endTime: Date
    @State private var showingDatePicker = false
    @State private var tempSelectedDate = Date()

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(selectedTaskIds: Set<String>, onSave: @escaping (Date?, Bool, Date?, Date?) -> Void) {
        self.selectedTaskIds = selectedTaskIds
        self.onSave = onSave

        // Initialize with today's date
        _selectedDate = State(initialValue: Date())
        _tempSelectedDate = State(initialValue: Date())

        // Initialize times to nearest half hour (consistent with individual task editing)
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0

        // Calculate next half hour
        var nextHour = hour
        var nextMinute: Int

        if minute < 30 {
            // Next half hour is :30 of current hour
            nextMinute = 30
        } else {
            // Next half hour is :00 of next hour
            nextMinute = 0
            nextHour = (hour + 1) % 24
        }

        // Set start time to next half hour
        let roundedStart = calendar.date(bySettingHour: nextHour, minute: nextMinute, second: 0, of: now) ?? now
        _startTime = State(initialValue: roundedStart)

        // Set end time to 30 minutes after start time
        _endTime = State(initialValue: calendar.date(byAdding: .minute, value: 30, to: roundedStart) ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Due Date Section
                Section("Due Date") {
                    if let dueDate = selectedDate {
                        // Show date with calendar icon and trash can
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)

                            Button(action: {
                                tempSelectedDate = dueDate
                                showingDatePicker = true
                            }) {
                                Text(BulkUpdateDueDatePicker.dueDateFormatter.string(from: dueDate))
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Spacer()

                            Button(action: {
                                selectedDate = nil
                                // Reset to all-day when due date is removed
                                isAllDay = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // All-day toggle
                        Toggle("All-day task", isOn: $isAllDay)

                        // Show time pickers only if not all-day
                        if !isAllDay {
                            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                    } else {
                        // No due date set - show button to add one
                        Button(action: {
                            selectedDate = Date()
                            tempSelectedDate = Date()
                        }) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundColor(.blue)
                                Text("Add Due Date")
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Section {
                    Text("This will update the due date for \(selectedTaskIds.count) selected task\(selectedTaskIds.count == 1 ? "" : "s").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Update Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let finalDate: Date?
                        var finalStartTime: Date?
                        var finalEndTime: Date?

                        if let date = selectedDate {
                            if isAllDay {
                                // Use just the date for all-day events
                                finalDate = date
                            } else {
                                // Combine date with start time for the due date
                                let calendar = Calendar.current
                                let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                                let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                                var combined = DateComponents()
                                combined.year = dateComponents.year
                                combined.month = dateComponents.month
                                combined.day = dateComponents.day
                                combined.hour = timeComponents.hour
                                combined.minute = timeComponents.minute
                                finalDate = calendar.date(from: combined) ?? date

                                // Also combine date with start and end times for the time window
                                finalStartTime = calendar.date(from: combined)

                                let endTimeComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                                var endCombined = DateComponents()
                                endCombined.year = dateComponents.year
                                endCombined.month = dateComponents.month
                                endCombined.day = dateComponents.day
                                endCombined.hour = endTimeComponents.hour
                                endCombined.minute = endTimeComponents.minute
                                finalEndTime = calendar.date(from: endCombined)
                            }
                        } else {
                            // No date selected - clear due date
                            finalDate = nil
                        }

                        onSave(finalDate, isAllDay, finalStartTime, finalEndTime)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker("", selection: $tempSelectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Due Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showingDatePicker = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    selectedDate = tempSelectedDate
                                    showingDatePicker = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Undo Toast Component

struct UndoToast: View {
    let action: BulkEditAction
    let count: Int
    let accentColor: Color
    let onUndo: () -> Void
    let onDismiss: () -> Void

    private var message: String {
        let taskWord = count == 1 ? "task" : "tasks"
        switch action {
        case .complete:
            return "\(count) \(taskWord) completed"
        case .delete:
            return "\(count) \(taskWord) deleted"
        case .move:
            return "\(count) \(taskWord) moved"
        case .updateDueDate:
            return "\(count) \(taskWord) updated"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            Button {
                onUndo()
            } label: {
                Text("Undo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Bulk Move Destination Picker

struct BulkMoveDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appPrefs = AppPreferences.shared
    let personalTaskLists: [GoogleTaskList]
    let professionalTaskLists: [GoogleTaskList]
    let onSelect: (GoogleAuthManager.AccountKind, String) -> Void

    var body: some View {
        NavigationView {
            List {
                if !personalTaskLists.isEmpty {
                    Section(appPrefs.personalAccountName) {
                        ForEach(personalTaskLists) { list in
                            Button {
                                onSelect(.personal, list.id)
                                dismiss()
                            } label: {
                                HStack {
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
                }

                if !professionalTaskLists.isEmpty {
                    Section(appPrefs.professionalAccountName) {
                        ForEach(professionalTaskLists) { list in
                            Button {
                                onSelect(.professional, list.id)
                                dismiss()
                            } label: {
                                HStack {
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
                }
            }
            .navigationTitle("Move to List")
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

// MARK: - Bulk Edit Toolbar View

struct BulkEditToolbarView: View {
    @ObservedObject var bulkEditManager: BulkEditManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                // Exit button
                Button {
                    bulkEditManager.state.isActive = false
                    bulkEditManager.state.selectedTaskIds.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                // Selection count
                Text("\(bulkEditManager.state.selectedTaskIds.count) selected")
                    .font(.headline)

                Spacer()

                // Action buttons
                HStack(spacing: 16) {
                    // Complete button
                    Button {
                        bulkEditManager.state.showingCompleteConfirmation = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                            Text("Complete")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
                    .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .green)

                    // Due Date button
                    Button {
                        bulkEditManager.state.showingDueDatePicker = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.title2)
                            Text("Due Date")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
                    .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .blue)

                    // Move button
                    Button {
                        bulkEditManager.state.showingMoveDestinationPicker = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.title2)
                            Text("Move")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
                    .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .orange)

                    // Delete button
                    Button {
                        bulkEditManager.state.showingDeleteConfirmation = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.title2)
                            Text("Delete")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
                    .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .red)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.15))

            Divider()
        }
    }
}
