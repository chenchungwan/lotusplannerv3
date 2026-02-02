# TasksComponent Customization Guide

## Overview
The `TasksComponent` is a reusable SwiftUI component that displays Google Tasks organized by task lists. It's used across multiple views in the app with different customization options to adapt its appearance and behavior to each context.

## Customization Parameters

### Required Parameters
- `taskLists: [GoogleTaskList]` - The list of task lists to display
- `tasksDict: [String: [GoogleTask]]` - Dictionary mapping list IDs to their tasks
- `accentColor: Color` - Color used for accents (account-specific: personal or professional)
- `accountType: GoogleAuthManager.AccountKind` - Either `.personal` or `.professional`
- `onTaskToggle: (GoogleTask, String) -> Void` - Callback when a task's completion status is toggled
- `onTaskDetails: (GoogleTask, String) -> Void` - Callback when a task is tapped for details

### Optional Parameters (with defaults)
- `onListRename: ((String, String) -> Void)?` - Callback for renaming a list (default: `nil`)
- `onOrderChanged: (([GoogleTaskList]) -> Void)?` - Callback when list order changes (default: `nil`)
- `hideDueDateTag: Bool` - Hide due date tags on tasks (default: `false`)
- `showEmptyState: Bool` - Show "No tasks" message when empty (default: `true`)
- `horizontalCards: Bool` - Display cards horizontally in a scrollable row (default: `false`)
- `isSingleDayView: Bool` - Optimize for single day view (default: `false`)
- `showTitle: Bool` - Show account title ("Personal Tasks" / "Professional Tasks") (default: `true`)

## How Different Views Customize TasksComponent

### 1. CalendarView (Day View) - Month Timeline
**Location:** `CalendarView.swift` lines ~1769, ~1799

**Configuration:**
- `isSingleDayView: true` - Optimized for day view
- `showTitle: false` (implicit - uses default)
- `horizontalCards: false` (implicit - uses default)
- `showEmptyState: true` (implicit - uses default)
- Uses month-filtered tasks

**Behavior:**
- Displays tasks side-by-side (Personal and Professional)
- No background container (no ScrollView wrapper)
- Flexible height, no max constraints
- Tasks sorted by completion status, due date, then alphabetically

---

### 2. CalendarView (Day View) - Single Day View
**Location:** `CalendarView.swift` lines ~4198, ~4249

**Configuration:**
- `isSingleDayView: true`
- `showTitle: true` (implicit - uses default)
- `horizontalCards: false` (implicit - uses default)
- `showEmptyState: true` (implicit - uses default)
- Uses date-filtered tasks for the current day

**Behavior:**
- Displays tasks in vertical list
- Shows account title ("Personal Tasks" / "Professional Tasks")
- Due date tags shown (only overdue tasks in single day view)
- Empty state shown when no tasks

---

### 3. TasksView (Main Tasks View)
**Location:** `TasksView.swift` lines ~1650, ~1688

**Configuration:**
- `horizontalCards: false` - Vertical layout
- `isSingleDayView: selectedFilter == .day` - Conditional based on filter
- `showTitle: true` (implicit - uses default)
- `showEmptyState: true` (implicit - uses default)
- Uses all tasks (not date-filtered)

**Behavior:**
- Displays all tasks regardless of date
- Shows account titles
- Vertical card layout
- Adapts to day/week/month filter context

---

### 4. TasksView (Compact View)
**Location:** `TasksView.swift` lines ~1995, ~2031, ~2068, ~2104

**Configuration:**
- `horizontalCards: true` - Horizontal scrolling cards
- `isSingleDayView: false` (implicit - uses default)
- `showTitle: true` (implicit - uses default)
- `showEmptyState: false` - No empty state message
- Uses date-filtered tasks

**Behavior:**
- Horizontal scrolling card layout
- Each card has fixed width (200px) and max height (300px)
- Cards are scrollable individually
- No empty state message

---

### 5. WeeklyView (Week View)
**Location:** `WeeklyView.swift` lines ~968, ~1008, ~1152, ~1194, ~1360, ~1402, ~2119, ~2160

**Configuration:**
- `hideDueDateTag: true` - Due dates hidden
- `showEmptyState: false` - No empty state
- `isSingleDayView: true` - Optimized for single day
- `showTitle: false` - No account title
- Uses date-filtered tasks for each day

**Behavior:**
- Very compact display for weekly grid
- No due date tags to save space
- No account titles
- No empty state messages
- Tasks shown per day in weekly layout

---

### 6. DayViewTimebox (Timebox Day View)
**Location:** `DayViewTimebox.swift` lines ~253, ~318

**Configuration:**
- `isSingleDayView: true`
- `showTitle: true` (implicit - uses default)
- `horizontalCards: false` (implicit - uses default)
- `showEmptyState: true` (implicit - uses default)
- Uses date-filtered tasks

**Behavior:**
- Displays tasks in middle section of timebox view
- Side-by-side Personal and Professional
- Standard vertical layout
- Shows account titles

