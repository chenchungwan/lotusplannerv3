# Goals Feature Implementation

## Overview
Added a new "Goals" view that displays goal categories in a 2x3 grid layout (6 categories total). Each category can contain multiple goals, and users can rename categories, create/edit/delete goals, and drag-and-drop categories to reorder them.

## What Was Implemented

### 1. Navigation Support
**File: `LotusPlannerV3/LotusPlannerV3/SettingsView.swift`**
- Added `.goals` case to `NavigationManager.CurrentView` enum
- Added `switchToGoals()` method to NavigationManager

### 2. Menu Item
**File: `LotusPlannerV3/LotusPlannerV3/NewUIs/GlobalNavBar.swift`**
- Added "Goals" menu item below "Lists" in the hamburger menu
- Uses "target" system icon
- Calls `navigationManager.switchToGoals()` when tapped

### 3. Goals View
**File: `LotusPlannerV3/LotusPlannerV3/GoalsView.swift` (NEW)**

Created a comprehensive view with the following features:

#### Main Features:
- **6-Grid Layout:** 2 columns x 3 rows using LazyVGrid
- **Goal Categories:** Each grid cell is a category card
- **Drag & Drop:** Categories can be reordered by dragging and dropping
- **Persistent Storage:** All data is saved to UserDefaults

#### Category Features:
Each category card includes:
- **Editable Title:** Tap the category name to rename it
- **Add Goals:** Plus button to add new goals
- **Goal List:** Scrollable list of goals within each category
- **Empty State:** Shows "No goals yet" when category is empty

#### Goal Features:
Each goal includes:
- **Checkbox:** Tap to toggle completion status
- **Editable Title:** Tap the goal text to edit it
- **Delete Button:** Trash icon to remove the goal
- **Strikethrough:** Completed goals show with strikethrough text
- **Visual Feedback:** Completed goals show with green checkmark and muted text

#### Default Categories:
The app initializes with 6 default categories:
1. Health & Fitness
2. Career
3. Personal Growth
4. Relationships
5. Finance
6. Hobbies

Users can rename any category to customize it for their needs.

### 4. Content View Integration
**File: `LotusPlannerV3/LotusPlannerV3/HomeView.swift`**
- Added `.goals` case to the navigation switch statement
- Shows GoalsView when Goals is selected

## Data Model

### Goal
```swift
struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
}
```

### GoalCategory
```swift
struct GoalCategory: Identifiable, Codable {
    let id: UUID
    var title: String
    var goals: [Goal]
    var position: Int
}
```

### GoalsViewModel
- Manages all categories and goals
- Handles CRUD operations (Create, Read, Update, Delete)
- Persists data to UserDefaults using JSON encoding
- Provides drag-and-drop state management

## How It Works

### User Flow:
1. User opens hamburger menu (☰)
2. Taps "Goals" menu item (below "Lists")
3. App displays 6 category cards in a 2x3 grid
4. User can:
   - Tap category title to rename it
   - Tap + button to add a new goal
   - Tap goal checkbox to toggle completion
   - Tap goal text to edit it
   - Tap trash icon to delete a goal
   - Long-press and drag a category card to reorder

### Data Persistence:
- All data is automatically saved to UserDefaults whenever any change is made
- Data is loaded on app launch
- Uses JSON encoding/decoding for robust data storage

## UI Design

### Grid Layout:
```
┌─────────────────────────┬─────────────────────────┐
│  Health & Fitness       │  Career                 │
│  ├─ Goal 1             │  ├─ Goal 1             │
│  ├─ Goal 2             │  ├─ Goal 2             │
│  └─ Goal 3             │  └─ Goal 3             │
├─────────────────────────┼─────────────────────────┤
│  Personal Growth        │  Relationships          │
│  ├─ Goal 1             │  ├─ Goal 1             │
│  ├─ Goal 2             │  └─ Goal 2             │
├─────────────────────────┼─────────────────────────┤
│  Finance                │  Hobbies                │
│  ├─ Goal 1             │  ├─ Goal 1             │
│  └─ Goal 2             │  ├─ Goal 2             │
│                         │  └─ Goal 3             │
└─────────────────────────┴─────────────────────────┘
```

### Category Card:
- Header with category title (tappable to edit) and + button
- Divider
- Scrollable goal list
- Rounded corners with shadow
- Secondary system background color

### Goal Row:
- Checkbox (circle/checkmark.circle.fill)
- Goal title (with strikethrough if completed)
- Delete button (trash icon)

## Technical Details

### Drag and Drop:
- Uses SwiftUI's `.onDrag()` and `.onDrop()` modifiers
- `GoalCategoryDropDelegate` handles drop logic
- Categories maintain their position when reordered
- Smooth animations during reordering

### View Model Pattern:
- `@StateObject` for GoalsViewModel in main view
- `@Published` properties for reactive updates
- Automatic save on any data change

### Responsive Design:
- LazyVGrid with flexible columns adapts to screen width
- Each category card takes 1/3 of screen height
- Scrollable content within each category
- Works on iPad and iPhone

## File Structure
```
LotusPlannerV3/
└── LotusPlannerV3/
    ├── GoalsView.swift (NEW)
    ├── SettingsView.swift (MODIFIED)
    ├── HomeView.swift (MODIFIED)
    └── NewUIs/
        └── GlobalNavBar.swift (MODIFIED)
```

## Future Enhancements (Not Implemented)
Potential features for future development:
- Goal deadlines/due dates
- Progress tracking (percentage complete)
- Goal priorities
- Sub-goals or nested goals
- Goal notes/descriptions
- Category colors/themes
- Goal templates
- Export/import goals
- Sync across devices (iCloud)
- Notifications for goal reminders

