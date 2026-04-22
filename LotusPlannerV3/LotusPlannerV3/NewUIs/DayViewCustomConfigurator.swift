import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// A single component the user can drop on the custom day-view grid.
enum CustomComponent: String, Codable, Identifiable, Hashable, CaseIterable {
    case eventsTimeline
    case eventsList
    case tasksPersonalGrouped
    case tasksProfessionalGrouped
    case tasksPersonalCompact
    case tasksProfessionalCompact
    case logWeight
    case logWorkout
    case logFood
    case logWater
    case logSleep
    case logCustom
    case logsAll
    case journal

    var id: String { rawValue }

    func displayName(personal: String, professional: String) -> String {
        switch self {
        case .eventsTimeline:            return "Events on Timeline"
        case .eventsList:                return "Events List"
        case .tasksPersonalGrouped:      return "\(personal) Tasks (grouped)"
        case .tasksProfessionalGrouped:  return "\(professional) Tasks (grouped)"
        case .tasksPersonalCompact:      return "\(personal) Tasks (compact)"
        case .tasksProfessionalCompact:  return "\(professional) Tasks (compact)"
        case .logWeight:                 return "Weight"
        case .logWorkout:                return "Workout"
        case .logFood:                   return "Food"
        case .logWater:                  return "Water"
        case .logSleep:                  return "Sleep"
        case .logCustom:                 return "Custom Logs"
        case .logsAll:                   return "All Logs"
        case .journal:                   return "Journal"
        }
    }

    var systemImage: String {
        switch self {
        case .eventsTimeline:                                   return "clock"
        case .eventsList:                                       return "calendar"
        case .tasksPersonalGrouped, .tasksPersonalCompact:      return "person.circle"
        case .tasksProfessionalGrouped, .tasksProfessionalCompact: return "briefcase"
        case .logWeight:                                        return "scalemass"
        case .logWorkout:                                       return "figure.run"
        case .logFood:                                          return "fork.knife"
        case .logWater:                                         return "drop"
        case .logSleep:                                         return "bed.double"
        case .logCustom:                                        return "square.grid.2x2"
        case .logsAll:                                          return "chart.bar"
        case .journal:                                          return "book"
        }
    }
}

/// Carried across an in-app drag. A `nil` source means the drag began in the
/// palette; otherwise it identifies the grid cell the component was lifted from.
struct ComponentDragPayload: Codable, Transferable {
    let component: CustomComponent
    let sourcePage: Int?
    let sourceRow: Int?
    let sourceCol: Int?

    var isFromPalette: Bool {
        sourcePage == nil || sourceRow == nil || sourceCol == nil
    }

    static var transferRepresentation: some TransferRepresentation {
        // `.json` is built-in and plays nicely with CodableRepresentation without
        // any Info.plist UTI registration. The drag stays usable across iPad and
        // Mac and doesn't require declaring a custom exported type.
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Persisted configuration

/// A single saved layout the user can put together in the configurator.
/// Pure data — loading/saving happens through `CustomDayViewLibrary`.
struct CustomDayViewConfig: Codable {
    /// Legacy storage key for single-config saves (pre-library). Kept so
    /// `CustomDayViewLibrary.load()` can migrate users who had a layout from
    /// before multi-version support shipped.
    static let legacyUserDefaultsKey = "customDayViewConfig.v1"

    var pageMode: Int
    var page1: PageConfig
    var page2: PageConfig?

    struct PageConfig: Codable {
        var rows: Int
        var cols: Int
        var merges: [MergeDTO]
        var placements: [PlacementDTO]
        var groups: [GroupDTO]? = nil
    }

    struct MergeDTO: Codable {
        var topRow: Int
        var leftCol: Int
        var rowSpan: Int
        var colSpan: Int
    }

    struct PlacementDTO: Codable {
        var row: Int
        var col: Int
        var component: String
    }

    struct GroupDTO: Codable {
        var orientation: String // GroupRegion.Orientation.rawValue
        var startRow: Int
        var startCol: Int
        // Current format: explicit rectangle.
        var rowSpan: Int?
        var colSpan: Int?
        /// Legacy: length along the primary axis. Kept for back-compat with
        /// saves that predate multi-column/multi-row groups.
        var length: Int?

        /// Resolves rowSpan/colSpan, falling back to the legacy single-axis
        /// representation if the new fields are absent.
        func resolvedSpans() -> (rowSpan: Int, colSpan: Int) {
            if let r = rowSpan, let c = colSpan { return (r, c) }
            let n = length ?? 1
            switch orientation {
            case "horizontal": return (rowSpan: 1, colSpan: n)
            case "vertical":   return (rowSpan: n, colSpan: 1)
            default:           return (rowSpan: n, colSpan: 1)
            }
        }
    }

    /// A fresh blank layout used when creating a new version from scratch.
    static func blank() -> CustomDayViewConfig {
        CustomDayViewConfig(
            pageMode: 1,
            page1: PageConfig(rows: 3, cols: 3, merges: [], placements: [], groups: nil),
            page2: nil
        )
    }
}

/// A named saved layout. The `id` is stable for the lifetime of the version
/// so the library can associate edits back to the same slot.
struct NamedCustomDayViewConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var config: CustomDayViewConfig
}

/// Holds up to `maxVersions` named layouts plus the id of the one currently
/// rendered by `DayViewCustom`. Persisted as JSON in UserDefaults and iCloud
/// KVS under `userDefaultsKey`.
struct CustomDayViewLibrary: Codable {
    static let userDefaultsKey = "customDayViewLibrary.v1"
    /// Posted on the main queue when the library changes (local save or a
    /// sync from another device via iCloud KVS).
    static let didChangeNotification = Notification.Name("CustomDayViewLibraryDidChange")
    static let maxVersions = 3

    var activeId: UUID?
    var versions: [NamedCustomDayViewConfig]

    /// The currently-selected version's config, if any.
    var activeConfig: CustomDayViewConfig? {
        guard let id = activeId,
              let version = versions.first(where: { $0.id == id }) else { return nil }
        return version.config
    }

    static func empty() -> CustomDayViewLibrary {
        CustomDayViewLibrary(activeId: nil, versions: [])
    }

