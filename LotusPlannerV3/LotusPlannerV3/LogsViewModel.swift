import Foundation
import SwiftUI

@MainActor
class LogsViewModel: ObservableObject {
    static let shared = LogsViewModel()
    
    private init() {
        loadLocalData()
        setupiCloudSync()
    }
    
    // Reload data from Core Data
    func reloadData() {
        loadLocalData()
    }
    

    @Published var selectedLogType: LogType = .weight
    @Published var currentDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddLogSheet = false
    @Published var showingEditLogSheet = false
    @Published var editingEntry: (type: LogType, id: String)? = nil
    
    // Weight entry form
    @Published var weightValue = ""
    @Published var selectedWeightUnit: WeightUnit = .pounds
    @Published var weightDate = Date()
    
    // Workout entry form
    @Published var workoutName = ""
    @Published var workoutDate = Date()
    
    // Food entry form
    @Published var foodName = ""
    @Published var foodDate = Date()

    // Sleep entry form
    @Published var sleepDate = Date()
    @Published var sleepWakeUpTime: Date?
    @Published var sleepBedTime: Date?

    // Original values for change detection in edit mode
    private var originalWeightValue = ""
    private var originalWeightUnit: WeightUnit = .pounds
    private var originalWeightDate = Date()
    private var originalWorkoutName = ""
    private var originalWorkoutDate = Date()
    private var originalFoodName = ""
    private var originalFoodDate = Date()
    private var originalSleepDate = Date()
    private var originalSleepWakeUpTime: Date?
    private var originalSleepBedTime: Date?
    
    // Local data storage
    @Published var weightEntries: [WeightLogEntry] = [] {
        didSet { rebuildWeightCache() }
    }
    @Published var workoutEntries: [WorkoutLogEntry] = [] {
        didSet { rebuildWorkoutCache() }
    }
    @Published var foodEntries: [FoodLogEntry] = [] {
        didSet { rebuildFoodCache() }
    }
    @Published var sleepEntries: [SleepLogEntry] = [] {
        didSet { rebuildSleepCache() }
    }

    private let coreDataManager = CoreDataManager.shared
    private let authManager = GoogleAuthManager.shared
    private var weightEntriesByDay: [Date: [WeightLogEntry]] = [:]
    private var workoutEntriesByDay: [Date: [WorkoutLogEntry]] = [:]
    private var foodEntriesByDay: [Date: [FoodLogEntry]] = [:]
    private var sleepEntriesByDay: [Date: [SleepLogEntry]] = [:]
    
    // MARK: - Computed Properties
    var filteredWeightEntries: [WeightLogEntry] {
        weightLogs(on: currentDate)
    }
    
    var filteredWorkoutEntries: [WorkoutLogEntry] {
        workoutLogs(on: currentDate)
    }
    
    var filteredFoodEntries: [FoodLogEntry] {
        foodLogs(on: currentDate)
    }

    var filteredSleepEntries: [SleepLogEntry] {
        sleepLogs(on: currentDate)
    }

    func weightLogs(on date: Date) -> [WeightLogEntry] {
        weightEntriesByDay[normalizedDay(date)] ?? []
    }

    func workoutLogs(on date: Date) -> [WorkoutLogEntry] {
        workoutEntriesByDay[normalizedDay(date)] ?? []
    }

    func foodLogs(on date: Date) -> [FoodLogEntry] {
        foodEntriesByDay[normalizedDay(date)] ?? []
    }

    func sleepLogs(on date: Date) -> [SleepLogEntry] {
        sleepEntriesByDay[normalizedDay(date)] ?? []
    }
    
    var accentColor: Color {
        return AppPreferences.shared.personalColor
    }
    
    // MARK: - Data Loading and Syncing
    private func loadLocalData() {
        // Refresh Core Data context to get latest changes from iCloud
        let context = PersistenceController.shared.container.viewContext
        context.refreshAllObjects()

        weightEntries = coreDataManager.loadWeightEntries()
        workoutEntries = coreDataManager.loadWorkoutEntries()
        foodEntries = coreDataManager.loadFoodEntries()
        sleepEntries = coreDataManager.loadSleepEntries()
    }
    
