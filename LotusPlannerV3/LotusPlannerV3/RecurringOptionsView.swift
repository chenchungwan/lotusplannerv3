import SwiftUI

struct RecurringOptionsView: View {
    @Binding var frequency: RecurringFrequency
    @Binding var interval: Int
    @Binding var startDate: Date
    @Binding var endDate: Date?
    @Binding var hasEndDate: Bool
    @Binding var customDays: [Int]
    @Binding var customDayOfMonth: Int
    @Binding var customMonthOfYear: Int
    
    let accentColor: Color
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var showingStartDatePicker = false
    @State private var showingEndDatePicker = false
    
    private let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Frequency") {
                    Picker("Repeat", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                            HStack {
                                Image(systemName: freq.icon)
                                Text(freq.displayName)
                            }
                            .tag(freq)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if frequency != .custom {
                        HStack {
                            Text("Every")
                            Spacer()
                            Picker("Interval", selection: $interval) {
                                ForEach(1...30, id: \.self) { number in
                                    Text("\(number)")
                                        .tag(number)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 80)
                            
                            Text(frequency == .daily ? (interval == 1 ? "day" : "days") :
                                frequency == .weekly ? (interval == 1 ? "week" : "weeks") :
                                frequency == .monthly ? (interval == 1 ? "month" : "months") :
                                frequency == .yearly ? (interval == 1 ? "year" : "years") : "")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Custom options based on frequency
                if frequency == .weekly || frequency == .custom {
                    Section("Days of Week") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                HStack {
                                    Button(action: {
                                        toggleWeekday(dayIndex)
                                    }) {
                                        HStack {
                                            Image(systemName: customDays.contains(dayIndex) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(customDays.contains(dayIndex) ? accentColor : .secondary)
                                            Text(weekdayNames[dayIndex])
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                
                if frequency == .monthly || frequency == .yearly {
                    Section("Day of Month") {
                        Picker("Day", selection: $customDayOfMonth) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)")
                                    .tag(day)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                if frequency == .yearly {
                    Section("Month") {
                        Picker("Month", selection: $customMonthOfYear) {
                            ForEach(1...12, id: \.self) { month in
                                Text(monthNames[month - 1])
                                    .tag(month)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Start Date") {
                    HStack {
                        Text("Start Date")
                        Spacer()
                        Text(startDate, style: .date)
                            .foregroundColor(.secondary)
                        Button(action: {
                            showingStartDatePicker = true
                        }) {
                            Image(systemName: "calendar")
                                .foregroundColor(accentColor)
                        }
                    }
                }
                
                Section("End Date") {
                    HStack {
                        Text("End Date")
                        Spacer()
                        
                        Toggle("Set End Date", isOn: $hasEndDate)
                            .toggleStyle(SwitchToggleStyle(tint: accentColor))
                    }
                    
                    if hasEndDate {
                        HStack {
                            Text("Date")
                            Spacer()
                            Text(endDate ?? Date(), style: .date)
                                .foregroundColor(.secondary)
                            Button(action: {
                                showingEndDatePicker = true
                            }) {
                                Image(systemName: "calendar")
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                }
                
                Section("Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generateSummary())
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if hasEndDate, let endDate = endDate {
                            Text("Until \(endDate, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Repeat Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValidConfiguration())
                }
            }
        }
        .sheet(isPresented: $showingStartDatePicker) {
            NavigationStack {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .navigationTitle("Start Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingStartDatePicker = false
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingStartDatePicker = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEndDatePicker) {
            NavigationStack {
                DatePicker("End Date", selection: Binding(
                    get: { endDate ?? Date() },
                    set: { endDate = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .navigationTitle("End Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingEndDatePicker = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingEndDatePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private func toggleWeekday(_ dayIndex: Int) {
        if customDays.contains(dayIndex) {
            customDays.removeAll { $0 == dayIndex }
        } else {
            customDays.append(dayIndex)
        }
        customDays.sort()
    }
    
    private func isValidConfiguration() -> Bool {
        switch frequency {
        case .weekly, .custom:
            return !customDays.isEmpty
        case .monthly, .yearly:
            return customDayOfMonth >= 1 && customDayOfMonth <= 31
        default:
            return true
        }
    }
    
    private func generateSummary() -> String {
        let intervalText = interval > 1 ? "every \(interval) " : ""
        
        switch frequency {
        case .daily:
            return "Repeats \(intervalText)\(interval == 1 ? "day" : "days")"
            
        case .weekly:
            if customDays.isEmpty {
                return "Repeats \(intervalText)\(interval == 1 ? "week" : "weeks")"
            } else {
                let dayNames = customDays.map { weekdayNames[$0] }
                return "Repeats \(intervalText)\(interval == 1 ? "week" : "weeks") on \(dayNames.joined(separator: ", "))"
            }
            
        case .monthly:
            return "Repeats \(intervalText)\(interval == 1 ? "month" : "months") on day \(customDayOfMonth)"
            
        case .yearly:
            return "Repeats \(intervalText)\(interval == 1 ? "year" : "years") on \(monthNames[customMonthOfYear - 1]) \(customDayOfMonth)"
            
        case .custom:
            if !customDays.isEmpty {
                let dayNames = customDays.map { weekdayNames[$0] }
                return "Repeats weekly on \(dayNames.joined(separator: ", "))"
            } else {
                return "Custom pattern"
            }
        }
    }
}

// MARK: - Preview
struct RecurringOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        RecurringOptionsView(
            frequency: .constant(.daily),
            interval: .constant(1),
            startDate: .constant(Date()),
            endDate: .constant(nil),
            hasEndDate: .constant(false),
            customDays: .constant([]),
            customDayOfMonth: .constant(1),
            customMonthOfYear: .constant(1),
            accentColor: .blue,
            onSave: {},
            onCancel: {}
        )
    }
}
