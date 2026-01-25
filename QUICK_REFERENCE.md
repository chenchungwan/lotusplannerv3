# Quick Reference: Running Tests

## One-Time Setup ✓

```
┌─────────────────────────────────────────────┐
│ 1. Open Xcode Project                       │
│    open LotusPlannerV3.xcodeproj           │
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│ 2. Add Test Target                          │
│    Click project → + button → Unit Testing  │
│    Name: LotusPlannerV3Tests               │
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│ 3. Add Test File                            │
│    Right-click Tests folder → Add Files     │
│    Select: LotusPlannerV3Tests.swift       │
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│ 4. Enable Testability                       │
│    Main target → Build Settings             │
│    Enable Testability → Yes (Debug)         │
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│ 5. Enable Code Coverage (Optional)          │
│    Product → Scheme → Edit Scheme           │
│    Test → ☑ Code Coverage                   │
└─────────────────────────────────────────────┘
```

## Running Tests 🏃

### Quick Run (Keyboard)
```
⌘ + U  →  Runs ALL tests
```

### Visual Run (Mouse)
```
1. Press ⌘ + 6 (Test Navigator)
2. Click ▶ next to test you want to run
```

### Menu Run
```
Product → Test
```

### Command Line
```bash
cd LotusPlannerV3
xcodebuild test -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Reading Results 📊

### Test Navigator (⌘ + 6)
```
✓ Green checkmark = Passed
✗ Red X          = Failed
○ Gray circle    = Not run
```

### Report Navigator (⌘ + 9)
```
Click latest test run
→ See summary
→ Click "Coverage" for coverage report
```

### Console Output
```
✓ SUCCESS:
  Test Suite 'All tests' passed
  52 tests, 0 failures, 2.3 seconds

✗ FAILURE:
  XCTAssertEqual failed: ("1") is not equal to ("0")
  /path/to/file.swift:45
```

## Expected Results ✅

```
┌───────────────────────────────┐
│ ✓ 52 tests passed            │
│ ✓ 0 failures                 │
│ ✓ ~2-3 seconds execution     │
│ ✓ 60-70% code coverage       │
└───────────────────────────────┘
```

## Quick Troubleshooting 🔧

| Problem | Solution |
|---------|----------|
| Module not found | ⌘+B then ⌘+U |
| Tests don't appear | ⌘+Shift+K then ⌘+B |
| Slow first run | Normal (compiling) |
| Simulator error | Change destination |

## Test Categories Covered ✓

- [x] Core Data (8 entities)
- [x] Managers (4 managers)
- [x] App Preferences
- [x] Navigation
- [x] Calendar Utils
- [x] Data Models
- [x] Security (Keychain)
- [x] Performance
- [x] Edge Cases
- [x] Recent Changes

## Keyboard Shortcuts 

```
⌘ + U          Run tests
⌘ + 6          Test Navigator
⌘ + 9          Report Navigator
⌘ + B          Build
⌘ + Shift + K  Clean Build
⌘ + <          Edit Scheme
```

## Files Created 📁

```
✓ LotusPlannerV3Tests/LotusPlannerV3Tests.swift
✓ TEST_DOCUMENTATION.md
✓ TEST_SETUP_GUIDE.md
✓ HOW_TO_RUN_TESTS.md (detailed)
✓ QUICK_REFERENCE.md (this file)
```

---

**Print this page for quick reference!**
