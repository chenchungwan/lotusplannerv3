import Foundation

// MARK: - Log Entry Types
enum LogType: String, CaseIterable, Codable {
    case weight = "weight"
    case workout = "workout"
    case food = "food"
    case sleep = "sleep"

    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .workout: return "Workout"
        case .food: return "Food"
        case .sleep: return "Sleep"
        }
    }

    var icon: String {
        switch self {
        case .weight: return "scalemass"
        case .workout: return "figure.run"
        case .food: return "fork.knife"
        case .sleep: return "bed.double.fill"
        }
    }
}

// MARK: - Weight Log Entry
struct WeightLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let time: Date
    let weight: Double
    let unit: WeightUnit
    let userId: String
    
    init(weight: Double, unit: WeightUnit, userId: String, date: Date = Date(), time: Date = Date()) {
        self.id = UUID().uuidString
        self.date = date
        self.time = time
        self.weight = weight
        self.unit = unit
        self.userId = userId
    }
    
    // Computed property for backward compatibility
    var timestamp: Date {
        Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: time),
                            minute: Calendar.current.component(.minute, from: time),
                            second: 0,
                            of: date) ?? date
    }
}

enum WeightUnit: String, CaseIterable, Codable {
    case pounds = "lbs"
    case kilograms = "kg"
    
    var displayName: String {
        switch self {
        case .pounds: return "lbs"
        case .kilograms: return "kg"
        }
    }
}

// MARK: - Workout Log Entry
struct WorkoutLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let name: String
    let userId: String
    let createdAt: Date
    
    init(date: Date, name: String, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = Date()
    }
}

// MARK: - Food Log Entry
struct FoodLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let name: String
    let userId: String
    let createdAt: Date

    init(date: Date, name: String, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = Date()
    }
}

// MARK: - Sleep Log Entry
struct SleepLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let wakeUpTime: Date?
    let bedTime: Date?
    let userId: String
    let createdAt: Date
    let updatedAt: Date

    init(date: Date, wakeUpTime: Date?, bedTime: Date?, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.wakeUpTime = wakeUpTime
        self.bedTime = bedTime
        self.userId = userId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, date: Date, wakeUpTime: Date?, bedTime: Date?, userId: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.date = date
        self.wakeUpTime = wakeUpTime
        self.bedTime = bedTime
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sleepDuration: TimeInterval? {
        guard let wake = wakeUpTime, let bed = bedTime else { return nil }
        // Calculate duration considering bed time might be on previous day
        if wake > bed {
            // Normal case: went to bed on previous day, woke up on current day
            return wake.timeIntervalSince(bed)
        } else {
            // Edge case: both times on same day (shouldn't normally happen)
            return bed.timeIntervalSince(wake) + 86400 // Add 24 hours
        }
    }

    var sleepDurationFormatted: String? {
        guard let duration = sleepDuration else { return nil }
        let decimalHours = duration / 3600
        return String(format: "%.1f h", decimalHours)
    }
}

// MARK: - Scrapbook Entry
struct ScrapbookEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let pdfURL: String // Local file URL or external URL
    let userId: String
    let accountKind: String
    let createdAt: Date
    let title: String?
    
    init(date: Date, pdfURL: String, userId: String, accountKind: GoogleAuthManager.AccountKind, title: String? = nil) {
        self.id = UUID().uuidString
        self.date = date
        self.pdfURL = pdfURL
        self.userId = userId
        self.accountKind = accountKind.rawValue
        self.createdAt = Date()
        self.title = title
    }
}

// MARK: - Log Entry Protocol
protocol LogEntry {
    var id: String { get }
    var date: Date { get }
    var userId: String { get }
}

extension WeightLogEntry: LogEntry {
    // date property is already defined in the struct
}

extension WorkoutLogEntry: LogEntry {}
extension FoodLogEntry: LogEntry {}
extension SleepLogEntry: LogEntry {}
extension ScrapbookEntry: LogEntry {} 