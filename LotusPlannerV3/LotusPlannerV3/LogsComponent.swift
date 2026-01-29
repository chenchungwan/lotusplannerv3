import SwiftUI

struct LogsComponent: View {
    @ObservedObject private var viewModel = LogsViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    let currentDate: Date
    let horizontal: Bool
    let allowInternalScrolling: Bool
    let compactHorizontal: Bool

    init(currentDate: Date = Date(), horizontal: Bool = false, allowInternalScrolling: Bool = true, compactHorizontal: Bool = false) {
        self.currentDate = currentDate
        self.horizontal = horizontal
        self.allowInternalScrolling = allowInternalScrolling
        self.compactHorizontal = compactHorizontal
    }
    
    var body: some View {
        if appPrefs.showAnyLogs {
            VStack(alignment: .leading, spacing: 8) {
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
                    if compactHorizontal {
                        compactHorizontalLayout
                    } else if horizontal {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                // First row: Food and Sleep
                                HStack(alignment: .top, spacing: 8) {
                                    if appPrefs.showFoodLogs {
                                        foodSection
                                    }

                                    if appPrefs.showSleepLogs {
                                        sleepSection
                                    }

                                    Spacer()
                                }

                                // Second row: Water and Weight
                                HStack(alignment: .top, spacing: 8) {
                                    if appPrefs.showWaterLogs {
                                        waterSection
                                    }

                                    if appPrefs.showWeightLogs {
                                        weightSection
                                    }

                                    Spacer()
                                }

                                // Third row: Workout
                                HStack(alignment: .top, spacing: 8) {
                                    if appPrefs.showWorkoutLogs {
                                        workoutSection
                                    }

                                    Spacer()
                                }

                                // Fourth row: Custom Logs (same width as other logs)
                                if appPrefs.showCustomLogs {
                                    HStack(alignment: .top, spacing: 8) {
                                        customLogSectionHorizontal
                                        Spacer()
                                    }
                                }
                            }
                        }
                    } else {
                        // Vertical layout - conditionally scrollable based on allowInternalScrolling
                        let content = VStack(spacing: 8) {
                            // Food Section
                            if appPrefs.showFoodLogs {
                                foodSection
                            }

                            // Sleep Section
                            if appPrefs.showSleepLogs {
                                sleepSection
                            }

                            // Water Section
                            if appPrefs.showWaterLogs {
                                waterSection
                            }

                            // Weight Section
                            if appPrefs.showWeightLogs {
                                weightSection
                            }

                            // Workout Section
                            if appPrefs.showWorkoutLogs {
                                workoutSection
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
            .frame(maxWidth: .infinity, maxHeight: compactHorizontal ? nil : .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "scalemass")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Weight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if viewModel.filteredWeightEntries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.filteredWeightEntries) { entry in
                    weightEntryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    var workoutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Workout")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if viewModel.filteredWorkoutEntries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.filteredWorkoutEntries) { entry in
                    workoutEntryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    var foodSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Food")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if viewModel.filteredFoodEntries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.filteredFoodEntries) { entry in
                    foodEntryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    var waterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Water")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Interactive water cups
            WaterCupsView(
                currentDate: currentDate,
                cupsConsumed: viewModel.filteredWaterEntries.first?.cupsConsumed ?? 0,
                onUpdate: { newCups in
                    viewModel.addOrUpdateWaterEntry(cupsConsumed: newCups, date: currentDate)
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    var sleepSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "zzz")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Sleep")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if viewModel.filteredSleepEntries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.filteredSleepEntries) { entry in
                    sleepEntryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    func sleepEntryRow(_ entry: SleepLogEntry) -> some View {
        HStack(spacing: 4) {
            // Bed time - Wake time (duration) all in one line
            if let bedTime = entry.bedTime, let wakeTime = entry.wakeUpTime {
                HStack(spacing: 4) {
                    Text(formatTime(bedTime))
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatTime(wakeTime))
                        .font(.caption)
                        .fontWeight(.medium)

                    if let duration = entry.sleepDurationFormatted {
                        Text("(\(duration))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let bedTime = entry.bedTime {
                // Only bed time
                HStack(spacing: 4) {
                    Text(formatTime(bedTime))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } else if let wakeTime = entry.wakeUpTime {
                // Only wake time
                HStack(spacing: 4) {
                    Text(formatTime(wakeTime))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onTapGesture {
            viewModel.editSleepEntry(entry)
        }
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var customLogSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Custom Logs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            CustomLogView()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    var customLogSectionHorizontal: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(viewModel.accentColor)
                    .frame(width: 20, alignment: .leading)
                Text("Custom Logs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            CustomLogView()
        }
        .frame(alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Compact Horizontal Layout for Standard Day View
    var compactHorizontalLayout: some View {
        // Calculate card width to show exactly 3 cards in portrait, 5 in landscape
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let visibleCount: CGFloat = isLandscape ? 5 : 3
            let spacing: CGFloat = 12
            let horizontalPadding: CGFloat = 16

            // Calculate card width - each card takes up 1/visibleCount of the available width
            let availableWidth = geometry.size.width - horizontalPadding
            let totalSpacing = spacing * (visibleCount - 1)
            let cardWidth = (availableWidth - totalSpacing) / visibleCount

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    if appPrefs.showFoodLogs {
                        compactLogCard(section: foodSection, width: cardWidth)
                    }

                    if appPrefs.showSleepLogs {
                        compactLogCard(section: sleepSection, width: cardWidth)
                    }

                    if appPrefs.showWaterLogs {
                        compactLogCard(section: waterSection, width: cardWidth)
                    }

                    if appPrefs.showWeightLogs {
                        compactLogCard(section: weightSection, width: cardWidth)
                    }

                    if appPrefs.showWorkoutLogs {
                        compactLogCard(section: workoutSection, width: cardWidth)
                    }

                    if appPrefs.showCustomLogs {
                        compactLogCard(section: customLogSectionHorizontal, width: cardWidth)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func compactLogCard<Content: View>(section: Content, width: CGFloat) -> some View {
        section
            .frame(width: width, alignment: .top)
    }

}

// MARK: - Water Cups Interactive View
struct WaterCupsView: View {
    let currentDate: Date
    let cupsConsumed: Int
    let onUpdate: (Int) -> Void

    @State private var currentCupsConsumed: Int

    init(currentDate: Date, cupsConsumed: Int, onUpdate: @escaping (Int) -> Void) {
        self.currentDate = currentDate
        self.cupsConsumed = cupsConsumed
        self.onUpdate = onUpdate
        self._currentCupsConsumed = State(initialValue: cupsConsumed)
    }

    private let defaultCupsCount = 4
    private let columns = [
        GridItem(.fixed(24), spacing: 4),
        GridItem(.fixed(24), spacing: 4),
        GridItem(.fixed(24), spacing: 4),
        GridItem(.fixed(24), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display cups in rows of 4
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                // Show default 4 cups or more if user added more
                ForEach(0..<max(defaultCupsCount, currentCupsConsumed), id: \.self) { index in
                    Button(action: {
                        toggleCup(at: index)
                    }) {
                        Image(systemName: currentCupsConsumed > index ? "drop.fill" : "drop")
                            .font(.title2)
                            .foregroundColor(currentCupsConsumed > index ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Show + button after 4th cup or last consumed cup
                if currentCupsConsumed >= defaultCupsCount {
                    Button(action: {
                        addCup()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Display count text
            Text("\(currentCupsConsumed) cup\(currentCupsConsumed == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onChange(of: cupsConsumed) { oldValue, newValue in
            currentCupsConsumed = newValue
        }
    }

    private func toggleCup(at index: Int) {
        if currentCupsConsumed > index {
            // Unfill this cup and all cups after it
            currentCupsConsumed = index
        } else {
            // Fill up to and including this cup
            currentCupsConsumed = index + 1
        }
        onUpdate(currentCupsConsumed)
    }

    private func addCup() {
        currentCupsConsumed += 1
        onUpdate(currentCupsConsumed)
    }
}
