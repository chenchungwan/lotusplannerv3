import Foundation
import PencilKit
import SwiftUI

/// Manages auto-save functionality for journal content across all day views
@MainActor
class JournalAutoSaveManager: ObservableObject {
    static let shared = JournalAutoSaveManager()
    
    private init() {}
    
    /// Auto-save journal content for a specific date
    /// This is called when leaving any day view to ensure content is saved
    func autoSaveJournalContent(for date: Date) async {
        // The actual saving is handled by JournalView's own auto-save mechanism
        // This method serves as a central point for triggering auto-save
        // and can be extended in the future if needed
        
        // Post a notification to trigger auto-save in any active JournalView
        NotificationCenter.default.post(
            name: Notification.Name("TriggerJournalAutoSave"),
            object: nil,
            userInfo: ["date": date]
        )
    }
}
