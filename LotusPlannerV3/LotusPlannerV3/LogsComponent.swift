import SwiftUI

struct LogsComponent: View {
    @ObservedObject private var viewModel = LogsViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    let currentDate: Date
    let horizontal: Bool
    let allowInternalScrolling: Bool
    
    init(currentDate: Date = Date(), horizontal: Bool = false, allowInternalScrolling: Bool = true) {
        self.currentDate = currentDate
        self.horizontal = horizontal
        self.allowInternalScrolling = allowInternalScrolling
    }
    
    var body: some View {
        if appPrefs.showAnyLogs {
            VStack(alignment: .leading, spacing: 16) {
                // Header with + button
                HStack {
                    Text("Logs")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.showingAddLogSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(viewModel.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                
                // All log sections (scrollable only in horizontal mode)
                Group {
                    if horizontal {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // First row: Weight and Workout
                                HStack(alignment: .top, spacing: 16) {
                                    if appPrefs.showWeightLogs {
                                        weightSection
                                    }
                                    
                                    if appPrefs.showWorkoutLogs {
                                        workoutSection
                                    }
                                    
                                    Spacer()
                                }
                                
                                // Second row: Water and Food
                                HStack(alignment: .top, spacing: 16) {
                                    if appPrefs.showWaterLogs {
                                        waterSection
                                    }
                                    
                                    if appPrefs.showFoodLogs {
                                        foodSection
                                    }
                                    
                                    Spacer()
                                }
                                
                                // Third row: Custom Logs (same width as other logs)
                                if appPrefs.showCustomLogs {
                                    HStack(alignment: .top, spacing: 16) {
                                        customLogSectionHorizontal
                                        Spacer()
                                    }
                                }
                            }
                        }
                    } else {
                        // Vertical layout - conditionally scrollable based on allowInternalScrolling
                        let content = VStack(spacing: 16) {
                            // Weight Section
                            if appPrefs.showWeightLogs {
                                weightSection
                            }
                            
                            // Workout Section  
                            if appPrefs.showWorkoutLogs {
                                workoutSection
                            }
                            
                            // Water Section
                            if appPrefs.showWaterLogs {
                                waterSection
                            }
                            
                            // Food Section
                            if appPrefs.showFoodLogs {
                                foodSection
                            }
                            
                            // Custom Log Section
                            if appPrefs.showCustomLogs {
                                customLogSection
                            }
                        }
                        
                        if allowInternalScrolling {
                            ScrollView(.vertical, showsIndicators: true) {
                                content
                            }
                        } else {
                            content
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    var customLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(viewModel.accentColor)
                Text("Custom Logs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            CustomLogView()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    var customLogSectionHorizontal: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(viewModel.accentColor)
                Text("Custom Logs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            CustomLogView()
        }
        .frame(alignment: .topLeading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
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