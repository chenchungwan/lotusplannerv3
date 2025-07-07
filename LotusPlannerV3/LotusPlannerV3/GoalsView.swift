import SwiftUI

private enum TimelineInterval: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", quarter = "Quarter", year = "Year"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }
}

private enum TimeFilter: String, CaseIterable, Identifiable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case all = "All"
    var id: String { rawValue }
}

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCategory: GoalCategory?
    @Namespace private var dragNS
    
    @State private var selectedCategoryForAdd: GoalCategory?
    @State private var editingGoal: Goal?
    @State private var categoryPendingDelete: GoalCategory?
    
    @State private var timeFilter: TimeFilter = .all
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    
    private let cardHeight: CGFloat = UIScreen.main.bounds.height / 3
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.categories) { category in
                    goalCard(category)
                        .onDrag {
                            NSItemProvider(object: category.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: GoalDropDelegate(item: category, viewModel: viewModel))
                }
                if viewModel.categories.count < 6 {
                    addCard
                }
            }
            .padding()
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Text(titleLine)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ForEach([TimeFilter.month, .quarter, .year, .all], id: \TimeFilter.id) { tf in
                    Button(tf.rawValue) { timeFilter = tf }
                        .fontWeight(tf == timeFilter ? .bold : .regular)
                }

                Button {
                    selectedCategoryForAdd = viewModel.categories.first
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .disabled(viewModel.categories.isEmpty)
            }
        }
        .sheet(item: $editingCategory) { cat in
            editSheet(for: cat)
        }
        .sheet(isPresented: $showingAddCategory) {
            addSheet
        }
        .sheet(item: $selectedCategoryForAdd) { cat in
            GoalEditorView(mode: .new, category: cat) { desc, date, catId in
                Task { await viewModel.addGoal(description: desc, dueDate: date, categoryId: catId) }
            }
            .environmentObject(viewModel)
        }
        .sheet(item: $editingGoal) { g in
            let cat = viewModel.categories.first(where: { $0.id == g.categoryId }) ?? viewModel.categories.first!
            GoalEditorView(mode: .edit(g), category: cat, onSave: { desc, date, catId in
                var updated = g
                updated.description = desc
                updated.dueDate = date
                updated.categoryId = catId
                Task { await viewModel.updateGoal(updated) }
            }, onDelete: {
                Task { await viewModel.deleteGoal(g) }
            })
            .environmentObject(viewModel)
        }
        .alert("Delete Category?", isPresented: Binding(get: { categoryPendingDelete != nil }, set: { if !$0 { categoryPendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let cat = categoryPendingDelete {
                    let goalsToDelete = viewModel.goals.filter { $0.categoryId == cat.id }
                    for g in goalsToDelete { Task { await viewModel.deleteGoal(g) } }
                    if let idx = viewModel.categories.firstIndex(of: cat) {
                        viewModel.categories.remove(at: idx)
                    }
                    categoryPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { categoryPendingDelete = nil }
        } message: {
            Text("Deleting \(categoryPendingDelete?.name ?? "this category") will also delete all its goals. This action cannot be undone.")
        }
        #if DEBUG
        .onAppear {
            // Inject mock goals if none exist for quick UI testing
            if viewModel.goals.isEmpty, let firstCat = viewModel.categories.first {
                viewModel.goals = [
                    Goal(description: "Run 5k", dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()), categoryId: firstCat.id, userId: "debug"),
                    Goal(description: "Read a book", dueDate: nil, categoryId: firstCat.id, userId: "debug"),
                    Goal(description: "Meditate 10min", dueDate: Date(), categoryId: firstCat.id, userId: "debug")
                ]
            }
        }
        #endif
    }
    
    private func goalCard(_ category: GoalCategory) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
            VStack(alignment: .leading, spacing: 6) {
                Text(category.name)
                    .font(.title3)
                    .padding(.bottom, 2)
                    .contextMenu {
                        Button("Rename") { editingCategory = category }
                        Button("Delete", role: .destructive) { categoryPendingDelete = category }
                    }
                let goalsForCat = viewModel.goals.filter { goal in
                    guard goal.categoryId == category.id else { return false }
                    if timeFilter == .all { return true }
                    guard let due = goal.dueDate else { return false }
                    return isDue(due, within: timeFilter)
                }
                if goalsForCat.isEmpty {
                    Text("No goals yet")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(goalsForCat) { goal in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(goal.isCompleted ? .green : .secondary)
                                .onTapGesture {
                                    Task { await viewModel.toggleCompletion(goal) }
                                }
                            Text(goal.description)
                                .font(.callout)
                                .lineLimit(1)
                                .strikethrough(goal.isCompleted)
                            Spacer()
                            if let due = goal.dueDate {
                                Text(Self.shortDateFormatter.string(from: due))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingGoal = goal }
                        .contextMenu {
                            Button("Edit") { editingGoal = goal }
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.deleteGoal(goal) }
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: cardHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
    }
    
    private var addCard: some View {
        Button {
            showingAddCategory = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.blue)
                Image(systemName: "plus")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
            }
            .frame(height: cardHeight)
        }
    }
    
    private func editSheet(for category: GoalCategory) -> some View {
        NavigationStack {
            Form {
                TextField("Category Name", text: Binding(
                    get: { category.name },
                    set: { newVal in
                        viewModel.rename(category, to: newVal)
                    }))
            }
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { editingCategory = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("New Category", text: $newCategoryName)
            }
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingAddCategory = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        if !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.addCategory(name: newCategoryName)
                        }
                        newCategoryName = ""
                        showingAddCategory = false
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.categories.count >= 6)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Subtitle Helper
    private func subtitle(for filter: TimeFilter) -> String {
        let now = Date()
        let cal = Calendar.mondayFirst
        let formatter = DateFormatter()
        switch filter {
        case .all:
            return ""
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: now)
        case .quarter:
            let month = cal.component(.month, from: now)
            let year = cal.component(.year, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let startDate = cal.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))!
            let endMonth = quarterStartMonth + 2
            let endDate = cal.date(from: DateComponents(year: year, month: endMonth, day: 1))!
            formatter.dateFormat = "MMMM"
            let startStr = formatter.string(from: startDate)
            let endStr = formatter.string(from: endDate)
            return "\(startStr) - \(endStr), \(year)"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: now)
        }
    }

    private var titleLine: String {
        let sub = subtitle(for: timeFilter)
        return sub.isEmpty ? "Goals" : "Goals \(sub)"
    }
}

