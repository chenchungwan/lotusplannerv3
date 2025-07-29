import Foundation
import SwiftUI

@MainActor
class LogsViewModel: ObservableObject {
    static let shared = LogsViewModel()
    
    private init() {
        print("🚀 LogsViewModel singleton initializing...")
        setupiCloudSync()
        loadLocalData()
    }
    
    // Reload data from Core Data
    func reloadData() {
        print("🔄 Reloading data from Core Data...")
        loadLocalData()
    }
    

    @Published var selectedLogType: LogType = .weight
    @Published var currentDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddLogSheet = false
    
    // Weight entry form
    @Published var weightValue = ""
    @Published var selectedWeightUnit: WeightUnit = .pounds
    
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
    
    private let coreDataManager = CoreDataManager.shared
    private let authManager = GoogleAuthManager.shared
    
    // MARK: - Computed Properties
    var filteredWeightEntries: [WeightLogEntry] {
        return weightEntries.filter { entry in
            Calendar.current.isDate(entry.timestamp, inSameDayAs: currentDate)
        }
    }
    
    var filteredWorkoutEntries: [WorkoutLogEntry] {
        return workoutEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }
    }
    
    var filteredFoodEntries: [FoodLogEntry] {
        return foodEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }
    }
    
    var accentColor: Color {
        return AppPreferences.shared.personalColor
    }
    
    // MARK: - Data Loading and Syncing
    private func loadLocalData() {
        print("📊 Loading local log data from Core Data...")
        
        weightEntries = coreDataManager.loadWeightEntries()
        workoutEntries = coreDataManager.loadWorkoutEntries()
        foodEntries = coreDataManager.loadFoodEntries()
        
        print("📊 Loaded \(weightEntries.count) weight, \(workoutEntries.count) workout, \(foodEntries.count) food entries")
    }
    
    private func setupiCloudSync() {
        // Core Data with CloudKit handles sync automatically
        // No manual sync setup needed
    }
    
    func loadLogsForCurrentDate() {
        // Data is already loaded locally, just filter for current date
        // This method is kept for compatibility with existing UI
        print("📊 Displaying logs for date: \(currentDate)")
        print("📊 Found \(filteredWeightEntries.count) weight, \(filteredWorkoutEntries.count) workout, \(filteredFoodEntries.count) food entries")
    }
    
    // MARK: - Weight Entries
    func addWeightEntry() {
        guard let weight = Double(weightValue), !weightValue.isEmpty else {
            errorMessage = "Please enter a valid weight"
            return
        }
        
        let userId = getUserId()
        let entry = WeightLogEntry(weight: weight, unit: selectedWeightUnit, userId: userId)
        
        // Save to Core Data immediately
        coreDataManager.saveWeightEntry(entry)
        
        // Update local array
        weightEntries.append(entry)
        
        // Clear form
        weightValue = ""
        showingAddLogSheet = false
        
        print("✅ Added weight entry: \(weight) \(selectedWeightUnit.rawValue)")
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteWeightEntry(entry)
        
        // Update local array
        weightEntries.removeAll { $0.id == entry.id }
        
        print("🗑️ Deleted weight entry: \(entry.id)")
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
        
        print("✅ Added workout entry: \(workoutName)")
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteWorkoutEntry(entry)
        
        // Update local array
        workoutEntries.removeAll { $0.id == entry.id }
        
        print("🗑️ Deleted workout entry: \(entry.id)")
    }
    
    // MARK: - Food Entries
    func addFoodEntry() {
        guard !foodName.isEmpty else {
            errorMessage = "Please enter a food name"
            return
        }
        
        let userId = getUserId()
        let entry = FoodLogEntry(date: foodDate, name: foodName, userId: userId)
        
        print("🍎 Adding food entry: \(foodName) for date: \(foodDate)")
        
        // Save to Core Data immediately
        coreDataManager.saveFoodEntry(entry)
        
        // Update local array
        foodEntries.append(entry)
        print("📊 Total food entries after add: \(foodEntries.count)")
        
        // Clear form
        foodName = ""
        foodDate = Date()
        showingAddLogSheet = false
        
        print("✅ Added food entry: \(foodName)")
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        // Delete from Core Data
        coreDataManager.deleteFoodEntry(entry)
        
        // Update local array
        foodEntries.removeAll { $0.id == entry.id }
        
        print("🗑️ Deleted food entry: \(entry.id)")
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
        }
    }
    
    func addCurrentLogEntry() {
        switch selectedLogType {
        case .weight: addWeightEntry()
        case .workout: addWorkoutEntry()
        case .food: addFoodEntry()
        }
    }
    
    func resetForms() {
        weightValue = ""
        workoutName = ""
        foodName = ""
        workoutDate = currentDate
        foodDate = currentDate
    }
} 