import SwiftUI

struct CustomLogManagementView: View {
    @ObservedObject private var customLogManager = CustomLogManager.shared
    @State private var showingAddItem = false
    @State private var newItemTitle = ""
    @State private var editingItem: CustomLogItemData?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(customLogManager.items) { item in
                    CustomLogItemRow(
                        item: item,
                        onEdit: { editingItem = $0 },
                        onDelete: { customLogManager.deleteItem($0) },
                        onToggle: { customLogManager.updateItem($0) }
                    )
                }
                .onMove(perform: moveItems)
            }
            .navigationTitle("Custom Logs Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingAddItem = true
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddCustomLogItemView { title in
                let newItem = CustomLogItemData(
                    title: title,
                    displayOrder: customLogManager.items.count
                )
                    customLogManager.addItem(newItem)
                }
            }
            .sheet(item: $editingItem) { item in
                EditCustomLogItemView(item: item) { updatedItem in
                    customLogManager.updateItem(updatedItem)
                }
            }
        }
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        var reorderedItems = customLogManager.items
        reorderedItems.move(fromOffsets: source, toOffset: destination)
        
        let newOrder = reorderedItems.map { $0.id }
        customLogManager.reorderItems(newOrder)
    }
}

struct CustomLogItemRow: View {
    let item: CustomLogItemData
    let onEdit: (CustomLogItemData) -> Void
    let onDelete: (UUID) -> Void
    let onToggle: (CustomLogItemData) -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack {
            Button(action: {
                var updatedItem = item
                updatedItem.isEnabled.toggle()
                onToggle(updatedItem)
            }) {
                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(!item.isEnabled)
                    .foregroundColor(item.isEnabled ? .primary : .secondary)
                
                Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { onEdit(item) }) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(item.id)
            }
        } message: {
            Text("Are you sure you want to delete '\(item.title)'? This will also delete all associated log entries.")
        }
    }
}

struct AddCustomLogItemView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void
    
    @State private var title = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
                }
            }
            .navigationTitle("New Custom Log Item")
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

struct EditCustomLogItemView: View {
    @Environment(\.dismiss) private var dismiss
    let item: CustomLogItemData
    let onSave: (CustomLogItemData) -> Void
    
    @State private var title: String
    @State private var isEnabled: Bool
    
    init(item: CustomLogItemData, onSave: @escaping (CustomLogItemData) -> Void) {
        self.item = item
        self.onSave = onSave
        self._title = State(initialValue: item.title)
        self._isEnabled = State(initialValue: item.isEnabled)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
                    
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .navigationTitle("Edit Custom Logs Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedItem = item
                        updatedItem.title = title
                        updatedItem.isEnabled = isEnabled
                        updatedItem.updatedAt = Date()
                        onSave(updatedItem)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

#Preview {
    CustomLogManagementView()
}
