# Setting Up Test Target for LotusPlannerV3

## Quick Setup Guide

The test target needs to be added through Xcode. Here's how:

### Step 1: Add Test Target in Xcode

1. Open `LotusPlannerV3.xcodeproj` in Xcode
2. Select the project in the navigator
3. Click the "+" button at the bottom of the targets list
4. Choose "Unit Testing Bundle"
5. Name it: `LotusPlannerV3Tests`
6. Set "Target to be Tested": `LotusPlannerV3`
7. Click "Finish"

### Step 2: Add Test File

The test file has already been created at:
```
/Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3Tests/LotusPlannerV3Tests.swift
```

If the folder doesn't exist in Xcode:
1. Right-click on project root
2. Select "Add Files to LotusPlannerV3..."
3. Navigate to and select `LotusPlannerV3Tests/LotusPlannerV3Tests.swift`
4. Ensure it's added to the `LotusPlannerV3Tests` target

### Step 3: Configure Test Target

In the test target's Build Settings:
- **Product Name**: `LotusPlannerV3Tests`
- **Bundle Identifier**: `com.chenchungwan.LotusPlannerV3Tests`
- **Test Host**: `$(BUILT_PRODUCTS_DIR)/LotusPlannerV3.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LotusPlannerV3`

### Step 4: Add Dependencies

Ensure the test target can access the main app:
1. Select test target
2. Go to "Build Phases"
3. Expand "Link Binary With Libraries"
4. Add any necessary frameworks (should be inherited)

### Step 5: Enable Testability

In the main app target's Build Settings:
1. Find "Enable Testability"
2. Set to `Yes` for Debug configuration

### Step 6: Run Tests

Run tests with:
- Keyboard: `⌘+U`
- Menu: Product → Test
- Test Navigator: Click play button next to test class/method

## Alternative: Command Line Setup

If you prefer to set up via command line (more complex):

```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3

# This would require pbxproj manipulation
# Recommended to use Xcode UI instead
```

## Verify Setup

After setup, verify:
```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3
xcodebuild test -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected output: All tests pass

## Test Coverage

Once setup, view coverage:
1. In Xcode, enable code coverage:
   - Edit Scheme → Test
   - Check "Code Coverage"
   - Select "LotusPlannerV3" target
2. Run tests (⌘+U)
3. View Report Navigator → Coverage tab

## Troubleshooting

### "No such module LotusPlannerV3"
- Ensure main app builds successfully first
- Verify `@testable import LotusPlannerV3` is correct
- Check target membership of test files

### Tests Not Appearing
- Clean build folder (⌘+Shift+K)
- Rebuild (⌘+B)
- Refresh test navigator

### Import Errors
- Ensure test target has access to main app
- Check "Enable Testability" is set
- Verify module name matches

## Files Created

1. **Test Suite**: `/LotusPlannerV3Tests/LotusPlannerV3Tests.swift`
   - 50+ comprehensive test cases
   - Covers all major functionality
   - Includes regression tests for recent changes

2. **Documentation**: `/TEST_DOCUMENTATION.md`
   - Complete test documentation
   - Coverage analysis
   - Maintenance guidelines

3. **This File**: `/TEST_SETUP_GUIDE.md`
   - Setup instructions
   - Troubleshooting tips

## Next Steps

After setup:
1. Run all tests to verify they pass
2. Review test coverage report
3. Add tests for any uncovered areas
4. Integrate into CI/CD pipeline
5. Run tests before each commit/PR

## Notes

- Tests use in-memory Core Data store (fast, isolated)
- No network calls (tests are unit tests, not integration tests)
- Google API and iCloud sync require separate mock setup
- UI tests require separate UI test target
