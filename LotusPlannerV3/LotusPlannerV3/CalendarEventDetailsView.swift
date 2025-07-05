import SwiftUI

struct CalendarEventDetailsView: View {
    let event: GoogleCalendarEvent
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String
    @State private var editedDescription: String
    
    init(event: GoogleCalendarEvent, onDelete: @escaping () -> Void) {
        self.event = event
        self.onDelete = onDelete
        _editedTitle = State(initialValue: event.summary)
        _editedDescription = State(initialValue: event.description ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $editedTitle)
                    TextField("Description", text: $editedDescription, axis: .vertical)
                }
                if let start = event.startTime, let end = event.endTime {
                    Section("Time") {
                        Text("Start: \(start.formatted(date: .abbreviated, time: .shortened))")
                        Text("End: \(end.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                Section {
                    Button("Delete Event", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
} 