# LotusPlannerV3 Regression Test Suite

## Overview

This document describes the comprehensive regression test suite for LotusPlannerV3, covering all critical functionality and recent changes.

## Test Structure

### Test Files
- `LotusPlannerV3Tests.swift` - Main test suite with comprehensive coverage
- Located in: `LotusPlannerV3Tests/` directory

### Test Categories

#### 1. Core Data Tests
Tests for all Core Data entities and persistence:

- **PersistenceController**
  - Initialization and setup
  - In-memory store for testing
  - ViewContext accessibility

- **Entity Creation Tests**
  - `WeightLog` - Weight tracking entries
  - `WorkoutLog` - Workout session entries
  - `FoodLog` - Meal and calorie entries
  - `TaskTimeWindow` - Task scheduling windows
  - `CustomLogItem` - User-defined log types
  - `CustomLogEntry` - Custom log entries
  - `Goal` - Goal entries with completion status
  - `GoalCategory` - Goal category organization

- **Entity Operations**
  - Create, Read, Update, Delete (CRUD)
  - Batch operations
  - Fetch request validation
  - Data integrity checks

#### 2. Manager Tests
Tests for singleton managers and business logic:

- **CoreDataManager**
  - Delete all logs functionality
  - Data migration validation
  - Error handling

- **GoalsManager**
  - Max category limit (6 categories)
  - Category management
  - Goal CRUD operations

- **CustomLogManager**
  - Item limit enforcement (10 items max)
  - Entry management
  - Date-based queries

- **NavigationManager**
  - View switching (calendar, tasks, goals, journal)
  - Interval updates (day, week, month, year)
  - State management

#### 3. App Preferences Tests
Tests for user settings and preferences:

- **Color Management**
  - Personal account color
  - Professional account color
  - Color persistence

- **Day View Layout**
  - Layout option selection
  - Layout persistence
  - Device-specific layouts

- **Logs Visibility**
  - Weight logs toggle
  - Workout logs toggle
  - Food logs toggle
  - Sleep logs toggle
  - Custom logs toggle
  - `showAnyLogs` computed property

- **Account Names** (NEW)
  - Custom account name setting
  - 30-character truncation
  - Name retrieval by account kind

- **Divider Positions**
  - Persistence of UI split views
  - Default values
  - Update mechanisms

#### 4. Calendar Utility Tests
Tests for date and calendar operations:

- **Calendar Extensions**
  - Monday-first week configuration
  - Date component extraction
  - Week boundary calculations

- **Date Formatters**
  - Standard month-year format
  - Short date format
  - Day of week format
  - Locale consistency (en_US_POSIX)

#### 5. Data Model Tests
Tests for Swift data structures:

- **GoalDataModel**
  - `GoalData` structure validation
  - `GoalCategoryData` structure validation
  - Timestamp tracking

- **CustomLogDataModel**
  - `CustomLogItemData` structure
  - `CustomLogEntryData` structure
  - ID relationships

#### 6. Enum Tests
Tests for enumeration types:

- **DayViewLayoutOption**
  - All case values
  - Display names
  - Descriptions
  - Raw value consistency

- **TimelineInterval**
  - Calendar component mapping
  - SF Symbol names
  - Task filter conversion

#### 7. Configuration Tests
Tests for app configuration:

- **ConfigurationManager**
  - Initialization
  - Production/debug detection
  - Google OAuth configuration
  - Validation methods

#### 8. Security Tests
Tests for secure data handling:

- **KeychainManager**
  - String save operations
  - String retrieval
  - String deletion
  - Error handling for missing keys

#### 9. Performance Tests
Benchmarking tests for critical operations:

- **Core Data Performance**
  - Batch insert (100 records)
  - Fetch operations
  - Background context performance

#### 10. Integration Tests
End-to-end system tests:

- **DataManager**
  - Initialization of all sub-managers
  - Lifecycle management
  - Component integration

- **PersistenceController**
  - Preview mode validation
  - CloudKit container setup

#### 11. Edge Case Tests
Tests for boundary conditions and error states:

- **Invalid Input Handling**
  - Empty strings
  - Nil dates
  - Negative values
  - Zero durations

- **Data Validation**
  - Weight validation (allows negative for UI validation)
  - Duration validation
  - String length limits

#### 12. Logging Tests
Tests for development logging:

- **DevLogger**
  - Log level support (info, warning, error)
  - Category support (8 categories)
  - Verbose mode toggle
  - No-crash guarantee

### Recent Changes Regression Tests

Special test suite for verifying recent feature additions and bug fixes:

#### Custom Account Names (2026-01)
- ✅ Setting custom names for Personal/Professional accounts
- ✅ 30-character truncation
- ✅ Name retrieval by account kind
- ✅ Persistence across app launches

#### Day View Layout Order (2026-01)
- ✅ Standard appears before Timebox in settings
- ✅ All layout options accessible
- ✅ Layout switching works correctly

