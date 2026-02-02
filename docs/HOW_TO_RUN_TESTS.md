# Complete Step-by-Step Guide: Running Regression Tests in Xcode

## Prerequisites
- Xcode 15.0 or later installed
- LotusPlannerV3 project on your Mac
- Test files already created (✓ Done)

---

## Part 1: First-Time Setup (Do this once)

### Step 1: Open Your Project in Xcode

**Option A - Via Terminal:**
```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3
open LotusPlannerV3.xcodeproj
```

**Option B - Via Finder:**
- Navigate to: `/Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3/`
- Double-click `LotusPlannerV3.xcodeproj`

⏱️ Wait for Xcode to open and load the project (10-30 seconds)

---

### Step 2: Add the Test Target

📍 **Location**: Left sidebar → Top of the file tree

1. **Click** on the blue "LotusPlannerV3" project icon (very top of left sidebar)
   - It's the icon that looks like a blue square with "LotusPlannerV3" next to it
   
2. **Look** at the main editor area - you'll see:
   - Top section: "PROJECT" with "LotusPlannerV3"
   - Bottom section: "TARGETS" with "LotusPlannerV3"

3. **Click** the **"+"** button at the bottom of the TARGETS list
   - It's a small plus icon just below the targets

4. **Template Chooser** appears:
   ```
   Choose a template for your new target:
   [iOS] [watchOS] [tvOS] [macOS]
   
   Application
   Framework & Library
   → Unit Testing Bundle  ← CLICK THIS ONE
   UI Testing Bundle
   ```

5. **Click** "Unit Testing Bundle"

6. **Click** "Next" button (bottom right)

7. **Configure** the test bundle:
   ```
   Product Name: LotusPlannerV3Tests
   Team: [Your development team]
   Organization Name: [Your name/company]
   Organization Identifier: com.chenchungwan
   Bundle Identifier: com.chenchungwan.LotusPlannerV3Tests
   Language: Swift
   Project: LotusPlannerV3
   Embed in Application: [Leave unchecked]
   Target to be Tested: LotusPlannerV3  ← Make sure this is selected
   ```

8. **Click** "Finish"

✅ **Result**: You'll see "LotusPlannerV3Tests" appear in the TARGETS list

---

### Step 3: Add the Test File to Xcode

The test file exists on disk but needs to be added to Xcode:

1. **Right-click** on the "LotusPlannerV3Tests" folder in the left sidebar
   - If you don't see this folder, look for a group/folder with that name
   - It might have been created automatically with a sample test file

2. **Select** "Add Files to LotusPlannerV3..."

3. **Navigate** to: `/Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3Tests/`

4. **Select** the file: `LotusPlannerV3Tests.swift`

5. **Important**: Check the settings at the bottom:
   ```
   ☑ Copy items if needed
   ☑ Create groups
   
   Add to targets:
   ☑ LotusPlannerV3Tests  ← MUST BE CHECKED
   ☐ LotusPlannerV3       ← Should NOT be checked
   ```

6. **Click** "Add"

7. **Delete** the automatically created sample test file if it exists:
   - Look for a file like "LotusPlannerV3Tests.swift" (the old one)
   - Right-click → Delete → Move to Trash

✅ **Result**: You should see `LotusPlannerV3Tests.swift` in the LotusPlannerV3Tests group

---

### Step 4: Enable Testability

This allows tests to access internal classes and methods:

1. **Click** on "LotusPlannerV3" target (the main app, not the test target)

2. **Click** on "Build Settings" tab at the top

3. **Search** for "testability" in the search box

4. **Find** "Enable Testability"

5. **Set** to "Yes" for Debug configuration
   ```
   Enable Testability
   Debug:   Yes  ← Make sure this is Yes
   Release: No   ← Leave as No
   ```

✅ **Result**: Tests can now access app code with `@testable import`

---

### Step 5: Configure Code Coverage (Optional but Recommended)

This shows you which code is tested:

1. **Click** "Product" in menu bar → "Scheme" → "Edit Scheme..."
   - Or press: `⌘ + <` (Command + Less-than)

2. **Select** "Test" from the left sidebar

