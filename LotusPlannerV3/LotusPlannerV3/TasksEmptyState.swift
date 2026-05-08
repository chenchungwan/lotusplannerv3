import Foundation

/// Shared copy for empty-tasks placeholders. Distinguishes "the user
/// actually has tasks but they're all completed" from "there are no
/// tasks at all" — the former gets a celebratory phrasing, the latter
/// is a plain prompt. Used by `TasksComponent`, `TasksCompactComponent`,
/// and any other surface that renders a tasks list with an empty state.
enum TasksEmptyState {
    /// Returns the appropriate empty-state string for `tasks`. `tasks`
    /// should be the *unfiltered* set — i.e. include completed items so
    /// we can detect the "all done" celebration case.
    static func text(forUnfiltered tasks: [GoogleTask]) -> String {
        if !tasks.isEmpty && tasks.allSatisfy({ $0.isCompleted }) {
            return "All tasks completed 🎉"
        }
        return "No tasks"
    }
}
