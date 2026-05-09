# Drawing Feature in the W (Weekly) View — `weekDraw` branch

This document analyzes the drawing-feature implementation that lives on
the `weekDraw` branch (last commit: `d538aff` — "drawing works but not
saving after first save"). It does not exist on `main`. The analysis
below is intended as a reference for a future port — what's there, how
it's wired, and known issues to fix before merging.

## TL;DR

- The drawing UI is **not** part of the existing `WeeklyView` (the W
  view that ships on `main`). The `weekDraw` branch ships a parallel
  weekly view called **`SimpleWeekView`** with a transparent PencilKit
  canvas overlaid on top of the timeline.
- A pencil button in `GlobalNavBar` (only when
  `currentView == .simpleWeekView`) toggles drawing mode via
  `NotificationCenter`.
- Strokes save to **CloudKit** (not Core Data, not iCloud Documents)
  in a private database, one record per ISO week.
- **Known bug** (per the branch's own commit message): drawings save
  the first time but fail on subsequent saves for the same week,
  because the storage layer recreates a fresh `CKRecord` instead of
  fetching-then-modifying.

## Files

| File | Lines | Role |
| --- | ---: | --- |
| `SimpleWeekView.swift` | 952 | The view itself — week grid + transparent drawing overlay + drawing-mode lifecycle. |
| `SimpleWeekDrawingStorage.swift` | 127 | Singleton that saves/loads/deletes/checks `PKDrawing` records in CloudKit, keyed by week. |

Plus integration points in `HomeView.swift` (case dispatch) and
`NewUIs/GlobalNavBar.swift` (pencil button + drawing-mode highlight).

## Activation flow

1. **Switch into the view.** `SettingsView.switchToSimpleWeekView()`
   sets `navigationManager.currentView = .simpleWeekView` and
   `currentInterval = .week`. `HomeView` then renders `SimpleWeekView()`
   for that case ([`HomeView.swift:78`](../LotusPlannerV3/LotusPlannerV3/HomeView.swift#L78)).

2. **Show the pencil button.** `GlobalNavBar` conditionally renders a
   pencil icon only when `currentView == .simpleWeekView`
   ([`GlobalNavBar.swift:532-542`](../LotusPlannerV3/LotusPlannerV3/NewUIs/GlobalNavBar.swift#L532-L542)).
   Tapping it posts a `Notification.Name("ToggleSimpleWeekDrawing")`.

3. **Toggle drawing mode.** `SimpleWeekView` listens for that
   notification in `.onAppear` and flips an `@State var isDrawingMode`
   ([`SimpleWeekView.swift:754-773`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L754-L773)).
   `GlobalNavBar` also listens to the same notification to track its
   own `isSimpleWeekDrawingMode` mirror state for the pencil-button
   tint color ([`GlobalNavBar.swift:997-999`](../LotusPlannerV3/LotusPlannerV3/NewUIs/GlobalNavBar.swift#L997-L999)).
   The two listeners are independent — they happen to both observe the
   same notification rather than sharing a single source of truth.

## The transparent canvas

The week timeline is drawn as a normal SwiftUI `ScrollView` containing
seven `timedEventsColumn` views in an `HStack`. The drawing surface is
a sibling `TransparentDrawingCanvas` placed in the *same* `ZStack` so
strokes register at consistent timeline coordinates regardless of
which day column the pen lands in.

```
ZStack(alignment: .topLeading) {
    HStack { /* 7 day columns */ }            // timeline content
    if isDrawingMode || !drawing.strokes.isEmpty {
        TransparentDrawingCanvas(...)          // overlay
            .frame(width: geo.size.width,
                   height: hourHeight * 24)    // 24-hour-tall canvas
            .allowsHitTesting(isDrawingMode)
            .zIndex(isDrawingMode ? 1000 : 999)
    }
}
.scrollDisabled(isDrawingMode)
```

Key behaviors of the overlay:

- The canvas is **24 hours tall** even though the scroll view shows
  only **10 hours at a time** (`hourHeight = availableHeight / 10.0`,
  [`SimpleWeekView.swift:148`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L148)).
  Strokes anchor to absolute hours, not the visible window.
- `allowsHitTesting(isDrawingMode)` keeps the canvas inert when not
  in drawing mode, so taps still hit underlying event blocks.
- `.scrollDisabled(isDrawingMode)` freezes the timeline scroll while
  drawing, so a pen-stroke can't double as a pan gesture. Side effect:
  the user can only draw on whatever 10-hour slice is currently
  visible — entering drawing mode is a commitment to that slice.
- The canvas mounts only when `isDrawingMode || !drawing.strokes.isEmpty`,
  so there's no PencilKit footprint on a brand-new empty week.

`TransparentDrawingCanvas` is a `UIViewRepresentable` over `PKCanvasView`
([`SimpleWeekView.swift:794-858`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L794-L858)):

- `tool = PKInkingTool(.pen, color: .black, width: 2)` — black 2pt pen
  default; the `PKToolPicker` overrides this once the user picks
  another tool.
- `drawingPolicy = .anyInput` and `allowsFingerDrawing = true` —
  finger or Pencil both work.
- `backgroundColor = .clear`, `isOpaque = false` — required for the
  timeline to remain visible behind the strokes.
- A `Coordinator: PKCanvasViewDelegate` forwards `canvasViewDrawingDidChange`
  to an `onDrawingChanged: () -> Void` closure passed in from the
  parent.

The tool picker is the **scene-shared** `PKToolPicker` (the system
floating palette). It's attached lazily inside `makeUIView`'s
`DispatchQueue.main.async` block via
`PKToolPicker.shared(for: window)` so the canvas is already in a
window hierarchy when we ask for the picker. Visibility tracks the
`showsToolPicker` binding, which `SimpleWeekView` ties to
`isDrawingMode`.

`SimpleWeekView` also defines two extra `UIViewRepresentable` types
that aren't used in production: **`WorkingCanvasView`** (red 5pt pen on
white-10%-alpha) and **`TestCanvasView`** (red 5pt pen on white-80%-alpha).
These look like debugging scaffolds left in during development. A
clean port should drop them.

## Save / load lifecycle

### Trigger points

- **On stroke change** ([`SimpleWeekView.swift:218-222`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L218-L222)):
  the `onDrawingChanged` callback calls `debouncedSaveDrawing()`,
  which schedules a 1-second-delayed save via a cancellable `Task`
  stored in `@State var saveTask` ([`SimpleWeekView.swift:28-54`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L28-L54)).
  Subsequent stroke changes cancel the pending task and queue a new
  one, so a flurry of strokes results in a single save 1s after the
  user stops.
- **On exiting drawing mode** ([`SimpleWeekView.swift:766-771`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L766-L771)):
  cancel the pending debounced save, then call `saveDrawingToiCloud()`
  immediately so an exit-while-debouncing doesn't lose the most recent
  strokes.
- **On view appear and on date change** ([`SimpleWeekView.swift:743-751`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L743-L751)):
  `loadDrawingFromiCloud()` clears the canvas, then asynchronously
  loads the persisted drawing (if any) for the new week.

### Storage key

Each week gets a record name like:

```
simple_week_drawing_2026-05-04_to_2026-05-11
```

…computed from `Calendar.mondayFirst.dateInterval(of: .weekOfYear, …)`
in [`SimpleWeekDrawingStorage.weekKey(for:)`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekDrawingStorage.swift#L17-L29).
Worth noting: there's a near-duplicate copy of the same key-builder in
`SimpleWeekView.getCurrentWeekKey()` ([`SimpleWeekView.swift:80-92`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekView.swift#L80-L92))
that's used only for log lines. If we port this, dedupe by exposing
`weekKey(for:)` from the storage type.

### Persistence

`SimpleWeekDrawingStorage` ([file](../LotusPlannerV3/LotusPlannerV3/SimpleWeekDrawingStorage.swift))
talks directly to `CKContainer.default().privateCloudDatabase`. It is
**not** wired through the existing `iCloudManager` /
`PersistenceController` Core Data + CloudKit stack the rest of the app
uses. The record schema:

| Field | Type | Notes |
| --- | --- | --- |
| `weekKey` | `String` | Mirror of recordID, useful for queries. |
| `drawingData` | `Data` | `PKDrawing.dataRepresentation()`. |
| `lastModified` | `Date` | Set on every save. |

`recordType = "SimpleWeekDrawing"`. The record's CloudKit schema does
not exist yet in the production zone — first deploy needs the schema
deployed via the CloudKit dashboard or by letting the development
environment auto-provision on first save.

## The known save bug

The branch's most recent commit message is *"drawing works but not
saving after first save"*. The bug is in
[`SimpleWeekDrawingStorage.saveDrawing(_:for:)`](../LotusPlannerV3/LotusPlannerV3/SimpleWeekDrawingStorage.swift#L33-L57):

```swift
let record = CKRecord(recordType: "SimpleWeekDrawing",
                      recordID: CKRecord.ID(recordName: weekKey))
record["weekKey"]      = weekKey
record["drawingData"]  = drawingData
record["lastModified"] = Date()
let _ = try await database.save(record)
```

This builds a **brand-new** `CKRecord` on every call, which means it
has no `recordChangeTag`. CloudKit treats this as "create a record
that doesn't exist." The first save succeeds because the record really
doesn't exist; every save afterward fails with a server-record-changed
error because the recordID is taken and the etag mismatches. The error
is then silently swallowed by the `print` in the `catch` block — the
`saveDrawing` call doesn't surface the failure to the caller, so the
UI keeps debouncing and "saving" with no user-facing indication that
nothing is making it to iCloud.

**Fix patterns** (any one of these works):

1. `database.record(for: id)` first, mutate the returned record, then
   save the same instance — preserves the etag.
2. `CKModifyRecordsOperation` with `savePolicy = .changedKeys` (or
   `.allKeys`) — explicitly opts into clobbering the server record.
3. Catch `.serverRecordChanged` from the `database.save` call, fetch
   the server record, copy our fields onto it, and retry — the
   "lazy" upsert pattern.

(2) is the simplest if we don't need conflict-resolution semantics.

## Other smells worth fixing on a clean port

1. **Singleton coupling.** `SimpleWeekView` reads
   `DataManager.shared.calendarViewModel` and
   `DataManager.shared.tasksViewModel`. On `main`, both are now
   accessible directly via `CalendarViewModel.shared` /
   `TasksViewModel.shared` — match the post-refactor convention.
2. **Two listeners for one toggle.** `SimpleWeekView` and
   `GlobalNavBar` both observe `ToggleSimpleWeekDrawing` and keep
   their own `Bool` mirror. A single source of truth on
   `NavigationManager` (or a tiny `DrawingModeManager.shared`) would
   eliminate the desync risk if either listener registers late.
3. **Duplicated `weekKey` builder.** Lives in
   `SimpleWeekDrawingStorage` *and* `SimpleWeekView`. Keep one.
4. **Logging volume.** Every save/load/clear path logs ~3 lines via
   `print(...)`. Should be `devLog(...)` at `.debug` once the feature
   is stable, per the repo's logging convention
   (see [`docs/CLAUDE.md`](../CLAUDE.md) under "Logging").
5. **Dead canvas variants.** `WorkingCanvasView` and `TestCanvasView`
   are unused at present and can be deleted. Also `@State var canvasView`
   (line 13) is declared but never used — only `drawingCanvasView` is
   wired up.
6. **Scroll-locked-while-drawing UX.** Because `scrollDisabled(isDrawingMode)`
   freezes the timeline, the user can't draw across hours that aren't
   currently on screen without exiting drawing mode, scrolling, and
   re-entering. Worth deciding whether that's intended or whether we
   want a "draw + pan" gesture model.
7. **Per-week granularity.** Drawings are keyed to the
   Monday-Sunday week. Navigating to a different week loads a
   different drawing; navigating to a different *interval* (e.g.,
   month) doesn't apply because `SimpleWeekView` is week-only by
   design (`SettingsView.switchToSimpleWeekView()` forces
   `currentInterval = .week`).

## Suggested port plan

If/when this gets merged into `main`, the cheapest order is:

1. Bring over `SimpleWeekView.swift` and `SimpleWeekDrawingStorage.swift`
   as-is, plus the `HomeView` / `GlobalNavBar` / `SettingsView`
   integration points.
2. Fix the CloudKit save bug (option 2 above is fewest lines).
3. Replace `DataManager.shared.tasksViewModel` etc. with the singleton
   accessors (`TasksViewModel.shared`).
4. Delete `WorkingCanvasView`, `TestCanvasView`, and the unused
   `canvasView` `@State`.
5. Centralize `weekKey(for:)` in the storage type and remove the
   duplicate from the view.
6. Convert `print(...)` → `devLog(..., level: .debug, category: .cloud)`.
7. Decide on the scroll-vs-draw gesture model and either accept the
   scroll lock or add a draw/pan toggle inside drawing mode.

Steps 1-2 land the feature working; 3-7 are cleanup that brings it in
line with the rest of the codebase.
