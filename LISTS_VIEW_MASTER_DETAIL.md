# Lists View - Master-Detail Layout

## New Layout (Updated)

```
┌────────────────────────────────────────────────────────────────────┐
│  ☰  ‹  MON 10/13/25  ›  [D] [W] [M] [Y] […] | 👁 ↻ +               │  ← GlobalNavBar
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌─────────────────────┬────────────────────────────────────────┐ │
│  │ Task Lists (8 Lists)│ My Tasks                    (5 Tasks) │ │  ← Headers
│  ├─────────────────────┼────────────────────────────────────────┤ │
│  │                     │                                        │ │
│  │ Personal            │  ○ Buy groceries                       │ │
│  ├─────────────────────┤     📅 Oct 14, 2025                    │ │
│  │ My Tasks         › │  ✓ Finish report                      │ │
│  │ Shopping List      │  ○ Call dentist                        │ │
│  │ Home Projects      │     📅 Oct 15, 2025                    │ │
│  │ Fitness Goals      │  ○ Review PR                           │ │
│  │ Travel Plans       │     Code review for feature X          │ │
│  │                     │     📅 Oct 13, 2025                    │ │
│  │ Professional        │  ○ Team meeting prep                   │ │
│  ├─────────────────────┤                                        │ │
│  │ Work Tasks         │                                        │ │
│  │ Project Alpha      │                                        │ │
│  │ Meetings           │                                        │ │
│  │                     │                                        │ │
│  └─────────────────────┴────────────────────────────────────────┘ │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## Layout Breakdown

### Left Column (35% width) - All Task Lists
```
┌──────────────────────┐
│ Task Lists (8 Lists) │  ← Header with total count
├──────────────────────┤
│ Personal             │  ← Section header (blue)
├──────────────────────┤
│ My Tasks          ›  │  ← Selected (highlighted)
│ Shopping List        │
│ Home Projects        │
│ Fitness Goals        │
│ Travel Plans         │
├──────────────────────┤
│ Professional         │  ← Section header (orange)
├──────────────────────┤
│ Work Tasks           │
│ Project Alpha        │
│ Meetings             │
└──────────────────────┘
```

### Right Column (65% width) - Selected List's Tasks
```
┌────────────────────────────────┐
│ My Tasks          (5 Tasks)    │  ← Selected list name + count
├────────────────────────────────┤
│ ○ Buy groceries                │
│    📅 Oct 14, 2025             │
├────────────────────────────────┤
│ ✓ Finish report                │  ← Completed task
├────────────────────────────────┤
│ ○ Call dentist                 │
│    📅 Oct 15, 2025             │
├────────────────────────────────┤
│ ○ Review PR                    │
│    Code review for feature X   │  ← Task with notes
│    📅 Oct 13, 2025             │
├────────────────────────────────┤
│ ○ Team meeting prep            │
└────────────────────────────────┘
```

## States

### Initial State (No List Selected)
```
┌──────────────────────┬────────────────────────────────┐
│ Task Lists (8 Lists) │                                │
│                      │        👆                      │
│ Personal             │    Select a List               │
│ My Tasks             │                                │
│ Shopping List        │  Tap a task list on the left   │
│ ...                  │  to view its tasks             │
│                      │                                │
└──────────────────────┴────────────────────────────────┘
```

### List Selected
```
┌──────────────────────┬────────────────────────────────┐
│ Task Lists (8 Lists) │ My Tasks          (5 Tasks)    │
│                      │                                │
│ Personal             │ ○ Task 1                       │
│ My Tasks          ›  │ ○ Task 2                       │  ← Highlighted
│ Shopping List        │ ✓ Task 3                       │
│ ...                  │ ○ Task 4                       │
│                      │ ○ Task 5                       │
└──────────────────────┴────────────────────────────────┘
```

### Empty List Selected
```
┌──────────────────────┬────────────────────────────────┐
│ Task Lists (8 Lists) │ Shopping List      (0 Tasks)   │
│                      │                                │
│ Personal             │        ✓                       │
│ My Tasks             │    No Tasks                    │
│ Shopping List     ›  │                                │
│ ...                  │  This list is empty            │
│                      │                                │
└──────────────────────┴────────────────────────────────┘
```

## Features

### Left Column Features:
- **All lists in one scrollable column**
- **Personal section** (lists personal task lists)
- **Professional section** (lists professional task lists)
- **Visual selection** (selected list is highlighted)
- **Tap to select** (tap any list to view its tasks)
- **Color coding** (personal = blue, professional = orange)
- **Total count** in header

### Right Column Features:
- **Shows tasks from selected list**
- **Task checkbox** (○ incomplete, ✓ completed)
- **Task title** (strikethrough if completed)
- **Task notes** (shown below title if present)
- **Due date** (📅 calendar icon with date)
- **Empty state** when no list selected
- **Empty list state** when list has no tasks

## Task Display

Each task shows:
```
┌────────────────────────────────────┐
│ ○ Task Title                       │  ← Checkbox + Title
│    Task notes (if any)             │  ← Notes (optional)
│    📅 Oct 13, 2025                 │  ← Due date (optional)
└────────────────────────────────────┘
```

Completed tasks:
```
┌────────────────────────────────────┐
│ ✓ Task Title                       │  ← Filled checkbox + Strikethrough
└────────────────────────────────────┘
```

## Interaction Flow

```
User opens Lists view
    ↓
Loads all task lists from both accounts
    ↓
Displays all lists in left column
    ↓
Shows "Select a List" in right column
    ↓
User taps a task list (e.g., "My Tasks")
    ↓
Left: List becomes highlighted with chevron (›)
Right: Shows all tasks from that list
    ↓
User can tap another list to switch
    ↓
Right column updates to show new list's tasks
```

## Color Scheme

### Personal Account
- **Section header background:** Blue at 10% opacity
- **Selected list background:** Blue at 15% opacity
- **List title (when selected):** Blue (bold)
- **Chevron:** Blue
- **Task header background:** Blue at 10% opacity
- **Completed task checkbox:** Blue filled

### Professional Account
- **Section header background:** Orange at 10% opacity
- **Selected list background:** Orange at 15% opacity
- **List title (when selected):** Orange (bold)
- **Chevron:** Orange
- **Task header background:** Orange at 10% opacity
- **Completed task checkbox:** Orange filled

## Advantages of This Layout

1. **Better Space Usage:** Tasks get more room (65% of screen)
2. **Clear Hierarchy:** Lists on left, details on right
3. **Single View:** All lists visible at once (Personal + Professional)
4. **Quick Navigation:** Easy to switch between lists
5. **Context Retention:** Can see both list and tasks simultaneously
6. **Familiar Pattern:** Standard master-detail layout

## Technical Details

### State Management
```swift
@State private var selectedListId: String?
@State private var selectedAccountKind: GoogleAuthManager.AccountKind?
```

### Data Flow
```
User taps list
    ↓
Updates selectedListId & selectedAccountKind
    ↓
TasksDetailColumn reads from tasksVM
    ↓
Displays tasks[listId] for that account
```

### Performance
- Lazy loading for both columns
- Efficient task filtering by list ID
- Reuses existing TasksViewModel data
- No additional API calls needed

---

**New Layout Complete!** Master-detail interface with all lists on the left and tasks on the right! 🎉

