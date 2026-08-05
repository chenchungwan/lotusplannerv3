import SwiftUI
import UniformTypeIdentifiers

enum WeeklyCustomComponent: String, Codable, Identifiable, Hashable, CaseIterable {
    case verticalWeek
    case horizontalWeek
    case weeklyGoalsBar
    case pastWeekSummary
    case eventsWeek
    case eventsWeeklyList
    case personalTasksWeek
    case personalTasksWeeklyList
    case professionalTasksWeek
    case professionalTasksWeeklyList
    case weightLogWeek
    case workoutLogWeek
    case foodLogWeek
    case waterLogWeek
    case sleepLogWeek
    case customLogDailyWeek
    case customLogDailyWeek2
    case customLogWeek
    case customLogWeek2
    case weeklyGoals
    case monthlyGoals
    case yearlyGoals
    case goalsPicker
    case weightGraph
    case weightGraphWeek
    case weightGraphMonth
    case weightGraphYear
    case workoutStreakGraph
    case workoutStreakGraphWeek
    case workoutStreakGraphMonth
    case workoutStreakGraphYear

    var id: String { rawValue }

    func displayName(personal: String, professional: String) -> String {
        switch self {
        case .verticalWeek: return "Vertical Week Layout"
        case .horizontalWeek: return "Horizontal Week Layout"
        case .weeklyGoalsBar: return "Weekly Goals Bar"
        case .pastWeekSummary: return "Past Week Summary"
        case .eventsWeek: return "Events Week"
        case .eventsWeeklyList: return "Events Weekly List"
        case .personalTasksWeek: return "\(personal) Tasks Week"
        case .personalTasksWeeklyList: return "\(personal) Tasks Weekly List"
        case .professionalTasksWeek: return "\(professional) Tasks Week"
        case .professionalTasksWeeklyList: return "\(professional) Tasks Weekly List"
        case .weightLogWeek: return "Weight Logs Week"
        case .workoutLogWeek: return "Workout Logs Week"
        case .foodLogWeek: return "Food Logs Week"
        case .waterLogWeek: return "Water Logs Week"
        case .sleepLogWeek: return "Sleep Logs Week"
        case .customLogDailyWeek: return "\(AppPreferences.shared.customLogSectionName(for: 0)) Each Day"
        case .customLogDailyWeek2: return "\(AppPreferences.shared.customLogSectionName(for: 1)) Each Day"
        case .customLogWeek: return "\(AppPreferences.shared.customLogSectionName(for: 0)) Week Grid"
        case .customLogWeek2: return "\(AppPreferences.shared.customLogSectionName(for: 1)) Week Grid"
        case .weeklyGoals: return "Weekly Goals"
        case .monthlyGoals: return "Monthly Goals"
        case .yearlyGoals: return "Yearly Goals"
        case .goalsPicker: return "Goals (W/M/Y)"
        case .weightGraph: return "Weight Graph (W/M/Y)"
        case .weightGraphWeek: return "Weekly Weight Graph"
        case .weightGraphMonth: return "Monthly Weight Graph"
        case .weightGraphYear: return "Yearly Weight Graph"
        case .workoutStreakGraph: return "Workout Streak Graph (W/M/Y)"
        case .workoutStreakGraphWeek: return "Weekly Workout Streak"
        case .workoutStreakGraphMonth: return "Monthly Workout Streak"
        case .workoutStreakGraphYear: return "Yearly Workout Streak"
        }
    }

    var systemImage: String {
        switch self {
        case .verticalWeek: return "rectangle.split.3x1"
        case .horizontalWeek: return "rectangle.split.1x2"
        case .weeklyGoalsBar, .weeklyGoals, .monthlyGoals, .yearlyGoals, .goalsPicker: return "target"
        case .pastWeekSummary: return "chart.bar"
        case .eventsWeek, .eventsWeeklyList: return "calendar"
        case .personalTasksWeek, .personalTasksWeeklyList: return "person.circle"
        case .professionalTasksWeek, .professionalTasksWeeklyList: return "briefcase"
        case .weightLogWeek: return "scalemass"
        case .workoutLogWeek: return "figure.run"
        case .foodLogWeek: return "fork.knife"
        case .waterLogWeek: return "drop"
        case .sleepLogWeek: return "bed.double"
        case .customLogDailyWeek, .customLogDailyWeek2, .customLogWeek, .customLogWeek2: return "calendar.badge.checkmark"
        case .weightGraph, .weightGraphWeek, .weightGraphMonth, .weightGraphYear: return "chart.xyaxis.line"
        case .workoutStreakGraph, .workoutStreakGraphWeek, .workoutStreakGraphMonth, .workoutStreakGraphYear: return "chart.line.uptrend.xyaxis"
        }
    }

    var isDayByDay: Bool {
        switch self {
        case .eventsWeek,
             .personalTasksWeek,
             .professionalTasksWeek,
             .weightLogWeek,
             .workoutLogWeek,
             .foodLogWeek,
             .waterLogWeek,
             .sleepLogWeek,
             .customLogDailyWeek,
             .customLogDailyWeek2:
            return true
        case .verticalWeek,
             .horizontalWeek,
             .weeklyGoalsBar,
             .pastWeekSummary,
             .eventsWeeklyList,
             .personalTasksWeeklyList,
             .professionalTasksWeeklyList,
             .weeklyGoals,
             .customLogWeek,
             .customLogWeek2,
             .monthlyGoals,
             .yearlyGoals,
             .goalsPicker,
             .weightGraph,
             .weightGraphWeek,
             .weightGraphMonth,
             .weightGraphYear,
             .workoutStreakGraph,
             .workoutStreakGraphWeek,
             .workoutStreakGraphMonth,
             .workoutStreakGraphYear:
            return false
        }
    }
}

