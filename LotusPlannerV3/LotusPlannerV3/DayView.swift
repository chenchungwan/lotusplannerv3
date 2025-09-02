import SwiftUI

enum DayViewLayout {
    case compact
    case expanded
}

struct DayView: View {
    let currentDate: Date
    let layout: DayViewLayout
    
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    
	// State for events
	@State private var dayEvents: [GoogleCalendarEvent] = []
	@State private var dayPersonalEvents: [GoogleCalendarEvent] = []
	@State private var dayProfessionalEvents: [GoogleCalendarEvent] = []
	
    // State for event details
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    
    // State for tasks
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct DayTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: DayTaskSelection?
    
    // Section width management for expanded layout
    @State private var leftSectionWidth: CGFloat = 300
    @State private var isDraggingLeftSlider = false
    
    var body: some View {
        Group {
            switch layout {
            case .compact:
                compactLayout
            case .expanded:
                expandedLayout
            }
        }
        .task {
            // Load initial data
            await tasksViewModel.loadTasks()
			dayEvents = await eventManager.getEventsForDate(currentDate)
			dayPersonalEvents = await eventManager.getPersonalEvents(for: .day(currentDate))
			dayProfessionalEvents = await eventManager.getProfessionalEvents(for: .day(currentDate))
        }
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetailsView(event: event) {
                // Handle event deletion
                selectedEvent = nil
            }
        }
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }
    
    // MARK: - Compact Layout
    private var compactLayout: some View {
        HStack(spacing: 0) {
            // Left section - Timeline
            VStack(alignment: .leading, spacing: 0) {
				TimelineBaseView(
					date: currentDate,
					events: dayEvents,
					personalEvents: dayPersonalEvents,
					professionalEvents: dayProfessionalEvents,
					personalColor: appPrefs.personalColor,
					professionalColor: appPrefs.professionalColor,
					onEventTap: { event in
						selectedEvent = event
					}
				)
            }
            .frame(width: leftSectionWidth)
            .padding(.all, 8)
            .background(Color(.systemGray6))
            
            // Divider
            Rectangle()
                .fill(isDraggingLeftSlider ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                .frame(width: 8)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingLeftSlider = true
                            let newWidth = leftSectionWidth + value.translation.width
                            leftSectionWidth = max(200, min(800, newWidth))
                        }
                        .onEnded { _ in
                            isDraggingLeftSlider = false
                        }
                )
            
            // Right section - Tasks
            ScrollView {
                VStack(spacing: 16) {
                    // Personal Tasks
                    if !personalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksViewModel.personalTaskLists,
                            tasksDict: personalTasks,
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = DayTaskSelection(task: task, listId: listId, accountKind: .personal)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                                }
                            }
                        )
                    }
                    
                    // Professional Tasks
                    if !professionalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksViewModel.professionalTaskLists,
                            tasksDict: professionalTasks,
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = DayTaskSelection(task: task, listId: listId, accountKind: .professional)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Expanded Layout
    private var expandedLayout: some View {
        HStack(spacing: 0) {
            // Left section - Timeline
			TimelineBaseView(
				date: currentDate,
				events: dayEvents,
				personalEvents: dayPersonalEvents,
				professionalEvents: dayProfessionalEvents,
				personalColor: appPrefs.personalColor,
				professionalColor: appPrefs.professionalColor,
				onEventTap: { event in
					selectedEvent = event
				}
			)
            .frame(width: UIScreen.main.bounds.width * 0.3)
            .padding(.all, 8)
            .background(Color(.systemGray6))
            
            // Middle section - Tasks
            ScrollView {
                VStack(spacing: 16) {
                    // Personal Tasks
                    if !personalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksViewModel.personalTaskLists,
                            tasksDict: personalTasks,
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = DayTaskSelection(task: task, listId: listId, accountKind: .personal)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                                }
                            }
                        )
                    }
                    
                    // Professional Tasks
                    if !professionalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksViewModel.professionalTaskLists,
                            tasksDict: professionalTasks,
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = DayTaskSelection(task: task, listId: listId, accountKind: .professional)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .frame(width: UIScreen.main.bounds.width * 0.35)
            
            // Right section - Journal
            JournalView(currentDate: currentDate, embedded: true)
                .frame(maxWidth: .infinity)
        }
    }
    
	// MARK: - Computed Properties
    
    private var personalTasks: [String: [GoogleTask]] {
        let calendar = Calendar.current
        return tasksViewModel.personalTasks.mapValues { tasks in
            tasks.filter { task in
                if let dueDate = task.dueDate {
                    return calendar.isDate(dueDate, inSameDayAs: currentDate)
                }
                return false
            }
        }
    }
    
    private var professionalTasks: [String: [GoogleTask]] {
        let calendar = Calendar.current
        return tasksViewModel.professionalTasks.mapValues { tasks in
            tasks.filter { task in
                if let dueDate = task.dueDate {
                    return calendar.isDate(dueDate, inSameDayAs: currentDate)
                }
                return false
            }
        }
    }
}

#Preview {
    DayView(currentDate: Date(), layout: .compact)
}
