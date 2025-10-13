import SwiftUI

struct LogsComponent: View {
    @ObservedObject private var viewModel = LogsViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    let currentDate: Date
    let horizontal: Bool
    
    init(currentDate: Date = Date(), horizontal: Bool = false) {
        self.currentDate = currentDate
        self.horizontal = horizontal
    }
    
    var body: some View {
        if appPrefs.showAnyLogs {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Logs")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Refresh button - reload data from Core Data
                    Button(action: {
                        viewModel.reloadData()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        viewModel.showingAddLogSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(viewModel.accentColor)
                    }
                }
                
                // All log sections in a scrollable view
                ScrollView {
                    if horizontal {
                        HStack(alignment: .top, spacing: 16) {
                            // Weight Section
                            if appPrefs.showWeightLogs {
                                weightSection
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                            
                            // Workout Section  
                            if appPrefs.showWorkoutLogs {
                                workoutSection
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                            
                            // Food Section
                            if appPrefs.showFoodLogs {
                                foodSection
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                            
                            // Water Section
                            if appPrefs.showWaterLogs {
                                waterSection
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            // Weight Section
                            if appPrefs.showWeightLogs {
                                weightSection
                            }
                            
                            // Workout Section  
                            if appPrefs.showWorkoutLogs {
                                workoutSection
                            }
                            
                            // Food Section
                            if appPrefs.showFoodLogs {
                                foodSection
                            }
                            
                            // Water Section
                            if appPrefs.showWaterLogs {
                                waterSection
                            }
                        }
                    }
                }
                
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
            .sheet(isPresented: $viewModel.showingAddLogSheet) {
                AddLogEntryView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingEditLogSheet) {
                EditLogEntryView(viewModel: viewModel)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                viewModel.currentDate = currentDate
                viewModel.reloadData()
                viewModel.loadLogsForCurrentDate()
            }
            .onChange(of: currentDate) { oldValue, newValue in
                viewModel.currentDate = newValue
                viewModel.loadLogsForCurrentDate()
            }
        }
    }
}

// MARK: - Log Section Views
extension LogsComponent {
    var weightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scalemass")
                    .foregroundColor(viewModel.accentColor)
                Text("Weight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if viewModel.filteredWeightEntries.isEmpty {
                Text("No weight entries for today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.filteredWeightEntries) { entry in
                    weightEntryRow(entry)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
    
    var workoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(viewModel.accentColor)
                Text("Workout")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if viewModel.filteredWorkoutEntries.isEmpty {
                Text("No workout entries for today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.filteredWorkoutEntries) { entry in
                    workoutEntryRow(entry)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
    
    var foodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundColor(viewModel.accentColor)
                Text("Food")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if viewModel.filteredFoodEntries.isEmpty {
                Text("No food entries for today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.filteredFoodEntries) { entry in
                    foodEntryRow(entry)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
    
    func weightEntryRow(_ entry: WeightLogEntry) -> some View {
        HStack(spacing: 8) {
            Text("\(entry.weight, specifier: "%.1f") \(entry.unit.displayName)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            Button(action: {
                viewModel.deleteWeightEntry(entry)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .cornerRadius(6)
        .onTapGesture {
            viewModel.editWeightEntry(entry)
        }
    }
    
    func workoutEntryRow(_ entry: WorkoutLogEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            Button(action: {
                viewModel.deleteWorkoutEntry(entry)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onTapGesture {
            viewModel.editWorkoutEntry(entry)
        }
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }
    
    func foodEntryRow(_ entry: FoodLogEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            Button(action: {
                viewModel.deleteFoodEntry(entry)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onTapGesture {
            viewModel.editFoodEntry(entry)
        }
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }
    
    var waterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(viewModel.accentColor)
                Text("Water")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Water cups display in rows of 5
            let entry = viewModel.getOrCreateWaterEntry(for: currentDate)
            let cupCount = entry.cupsFilled.count
            let totalItems = cupCount + 1 // cups + plus button
            let rows = (totalItems + 4) / 5 // Calculate number of rows needed (ceiling division)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { col in
                            let index = row * 5 + col
                            if index < cupCount {
                                // Show a cup
                                waterCupButton(index: index, isFilled: entry.cupsFilled[index])
                            } else if index == cupCount {
                                // Show the plus button
                                Button(action: {
                                    viewModel.addWaterCup(for: currentDate)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(viewModel.accentColor)
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
            
            Text("\(entry.filledCount) cups filled")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
    
    func waterCupButton(index: Int, isFilled: Bool) -> some View {
        Button(action: {
            viewModel.toggleWaterCup(at: index, for: currentDate)
        }) {
            Image(systemName: isFilled ? "drop.fill" : "drop")
                .font(.title2)
                .foregroundColor(isFilled ? .blue : .gray)
        }
    }
}