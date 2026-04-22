# Mac Drag-and-Drop Regression — Investigation Notes

**Status:** Unresolved. All work on the `fixmac` branch was discarded — no commits were merged.
**Last investigated:** 2026-04-22

## Symptom

On Mac (Designed for iPad build), dragging any draggable item produces a
visible drag preview that follows the cursor, but releasing never applies
the drop — the preview disappears and the original element stays in place.

Affected views:
- `WeeklyView` — dragging tasks between day columns
- `TimeboxView` — dragging tasks / events to different day/time slots
- `DayViewCustomConfigurator` — dragging components from the palette into grid cells
- `SettingsView` — any drag-to-reorder inside the settings sheet
- Possibly `GoalsView` reorder (not individually verified)

iPad and iPhone are **unaffected** — drag/drop works correctly on both.

User reports drag/drop worked on Mac before the custom day view merge
(commit `9e1b14e`), but could not pin down the exact last-working build.

## What We Proved With Diagnostic `NSLog` Calls

Sources of truth: instrumented every `.onDrag { ... }` closure and every
`DropDelegate` method with `NSLog("LP_DRAG ...")` so log output would not
be filtered by OSLog levels or Console.app filters.

- **Drag sources DO fire on Mac.** Confirmed across:
  - `TasksComponent.row.onDrag` (task rows)
  - `TimeboxComponent.onDrag` (timeline tasks)
  - `TimeboxView.allday.task.onDrag` (all-day task tiles)
- **Drop callbacks NEVER fire on Mac.** Confirmed by forcing
  `TimeboxDropDelegate.validateDrop` to unconditionally return `true` and
  logging entry to every callback — not one of `dropEntered`, `dropExited`,
  `dropUpdated`, `validateDrop`, or `performDrop` fires on Mac when the
  drag is released over what should be a valid drop zone.
- `dropUpdated` is especially telling: it is normally called many times a
  second while the drag preview is inside the drop zone. Zero calls on Mac
  means the drop zone is **not receiving drag-session events at all.**

So this is not a UTI-matching bug, not a `validateDrop`-returning-false
bug, and not a handler-logic bug. The drop modifier itself is inert on Mac.

## Theories Tried And Ruled Out

Each of these was implemented, built successfully, and tested on Mac. None
changed the Mac behavior.

1. **Transferable `.json` content-type collision.** `DraggableTaskInfo`
   (WeeklyView) and `ComponentDragPayload` (configurator) both declared
   `CodableRepresentation(contentType: .json)`, so Mac's Transferable
   resolver might have confused them. Converting `ComponentDragPayload` to
   a plain `Codable` with an `NSItemProvider`-based drag pipeline did not
   restore Mac drop events.
2. **Legacy vs. Transferable mismatch.** Converting WeeklyView's
   Transferable-based drops (`.draggable` + `.dropDestination(for:)`) to
   the legacy `.onDrag { NSItemProvider(...) }` + `.onDrop(of: [.plainText])`
   pipeline — matching what TimeboxView has always used — did not help.
3. **`NSString`-published UTI mismatch.** On Mac,
   `NSItemProvider(object: someString as NSString)` advertises as
   `public.utf8-plain-text`, and a drop zone filtering by
   `[.plainText]` might not see it as conforming. Broadening the accepted
   types to `[.plainText, .utf8PlainText, .text]`, then to
   `[.item, .data, .plainText, .utf8PlainText, .text]`, did not help.
4. **`loadItem(forTypeIdentifier:)` mismatch.** Changed all drop handlers
   to try `utf8PlainText` first and fall back to `plainText`. Did not help
   (drop handlers never get called anyway).
5. **`validateDrop` rejecting.** Forced `TimeboxDropDelegate.validateDrop`
   to always return `true`. Still never called.

## Leading Unverified Theories

### 1. Nested `ScrollView`s eating drop events on Mac (most likely)

Both `WeeklyView.weekTasksContent` and `TimeboxView.timeboxColumn` are
rendered inside nested scroll views (horizontal outer + vertical inner).
There are reports in the SwiftUI community that on "Designed for iPad"
Mac builds the UIKit-on-macOS runtime's scroll view can swallow drag
session events before they reach inner `.onDrop` modifiers. This would
explain why `dropUpdated`/`validateDrop` never fires even though the
drag source runs normally.

iPad is unaffected either because iPad's UIScrollView cooperates with
UIDragInteraction correctly, or because the gesture arbitration on iPad
differs from the macOS runtime path.

This matches the user's recollection that drag worked before the custom
day view merge — **if** the merge added any wrapping that changed how
the scroll views host the drop targets. The customize merge itself did
not obviously change scroll-view structure, but it did add
`CustomDayViewConfig.startSync()` to `LotusPlannerV3App.init()` and a
second `Transferable` type to the app. Neither alone is a known cause of
this particular symptom.

### 2. A global modifier / gesture added by the customize merge

The customize merge (`9e1b14e`) and the sync/group commit (`5c093ee`)
added:
- `ComponentDragPayload: Transferable` with `.json` content type (since
  reverted in experiments — no effect).
- `Menu { Button("Log") { ... } }` entries inside the `+` menu in
  `GlobalNavBar`.
