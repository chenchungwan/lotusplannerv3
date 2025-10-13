# Logs Table Feature Implementation

## Overview
Added a new "Logs" view that displays weekly logs in a table format similar to the horizontal layout of the weekly view. Each row represents a day of the week, and each column represents a different log type (Weight, Workout, Food).

## What Was Implemented

### 1. Navigation Support
**File: `LotusPlannerV3/LotusPlannerV3/SettingsView.swift`**
- Added `.logs` case to `NavigationManager.CurrentView` enum
- Added `switchToLogs()` method to NavigationManager

### 2. Menu Item
**File: `LotusPlannerV3/LotusPlannerV3/NewUIs/GlobalNavBar.swift`**
- Added "Logs" menu item between "Lists" and "Goals" in the hamburger menu
- Uses "chart.bar.doc.horizontal" system icon
- Calls `navigationManager.switchToLogs()` when tapped

### 3. Logs Table View
**File: `LotusPlannerV3/LotusPlannerV3/LogsTableView.swift` (NEW)**

Created a comprehensive table view with the following features:

#### Main Features:
- **Table Layout:** Days of the week as rows, log types as columns
- **Week Navigation:** Previous/Next week buttons and "Today" button
- **Week Range Display:** Shows the date range of the current week
- **Dynamic Columns:** Only shows columns for enabled log types
- **Responsive Design:** Adapts to screen width and enabled log types

#### Table Structure:

**Header Row:**
- Day column (fixed width, 80pt)
- Weight column (if enabled in settings)
- Workout column (if enabled in settings)
- Food column (if enabled in settings)

**Data Rows (7 rows for each day of the week):**
- Day name (Mon, Tue, Wed, etc.) and date (M/d format)
- Weight entries: Shows weight value, unit, and time
- Workout entries: Shows workout names
- Food entries: Shows food names
- Multiple entries per day are shown on separate lines
- Empty cells show "-"
- Today's row is highlighted with blue background tint

#### Visual Design:
- Clean table grid with dividers between rows and columns
- Column headers with icons and labels
- Fixed-width day column for consistency
- Flexible-width data columns that share remaining space
- Today's row highlighted with bold text and blue tint
- Compact font sizes for table readability

### 4. Content View Integration
**File: `LotusPlannerV3/LotusPlannerV3/HomeView.swift`**
- Added `.logs` case to the navigation switch statement
- Shows LogsTableView when Logs is selected

## Data Display Format

### Weight Logs
- Format: `[weight] [unit] @ [time]`
- Example: `165.5 lbs @ 8:30 AM`
- Shows all weight entries for the day
- Multiple entries appear on separate lines

### Workout Logs
- Format: `[workout name]`
- Example: `Morning Run`
- Shows all workout names for the day
- Multiple entries appear on separate lines

### Food Logs
- Format: `[food name]`
- Example: `Oatmeal`
- Shows all food entries for the day
- Multiple entries appear on separate lines

## How It Works

### User Flow:
1. User opens hamburger menu (☰)
2. Taps "Logs" menu item (between "Lists" and "Goals")
3. App displays the current week's logs in table format
4. User can:
   - Navigate to previous/next week using arrow buttons
   - Jump to current week using "Today" button
   - View all logs for the week at a glance
   - See which days have logs and which are empty

### Data Source:
- Connects to `LogsViewModel.shared` for all log data
- Filters entries by date for each day of the week
- Respects `AppPreferences` settings for showing/hiding log types

### Week Navigation:
- Week starts on Monday (using Calendar.startOfWeek)
- Shows Monday through Sunday
- Week range displayed at top (e.g., "Jan 8 - Jan 14, 2024")
- Previous/Next buttons navigate by 7 days
- "Today" button jumps to the week containing today's date

## UI Layout

### Table Structure:
```
┌──────────────────────────────────────────────────────────────┐
│   ←  Jan 8 - Jan 14, 2024  →  [Today]                      │
├──────────┬──────────────┬──────────────┬────────────────────┤
│ Day      │ 📊 Weight    │ 🏃 Workout   │ 🍴 Food            │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Mon 1/8  │ 165.5 lbs    │ Morning Run  │ Oatmeal            │
│          │ @ 8:30 AM    │              │                    │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Tue 1/9  │ -            │ Yoga         │ Smoothie           │
│          │              │              │ Salad              │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Wed 1/10 │ 164.2 lbs    │ -            │ Chicken            │
│ (Today)  │ @ 8:00 AM    │              │                    │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Thu 1/11 │ -            │ -            │ -                  │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Fri 1/12 │ -            │ Gym          │ -                  │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Sat 1/13 │ -            │ -            │ -                  │
├──────────┼──────────────┼──────────────┼────────────────────┤
│ Sun 1/14 │ -            │ -            │ -                  │
└──────────┴──────────────┴──────────────┴────────────────────┘
```

### Visual Indicators:
- **Today's row:** Blue tint background, bold day text
- **Empty cells:** Show "-" in gray
- **Multiple entries:** Stacked vertically with line breaks
- **Column headers:** Icon + text label
- **Dividers:** Between all rows and columns

## Technical Details

### Calendar Extension:
Added `startOfWeek(for:)` method to Calendar to get the Monday of any given week:
```swift
extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
```

### View Components:
- **LogsTableView:** Main view with navigation and table
- **LogsTableRow:** Individual row for each day
- **LogCellContent:** Reusable cell content view
- Uses `@ObservedObject` for reactive updates

### Performance:
- Efficient filtering of logs by date
- LazyVStack not needed as only 7 rows always visible
- Minimal re-renders through targeted @Published properties

## Settings Integration

The table respects the user's log visibility preferences from Settings:
- Shows/hides Weight column based on `AppPreferences.showWeightLogs`
- Shows/hides Workout column based on `AppPreferences.showWorkoutLogs`
- Shows/hides Food column based on `AppPreferences.showFoodLogs`

If all log types are disabled in settings, the table will only show the day column.

## File Structure
```
LotusPlannerV3/
└── LotusPlannerV3/
    ├── LogsTableView.swift (NEW)
    ├── SettingsView.swift (MODIFIED)
    ├── HomeView.swift (MODIFIED)
    └── NewUIs/
        └── GlobalNavBar.swift (MODIFIED)
```

## Comparison with Other Views

### Similar to Weekly View:
- Horizontal layout showing 7 days
- Week navigation with previous/next buttons
- Compact representation of daily data

### Different from Daily Logs View:
- Shows entire week at once (not single day)
- Table format (not list format)
- All log types visible side-by-side
- No edit functionality in table (read-only view)

## Future Enhancements (Not Implemented)
Potential features for future development:
- Tap cells to edit logs
- Add new logs directly from table cells
- Export table to CSV/PDF
- Monthly view option (4-5 weeks at once)
- Summary row showing weekly totals/averages
- Color coding for different value ranges
- Trend indicators (arrows showing increases/decreases)
- Filter by specific log types
- Search/filter functionality

