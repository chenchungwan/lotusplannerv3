# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LotusPlannerV3 is an iOS productivity app built with SwiftUI that integrates calendar, tasks, goals, and journaling capabilities. It uses Google Calendar API and Google Tasks API for external data synchronization and iCloud/CloudKit for cross-device data persistence.

**Tech Stack:**
- SwiftUI (iOS app)
- Core Data with NSPersistentCloudKitContainer (local storage + iCloud sync)
- Google Sign-In SDK (authentication)
- Google Calendar & Tasks APIs
- CloudKit (iCloud sync)

## Project Structure

```
LotusPlannerV3/
├── LotusPlannerV3/
│   ├── LotusPlannerV3/           # Main source directory
│   │   ├── NewUIs/                # Specialized day view components
│   │   ├── Assets.xcassets/       # App icons and images
│   │   ├── LotusPlannerV3.xcdatamodeld/  # Core Data model
│   │   └── *.swift                # Source files
│   └── LotusPlannerV3.xcodeproj
├── CLAUDE.md                      # This file
├── TASKS_COMPONENT_CUSTOMIZATION.md  # TasksComponent usage guide
├── APP_STORE_SUBMISSION_GUIDE.md  # App Store deployment guide
├── validate_security.sh           # Security validation script
└── ExportOptions.plist            # Xcode export configuration
```

## Building and Running

### Prerequisites
1. Xcode 15.0 or later
2. iOS 16.0+ deployment target
3. Valid Google OAuth Client ID configured in Info.plist
4. GoogleService-Info.plist file (copy from template and configure with actual credentials)

### Build Commands
```bash
# Open project in Xcode
open LotusPlannerV3/LotusPlannerV3.xcodeproj

# Build from command line (requires xcodebuild)
cd LotusPlannerV3
xcodebuild -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Debug build

# Build for release
xcodebuild -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Release build

# Archive for App Store distribution
xcodebuild -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Release archive -archivePath ./LotusPlannerV3.xcarchive

# Export archive for App Store (requires ExportOptions.plist)
xcodebuild -exportArchive -archivePath ./LotusPlannerV3.xcarchive -exportPath ./AppStoreExport -exportOptionsPlist ExportOptions.plist
```

### Security Validation
Before deploying to production, run the security validation script:
```bash
./validate_security.sh
```
This checks for API keys in source control, ensures Keychain is used for tokens, and validates configuration.

### Configuration
- **Info.plist:** Contains `GIDClientID` for Google Sign-In
- **GoogleService-Info.plist:** Not in version control (listed in .gitignore) - must be created from template
- **Template:** `LotusPlannerV3/LotusPlannerV3/GoogleService-Info-Template.plist`

## Architecture

### Core Managers (Singleton Pattern)

The app uses a centralized singleton pattern for shared state management:

#### Data Management Layer
- **`DataManager.shared`** - Main coordinator for app-wide data initialization and preloading
  - Manages `CalendarViewModel`, `TasksViewModel`, `GoalsManager`, `CustomLogManager`
  - Handles app lifecycle events (foreground/background)
  - Debounces expensive operations like month preloading
  - Location: `LotusPlannerV3/LotusPlannerV3/DataManager.swift`

#### Persistence Layer
- **`PersistenceController.shared`** - Core Data stack with CloudKit integration
  - Uses `NSPersistentCloudKitContainer` for automatic iCloud sync
  - Enables history tracking and remote change notifications
  - Location: `LotusPlannerV3/LotusPlannerV3/Persistence.swift`

- **`CoreDataManager.shared`** - High-level Core Data operations
  - CRUD operations for logs (weight, workout, food)
  - Task time window management
  - Legacy migration from UserDefaults/iCloud KVS to Core Data
  - Location: `LotusPlannerV3/LotusPlannerV3/CoreDataManager.swift`

#### Cloud Sync Layer
- **`iCloudManager.shared`** - CloudKit sync coordination
  - Monitors iCloud account status
  - Handles sync conflicts and merging
  - Listens for `NSPersistentStoreRemoteChange` notifications
  - Provides diagnostic tools for CloudKit data inspection
  - Posts `.iCloudDataChanged` notifications when sync completes
  - Location: `LotusPlannerV3/LotusPlannerV3/iCloudManager.swift`

#### Authentication Layer
- **`GoogleAuthManager.shared`** - Google OAuth management
  - Manages Personal and Professional Google accounts separately
  - Token storage in Keychain (via `KeychainManager`)
  - Automatic token refresh when expired
  - Location: `LotusPlannerV3/LotusPlannerV3/GoogleAuthManager.swift`

- **`KeychainManager`** - Secure keychain storage
  - Stores OAuth tokens securely in iOS Keychain
  - Used by GoogleAuthManager for token persistence
  - Prevents tokens from being stored in UserDefaults
  - Location: `LotusPlannerV3/LotusPlannerV3/KeychainManager.swift`

#### Domain-Specific Managers
- **`GoalsManager.shared`** - Goals and goal categories
  - Core Data + CloudKit sync for goals
  - Category management (max 6 categories)
  - Location: `LotusPlannerV3/LotusPlannerV3/GoalsManager.swift:10`

