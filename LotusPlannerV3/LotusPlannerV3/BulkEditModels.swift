//
//  BulkEditModels.swift
//  LotusPlannerV3
//
//  Shared data structures for bulk edit functionality across Lists, Tasks, and Calendar views
//

import Foundation

// MARK: - Bulk Edit Action Types

enum BulkEditAction {
    case complete
    case delete
    case move
    case updateDueDate
}

// MARK: - Bulk Edit State

struct BulkEditState {
    var isActive: Bool = false
    var selectedTaskIds: Set<String> = []
    var showingCompleteConfirmation: Bool = false
    var showingDeleteConfirmation: Bool = false
    var showingMoveDestinationPicker: Bool = false
    var showingDueDatePicker: Bool = false
    var showingMoveConfirmation: Bool = false
    var showingUpdateDueDateConfirmation: Bool = false

    // Pending operation data
    var pendingMoveDestination: (listId: String, accountKind: GoogleAuthManager.AccountKind)?
    var pendingDueDate: Date?
    var pendingIsAllDay: Bool = true
    var pendingStartTime: Date?
    var pendingEndTime: Date?

    // Undo state
    var showingUndoToast: Bool = false
    var undoAction: BulkEditAction?
    var undoData: BulkEditUndoData?

    mutating func reset() {
        isActive = false
        selectedTaskIds.removeAll()
        showingCompleteConfirmation = false
        showingDeleteConfirmation = false
        showingMoveDestinationPicker = false
        showingDueDatePicker = false
        showingMoveConfirmation = false
        showingUpdateDueDateConfirmation = false
        pendingMoveDestination = nil
        pendingDueDate = nil
        pendingIsAllDay = true
        pendingStartTime = nil
        pendingEndTime = nil
    }

    mutating func clearPendingState() {
        showingCompleteConfirmation = false
        showingDeleteConfirmation = false
        showingMoveDestinationPicker = false
        showingDueDatePicker = false
        showingMoveConfirmation = false
        showingUpdateDueDateConfirmation = false
        pendingMoveDestination = nil
        pendingDueDate = nil
        pendingIsAllDay = true
        pendingStartTime = nil
        pendingEndTime = nil
    }
}

// MARK: - Undo Data

struct BulkEditUndoData {
    let tasks: [GoogleTask]
    let listId: String  // Primary list ID (for backward compatibility)
    let accountKind: GoogleAuthManager.AccountKind  // Primary account kind (for backward compatibility)
    let destinationListId: String?
    let destinationAccountKind: GoogleAuthManager.AccountKind?
    let originalDueDates: [String: String?]?
    let originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?]?
    let taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)]?  // Maps task ID to its list/account
    let count: Int
}
