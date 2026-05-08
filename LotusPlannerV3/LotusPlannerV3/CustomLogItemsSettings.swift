import SwiftUI

// MARK: - Custom Logs Items Inline View
struct CustomLogItemsInlineView: View {
    /// Which collection (0 or 1) this inline editor manages.
    let collectionIndex: Int

    @ObservedObject private var customLogManager = CustomLogManager.shared
    @State private var showingAddItem = false
    @State private var newItemTitle = ""
    @State private var editingItem: CustomLogItemData?

    private let maxItems = 10
    private let maxItemLength = 20

    private var collectionItems: [CustomLogItemData] {
        customLogManager.items(in: collectionIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with add button
            HStack {
                Text("Items (\(collectionItems.count)/\(maxItems))")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if collectionItems.count < maxItems {
                    Button(action: { showingAddItem = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Items list
            if collectionItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)

                    Text("No custom log items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Tap + to add your first item")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(collectionItems) { item in
                        CustomLogItemInlineRow(
                            item: item,
                            onEdit: { editingItem = $0 },
                            onDelete: { customLogManager.deleteItem($0) },
                            onToggle: { customLogManager.updateItem($0) }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddCustomLogItemInlineView(
                maxLength: maxItemLength,
                onSave: { title in
                    let newItem = CustomLogItemData(
                        title: title,
                        displayOrder: collectionItems.count,
                        collectionIndex: collectionIndex
                    )
                    customLogManager.addItem(newItem)
                }
            )
        }
        .sheet(item: $editingItem) { item in
            EditCustomLogItemInlineView(
                item: item,
                maxLength: maxItemLength,
                onSave: { updatedItem in
                    customLogManager.updateItem(updatedItem)
                }
            )
        }
    }
}

struct CustomLogItemInlineRow: View {
    let item: CustomLogItemData
    let onEdit: (CustomLogItemData) -> Void
    let onDelete: (UUID) -> Void
    let onToggle: (CustomLogItemData) -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                var updatedItem = item
                updatedItem.isEnabled.toggle()
                onToggle(updatedItem)
            }) {
                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                .strikethrough(!item.isEnabled)
                .foregroundColor(item.isEnabled ? .primary : .secondary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { onEdit(item) }) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(item.id)
            }
        } message: {
            Text("Are you sure you want to delete '\(item.title)'?")
        }
    }
}

struct AddCustomLogItemInlineView: View {
    @Environment(\.dismiss) private var dismiss
    let maxLength: Int
    let onSave: (String) -> Void
    
    @State private var title = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
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
            .navigationTitle("Add Custom Logs Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct EditCustomLogItemInlineView: View {
    @Environment(\.dismiss) private var dismiss
    let item: CustomLogItemData
    let maxLength: Int
    let onSave: (CustomLogItemData) -> Void
    
    @State private var title: String
    @State private var isEnabled: Bool
    
    init(item: CustomLogItemData, maxLength: Int, onSave: @escaping (CustomLogItemData) -> Void) {
        self.item = item
        self.maxLength = maxLength
        self.onSave = onSave
        self._title = State(initialValue: item.title)
        self._isEnabled = State(initialValue: item.isEnabled)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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


