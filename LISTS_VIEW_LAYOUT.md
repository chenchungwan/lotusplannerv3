# Lists View Layout

## Visual Structure

```
┌────────────────────────────────────────────────────────────────┐
│  ☰  ‹  MON 10/13/25  ›  [D] [W] [M] [Y] […] | 👁 ↻ +           │  ← GlobalNavBar
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────────────────┬──────────────────────────┐      │
│  │ Personal       (5 Lists) │ Professional    (3 Lists)│      │  ← Headers
│  ├──────────────────────────┼──────────────────────────┤      │
│  │                          │                          │      │
│  │ 📋 My Tasks             │ 📋 Work Tasks           │      │
│  │    Updated: Oct 13...   │    Updated: Oct 12...   │      │
│  │                      ›   │                      ›   │      │
│  ├──────────────────────────┼──────────────────────────┤      │
│  │                          │                          │      │
│  │ 📋 Shopping List        │ 📋 Project Alpha        │      │
│  │    Updated: Oct 12...   │    Updated: Oct 10...   │      │
│  │                      ›   │                      ›   │      │
│  ├──────────────────────────┼──────────────────────────┤      │
│  │                          │                          │      │
│  │ 📋 Home Projects        │ 📋 Meetings             │      │
│  │    Updated: Oct 11...   │    Updated: Oct 9...    │      │
│  │                      ›   │                      ›   │      │
│  ├──────────────────────────┼──────────────────────────┤      │
│  │                          │                          │      │
│  │ 📋 Fitness Goals        │                          │      │
│  │    Updated: Oct 10...   │                          │      │
│  │                      ›   │                          │      │
│  ├──────────────────────────┤                          │      │
│  │                          │                          │      │
│  │ 📋 Travel Plans         │                          │      │
│  │    Updated: Oct 9...    │                          │      │
│  │                      ›   │                          │      │
│  └──────────────────────────┴──────────────────────────┘      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Layout Variations

### Both Accounts Linked (Default)
```
┌─────────────────────────────────┬─────────────────────────────────┐
│        Personal (50%)           │      Professional (50%)         │
│  - List 1                       │  - List A                       │
│  - List 2                       │  - List B                       │
│  - List 3                       │  - List C                       │
└─────────────────────────────────┴─────────────────────────────────┘
```

### Only Personal Account
```
┌─────────────────────────────────────────────────────────────────┐
│                    Personal (100%)                              │
│  - List 1                                                       │
│  - List 2                                                       │
│  - List 3                                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Only Professional Account
```
┌─────────────────────────────────────────────────────────────────┐
│                  Professional (100%)                            │
│  - List A                                                       │
│  - List B                                                       │
│  - List C                                                       │
└─────────────────────────────────────────────────────────────────┘
```

### No Accounts Linked
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    ⚠️                                           │
│       No Google Accounts Linked                                │
│                                                                 │
│  Please link your Google account in                            │
│  Settings to view your task lists.                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Empty Task Lists
```
┌─────────────────────────────────┬─────────────────────────────────┐
│        Personal (0 Lists)       │   Professional (0 Lists)        │
│                                 │                                 │
│         📂                      │         📂                      │
│    No Task Lists                │    No Task Lists                │
│                                 │                                 │
│  Create a task list in          │  Create a task list in          │
│  Google Tasks to see it here.   │  Google Tasks to see it here.   │
│                                 │                                 │
└─────────────────────────────────┴─────────────────────────────────┘
```

## Component Breakdown

### TaskListRow
Each row displays:
```
┌──────────────────────────────────────────────┐
│ 📋  List Title                            ›  │
│     Updated: Oct 13, 2025 at 2:30 PM        │
└──────────────────────────────────────────────┘
```

Elements:
- `📋` Icon (colored with account's accent color)
- **List Title** (Medium weight font)
- **Updated date** (Small, secondary color)
- `›` Chevron (for future detail navigation)

### TaskListColumn Header
```
┌──────────────────────────────────────────────┐
│ Personal                    5 Lists          │  ← Light background
└──────────────────────────────────────────────┘
```

Elements:
- **Account Name** (Title2, Bold, Accent color)
- **Count** (Caption, Secondary color)
- Background tinted with account's accent color (10% opacity)

## Color Scheme

### Personal Account
- Accent: `appPrefs.personalColor` (typically blue)
- Header background: Personal color at 10% opacity
- Icon: Personal color
- Text: Primary/Secondary based on hierarchy

### Professional Account
- Accent: `appPrefs.professionalColor` (typically orange)
- Header background: Professional color at 10% opacity
- Icon: Professional color
- Text: Primary/Secondary based on hierarchy

## Menu Integration

The Lists item appears in the hamburger menu:

```
☰ Menu
├─ Calendar      📅
├─ Tasks         ✓
├─ Lists         📋  ← NEW
├─────────────────
├─ Settings      ⚙️
├─ About         ℹ️
└─ Report Issue  🐛
```

## Navigation Flow

```
Start
  │
  ├─ Open hamburger menu
  │     │
  │     ├─ Tap "Lists"
  │     │     │
  │     │     └─ Load task lists
  │     │           │
  │     │           ├─ Show loading indicator
  │     │           │
  │     │           ├─ Fetch data from Google Tasks API
  │     │           │
  │     │           └─ Display in two-column layout
  │     │
  │     └─ Return to previous view
  │
  └─ Continue using app
```

## Interaction States

### Loading
```
┌─────────────────────────────────────────────┐
│                                             │
│              ⏳                             │
│       Loading Task Lists...                │
│                                             │
└─────────────────────────────────────────────┘
```

### Loaded
- Scrollable columns
- Each list is tappable (prepared for future detail view)
- Dividers between lists

### Error State
- Falls back to showing empty state
- Error message appears in console (for debugging)

## Responsive Design

### Wide Screen (iPad, Mac)
- Two columns side-by-side
- More breathing room
- Full content visible

### Narrow Screen (iPhone)
- Two columns still visible but narrower
- Scroll within each column
- Text may wrap if very narrow

## Technical Details

### Data Flow
```
ListsView
  │
  ├─ onAppear
  │    └─ loadTaskLists()
  │         └─ tasksVM.loadTasks()
  │              │
  │              ├─ Fetch personalTaskLists
  │              └─ Fetch professionalTaskLists
  │
  └─ Display
       │
       ├─ TaskListColumn (Personal)
       │    └─ ForEach personalTaskLists
       │         └─ TaskListRow
       │
       └─ TaskListColumn (Professional)
            └─ ForEach professionalTaskLists
                 └─ TaskListRow
```

### Performance
- Lazy loading with `LazyVStack`
- Efficient reuse of row components
- Parallel data fetching for both accounts
- Cached data from `TasksViewModel`

---

**UI Complete:** Shows all task lists from both accounts in a clean, organized layout! 🎉

