//
//  AddEventView.swift
//  LotusPlannerV3
//
//  Created by refactoring from CalendarView.swift
//

import SwiftUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0 // 0 = Task, 1 = Calendar Event
    @State private var itemTitle = ""
    @State private var itemNotes = ""
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var selectedTaskListId = ""
    @State private var newTaskListName = ""
    @State private var isCreatingNewList = false
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var isCreating = false
    @State private var eventStart: Date
    @State private var eventEnd: Date
    @State private var isAllDay = false
    @State private var showingDeleteEventAlert = false
    @State private var showingEndTimePicker = false
    
    let currentDate: Date
    let tasksViewModel: TasksViewModel
    let calendarViewModel: CalendarViewModel
    let appPrefs: AppPreferences
    let existingEvent: GoogleCalendarEvent?
    let existingEventAccountKind: GoogleAuthManager.AccountKind?
    let showEventOnly: Bool
    
    private let authManager = GoogleAuthManager.shared
    
    // Store original event properties to preserve them during updates
    private let originalIsAllDay: Bool
    private let originalEventStart: Date
    private let originalEventEnd: Date
    
    private var availableTaskLists: [GoogleTaskList] {
        guard let accountKind = selectedAccountKind else { return [] }
        switch accountKind {
        case .personal:
            return tasksViewModel.personalTaskLists
        case .professional:
            return tasksViewModel.professionalTaskLists
        }
    }
    
    private var canCreateTask: Bool {
        !itemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedAccountKind != nil &&
        ((!isCreatingNewList && !selectedTaskListId.isEmpty) || 
         (isCreatingNewList && !newTaskListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    
    private var canCreateEvent: Bool {
        !itemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isEditingEvent || selectedAccountKind != nil) && (isAllDay || eventEnd >= eventStart)
    }
    
    private var hasEventChanges: Bool {
        guard let ev = existingEvent else { return false }
        
        // Helper function to compare times (ignoring seconds and milliseconds)
        func areTimesEqual(_ time1: Date, _ time2: Date) -> Bool {
            let calendar = Calendar.current
            let components1 = calendar.dateComponents([.hour, .minute], from: time1)
            let components2 = calendar.dateComponents([.hour, .minute], from: time2)
            return components1.hour == components2.hour && components1.minute == components2.minute
        }
        
        // Compare dates (for all-day events) or dates + times (for timed events)
        let calendar = Calendar.current
        let originalStart = ev.startTime ?? Date()
        let originalEnd = ev.endTime ?? Date()
        
        let startChanged: Bool
        let endChanged: Bool
        
        if isAllDay {
            // For all-day events, compare dates only
            let currentStartDate = calendar.startOfDay(for: eventStart)
            let originalStartDate = calendar.startOfDay(for: originalStart)
            let currentEndDate = calendar.startOfDay(for: eventEnd)
            let originalEndDate = calendar.startOfDay(for: originalEnd)
            startChanged = currentStartDate != originalStartDate
            endChanged = currentEndDate != originalEndDate
        } else {
            // For timed events, compare date and time (hour and minute) separately
            let currentStartDate = calendar.startOfDay(for: eventStart)
            let originalStartDate = calendar.startOfDay(for: originalStart)
            let currentEndDate = calendar.startOfDay(for: eventEnd)
            let originalEndDate = calendar.startOfDay(for: originalEnd)
            
            // Start changed if date changed OR time changed
            startChanged = (currentStartDate != originalStartDate) || !areTimesEqual(eventStart, originalStart)
            // End changed if date changed OR time changed
            endChanged = (currentEndDate != originalEndDate) || !areTimesEqual(eventEnd, originalEnd)
        }
        
        return itemTitle != ev.summary ||
               itemNotes != (ev.description ?? "") ||
               startChanged ||
               endChanged ||
               isAllDay != ev.isAllDay ||
               selectedAccountKind != existingEventAccountKind
    }
    
    private var accentColor: Color {
        guard let accountKind = selectedAccountKind else { return .accentColor }
        return accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    private var isEditingEvent: Bool { existingEvent != nil }
    
    init(currentDate: Date,
         tasksViewModel: TasksViewModel,
         calendarViewModel: CalendarViewModel,
         appPrefs: AppPreferences,
         existingEvent: GoogleCalendarEvent? = nil,
         accountKind: GoogleAuthManager.AccountKind? = nil,
         showEventOnly: Bool = false) {
        self.currentDate = currentDate
        self.tasksViewModel = tasksViewModel
        self.calendarViewModel = calendarViewModel
        self.appPrefs = appPrefs
        self.existingEvent = existingEvent
        self.existingEventAccountKind = accountKind
        self.showEventOnly = showEventOnly
        // default times
        let cal = Calendar.current
        if let ev = existingEvent {
            // Editing path – prefill
            _selectedTab = State(initialValue: 1)
            _itemTitle = State(initialValue: ev.summary)
            _itemNotes = State(initialValue: ev.description ?? "")
            _selectedAccountKind = State(initialValue: accountKind)
            let initStart = ev.startTime ?? Date()
            let rawEnd = ev.endTime ?? (ev.startTime ?? Date()).addingTimeInterval(1800)
            let calendar = Calendar.current
            let adjustedEnd: Date
            if ev.isAllDay {
                adjustedEnd = calendar.date(byAdding: .day, value: -1, to: rawEnd) ?? initStart
            } else {
                adjustedEnd = rawEnd
            }
            _eventStart = State(initialValue: initStart)
            _eventEnd   = State(initialValue: max(initStart, adjustedEnd))
            _isAllDay = State(initialValue: ev.isAllDay)
            
            // Store original values to preserve them
            self.originalIsAllDay = ev.isAllDay
            self.originalEventStart = initStart
            self.originalEventEnd = max(initStart, adjustedEnd)
        } else {
            let rounded = cal.nextDate(after: Date(), matching: DateComponents(minute: cal.component(.minute, from: Date()) < 30 ? 30 : 0), matchingPolicy: .nextTime, direction: .forward) ?? Date()
            let initEnd = cal.date(byAdding: .minute, value: 30, to: rounded)!
            _eventStart = State(initialValue: rounded)
            _eventEnd = State(initialValue: initEnd)
            
            // For new events, store defaults
            self.originalIsAllDay = false
            self.originalEventStart = rounded
            self.originalEventEnd = initEnd
            
            if showEventOnly {
                _selectedTab = State(initialValue: 1)
                // Default to Personal account if available
                if authManager.isLinked(kind: .personal) {
                    _selectedAccountKind = State(initialValue: .personal)
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector (hidden when creating event-only, or editing an existing event)
                if !(showEventOnly || isEditingEvent) {
                    Picker("Type", selection: $selectedTab) {
                        Text("Task").tag(0)
                        Text("Calendar Event").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                }

                Form {
                    // MARK: - Basic Information Section
                    Section("Basic Information") {
                        // Title field
                        if selectedTab == 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Task Title")
                                TextField("Add task title", text: $itemTitle, axis: .vertical)
                                    .lineLimit(1...3)
                            }
                        } else {
                            TextField("Add event title", text: $itemTitle, axis: .vertical)
                                .lineLimit(1...3)
                                .textFieldStyle(PlainTextFieldStyle())
                        }

                        // Notes/Description field
                        if selectedTab == 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                TextField("Add description (optional)", text: $itemNotes, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                        } else {
                            TextField("Add description (optional)", text: $itemNotes, axis: .vertical)
                                .lineLimit(itemNotes.isEmpty ? 1 : nil)
                                .textFieldStyle(PlainTextFieldStyle())
                                .frame(height: itemNotes.isEmpty ? 30 : nil)
                        }
                    }

                    // MARK: - Account Section
                    Section("Account") {
                        HStack(spacing: 12) {
                            if authManager.isLinked(kind: .personal) {
                                Button(action: {
                                    let previousAccount = selectedAccountKind
                                    selectedAccountKind = .personal
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                    // When switching accounts for an existing event, preserve isAllDay and times
                                    if isEditingEvent && previousAccount != nil && previousAccount != .personal {
                                        // Don't reset isAllDay or times - preserve them
                                        // The eventStart and eventEnd should remain unchanged
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text(appPrefs.personalAccountName)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .personal ? appPrefs.personalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .personal ? appPrefs.personalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .personal ? appPrefs.personalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if authManager.isLinked(kind: .professional) {
                                Button(action: {
                                    let previousAccount = selectedAccountKind
                                    selectedAccountKind = .professional
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                    // When switching accounts for an existing event, preserve isAllDay and times
                                    if isEditingEvent && previousAccount != nil && previousAccount != .professional {
                                        // Don't reset isAllDay or times - preserve them
                                        // The eventStart and eventEnd should remain unchanged
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "briefcase.circle.fill")
                                        Text(appPrefs.professionalAccountName)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .professional ? appPrefs.professionalColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .professional ? appPrefs.professionalColor : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .professional ? appPrefs.professionalColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // MARK: - Task List Section
                        // Task List (only for tasks)
                        if selectedTab == 0 && selectedAccountKind != nil {
                            VStack(spacing: 8) {
                                // Create New List Option
                                HStack {
                                    Button(action: {
                                        isCreatingNewList.toggle()
                                        if isCreatingNewList {
                                            selectedTaskListId = ""
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: isCreatingNewList ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isCreatingNewList ? accentColor : .secondary)
                                            Text("Create new list")
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    Spacer()
                                }

                                if isCreatingNewList {
                                    TextField("New list name", text: $newTaskListName)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .padding(.leading, 28)
                                }

                                // Existing Lists
                                if !isCreatingNewList && !availableTaskLists.isEmpty {
                                    ForEach(availableTaskLists) { taskList in
                                        HStack {
                                            Button(action: {
                                                selectedTaskListId = taskList.id
                                            }) {
                                                HStack {
                                                    Image(systemName: selectedTaskListId == taskList.id ? "checkmark.circle.fill" : "circle")
                                                        .foregroundColor(selectedTaskListId == taskList.id ? accentColor : .secondary)
                                                    Text(taskList.title)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if selectedTab == 0 {
                        // Task-specific Due Date section

                        Section("Due Date") {
                            HStack {
                                Button(action: {
                                    hasDueDate.toggle()
                                    if !hasDueDate {
                                        dueDate = nil
                                    } else {
                                        dueDate = currentDate
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: hasDueDate ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(hasDueDate ? accentColor : .secondary)
                                        Text("Set due date")
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }

                            if hasDueDate {
                                DatePicker("Due Date", selection: Binding(
                                    get: { dueDate ?? currentDate },
                                    set: { dueDate = $0 }
                                ), displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .frame(maxHeight: 400)
                                .environment(\.calendar, Calendar.mondayFirst)
                            }
                        }
                    } else {
                        // Calendar event-specific fields
                        Section("Event Time") {
                            Toggle("All Day", isOn: Binding(
                                get: { isAllDay },
                                set: { newValue in
                                    // Only update if the value actually changed
                                    // This prevents accidental resets when other properties change
                                    if isAllDay != newValue {
                                        isAllDay = newValue
                                    }
                                }
                            ))
                            DatePicker("Start", selection: Binding(
                                get: { eventStart },
                                set: { newValue in
                                    // Accept the new value directly - user can change both date and time
                                    eventStart = newValue
                                }
                            ), displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                .environment(\.calendar, Calendar.mondayFirst)

                            // Custom end time picker for non-all-day events
                            if !isAllDay {
                                HStack {
                                    Text("End")
                                    Spacer()
                                    Button(action: {
                                        showingEndTimePicker = true
                                    }) {
                                        Text(formatEndTime(eventEnd))
                                            .foregroundColor(.primary)
                                    }
                                }
                            } else {
                                DatePicker("End", selection: Binding(
                                    get: { eventEnd },
                                    set: { newValue in
                                        // Accept the new value directly - user can change both date and time
                                        eventEnd = newValue
                                    }
                                ), in: eventStart..., displayedComponents: [.date])
                                    .environment(\.calendar, Calendar.mondayFirst)
                            }
                        }
                    }
                    
                    // Danger Zone section at bottom
                    if isEditingEvent {
                        Section("Danger Zone") {
                            Button(role: .destructive) {
                                showingDeleteEventAlert = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Event")
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .onChange(of: eventStart) { oldValue, newValue in
                    // When start date/time changes, preserve the duration by adjusting end date
                    let duration = oldValue.distance(to: eventEnd)
                    if duration > 0 {
                        // Preserve the original duration
                        eventEnd = newValue.addingTimeInterval(duration)
                    } else {
                        // If there was no duration or negative duration, set a default 30 min
                        eventEnd = Calendar.current.date(byAdding: .minute, value: 30, to: newValue) ?? newValue.addingTimeInterval(1800)
                    }
                }
                .onChange(of: selectedAccountKind) { oldValue, newValue in
                    // When switching accounts for an existing event, preserve isAllDay and times
                    // Only preserve if we're editing an existing event and the account actually changed
                    if isEditingEvent && oldValue != nil && newValue != nil && oldValue != newValue {
                        // Don't reset isAllDay or times - they should remain as they were
                        // The user is just moving the event to a different account
                    }
                }
                .onChange(of: isAllDay) { oldValue, newValue in
                    // Only update times if the user explicitly changed isAllDay (not during account switching)
                    // When editing an existing event and switching accounts, we want to preserve the original times
                    if oldValue != newValue {
                        let cal = Calendar.current
                        if newValue {
                            // Converting to all-day: clamp to start of day and default to same-day duration
                            let startDate = cal.startOfDay(for: eventStart)
                            eventStart = startDate
                            eventEnd = startDate
                        } else {
                            // Only set default times if the event was previously all-day
                            // If it was already timed, preserve the existing times
                            if oldValue == true {
                                // Converting from all-day to timed event: provide sensible default times
                                let eventDate = cal.startOfDay(for: eventStart)
                                let isToday = cal.isDateInToday(eventDate)
                                let isFuture = eventDate > cal.startOfDay(for: Date())
                                
                                if isToday {
                                    // For today, use current time rounded to next 30-min mark
                                    let now = Date()
                                    let minute = cal.component(.minute, from: now)
                                    let rounded = cal.nextDate(
                                        after: now,
                                        matching: DateComponents(minute: minute < 30 ? 30 : 0),
                                        matchingPolicy: .nextTime,
                                        direction: .forward
                                    ) ?? now
                                    eventStart = rounded
                                    eventEnd = cal.date(byAdding: .minute, value: 30, to: rounded) ?? rounded.addingTimeInterval(1800)
                                } else {
                                    // For past or future dates, use 9:00 AM as default
                                    if let defaultStart = cal.date(bySettingHour: 9, minute: 0, second: 0, of: eventDate) {
                                        eventStart = defaultStart
                                        eventEnd = cal.date(byAdding: .minute, value: 30, to: defaultStart) ?? defaultStart.addingTimeInterval(1800)
                                    } else {
                                        // Fallback if date creation fails
                                        eventStart = eventDate.addingTimeInterval(9 * 3600) // 9 AM
                                        eventEnd = eventStart.addingTimeInterval(1800) // 30 minutes later
                                    }
                                }
                            }
                            // If oldValue was false (already timed), don't change the times
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "New Task" : (isEditingEvent ? "Event Details" : "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditingEvent ? "Save" : "Create") {
                        if isEditingEvent {
                            // Always update the existing event when in edit mode, regardless of tab
                            updateEvent()
                        } else {
                            if selectedTab == 0 {
                                createTask()
                            } else {
                                createEvent()
                            }
                        }
                    }
                    .disabled(isEditingEvent ? (!canCreateEvent || !hasEventChanges) : (selectedTab == 0 ? !canCreateTask : !canCreateEvent))
                    .fontWeight(.semibold)
                    .foregroundColor((isEditingEvent ? (canCreateEvent && hasEventChanges) : (selectedTab == 0 ? canCreateTask : canCreateEvent)) ? accentColor : .secondary)
                    .opacity((isEditingEvent ? (canCreateEvent && hasEventChanges) : (selectedTab == 0 ? canCreateTask : canCreateEvent)) ? 1.0 : 0.5)
                }
                
                // Removed delete button from top toolbar
            }
        }
        .sheet(isPresented: $showingEndTimePicker) {
            EndTimePickerView(
                startTime: eventStart,
                endTime: $eventEnd,
                onDismiss: { showingEndTimePicker = false }
            )
        }
        .alert("Delete Event", isPresented: $showingDeleteEventAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
        } message: {
            if let event = existingEvent {
                Text("Are you sure you want to delete '\(event.summary ?? "this event")'? This action cannot be undone.")
            }
        }
    }
    
    private func createTask() {
        guard let accountKind = selectedAccountKind else { return }
        
        isCreating = true
        
        Task {
            do {
                if isCreatingNewList {
                    // Create new task list first
                    guard let newListId = await tasksViewModel.createTaskList(
                        title: newTaskListName.trimmingCharacters(in: .whitespacesAndNewlines),
                        for: accountKind
                    ) else {
                        throw TasksError.failedToCreateTaskList
                    }
                    
                    // Create task in new list
                    await tasksViewModel.createTask(
                        title: itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: itemNotes.isEmpty ? nil : itemNotes,
                        dueDate: dueDate,
                        in: newListId,
                        for: accountKind
                    )
                } else {
                    // Create task in existing list
                    await tasksViewModel.createTask(
                        title: itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: itemNotes.isEmpty ? nil : itemNotes,
                        dueDate: dueDate,
                        in: selectedTaskListId,
                        for: accountKind
                    )
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    // Handle error (could show alert)
                }
            }
        }
    }
    
    private func createEvent() {
        guard let accountKind = selectedAccountKind else { return }
        isCreating = true

        Task {
            do {
                let accessToken = try await authManager.getAccessToken(for: accountKind)
                
                let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.timeZone = TimeZone.current

                var startDict: [String: String] = [:]
                var endDict: [String: String] = [:]
        if isAllDay {
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let (startDate, exclusiveEndDate) = normalizedAllDayDateRange(using: calendar)
            startDict["date"] = dateFormatter.string(from: startDate)
            endDict["date"] = dateFormatter.string(from: exclusiveEndDate)
        } else {
                    startDict["dateTime"] = isoFormatter.string(from: eventStart)
                    endDict["dateTime"] = isoFormatter.string(from: eventEnd)
                    // Provide explicit timeZone to satisfy Google Calendar API
                    startDict["timeZone"] = TimeZone.current.identifier
                    endDict["timeZone"] = TimeZone.current.identifier
                }

                var body: [String: Any] = [
                    "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    "start": startDict,
                    "end": endDict
                ]
                if !itemNotes.isEmpty { body["description"] = itemNotes }

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PlannerCalendarError.invalidResponse
                }
                
                
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let responseString = String(data: data, encoding: .utf8) {
                devLog("   - ❌ Error response: \(responseString)")
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
        // Log successful creation
        if let responseString = String(data: data, encoding: .utf8) {
            devLog("   - ✅ Success! Response: \(responseString.prefix(500))")
        }
        devLog("📅 CREATE EVENT IN ACCOUNT - Event created successfully")

        // Refresh the current view to reflect changes
        Task {
            await calendarViewModel.refreshDataForCurrentView()
        }

        await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }
    
    private func normalizedAllDayDateRange(using calendar: Calendar) -> (start: Date, exclusiveEnd: Date) {
        let normalizedStart = calendar.startOfDay(for: eventStart)
        let normalizedEnd = calendar.startOfDay(for: max(eventStart, eventEnd))
        let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: normalizedEnd) ?? normalizedEnd.addingTimeInterval(24 * 3600)
        return (normalizedStart, exclusiveEnd)
    }
    
    // MARK: - Update existing event
    private func updateEvent() {
        guard let ev = existingEvent else { return }
        guard let originalAccountKind = existingEventAccountKind else { return }
        let targetAccountKind = selectedAccountKind ?? originalAccountKind
        
        // Log existing event details
        let calendar = Calendar.current
        let existingStartTime = ev.startTime ?? Date()
        let existingEndTime = ev.endTime ?? (ev.startTime ?? Date()).addingTimeInterval(1800)
        let existingStartHour = calendar.component(.hour, from: existingStartTime)
        let existingStartMinute = calendar.component(.minute, from: existingStartTime)
        let existingEndHour = calendar.component(.hour, from: existingEndTime)
        let existingEndMinute = calendar.component(.minute, from: existingEndTime)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        devLog("📅 EVENT UPDATE - Existing Event Details:")
        devLog("   - Event ID: \(ev.id)")
        devLog("   - Title: \(ev.summary)")
        devLog("   - isAllDay: \(ev.isAllDay)")
        devLog("   - Start Time: \(dateFormatter.string(from: existingStartTime)) (\(existingStartHour):\(String(format: "%02d", existingStartMinute)))")
        devLog("   - End Time: \(dateFormatter.string(from: existingEndTime)) (\(existingEndHour):\(String(format: "%02d", existingEndMinute)))")
        devLog("   - Original Account: \(originalAccountKind)")
        devLog("   - Target Account: \(targetAccountKind)")
        
        // Log current state values
        let currentStartHour = calendar.component(.hour, from: eventStart)
        let currentStartMinute = calendar.component(.minute, from: eventStart)
        let currentEndHour = calendar.component(.hour, from: eventEnd)
        let currentEndMinute = calendar.component(.minute, from: eventEnd)
        
        devLog("📅 EVENT UPDATE - Current State Values:")
        devLog("   - isAllDay: \(isAllDay)")
        devLog("   - eventStart: \(dateFormatter.string(from: eventStart)) (\(currentStartHour):\(String(format: "%02d", currentStartMinute)))")
        devLog("   - eventEnd: \(dateFormatter.string(from: eventEnd)) (\(currentEndHour):\(String(format: "%02d", currentEndMinute)))")
        devLog("   - originalIsAllDay: \(originalIsAllDay)")
        devLog("   - originalEventStart: \(dateFormatter.string(from: originalEventStart))")
        devLog("   - originalEventEnd: \(dateFormatter.string(from: originalEventEnd))")
        
        isCreating = true

        Task {
            do {
                // Check if we're moving between accounts
                if originalAccountKind != targetAccountKind {
                    devLog("📅 EVENT UPDATE - Moving between accounts")
                    
                    // First create the event in the new account
                    try await createEventInAccount(targetAccountKind)
                    
                    // Then delete the event from the original account
                    try await deleteEventFromAccount(ev, from: originalAccountKind, viewModel: calendarViewModel)
                    
                } else {
                    devLog("📅 EVENT UPDATE - Updating in same account")
                    // Same account - just update the existing event
                    try await updateEventInSameAccount(ev, accountKind: originalAccountKind)
                }

                // Refresh events for the currently visible date so UI reflects change immediately
                Task {
                    await calendarViewModel.refreshDataForCurrentView()
                }
                
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }
    
    private func createEventInAccount(_ accountKind: GoogleAuthManager.AccountKind) async throws {
        
        // Log what's being sent to API
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let startHour = calendar.component(.hour, from: eventStart)
        let startMinute = calendar.component(.minute, from: eventStart)
        let endHour = calendar.component(.hour, from: eventEnd)
        let endMinute = calendar.component(.minute, from: eventEnd)
        
        devLog("📅 CREATE EVENT IN ACCOUNT - Sending to API:")
        devLog("   - Account: \(accountKind)")
        devLog("   - isAllDay: \(isAllDay)")
        devLog("   - eventStart: \(dateFormatter.string(from: eventStart)) (\(startHour):\(String(format: "%02d", startMinute)))")
        devLog("   - eventEnd: \(dateFormatter.string(from: eventEnd)) (\(endHour):\(String(format: "%02d", endMinute)))")
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone.current

        var startDict: [String: String] = [:]
        var endDict: [String: String] = [:]
        if isAllDay {
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let (startDate, exclusiveEndDate) = normalizedAllDayDateRange(using: calendar)
            startDict["date"] = dateFormatter.string(from: startDate)
            endDict["date"] = dateFormatter.string(from: exclusiveEndDate)
            devLog("   - Start dict (all-day): \(startDict)")
            devLog("   - End dict (all-day): \(endDict)")
        } else {
            startDict["dateTime"] = isoFormatter.string(from: eventStart)
            endDict["dateTime"] = isoFormatter.string(from: eventEnd)
            startDict["timeZone"] = TimeZone.current.identifier
            endDict["timeZone"] = TimeZone.current.identifier
            devLog("   - Start dict (timed): \(startDict)")
            devLog("   - End dict (timed): \(endDict)")
        }

        var body: [String: Any] = [
            "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": startDict,
            "end": endDict
        ]
        if !itemNotes.isEmpty { body["description"] = itemNotes }
        
        devLog("   - Start dict: \(startDict)")
        devLog("   - End dict: \(endDict)")
        devLog("   - Body being sent: \(body)")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let responseString = String(data: data, encoding: .utf8) {
                devLog("   - ❌ Error response: \(responseString)")
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
        // Log successful creation and parse response to see what was saved
        if let responseString = String(data: data, encoding: .utf8),
           let responseData = responseString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            
            devLog("   - ✅ Success! Response received")
            
            // Parse response to see what was saved
            if let startDict = json["start"] as? [String: Any] {
                devLog("   - Response start: \(startDict)")
            }
            if let endDict = json["end"] as? [String: Any] {
                devLog("   - Response end: \(endDict)")
            }
            
            // Extract dates from response
            if let startDict = json["start"] as? [String: Any],
               let dateTimeStr = startDict["dateTime"] as? String {
                let isoFormatter = ISO8601DateFormatter()
                if let savedStartTime = isoFormatter.date(from: dateTimeStr) {
                    let savedFormatter = DateFormatter()
                    savedFormatter.dateStyle = .short
                    savedFormatter.timeStyle = .short
                    let savedStartHour = calendar.component(.hour, from: savedStartTime)
                    let savedStartMinute = calendar.component(.minute, from: savedStartTime)
                    devLog("   - 📅 Saved Start Time: \(savedFormatter.string(from: savedStartTime)) (\(savedStartHour):\(String(format: "%02d", savedStartMinute)))")
                }
            }
            if let endDict = json["end"] as? [String: Any],
               let dateTimeStr = endDict["dateTime"] as? String {
                let isoFormatter = ISO8601DateFormatter()
                if let savedEndTime = isoFormatter.date(from: dateTimeStr) {
                    let savedFormatter = DateFormatter()
                    savedFormatter.dateStyle = .short
                    savedFormatter.timeStyle = .short
                    let savedEndHour = calendar.component(.hour, from: savedEndTime)
                    let savedEndMinute = calendar.component(.minute, from: savedEndTime)
                    devLog("   - 📅 Saved End Time: \(savedFormatter.string(from: savedEndTime)) (\(savedEndHour):\(String(format: "%02d", savedEndMinute)))")
                }
            }
        }
        devLog("📅 CREATE EVENT IN ACCOUNT - Event created successfully")
        
    }
    
    private func deleteEventFromAccount(_ event: GoogleCalendarEvent, from accountKind: GoogleAuthManager.AccountKind, viewModel: CalendarViewModel) async throws {
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let calId = event.calendarId ?? "primary"
        let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*", forHTTPHeaderField: "If-Match")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
    }
    
    private func updateEventInSameAccount(_ event: GoogleCalendarEvent, accountKind: GoogleAuthManager.AccountKind) async throws {
        
        // Log what's being sent to API
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let startHour = calendar.component(.hour, from: eventStart)
        let startMinute = calendar.component(.minute, from: eventStart)
        let endHour = calendar.component(.hour, from: eventEnd)
        let endMinute = calendar.component(.minute, from: eventEnd)
        
        devLog("📅 UPDATE EVENT IN SAME ACCOUNT - Sending to API:")
        devLog("   - Event ID: \(event.id)")
        devLog("   - Account: \(accountKind)")
        devLog("   - isAllDay: \(isAllDay)")
        devLog("   - eventStart: \(dateFormatter.string(from: eventStart)) (\(startHour):\(String(format: "%02d", startMinute)))")
        devLog("   - eventEnd: \(dateFormatter.string(from: eventEnd)) (\(endHour):\(String(format: "%02d", endMinute)))")
        
        let accessToken = try await authManager.getAccessToken(for: accountKind)
        let calId = event.calendarId ?? "primary"
        let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let encodedEventId = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*", forHTTPHeaderField: "If-Match")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        isoFormatter.timeZone = TimeZone.current

        var startDict: [String: Any] = [:]
        var endDict: [String: Any] = [:]
        if isAllDay {
            // Converting to all-day event (Google expects exclusive end)
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let (startDate, exclusiveEndDate) = normalizedAllDayDateRange(using: calendar)
            startDict["date"] = dateFormatter.string(from: startDate)
            endDict["date"] = dateFormatter.string(from: exclusiveEndDate)
            // Explicitly remove dateTime and timeZone fields
            startDict["dateTime"] = NSNull()
            startDict["timeZone"] = NSNull()
            endDict["dateTime"] = NSNull()
            endDict["timeZone"] = NSNull()
        } else {
            // Converting to timed event
            startDict["dateTime"] = isoFormatter.string(from: eventStart)
            endDict["dateTime"] = isoFormatter.string(from: eventEnd)
            startDict["timeZone"] = TimeZone.current.identifier
            endDict["timeZone"] = TimeZone.current.identifier
            // Explicitly remove date field
            startDict["date"] = NSNull()
            endDict["date"] = NSNull()
        }

        var body: [String: Any] = [
            "summary": itemTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": startDict,
            "end": endDict,
            // Always include description so clearing notes works
            "description": itemNotes
        ]
        
        devLog("   - Start dict: \(startDict)")
        devLog("   - End dict: \(endDict)")
        devLog("   - Body being sent: \(body)")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                devLog("   - ❌ Error response: \(responseString)")
            }
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
        
        // Log successful update and parse response to see what was saved
        if let responseString = String(data: data, encoding: .utf8),
           let responseData = responseString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            
            devLog("   - ✅ Success! Response received")
            
            // Parse response to see what was saved
            if let startDict = json["start"] as? [String: Any] {
                devLog("   - Response start: \(startDict)")
            }
            if let endDict = json["end"] as? [String: Any] {
                devLog("   - Response end: \(endDict)")
            }
            
            // Extract dates from response
            if let startDict = json["start"] as? [String: Any],
               let dateTimeStr = startDict["dateTime"] as? String {
                let isoFormatter = ISO8601DateFormatter()
                if let savedStartTime = isoFormatter.date(from: dateTimeStr) {
                    let savedFormatter = DateFormatter()
                    savedFormatter.dateStyle = .short
                    savedFormatter.timeStyle = .short
                    let savedStartHour = calendar.component(.hour, from: savedStartTime)
                    let savedStartMinute = calendar.component(.minute, from: savedStartTime)
                    devLog("   - 📅 Saved Start Time: \(savedFormatter.string(from: savedStartTime)) (\(savedStartHour):\(String(format: "%02d", savedStartMinute)))")
                }
            }
            if let endDict = json["end"] as? [String: Any],
               let dateTimeStr = endDict["dateTime"] as? String {
                let isoFormatter = ISO8601DateFormatter()
                if let savedEndTime = isoFormatter.date(from: dateTimeStr) {
                    let savedFormatter = DateFormatter()
                    savedFormatter.dateStyle = .short
                    savedFormatter.timeStyle = .short
                    let savedEndHour = calendar.component(.hour, from: savedEndTime)
                    let savedEndMinute = calendar.component(.minute, from: savedEndTime)
                    devLog("   - 📅 Saved End Time: \(savedFormatter.string(from: savedEndTime)) (\(savedEndHour):\(String(format: "%02d", savedEndMinute)))")
                }
            }
        }
        devLog("📅 UPDATE EVENT IN SAME ACCOUNT - Update completed")
        
    }
    
    // MARK: - Delete Event
    private func deleteEvent() {
        guard let ev = existingEvent, let accountKind = existingEventAccountKind ?? selectedAccountKind else { return }
        isCreating = true
        Task {
            do {
                let accessToken = try await authManager.getAccessToken(for: accountKind)
                let calId = ev.calendarId ?? "primary"
                let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
                let encodedEventId = ev.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ev.id
                let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("*", forHTTPHeaderField: "If-Match")

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
                    throw CalendarManager.shared.handleHttpError((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                await calendarViewModel.refreshDataForCurrentView()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { isCreating = false }
            }
        }
    }

    // MARK: - Helper Functions
    private func formatEndTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time)
    }
}