- Reordering of log sections in `SettingsView` (uses `.onMove`, scoped to
  the Settings list — shouldn't affect app-level gestures).
- `@MainActor CustomDayViewConfig.startSync()` called from the App's
  `init()`, which runs `NSUbiquitousKeyValueStore.synchronize()` twice
  synchronously on the main thread at launch and installs a
  `didChangeExternallyNotification` observer.

None obviously touch the gesture system. But removing `Transferable`
from `ComponentDragPayload` (the only drag-related addition) did not
restore Mac drops, so if the merge is the cause, it's via something
subtler.

### 3. Xcode / macOS SDK regression

The Designed-for-iPad Mac runtime evolves across OS releases. It's
possible that a recent macOS/Xcode update broke this pattern
independently of our code. This is consistent with the user's recall of
it working "before" but being unable to pin down a build — it may have
regressed at an OS-level update the user installed around the same time
as the custom day view work.

## What To Try Next

In rough order of cost vs. likelihood of resolving it:

1. **Run the pre-customize commit on Mac.** Check out `71eff36` (the
   commit immediately before the custom day view merge). Clean build.
   Run on Mac. Drag a task.
   - If drag works at `71eff36`: bisect forward between `71eff36` and
     `5c093ee` by commit to identify the breaker.
   - If drag does NOT work at `71eff36`: the regression is older than we
     thought, and bisecting further back will find it — or it's an OS/SDK
     regression independent of the app.

2. **Test `.draggable` + `.dropDestination(for: String.self)`** in
   isolation on Mac (this is what `GoalsView` uses). If that simple
   built-in Transferable case also fails on Mac, the regression is not
   specific to anything custom and points at #3 above.

3. **Bypass SwiftUI with UIKit.** Wrap each drop target in a
   `UIViewRepresentable` whose `UIView` attaches a `UIDropInteraction`
   directly. This is the escape hatch; known to work on Mac Catalyst
   and Designed-for-iPad builds because it avoids the SwiftUI-hosted
   drop modifier entirely. More code, but proven.

4. **Move `.onDrop` out of the ScrollView.** Instead of attaching drop
   handlers to per-day-column views, attach a single drop handler to
   the ScrollView's ancestor and compute the target day from the drop
   location's `x` coordinate. Speculative but cheap.

5. **Add a bare SwiftUI drop test harness.** A dedicated debug view with
   a rectangle that uses `.onDrop(of: [.plainText])` and a rectangle
   that uses `.onDrag { NSItemProvider(object: "x" as NSString) }`, no
   ScrollView, no other chrome. If this also fails on Mac, SwiftUI
   `.onDrop` is broken in this build configuration globally (and we
   need path #3). If it works, the problem is our view hierarchy
   (probably the ScrollView nesting).

## How To Reproduce The Diagnostic Logging (If Picking This Back Up)

The `fixmac` branch is deleted; to re-instrument:

- In every `.onDrag { ... }` closure, add `NSLog("LP_DRAG <site>: ...")`
  before `return NSItemProvider(...)`.
- Implement the full `DropDelegate` protocol with `NSLog` in every
  method (`dropEntered`, `dropExited`, `dropUpdated`, `validateDrop`,
  `performDrop`). Make `validateDrop` unconditionally return `true`
  during diagnosis.
- Build from Xcode (not TestFlight) with "My Mac (Designed for iPad)"
  as the destination — TestFlight builds do not have the new logs.
- In Console.app: `process:LotusPlannerV3` filter, search for
  `LP_DRAG`. Or use Xcode's own console pane, which is unfiltered.

`NSLog` is used instead of the project's `devLog` because it bypasses
OSLog levels and Console filters that mask `devLog .debug`/`.info` on
Mac by default.

## Files Most Relevant

- `LotusPlannerV3/LotusPlannerV3/WeeklyView.swift` — `DraggableTaskInfo`,
  `.dropDestination` per task column, `handleTaskDrop`, `handleEventDrop`.
- `LotusPlannerV3/LotusPlannerV3/TasksComponent.swift` — task row
  `.draggable(DraggableTaskInfo)`; list card `.onDrag`.
- `LotusPlannerV3/LotusPlannerV3/TimeboxView.swift` — `TimeboxDropDelegate`,
  timebox column `.onDrop(of: [.plainText], delegate:)`, all-day
  event/task `.onDrag`.
- `LotusPlannerV3/LotusPlannerV3/TimeboxComponent.swift` — timeline
  task/event `.onDrag`.
- `LotusPlannerV3/LotusPlannerV3/NewUIs/DayViewCustomConfigurator.swift`
  — `ComponentDragPayload: Codable, Transferable`, palette `.draggable`,
  `CellDragModifier`.
- `LotusPlannerV3/LotusPlannerV3/LotusPlannerV3App.swift` — calls
  `CustomDayViewConfig.startSync()` at launch.
- `LotusPlannerV3/LotusPlannerV3/LotusPlannerV3.entitlements` — sandbox
  entitlements (photos-library added in `4f50f3e`).

## Commits Worth Knowing

- `71eff36` — last commit before the custom day view work (good bisect
  starting point for "known working if user's memory is correct").
- `9e1b14e` — first custom day view commit.
- `5c093ee` — follow-up adding iCloud sync + groups.
- `4f50f3e` — added `com.apple.security.personal-information.photos-library`
  entitlement for Mac sandbox. Precedes the custom day view merge and is
  unlikely to be related, but listed here because it's the only other
  Mac-specific change in recent history.