    private func setupiCloudSync() {
        // Listen for iCloud data change notifications
        NotificationCenter.default.addObserver(
            forName: .iCloudDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Reload data when iCloud sync completes
            self?.loadLocalData()
        }
        
        // Listen for Core Data remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Reload data when CloudKit changes are received
            self?.loadLocalData()
        }
    }
    
    private func rebuildWeightCache() {
        var map: [Date: [WeightLogEntry]] = [:]
        for entry in weightEntries {
            let key = normalizedDay(entry.timestamp)
            map[key, default: []].append(entry)
        }
        for key in map.keys {
            map[key]?.sort { $0.timestamp > $1.timestamp }
        }
        weightEntriesByDay = map
    }
    
    private func rebuildWorkoutCache() {
        var map: [Date: [WorkoutLogEntry]] = [:]
        for entry in workoutEntries {
            let key = normalizedDay(entry.date)
            map[key, default: []].append(entry)
        }
        for key in map.keys {
            map[key]?.sort { $0.createdAt > $1.createdAt }
        }
        workoutEntriesByDay = map
    }
    
    private func rebuildFoodCache() {
        var map: [Date: [FoodLogEntry]] = [:]
        for entry in foodEntries {
            let key = normalizedDay(entry.date)
            map[key, default: []].append(entry)
        }
        for key in map.keys {
            map[key]?.sort { $0.createdAt < $1.createdAt }
        }
        foodEntriesByDay = map
    }

    private func rebuildSleepCache() {
        var map: [Date: [SleepLogEntry]] = [:]
        for entry in sleepEntries {
            let key = normalizedDay(entry.date)
            map[key, default: []].append(entry)
        }
        for key in map.keys {
            map[key]?.sort { $0.createdAt < $1.createdAt }
        }
        sleepEntriesByDay = map
    }

    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    
    func loadLogsForCurrentDate() {
        // Data is already loaded locally, just filter for current date
        // This method is kept for compatibility with existing UI
    }
    
    // MARK: - Weight Entries
    func addWeightEntry() {
        guard let weight = Double(weightValue), !weightValue.isEmpty else {
            errorMessage = "Please enter a valid weight"
            return
        }
        
        let userId = getUserId()
        
        // Extract date and time from the combined date picker
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: weightDate)
        let time = weightDate
        
        let entry = WeightLogEntry(weight: weight, unit: selectedWeightUnit, userId: userId, date: date, time: time)
        
        // Save to Core Data immediately
        coreDataManager.saveWeightEntry(entry)
        
        // Update local array
        weightEntries.append(entry)
        
        // Clear form
        weightValue = ""
        weightDate = Date()
        showingAddLogSheet = false
        
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteWeightEntry(entry)
        
        // Update local array
        weightEntries.removeAll { $0.id == entry.id }
        
    }
    
    private func saveWeightEntries() {
        // Individual entries are saved immediately when added/updated
        // No batch save needed with Core Data
    }
    
    // MARK: - Workout Entries
    func addWorkoutEntry() {
        guard !workoutName.isEmpty else {
            errorMessage = "Please enter a workout name"
            return
        }
        
        let userId = getUserId()
        let entry = WorkoutLogEntry(date: workoutDate, name: workoutName, userId: userId)
        
        // Save to Core Data immediately
        coreDataManager.saveWorkoutEntry(entry)
        
        // Update local array
        workoutEntries.append(entry)
        
        // Clear form
        workoutName = ""
        workoutDate = Date()
        showingAddLogSheet = false
        
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteWorkoutEntry(entry)
        
        // Update local array
        workoutEntries.removeAll { $0.id == entry.id }
        
    }
    
    // MARK: - Food Entries
    func addFoodEntry() {
        guard !foodName.isEmpty else {
            errorMessage = "Please enter a food name"
            return
        }
        
        let userId = getUserId()
        let entry = FoodLogEntry(date: foodDate, name: foodName, userId: userId)
        
        
        // Save to Core Data immediately
        coreDataManager.saveFoodEntry(entry)
        
        // Update local array
        foodEntries.append(entry)
        
        // Clear form
        foodName = ""
        foodDate = Date()
        showingAddLogSheet = false
        
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteFoodEntry(entry)

        // Update local array
        foodEntries.removeAll { $0.id == entry.id }

    }

    // MARK: - Sleep Entries
    func addSleepEntry() {
        let userId = getUserId()
        let entry = SleepLogEntry(
            date: sleepDate,
            wakeUpTime: sleepWakeUpTime,
            bedTime: sleepBedTime,
            userId: userId
        )

        // Save to Core Data immediately
        coreDataManager.saveSleepEntry(entry)

        // Update local array
        sleepEntries.append(entry)

        // Clear form
        sleepDate = Date()
        sleepWakeUpTime = nil
        sleepBedTime = nil
        showingAddLogSheet = false
    }

    func deleteSleepEntry(_ entry: SleepLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteSleepEntry(entry)

        // Update local array
        sleepEntries.removeAll { $0.id == entry.id }
    }

    // MARK: - Helper Methods
    private func getUserId() -> String {
        return authManager.getEmail(for: .personal) ?? "default_user"
    }
    
    // MARK: - Date Navigation
    func goToPreviousDay() {
        currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        loadLogsForCurrentDate()
    }
    
    func goToNextDay() {
        currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        loadLogsForCurrentDate()
    }
    
    func goToToday() {
        currentDate = Date()
        loadLogsForCurrentDate()
    }
    
    // MARK: - Form Validation & Actions (for UI compatibility)
    var canAddWeight: Bool {
        guard let weight = Double(weightValue) else { return false }
        return weight > 0 && !weightValue.isEmpty
    }
    
    var canAddWorkout: Bool {
        return !workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var canAddFood: Bool {
        return !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAddSleep: Bool {
        // At least one time must be set
        return sleepWakeUpTime != nil || sleepBedTime != nil
    }

    var canAddCurrentLogType: Bool {
        switch selectedLogType {
        case .weight: return canAddWeight
        case .workout: return canAddWorkout
        case .food: return canAddFood
        case .sleep: return canAddSleep
        }
    }

    var hasEditChanges: Bool {
        guard editingEntry != nil else { return false }

        switch selectedLogType {
        case .weight:
            return weightValue != originalWeightValue ||
                   selectedWeightUnit != originalWeightUnit ||
                   weightDate != originalWeightDate
        case .workout:
            return workoutName != originalWorkoutName ||
                   workoutDate != originalWorkoutDate
        case .food:
            return foodName != originalFoodName ||
                   foodDate != originalFoodDate
        case .sleep:
            return sleepDate != originalSleepDate ||
                   sleepWakeUpTime != originalSleepWakeUpTime ||
                   sleepBedTime != originalSleepBedTime
        }
    }

    var canSaveEdit: Bool {
        canAddCurrentLogType && hasEditChanges
    }

    func addCurrentLogEntry() {
        switch selectedLogType {
        case .weight: addWeightEntry()
        case .workout: addWorkoutEntry()
        case .food: addFoodEntry()
        case .sleep: addSleepEntry()
        }
    }
    
    func resetForms() {
        weightValue = ""
        weightDate = currentDate
        workoutName = ""
        foodName = ""
        workoutDate = currentDate
        foodDate = currentDate
        sleepDate = currentDate
        sleepWakeUpTime = nil
        sleepBedTime = nil
    }
    
    // MARK: - Edit Entry Methods
    func editWeightEntry(_ entry: WeightLogEntry) {
        editingEntry = (.weight, entry.id)
        selectedLogType = .weight
        weightValue = String(entry.weight)
        selectedWeightUnit = entry.unit
        weightDate = entry.timestamp
        // Store original values for change detection
        originalWeightValue = String(entry.weight)
        originalWeightUnit = entry.unit
        originalWeightDate = entry.timestamp
        showingEditLogSheet = true
    }
    
    func editWorkoutEntry(_ entry: WorkoutLogEntry) {
        editingEntry = (.workout, entry.id)
        selectedLogType = .workout
        workoutName = entry.name
        workoutDate = entry.date
        // Store original values for change detection
        originalWorkoutName = entry.name
        originalWorkoutDate = entry.date
        showingEditLogSheet = true
    }
    
    func editFoodEntry(_ entry: FoodLogEntry) {
        editingEntry = (.food, entry.id)
        selectedLogType = .food
        foodName = entry.name
        foodDate = entry.date
        // Store original values for change detection
        originalFoodName = entry.name
        originalFoodDate = entry.date
        showingEditLogSheet = true
    }

    func editSleepEntry(_ entry: SleepLogEntry) {
        editingEntry = (.sleep, entry.id)
        selectedLogType = .sleep
        sleepDate = entry.date
        sleepWakeUpTime = entry.wakeUpTime
        sleepBedTime = entry.bedTime
        // Store original values for change detection
        originalSleepDate = entry.date
        originalSleepWakeUpTime = entry.wakeUpTime
        originalSleepBedTime = entry.bedTime
        showingEditLogSheet = true
    }

    func updateCurrentLogEntry() {
        guard let editingEntry = editingEntry else { return }

        switch editingEntry.type {
        case .weight:
            updateWeightEntry()
        case .workout:
            updateWorkoutEntry()
        case .food:
            updateFoodEntry()
        case .sleep:
            updateSleepEntry()
        }
    }
    
    private func updateWeightEntry() {
        guard let editingEntry = editingEntry,
              let weight = Double(weightValue), !weightValue.isEmpty else {
            errorMessage = "Please enter a valid weight"
            return
        }
        
        // Find and update the entry
        if let index = weightEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            let calendar = Calendar.current
            let date = calendar.startOfDay(for: weightDate)
            let time = weightDate
            
            let updatedEntry = WeightLogEntry(
                id: editingEntry.id,
                date: date,
                time: time,
                weight: weight,
                unit: selectedWeightUnit,
                userId: weightEntries[index].userId
            )
            
            // Update in Core Data
            coreDataManager.deleteWeightEntry(weightEntries[index])
            coreDataManager.saveWeightEntry(updatedEntry)
            
            // Update local array
            weightEntries[index] = updatedEntry
        }
        
        // Clear form and close sheet
        resetForms()
        showingEditLogSheet = false
        self.editingEntry = nil
    }
    
    private func updateWorkoutEntry() {
        guard let editingEntry = editingEntry,
              !workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a workout name"
            return
        }
        
        // Find and update the entry
        if let index = workoutEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            let updatedEntry = WorkoutLogEntry(
                id: editingEntry.id,
                date: workoutDate,
                name: workoutName,
                userId: workoutEntries[index].userId,
                createdAt: workoutEntries[index].createdAt
            )
            
            // Update in Core Data
            coreDataManager.deleteWorkoutEntry(workoutEntries[index])
            coreDataManager.saveWorkoutEntry(updatedEntry)
            
            // Update local array
            workoutEntries[index] = updatedEntry
        }
        
        // Clear form and close sheet
        resetForms()
        showingEditLogSheet = false
        self.editingEntry = nil
    }
    
    private func updateFoodEntry() {
        guard let editingEntry = editingEntry,
              !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a food name"
            return
        }

        // Find and update the entry
        if let index = foodEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            let updatedEntry = FoodLogEntry(
                id: editingEntry.id,
                date: foodDate,
                name: foodName,
                userId: foodEntries[index].userId,
                createdAt: foodEntries[index].createdAt
            )

            // Update in Core Data
            coreDataManager.deleteFoodEntry(foodEntries[index])
            coreDataManager.saveFoodEntry(updatedEntry)

            // Update local array
            foodEntries[index] = updatedEntry
        }

        // Clear form and close sheet
        resetForms()
        showingEditLogSheet = false
        self.editingEntry = nil
    }

    private func updateSleepEntry() {
        guard let editingEntry = editingEntry else {
            return
        }

        // Find and update the entry
        if let index = sleepEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            let updatedEntry = SleepLogEntry(
                id: editingEntry.id,
                date: sleepDate,
                wakeUpTime: sleepWakeUpTime,
                bedTime: sleepBedTime,
                userId: sleepEntries[index].userId,
                createdAt: sleepEntries[index].createdAt,
                updatedAt: Date()
            )

            // Update in Core Data
            coreDataManager.updateSleepEntry(updatedEntry)

            // Update local array
            sleepEntries[index] = updatedEntry
        }

        // Clear form and close sheet
        resetForms()
        showingEditLogSheet = false
        self.editingEntry = nil
    }

} 