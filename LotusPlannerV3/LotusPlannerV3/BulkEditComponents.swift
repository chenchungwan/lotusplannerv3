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

    @State private var selectedDate = Date()
    @State private var isAllDay = true
    @State private var startTime = Date()
    @State private var endTime: Date

    init(selectedTaskIds: Set<String>, onSave: @escaping (Date?, Bool, Date?, Date?) -> Void) {
        self.selectedTaskIds = selectedTaskIds
        self.onSave = onSave

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
                Section {
                    DatePicker("Due Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section {
                    Toggle("All-Day", isOn: $isAllDay)

                    if !isAllDay {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
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
                        let finalDate: Date
                        var finalStartTime: Date?
                        var finalEndTime: Date?

                        if isAllDay {
                            // Use just the date for all-day events
                            finalDate = selectedDate
                        } else {
                            // Combine date with start time for the due date
                            let calendar = Calendar.current
                            let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                            var combined = DateComponents()
                            combined.year = dateComponents.year
                            combined.month = dateComponents.month
                            combined.day = dateComponents.day
                            combined.hour = timeComponents.hour
                            combined.minute = timeComponents.minute
                            finalDate = calendar.date(from: combined) ?? selectedDate

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
                        onSave(finalDate, isAllDay, finalStartTime, finalEndTime)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
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
