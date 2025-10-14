import Foundation
import SwiftUI

@MainActor
class LogsViewModel: ObservableObject {
    static let shared = LogsViewModel()
    
    private init() {
        loadLocalData()
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
    
    // Local data storage
    @Published var weightEntries: [WeightLogEntry] = []
    @Published var workoutEntries: [WorkoutLogEntry] = []
    @Published var foodEntries: [FoodLogEntry] = []
    @Published var waterEntries: [WaterLogEntry] = []
    
    private let coreDataManager = CoreDataManager.shared
    private let authManager = GoogleAuthManager.shared
    
    // MARK: - Computed Properties
    var filteredWeightEntries: [WeightLogEntry] {
        return weightEntries.filter { entry in
            Calendar.current.isDate(entry.timestamp, inSameDayAs: currentDate)
        }.sorted { $0.timestamp > $1.timestamp }  // Newest first
    }
    
    var filteredWorkoutEntries: [WorkoutLogEntry] {
        return workoutEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }.sorted { $0.createdAt > $1.createdAt }  // Newest first
    }
    
    var filteredFoodEntries: [FoodLogEntry] {
        return foodEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }.sorted { $0.createdAt > $1.createdAt }  // Newest first
    }
    
    var filteredWaterEntries: [WaterLogEntry] {
        return waterEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }.sorted { $0.createdAt > $1.createdAt }  // Newest first
    }
    
    var accentColor: Color {
        return AppPreferences.shared.personalColor
    }
    
    // MARK: - Data Loading and Syncing
    private func loadLocalData() {
        
        weightEntries = coreDataManager.loadWeightEntries()
        workoutEntries = coreDataManager.loadWorkoutEntries()
        foodEntries = coreDataManager.loadFoodEntries()
        waterEntries = coreDataManager.loadWaterEntries()
        
    }
    
    private func setupiCloudSync() {}
    
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
    
    var canAddCurrentLogType: Bool {
        switch selectedLogType {
        case .weight: return canAddWeight
        case .workout: return canAddWorkout
        case .food: return canAddFood
        case .water: return true // Water is handled differently (cup toggling)
        }
    }
    
    func addCurrentLogEntry() {
        switch selectedLogType {
        case .weight: addWeightEntry()
        case .workout: addWorkoutEntry()
        case .food: addFoodEntry()
        case .water: break // Water is handled differently (cup toggling)
        }
    }
    
    func resetForms() {
        weightValue = ""
        weightDate = currentDate
        workoutName = ""
        foodName = ""
        workoutDate = currentDate
        foodDate = currentDate
    }
    
    // MARK: - Edit Entry Methods
    func editWeightEntry(_ entry: WeightLogEntry) {
        editingEntry = (.weight, entry.id)
        selectedLogType = .weight
        weightValue = String(entry.weight)
        selectedWeightUnit = entry.unit
        weightDate = entry.timestamp
        showingEditLogSheet = true
    }
    
    func editWorkoutEntry(_ entry: WorkoutLogEntry) {
        editingEntry = (.workout, entry.id)
        selectedLogType = .workout
        workoutName = entry.name
        workoutDate = entry.date
        showingEditLogSheet = true
    }
    
    func editFoodEntry(_ entry: FoodLogEntry) {
        editingEntry = (.food, entry.id)
        selectedLogType = .food
        foodName = entry.name
        foodDate = entry.date
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
        case .water:
            break // Water is handled differently (cup toggling)
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
    
    // MARK: - Water Entries
    func getOrCreateWaterEntry(for date: Date) -> WaterLogEntry {
        // Check if we already have a water entry for this date
        if let existingEntry = waterEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return existingEntry
        }
        
        // Create a new entry
        let userId = getUserId()
        let entry = WaterLogEntry(date: date, userId: userId)
        coreDataManager.saveWaterEntry(entry)
        waterEntries.append(entry)
        return entry
    }
    
    func toggleWaterCup(at index: Int, for date: Date) {
        var entry = getOrCreateWaterEntry(for: date)
        
        // Ensure the array is large enough
        while entry.cupsFilled.count <= index {
            entry.cupsFilled.append(false)
        }
        
        // Toggle the cup
        entry.cupsFilled[index].toggle()
        
        // Update in Core Data and local array
        updateWaterEntry(entry)
    }
    
    func addWaterCup(for date: Date) {
        var entry = getOrCreateWaterEntry(for: date)
        entry.cupsFilled.append(false)
        updateWaterEntry(entry)
    }
    
    private func updateWaterEntry(_ entry: WaterLogEntry) {
        // Find and update the entry
        if let index = waterEntries.firstIndex(where: { $0.id == entry.id }) {
            // Update in Core Data
            coreDataManager.deleteWaterEntry(waterEntries[index])
            coreDataManager.saveWaterEntry(entry)
            
            // Update local array
            waterEntries[index] = entry
        }
    }
    
    func deleteWaterEntry(_ entry: WaterLogEntry) {
        coreDataManager.deleteWaterEntry(entry)
        if let index = waterEntries.firstIndex(where: { $0.id == entry.id }) {
            waterEntries.remove(at: index)
        }
    }
} 