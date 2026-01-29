//
//  CalendarHelperViews.swift
//  LotusPlannerV3
//
//  Created by refactoring from CalendarView.swift
//

import SwiftUI
import PencilKit

// MARK: - Helper Views

struct WeekPencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 15)
        canvasView.drawingPolicy = .anyInput
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update if needed
    }
}



// GameChanger removed

struct LargeMonthCardView: View {
    let month: Int
    let year: Int
    let currentDate: Date
    
    private var monthName: String {
        Calendar.mondayFirst.monthSymbols[month - 1]
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return Calendar.mondayFirst.component(.year, from: today) == year &&
               Calendar.mondayFirst.component(.month, from: today) == month
    }
    
    private var currentDay: Int {
        Calendar.mondayFirst.component(.day, from: currentDate)
    }
    
    private var monthData: (daysInMonth: Int, offsetDays: Int) {
        let calendar = Calendar.mondayFirst
        let monthDate = calendar.date(from: DateComponents(year: year, month: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let offsetDays = (firstWeekday + 5) % 7
        return (daysInMonth, offsetDays)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Week headers
            HStack(spacing: 4) {
                Text("Week")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 50)
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { week in
                    largeWeekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func largeWeekRow(week: Int) -> some View {
        HStack(spacing: 4) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 50, height: 40)
            
            // Days
            ForEach(0..<7, id: \.self) { dayOfWeek in
                largeDayCell(week: week, dayOfWeek: dayOfWeek)
            }
        }
    }
    
    private func largeDayCell(week: Int, dayOfWeek: Int) -> some View {
        let dayNumber = week * 7 + dayOfWeek - monthData.offsetDays + 1
        let isValidDay = dayNumber > 0 && dayNumber <= monthData.daysInMonth
        let isToday = isCurrentMonth && dayNumber == currentDay
        
        return Group {
            if isValidDay {
                Text("\(dayNumber)")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
        }
    }
    
    private func getWeekNumber(for week: Int) -> String {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = (firstWeekday + 5) % 7
        
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth),
              let currentWeekDate = calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek) else {
            return ""
        }
        
        let weekNumber = calendar.component(.weekOfYear, from: currentWeekDate)
        return weekNumber > 0 ? "\(weekNumber)" : ""
    }
}

struct MonthCardView: View {
    let month: Int
    let year: Int
    let currentDate: Date
    let onDayTap: (Date) -> Void
    let onMonthTap: () -> Void
    let onWeekTap: (Date) -> Void
    
    private var monthName: String {
        Calendar.mondayFirst.monthSymbols[month - 1]
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return Calendar.mondayFirst.component(.year, from: today) == year &&
               Calendar.mondayFirst.component(.month, from: today) == month
    }
    
    private var currentDay: Int {
        Calendar.mondayFirst.component(.day, from: currentDate)
    }
    
    private var todayDay: Int {
        Calendar.mondayFirst.component(.day, from: Date())
    }
    
    private var monthData: (daysInMonth: Int, offsetDays: Int) {
        let calendar = Calendar.mondayFirst
        let monthDate = calendar.date(from: DateComponents(year: year, month: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let offsetDays = (firstWeekday + 5) % 7
        return (daysInMonth, offsetDays)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Month title
            Text(monthName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isCurrentMonth ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrentMonth ? Color.blue : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { onMonthTap() }
            
            // Week headers
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 20)
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    weekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            onDayTap(currentDate)
        }
    }
    
    private func weekRow(week: Int) -> some View {
        HStack(spacing: 2) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let weekStart = getWeekStartDate(for: week) {
                        onWeekTap(weekStart)
                    }
                }
            
            // Days
            ForEach(0..<7, id: \.self) { dayOfWeek in
                dayCell(week: week, dayOfWeek: dayOfWeek)
            }
        }
    }
    
    private func dayCell(week: Int, dayOfWeek: Int) -> some View {
        let dayNumber = week * 7 + dayOfWeek - monthData.offsetDays + 1
        let isValidDay = dayNumber > 0 && dayNumber <= monthData.daysInMonth
        let isToday = isCurrentMonth && dayNumber == todayDay
        
        return Group {
            if isValidDay {
                Text("\(dayNumber)")
                    .font(.body)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let calendar = Calendar.mondayFirst
                        if let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) {
                            onDayTap(date)
                        }
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
        }
    }
    