// Drop Delegate
struct GoalDropDelegate: DropDelegate {
    let item: GoalCategory
    let viewModel: GoalsViewModel
    func performDrop(info: DropInfo) -> Bool { return true }
    func dropEntered(info: DropInfo) {
        guard let sourceId = info.itemProviders(for: [.text]).first else { return }
        sourceId.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, _) in
            DispatchQueue.main.async {
                guard let d = data as? Data,
                      let idStr = String(data: d, encoding: .utf8),
                      let uuid = UUID(uuidString: idStr),
                      let sourceIndex = viewModel.categories.firstIndex(where: { $0.id == uuid }),
                      let destIndex = viewModel.categories.firstIndex(of: item) else { return }
                if sourceIndex != destIndex {
                    withAnimation {
                        viewModel.categories.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destIndex > sourceIndex ? destIndex+1 : destIndex)
                    }
                }
            }
        }
    }
}

// MARK: - Goals List Sheet per Category
extension GoalsView {
    struct GoalsListSheet: View {
        let category: GoalCategory
        @EnvironmentObject var viewModel: GoalsViewModel
        @State private var showNewEditor = false
        @State private var editingGoal: Goal?
        var body: some View {
            NavigationStack {
                List {
                    ForEach(viewModel.goals.filter { $0.categoryId == category.id }) { goal in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.description)
                                    .font(.body)
                                    .bold()
                                    .lineLimit(1)
                                if let due = goal.dueDate {
                                    Text(due.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                }
                            }
                            Spacer()
                        }
                        .contextMenu {
                            Button("Edit") { editingGoal = goal }
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.deleteGoal(goal) }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            let goals = viewModel.goals.filter { $0.categoryId == category.id }
                            for idx in indexSet { await viewModel.deleteGoal(goals[idx]) }
                        }
                    }
                }
                .navigationTitle(category.name)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add") { showNewEditor = true }
                    }
                }
            }
            .sheet(isPresented: $showNewEditor) {
                GoalEditorView(mode: .new, category: category) { desc, date, catId in
                    Task { await viewModel.addGoal(description: desc, dueDate: date, categoryId: catId) }
                }
                .environmentObject(viewModel)
            }
            .sheet(item: $editingGoal) { g in
                GoalEditorView(mode: .edit(g), category: category) { desc, date, catId in
                    var updated = g
                    updated.description = desc
                    updated.dueDate = date
                    updated.categoryId = catId
                    Task { await viewModel.updateGoal(updated) }
                }
                .environmentObject(viewModel)
            }
        }
    }
}

// MARK: - Date filter helper
extension GoalsView {
    private func isDue(_ date: Date, within filter: TimeFilter) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch filter {
        case .all:
            return true
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .quarter:
            let nowQuarter = (calendar.component(.month, from: now) - 1) / 3
            let dateQuarter = (calendar.component(.month, from: date) - 1) / 3
            return calendar.component(.year, from: date) == calendar.component(.year, from: now) && nowQuarter == dateQuarter
        case .year:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}

#Preview {
    GoalsView()
} 