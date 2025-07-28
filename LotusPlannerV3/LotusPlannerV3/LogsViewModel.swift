import Foundation
import SwiftUI

@MainActor
class LogsViewModel: ObservableObject {
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
    
    private let cloudManager = iCloudManager.shared
    private let authManager = GoogleAuthManager.shared
    
    init() {
        loadLocalData()
        setupiCloudSync()
    }
    
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
        print("📊 Loading local log data...")
        weightEntries = cloudManager.loadWeightEntries()
        workoutEntries = cloudManager.loadWorkoutEntries()
        foodEntries = cloudManager.loadFoodEntries()
        print("📊 Loaded \(weightEntries.count) weight, \(workoutEntries.count) workout, \(foodEntries.count) food entries")
    }
    
    private func setupiCloudSync() {
        NotificationCenter.default.addObserver(
            forName: .iCloudDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadLocalData()
            }
        }
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
        
        weightEntries.append(entry)
        saveWeightEntries()
        
        // Clear form
        weightValue = ""
        showingAddLogSheet = false
        
        print("✅ Added weight entry: \(weight) \(selectedWeightUnit.rawValue)")
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        weightEntries.removeAll { $0.id == entry.id }
        saveWeightEntries()
        print("🗑️ Deleted weight entry: \(entry.id)")
    }
    
    private func saveWeightEntries() {
        cloudManager.saveWeightEntries(weightEntries)
    }
    
    // MARK: - Workout Entries
    func addWorkoutEntry() {
        guard !workoutName.isEmpty else {
            errorMessage = "Please enter a workout name"
            return
        }
        
        let userId = getUserId()
        let entry = WorkoutLogEntry(date: workoutDate, name: workoutName, userId: userId)
        
        workoutEntries.append(entry)
        saveWorkoutEntries()
        
        // Clear form
        workoutName = ""
        workoutDate = Date()
        showingAddLogSheet = false
        
        print("✅ Added workout entry: \(workoutName)")
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        workoutEntries.removeAll { $0.id == entry.id }
        saveWorkoutEntries()
        print("🗑️ Deleted workout entry: \(entry.id)")
    }
    
    private func saveWorkoutEntries() {
        cloudManager.saveWorkoutEntries(workoutEntries)
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
        foodEntries.append(entry)
        print("📊 Total food entries after add: \(foodEntries.count)")
        
        saveFoodEntries()
        
        // Clear form
        foodName = ""
        foodDate = Date()
        showingAddLogSheet = false
        
        print("✅ Added food entry: \(foodName)")
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        foodEntries.removeAll { $0.id == entry.id }
        saveFoodEntries()
        print("🗑️ Deleted food entry: \(entry.id)")
    }
    
    private func saveFoodEntries() {
        print("💾 Saving \(foodEntries.count) food entries...")
        cloudManager.saveFoodEntries(foodEntries)
        print("✅ Food entries saved")
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