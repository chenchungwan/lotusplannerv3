import SwiftUI

struct CustomLogView: View {
    @ObservedObject private var customLogManager = CustomLogManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    private var enabledItems: [CustomLogItemData] {
        customLogManager.items.filter { $0.isEnabled }
    }
    
    private var entriesForDate: [CustomLogEntryData] {
        customLogManager.getEntriesForDate(navigationManager.currentDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if enabledItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    
                    Text("No custom log items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Add items in Settings > Custom Logs Items")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(enabledItems) { item in
                        CustomLogItemView(
                            item: item,
                            date: navigationManager.currentDate,
                            isCompleted: customLogManager.getCompletionStatus(for: item.id, date: navigationManager.currentDate),
                            onToggle: {
                                customLogManager.toggleEntry(for: item.id, date: navigationManager.currentDate)
                            }
                        )
                    }
                }
            }
        }
        .onChange(of: navigationManager.currentDate) { _ in
            // Refresh entries when date changes
            customLogManager.refreshData()
        }
    }
}

struct CustomLogItemView: View {
    let item: CustomLogItemData
    let date: Date
    let isCompleted: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isCompleted ? .accentColor : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                .strikethrough(isCompleted)
                .foregroundColor(isCompleted ? .secondary : .primary)
            
            Spacer()
        }
    }
}

#Preview {
    CustomLogView()
}
