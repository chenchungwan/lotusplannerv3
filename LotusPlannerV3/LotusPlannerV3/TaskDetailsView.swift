import SwiftUI

// MARK: - Task Details View
struct TaskDetailsView: View {
    let task: GoogleTask
    let taskListId: String
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let personalTaskLists: [GoogleTaskList]
    let professionalTaskLists: [GoogleTaskList]
    let appPrefs: AppPreferences
    let viewModel: TasksViewModel
    let onSave: (GoogleTask) -> Void
    let onDelete: () -> Void
    let onMove: (GoogleTask, String) -> Void
    let onCrossAccountMove: (GoogleTask, GoogleAuthManager.AccountKind, String) -> Void
    let isNew: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var editedDueDate: Date?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind
    @State private var selectedListId: String
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var showingDeleteAlert = false
    @State private var showingDatePicker = false
    @State private var showingEndTimePicker = false
    @State private var isSaving = false
    @State private var tempSelectedDate = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var isAllDay: Bool = true
    /// One-shot suppression for the startTime onChange handler so the
    /// freshly-set 30-min window from an all-day toggle isn't immediately
    /// stretched back to the prior duration.
    @State private var skipNextEndAutoAdjust: Bool = false
    @State private var isCompleted: Bool = false
    @State private var selectedPriority: TaskPriorityData?

    // Recurrence (existing tasks only; new tasks lack a stable server id to
    // key a RecurrenceRule under).
    @State private var repeatFrequency: RecurrenceFrequency?
    @State private var repeatInterval: Int = 1
    @State private var repeatEndDate: Date?

    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    @ObservedObject private var taskGoalLinkManager = TaskGoalLinkManager.shared

    // Track original due date to detect changes properly
    private let originalDueDate: Date?

    // Track original time window values to detect changes
    private let originalIsAllDay: Bool
    private let originalStartTime: Date
    private let originalEndTime: Date
    private let originalIsCompleted: Bool
    private let originalCompletedTimestamp: String?

    // Track original recurrence values so hasChanges fires for repeat edits.
    private let originalRepeatFrequency: RecurrenceFrequency?
    private let originalRepeatInterval: Int
    private let originalRepeatEndDate: Date?
    
    private var linkedGoals: [GoalData] {
        let goalIds = taskGoalLinkManager.goalIds(for: task.id)
        return GoalsManager.shared.goals.filter { goalIds.contains($0.id) }
    }

    private let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    private static let completionTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Thin alias for `TimeMath.defaultTimedWindow` so existing
    /// `Self.defaultTimedWindow(on:)` callers in this file continue to
    /// work without churning every call site.
    static func defaultTimedWindow(on date: Date) -> (start: Date, end: Date) {
        TimeMath.defaultTimedWindow(on: date)
    }


    init(task: GoogleTask, taskListId: String, accountKind: GoogleAuthManager.AccountKind, accentColor: Color, personalTaskLists: [GoogleTaskList], professionalTaskLists: [GoogleTaskList], appPrefs: AppPreferences, viewModel: TasksViewModel, onSave: @escaping (GoogleTask) -> Void, onDelete: @escaping () -> Void, onMove: @escaping (GoogleTask, String) -> Void, onCrossAccountMove: @escaping (GoogleTask, GoogleAuthManager.AccountKind, String) -> Void, isNew: Bool = false) {
        self.task = task
        self.taskListId = taskListId
        self.accountKind = accountKind
        self.accentColor = accentColor
        self.personalTaskLists = personalTaskLists
        self.professionalTaskLists = professionalTaskLists
        self.appPrefs = appPrefs
        self.viewModel = viewModel
        self.onSave = onSave
        self.onDelete = onDelete
        self.onMove = onMove
        self.onCrossAccountMove = onCrossAccountMove
        self.isNew = isNew
        
        // Store original due date to detect changes properly
        self.originalDueDate = task.dueDate
        self.originalIsCompleted = task.isCompleted
        self.originalCompletedTimestamp = task.completed
        
        _editedTitle = State(initialValue: task.title)
        _editedNotes = State(initialValue: task.userNotes ?? "")
        // For new tasks, default due date to current day; for existing tasks, use the task's due date
        _editedDueDate = State(initialValue: isNew ? Calendar.current.startOfDay(for: Date()) : task.dueDate)
        _selectedAccountKind = State(initialValue: accountKind)
        _selectedListId = State(initialValue: taskListId)
        _isCompleted = State(initialValue: isNew ? false : task.isCompleted)
        _selectedPriority = State(initialValue: task.priority)
        
        // Initialize time window state and store original values
        let calendar = Calendar.current
        if let existingTimeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
            _isAllDay = State(initialValue: existingTimeWindow.isAllDay)
            _startTime = State(initialValue: existingTimeWindow.startTime)
            _endTime = State(initialValue: existingTimeWindow.endTime)
            
            // Store original values
            self.originalIsAllDay = existingTimeWindow.isAllDay
            self.originalStartTime = existingTimeWindow.startTime
            self.originalEndTime = existingTimeWindow.endTime
        } else {
            // No time window exists - default to all-day initially
            let defaultIsAllDay = true
            let defaultStartTime: Date
            let defaultEndTime: Date
            
            // Use all-day defaults (will be updated when user toggles to timed via onChange)
            if let dueDate = task.dueDate {
                let startOfDay = calendar.startOfDay(for: dueDate)
                defaultStartTime = startOfDay
                defaultEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
            } else {
                // Default to today's start and end of day
                let today = Date()
                let startOfDay = calendar.startOfDay(for: today)
                defaultStartTime = startOfDay
                defaultEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? startOfDay
            }
            
            _isAllDay = State(initialValue: defaultIsAllDay)
            _startTime = State(initialValue: defaultStartTime)
            _endTime = State(initialValue: defaultEndTime)
            
            // Store original values (default values)
            self.originalIsAllDay = defaultIsAllDay
            self.originalStartTime = defaultStartTime
            self.originalEndTime = defaultEndTime
        }