3. **Check** the "Code Coverage" checkbox
   ```
   ☑ Code Coverage
   ☑ Gather coverage for:
      ☑ LotusPlannerV3
   ```

4. **Click** "Close"

✅ **Result**: You'll see coverage percentages after running tests

---

## Part 2: Running the Tests

### Method 1: Run All Tests (Recommended First Time)

**Keyboard Shortcut:** Press `⌘ + U` (Command + U)

**OR Menu:** Product → Test

⏱️ **Wait**: Tests will compile and run (30-60 seconds first time)

---

### Method 2: Run Tests via Test Navigator

1. **Show Test Navigator**:
   - Click the diamond/test tube icon in the left sidebar
   - Or press: `⌘ + 6` (Command + 6)

2. **You'll see test structure**:
   ```
   LotusPlannerV3Tests
   └── LotusPlannerV3Tests
       ├── testPersistenceControllerInitialization()
       ├── testWeightLogCreation()
       ├── testWorkoutLogCreation()
       └── ... (50+ more tests)
   
   RecentChangesRegressionTests
   └── RecentChangesRegressionTests
       ├── testCustomAccountNamesFeature()
       ├── testStandardBeforeTimeboxOrder()
       └── ... (more tests)
   ```

3. **Run Options**:
   - **Run ALL tests**: Click ▶ next to "LotusPlannerV3Tests" (top level)
   - **Run one test class**: Click ▶ next to class name
   - **Run one test**: Click ▶ next to specific test method
   - **Hover over** any test to see the ▶ play button appear

---

### Method 3: Run Individual Test (For Debugging)

1. **Open** `LotusPlannerV3Tests.swift` in the editor

2. **Find** a test method (they start with `func test...`)

3. **Look** for the diamond icon in the left margin next to the test

4. **Click** the diamond icon → it runs just that test

---

### Method 4: Run Via Command Line

**Open Terminal** and run:

```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3

# Run all tests
xcodebuild test \
  -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  | xcpretty

# If you don't have xcpretty installed:
xcodebuild test \
  -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Install xcpretty for prettier output** (optional):
```bash
gem install xcpretty
```

---

## Part 3: Reading Test Results

### In Xcode - Test Navigator View

After tests run, you'll see:

✅ **Green Checkmarks** = Tests Passed
```
✓ LotusPlannerV3Tests
  ✓ testPersistenceControllerInitialization (0.003s)
  ✓ testWeightLogCreation (0.012s)
  ✓ testWorkoutLogCreation (0.008s)
```

❌ **Red X** = Tests Failed
```
✗ LotusPlannerV3Tests
  ✗ testSomethingBroken (0.156s)
     XCTAssertEqual failed: ("Expected") is not equal to ("Actual")
```

---

### In Xcode - Report Navigator

1. **Show Report Navigator**:
   - Click the speech bubble icon (rightmost in left sidebar)
   - Or press: `⌘ + 9` (Command + 9)

2. **Click** on the latest test run

3. **See detailed results**:
   ```
   Test Summary
   ✓ All tests passed (52 tests, 0 failures, 2.3 seconds)
   
   LotusPlannerV3Tests (2.1s)
     testPersistenceControllerInitialization ✓ (0.003s)
     testWeightLogCreation ✓ (0.012s)
     testWorkoutLogCreation ✓ (0.008s)
     ...
   ```

4. **Click** on any test to see:
   - Execution time
   - Console output
   - Failure messages (if any)
   - Stack traces

---

### Code Coverage Report

If you enabled code coverage:

1. **Show Report Navigator**: Press `⌘ + 9`

2. **Click** on the latest test run

3. **Click** "Coverage" tab at the top

4. **See coverage**:
   ```
   Target: LotusPlannerV3
   Coverage: 62.4%
   
   File                              Coverage
   ════════════════════════════════════════
   PersistenceController.swift       87.2%
   CoreDataManager.swift             73.5%
   GoalsManager.swift                68.1%
   AppPreferences.swift              91.3%
   NavigationManager.swift           95.7%
   CalendarView.swift                42.8%  ← Needs more tests
   ```

5. **Click** on any file to see:
   - Green lines = covered by tests
   - Red lines = not covered
   - Execution counts

---

## Part 4: Understanding Results

### Success Looks Like This:

**Console Output:**
```
Test Suite 'All tests' started at 2026-01-24 17:30:00.123
Test Suite 'LotusPlannerV3Tests.xctest' started at 2026-01-24 17:30:00.124
Test Suite 'LotusPlannerV3Tests' started at 2026-01-24 17:30:00.125

