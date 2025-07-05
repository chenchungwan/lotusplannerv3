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
    
    private let firestoreManager = FirestoreManager.shared
    private let authManager = GoogleAuthManager.shared
    
    // MARK: - Computed Properties
    var weightEntries: [WeightLogEntry] {
        return firestoreManager.weightEntries.filter { entry in
            Calendar.current.isDate(entry.timestamp, inSameDayAs: currentDate)
        }
    }
    
    var workoutEntries: [WorkoutLogEntry] {
        return firestoreManager.workoutEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }
    }
    
    var foodEntries: [FoodLogEntry] {
        return firestoreManager.foodEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: currentDate)
        }
    }
    
    var accentColor: Color {
        return AppPreferences.shared.personalColor
    }
    
    // MARK: - Actions
    func loadLogsForCurrentDate() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                // First, load existing data for the current date
                async let weightEntries = firestoreManager.getWeightEntries(for: currentDate)
                async let workoutEntries = firestoreManager.getWorkoutEntries(for: currentDate)
                async let foodEntries = firestoreManager.getFoodEntries(for: currentDate)
                
                let (weights, workouts, foods) = try await (weightEntries, workoutEntries, foodEntries)
                
                // Update the FirestoreManager's published properties
                await MainActor.run {
                    firestoreManager.weightEntries = weights
                    firestoreManager.workoutEntries = workouts
                    firestoreManager.foodEntries = foods
                    
                    // Validate user security after loading
                    self.validateLogEntrySecurity()
                }
                
                // Start real-time listeners for new changes
                firestoreManager.startListening(for: currentDate)
                
                print("📊 Loaded \(weights.count) weight, \(workouts.count) workout, \(foods.count) food entries for \(currentDate)")
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load logs: \(error.localizedDescription)"
                    print("❌ Error loading logs: \(error)")
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    func addWeightEntry() {
        guard let weight = Double(weightValue), weight > 0 else {
            errorMessage = "Please enter a valid weight"
            return
        }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let userId = authManager.getEmail(for: .personal)
                print("📝 Adding weight entry for user: \(userId)")
                
                let entry = WeightLogEntry(
                    weight: weight,
                    unit: selectedWeightUnit,
                    userId: userId
                )
                
                try await firestoreManager.addWeightEntry(entry)
                print("✅ Successfully added weight entry: \(weight) \(selectedWeightUnit.displayName)")
                
                // Clear form
                weightValue = ""
                showingAddLogSheet = false
            } catch {
                errorMessage = error.localizedDescription
                print("❌ Error adding weight entry: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func addWorkoutEntry() {
        let trimmedWorkout = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedWorkout.count >= 10 else {
            errorMessage = "Workout name must be at least 10 characters"
            return
        }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let userId = authManager.getEmail(for: .personal)
                print("📝 Adding workout entry for user: \(userId)")
                
                let entry = WorkoutLogEntry(
                    date: workoutDate,
                    name: trimmedWorkout,
                    userId: userId
                )
                
                try await firestoreManager.addWorkoutEntry(entry)
                print("✅ Successfully added workout entry: \(workoutName)")
                
                // Clear form
                workoutName = ""
                workoutDate = Date()
                showingAddLogSheet = false
            } catch {
                errorMessage = error.localizedDescription
                print("❌ Error adding workout entry: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func addFoodEntry() {
        let trimmedFood = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFood.count >= 10 else {
            errorMessage = "Food name must be at least 10 characters"
            return
        }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let userId = authManager.getEmail(for: .personal)
                print("📝 Adding food entry for user: \(userId)")
                
                let entry = FoodLogEntry(
                    date: foodDate,
                    name: trimmedFood,
                    userId: userId
                )
                
                try await firestoreManager.addFoodEntry(entry)
                print("✅ Successfully added food entry: \(foodName)")
                
                // Clear form
                foodName = ""
                foodDate = Date()
                showingAddLogSheet = false
            } catch {
                errorMessage = error.localizedDescription
                print("❌ Error adding food entry: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                try await firestoreManager.deleteWeightEntry(entry.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                try await firestoreManager.deleteWorkoutEntry(entry.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                try await firestoreManager.deleteFoodEntry(entry.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
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
    
    // MARK: - Private Helper Methods
    private func validateUserAccess(for entry: any LogEntry, expectedUserId: String) -> Bool {
        let isValidUser = entry.userId == expectedUserId
        if !isValidUser {
            print("⚠️ Security Warning: Entry \(entry.id) belongs to different user: \(entry.userId), expected: \(expectedUserId)")
        }
        return isValidUser
    }
    
    private func filterEntriesByUser<T: LogEntry>(_ entries: [T]) -> [T] {
        let expectedUserId = authManager.getEmail(for: .personal)
        return entries.filter { entry in
            let isValid = validateUserAccess(for: entry, expectedUserId: expectedUserId)
            return isValid
        }
    }
    
    // MARK: - Validation Methods
    func validateLogEntrySecurity() {
        print("🔒 Validating log entry security for user: \(authManager.getEmail(for: .personal))")
        
        // Validate weight entries
        let invalidWeightEntries = weightEntries.filter { !validateUserAccess(for: $0, expectedUserId: authManager.getEmail(for: .personal)) }
        let invalidWorkoutEntries = workoutEntries.filter { !validateUserAccess(for: $0, expectedUserId: authManager.getEmail(for: .personal)) }
        let invalidFoodEntries = foodEntries.filter { !validateUserAccess(for: $0, expectedUserId: authManager.getEmail(for: .personal)) }
        
        if !invalidWeightEntries.isEmpty || !invalidWorkoutEntries.isEmpty || !invalidFoodEntries.isEmpty {
            errorMessage = "Security Warning: Some entries don't belong to current user!"
            print("❌ Found invalid entries - Weight: \(invalidWeightEntries.count), Workout: \(invalidWorkoutEntries.count), Food: \(invalidFoodEntries.count)")
        } else {
            print("✅ All entries properly filtered for current user")
        }
    }
} 