struct WeeklyComponentDragPayload: Codable, Transferable {
    let component: WeeklyCustomComponent
    let sourceRow: Int?
    let sourceCol: Int?

    var isFromPalette: Bool {
        sourceRow == nil || sourceCol == nil
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct CustomWeeklyViewConfig: Codable {
    static let legacyUserDefaultsKey = "customWeeklyViewConfig.v1"

    var orientation: CustomWeeklyLayoutOrientation
    var rows: Int
    var cols: Int
    var placements: [PlacementDTO]

    struct PlacementDTO: Codable {
        var row: Int
        var col: Int
        var rowSpan: Int
        var colSpan: Int
        var component: String

        init(row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1, component: String) {
            self.row = row
            self.col = col
            self.rowSpan = rowSpan
            self.colSpan = colSpan
            self.component = component
        }

        enum CodingKeys: String, CodingKey {
            case row
            case col
            case rowSpan
            case colSpan
            case component
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            row = try container.decode(Int.self, forKey: .row)
            col = try container.decode(Int.self, forKey: .col)
            rowSpan = try container.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1
            colSpan = try container.decodeIfPresent(Int.self, forKey: .colSpan) ?? 1
            component = try container.decode(String.self, forKey: .component)
        }
    }

    static func blank() -> CustomWeeklyViewConfig {
        CustomWeeklyViewConfig(orientation: .daysInColumns, rows: 3, cols: 7, placements: [])
    }

    enum CodingKeys: String, CodingKey {
        case orientation
        case rows
        case cols
        case placements
    }

    init(
        orientation: CustomWeeklyLayoutOrientation = .daysInColumns,
        rows: Int,
        cols: Int,
        placements: [PlacementDTO]
    ) {
        self.orientation = orientation
        self.rows = rows
        self.cols = cols
        self.placements = placements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try container.decodeIfPresent(CustomWeeklyLayoutOrientation.self, forKey: .orientation) ?? .daysInColumns
        rows = try container.decode(Int.self, forKey: .rows)
        cols = try container.decode(Int.self, forKey: .cols)
        placements = try container.decode([PlacementDTO].self, forKey: .placements)
    }
}

enum CustomWeeklyLayoutOrientation: String, Codable, CaseIterable, Identifiable {
    case daysInColumns
    case daysInRows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daysInColumns: return "Days in Columns"
        case .daysInRows: return "Days in Rows"
        }
    }

    var systemImage: String {
        switch self {
        case .daysInColumns: return "rectangle.split.3x1"
        case .daysInRows: return "rectangle.split.1x2"
        }
    }

    var fixedRows: Int? {
        switch self {
        case .daysInColumns: return nil
        case .daysInRows: return 7
        }
    }

    var fixedCols: Int? {
        switch self {
        case .daysInColumns: return 7
        case .daysInRows: return nil
        }
    }
}

struct NamedCustomWeeklyViewConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var config: CustomWeeklyViewConfig
}

struct CustomWeeklyViewLibrary: Codable {
    static let userDefaultsKey = "customWeeklyViewLibrary.v1"
    static let localActiveIdKey = "customWeeklyViewLibrary.localActiveId.v1"
    static let didChangeNotification = Notification.Name("CustomWeeklyViewLibraryDidChange")
    static let maxVersions = 10

    var activeId: UUID?
    var versions: [NamedCustomWeeklyViewConfig]

    static var localActiveId: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: localActiveIdKey),
                  let uuid = UUID(uuidString: raw) else { return nil }
            return uuid
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: localActiveIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: localActiveIdKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    var resolvedActiveId: UUID? {
        if let local = Self.localActiveId,
           versions.contains(where: { $0.id == local }) {
            return local
        }
        if let synced = activeId,
           versions.contains(where: { $0.id == synced }) {
            return synced
        }
        return versions.first?.id
    }

    var activeConfig: CustomWeeklyViewConfig? {
        guard let id = resolvedActiveId,
              let version = versions.first(where: { $0.id == id }) else { return nil }
        return version.config
    }

    static func empty() -> CustomWeeklyViewLibrary {
        CustomWeeklyViewLibrary(activeId: nil, versions: [])
    }

    static func load() -> CustomWeeklyViewLibrary {
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = kvs.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(CustomWeeklyViewLibrary.self, from: data) {
            return lib
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(CustomWeeklyViewLibrary.self, from: data) {
            return lib
        }
        if let data = kvs.data(forKey: CustomWeeklyViewConfig.legacyUserDefaultsKey) ?? UserDefaults.standard.data(forKey: CustomWeeklyViewConfig.legacyUserDefaultsKey),
           let legacy = try? JSONDecoder().decode(CustomWeeklyViewConfig.self, from: data) {
            let named = NamedCustomWeeklyViewConfig(id: UUID(), name: "My Custom Week", config: legacy)
            let lib = CustomWeeklyViewLibrary(activeId: named.id, versions: [named])
            save(lib)
            return lib
        }
        return .empty()
    }

    static func save(_ library: CustomWeeklyViewLibrary) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    @MainActor
    static func startSync() {
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

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

            let store = NSUbiquitousKeyValueStore.default
            if let data = store.data(forKey: userDefaultsKey) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
