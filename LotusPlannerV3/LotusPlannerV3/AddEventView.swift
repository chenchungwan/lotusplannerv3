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
    /// One-shot flag set by `handleAllDayChange` so the eventStart onChange
    /// handler doesn't immediately stretch our freshly-set 30-min window
    /// back to the prior duration. Reset on the next eventStart onChange fire.
    @State private var skipNextEndAutoAdjust = false
    
    let currentDate: Date
    let tasksViewModel: TasksViewModel
    let calendarViewModel: CalendarViewModel
    let appPrefs: AppPreferences
    let existingEvent: GoogleCalendarEvent?
    let existingEventAccountKind: GoogleAuthManager.AccountKind?
    let showEventOnly: Bool
    /// True when hosted inside `CreateItemSheet`, which owns the
    /// NavigationStack so the tab strip can sit above the form.
    let isEmbedded: Bool
    /// Reports title/notes edits so the host can carry them to another tab.
    let onDraftChange: ((String, String) -> Void)?
    
    private let authManager = GoogleAuthManager.shared

    // Store original event properties to preserve them during updates
    private let originalIsAllDay: Bool
    private let originalEventStart: Date
    private let originalEventEnd: Date

    /// Reacts to the All-Day toggle. Lives outside `body` to keep the view
    /// builder's type-checker workload small.
    private func handleAllDayChange(oldValue: Bool, newValue: Bool) {
        guard oldValue != newValue else { return }
        let cal = Calendar.current
        if newValue {
            // Converting to all-day: clamp to start of day and default to
            // same-day duration.
            let startDate = cal.startOfDay(for: eventStart)
            skipNextEndAutoAdjust = true
            eventStart = startDate
            eventEnd = startDate
        } else if oldValue == true {
            // Converting all-day → timed: next half-hour boundary after now
            // + 30 min duration, applied to the event's day. Same rule
            // whether the day is today or any other day.
            let eventDate = cal.startOfDay(for: eventStart)
            let window = Self.defaultTimedWindow(on: eventDate)
            skipNextEndAutoAdjust = true
            eventStart = window.start
            eventEnd = window.end
        }
        // If oldValue was false (already timed), don't change the times.
    }

    /// Thin alias for `TimeMath.defaultTimedWindow` so existing
    /// `Self.defaultTimedWindow(on:)` callers in this file continue to
    /// work without churning every call site.
    static func defaultTimedWindow(on date: Date) -> (start: Date, end: Date) {
        TimeMath.defaultTimedWindow(on: date)
    }
    
    private var availableTaskLists: [GoogleTaskList] {
        guard let accountKind = selectedAccountKind else { return [] }
        switch accountKind {
        case .account1:
            return tasksViewModel.account1TaskLists
        case .account2:
            return tasksViewModel.account2TaskLists
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
        return accountKind == .account1 ? appPrefs.account1Color : appPrefs.account2Color
    }
    
    private var isEditingEvent: Bool { existingEvent != nil }
    
    init(currentDate: Date,
         tasksViewModel: TasksViewModel,
         calendarViewModel: CalendarViewModel,
         appPrefs: AppPreferences,
         existingEvent: GoogleCalendarEvent? = nil,
         accountKind: GoogleAuthManager.AccountKind? = nil,
         showEventOnly: Bool = false,
         isEmbedded: Bool = false,
         initialTitle: String = "",
         initialNotes: String = "",
         onDraftChange: ((String, String) -> Void)? = nil) {
        self.currentDate = currentDate
        self.tasksViewModel = tasksViewModel
        self.calendarViewModel = calendarViewModel
        self.appPrefs = appPrefs
        self.existingEvent = existingEvent
        self.existingEventAccountKind = accountKind
        self.showEventOnly = showEventOnly
        self.isEmbedded = isEmbedded
        self.onDraftChange = onDraftChange
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
            _itemTitle = State(initialValue: initialTitle)
            _itemNotes = State(initialValue: initialNotes)
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
                // Default to the first linked account in Account-section
                // order (Account 1, then Account 2) so the form opens
                // ready to submit. The selection stays editable, and the
                // chosen account is highlighted in the Account row so it's
                // visible before the user taps Create.
                if authManager.isLinked(kind: .account1) {
                    _selectedAccountKind = State(initialValue: .account1)
                } else if authManager.isLinked(kind: .account2) {
                    _selectedAccountKind = State(initialValue: .account2)
                }
            }
        }
    }
    
    var body: some View {
        Group {
            if isEmbedded {
                formContent
            } else {
                NavigationStack {
                    formContent
                }
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

    /// The form plus its navigation chrome (title, Cancel/Create). Split out
    /// of `body` so `CreateItemSheet` can host it inside its own
    /// NavigationStack — the toolbar items surface in that stack's bar.
    @ViewBuilder
    private var formContent: some View {
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
                            if authManager.isLinked(kind: .account1) {
                                Button(action: {
                                    let previousAccount = selectedAccountKind
                                    selectedAccountKind = .account1
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                    // When switching accounts for an existing event, preserve isAllDay and times
                                    if isEditingEvent && previousAccount != nil && previousAccount != .account1 {
                                        // Don't reset isAllDay or times - preserve them
                                        // The eventStart and eventEnd should remain unchanged
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                        Text(appPrefs.account1Name)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .account1 ? appPrefs.account1Color.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .account1 ? appPrefs.account1Color : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .account1 ? appPrefs.account1Color : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if authManager.isLinked(kind: .account2) {
                                Button(action: {
                                    let previousAccount = selectedAccountKind
                                    selectedAccountKind = .account2
                                    selectedTaskListId = ""
                                    isCreatingNewList = false
                                    // When switching accounts for an existing event, preserve isAllDay and times
                                    if isEditingEvent && previousAccount != nil && previousAccount != .account2 {
                                        // Don't reset isAllDay or times - preserve them
                                        // The eventStart and eventEnd should remain unchanged
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "briefcase.circle.fill")
                                        Text(appPrefs.account2Name)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAccountKind == .account2 ? appPrefs.account2Color.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedAccountKind == .account2 ? appPrefs.account2Color : .primary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAccountKind == .account2 ? appPrefs.account2Color : Color.clear, lineWidth: 2)
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
                    // Skip the auto end-adjust when handleAllDayChange just
                    // set both start and end together — otherwise the
                    // duration calc would stretch the freshly-set 30-min
                    // window back to the prior all-day-derived span.
                    if skipNextEndAutoAdjust {
                        skipNextEndAutoAdjust = false
                        return
                    }
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
                    handleAllDayChange(oldValue: oldValue, newValue: newValue)
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
            .onChange(of: itemTitle) { _, newValue in
                onDraftChange?(newValue, itemNotes)
            }
            .onChange(of: itemNotes) { _, newValue in
                onDraftChange?(itemTitle, newValue)
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
                let savedEmail = authManager.getEmail(for: accountKind)

                // Ask Google whose token this actually is. If the
                // returned email doesn't match the account we think we
                // selected, the keychain entries got crossed at link
                // time and that's why events keep landing in the wrong
                // Gmail.
                var tokenActualEmail = "?"
                if let userinfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") {
                    var ureq = URLRequest(url: userinfoURL)
                    ureq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    if let (uData, _) = try? await URLSession.shared.data(for: ureq),
                       let info = try? JSONSerialization.jsonObject(with: uData) as? [String: Any] {
                        tokenActualEmail = (info["email"] as? String) ?? "?"
                    }
                }
                devLog("📅 createEvent kind=\(accountKind.rawValue) savedEmail=\(savedEmail) tokenActualEmail=\(tokenActualEmail) isAllDay=\(isAllDay)", level: .info, category: .calendar)

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

                // Log whatever the server actually persisted so we can
                // see which Gmail / calendar the event landed in. The
                // `creator.email` and `organizer.email` fields name the
                // owning account — which is the source of truth even if
                // the local `accountKind` says otherwise.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let createdId = (json["id"] as? String) ?? "?"
                    let creatorEmail = ((json["creator"] as? [String: Any])?["email"] as? String) ?? "?"
                    let organizerEmail = ((json["organizer"] as? [String: Any])?["email"] as? String) ?? "?"
                    devLog("📅 createEvent response status=\(httpResponse.statusCode) id=\(createdId) creator=\(creatorEmail) organizer=\(organizerEmail)", level: .info, category: .calendar)
                } else {
                    devLog("📅 createEvent response status=\(httpResponse.statusCode) body=\(String(data: data, encoding: .utf8) ?? "")", level: .info, category: .calendar)
                }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }

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

        isCreating = true

        Task {
            do {
                // Check if we're moving between accounts
                if originalAccountKind != targetAccountKind {
                    // First create the event in the new account
                    try await createEventInAccount(targetAccountKind)

                    // Then delete the event from the original account
                    try await deleteEventFromAccount(ev, from: originalAccountKind, viewModel: calendarViewModel)
                } else {
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
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
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

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }

        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
    }
    
    private func updateEventInSameAccount(_ event: GoogleCalendarEvent, accountKind: GoogleAuthManager.AccountKind) async throws {
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerCalendarError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw CalendarManager.shared.handleHttpError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Delete Event
    private func deleteEvent() {
        guard let ev = existingEvent else {
            devLog("🗑️ deleteEvent: no existingEvent — aborting", level: .warning, category: .calendar)
            return
        }
        // Always re-resolve via calendarId rather than trusting the
        // sheet's stashed `existingEventAccountKind`. If the stashed
        // kind is stale (e.g. the event was reassigned by a refresh),
        // we'd build the DELETE URL with the wrong token and the call
        // would 404 — and the previous code swallowed that error,
        // leaving the sheet open with no feedback.
        let accountKind = calendarViewModel.accountKind(for: ev)
        let calId = ev.calendarId ?? "primary"
        // Google's DELETE endpoint accepts the bare event id — and
        // when the id contains characters like `_` it encodes fine
        // as-is. Older code double-encoded it which produced a 404.
        let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let encodedEventId = ev.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ev.id
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEventId)"
        devLog("🗑️ deleteEvent kind=\(accountKind.rawValue) calendarId=\(calId) eventId=\(ev.id) url=\(urlString)", level: .info, category: .calendar)

        isCreating = true
        Task {
            do {
                let accessToken = try await authManager.getAccessToken(for: accountKind)
                guard let url = URL(string: urlString) else {
                    devLog("🗑️ deleteEvent: bad url \(urlString)", level: .error, category: .calendar)
                    await MainActor.run { isCreating = false }
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("*", forHTTPHeaderField: "If-Match")

                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                devLog("🗑️ deleteEvent response status=\(status) body=\(bodyText.prefix(200))", level: .info, category: .calendar)

                // Google returns 204 No Content on success and 410
                // Gone if the event is already deleted — both should
                // dismiss the sheet and refresh. Anything else is a
                // real error we want to surface so the user knows.
                guard status == 204 || status == 410 else {
                    throw CalendarManager.shared.handleHttpError(status)
                }
                await calendarViewModel.refreshDataForCurrentView()
                await MainActor.run { dismiss() }
            } catch {
                devLog("🗑️ deleteEvent failed: \(error)", level: .error, category: .calendar)
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