        // Hydrate the repeat picker from the existing rule (if any).
        let existingRule = isNew ? nil : RecurrenceManager.shared.rule(for: task.id)
        _repeatFrequency = State(initialValue: existingRule?.frequency)
        _repeatInterval = State(initialValue: existingRule?.interval ?? 1)
        _repeatEndDate = State(initialValue: existingRule?.endDate)
        self.originalRepeatFrequency = existingRule?.frequency
        self.originalRepeatInterval = existingRule?.interval ?? 1
        self.originalRepeatEndDate = existingRule?.endDate
    }
    
    var availableTaskLists: [GoogleTaskList] {
        selectedAccountKind == .personal ? personalTaskLists : professionalTaskLists
    }
    
    var currentTaskListName: String {
        availableTaskLists.first { $0.id == selectedListId }?.title ?? "Unknown List"
    }
    
    var currentAccentColor: Color {
        selectedAccountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    var hasChanges: Bool {
        editedTitle != task.title ||
        editedNotes != (task.userNotes ?? "") ||
        editedDueDate != originalDueDate ||
        selectedAccountKind != accountKind ||
        selectedListId != taskListId ||
        isCreatingNewList ||
        isAllDay != originalIsAllDay ||
        !areTimesEqual(startTime, originalStartTime) ||
        !areTimesEqual(endTime, originalEndTime) ||
        isCompleted != originalIsCompleted ||
        selectedPriority != task.priority ||
        repeatFrequency != originalRepeatFrequency ||
        (repeatFrequency != nil && repeatInterval != originalRepeatInterval) ||
        (repeatFrequency != nil && repeatEndDate != originalRepeatEndDate)
    }
    
    // Helper function to compare times (ignoring seconds and milliseconds)
    private func areTimesEqual(_ time1: Date, _ time2: Date) -> Bool {
        let calendar = Calendar.current
        let components1 = calendar.dateComponents([.hour, .minute], from: time1)
        let components2 = calendar.dateComponents([.hour, .minute], from: time2)
        return components1.hour == components2.hour && components1.minute == components2.minute
    }
    
    var canSave: Bool {
        let hasValidTitle = !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidList = (!isCreatingNewList && !selectedListId.isEmpty) ||
                          (isCreatingNewList && !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // For timed tasks, ensure end time is after start time
        let hasValidTimes: Bool
        if !isAllDay && editedDueDate != nil {
            hasValidTimes = endTime > startTime
        } else {
            hasValidTimes = true
        }

        return hasValidTitle && hasValidList && hasValidTimes
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Information Section
                Section("Basic Information") {
                    TextField("Add task title", text: $editedTitle, axis: .vertical)
                        .lineLimit(1...3)
                    
                    TextField("Add description (optional)", text: $editedNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                // Account Section
                Section("Account") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Two rows: Personal and Professional, each with its own current list on the same line
                        ForEach([GoogleAuthManager.AccountKind.personal, .professional], id: \.self) { kind in
                            if GoogleAuthManager.shared.isLinked(kind: kind) {
                                let lists: [GoogleTaskList] = (kind == .personal) ? personalTaskLists : professionalTaskLists
                                let currentId: String = (selectedAccountKind == kind ? selectedListId : lists.first?.id) ?? lists.first?.id ?? ""
                                let currentTitle: String = lists.first(where: { $0.id == currentId })?.title ?? (lists.first?.title ?? "Select list")

                                HStack(spacing: 10) {
                                    Button {
                                        let previousAccount = selectedAccountKind
                                        selectedAccountKind = kind
                                        if let first = lists.first { selectedListId = first.id }
                                        isCreatingNewList = false
                                        newListName = ""
                                        // When switching accounts for an existing timed task, preserve times
                                        if !isNew && !isAllDay && previousAccount != kind {
                                            // Preserve original times - don't reset them
                                            if startTime == Calendar.current.startOfDay(for: startTime) || 
                                               endTime == Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endTime) {
                                                // Times were reset - restore from original
                                                startTime = originalStartTime
                                                endTime = originalEndTime
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: selectedAccountKind == kind ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(selectedAccountKind == kind ? (kind == .personal ? appPrefs.personalColor : appPrefs.professionalColor) : .secondary)
                                            Text(appPrefs.accountName(for: kind) + ":")
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    // Place the list immediately after the account name and colon
                                    if selectedAccountKind == kind {
                                        Menu(currentTitle) {
                                            Button("Create new list") {
                                                selectedAccountKind = kind
                                                isCreatingNewList = true
                                                newListName = ""
                                            }
                                            ForEach(lists) { taskList in
                                                Button(taskList.title) {
                                                    let previousList = selectedListId
                                                    selectedAccountKind = kind
                                                    selectedListId = taskList.id
                                                    isCreatingNewList = false
                                                    // When switching lists for an existing timed task, preserve times
                                                    if !isNew && !isAllDay && previousList != taskList.id {
                                                        // Preserve original times - don't reset them
                                                        if startTime == Calendar.current.startOfDay(for: startTime) || 
                                                           endTime == Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endTime) {
                                                            // Times were reset - restore from original
                                                            startTime = originalStartTime
                                                            endTime = originalEndTime
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Spacer(minLength: 8)
                                }
                            }
                        }

                        // Inline new list name input when requested
                        if isCreatingNewList {
                            HStack(spacing: 8) {
                                TextField("New list name", text: $newListName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Create") {
                                    Task {
                                        if let newId = await viewModel.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: selectedAccountKind) {
                                            selectedListId = newId
                                            isCreatingNewList = false
                                            newListName = ""
                                        }
                                    }
                                }
                                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                
                // Linked Goals Section
                if !linkedGoals.isEmpty {
                    Section("Linked Goals") {
                        ForEach(linkedGoals, id: \.id) { goal in
                            Button {
                                // Navigate to goals view
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    let nav = NavigationManager.shared
                                    // Set the interval to match the goal's timeframe
                                    switch goal.targetTimeframe {
                                    case .week:
                                        nav.switchToGoals()
                                        nav.updateInterval(.week, date: goal.dueDate)
                                    case .month:
                                        nav.switchToGoals()
                                        nav.updateInterval(.month, date: goal.dueDate)
                                    case .year:
                                        nav.switchToGoals()
                                        nav.updateInterval(.year, date: goal.dueDate)
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "target")
                                        .foregroundColor(goal.isCompleted ? .green : .accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(goal.title)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        if let category = GoalsManager.shared.categories.first(where: { $0.id == goal.categoryId }) {
                                            Text(category.title)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // Due Date Section
                Section("Due Date") {
                    if let dueDate = editedDueDate {
                    // Show date with calendar icon and trash can
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        
                        Button(action: {
                            tempSelectedDate = dueDate
                            showingDatePicker = true
                        }) {
                            Text(dueDateFormatter.string(from: dueDate))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            editedDueDate = nil
                            // Reset times when due date is removed
                            isAllDay = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // All-day toggle
                    Toggle(isOn: Binding(
                        get: { isAllDay },
                        set: { newValue in
                            let wasAllDay = isAllDay
                            isAllDay = newValue

                            // When switching from all-day to timed, default to the
                            // next half-hour boundary after the current wall-clock
                            // time + 30-minute duration. Same rule for new and
                            // existing tasks, regardless of whether the due date is
                            // today or future.
                            if !newValue && wasAllDay {
                                let dueDate = editedDueDate ?? Date()
                                let window = Self.defaultTimedWindow(on: dueDate)
                                skipNextEndAutoAdjust = true
                                startTime = window.start
                                endTime = window.end
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("All-day task")
                        }
                    }
                    
                    // Start and End time pickers (only show if not all-day)
                    if !isAllDay {
                        DatePicker("Start", selection: Binding(
                            get: { startTime },
                            set: { newValue in
                                startTime = newValue
                            }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .environment(\.calendar, Calendar.mondayFirst)

                        // Custom end time picker (same as events)
                        HStack {
                            Text("End")
                            Spacer()
                            Button(action: {
                                showingEndTimePicker = true
                            }) {
                                Text(formatEndTime(endTime))
                                    .foregroundColor(.primary)
                            }
                        }

                        // Validation message for invalid time range
                        if endTime <= startTime {
                            Text("End time must be after start time")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    // Show placeholder button
                    Button(action: {
                        tempSelectedDate = Date() // Initialize to today's date
                        showingDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("Add due date")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                    
                    Toggle(isOn: $isCompleted) {
                        HStack(spacing: 8) {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isCompleted ? currentAccentColor : .secondary)
                            Text(isCompleted ? "Marked complete" : "Mark as completed")
                                .foregroundColor(isCompleted ? currentAccentColor : .primary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: currentAccentColor))
                    
                    // Removed Task Status section per request
                }

                // Priority Section
                Section("Priority") {
                    PriorityIconSelector(selectedPriority: $selectedPriority)
                        .frame(maxWidth: .infinity)
                }

                Section("Repeat") {
                    Picker("Frequency", selection: $repeatFrequency) {
                        Text("Never").tag(nil as RecurrenceFrequency?)
                        ForEach(RecurrenceFrequency.allCases) { freq in
                            Text(freq.displayName).tag(freq as RecurrenceFrequency?)
                        }
                    }
                    .pickerStyle(.menu)

                    if let freq = repeatFrequency {
                        Stepper(value: $repeatInterval, in: 1...30) {
                            Text("Every \(repeatInterval) \(repeatInterval == 1 ? freq.unitName : "\(freq.unitName)s")")
                        }

                        Toggle("End on date", isOn: Binding(
                            get: { repeatEndDate != nil },
                            set: { hasEnd in
                                if hasEnd {
                                    repeatEndDate = repeatEndDate
                                        ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())
                                } else {
                                    repeatEndDate = nil
                                }
                            }
                        ))

                        if repeatEndDate != nil {
                            DatePicker(
                                "End date",
                                selection: Binding(
                                    get: { repeatEndDate ?? Date() },
                                    set: { repeatEndDate = $0 }
                                ),
                                in: Date()...,
                                displayedComponents: .date
                            )
                        }
                    }
                }

                // Add empty section at bottom to provide space when time pickers are visible
                if !isNew && !isAllDay {
                    Section {
                        EmptyView()
                    }
                    .frame(height: 60)
                }

                // Danger Zone section at bottom
                if !isNew {
                    Section("Danger Zone") {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Task")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Task" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? (isNew ? "Creating..." : "Saving...") : (isNew ? "Create" : "Save")) {
                        saveTask()
                    }
                    .disabled(!canSave || (isNew ? false : !hasChanges) || isSaving)
                    .fontWeight(.semibold)
                    .foregroundColor((canSave && (isNew || hasChanges) && !isSaving) ? currentAccentColor : .secondary)
                    .opacity((canSave && (isNew || hasChanges) && !isSaving) ? 1.0 : 0.5)
                }
            }
        }
        .presentationDetents([.large, .height(isAllDay ? 600 : (!isNew ? 850 : 750))]) // Increase height when delete button and time pickers are visible
        .presentationDragIndicator(.visible)
        .alert("Delete Task", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Clean up any recurrence rule before the task itself goes away.
                RecurrenceManager.shared.deleteRule(for: task.id)
                onDelete()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(task.title)'? This action cannot be undone.")
        }
        .onChange(of: selectedListId) { oldValue, newValue in
            // When switching lists for an existing timed task, preserve times
            if !isNew && !isAllDay && oldValue != newValue {
                // Check if times are at default all-day values
                let calendar = Calendar.current
                let startHour = calendar.component(.hour, from: startTime)
                let startMinute = calendar.component(.minute, from: startTime)
                let endHour = calendar.component(.hour, from: endTime)
                let endMinute = calendar.component(.minute, from: endTime)
                
                let isStartAtMidnight = startHour == 0 && startMinute == 0
                let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                
                // If times were reset to defaults, restore from original
                if isStartAtMidnight && isEndAtEndOfDay && !originalIsAllDay {
                    startTime = originalStartTime
                    endTime = originalEndTime
                }
            }
        }
        .onChange(of: selectedAccountKind) { oldValue, newValue in
            // When switching accounts for an existing timed task, preserve times
            if !isNew && !isAllDay && oldValue != newValue {
                // Check if times are at default all-day values
                let calendar = Calendar.current
                let startHour = calendar.component(.hour, from: startTime)
                let startMinute = calendar.component(.minute, from: startTime)
                let endHour = calendar.component(.hour, from: endTime)
                let endMinute = calendar.component(.minute, from: endTime)
                
                let isStartAtMidnight = startHour == 0 && startMinute == 0
                let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                
                // If times were reset to defaults, restore from original
                if isStartAtMidnight && isEndAtEndOfDay && !originalIsAllDay {
                    startTime = originalStartTime
                    endTime = originalEndTime
                }
            }
        }
        .onAppear {
            // Load tasks on-demand when popup opens (performance optimization)
            Task {
                await viewModel.loadTasksOnDemand()
            }
            
            // For new tasks, if they're already timed (shouldn't happen normally, but just in case)
            // or if they're all-day but we want to ensure proper initialization
            // This is a backup to ensure times are set correctly
            if isNew && !isAllDay {
                let calendar = Calendar.current
                let dueDate = editedDueDate ?? Date()

                // Check if times are still at default all-day values; if so,
                // replace with the next-half-hour + 30 min default.
                let startHour = calendar.component(.hour, from: startTime)
                let startMinute = calendar.component(.minute, from: startTime)
                let endHour = calendar.component(.hour, from: endTime)
                let endMinute = calendar.component(.minute, from: endTime)

                let isStartAtMidnight = startHour == 0 && startMinute == 0
                let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                if isStartAtMidnight && isEndAtEndOfDay {
                    let window = Self.defaultTimedWindow(on: dueDate)
                    startTime = window.start
                    endTime = window.end
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $tempSelectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Due Date")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Initialize tempSelectedDate with current editedDueDate or today
                    tempSelectedDate = editedDueDate ?? Date()
                    // Update start and end times when due date changes
                    if let dueDate = editedDueDate {
                        let calendar = Calendar.current
                        // Keep the time but update the date
                        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                        
                        if let hour = startComponents.hour, let minute = startComponents.minute {
                            startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? dueDate
                        } else {
                            startTime = calendar.startOfDay(for: dueDate)
                        }
                        
                        if let hour = endComponents.hour, let minute = endComponents.minute {
                            endTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? dueDate
                        } else {
                            endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? dueDate
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            // Sync the selected date to editedDueDate
                            let oldDueDate = editedDueDate
                            editedDueDate = tempSelectedDate
                            
                            // Update start and end times to match new due date
                            if let newDueDate = editedDueDate {
                                let calendar = Calendar.current
                                if oldDueDate != nil {
                                    // Transfer time components from old date to new date
                                    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                                    let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                                    
                                    if let hour = startComponents.hour, let minute = startComponents.minute {
                                        startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDueDate) ?? newDueDate
                                    } else {
                                        startTime = calendar.startOfDay(for: newDueDate)
                                    }
                                    
                                    if let hour = endComponents.hour, let minute = endComponents.minute {
                                        endTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDueDate) ?? newDueDate
                                    } else {
                                        endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: newDueDate) ?? newDueDate
                                    }
                                } else {
                                    // New due date - set default times
                                    let startOfDay = calendar.startOfDay(for: newDueDate)
                                    startTime = startOfDay
                                    endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: newDueDate) ?? startOfDay
                                }
                            }
                            
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: startTime) { oldValue, newValue in
            // Skip the auto end-adjust when the all-day toggle just set
            // both start and end together — otherwise the duration calc
            // would stretch the freshly-set 30-min window back to the
            // prior all-day-derived span.
            if skipNextEndAutoAdjust {
                skipNextEndAutoAdjust = false
            } else {
                // Preserve duration when start time changes (same as events)
                let duration = oldValue.distance(to: endTime)
                if duration > 0 {
                    endTime = newValue.addingTimeInterval(duration)
                } else {
                    endTime = Calendar.current.date(byAdding: .minute, value: 30, to: newValue) ?? newValue.addingTimeInterval(1800)
                }
            }

            // Sync due date if the date component changed
            let calendar = Calendar.current
            if let dueDate = editedDueDate, !calendar.isDate(newValue, inSameDayAs: dueDate) {
                editedDueDate = newValue
            }
        }
        .sheet(isPresented: $showingEndTimePicker) {
            EndTimePickerView(
                startTime: startTime,
                endTime: $endTime,
                onDismiss: { showingEndTimePicker = false }
            )
        }
    }

    private func formatEndTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time)
    }

    /// Writes the user's selection from the Repeat section into
    /// `RecurrenceManager`. A nil frequency means the user removed the rule.
    private func persistRecurrenceRule() {
        if let freq = repeatFrequency {
            let existing = RecurrenceManager.shared.rule(for: task.id)
            let now = Date()
            let rule = RecurrenceRule(
                seriesId: existing?.seriesId ?? UUID(),
                currentTaskId: task.id,
                accountKind: selectedAccountKind == .professional ? "professional" : "personal",
                listId: selectedListId,
                frequency: freq,
                interval: max(1, repeatInterval),
                endDate: repeatEndDate,
                endCount: nil,
                occurrencesSpawned: existing?.occurrencesSpawned ?? 0,
                lastSpawnedDate: existing?.lastSpawnedDate,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            RecurrenceManager.shared.setRule(rule)
        } else if RecurrenceManager.shared.hasRule(for: task.id) {
            RecurrenceManager.shared.deleteRule(for: task.id)
        }
    }

    private func saveTask() {
        isSaving = true

        // Persist the repeat rule synchronously (against the existing task id).
        // Cross-account moves rewrite the task id; for that edge case the rule
        // is left keyed to the old id and will be cleaned up by the catch-up
        // sweep when the old task disappears. Acceptable for MVP.
        if !isNew {
            persistRecurrenceRule()
        }

        Task {
            let targetListId: String
            
            if isCreatingNewList {
                // Create new task list first
                guard let newListId = await viewModel.createTaskList(
                    title: newListName.trimmingCharacters(in: .whitespacesAndNewlines),
                    for: selectedAccountKind
                ) else {
                    await MainActor.run {
                        isSaving = false
                    }
                    return
                }
                targetListId = newListId
            } else {
                targetListId = selectedListId
            }
            
            // Prepare due date string
            let dueDateString: String?
            if let dueDate = editedDueDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                dueDateString = formatter.string(from: dueDate)
            } else {
                dueDateString = nil
            }
            
            let statusString = isCompleted ? "completed" : "needsAction"
            let completionTimestamp: String?
            if isCompleted {
                if originalIsCompleted && !isNew {
                    completionTimestamp = originalCompletedTimestamp
                } else {
                    completionTimestamp = TaskDetailsView.completionTimestampFormatter.string(from: Date())
                }
            } else {
                completionTimestamp = nil
            }
            
            // Combine user notes with priority tag
            let userNotesText = editedNotes.isEmpty ? nil : editedNotes
            let notesWithPriority = TaskPriorityData.updateNotes(userNotesText, with: selectedPriority)

            let updatedTask = GoogleTask(
                id: task.id,
                title: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notesWithPriority,
                status: statusString,
                due: dueDateString,
                completed: completionTimestamp,
                updated: task.updated
            )
            
            if isNew {
                // Creation path
                // Prepare time window data if due date exists
                let finalStartTime: Date?
                let finalEndTime: Date?
                
                if let dueDate = editedDueDate {
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: dueDate)
                    
                    if isAllDay {
                        finalStartTime = startOfDay
                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                    } else {
                        // For new timed tasks, check if times are still at default all-day values
                        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endTime)
                        let startHour = startComponents.hour ?? 0
                        let startMinute = startComponents.minute ?? 0
                        let endHour = endComponents.hour ?? 23
                        let endMinute = endComponents.minute ?? 59
                        
                        // Check if times are at default all-day values (12:00am and 11:59pm)
                        // Also check if start time is at start of day (00:00:00) and end time is close to end of day
                        let isStartAtMidnight = startHour == 0 && startMinute == 0
                        let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0) || (endHour == 23 && endMinute == 58)
                        let isDefaultAllDayTime = isStartAtMidnight && isEndAtEndOfDay
                        
                        // Also check if the start time matches the start of the due date
                        let startTimeMatchesStartOfDay = calendar.isDate(startTime, inSameDayAs: dueDate) && 
                                                       calendar.component(.hour, from: startTime) == 0 &&
                                                       calendar.component(.minute, from: startTime) == 0
                        
                        if isDefaultAllDayTime || startTimeMatchesStartOfDay {
                            let window = Self.defaultTimedWindow(on: dueDate)
                            finalStartTime = window.start
                            finalEndTime = window.end
                        } else {
                            // Use the times as set by the user
                            if let hour = startComponents.hour, let minute = startComponents.minute {
                                finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                            } else {
                                finalStartTime = startOfDay
                            }
                            
                            if let hour = endComponents.hour, let minute = endComponents.minute {
                                finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                            } else {
                                finalEndTime = startOfDay.addingTimeInterval(1800) // Default 30 minutes
                            }
                        }
                    }
                } else {
                    finalStartTime = nil
                    finalEndTime = nil
                }
                
                // Capture user's repeat selection so we can attach a rule
                // once the server returns a real task id.
                let pendingFrequency = repeatFrequency
                let pendingInterval = max(1, repeatInterval)
                let pendingEndDate = repeatEndDate
                let pendingAccountKind = selectedAccountKind == .professional ? "professional" : "personal"
                let pendingListId = targetListId

                // Create task with time window parameters
                await viewModel.createTask(
                    title: updatedTask.title,
                    notes: updatedTask.notes,
                    dueDate: editedDueDate,
                    in: targetListId,
                    for: selectedAccountKind,
                    startTime: finalStartTime,
                    endTime: finalEndTime,
                    isAllDay: isAllDay,
                    status: statusString,
                    completed: completionTimestamp,
                    onServerCreated: { createdTask in
                        guard let freq = pendingFrequency else { return }
                        let now = Date()
                        let rule = RecurrenceRule(
                            seriesId: UUID(),
                            currentTaskId: createdTask.id,
                            accountKind: pendingAccountKind,
                            listId: pendingListId,
                            frequency: freq,
                            interval: pendingInterval,
                            endDate: pendingEndDate,
                            endCount: nil,
                            occurrencesSpawned: 0,
                            lastSpawnedDate: nil,
                            createdAt: now,
                            updatedAt: now
                        )
                        RecurrenceManager.shared.setRule(rule)
                    }
                )
                
                await MainActor.run {
                    dismiss()
                }
            } else {
                // Editing path (perform updates directly to ensure they complete)

                // Get the original time window before moving (if it exists)
                var originalTimeWindow: TaskTimeWindowData? = nil
                if selectedAccountKind != accountKind || targetListId != taskListId {
                    // Get time window from original task before moving (for both cross-account and same-account moves)
                    originalTimeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id)
                }
                
                if selectedAccountKind != accountKind {
                    let newTask = await viewModel.crossAccountMoveTask(updatedTask, from: (accountKind, taskListId), to: (selectedAccountKind, targetListId))
                    
                    // After cross-account move, use the returned new task
                    if let newTask = newTask {
                        let newTaskId = newTask.id

                        // Save time window for the new task if we have original time window or calculated times
                        if let dueDate = editedDueDate {
                            let calendar = Calendar.current
                            let startOfDay = calendar.startOfDay(for: dueDate)
                            
                            let finalStartTime: Date
                            let finalEndTime: Date
                            
                            if isAllDay {
                                finalStartTime = startOfDay
                                finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                            } else {
                                // Use original time window if available, otherwise use calculated times
                                if let originalTimeWindow = originalTimeWindow, !originalTimeWindow.isAllDay {
                                    // Transfer original times to new due date
                                    let originalStartComponents = calendar.dateComponents([.hour, .minute], from: originalTimeWindow.startTime)
                                    let originalEndComponents = calendar.dateComponents([.hour, .minute], from: originalTimeWindow.endTime)
                                    
                                    if let hour = originalStartComponents.hour, let minute = originalStartComponents.minute {
                                        finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalStartTime = startOfDay
                                    }
                                    
                                    if let hour = originalEndComponents.hour, let minute = originalEndComponents.minute {
                                        finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                                    }
                                } else {
                                    // Calculate times from current state
                                    let effectiveStartTime: Date
                                    let effectiveEndTime: Date
                                    
                                    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
                                    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endTime)
                                    let startHour = startComponents.hour ?? 0
                                    let startMinute = startComponents.minute ?? 0
                                    let endHour = endComponents.hour ?? 23
                                    let endMinute = endComponents.minute ?? 59
                                    
                                    let isStartAtMidnight = startHour == 0 && startMinute == 0
                                    let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                                    let isDefaultAllDayTime = isStartAtMidnight && isEndAtEndOfDay
                                    
                                    let originalStartComponents = calendar.dateComponents([.hour, .minute], from: originalStartTime)
                                    let originalEndComponents = calendar.dateComponents([.hour, .minute], from: originalEndTime)
                                    let currentStartComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                                    let currentEndComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                                    
                                    let timesMatchOriginal = originalStartComponents.hour == currentStartComponents.hour &&
                                                            originalStartComponents.minute == currentStartComponents.minute &&
                                                            originalEndComponents.hour == currentEndComponents.hour &&
                                                            originalEndComponents.minute == currentEndComponents.minute
                                    
                                    if !originalIsAllDay {
                                        if isDefaultAllDayTime || timesMatchOriginal {
                                            effectiveStartTime = originalStartTime
                                            effectiveEndTime = originalEndTime
                                        } else {
                                            effectiveStartTime = startTime
                                            effectiveEndTime = endTime
                                        }
                                    } else {
                                        effectiveStartTime = startTime
                                        effectiveEndTime = endTime
                                    }
                                    
                                    let effectiveStartComponents = calendar.dateComponents([.hour, .minute], from: effectiveStartTime)
                                    let effectiveEndComponents = calendar.dateComponents([.hour, .minute], from: effectiveEndTime)
                                    
                                    if let hour = effectiveStartComponents.hour, let minute = effectiveStartComponents.minute {
                                        finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalStartTime = startOfDay
                                    }
                                    
                                    if let hour = effectiveEndComponents.hour, let minute = effectiveEndComponents.minute {
                                        finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                                    }
                                }
                            }
                            
                            // Only save time window for timed tasks (not all-day)
                            if !isAllDay {
                                TaskTimeWindowManager.shared.saveTimeWindow(
                                    taskId: newTaskId,
                                    startTime: finalStartTime,
                                    endTime: finalEndTime,
                                    isAllDay: false
                                )
                            } else {
                                // Delete time window for all-day tasks
                                TaskTimeWindowManager.shared.deleteTimeWindow(for: newTaskId)
                            }
                        } else {
                            // Remove time window if due date is removed
                            TaskTimeWindowManager.shared.deleteTimeWindow(for: newTaskId)
                        }

                        // Delete time window from old task
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                    } else {
                    }
                } else if targetListId != taskListId {
                    let newTask = await viewModel.moveTask(updatedTask, from: taskListId, to: targetListId, for: selectedAccountKind)
                    
                    // After same-account move, use the returned new task
                    if let newTask = newTask {
                        let newTaskId = newTask.id

                        // Save time window for the new task if we have original time window or calculated times
                        if let dueDate = editedDueDate {
                            let calendar = Calendar.current
                            let startOfDay = calendar.startOfDay(for: dueDate)
                            
                            let finalStartTime: Date
                            let finalEndTime: Date
                            
                            if isAllDay {
                                finalStartTime = startOfDay
                                finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                            } else {
                                // Use original time window if available, otherwise use calculated times
                                if let originalTimeWindow = originalTimeWindow, !originalTimeWindow.isAllDay {
                                    // Transfer original times to new due date
                                    let originalStartComponents = calendar.dateComponents([.hour, .minute], from: originalTimeWindow.startTime)
                                    let originalEndComponents = calendar.dateComponents([.hour, .minute], from: originalTimeWindow.endTime)
                                    
                                    if let hour = originalStartComponents.hour, let minute = originalStartComponents.minute {
                                        finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalStartTime = startOfDay
                                    }
                                    
                                    if let hour = originalEndComponents.hour, let minute = originalEndComponents.minute {
                                        finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                                    }
                                } else {
                                    // Calculate times from current state
                                    let effectiveStartTime: Date
                                    let effectiveEndTime: Date
                                    
                                    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
                                    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endTime)
                                    let startHour = startComponents.hour ?? 0
                                    let startMinute = startComponents.minute ?? 0
                                    let endHour = endComponents.hour ?? 23
                                    let endMinute = endComponents.minute ?? 59
                                    
                                    let isStartAtMidnight = startHour == 0 && startMinute == 0
                                    let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                                    let isDefaultAllDayTime = isStartAtMidnight && isEndAtEndOfDay
                                    
                                    let originalStartComponents = calendar.dateComponents([.hour, .minute], from: originalStartTime)
                                    let originalEndComponents = calendar.dateComponents([.hour, .minute], from: originalEndTime)
                                    let currentStartComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                                    let currentEndComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                                    
                                    let timesMatchOriginal = originalStartComponents.hour == currentStartComponents.hour &&
                                                            originalStartComponents.minute == currentStartComponents.minute &&
                                                            originalEndComponents.hour == currentEndComponents.hour &&
                                                            originalEndComponents.minute == currentEndComponents.minute
                                    
                                    if !originalIsAllDay {
                                        if isDefaultAllDayTime || timesMatchOriginal {
                                            effectiveStartTime = originalStartTime
                                            effectiveEndTime = originalEndTime
                                        } else {
                                            effectiveStartTime = startTime
                                            effectiveEndTime = endTime
                                        }
                                    } else {
                                        effectiveStartTime = startTime
                                        effectiveEndTime = endTime
                                    }
                                    
                                    let effectiveStartComponents = calendar.dateComponents([.hour, .minute], from: effectiveStartTime)
                                    let effectiveEndComponents = calendar.dateComponents([.hour, .minute], from: effectiveEndTime)
                                    
                                    if let hour = effectiveStartComponents.hour, let minute = effectiveStartComponents.minute {
                                        finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalStartTime = startOfDay
                                    }
                                    
                                    if let hour = effectiveEndComponents.hour, let minute = effectiveEndComponents.minute {
                                        finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                                    } else {
                                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                                    }
                                }
                            }
                            
                            // Only save time window for timed tasks (not all-day)
                            if !isAllDay {
                                TaskTimeWindowManager.shared.saveTimeWindow(
                                    taskId: newTaskId,
                                    startTime: finalStartTime,
                                    endTime: finalEndTime,
                                    isAllDay: false
                                )
                            } else {
                                // Delete time window for all-day tasks
                                TaskTimeWindowManager.shared.deleteTimeWindow(for: newTaskId)
                            }
                        } else {
                            // Remove time window if due date is removed
                            TaskTimeWindowManager.shared.deleteTimeWindow(for: newTaskId)
                        }

                        // Delete time window from old task
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                    } else {
                    }
                } else {
                    await viewModel.updateTask(updatedTask, in: targetListId, for: selectedAccountKind)
                }
                
                // Save time window if due date exists (only for same-account moves or in-place updates)
                if selectedAccountKind == accountKind, let dueDate = editedDueDate {
                    // Ensure start and end times are on the same day as due date
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: dueDate)
                    
                    let finalStartTime: Date
                    let finalEndTime: Date
                    
                    if isAllDay {
                        finalStartTime = startOfDay
                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                    } else {
                        // For existing timed tasks, always prefer original times unless user explicitly changed them
                        let effectiveStartTime: Date
                        let effectiveEndTime: Date
                        
                        // For existing timed tasks, always prefer original times unless explicitly changed
                        // Check if current times are at default all-day values (midnight/end of day)
                        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endTime)
                        let startHour = startComponents.hour ?? 0
                        let startMinute = startComponents.minute ?? 0
                        let endHour = endComponents.hour ?? 23
                        let endMinute = endComponents.minute ?? 59
                        
                        let isStartAtMidnight = startHour == 0 && startMinute == 0
                        let isEndAtEndOfDay = (endHour == 23 && endMinute == 59) || (endHour == 23 && endMinute == 0)
                        let isDefaultAllDayTime = isStartAtMidnight && isEndAtEndOfDay
                        
                        // Check if current times match original times (ignoring date, just time components)
                        let originalStartComponents = calendar.dateComponents([.hour, .minute], from: originalStartTime)
                        let originalEndComponents = calendar.dateComponents([.hour, .minute], from: originalEndTime)
                        let currentStartComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                        let currentEndComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                        
                        let timesMatchOriginal = originalStartComponents.hour == currentStartComponents.hour &&
                                                originalStartComponents.minute == currentStartComponents.minute &&
                                                originalEndComponents.hour == currentEndComponents.hour &&
                                                originalEndComponents.minute == currentEndComponents.minute
                        
                        // For existing timed tasks:
                        // - Always use original times if current times are at defaults (were reset)
                        // - Always use original times if times match (user didn't change them, just due date changed)
                        // - Otherwise, use current times (user explicitly modified them)
                        if !originalIsAllDay {
                            if isDefaultAllDayTime || timesMatchOriginal {
                                // Use original times - they're the correct values
                                // This ensures we preserve the original times even if due date changed
                                effectiveStartTime = originalStartTime
                                effectiveEndTime = originalEndTime
                            } else {
                                // User explicitly modified times - use current values
                                effectiveStartTime = startTime
                                effectiveEndTime = endTime
                            }
                        } else {
                            // Task was originally all-day - use current times
                            effectiveStartTime = startTime
                            effectiveEndTime = endTime
                        }
                        
                        // Ensure times are on the due date
                        let effectiveStartComponents = calendar.dateComponents([.hour, .minute], from: effectiveStartTime)
                        let effectiveEndComponents = calendar.dateComponents([.hour, .minute], from: effectiveEndTime)
                        
                        if let hour = effectiveStartComponents.hour, let minute = effectiveStartComponents.minute {
                            finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalStartTime = startOfDay
                        }
                        
                        if let hour = effectiveEndComponents.hour, let minute = effectiveEndComponents.minute {
                            finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                        }
                    }
                    
                    // Only save time window for timed tasks (not all-day)
                    if !isAllDay {
                        TaskTimeWindowManager.shared.saveTimeWindow(
                            taskId: task.id,
                            startTime: finalStartTime,
                            endTime: finalEndTime,
                            isAllDay: false
                        )
                    } else {
                        // Delete time window for all-day tasks
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                    }
                } else {
                    // Remove time window if due date is removed
                    TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                }
                
                // No need to reload all tasks - individual methods update local state
                await MainActor.run { dismiss() }
            }
        }
    }
}

#Preview {
    TasksView()
} 