- **`CustomLogManager.shared`** - Custom log types and entries
  - User-defined log categories
  - Core Data persistence
  - Location: `LotusPlannerV3/LotusPlannerV3/CustomLogManager.swift`

- **`JournalManager.shared`** - Journal drawings and photos
  - iCloud Documents storage for journal data
  - PDF background management
  - Photo metadata management
  - Location: `LotusPlannerV3/LotusPlannerV3/JournalManager.swift`

- **`TaskTimeWindowManager.shared`** - Task scheduling time windows
  - Links Google Tasks to specific time slots
  - Core Data persistence with CloudKit sync
  - Referenced in: `LotusPlannerV3/LotusPlannerV3/TaskTimeWindowManager.swift`

- **`CalendarManager.shared`** - Calendar operations helper
  - Calendar permission management
  - Date/time utilities
  - Location: `LotusPlannerV3/LotusPlannerV3/CalendarManager.swift`

### ViewModels

ViewModels are embedded within their respective view files (not separate files):

- **`CalendarViewModel`** - Calendar events and navigation
  - Manages Google Calendar API calls for both Personal and Professional accounts
  - Month-based caching for performance
  - Preloads adjacent months in background
  - Location: `LotusPlannerV3/LotusPlannerV3/CalendarView.swift` (class definition)

- **`TasksViewModel`** - Google Tasks management
  - Manages task lists and tasks from Google Tasks API
  - Supports both Personal and Professional accounts
  - On-demand loading for performance optimization
  - Location: `LotusPlannerV3/LotusPlannerV3/TasksView.swift` (class definition)

- **`LogsViewModel.shared`** - Custom logging data
  - Singleton pattern for global access
  - Location: `LotusPlannerV3/LotusPlannerV3/LogsViewModel.swift`

### View Architecture

The app has a modular view structure with specialized day views:

#### Navigation Entry Points
- **`LotusPlannerV3App`** - App entry point with initialization
  - Sets up `PersistenceController`, `iCloudManager`, `ConfigurationManager`
  - Location: `LotusPlannerV3/LotusPlannerV3/LotusPlannerV3App.swift`

- **`RootView`** - Root container with cover animation
  - Shows splash screen with slide-to-open gesture
  - Auto-dismisses after 0.5 seconds
  - Location: `LotusPlannerV3/LotusPlannerV3/RootView.swift`

- **`ContentView`** - Main navigation container (not shown in file list but referenced)

#### Main Views
- **`CalendarView`** - Calendar display (month/week/day views)
  - Contains embedded `CalendarViewModel`
  - Integrates with Google Calendar API
  - Shows tasks inline with calendar
  - Location: `LotusPlannerV3/LotusPlannerV3/CalendarView.swift`

- **`WeeklyView`** - Week timeline view
  - Compact week layout with time slots
  - Location: `LotusPlannerV3/LotusPlannerV3/WeeklyView.swift`

- **`TasksView`** - Tasks management interface
  - Contains embedded `TasksViewModel`
  - Multiple layout modes (vertical, horizontal cards)
  - Location: `LotusPlannerV3/LotusPlannerV3/TasksView.swift`

- **`GoalsView`** - Goals management
  - Location: `LotusPlannerV3/LotusPlannerV3/GoalsView.swift`

- **`JournalView`** - Journal/drawing interface
  - Location: `LotusPlannerV3/LotusPlannerV3/JournalView.swift`

- **`SettingsView`** - App settings and configuration
  - Account linking/unlinking
  - iCloud sync controls
  - Location: `LotusPlannerV3/LotusPlannerV3/SettingsView.swift`

#### Specialized Day Views (in `NewUIs/` directory)
- **`DayViewCompact`** - Compact single-day layout
- **`DayViewExpanded`** - Expanded single-day layout
- **`DayViewMobile`** - Mobile-optimized day view
- **`DayViewTimebox`** - Time-boxed day view with scheduling
- **`GlobalNavBar`** - Shared navigation bar component

All located in: `LotusPlannerV3/LotusPlannerV3/NewUIs/`

### Reusable Components

- **`TasksComponent`** - Highly customizable tasks display component
  - Used across 8+ different views with different configurations
  - Parameters: `horizontalCards`, `isSingleDayView`, `hideDueDateTag`, `showTitle`, `showEmptyState`
  - See `TASKS_COMPONENT_CUSTOMIZATION.md` for detailed usage guide
  - Location: `LotusPlannerV3/LotusPlannerV3/TasksComponent.swift`

- **`TimeboxComponent`** - Time-boxed scheduling view
  - Location: `LotusPlannerV3/LotusPlannerV3/TimeboxComponent.swift`

- **`TimelineComponent`** - Timeline visualization
  - Location: `LotusPlannerV3/LotusPlannerV3/TimelineComponent.swift`

### Data Models