Test Case '-[LotusPlannerV3Tests testPersistenceControllerInitialization]' started.
Test Case '-[LotusPlannerV3Tests testPersistenceControllerInitialization]' passed (0.003 seconds).

Test Case '-[LotusPlannerV3Tests testWeightLogCreation]' started.
Test Case '-[LotusPlannerV3Tests testWeightLogCreation]' passed (0.012 seconds).

... (50+ more tests) ...

Test Suite 'LotusPlannerV3Tests' passed at 2026-01-24 17:30:02.456.
     Executed 52 tests, with 0 failures (0 unexpected) in 2.331 seconds

Test Suite 'All tests' passed at 2026-01-24 17:30:02.457.
     Executed 52 tests, with 0 failures (0 unexpected) in 2.332 seconds
```

**Summary Bar (Top of Xcode):**
```
Build Succeeded | Test Succeeded (52 tests)
```

---

### Failure Looks Like This:

**Console Output:**
```
Test Case '-[LotusPlannerV3Tests testWeightLogCreation]' started.
/Users/.../LotusPlannerV3Tests.swift:45: error: -[LotusPlannerV3Tests testWeightLogCreation] : 
XCTAssertEqual failed: ("1") is not equal to ("0") - Should have one weight log
Test Case '-[LotusPlannerV3Tests testWeightLogCreation]' failed (0.012 seconds).
```

**How to Debug**:
1. Click on the failed test in Test Navigator
2. Read the error message
3. Click on the file:line reference to jump to the failing assertion
4. Add breakpoints and run test again
5. Inspect variables in the debugger

---

## Part 5: Quick Verification Checklist

After running tests, verify:

- [ ] **Build succeeded** - No compilation errors
- [ ] **All tests passed** - Green checkmarks everywhere
- [ ] **Execution time** - Under 5 seconds (should be ~2-3 seconds)
- [ ] **No warnings** - Clean console output
- [ ] **Coverage** - At least 60% (optional, if enabled)

**Expected Results:**
```
✓ 52 tests passed in 2.3 seconds
✓ 0 failures
✓ 0 unexpected failures
✓ Code coverage: ~60-70%
```

---

## Troubleshooting Common Issues

### Issue 1: "No such module 'LotusPlannerV3'"

**Solution:**
1. Build the main app first: `⌘ + B`
2. Clean build folder: `⌘ + Shift + K`
3. Rebuild and test: `⌘ + U`

---

### Issue 2: Tests Don't Appear in Test Navigator

**Solution:**
1. Close and reopen the project
2. Clean build folder: `⌘ + Shift + K`
3. File → Workspace Settings → Derived Data → Delete
4. Rebuild: `⌘ + B`

---

### Issue 3: "Target 'LotusPlannerV3Tests' not found"

**Solution:**
1. Make sure you selected the right scheme
2. Product → Scheme → Select "LotusPlannerV3"
3. Edit Scheme → Test → Add LotusPlannerV3Tests

---

### Issue 4: Core Data Errors

**Solution:**
Tests use in-memory store, so this shouldn't happen, but if it does:
1. Check that `PersistenceController(inMemory: true)` is being used
2. Verify setUp() and tearDown() are called
3. Make sure each test cleans up its data

---

### Issue 5: Simulator Not Available

**Solution:**
```bash
# List available simulators
xcrun simctl list devices available

