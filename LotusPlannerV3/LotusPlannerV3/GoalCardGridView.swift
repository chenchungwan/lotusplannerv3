import SwiftUI

// MARK: - Goal Card Grid View (Individual Cards)
struct GoalCardGridView: View {
    let sortedCategories: [GoalCategoryData]
    let getFilteredGoals: (UUID) -> [GoalData]
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void
    /// Current navigation interval (`.week`, `.month`, `.year`). Required so
    /// the empty-state "copy from previous period" button knows what to copy.
    let currentInterval: TimelineInterval
    let currentDate: Date

    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // Empty-state copy-from-previous-period flow: confirmation + "no goals
    // found" alert. Mirrors the per-category flow in `GoalCategoryCard`.
    @State private var showingCopyAlert = false
    @State private var showingNoGoalsAlert = false

    private var isCompactDevice: Bool {
        horizontalSizeClass == .compact
    }

    private var columns: [GridItem] {
        if isCompactDevice {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.adaptive(minimum: 298, maximum: 298), spacing: 12)]
        }
    }

    /// All goals ordered by displayOrder, falling back to category position
    private var orderedGoals: [(goal: GoalData, category: GoalCategoryData)] {
        var result: [(GoalData, GoalCategoryData)] = []
        for category in sortedCategories {
            let goals = getFilteredGoals(category.id)
            for goal in goals {
                result.append((goal, category))
            }
        }
        return result.sorted(by: { (a: (goal: GoalData, category: GoalCategoryData), b: (goal: GoalData, category: GoalCategoryData)) in
            a.goal.displayOrder < b.goal.displayOrder
        })
    }

    var body: some View {
        ScrollView {
            if orderedGoals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No goals for this period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Copy-from-previous-period button. Hidden in the day
                    // view ("All Goals") since there's no notion of a
                    // previous period to copy from.
                    if currentInterval != .day {
                        Button {
                            showingCopyAlert = true
                        } label: {
                            Label(
                                "Copy from previous \(currentInterval.rawValue.lowercased())",
                                systemImage: "repeat"
                            )
                            .font(.body)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .alert("Copy Goals from Previous Period?", isPresented: $showingCopyAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Copy") {
                        copyAllGoalsFromPreviousPeriod()
                    }
                } message: {
                    Text("This will copy every \(currentInterval.rawValue.lowercased()) goal from the previous \(currentInterval.rawValue.lowercased()) into this period.")
                }
                .alert("No Goals to Copy", isPresented: $showingNoGoalsAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("There are no \(currentInterval.rawValue.lowercased()) goals in the previous period to copy.")
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(orderedGoals, id: \.goal.id) { item in
                        // Resolve tasks at THIS level where @ObservedObject tasksVM triggers re-render
                        let tasks = item.goal.linkedTasks.compactMap { linked -> GoalCardTaskInfo? in
                            for (_, tasks) in tasksVM.account1Tasks {
                                if let t = tasks.first(where: { $0.id == linked.taskId }) {
                                    return GoalCardTaskInfo(id: t.id, title: t.title, isCompleted: t.isCompleted, dueDate: t.dueDate)
                                }
                            }
                            for (_, tasks) in tasksVM.account2Tasks {
                                if let t = tasks.first(where: { $0.id == linked.taskId }) {
                                    return GoalCardTaskInfo(id: t.id, title: t.title, isCompleted: t.isCompleted, dueDate: t.dueDate)
                                }
                            }
                            return GoalCardTaskInfo(id: linked.taskId, title: linked.taskTitle ?? "Task", isCompleted: false, dueDate: nil)
                        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

                        GoalCard(
                            goal: item.goal,
                            category: item.category,
                            onTap: { onGoalTap(item.goal) },
                            onEdit: { onGoalEdit(item.goal) },
                            taskInfos: tasks
                        )
                        .draggable(item.goal.id.uuidString)
                        .dropDestination(for: String.self) { droppedItems, _ in
                            guard let droppedId = droppedItems.first,
                                  let droppedUUID = UUID(uuidString: droppedId),
                                  droppedUUID != item.goal.id else { return false }
                            reorderGoal(droppedUUID, before: item.goal.id)
                            return true
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func reorderGoal(_ draggedId: UUID, before targetId: UUID) {
        var ids = orderedGoals.map { $0.goal.id }
        guard let fromIndex = ids.firstIndex(of: draggedId),
              let toIndex = ids.firstIndex(of: targetId) else { return }
        ids.remove(at: fromIndex)
        ids.insert(draggedId, at: toIndex)
        goalsManager.updateGoalDisplayOrders(ids)
    }

    /// Copies every goal from the previous period (matching the current
    /// interval) into the current period, preserving title / description /
    /// success metric / category / linkedTasks but resetting `isCompleted`
    /// and shifting the due date forward by one period. Mirrors
    /// `GoalCategoryCard.copyGoalsFromPreviousPeriod` but operates across
    /// every category rather than a single one.
    private func copyAllGoalsFromPreviousPeriod() {
        let calendar = Calendar.mondayFirst
        let timeframe: GoalTimeframe
        let previousPeriodStart: Date
        let previousPeriodEnd: Date
        let periodShift: DateComponents

        switch currentInterval {
        case .week:
            timeframe = .week
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate),
                  let prevStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
                  let prevInterval = calendar.dateInterval(of: .weekOfYear, for: prevStart) else { return }
            previousPeriodStart = prevInterval.start
            previousPeriodEnd = prevInterval.end
            periodShift = DateComponents(weekOfYear: 1)
        case .month:
            timeframe = .month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
                  let prevStart = calendar.date(byAdding: .month, value: -1, to: monthInterval.start),
                  let prevInterval = calendar.dateInterval(of: .month, for: prevStart) else { return }
            previousPeriodStart = prevInterval.start
            previousPeriodEnd = prevInterval.end
            periodShift = DateComponents(month: 1)
        case .year:
            timeframe = .year
            guard let yearInterval = calendar.dateInterval(of: .year, for: currentDate),
                  let prevStart = calendar.date(byAdding: .year, value: -1, to: yearInterval.start),
                  let prevInterval = calendar.dateInterval(of: .year, for: prevStart) else { return }
            previousPeriodStart = prevInterval.start
            previousPeriodEnd = prevInterval.end
            periodShift = DateComponents(year: 1)
        case .day:
            return
        default:
            // Defensive: never reached today (TimelineInterval has only the
            // four cases above), but keeps the switch exhaustive if a new
            // case is added later.
            return
        }

        let previousPeriodGoals = goalsManager.goals.filter { goal in
            goal.targetTimeframe == timeframe &&
            goal.dueDate >= previousPeriodStart &&
            goal.dueDate < previousPeriodEnd
        }

        if previousPeriodGoals.isEmpty {
            showingNoGoalsAlert = true
            return
        }

        for oldGoal in previousPeriodGoals {
            guard let newDueDate = calendar.date(byAdding: periodShift, to: oldGoal.dueDate) else { continue }
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
                updatedAt: Date(),
                linkedTasks: oldGoal.linkedTasks
            )
            goalsManager.addGoal(newGoal)
        }
    }
}