    private func getWeekNumber(for week: Int) -> String {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = (firstWeekday + 5) % 7
        
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth),
              let currentWeekDate = calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek) else {
            return ""
        }
        
        let weekNumber = calendar.component(.weekOfYear, from: currentWeekDate)
        return weekNumber > 0 ? "\(weekNumber)" : ""
    }
    
    private func getWeekStartDate(for week: Int) -> Date? {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let offsetDays = (firstWeekday + 5) % 7
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -offsetDays, to: firstDayOfMonth) else { return nil }
        return calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek)
    }
}

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    /// Controls whether the system PKToolPicker is visible. Defaults to `true` to
    /// keep existing behaviour for call-sites that don't specify the argument.
    var showsToolPicker: Bool = true
    var onDrawingChanged: (() -> Void)?
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var toolPicker: PKToolPicker?
        let parent: PencilKitView
        
        init(_ parent: PencilKitView) {
            self.parent = parent
            super.init()
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.delegate = context.coordinator

        // Attach the scene-shared PKToolPicker once the view is in a window
        DispatchQueue.main.async {
            if let window = canvasView.window, let picker = PKToolPicker.shared(for: window) {
                context.coordinator.toolPicker = picker
                picker.addObserver(canvasView)
                picker.setVisible(showsToolPicker, forFirstResponder: canvasView)
                if showsToolPicker {
                    canvasView.becomeFirstResponder()
                }
            }
        }

        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update tool-picker visibility when state changes
        if let picker = context.coordinator.toolPicker {
            picker.setVisible(showsToolPicker, forFirstResponder: uiView)
            if showsToolPicker {
                if !uiView.isFirstResponder {
                    DispatchQueue.main.async {
                        uiView.becomeFirstResponder()
                    }
                }
            } else {
                if uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            }
        } else {
            // If the picker hasn't been set yet, attempt to attach it now
            DispatchQueue.main.async {
                if let window = uiView.window, let picker = PKToolPicker.shared(for: window) {
                    context.coordinator.toolPicker = picker
                    picker.addObserver(uiView)
                    picker.setVisible(showsToolPicker, forFirstResponder: uiView)
                    if showsToolPicker {
                        uiView.becomeFirstResponder()
                    }
                }
            }
        }
    }
}



// MARK: - Add Item View


// MARK: - End Time Picker View

struct EndTimePickerView: View {
    let startTime: Date
    @Binding var endTime: Date
    let onDismiss: () -> Void
    var title: String = "End Time"
    var maxMinutes: Int = 480

    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomPicker = false

    private var timeOptions: [(time: Date, label: String, duration: String)] {
        let calendar = Calendar.current
        var options: [(time: Date, label: String, duration: String)] = []

        // Generate time options in 15-minute increments
        // Start from the start time and go up to 8 hours later (to cover full workday)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        // Check if we need to show the date (for next-day times)
        let fullFormatter = DateFormatter()
        fullFormatter.dateStyle = .short
        fullFormatter.timeStyle = .short

        for minutes in stride(from: 0, through: maxMinutes, by: 15) {
            if let optionTime = calendar.date(byAdding: .minute, value: minutes, to: startTime) {
                let durationMinutes = minutes
                let durationText: String

                if durationMinutes == 0 {
                    durationText = "(0 mins)"
                } else if durationMinutes < 60 {
                    durationText = "(\(durationMinutes) mins)"
                } else {
                    let hours = durationMinutes / 60
                    let remainingMins = durationMinutes % 60
                    if remainingMins == 0 {
                        durationText = "(\(hours) hr\(hours > 1 ? "s" : ""))"
                    } else {
                        durationText = "(\(hours) hr\(hours > 1 ? "s" : "") \(remainingMins) mins)"
                    }
                }

                // Show date + time if it's a different day
                let timeLabel: String
                if calendar.isDate(startTime, inSameDayAs: optionTime) {
                    timeLabel = formatter.string(from: optionTime)
                } else {
                    timeLabel = fullFormatter.string(from: optionTime)
                }
                options.append((time: optionTime, label: timeLabel, duration: durationText))
            }
        }

        return options
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(timeOptions, id: \.time) { option in
                    Button(action: {
                        endTime = option.time
                        dismiss()
                        onDismiss()
                    }) {
                        HStack {
                            Text("\(option.label) \(option.duration)")
                                .foregroundColor(.primary)
                            Spacer()
                            if calendar.isDate(endTime, equalTo: option.time, toGranularity: .minute) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Custom time option
                Section {
                    Button(action: {
                        showingCustomPicker = true
                    }) {
                        HStack {
                            Text("Custom...")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCustomPicker) {
                NavigationStack {
                    Form {
                        DatePicker(title, selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.calendar, Calendar.mondayFirst)
                    }
                    .navigationTitle("Custom \(title)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingCustomPicker = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingCustomPicker = false
                                dismiss()
                                onDismiss()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var calendar: Calendar {
        Calendar.current
    }
}

#Preview {
    CalendarView()
} 
