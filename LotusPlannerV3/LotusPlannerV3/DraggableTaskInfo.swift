import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Drag & Drop Task Data

/// Payload carried across an in-app drag-and-drop of a task. The Tasks
/// component emits this via `.draggable(...)`; the timeline drop targets
/// (`DraggableTimeboxComponent`, `DraggableTimeboxWeekContent`,
/// `WeeklyView` per-day cells) decode it and reschedule the task.
///
/// `accountKind` is a string so the payload is plain Codable JSON without
/// depending on the `GoogleAuthManager.AccountKind` enum at the wire level —
/// the latter can evolve without breaking already-encoded drop payloads in
/// flight. Decode it with `AccountKind.fromStoredValue(_:)`.
struct DraggableTaskInfo: Codable, Transferable {
    let taskId: String
    let listId: String
    /// Persisted `GoogleAuthManager.AccountKind.rawValue`.
    let accountKind: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
