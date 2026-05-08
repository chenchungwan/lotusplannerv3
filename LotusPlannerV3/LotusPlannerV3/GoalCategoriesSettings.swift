import SwiftUI

// MARK: - Goal Categories Inline View
struct GoalCategoriesInlineView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var showingAddCategory = false
    @State private var editingCategory: GoalCategoryData?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goal Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if goalsManager.canAddCategory {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Max \(GoalsManager.maxCategories)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if goalsManager.categories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    
                    Text("No goal categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Tap + to add your first category")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })) { category in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.body)
                            
                            Text(category.title)
                                .font(.body)
                            
                            Spacer()
                            
                            let goalCount = goalsManager.getGoalsForCategory(category.id).count
                            Text("\(goalCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            
                            Button {
                                editingCategory = category
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddGoalCategorySheet { title in
                goalsManager.addCategory(title: title)
            }
        }
        .sheet(item: $editingCategory) { category in
            EditGoalCategorySheet(category: category) { updatedCategory in
                goalsManager.updateCategory(updatedCategory)
            } onDelete: {
                goalsManager.deleteCategory(category.id)
            }
        }
    }
}

// MARK: - Add Goal Category Sheet
struct AddGoalCategorySheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    
    private let maxLength = 50
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Goal Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundColor(!title.isEmpty ? .accentColor : .secondary)
                    .opacity(!title.isEmpty ? 1.0 : 0.5)
                }
            }
        }
    }
}

// MARK: - Edit Goal Category Sheet
struct EditGoalCategorySheet: View {
    let category: GoalCategoryData
    let onSave: (GoalCategoryData) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var showingDeleteAlert = false
    
    private let maxLength = 50
    
    init(category: GoalCategoryData, onSave: @escaping (GoalCategoryData) -> Void, onDelete: @escaping () -> Void) {
        self.category = category
        self.onSave = onSave
        self.onDelete = onDelete
        self._title = State(initialValue: category.title)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Category")
                        }
                    }
                }
            }
            .navigationTitle("Edit Goal Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedCategory = category
                        updatedCategory.title = title
                        updatedCategory.updatedAt = Date()
                        onSave(updatedCategory)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .alert("Delete Category?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will delete the category and all goals in it. This action cannot be undone.")
            }
        }
    }
}
