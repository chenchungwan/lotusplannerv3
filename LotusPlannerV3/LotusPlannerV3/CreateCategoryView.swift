import SwiftUI

// MARK: - Create Category View
struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    @State private var title = ""
    @State private var selectedPosition = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Category name", text: $title)
                }
                
                Section("Position") {
                    Picker("Position in grid", selection: $selectedPosition) {
                        ForEach(0..<6, id: \.self) { position in
                            let row = position / 2
                            let col = position % 2
                            Text("Row \(row + 1), Column \(col + 1)").tag(position)
                        }
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func saveCategory() {
        goalsManager.addCategory(title: title, displayPosition: selectedPosition)
        dismiss()
    }
}