Core Data entities (defined in `LotusPlannerV3.xcdatamodeld`):
- `WeightLog`, `WorkoutLog`, `FoodLog` - Health/fitness logging
- `TaskTimeWindow` - Task scheduling data
- `CustomLogEntry`, `CustomLogItem` - User-defined logs
- `Goal`, `GoalCategory` - Goals management

Swift data structures:
- `GoalData`, `GoalCategoryData` - In `GoalsDataModel.swift`
- `CustomLogData` - In `CustomLogDataModel.swift`
- `LogsDataModel` - In `LogsDataModel.swift`
- Google API types - Defined inline in CalendarViewModel and TasksViewModel

## Key Patterns and Conventions

### Logging
- Use `devLog()` function for debug logging (defined in `DevLogger.swift`)
- Logs are disabled in Release builds automatically
- Verbose logging controlled by `verboseLoggingEnabled` UserDefaults key
- Log categories: `.general`, `.sync`, `.tasks`, `.goals`, `.calendar`, `.navigation`, `.cloud`, `.auth`

**Example:**
```swift
devLog("🔄 Syncing data...", level: .info, category: .sync)
devLog("❌ Error occurred: \(error)", level: .error, category: .cloud)
```

### Error Handling
- Never crash on errors - use graceful degradation
- Show user-friendly error messages
- Log detailed error information for debugging
- Example: Core Data load failures should not crash the app

### Async/Await
- All network operations use async/await
- ViewModels use `@MainActor` for UI updates
- Background operations use `Task.detached(priority: .background)`

### Security
- **NEVER** commit API keys or tokens to git
- Use `KeychainManager` for storing sensitive tokens
- `GoogleAuthManager` migrates old UserDefaults tokens to Keychain automatically
- Run `./validate_security.sh` before releases

### Data Sync Strategy
1. **Google Calendar/Tasks**: Fetched on-demand via REST API
2. **Local logs**: Core Data with CloudKit sync via `NSPersistentCloudKitContainer`
3. **Journal data**: iCloud Documents folder for drawings/photos
4. **Preferences**: UserDefaults for non-sensitive settings

### Performance Optimizations
- Month-based caching for calendar events (`CalendarViewModel`)
- Debounced preloading of adjacent months (500ms delay)
- On-demand task loading (load lists first, then tasks when needed)
- Background processing for non-critical operations
- Image caching with `ImageCache.shared`

## Common Development Workflows

### Adding a New Manager
1. Create singleton with `static let shared = ManagerName()`
2. Add `@MainActor` if it updates UI state
3. Use `@Published` properties for observable state
4. Add initialization to `LotusPlannerV3App.init()` if needed
5. Register for relevant NotificationCenter events

### Adding a New Core Data Entity
1. Open `LotusPlannerV3.xcdatamodeld` in Xcode
2. Add entity with attributes
3. Enable CloudKit sync if needed (check "Use for CloudKit")
4. Update `CoreDataManager` with CRUD methods
5. Core Data automatically handles lightweight migration

### Working with Google APIs
- Access tokens are automatically refreshed by `GoogleAuthManager`
- Always use `try await GoogleAuthManager.shared.getAccessToken(for: .personal)`
- Handle both `.personal` and `.professional` account types
- Implement error handling for network failures and auth errors

### Debugging iCloud Sync
Use `iCloudManager` diagnostic methods:
```swift
await iCloudManager.shared.diagnoseCloudKitData()  // Check CloudKit records
iCloudManager.shared.forceCompleteSync()           // Force full sync
```

### Testing
- No test files currently present
- Manual testing required
- Use in-memory Core Data store for SwiftUI previews: `PersistenceController.preview`

## Important Notes

### Calendar Utilities
- Use `Calendar.mondayFirst` extension for Monday-start weeks (defined in extensions)
- Date formatting uses `Locale(identifier: "en_US_POSIX")` for consistency

### State Management
- Global app preferences in `AppPreferences.shared` (referenced but not shown in files)
- Navigation state in `NavigationManager.shared` (referenced in RootView)
- Most managers use `@Published` for reactive UI updates

### iCloud Sync Timing
- CloudKit imports can take 10-15 seconds after changes
- `iCloudManager.forceCompleteSync()` includes polling logic with delays
- Listen for `.iCloudDataChanged` notifications for UI updates

### Multi-Account Support
- Supports two separate Google accounts: Personal and Professional
- Each account has separate token storage in Keychain
- Calendar and Tasks are fetched separately per account
- UI shows both accounts side-by-side where applicable

### Known Limitations
- No unit tests (consider adding tests for critical business logic)
- Some debug print statements still use manual `#if DEBUG` blocks (should migrate to `devLog()`)
- Core Data migration is automatic (no manual migration logic)

## File References

When editing code, always reference line numbers for specific functions:
```
Example: CalendarViewModel.loadEvents() is at CalendarView.swift:245
```

## Dependencies

External dependencies are managed via Swift Package Manager or CocoaPods (not visible in provided files, but GoogleSignIn SDK is used).

**Key Dependencies:**
- Google Sign-In SDK (GoogleSignIn)
- CloudKit (Apple framework)
- PencilKit (for journal drawings)