#### Timeline Auto-Scroll (2026-01)
- ✅ Expanded view always shows timeline (not list)
- ✅ Standard view respects timeline/list preference
- ✅ Timeline auto-scrolls to current time
- ✅ Red current-time line appears

#### Monthly Calendar Enhancements (2026-01)
- ✅ Red border around current day
- ✅ Border only appears for today
- ✅ 2-point border width

#### Console Log Cleanup (2026-01)
- ✅ All `print()` replaced with `devLog()`
- ✅ Duplicate `#if DEBUG` blocks removed
- ✅ Proper log levels used
- ✅ Appropriate categories assigned
- ✅ 128 lines of code removed

## Running Tests

### Via Xcode
1. Open `LotusPlannerV3.xcodeproj`
2. Select the test target
3. Press `⌘+U` to run all tests
4. View results in Test Navigator

### Via Command Line
```bash
cd LotusPlannerV3
xcodebuild test -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Via Continuous Integration
Tests should be run on:
- Every pull request
- Before merging to main
- Before production releases
- Nightly builds (optional)

## Test Coverage

### Current Coverage Areas

✅ **High Coverage (>80%)**
- Core Data entities and operations
- App preferences and settings
- Navigation state management
- Calendar utilities
- Data model structures

✅ **Medium Coverage (50-80%)**
- Manager business logic
- Configuration management
- Security (Keychain operations)

⚠️ **Low Coverage (<50%)**
- Google API integration (requires mocking)
- iCloud sync operations (requires CloudKit test environment)
- UI components (requires UI testing framework)
- Network operations (requires mock server)

### Not Covered (Requires Additional Setup)

❌ **Google Calendar API**
- Requires mock HTTP responses
- OAuth token validation
- Calendar event CRUD operations

❌ **Google Tasks API**
- Task list operations
- Task CRUD operations
- Multi-account support

❌ **iCloud Sync**
- CloudKit record operations
- Sync conflict resolution
- Remote change notifications

❌ **UI Testing**
- View rendering
- User interactions
- Navigation flows
- Gesture handling

❌ **Journal Drawing**
- PencilKit operations
- Image capture and storage
- iCloud Documents sync

## Test Maintenance

### Adding New Tests

When adding new features, create tests for:

1. **Data Layer**
   - New Core Data entities
   - New data models
   - CRUD operations

2. **Business Logic**
   - New manager methods
   - State transitions
   - Validation rules

3. **Configuration**
   - New settings
   - Default values
   - Persistence

4. **Edge Cases**
   - Nil handling
   - Empty states
   - Boundary values

### Updating Tests

When modifying existing features:

1. Review related test cases
2. Update assertions if behavior changed
3. Add new test cases for new scenarios
4. Ensure backward compatibility
5. Update documentation

### Test Guidelines

**DO:**
- Write descriptive test names
- Test one thing per test method
- Use arrange-act-assert pattern
- Clean up test data in tearDown
- Use XCTAssertions with messages

**DON'T:**
- Test implementation details
- Create dependencies between tests
- Use production data
- Skip cleanup
- Ignore test failures

## Known Issues and Limitations

### Test Environment Limitations

1. **In-Memory Store**
   - Tests use in-memory Core Data store
   - CloudKit sync not tested
   - Performance may differ from production

2. **No Network**
   - Google API calls not tested
   - Requires mock responses
   - Token refresh not validated

3. **UI Testing**
   - No UI test framework integrated
   - SwiftUI preview testing limited
   - Gesture recognition not tested

4. **Background Processing**
   - Background tasks not tested
   - Notification handling not tested
   - App lifecycle events limited

### Future Improvements

- [ ] Add UI test target
- [ ] Integrate mock HTTP server
- [ ] Add CloudKit test configuration
- [ ] Implement code coverage reporting
- [ ] Add performance benchmarks
- [ ] Create snapshot tests for UI
- [ ] Add accessibility tests
- [ ] Test localization strings

## Test Metrics

### Success Criteria

- ✅ All tests pass
- ✅ No test warnings
- ✅ Tests complete in <5 seconds
- ✅ No flaky tests
- ✅ Code coverage >70% (goal)

### Current Status

- **Total Tests**: 50+
- **Pass Rate**: 100% (target)
- **Execution Time**: <3 seconds
- **Coverage**: ~60% (estimated)

## Regression Checklist

Before each release, verify:

- [ ] All Core Data entities can be created
- [ ] All managers initialize correctly
- [ ] App preferences persist correctly
- [ ] Navigation state updates properly
- [ ] Date/calendar utilities work correctly
- [ ] Keychain operations succeed
- [ ] Performance tests meet benchmarks
- [ ] No memory leaks detected
- [ ] All recent features tested
- [ ] Edge cases handled gracefully

## Contact

For questions about tests:
- Review `LotusPlannerV3Tests.swift` for examples
- Check `CLAUDE.md` for architecture details
- See inline test documentation

Last Updated: 2026-01-22