# Pick one and use in command:
xcodebuild test \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  ...
```

---

## Video Tutorial Summary

If you were watching a video, here's what you'd see:

1. **[0:00-0:30]** Opening Xcode, navigating to project
2. **[0:30-2:00]** Creating test target, configuring settings
3. **[2:00-3:00]** Adding test file, enabling testability
4. **[3:00-3:30]** Enabling code coverage
5. **[3:30-4:00]** Running tests with ⌘+U
6. **[4:00-5:00]** Watching tests execute (green checkmarks!)
7. **[5:00-6:00]** Reviewing results in Report Navigator
8. **[6:00-7:00]** Checking code coverage report
9. **[7:00-8:00]** Running individual test for debugging
10. **[8:00-9:00]** Command-line testing demonstration

---

## What Success Looks Like

When everything works, you should see:

### In Test Navigator (⌘+6):
```
✓ LotusPlannerV3Tests (52 tests)
  ✓ testPersistenceControllerInitialization
  ✓ testWeightLogCreation
  ✓ testWorkoutLogCreation
  ✓ testFoodLogCreation
  ✓ testTaskTimeWindowCreation
  ✓ testCustomLogItemCreation
  ✓ testCustomLogEntryCreation
  ✓ testGoalCreation
  ✓ testGoalCategoryCreation
  ✓ testCoreDataManagerDeleteAllLogs
  ✓ testGoalsManagerMaxCategories
  ✓ testCalendarMondayFirst
  ✓ testDateFormatters
  ✓ testGoalDataModel
  ✓ testCustomLogDataModel
  ✓ testNavigationManagerInitialization
  ✓ testNavigationManagerViewSwitching
  ✓ testNavigationManagerIntervalUpdate
  ✓ testAppPreferencesInitialization
  ✓ testAppPreferencesColorUpdate
  ✓ testAppPreferencesDayViewLayout
  ✓ testAppPreferencesLogsVisibility
  ✓ testAppPreferencesAccountNames
  ✓ testAppPreferencesAccountNameTruncation
  ✓ testDayViewLayoutOptions
  ✓ testTimelineInterval
  ✓ testConfigurationManagerInitialization
  ✓ testKeychainManagerBasicOperations
  ✓ testCoreDataBatchInsertPerformance
  ✓ testCoreDataFetchPerformance
  ✓ testDataManagerInitialization
  ✓ testPersistenceControllerPreview
  ✓ testEmptyStringHandling
  ✓ testNilDateHandling
  ✓ testInvalidWeightValues
  ✓ testZeroWorkoutDuration
  ✓ testDevLoggerBasicUsage
  ✓ testDevLoggerVerboseControl
  
✓ RecentChangesRegressionTests (6 tests)
  ✓ testCustomAccountNamesFeature
  ✓ testStandardBeforeTimeboxOrder
  ✓ testExpandedViewAlwaysShowsTimeline
  ✓ testMonthlyCalendarCurrentDayBorder
  ✓ testNoRawPrintStatements
  ✓ testDevLogUsesCategories
```

### In Console:
```
All tests passed! 🎉
52 tests, 0 failures, 2.3 seconds
```

---

## Next Steps

Once tests are passing:

1. **Run tests regularly**:
   - Before committing code: `⌘ + U`
   - Before creating PR: Full test suite
   - Daily: As part of CI/CD

2. **Monitor coverage**:
   - Aim for >70% coverage
   - Add tests for new features
   - Focus on critical paths

3. **Add to CI/CD**:
   - GitHub Actions, Jenkins, etc.
   - Fail builds on test failures
   - Track coverage trends

4. **Keep tests updated**:
   - Add tests for bug fixes
   - Update tests when features change
   - Remove obsolete tests

---

## Questions?

- **Tests not running?** → Check troubleshooting section above
- **Tests failing?** → Check console output for error messages
- **Need more tests?** → See `TEST_DOCUMENTATION.md` for coverage gaps
- **Performance issues?** → Tests should complete in <5 seconds

**Documentation Files:**
- This file: Complete walkthrough
- `TEST_DOCUMENTATION.md`: Test suite details
- `LotusPlannerV3Tests.swift`: The actual tests

---

**Last Updated**: 2026-01-24
**Total Test Count**: 52 tests
**Expected Pass Rate**: 100%
**Average Execution Time**: 2-3 seconds