---

### 7. DayViewClassic2 (Classic 2 Day View)
**Location:** `DayViewClassic2.swift` lines ~201, ~268

**Configuration:**
- `isSingleDayView: true`
- `showTitle: true` (implicit - uses default)
- `horizontalCards: false` (implicit - uses default)
- `showEmptyState: true` (implicit - uses default)
- Uses date-filtered tasks

**Behavior:**
- Similar to DayViewTimebox
- Displays in left section of classic 2 layout
- Standard vertical card layout

---

### 8. DayViewExpanded (Expanded Day View)
**Location:** `DayViewExpanded.swift` lines ~127, ~157

**Configuration:**
- `hideDueDateTag: false` - Due dates shown
- `showEmptyState: true`
- `horizontalCards: false`
- `isSingleDayView: true`
- Uses date-filtered tasks

**Behavior:**
- Shows due date tags
- Displays in expanded day view layout
- Standard vertical layout

---

## Key Behavioral Differences Based on Parameters

### `isSingleDayView: true`
When set to `true`:
- **Layout:** No ScrollView wrapper - flexible height, no background container
- **Due Date Tags:** Only shows overdue tasks (hides future/today dates)
- **Completed Tasks:** Doesn't show completion date for completed tasks
- **Empty State:** Shows "No tasks" message if `showEmptyState: true`

### `isSingleDayView: false`
When set to `false`:
- **Layout:** ScrollView with background styling (`.tertiarySystemBackground`, corner radius 12)
- **Due Date Tags:** Shows all due dates (Today, Tomorrow, Overdue, Future dates)
- **Completed Tasks:** Shows completion date for completed tasks
- **Empty State:** Shows "No tasks" message if `showEmptyState: true`

### `horizontalCards: true`
When set to `true`:
- **Layout:** Horizontal ScrollView with HStack of cards
- **Card Size:** Fixed width (200px), max height (300px)
- **Scrolling:** Each card has internal vertical scrolling enabled
- **Spacing:** 3px spacing between cards

### `horizontalCards: false`
When set to `false`:
- **Layout:** Vertical VStack of cards
- **Card Size:** Flexible width, no height constraints (unless `isSingleDayView: false`)
- **Scrolling:** Depends on `isSingleDayView` (see above)

### `hideDueDateTag: true`
When set to `true`:
- **Due Date Display:** Due dates are hidden via environment variable
- **Use Case:** Compact views like WeeklyView where space is limited

### `showTitle: false`
When set to `false`:
- **Account Title:** Hides "Personal Tasks" / "Professional Tasks" header
- **Use Case:** When title is redundant or space is limited

### `showEmptyState: false`
When set to `false`:
- **Empty Message:** Doesn't show "No tasks" message when all lists are empty
- **Use Case:** When parent view handles empty states or space is limited

---

## Task Filtering and Sorting

All views use the same filtering and sorting logic within `TasksComponent`:

1. **Filtering:** 
   - Respects `appPrefs.hideCompletedTasks` setting
   - Filters out completed tasks if the preference is enabled

2. **Sorting (in order):**
   - Completion status (incomplete first)
   - Due date (soonest first, no due date last)
   - Alphabetically by title

---

## Callback Functions

### `onTaskToggle`
Called when user taps the checkmark circle to toggle task completion.
- **All views:** Implement async task completion toggle
- **All views:** Update the view model with the new completion status

### `onTaskDetails`
Called when user taps on a task title.
- **All views:** Show task details sheet/modal
- **All views:** Pass task and list ID to detail view

### `onListRename`
Called when user renames a task list (optional).
- **Most views:** Implement async list rename
- **Some views:** Not provided (nil) - renaming disabled

### `onOrderChanged`
Called when task list order changes (optional).
- **Most views:** Implement async order update
- **Some views:** Not provided (nil) - reordering disabled

---

## Summary Table

| View | horizontalCards | isSingleDayView | hideDueDateTag | showTitle | showEmptyState |
|------|----------------|-----------------|----------------|-----------|----------------|
| CalendarView (Month) | false | true | false | true* | true |
| CalendarView (Day) | false | true | false | true* | true |
| TasksView (Main) | false | conditional | false | true* | true |
| TasksView (Compact) | true | false | false | true* | false |
| WeeklyView | false | true | true | false | false |
| DayViewTimebox | false | true | false | true* | true |
| DayViewClassic2 | false | true | false | true* | true |
| DayViewExpanded | false | true | false | true* | true |

*Uses default value (true)

---

## Recommendations for Future Customization

1. **Add `showDueDateTag` parameter** - Currently only `hideDueDateTag` exists, but some views might want explicit control
2. **Add `maxHeight` parameter** - Allow views to set maximum height for the component
3. **Add `cardSpacing` parameter** - Allow customization of spacing between cards
4. **Add `compactMode` parameter** - For even more compact displays
5. **Add `showListHeaders` parameter** - Allow hiding list card headers

