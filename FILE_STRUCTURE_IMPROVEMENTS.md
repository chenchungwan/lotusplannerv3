# File Structure Improvement Recommendations

**Generated:** 2026-01-26
**Project:** LotusPlannerV3

## Current State

The project has **74 Swift files** with **66 in the root directory** and only **8 in NewUIs/**. This flat structure makes navigation challenging as the codebase grows.

---

## 🎯 Recommended Directory Structure

```
LotusPlannerV3/LotusPlannerV3/
├── App/
│   ├── LotusPlannerV3App.swift
│   ├── RootView.swift
│   └── AppDelegate.swift (if exists)
│
├── Core/
│   ├── Managers/
│   │   ├── Data/
│   │   │   ├── DataManager.swift
│   │   │   ├── CoreDataManager.swift
│   │   │   ├── Persistence.swift
│   │   │   └── iCloudManager.swift
│   │   ├── Auth/
│   │   │   ├── GoogleAuthManager.swift
│   │   │   └── KeychainManager.swift
│   │   ├── Configuration/
│   │   │   ├── ConfigurationManager.swift
│   │   │   └── BackgroundProcessor.swift
│   │   └── Navigation/
│   │       └── NavigationManager.swift (if exists)
│   │
│   ├── Utilities/
│   │   ├── Logging/
│   │   │   ├── DevLogger.swift
│   │   │   └── PerformanceLogger.swift
│   │   ├── Helpers/
│   │   │   ├── ImageCache.swift
│   │   │   ├── ScreenSizeHelper.swift
│   │   │   └── CalendarExtensions.swift (if exists)
│   │   └── UI/
│   │       ├── SidebarToggleHidden.swift
│   │       └── SharedToolbar.swift
│   │
│   └── Persistence/
│       ├── LotusPlannerV3.xcdatamodeld/
│       └── CoreDataEntities/ (if you have entity extensions)
│
├── Features/
│   ├── Calendar/
│   │   ├── Views/
│   │   │   ├── CalendarView.swift
│   │   │   ├── CalendarWeekView.swift
│   │   │   └── CalendarYearlyView.swift
│   │   ├── Components/
│   │   │   └── EventsListComponent.swift
│   │   ├── ViewModels/
│   │   │   └── CalendarViewModel.swift (extract from CalendarView)
│   │   ├── Models/
│   │   │   └── CalendarTypes.swift
│   │   └── Managers/
│   │       └── CalendarManager.swift
│   │
│   ├── Tasks/
│   │   ├── Views/
│   │   │   ├── TasksView.swift
│   │   │   └── ListsView.swift
│   │   ├── Components/
│   │   │   ├── TasksComponent.swift
│   │   │   └── TasksCompactComponent.swift
│   │   ├── ViewModels/
│   │   │   └── TasksViewModel.swift (extract from TasksView)
│   │   ├── Models/
│   │   │   ├── TaskPriority.swift
│   │   │   └── TaskTimeWindow.swift
│   │   └── Managers/
│   │       └── TaskTimeWindowManager.swift
│   │
│   ├── Goals/
│   │   ├── Views/
│   │   │   ├── GoalsView.swift
│   │   │   └── AllGoalsView.swift
│   │   ├── ViewModels/
│   │   │   └── GoalsViewModel.swift (if needed)
│   │   ├── Models/
│   │   │   └── GoalsDataModel.swift
│   │   ├── Managers/
│   │   │   └── GoalsManager.swift
│   │   └── Testing/
│   │       └── GoalsTestHelper.swift
│   │
│   ├── Journal/
│   │   ├── Views/
│   │   │   ├── JournalView.swift
│   │   │   └── JournalDayViews.swift
│   │   ├── Managers/
│   │   │   ├── JournalManager.swift
│   │   │   ├── JournalAutoSaveManager.swift
│   │   │   ├── JournalDrawingManagerNew.swift
│   │   │   ├── JournalStorageNew.swift
│   │   │   └── JournalFilePresenter.swift
│   │   └── Models/
│   │       └── JournalVersion.swift
│   │
│   ├── Logs/
│   │   ├── Views/
│   │   │   ├── CustomLogView.swift
│   │   │   ├── CustomLogManagementView.swift
│   │   │   ├── EditLogEntryView.swift
│   │   │   └── AddLogEntryView.swift
│   │   ├── Components/
│   │   │   ├── LogsComponent.swift
│   │   │   └── PriorityIconSelector.swift
│   │   ├── ViewModels/
│   │   │   └── LogsViewModel.swift
│   │   ├── Models/
│   │   │   ├── LogsDataModel.swift
│   │   │   └── CustomLogDataModel.swift
│   │   └── Managers/
│   │       └── CustomLogManager.swift
│   │
│   ├── DayViews/
│   │   ├── Active/
│   │   │   ├── DayViewNewClassic.swift
│   │   │   ├── DayViewCompact.swift
│   │   │   ├── DayViewTimebox.swift
│   │   │   └── DayViewMobile.swift
│   │   ├── Legacy/
│   │   │   ├── DayViewExpanded.swift
│   │   │   └── DayViewNewCompact.swift
│   │   ├── Components/
│   │   │   └── GlobalNavBar.swift
│   │   └── Supporting/
│   │       ├── WeeklyView.swift
│   │       ├── SimpleWeekView.swift
│   │       └── TimeboxView.swift
│   │
│   ├── Timeline/
│   │   ├── Components/
│   │   │   ├── TimelineComponent.swift
│   │   │   ├── TimelineBaseView.swift
│   │   │   ├── WeekTimelineComponent.swift
│   │   │   ├── MonthTimelineComponent.swift
│   │   │   └── TimeboxComponent.swift
│   │   └── Models/
│   │       └── (timeline models if any)
│   │
│   ├── Settings/
│   │   ├── Views/
│   │   │   ├── SettingsView.swift
│   │   │   ├── AboutView.swift
│   │   │   └── ReportIssuesView.swift
│   │   └── Models/
│   │       └── AppPreferences.swift (if exists)
│   │
│   ├── BulkEdit/
│   │   ├── Managers/
│   │   │   └── BulkEditManager.swift
│   │   ├── Models/
│   │   │   └── BulkEditModels.swift
│   │   └── Components/
│   │       └── BulkEditComponents.swift
│   │
│   └── Home/
│       └── HomeView.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── GoogleService-Info-Template.plist
│
└── Documentation/
    └── (move from root if desired)
```

---

## 🔑 Key Improvements

### 1. **Feature-Based Organization** (Most Important)
Group all related files by feature domain rather than by file type. This makes it easier to work on a feature without jumping between distant directories.

**Benefits:**
- Find all Calendar-related code in one place
- Easier to onboard new developers
- Clear feature boundaries
- Easier to refactor or extract features

### 2. **Separate ViewModels from Views**
Currently `CalendarViewModel` and `TasksViewModel` are embedded in view files. Extract them to separate files:

```swift
// Features/Calendar/ViewModels/CalendarViewModel.swift
// Features/Tasks/ViewModels/TasksViewModel.swift
```

**Benefits:**
- Better testability
- Clearer separation of concerns
- Easier to reuse ViewModels
- Follows MVVM pattern more strictly

### 3. **Consolidate Core Infrastructure**
Move all foundational code into `Core/`:
- **Managers/** - All singleton managers organized by domain
- **Utilities/** - All helpers and utilities
- **Persistence/** - Core Data stack

### 4. **Split DayViews More Clearly**
Rename `NewUIs/` to `Features/DayViews/` and organize by status:
- **Active/** - 4 active layouts
- **Legacy/** - Deprecated layouts
- **Components/** - Shared day view components

### 5. **Create Dedicated Components Directory**
Within each feature, separate reusable components:
- `TasksComponent` → `Features/Tasks/Components/`
- `LogsComponent` → `Features/Logs/Components/`
- `TimelineComponent` → `Features/Timeline/Components/`

---

## 📋 Migration Plan

### Phase 1: Create Directory Structure (Low Risk)
```bash
# Create new directories (doesn't break anything)
cd LotusPlannerV3/LotusPlannerV3
mkdir -p App
mkdir -p Core/Managers/{Data,Auth,Configuration,Navigation}
mkdir -p Core/Utilities/{Logging,Helpers,UI}
mkdir -p Core/Persistence
mkdir -p Features/Calendar/{Views,Components,ViewModels,Models,Managers}
mkdir -p Features/Tasks/{Views,Components,ViewModels,Models,Managers}
mkdir -p Features/Goals/{Views,ViewModels,Models,Managers,Testing}
mkdir -p Features/Journal/{Views,Managers,Models}
mkdir -p Features/Logs/{Views,Components,ViewModels,Models,Managers}
mkdir -p Features/DayViews/{Active,Legacy,Components,Supporting}
mkdir -p Features/Timeline/{Components,Models}
mkdir -p Features/Settings/{Views,Models}
mkdir -p Features/BulkEdit/{Managers,Models,Components}
mkdir -p Features/Home
mkdir -p Resources
```

### Phase 2: Move Files by Feature (Incremental)

**IMPORTANT:** Use Xcode's built-in "Move" feature, not Finder or command line, to ensure Xcode project references are updated automatically.

Start with one feature at a time:

1. **Calendar** (4 files) - Test that build works
   - CalendarView.swift → Features/Calendar/Views/
   - CalendarWeekView.swift → Features/Calendar/Views/
   - CalendarYearlyView.swift → Features/Calendar/Views/
   - CalendarManager.swift → Features/Calendar/Managers/
   - CalendarTypes.swift → Features/Calendar/Models/
   - EventsListComponent.swift → Features/Calendar/Components/

2. **Tasks** (3 files) - Test again
   - TasksView.swift → Features/Tasks/Views/
   - ListsView.swift → Features/Tasks/Views/
   - TasksComponent.swift → Features/Tasks/Components/
   - TasksCompactComponent.swift → Features/Tasks/Components/
   - TaskPriority.swift → Features/Tasks/Models/
   - TaskTimeWindow.swift → Features/Tasks/Models/
   - TaskTimeWindowManager.swift → Features/Tasks/Managers/

3. **Goals** (4 files) - Continue pattern
   - GoalsView.swift → Features/Goals/Views/
   - AllGoalsView.swift → Features/Goals/Views/
   - GoalsDataModel.swift → Features/Goals/Models/
   - GoalsManager.swift → Features/Goals/Managers/
   - GoalsTestHelper.swift → Features/Goals/Testing/

4. **Journal** (6 files)
   - JournalView.swift → Features/Journal/Views/
   - JournalDayViews.swift → Features/Journal/Views/
   - JournalManager.swift → Features/Journal/Managers/
   - JournalAutoSaveManager.swift → Features/Journal/Managers/
   - JournalDrawingManagerNew.swift → Features/Journal/Managers/
   - JournalStorageNew.swift → Features/Journal/Managers/
   - JournalFilePresenter.swift → Features/Journal/Managers/
   - JournalVersion.swift → Features/Journal/Models/

5. **Logs** (9 files)
   - CustomLogView.swift → Features/Logs/Views/
   - CustomLogManagementView.swift → Features/Logs/Views/
   - EditLogEntryView.swift → Features/Logs/Views/
   - AddLogEntryView.swift → Features/Logs/Views/
   - LogsComponent.swift → Features/Logs/Components/
   - PriorityIconSelector.swift → Features/Logs/Components/
   - LogsViewModel.swift → Features/Logs/ViewModels/
   - LogsDataModel.swift → Features/Logs/Models/
   - CustomLogDataModel.swift → Features/Logs/Models/
   - CustomLogManager.swift → Features/Logs/Managers/

6. **DayViews** (8 files from NewUIs/)
   - DayViewNewClassic.swift → Features/DayViews/Active/
   - DayViewCompact.swift → Features/DayViews/Active/
   - DayViewTimebox.swift → Features/DayViews/Active/
   - DayViewMobile.swift → Features/DayViews/Active/
   - DayViewExpanded.swift → Features/DayViews/Legacy/
   - DayViewNewCompact.swift → Features/DayViews/Legacy/
   - GlobalNavBar.swift → Features/DayViews/Components/
   - JournalDayViews.swift → Features/DayViews/Components/ (or Journal feature)
   - WeeklyView.swift → Features/DayViews/Supporting/
   - SimpleWeekView.swift → Features/DayViews/Supporting/
   - TimeboxView.swift → Features/DayViews/Supporting/

7. **Timeline** (5 files)
   - TimelineComponent.swift → Features/Timeline/Components/
   - TimelineBaseView.swift → Features/Timeline/Components/
   - WeekTimelineComponent.swift → Features/Timeline/Components/
   - MonthTimelineComponent.swift → Features/Timeline/Components/
   - TimeboxComponent.swift → Features/Timeline/Components/

8. **Core Managers**
   - DataManager.swift → Core/Managers/Data/
   - CoreDataManager.swift → Core/Managers/Data/
   - Persistence.swift → Core/Managers/Data/
   - iCloudManager.swift → Core/Managers/Data/
   - GoogleAuthManager.swift → Core/Managers/Auth/
   - KeychainManager.swift → Core/Managers/Auth/
   - ConfigurationManager.swift → Core/Managers/Configuration/
   - BackgroundProcessor.swift → Core/Managers/Configuration/

9. **Utilities**
   - DevLogger.swift → Core/Utilities/Logging/
   - PerformanceLogger.swift → Core/Utilities/Logging/
   - ImageCache.swift → Core/Utilities/Helpers/
   - ScreenSizeHelper.swift → Core/Utilities/Helpers/
   - SidebarToggleHidden.swift → Core/Utilities/UI/
   - SharedToolbar.swift → Core/Utilities/UI/

10. **Settings** (3 files)
    - SettingsView.swift → Features/Settings/Views/
    - AboutView.swift → Features/Settings/Views/
    - ReportIssuesView.swift → Features/Settings/Views/

11. **BulkEdit** (3 files)
    - BulkEditManager.swift → Features/BulkEdit/Managers/
    - BulkEditModels.swift → Features/BulkEdit/Models/
    - BulkEditComponents.swift → Features/BulkEdit/Components/

12. **App Entry**
    - LotusPlannerV3App.swift → App/
    - RootView.swift → App/

13. **Home**
    - HomeView.swift → Features/Home/

14. **Resources**
    - Assets.xcassets → Resources/
    - Info.plist → Resources/
    - GoogleService-Info-Template.plist → Resources/

15. **Core Data**
    - LotusPlannerV3.xcdatamodeld → Core/Persistence/

### Phase 3: Extract ViewModels (Refactoring)

This requires code changes, not just file moves:

1. **CalendarViewModel** - Extract from CalendarView.swift:
   ```swift
   // Create new file: Features/Calendar/ViewModels/CalendarViewModel.swift
   // Move CalendarViewModel class from CalendarView.swift
   // Update CalendarView.swift to import and reference it
   ```

2. **TasksViewModel** - Extract from TasksView.swift:
   ```swift
   // Create new file: Features/Tasks/ViewModels/TasksViewModel.swift
   // Move TasksViewModel class from TasksView.swift
   // Update TasksView.swift to import and reference it
   ```

### Phase 4: Update Documentation
- Update CLAUDE.md with new structure
- Update any file path references in documentation
- Update this file with actual migration results

---

## 🚦 Priority Recommendations

### High Priority (Do First)
1. ✅ **Create Core/Managers/** structure - Consolidates singleton managers
2. ✅ **Reorganize DayViews/** - Clarifies active vs legacy layouts (rename NewUIs/)
3. ✅ **Move Core Utilities** - Group helpers logically

### Medium Priority (Do Next)
4. ✅ **Feature-based organization** - Start with Calendar and Tasks features
5. ✅ **Extract ViewModels** - Improves testability and separation of concerns

### Low Priority (Nice to Have)
6. ✅ **Move Resources** - Cleaner root directory
7. ✅ **Add Tests directory** - Prepare for future testing

---

## 🎁 Benefits

### Better Navigation
- Xcode's file navigator becomes more logical
- CMD+Shift+O file search becomes easier with namespacing
- New developers can find code faster

### Improved Modularity
- Clear feature boundaries
- Easier to extract features into frameworks/packages
- Better code ownership (teams can own features)

### Scalability
- Adding new features becomes straightforward
- Pattern is clear for where new files go
- Prevents root directory from growing further

### Better Testing
- Feature-based structure makes unit testing easier
- ViewModels in separate files are more testable
- Clear boundaries for integration tests

### Documentation
- Folder structure documents architecture
- Easier to explain project organization
- Better aligns with CLAUDE.md documentation

---

## ⚠️ Migration Warnings

### Critical: Use Xcode's Move Feature
**DO NOT** use Finder or command line `mv` to move files. Always use Xcode's built-in move functionality:

1. Select file(s) in Xcode Project Navigator
2. Drag to new group/folder, OR
3. Right-click → Show in Finder → Move using Xcode's file inspector

This ensures:
- Xcode project references are updated
- Build settings are preserved
- Import statements are updated automatically
- Git tracking is maintained

### Things to Watch Out For

1. **Import Statements** - Xcode updates these automatically when moving files, but double-check after major moves
2. **Relative Paths** - Check for any hardcoded file paths (unlikely in Swift)
3. **Git History** - Xcode's move preserves git history, but verify with `git log --follow <file>`
4. **Build Settings** - Test build after each major batch of moves
5. **Info.plist References** - Ensure Info.plist paths are updated if moved
6. **Asset Catalog** - Assets.xcassets references should be updated automatically

### Testing After Migration

After each phase:
```bash
# Clean build folder
cd LotusPlannerV3
xcodebuild clean -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3

# Build to verify
xcodebuild -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Debug build

# Run app in simulator to verify runtime behavior
```

---

## 📊 Migration Tracking

Use this checklist to track progress:

- [ ] Phase 1: Create directory structure
- [ ] Phase 2: Move files
  - [ ] Calendar feature (4 files)
  - [ ] Tasks feature (7 files)
  - [ ] Goals feature (4 files)
  - [ ] Journal feature (7 files)
  - [ ] Logs feature (9 files)
  - [ ] DayViews feature (11 files)
  - [ ] Timeline feature (5 files)
  - [ ] Core Managers (8 files)
  - [ ] Utilities (6 files)
  - [ ] Settings feature (3 files)
  - [ ] BulkEdit feature (3 files)
  - [ ] App entry (2 files)
  - [ ] Home feature (1 file)
  - [ ] Resources (3 items)
  - [ ] Core Data model (1 file)
- [ ] Phase 3: Extract ViewModels
  - [ ] CalendarViewModel
  - [ ] TasksViewModel
- [ ] Phase 4: Update documentation
  - [ ] Update CLAUDE.md
  - [ ] Update file references in other docs
  - [ ] Update this file with results

---

## 🔄 Rollback Plan

If migration causes issues:

1. **Git Revert**:
   ```bash
   git reset --hard HEAD  # If not committed
   git revert <commit>    # If committed
   ```

2. **Xcode Reset**:
   - Close Xcode
   - Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
   - Reopen project

3. **Manual Fix**:
   - Check Xcode project file for broken references
   - Re-add files if needed via Xcode (not Finder)

---

## 📝 Notes

- Current structure: 66 files in root, 8 in NewUIs/
- Proposed structure: ~0 files in root (only Xcode project), organized by domain
- Estimated time: 2-4 hours for full migration (done incrementally)
- Risk level: Low (if using Xcode's move feature and testing incrementally)

---

## Next Steps

1. Review this document and approve approach
2. Create directory structure (Phase 1)
3. Start with Calendar feature migration as proof of concept
4. Test build and runtime behavior
5. Continue with remaining features
6. Extract ViewModels (optional but recommended)
7. Update documentation

---

**Questions or concerns?** Test on a separate git branch first, or migrate one feature at a time to minimize risk.
