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

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCategory: GoalCategory?
    @Namespace private var dragNS
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    
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
        .navigationTitle("Goals")
        .sheet(item: $editingCategory) { cat in
            editSheet(for: cat)
        }
        .sheet(isPresented: $showingAddCategory) {
            addSheet
        }
    }
    
    private func goalCard(_ category: GoalCategory) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
            VStack {
                Text(category.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(height: 120)
        .contextMenu {
            Button("Rename") { editingCategory = category }
            Button("Delete", role: .destructive) {
                if let idx = viewModel.categories.firstIndex(of: category) {
                    viewModel.categories.remove(at: idx)
                }
            }
        }
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
            .frame(height: 120)
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

#Preview {
    GoalsView()
} 