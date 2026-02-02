## How Page-by-Page Swipable/Scrollable Navigation Is Constructed

### Core Mechanism: `TabView` with Page Style

The entire navigation system is built on a single SwiftUI `TabView` configured with `.tabViewStyle(.page(indexDisplayMode: .never))` (iOS only). This gives the app native page-curl swipe gestures between pages, with the index dots hidden.

**Key state:** A single `@State private var currentPage = 0` integer in `BookView` drives which page is visible. The `TabView` is bound to this via `TabView(selection: $currentPage)`.

```
BookTestApp → ContentView → BookView (owns the TabView + currentPage state)
```

### Page Generation (compile-time, not lazy)

All pages are generated upfront in `BookView.init()` by calling `PageGenerator.generatePages(for: 2026)`, which returns an array of `[PageContent]` — an enum with five cases:

```swift
enum PageContent {
    case cover
    case year(Int)
    case month(Int, Int)   // month, year
    case week(Date)        // start date (Monday)
    case day(Date)
}
```

`PageGenerator` builds the array in this fixed order:

| Section | Pages | Indices (approx) |
|---------|-------|-------------------|
| Cover | 1 | 0 |
| Year overview | 1 | 1 |
| 12 Month views | 12 | 2–13 |
| ~52 Week views | ~52 | 14–65 |
| 365 Day views | 365 | 66–430 |

**Total: ~431 pages**, all materialized as enum values in a `[PageContent]` array stored as a `let` property on `BookView`.

### Rendering Pages Inside the TabView

`BookView.body` iterates the full array with `ForEach(0..<pages.count, id: \.self)` inside the `TabView`. Each index is tagged with `.tag(index)` so the `selection` binding can address it:

```swift
TabView(selection: $currentPage) {
    ForEach(0..<pages.count, id: \.self) { index in
        pageView(for: pages[index])
            .tag(index)
    }
}
```

The `pageView(for:)` method pattern-matches the `PageContent` enum to instantiate the correct SwiftUI view (`BookCoverView`, `YearView`, `MonthView`, `WeekView`, or `DayView`).

### Three Navigation Mechanisms

#### 1. Swipe/Scroll (built-in)

The `TabView` with `.page` style provides native horizontal swipe gestures. Swiping left advances `currentPage` by 1; swiping right decrements it. No custom gesture code is needed — this is entirely handled by SwiftUI's `TabView`.

#### 2. Programmatic Jump via `onNavigate` Callbacks

`YearView`, `MonthView`, and `WeekView` each accept an optional closure `onNavigate: ((PageContent) -> Void)?`. When a user taps an interactive element (a day number, a week number label), the view calls this closure with the target `PageContent` value:

```
YearView:  tap day number  → onNavigate?(.day(date))
           tap week label   → onNavigate?(.week(date))

MonthView: tap day number  → onNavigate?(.day(date))
           tap week label   → onNavigate?(.week(date))

WeekView:  tap day row     → onNavigate?(.day(date))
```

In `BookView.pageView(for:)`, each view receives `navigateToPage` as the callback:

```swift
case .year(let year):
    YearView(year: year, onNavigate: navigateToPage)
```

`navigateToPage` calls `findPageIndex(for:)`, which does a linear search through the `pages` array to find the matching index, then sets `currentPage` inside `withAnimation`:

```swift
private func navigateToPage(to content: PageContent) {
    if let index = findPageIndex(for: content) {
        withAnimation {
            currentPage = index
        }
    }
}
```

`findPageIndex` handles three cases:
- **`.week(targetDate)`**: Finds the week page whose Monday–Sunday range contains the target date.
- **`.day(targetDate)`**: Finds the exact day page matching `calendar.isDate(_:inSameDayAs:)`.
- **`.month(m, y)`**: Finds the page with matching month and year numbers.

`DayView` does **not** receive an `onNavigate` callback — it is a leaf page with no outbound navigation links.

#### 3. Global Navigation Overlays (ZStack)

Two persistent UI elements are layered on top of the `TabView` in a `ZStack`:

**GlobalNavBar** (top center): A "Today" button that calls `navigateToToday()`, which searches the `pages` array for a `.day` entry matching today's date and jumps to it.

**MonthTabBar** (right edge): 12 single-letter tabs (J, F, M, ..., D). `BookView.init()` pre-computes a `monthPageIndices: [Int: Int]` lookup table mapping month numbers to their page indices. Tapping a tab calls `onMonthSelected`, which reads the index from this dictionary and sets `currentPage` with animation.

The currently active month is highlighted by reading `currentMonthNumber`, a computed property that checks whether the current page is a `.month` case and extracts its month number.

### Platform Handling

The `.tabViewStyle(.page(indexDisplayMode: .never))` modifier is wrapped in `#if os(iOS)`. On macOS and visionOS, the `TabView` falls back to its default tab style. This means the page-curl swipe behavior is iOS-only; other platforms would use standard tab switching.

### State Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│  BookView                                           │
│                                                     │
│  @State currentPage: Int  ◄─────────────────────┐   │
│       │                                         │   │
│       ▼                                         │   │
│  TabView(selection: $currentPage)               │   │
│       │                                         │   │
│       ├── page 0: BookCoverView                 │   │
│       ├── page 1: YearView(onNavigate:)────────►│   │
│       ├── pages 2-13: MonthView(onNavigate:)───►│   │
│       ├── pages 14-65: WeekView(onNavigate:)───►│   │
│       └── pages 66-430: DayView (no callback)   │   │
│                                                 │   │
│  ZStack overlays:                               │   │
│       ├── GlobalNavBar "Today" ─────────────────►   │
│       └── MonthTabBar (12 tabs) ────────────────►   │
└─────────────────────────────────────────────────────┘
```

All navigation ultimately converges on a single operation: setting `currentPage` to a new integer index, which the `TabView` selection binding picks up to display the corresponding page.

### Key Design Observations

- **No lazy loading.** All 431 `PageContent` enum values are generated at init time. However, SwiftUI's `TabView` with page style only renders the visible page and its immediate neighbors, so the enum-level cost is just memory for the array, not 431 rendered views.
- **Linear search for jump navigation.** `findPageIndex` uses `Array.firstIndex(where:)` — O(n) on ~431 elements. The `monthPageIndices` dictionary is the one exception, providing O(1) lookup for month tabs.
- **Single source of truth.** The `currentPage` integer is the only navigation state. There is no navigation stack, no router, no coordinator. All navigation — swipe, tap, and toolbar — writes to this one binding.
- **Animation.** All programmatic jumps wrap `currentPage` assignment in `withAnimation { }`. The `TabView` page style animates the transition. Swipe gestures animate natively.