    /// Load the library, preferring iCloud KVS over the local cache.
    /// On first run after the multi-version update, migrates a pre-existing
    /// single-config save into a one-version library.
    static func load() -> CustomDayViewLibrary {
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = kvs.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(CustomDayViewLibrary.self, from: data) {
            return lib
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(CustomDayViewLibrary.self, from: data) {
            return lib
        }
        // Migrate legacy single-config save, preferring KVS over local.
        let legacyKey = CustomDayViewConfig.legacyUserDefaultsKey
        if let data = kvs.data(forKey: legacyKey) ?? UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(CustomDayViewConfig.self, from: data) {
            let named = NamedCustomDayViewConfig(id: UUID(), name: "My Custom View", config: legacy)
            let lib = CustomDayViewLibrary(activeId: named.id, versions: [named])
            save(lib)
            return lib
        }
        return .empty()
    }

    /// Writes to both UserDefaults (local cache) and NSUbiquitousKeyValueStore
    /// (iCloud sync). Posts `didChangeNotification` so views re-render.
    static func save(_ library: CustomDayViewLibrary) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Registers the iCloud KVS observer that mirrors remote changes to the
    /// local cache. Call once at app launch.
    @MainActor
    static func startSync() {
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        // One-time migration: if this device has a library locally but KVS is
        // empty, push it up so other devices pick it up.
        if kvs.data(forKey: userDefaultsKey) == nil,
           let localData = UserDefaults.standard.data(forKey: userDefaultsKey) {
            kvs.set(localData, forKey: userDefaultsKey)
            kvs.synchronize()
        }

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard changedKeys.isEmpty || changedKeys.contains(userDefaultsKey) else { return }

            if let data = kvs.data(forKey: userDefaultsKey) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}


/// A rectangular region of merged cells within a page's 3x3 grid.
/// `topRow`/`leftCol` identify the top-left anchor; spans describe how many
/// cells the region covers.
private struct MergedRegion: Hashable {
    let topRow: Int
    let leftCol: Int
    let rowSpan: Int
    let colSpan: Int

    func contains(row: Int, col: Int) -> Bool {
        row >= topRow && row < topRow + rowSpan &&
        col >= leftCol && col < leftCol + colSpan
    }

    var cellPositions: [(row: Int, col: Int)] {
        (topRow..<(topRow + rowSpan)).flatMap { r in
            (leftCol..<(leftCol + colSpan)).map { c in (row: r, col: c) }
        }
    }
}

/// Identifies a specific cell within a page's grid.
private struct CellPos: Hashable {
    let page: Int
    let row: Int
    let col: Int
}

/// Visible cells exposed to the grid `ForEach`. Hidden cells inside a merge
/// (non-anchor cells) are filtered out.
private struct VisibleCell: Identifiable {
    let page: Int
    let row: Int
    let col: Int
    var id: String { "\(page)_\(row)_\(col)" }
}

/// A "group" is a flex container covering a rectangle of cells. Components
/// inside a group render with minimal spacing — the orientation dictates
/// whether they pack vertically (column of components) or horizontally (row
/// of components).
struct GroupRegion: Hashable, Identifiable {
    enum Orientation: String, Codable, Hashable {
        case horizontal // row of components stacked left-to-right
        case vertical   // column of components stacked top-to-bottom
    }
    let orientation: Orientation
    let startRow: Int
    let startCol: Int
    let rowSpan: Int
    let colSpan: Int

    var id: String {
        "\(orientation.rawValue)_\(startRow)_\(startCol)_\(rowSpan)_\(colSpan)"
    }

    func contains(row: Int, col: Int) -> Bool {
        row >= startRow && row < startRow + rowSpan &&
        col >= startCol && col < startCol + colSpan
    }

    var cells: [(row: Int, col: Int)] {
        (0..<rowSpan).flatMap { dr in
            (0..<colSpan).map { dc in (row: startRow + dr, col: startCol + dc) }
        }
    }
}


/// Configuration UI for a single Custom day view layout version.
///
/// Callers present this in a sheet/cover and pass the `versionId` of the
/// `NamedCustomDayViewConfig` to edit. On Save, the configurator writes back
/// to the same slot in `CustomDayViewLibrary`, preserving the id so the
/// library's other versions and `activeId` stay intact.
struct DayViewCustomConfigurator: View {
    @Environment(\.dismiss) private var dismiss

    /// Stable id of the version this configurator edits. Passed in by the
    /// caller (Settings) so saves land in the right slot in the library.
    private let versionId: UUID

    enum PageMode: String, CaseIterable, Identifiable {
        case one = "1 page"
        case two = "2 pages"
        var id: String { rawValue }
    }

    @State private var versionName: String = ""
    @State private var pageMode: PageMode = .one
    @State private var mergesByPage: [Int: [MergedRegion]] = [1: [], 2: []]
    @State private var groupsByPage: [Int: [GroupRegion]] = [1: [], 2: []]
    @State private var selectedCells: Set<CellPos> = []
    @State private var rowsByPage: [Int: Int] = [1: 3, 2: 3]
    @State private var colsByPage: [Int: Int] = [1: 3, 2: 3]
    /// Component placed at a given anchor cell. Non-anchor cells inside a
    /// merged region aren't keys — the component fills the whole merge shape.
    @State private var placements: [CellPos: CustomComponent] = [:]
    @State private var dropError: String?
    @State private var showingResetConfirmation: Bool = false

    @ObservedObject private var appPrefs = AppPreferences.shared

    private let maxRowsOrCols = 10
    private let minRowsOrCols = 1

    init(versionId: UUID) {
        self.versionId = versionId
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    workArea
                        .frame(width: proxy.size.width * 2.0 / 3.0)

                    Divider()

                    componentPalette
                        .frame(width: proxy.size.width * 1.0 / 3.0)
                }
            }
            .navigationTitle("Customize Day View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    TextField("Version name", text: $versionName)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 260)
                        .submitLabel(.done)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }

                    Button("Save") {
                        saveConfiguration()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert(
                "Can't Place Component",
                isPresented: Binding(
                    get: { dropError != nil },
                    set: { if !$0 { dropError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { dropError = nil }
            } message: {
                Text(dropError ?? "")
            }
            .alert(
                "Start Fresh?",
                isPresented: $showingResetConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetConfiguration() }
            } message: {
                Text("This clears your current layout — grid size, merges, placed components, and dividers. You can still cancel without saving to keep the previously saved version.")
            }
            .onAppear {
                loadSavedConfiguration()
            }
        }
    }

    /// Hydrates the configurator's `@State` from the library entry matching
    /// `versionId`. Runs on `.onAppear` so reconfigure continues from where
    /// Save left off. If the id no longer exists (version was deleted in
    /// another tab before we appeared), start from a blank layout.
    private func loadSavedConfiguration() {
        let library = CustomDayViewLibrary.load()
        guard let version = library.versions.first(where: { $0.id == versionId }) else {
            versionName = "My Custom View"
            return
        }
        versionName = version.name
        let config = version.config

        pageMode = config.pageMode == 2 ? .two : .one
        rowsByPage[1] = max(minRowsOrCols, min(maxRowsOrCols, config.page1.rows))
        colsByPage[1] = max(minRowsOrCols, min(maxRowsOrCols, config.page1.cols))
        mergesByPage[1] = config.page1.merges.map {
            MergedRegion(
                topRow: $0.topRow, leftCol: $0.leftCol,
                rowSpan: $0.rowSpan, colSpan: $0.colSpan
            )
        }

        var loaded: [CellPos: CustomComponent] = [:]
        for dto in config.page1.placements {
            if let component = CustomComponent(rawValue: dto.component) {
                loaded[CellPos(page: 1, row: dto.row, col: dto.col)] = component
            }
        }

        groupsByPage[1] = (config.page1.groups ?? []).compactMap { dto in
            guard let orientation = GroupRegion.Orientation(rawValue: dto.orientation) else { return nil }
            let (rs, cs) = dto.resolvedSpans()
            return GroupRegion(
                orientation: orientation,
                startRow: dto.startRow,
                startCol: dto.startCol,
                rowSpan: rs,
                colSpan: cs
            )
        }

        if let p2 = config.page2 {
            rowsByPage[2] = max(minRowsOrCols, min(maxRowsOrCols, p2.rows))
            colsByPage[2] = max(minRowsOrCols, min(maxRowsOrCols, p2.cols))
            mergesByPage[2] = p2.merges.map {
                MergedRegion(
                    topRow: $0.topRow, leftCol: $0.leftCol,
                    rowSpan: $0.rowSpan, colSpan: $0.colSpan
                )
            }
            for dto in p2.placements {
                if let component = CustomComponent(rawValue: dto.component) {
                    loaded[CellPos(page: 2, row: dto.row, col: dto.col)] = component
                }
            }
            groupsByPage[2] = (p2.groups ?? []).compactMap { dto in
                guard let orientation = GroupRegion.Orientation(rawValue: dto.orientation) else { return nil }
                let (rs, cs) = dto.resolvedSpans()
                return GroupRegion(
                    orientation: orientation,
                    startRow: dto.startRow,
                    startCol: dto.startCol,
                    rowSpan: rs,
                    colSpan: cs
                )
            }
        } else {
            mergesByPage[2] = []
            groupsByPage[2] = []
            rowsByPage[2] = 3
            colsByPage[2] = 3
        }

        placements = loaded
        selectedCells = []
    }

    // MARK: - Work Area (left 2/3)

    private var workArea: some View {
        VStack(spacing: 0) {
            editHeader

            GeometryReader { proxy in
                pagesScroll(in: proxy.size)
            }
        }
    }

    private var editHeader: some View {
        HStack(spacing: 12) {
            Picker("Pages", selection: $pageMode) {
                ForEach(PageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .onChange(of: pageMode) { _, _ in
                if pageMode == .one {
                    selectedCells = selectedCells.filter { $0.page == 1 }
                }
            }

            Spacer()

            Button { performMerge() } label: {
                Label("Merge", systemImage: "rectangle.on.rectangle.angled")
            }
            .disabled(!canMerge)

            Button { performUnmerge() } label: {
                Label("Unmerge", systemImage: "rectangle.split.2x1")
            }
            .disabled(!canUnmerge)

            Button { performGroup() } label: {
                Label("Group", systemImage: "rectangle.stack")
            }
            .disabled(!canGroup)

            Button { performUngroup() } label: {
                Label("Ungroup", systemImage: "rectangle.stack.badge.minus")
            }
            .disabled(!canUngroup)

            if !selectedCells.isEmpty {
                Button("Clear") { selectedCells.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func pagesScroll(in containerSize: CGSize) -> some View {
        let outerPadding: CGFloat = 16
        let pageSpacing: CGFloat = 24
        let labelHeight: CGFloat = 22
        let labelSpacing: CGFloat = 6
        let stepperHeight: CGFloat = 30
        let stepperSpacing: CGFloat = 8

        let availableCardH = max(
            0,
            containerSize.height - 2 * outerPadding
                - labelHeight - labelSpacing
                - stepperHeight - stepperSpacing
        )
        let aspect = screenAspectRatio()
        var cardH = availableCardH
        var cardW = cardH * aspect

        if pageMode == .one {
            let maxW = containerSize.width - 2 * outerPadding
            if cardW > maxW {
                cardW = maxW
                cardH = cardW / aspect
            }
        }

        let cardSize = CGSize(width: cardW, height: cardH)
        let totalContentW: CGFloat = pageMode == .one
            ? cardW + 2 * outerPadding
            : cardW * 2 + pageSpacing + 2 * outerPadding

        return ScrollView(.horizontal, showsIndicators: pageMode == .two) {
            HStack(spacing: pageSpacing) {
                pageCard(index: 1, size: cardSize)
                if pageMode == .two {
                    pageCard(index: 2, size: cardSize)
                }
            }
            .padding(outerPadding)
            .frame(minWidth: max(containerSize.width, totalContentW), alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    /// Returns the current screen's aspect ratio (width / height).
    private func screenAspectRatio() -> CGFloat {
        #if os(iOS)
        let bounds = UIScreen.main.bounds
        guard bounds.height > 0 else { return 4.0 / 3.0 }
        return bounds.width / bounds.height
        #else
        return 4.0 / 3.0
        #endif
    }

    private func pageCard(index: Int, size: CGSize) -> some View {
        let navHeight = navBarPreviewHeight(cardHeight: size.height)
        let gridHeight = max(0, size.height - navHeight)

        return VStack(spacing: 6) {
            Text("Page \(index)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(height: 22)

            VStack(spacing: 0) {
                navBarPreview(cardWidth: size.width)
                    .frame(width: size.width, height: navHeight)

                pageGrid(pageIndex: index, size: CGSize(width: size.width, height: gridHeight))
                    .frame(width: size.width, height: gridHeight)
            }
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)

            gridSizeStepper(for: index)
                .frame(width: size.width)
        }
    }

    private func gridSizeStepper(for page: Int) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Rows")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    removeRow(page: page)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .disabled(rows(for: page) <= minRowsOrCols)

                Text("\(rows(for: page))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 14)

                Button {
                    addRow(page: page)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .disabled(rows(for: page) >= maxRowsOrCols)
            }

            HStack(spacing: 6) {
                Text("Cols")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    removeColumn(page: page)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .disabled(columns(for: page) <= minRowsOrCols)

                Text("\(columns(for: page))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 14)

                Button {
                    addColumn(page: page)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .disabled(columns(for: page) >= maxRowsOrCols)
            }
        }
        .frame(height: 30)
    }

    /// Approximates the live nav bar's height relative to the screen.
    private func navBarPreviewHeight(cardHeight: CGFloat) -> CGFloat {
        max(22, min(32, cardHeight * 0.06))
    }

    /// Non-interactive visual mock of the global nav bar.
    private func navBarPreview(cardWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
            Image(systemName: "chevron.left")
            Text("Day")
                .lineLimit(1)
            Image(systemName: "chevron.right")
            Spacer()
            Image(systemName: "d.circle")
            Image(systemName: "w.circle")
            Image(systemName: "m.circle")
            Image(systemName: "y.circle")
            Spacer()
            Image(systemName: "arrow.trianglehead.clockwise.icloud")
            Image(systemName: "plus")
        }
        .font(.system(size: 9, weight: .regular))
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: - Grid rendering

    private func pageGrid(pageIndex: Int, size: CGSize) -> some View {
        let columns = self.columns(for: pageIndex)
        let rows = self.rows(for: pageIndex)
        let spacing: CGFloat = 6
        let padding: CGFloat = 8
        let innerW = size.width - padding * 2
        let innerH = size.height - padding * 2
        let cellW = max(0, (innerW - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let cellH = max(0, (innerH - spacing * CGFloat(rows - 1)) / CGFloat(rows))

        return ZStack(alignment: .topLeading) {
            ForEach(visibleCells(page: pageIndex)) { cell in
                placedCellView(
                    cell: cell,
                    cellW: cellW,
                    cellH: cellH,
                    spacing: spacing,
                    padding: padding,
                    columns: columns
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func placedCellView(cell: VisibleCell, cellW: CGFloat, cellH: CGFloat, spacing: CGFloat, padding: CGFloat, columns: Int) -> some View {
        let region = mergedRegion(page: cell.page, row: cell.row, col: cell.col)
        let rowSpan = region?.rowSpan ?? 1
        let colSpan = region?.colSpan ?? 1
        let width = CGFloat(colSpan) * cellW + CGFloat(colSpan - 1) * spacing
        let height = CGFloat(rowSpan) * cellH + CGFloat(rowSpan - 1) * spacing
        let x = CGFloat(cell.col) * (cellW + spacing) + padding
        let y = CGFloat(cell.row) * (cellH + spacing) + padding
        let isMerged = region != nil
        let isSelected = isCellSelected(cell: cell, region: region)
        let anchorPos = CellPos(page: cell.page, row: cell.row, col: cell.col)
        let placed = placements[anchorPos]
        let group = groupContaining(page: cell.page, row: cell.row, col: cell.col)

        return gridCell(
            row: cell.row,
            col: cell.col,
            columns: columns,
            isSelected: isSelected,
            isMerged: isMerged,
            isGrouped: group != nil,
            component: placed
        )
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .modifier(
            CellDragModifier(
                component: placed,
                cellPage: cell.page,
                cellRow: cell.row,
                cellCol: cell.col
            )
        )
        .dropDestination(for: ComponentDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            applyDrop(payload: payload, targetPage: cell.page, targetRow: cell.row, targetCol: cell.col)
            return true
        }
        .onTapGesture {
            toggleCell(page: cell.page, row: cell.row, col: cell.col)
        }
        .contextMenu {
            if placements[CellPos(page: cell.page, row: cell.row, col: cell.col)] != nil {
                Button(role: .destructive) {
                    removePlacement(page: cell.page, row: cell.row, col: cell.col)
                } label: {
                    Label("Delete Component", systemImage: "trash")
                }
            }
        }
        // Use `.position` (not `.offset`) so each cell has its own real layout
        // frame. `.offset` only shifts visuals, leaving all siblings stacked at
        // (0,0) in the ZStack — which broke taps and drop targeting.
        .position(x: x + width / 2, y: y + height / 2)
    }

    private func gridCell(row: Int, col: Int, columns: Int, isSelected: Bool, isMerged: Bool, isGrouped: Bool, component: CustomComponent?) -> some View {
        let stroke: Color
        if isSelected {
            stroke = .accentColor
        } else if isGrouped {
            stroke = .purple
        } else {
            stroke = .secondary.opacity(0.5)
        }
        let fill: Color
        if isSelected {
            fill = Color.accentColor.opacity(0.18)
        } else if component != nil {
            fill = Color.accentColor.opacity(0.08)
        } else if isGrouped {
            fill = Color.purple.opacity(0.08)
        } else {
            fill = Color(.secondarySystemBackground)
        }
        let lineWidth: CGFloat = isSelected ? 2 : 1

        return RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, dash: (isMerged || isGrouped || component != nil) ? [] : [6]))
            .foregroundColor(stroke)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
            )
            .overlay(
                Group {
                    if let component = component {
                        VStack(spacing: 4) {
                            Image(systemName: component.systemImage)
                                .foregroundColor(.accentColor)
                            Text(component.displayName(
                                personal: appPrefs.personalAccountName,
                                professional: appPrefs.professionalAccountName
                            ))
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                        }
                    } else {
                        Text("\(row * columns + col + 1)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            )
    }

    // MARK: - Component Palette (right 1/3)

    /// All components the user can currently place, filtered to reflect their
    /// account names + enabled logs, and excluding anything already on the grid.
    private var availablePaletteComponents: [CustomComponent] {
        var items: [CustomComponent] = [
            .eventsTimeline,
            .eventsList,
            .tasksPersonalGrouped,
            .tasksProfessionalGrouped,
            .tasksPersonalCompact,
            .tasksProfessionalCompact,
        ]
        if appPrefs.showWeightLogs  { items.append(.logWeight) }
        if appPrefs.showWorkoutLogs { items.append(.logWorkout) }
        if appPrefs.showFoodLogs    { items.append(.logFood) }
        if appPrefs.showWaterLogs   { items.append(.logWater) }
        if appPrefs.showSleepLogs   { items.append(.logSleep) }
        if appPrefs.showCustomLogs  { items.append(.logCustom) }
        if appPrefs.showAnyLogs     { items.append(.logsAll) }
        items.append(.journal)

        let placed = Set(placements.values)
        return items.filter { !placed.contains($0) }
    }

    private var componentPalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Components")
                    .font(.headline)
                Text("Drag a component into the work area.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(availablePaletteComponents) { component in
                        componentCard(component: component)
                            .draggable(
                                ComponentDragPayload(
                                    component: component,
                                    sourcePage: nil,
                                    sourceRow: nil,
                                    sourceCol: nil
                                )
                            ) {
                                componentCard(component: component)
                                    .frame(width: 200)
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemBackground))
    }

    private func componentCard(component: CustomComponent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: component.systemImage)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(component.displayName(personal: appPrefs.personalAccountName,
                                       professional: appPrefs.professionalAccountName))
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }


    // MARK: - Merge / Unmerge logic

    private func merges(for page: Int) -> [MergedRegion] {
        mergesByPage[page] ?? []
    }

    private func mergedRegion(page: Int, row: Int, col: Int) -> MergedRegion? {
        merges(for: page).first { $0.contains(row: row, col: col) }
    }

    private func isCellHidden(page: Int, row: Int, col: Int) -> Bool {
        guard let r = mergedRegion(page: page, row: row, col: col) else { return false }
        return r.topRow != row || r.leftCol != col
    }

    private func visibleCells(page: Int) -> [VisibleCell] {
        let r = rows(for: page)
        let c = columns(for: page)
        var result: [VisibleCell] = []
        for row in 0..<r {
            for col in 0..<c {
                if !isCellHidden(page: page, row: row, col: col) {
                    result.append(VisibleCell(page: page, row: row, col: col))
                }
            }
        }
        return result
    }

    // MARK: - Grid size (rows/columns per page)

    private func rows(for page: Int) -> Int { rowsByPage[page] ?? 3 }
    private func columns(for page: Int) -> Int { colsByPage[page] ?? 3 }

    private func addRow(page: Int) {
        let current = rows(for: page)
        guard current < maxRowsOrCols else { return }
        rowsByPage[page] = current + 1
    }

    private func removeRow(page: Int) {
        let current = rows(for: page)
        guard current > minRowsOrCols else { return }
        let newCount = current - 1

        mergesByPage[page] = (mergesByPage[page] ?? []).compactMap { region in
            // Region fully inside the kept range: unchanged.
            if region.topRow + region.rowSpan <= newCount { return region }
            // Region fully inside the removed range: drop.
            if region.topRow >= newCount { return nil }
            // Region straddles the boundary: shrink. Drop if it collapses to 1x1.
            let newRowSpan = newCount - region.topRow
            if newRowSpan < 1 { return nil }
            if newRowSpan == 1 && region.colSpan == 1 { return nil }
            return MergedRegion(
                topRow: region.topRow,
                leftCol: region.leftCol,
                rowSpan: newRowSpan,
                colSpan: region.colSpan
            )
        }
        groupsByPage[page] = (groupsByPage[page] ?? []).compactMap { group in
            if group.startRow >= newCount { return nil }
            let newRowSpan = min(group.rowSpan, newCount - group.startRow)
            // Drop if the resulting rect no longer contains at least 2 cells.
            if newRowSpan * group.colSpan < 2 { return nil }
            return GroupRegion(
                orientation: group.orientation,
                startRow: group.startRow,
                startCol: group.startCol,
                rowSpan: newRowSpan,
                colSpan: group.colSpan
            )
        }
        selectedCells = selectedCells.filter { !($0.page == page && $0.row >= newCount) }
        rowsByPage[page] = newCount
    }

    private func addColumn(page: Int) {
        let current = columns(for: page)
        guard current < maxRowsOrCols else { return }
        colsByPage[page] = current + 1
    }

    private func removeColumn(page: Int) {
        let current = columns(for: page)
        guard current > minRowsOrCols else { return }
        let newCount = current - 1

        mergesByPage[page] = (mergesByPage[page] ?? []).compactMap { region in
            if region.leftCol + region.colSpan <= newCount { return region }
            if region.leftCol >= newCount { return nil }
            let newColSpan = newCount - region.leftCol
            if newColSpan < 1 { return nil }
            if region.rowSpan == 1 && newColSpan == 1 { return nil }
            return MergedRegion(
                topRow: region.topRow,
                leftCol: region.leftCol,
                rowSpan: region.rowSpan,
                colSpan: newColSpan
            )
        }
        groupsByPage[page] = (groupsByPage[page] ?? []).compactMap { group in
            if group.startCol >= newCount { return nil }
            let newColSpan = min(group.colSpan, newCount - group.startCol)
            if group.rowSpan * newColSpan < 2 { return nil }
            return GroupRegion(
                orientation: group.orientation,
                startRow: group.startRow,
                startCol: group.startCol,
                rowSpan: group.rowSpan,
                colSpan: newColSpan
            )
        }
        selectedCells = selectedCells.filter { !($0.page == page && $0.col >= newCount) }
        colsByPage[page] = newCount
    }

    private func isCellSelected(cell: VisibleCell, region: MergedRegion?) -> Bool {
        if let r = region {
            let regionCells = Set(r.cellPositions.map { CellPos(page: cell.page, row: $0.row, col: $0.col) })
            return regionCells.isSubset(of: selectedCells)
        }
        return selectedCells.contains(CellPos(page: cell.page, row: cell.row, col: cell.col))
    }

    private func toggleCell(page: Int, row: Int, col: Int) {
        // Keep selection contained to a single page at a time.
        if let existingPage = selectedCells.first?.page, existingPage != page {
            selectedCells.removeAll()
        }

        // If the cell is part of a merge, select/deselect the whole merge.
        if let region = mergedRegion(page: page, row: row, col: col) {
            let regionCells = Set(region.cellPositions.map { CellPos(page: page, row: $0.row, col: $0.col) })
            if regionCells.isSubset(of: selectedCells) {
                selectedCells.subtract(regionCells)
            } else {
                selectedCells.formUnion(regionCells)
            }
            return
        }

        // If the cell is part of a group, select/deselect the whole group.
        if let group = groupContaining(page: page, row: row, col: col) {
            let groupCells = Set(group.cells.map { CellPos(page: page, row: $0.row, col: $0.col) })
            if groupCells.isSubset(of: selectedCells) {
                selectedCells.subtract(groupCells)
            } else {
                selectedCells.formUnion(groupCells)
            }
            return
        }

        // Plain cell — toggle individually.
        let pos = CellPos(page: page, row: row, col: col)
        if selectedCells.contains(pos) {
            selectedCells.remove(pos)
        } else {
            selectedCells.insert(pos)
        }
    }

    private var selectionPage: Int? {
        let pages = Set(selectedCells.map { $0.page })
        return pages.count == 1 ? pages.first : nil
    }

    private var canMerge: Bool {
        guard let page = selectionPage else { return false }
        let cells = selectedCells.filter { $0.page == page }
        guard cells.count >= 2 else { return false }

        let rows = cells.map { $0.row }
        let cols = cells.map { $0.col }
        guard let minR = rows.min(), let maxR = rows.max(),
              let minC = cols.min(), let maxC = cols.max() else { return false }
        let rowSpan = maxR - minR + 1
        let colSpan = maxC - minC + 1

        // Bounding box must be fully selected (forms a solid rectangle).
        guard cells.count == rowSpan * colSpan else { return false }

        // Must not overlap any existing merged region.
        let existing = merges(for: page)
        for r in minR...maxR {
            for c in minC...maxC {
                if existing.contains(where: { $0.contains(row: r, col: c) }) {
                    return false
                }
            }
        }
        return true
    }

    private func performMerge() {
        guard canMerge, let page = selectionPage else { return }
        let cells = selectedCells.filter { $0.page == page }
        let rows = cells.map { $0.row }
        let cols = cells.map { $0.col }
        guard let minR = rows.min(), let maxR = rows.max(),
              let minC = cols.min(), let maxC = cols.max() else { return }
        let region = MergedRegion(
            topRow: minR,
            leftCol: minC,
            rowSpan: maxR - minR + 1,
            colSpan: maxC - minC + 1
        )
        mergesByPage[page, default: []].append(region)
        selectedCells.removeAll()
    }

    /// Returns the merged region whose cells exactly equal the current selection,
    /// if any. Used for the Unmerge action.
    private var mergedRegionForUnmerge: (page: Int, region: MergedRegion)? {
        guard let page = selectionPage else { return nil }
        let selectedOnPage = selectedCells.filter { $0.page == page }
        for region in merges(for: page) {
            let regionCells = Set(region.cellPositions.map { CellPos(page: page, row: $0.row, col: $0.col) })
            if regionCells == selectedOnPage {
                return (page, region)
            }
        }
        return nil
    }

    private var canUnmerge: Bool { mergedRegionForUnmerge != nil }

    private func performUnmerge() {
        guard let info = mergedRegionForUnmerge else { return }
        mergesByPage[info.page]?.removeAll { $0 == info.region }
        selectedCells.removeAll()
    }

    // MARK: - Group / Ungroup

    private func groups(for page: Int) -> [GroupRegion] {
        groupsByPage[page] ?? []
    }

    private func groupContaining(page: Int, row: Int, col: Int) -> GroupRegion? {
        groups(for: page).first { $0.contains(row: row, col: col) }
    }

    /// Footprint of a component (an unmerged placement or a merged region
    /// that carries a placement).
    private struct Footprint: Hashable {
        let rowStart: Int
        let rowEnd: Int     // inclusive
        let colStart: Int
        let colEnd: Int     // inclusive
    }

    /// Returns the per-component footprints covered by the current selection,
    /// or nil if the selection contains an empty cell or an unresolved merge.
    private func selectedFootprints(page: Int, cells: Set<CellPos>) -> [Footprint]? {
        let existingMerges = merges(for: page)
        var seenAnchors = Set<CellPos>()
        var footprints: [Footprint] = []
        for cell in cells {
            let pos = CellPos(page: page, row: cell.row, col: cell.col)
            if let merge = existingMerges.first(where: { $0.contains(row: cell.row, col: cell.col) }) {
                let anchor = CellPos(page: page, row: merge.topRow, col: merge.leftCol)
                guard placements[anchor] != nil else { return nil }
                if seenAnchors.insert(anchor).inserted {
                    footprints.append(Footprint(
                        rowStart: merge.topRow,
                        rowEnd: merge.topRow + merge.rowSpan - 1,
                        colStart: merge.leftCol,
                        colEnd: merge.leftCol + merge.colSpan - 1
                    ))
                }
            } else if placements[pos] != nil {
                if seenAnchors.insert(pos).inserted {
                    footprints.append(Footprint(
                        rowStart: cell.row,
                        rowEnd: cell.row,
                        colStart: cell.col,
                        colEnd: cell.col
                    ))
                }
            } else {
                return nil
            }
        }
        return footprints
    }

    /// Valid grouping: selection covers 2+ components that all share the same
    /// column range (→ vertical group) OR the same row range (→ horizontal
    /// group), are adjacent with no gaps along their primary axis, and their
    /// combined footprint matches the selected cells exactly.
    private var canGroup: Bool {
        _ = determinedGroupOrientation
        return determinedGroupOrientation != nil
    }

    /// Returns the orientation + bounding rect + component footprints for the
    /// current selection if it's groupable. Nil otherwise.
    private var determinedGroupOrientation: (orientation: GroupRegion.Orientation, startRow: Int, startCol: Int, rowSpan: Int, colSpan: Int)? {
        guard let page = selectionPage else { return nil }
        let cells = selectedCells.filter { $0.page == page }
        guard cells.count >= 2 else { return nil }

        guard let footprints = selectedFootprints(page: page, cells: cells) else { return nil }
        guard footprints.count >= 2 else { return nil }

        // Selection must equal the union of all component footprints (user
        // selected full components — not partial merges).
        var expected = Set<CellPos>()
        for fp in footprints {
            for r in fp.rowStart...fp.rowEnd {
                for c in fp.colStart...fp.colEnd {
                    expected.insert(CellPos(page: page, row: r, col: c))
                }
            }
        }
        guard cells == expected else { return nil }

        // Vertical group: all components share the same (colStart, colEnd)
        // and are stacked consecutively by row.
        let firstColRange = (footprints[0].colStart, footprints[0].colEnd)
        let firstRowRange = (footprints[0].rowStart, footprints[0].rowEnd)
        let allSameCols = footprints.allSatisfy { ($0.colStart, $0.colEnd) == firstColRange }
        let allSameRows = footprints.allSatisfy { ($0.rowStart, $0.rowEnd) == firstRowRange }

        let orientation: GroupRegion.Orientation
        if allSameCols {
            let sorted = footprints.sorted { $0.rowStart < $1.rowStart }
            for i in 1..<sorted.count {
                if sorted[i].rowStart != sorted[i - 1].rowEnd + 1 { return nil }
            }
            orientation = .vertical
        } else if allSameRows {
            let sorted = footprints.sorted { $0.colStart < $1.colStart }
            for i in 1..<sorted.count {
                if sorted[i].colStart != sorted[i - 1].colEnd + 1 { return nil }
            }
            orientation = .horizontal
        } else {
            return nil
        }

        // No overlap with existing groups.
        let existingGroups = groups(for: page)
        for cell in cells {
            if existingGroups.contains(where: { $0.contains(row: cell.row, col: cell.col) }) {
                return nil
            }
        }

        let minR = footprints.map { $0.rowStart }.min() ?? 0
        let maxR = footprints.map { $0.rowEnd   }.max() ?? 0
        let minC = footprints.map { $0.colStart }.min() ?? 0
        let maxC = footprints.map { $0.colEnd   }.max() ?? 0
        return (orientation, minR, minC, maxR - minR + 1, maxC - minC + 1)
    }

    private func performGroup() {
        guard let info = determinedGroupOrientation,
              let page = selectionPage else { return }
        let region = GroupRegion(
            orientation: info.orientation,
            startRow: info.startRow,
            startCol: info.startCol,
            rowSpan: info.rowSpan,
            colSpan: info.colSpan
        )
        groupsByPage[page, default: []].append(region)
        selectedCells.removeAll()
    }

    /// Selection must exactly match one group's cells.
    private var groupForUngroup: (page: Int, region: GroupRegion)? {
        guard let page = selectionPage else { return nil }
        let cellsOnPage = selectedCells.filter { $0.page == page }
        for region in groups(for: page) {
            let regionCells = Set(region.cells.map { CellPos(page: page, row: $0.row, col: $0.col) })
            if regionCells == cellsOnPage { return (page, region) }
        }
        return nil
    }

    private var canUngroup: Bool { groupForUngroup != nil }

    private func performUngroup() {
        guard let info = groupForUngroup else { return }
        groupsByPage[info.page]?.removeAll { $0 == info.region }
        selectedCells.removeAll()
    }

    /// Removes the placement at the given anchor cell so the component
    /// reappears in the palette. Leaves any merged region intact so the user
    /// can place a different component into the same layout slot.
    private func removePlacement(page: Int, row: Int, col: Int) {
        placements.removeValue(forKey: CellPos(page: page, row: row, col: col))
    }

    /// Clears every in-memory editing state so the configurator is back to a
    /// clean slate. Does not touch UserDefaults — the user still has to press
    /// Save to persist (or Cancel to abandon the reset).
    private func resetConfiguration() {
        pageMode = .one
        rowsByPage = [1: 3, 2: 3]
        colsByPage = [1: 3, 2: 3]
        mergesByPage = [1: [], 2: []]
        groupsByPage = [1: [], 2: []]
        placements = [:]
        selectedCells = []
    }

    // MARK: - Persistence

    /// Serializes the current configuration into the library entry matching
    /// `versionId`, then saves the whole library (UserDefaults + iCloud KVS).
    /// Creates the slot if it doesn't exist yet (first-save of a new version).
    private func saveConfiguration() {
        let config = CustomDayViewConfig(
            pageMode: pageMode == .one ? 1 : 2,
            page1: pageConfig(for: 1),
            page2: pageMode == .two ? pageConfig(for: 2) : nil
        )
        let trimmedName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "My Custom View" : trimmedName

        var library = CustomDayViewLibrary.load()
        if let idx = library.versions.firstIndex(where: { $0.id == versionId }) {
            library.versions[idx].name = finalName
            library.versions[idx].config = config
        } else {
            // Slot was deleted elsewhere; add it back (up to the version cap).
            guard library.versions.count < CustomDayViewLibrary.maxVersions else { return }
            library.versions.append(
                NamedCustomDayViewConfig(id: versionId, name: finalName, config: config)
            )
        }
        // If nothing was active before, make this version active so the user
        // sees it immediately without an extra tap.
        if library.activeId == nil {
            library.activeId = versionId
        }
        CustomDayViewLibrary.save(library)
    }

    private func pageConfig(for page: Int) -> CustomDayViewConfig.PageConfig {
        let merges = mergesByPage[page]?.map {
            CustomDayViewConfig.MergeDTO(
                topRow: $0.topRow,
                leftCol: $0.leftCol,
                rowSpan: $0.rowSpan,
                colSpan: $0.colSpan
            )
        } ?? []
        let placementsList = placements
            .compactMap { (pos, component) -> CustomDayViewConfig.PlacementDTO? in
                guard pos.page == page else { return nil }
                return CustomDayViewConfig.PlacementDTO(
                    row: pos.row,
                    col: pos.col,
                    component: component.rawValue
                )
            }
        let groupsList = groupsByPage[page]?.map {
            CustomDayViewConfig.GroupDTO(
                orientation: $0.orientation.rawValue,
                startRow: $0.startRow,
                startCol: $0.startCol,
                rowSpan: $0.rowSpan,
                colSpan: $0.colSpan,
                length: nil
            )
        } ?? []
        return CustomDayViewConfig.PageConfig(
            rows: rows(for: page),
            cols: columns(for: page),
            merges: merges,
            placements: placementsList,
            groups: groupsList.isEmpty ? nil : groupsList
        )
    }

    // MARK: - Drag-and-drop placement

    private func applyDrop(payload: ComponentDragPayload, targetPage: Int, targetRow: Int, targetCol: Int) {
        let (sourceRowSpan, sourceColSpan) = sourceSpan(payload: payload)

        // Anchor the drop at the target cell's merge anchor (if any).
        let (anchorRow, anchorCol, targetRowSpan, targetColSpan) = targetAnchor(
            page: targetPage, row: targetRow, col: targetCol
        )

        // Decide the final shape:
        //   - Dropping into an existing merge → adopt that merge's shape
        //     (provided source is 1x1 or matches the merge exactly).
        //   - Dropping onto a plain cell → keep the source's shape.
        let finalRowSpan: Int
        let finalColSpan: Int
        if targetRowSpan > 1 || targetColSpan > 1 {
            if sourceRowSpan == 1 && sourceColSpan == 1 {
                finalRowSpan = targetRowSpan
                finalColSpan = targetColSpan
            } else if sourceRowSpan == targetRowSpan && sourceColSpan == targetColSpan {
                finalRowSpan = targetRowSpan
                finalColSpan = targetColSpan
            } else {
                dropError = "The target cell's merged shape doesn't match the component's shape."
                return
            }
        } else {
            finalRowSpan = sourceRowSpan
            finalColSpan = sourceColSpan
        }

        // Bounds check.
        let rowsT = rows(for: targetPage)
        let colsT = columns(for: targetPage)
        if anchorRow + finalRowSpan > rowsT || anchorCol + finalColSpan > colsT {
            dropError = "The component doesn't fit within the target page's grid. Free up more cells or resize the grid."
            return
        }

        // Cells currently occupied by the source (ignored in the occupancy check
        // because they'll be freed up by the move).
        let sourceCells: Set<CellPos> = {
            guard !payload.isFromPalette,
                  let sPage = payload.sourcePage,
                  let sRow = payload.sourceRow,
                  let sCol = payload.sourceCol else { return [] }
            let region = mergedRegion(page: sPage, row: sRow, col: sCol)
            if let r = region {
                return Set(r.cellPositions.map { CellPos(page: sPage, row: $0.row, col: $0.col) })
            }
            return [CellPos(page: sPage, row: sRow, col: sCol)]
        }()

        // Check every cell in the target region is free.
        for r in anchorRow..<(anchorRow + finalRowSpan) {
            for c in anchorCol..<(anchorCol + finalColSpan) {
                let pos = CellPos(page: targetPage, row: r, col: c)
                if sourceCells.contains(pos) { continue }

                // Conflict with another merge (other than the one we're landing in).
                if let m = mergedRegion(page: targetPage, row: r, col: c),
                   !(m.topRow == anchorRow && m.leftCol == anchorCol
                     && m.rowSpan == finalRowSpan && m.colSpan == finalColSpan) {
                    dropError = "Target cells overlap another merged region."
                    return
                }

                // Conflict with an existing placement.
                if let existingAnchor = placementAnchor(page: targetPage, row: r, col: c) {
                    if existingAnchor.page != payload.sourcePage
                        || existingAnchor.row != payload.sourceRow
                        || existingAnchor.col != payload.sourceCol {
                        dropError = "Target cells are already occupied by another component."
                        return
                    }
                }
            }
        }

        // Commit: remove source, then place at target.
        if !payload.isFromPalette,
           let sPage = payload.sourcePage,
           let sRow = payload.sourceRow,
           let sCol = payload.sourceCol {
            placements.removeValue(forKey: CellPos(page: sPage, row: sRow, col: sCol))
            mergesByPage[sPage]?.removeAll {
                $0.topRow == sRow && $0.leftCol == sCol
            }
        }

        // Add a merge at the target if the final shape is > 1x1 and no matching merge exists.
        if finalRowSpan > 1 || finalColSpan > 1 {
            let existing = mergedRegion(page: targetPage, row: anchorRow, col: anchorCol)
            if existing == nil {
                mergesByPage[targetPage, default: []].append(
                    MergedRegion(
                        topRow: anchorRow,
                        leftCol: anchorCol,
                        rowSpan: finalRowSpan,
                        colSpan: finalColSpan
                    )
                )
            }
        }

        placements[CellPos(page: targetPage, row: anchorRow, col: anchorCol)] = payload.component
    }

    private func sourceSpan(payload: ComponentDragPayload) -> (Int, Int) {
        guard !payload.isFromPalette,
              let sPage = payload.sourcePage,
              let sRow = payload.sourceRow,
              let sCol = payload.sourceCol else { return (1, 1) }
        if let region = mergedRegion(page: sPage, row: sRow, col: sCol) {
            return (region.rowSpan, region.colSpan)
        }
        return (1, 1)
    }

    /// Returns the anchor position of the cell at (page, row, col) along with
    /// the effective span of whatever region contains it.
    private func targetAnchor(page: Int, row: Int, col: Int) -> (row: Int, col: Int, rowSpan: Int, colSpan: Int) {
        if let region = mergedRegion(page: page, row: row, col: col) {
            return (region.topRow, region.leftCol, region.rowSpan, region.colSpan)
        }
        return (row, col, 1, 1)
    }

    /// If the given cell is occupied (directly or as part of a merged region
    /// that has a placement), returns the anchor cell of that placement.
    private func placementAnchor(page: Int, row: Int, col: Int) -> CellPos? {
        if let region = mergedRegion(page: page, row: row, col: col) {
            let anchor = CellPos(page: page, row: region.topRow, col: region.leftCol)
            return placements[anchor] != nil ? anchor : nil
        }
        let pos = CellPos(page: page, row: row, col: col)
        return placements[pos] != nil ? pos : nil
    }
}

/// Attaches `.draggable` to cells that hold a component so the user can move
/// them to a different grid cell. Empty cells aren't draggable.
private struct CellDragModifier: ViewModifier {
    let component: CustomComponent?
    let cellPage: Int
    let cellRow: Int
    let cellCol: Int

    func body(content: Content) -> some View {
        if let component = component {
            content.draggable(
                ComponentDragPayload(
                    component: component,
                    sourcePage: cellPage,
                    sourceRow: cellRow,
                    sourceCol: cellCol
                )
            ) {
                VStack(spacing: 4) {
                    Image(systemName: component.systemImage)
                        .foregroundColor(.accentColor)
                    Text(component.rawValue)
                        .font(.caption)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.15))
                )
            }
        } else {
            content
        }
    }
}

#Preview {
    DayViewCustomConfigurator(versionId: UUID())
}
