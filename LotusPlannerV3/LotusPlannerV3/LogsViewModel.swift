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
    
    // Local storage for entries
    @Published var weightEntries: [WeightLogEntry] = []
    @Published var workoutEntries: [WorkoutLogEntry] = []
    @Published var foodEntries: [FoodLogEntry] = []
    
    private let authManager = GoogleAuthManager.shared
    private let cloudManager = iCloudManager.shared
    
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
    
    // MARK: - iCloud Storage Methods
    private func loadLocalData() {
        loadWeightEntries()
        loadWorkoutEntries()
        loadFoodEntries()
    }
    
    private func setupiCloudSync() {
        // Listen for iCloud data changes
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
    
    private func loadWeightEntries() {
        self.weightEntries = cloudManager.loadWeightEntries()
    }
    
    private func loadWorkoutEntries() {
        self.workoutEntries = cloudManager.loadWorkoutEntries()
    }
    
    private func loadFoodEntries() {
        self.foodEntries = cloudManager.loadFoodEntries()
    }
    
    private func saveWeightEntries() {
        cloudManager.saveWeightEntries(weightEntries)
    }
    
    private func saveWorkoutEntries() {
        cloudManager.saveWorkoutEntries(workoutEntries)
    }
    
    private func saveFoodEntries() {
        print("💾 Saving \(foodEntries.count) food entries to iCloud/local storage")
        cloudManager.saveFoodEntries(foodEntries)
        print("💾 Food entries save completed")
    }
    
    // MARK: - Actions
    func loadLogsForCurrentDate() {
        // Just reload local data - no network calls needed
        loadLocalData()
        print("📊 Loaded local data: \(filteredWeightEntries.count) weight, \(filteredWorkoutEntries.count) workout, \(filteredFoodEntries.count) food entries for \(currentDate)")
    }
    
    func addWeightEntry() {
        guard let weight = Double(weightValue), weight > 0 else {
            errorMessage = "Please enter a valid weight"
            return
        }
        
        let userId = authManager.getEmail(for: .personal)
        print("📝 Adding weight entry for user: \(userId)")
        
        let entry = WeightLogEntry(
            weight: weight,
            unit: selectedWeightUnit,
            userId: userId
        )
        
        weightEntries.append(entry)
        saveWeightEntries()
        
        print("✅ Successfully added weight entry: \(weight) \(selectedWeightUnit.displayName)")
        
        // Clear form
        weightValue = ""
        showingAddLogSheet = false
    }
    
    func addWorkoutEntry() {
        let trimmedWorkout = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedWorkout.count >= 10 else {
            errorMessage = "Workout name must be at least 10 characters"
            return
        }
        
        let userId = authManager.getEmail(for: .personal)
        print("📝 Adding workout entry for user: \(userId)")
        
        let entry = WorkoutLogEntry(
            date: workoutDate,
            name: trimmedWorkout,
            userId: userId
        )
        
        workoutEntries.append(entry)
        saveWorkoutEntries()
        
        print("✅ Successfully added workout entry: \(workoutName)")
        
        // Clear form
        workoutName = ""
        workoutDate = Date()
        showingAddLogSheet = false
    }
    
    func addFoodEntry() {
        let trimmedFood = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🍎 Attempting to add food entry: '\(trimmedFood)' (length: \(trimmedFood.count))")
        print("🍎 Current food entries count: \(foodEntries.count)")
        print("🍎 Current filtered food entries count: \(filteredFoodEntries.count)")
        
        guard trimmedFood.count >= 10 else {
            errorMessage = "Food name must be at least 10 characters"
            print("❌ Food entry rejected: name too short")
            return
        }
        
        let userId = authManager.getEmail(for: .personal)
        print("📝 Adding food entry for user: \(userId)")
        
        let entry = FoodLogEntry(
            date: foodDate,
            name: trimmedFood,
            userId: userId
        )
        
        print("🍎 Entry date: \(foodDate)")
        print("🍎 Current filter date: \(currentDate)")
        print("🍎 Dates match: \(Calendar.current.isDate(foodDate, inSameDayAs: currentDate))")
        
        print("🍎 Created entry: \(entry)")
        foodEntries.append(entry)
        print("🍎 Food entries count after append: \(foodEntries.count)")
        
        saveFoodEntries()
        print("🍎 Save completed. New filtered count: \(filteredFoodEntries.count)")
        
        print("✅ Successfully added food entry: \(trimmedFood)")
        
        // Clear form
        foodName = ""
        foodDate = Date()
        showingAddLogSheet = false
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        weightEntries.removeAll { $0.id == entry.id }
        saveWeightEntries()
        print("🗑️ Deleted weight entry: \(entry.id)")
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        workoutEntries.removeAll { $0.id == entry.id }
        saveWorkoutEntries()
        print("🗑️ Deleted workout entry: \(entry.id)")
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        foodEntries.removeAll { $0.id == entry.id }
        saveFoodEntries()
        print("🗑️ Deleted food entry: \(entry.id)")
    }
    
    func changeDate(to newDate: Date) {
        currentDate = newDate
        loadLogsForCurrentDate()
    }
    
    // MARK: - Form Validation
    var canAddWeight: Bool {
        guard let weight = Double(weightValue) else { return false }
        return weight > 0
    }
    
    var canAddWorkout: Bool {
        return workoutName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }
    
    var canAddFood: Bool {
        return foodName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }
    
    var canAddCurrentLogType: Bool {
        switch selectedLogType {
        case .weight: return canAddWeight
        case .workout: return canAddWorkout
        case .food: return canAddFood
        }
    }
    
    // MARK: - Form Actions
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