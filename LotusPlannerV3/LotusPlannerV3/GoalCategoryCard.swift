import SwiftUI

// MARK: - Goal Category Card
struct GoalCategoryCard: View {
    let category: GoalCategoryData
    let goals: [GoalData]
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void
    let onGoalDelete: (GoalData) -> Void
    let onCategoryEdit: (GoalCategoryData) -> Void
    let onCategoryDelete: (GoalCategoryData) -> Void
    let showTags: Bool
    let currentInterval: TimelineInterval
    let currentDate: Date
    let showQuickAdd: Bool
    
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingCopyAlert = false
    @State private var showingNoGoalsAlert = false
    @State private var isAddingQuickGoal = false
    @State private var newGoalTitle = ""
    @FocusState private var isQuickGoalFieldFocused: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 12
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 6 : 8
    }
    
    // Computed properties for better performance
    private var completedGoalsCount: Int {
        goals.filter { $0.isCompleted }.count
    }
    
    private var totalGoalsCount: Int {
        goals.count
    }
    
    // Check if we should show the repeat icon
    private var shouldShowRepeatIcon: Bool {
        // Only show in week, month, year views (not day view which is "All Goals")
        // Always show the icon to allow repeated copying from previous period
        return currentInterval != .day
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: adaptiveSpacing) {
            // Header with title
            HStack {
                if isEditingTitle {
                    TextField("Category name", text: $editedTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveCategoryTitle()
                        }
                } else {
                    Text("\(category.title) (\(totalGoalsCount))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .onTapGesture {
                            startEditingTitle()
                        }
                }
                
                Spacer()
                
                if isEditingTitle {
                    Button("Save") {
                        saveCategoryTitle()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                // Repeat icon to copy goals from previous period
                if shouldShowRepeatIcon {
                    Button(action: {
                        showingCopyAlert = true
                    }) {
                        Image(systemName: "repeat")
                            .font(.body) // Larger for better tap target
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, adaptivePadding)
            .padding(.top, adaptivePadding)
            
            Divider()
            
            // Goals list
            ScrollView {
                LazyVStack(spacing: adaptiveSpacing) {
                    ForEach(goals) { goal in
                        GoalRow(
                            goal: goal,
                            onTap: { 
                                goalsManager.toggleGoalCompletion(goal.id)
                            },
                            onEdit: { onGoalEdit(goal) },
                            onDelete: { onGoalDelete(goal) },
                            showTags: showTags
                        )
                    }
                    
                    if goals.isEmpty {
                        Text("No goals yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                    
                    if showQuickAdd {
                        quickAddGoalRow
                    }
                }
                .padding(.horizontal, adaptivePadding / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .onChange(of: showQuickAdd) { value in
            if !value {
                cancelQuickGoalInline()
            }
        }
        .alert("Copy Goals from Previous Period?", isPresented: $showingCopyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Copy", role: .none) {
                copyGoalsFromPreviousPeriod()
            }
        } message: {
            Text("This will copy all \(currentInterval.rawValue.lowercased()) goals from the previous \(currentInterval.rawValue.lowercased()) to this period. Your existing goals will be kept. Are you sure?")
        }
        .alert("No Goals to Copy", isPresented: $showingNoGoalsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There are no \(currentInterval.rawValue.lowercased()) goals in the previous period to copy.")
        }
    }
    
    @ViewBuilder
    private var quickAddGoalRow: some View {
        if isAddingQuickGoal {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                TextField("New goal", text: $newGoalTitle)
                    .font(.body)
                    .focused($isQuickGoalFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        createQuickGoalInline()
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isQuickGoalFieldFocused = true
                        }
                    }
                
                Button {
                    cancelQuickGoalInline()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel quick goal")
            }
            .padding(adaptivePadding)
        } else {
            Button {
                isAddingQuickGoal = true
                newGoalTitle = ""
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Text("New goal")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(adaptivePadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add quick goal")
        }
    }
    
    private func cancelQuickGoalInline() {
        isAddingQuickGoal = false
        newGoalTitle = ""
        isQuickGoalFieldFocused = false
    }
    
    private func createQuickGoalInline() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelQuickGoalInline()
            return
        }
        
        let timeframe = convertToGoalTimeframe(currentInterval)
        let dueDate = quickGoalDueDate(for: timeframe)
        
        let newGoal = GoalData(
            title: trimmed,
            description: "",
            successMetric: "",
            categoryId: category.id,
            targetTimeframe: timeframe,
            dueDate: dueDate,
            isCompleted: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        goalsManager.addGoal(newGoal)
        cancelQuickGoalInline()
    }
    
    private func quickGoalDueDate(for timeframe: GoalTimeframe) -> Date {
        switch timeframe {
        case .week:
            return GoalData.calculateDueDate(for: .week, from: currentDate)
        case .month:
            return GoalData.calculateDueDate(for: .month, from: currentDate)
        case .year:
            return GoalData.calculateDueDate(for: .year, from: currentDate)
        }
    }
    
    private func startEditingTitle() {
        editedTitle = category.title
        isEditingTitle = true
    }
    
    private func saveCategoryTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var updatedCategory = category
            updatedCategory.title = trimmed
            updatedCategory.updatedAt = Date()
            onCategoryEdit(updatedCategory)
        }
        isEditingTitle = false
    }
    
    private func copyGoalsFromPreviousPeriod() {
        let calendar = Calendar.mondayFirst
        
        // Calculate previous period based on current interval
        let previousPeriodStart: Date
        let previousPeriodEnd: Date
        
        switch currentInterval {
        case .week:
            // Get previous week
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate),
                  let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
                  let prevWeekInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekStart) else {
                return
            }
            previousPeriodStart = prevWeekInterval.start
            previousPeriodEnd = prevWeekInterval.end
            
        case .month:
            // Get previous month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
                  let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthInterval.start),
                  let prevMonthInterval = calendar.dateInterval(of: .month, for: prevMonthStart) else {
                return
            }
            previousPeriodStart = prevMonthInterval.start
            previousPeriodEnd = prevMonthInterval.end
            
        case .year:
            // Get previous year
            guard let yearInterval = calendar.dateInterval(of: .year, for: currentDate),
                  let prevYearStart = calendar.date(byAdding: .year, value: -1, to: yearInterval.start),
                  let prevYearInterval = calendar.dateInterval(of: .year, for: prevYearStart) else {
                return
            }
            previousPeriodStart = prevYearInterval.start
            previousPeriodEnd = prevYearInterval.end
            
        case .day:
            return // Should not happen due to shouldShowRepeatIcon check
        }
        
        // Get all goals from previous period for this category with matching timeframe type
        let previousPeriodGoals = goalsManager.goals.filter { goal in
            goal.categoryId == category.id &&
            goal.targetTimeframe == convertToGoalTimeframe(currentInterval) &&
            goal.dueDate >= previousPeriodStart &&
            goal.dueDate < previousPeriodEnd
        }
        
        // Check if there are any goals to copy
        if previousPeriodGoals.isEmpty {
            // Show alert that no goals were found
            showingNoGoalsAlert = true
            return
        }
        
        // Calculate the new due date (shift by one period forward)
        let periodShift: DateComponents
        switch currentInterval {
        case .week:
            periodShift = DateComponents(weekOfYear: 1)
        case .month:
            periodShift = DateComponents(month: 1)
        case .year:
            periodShift = DateComponents(year: 1)
        case .day:
            return
        }
        
        // Copy each goal to the current period
        for oldGoal in previousPeriodGoals {
            guard let newDueDate = calendar.date(byAdding: periodShift, to: oldGoal.dueDate) else {
                continue
            }
            
            // Create new goal with same properties but new due date and not completed
            let newGoal = GoalData(
                id: UUID(),
                title: oldGoal.title,
                description: oldGoal.description,
                successMetric: oldGoal.successMetric,
                categoryId: oldGoal.categoryId,
                targetTimeframe: oldGoal.targetTimeframe,
                dueDate: newDueDate,
                isCompleted: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            goalsManager.addGoal(newGoal)
        }
        
        // Post notification to refresh All Goals view
        NotificationCenter.default.post(name: .refreshAllGoalsView, object: nil)
    }
    
    private func convertToGoalTimeframe(_ interval: TimelineInterval) -> GoalTimeframe {
        switch interval {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        case .day:
            return .week // Fallback, shouldn't happen
        }
    }
}

