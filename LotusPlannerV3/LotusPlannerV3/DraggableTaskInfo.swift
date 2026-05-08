import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Drag & Drop Task Data

/// Payload carried across an in-app drag-and-drop of a task. The Tasks
/// component emits this via `.draggable(...)`; the timeline drop targets
/// (`DraggableTimeboxComponent`, `DraggableTimeboxWeekContent`,
/// `WeeklyView` per-day cells) decode it and reschedule the task.
///
/// `accountKind` is a string ("personal" / "professional") so the
/// payload is plain Codable JSON without depending on the
/// `GoogleAuthManager.AccountKind` enum at the wire level — the latter
/// can evolve without breaking already-encoded drop payloads in flight.
struct DraggableTaskInfo: Codable, Transferable {
    let taskId: String
    let listId: String
    let accountKind: String // "personal" or "professional"

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
