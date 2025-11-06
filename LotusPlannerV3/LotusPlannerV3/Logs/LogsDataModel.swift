import Foundation

// MARK: - Log Entry Types
enum LogType: String, CaseIterable, Codable {
    case weight = "weight"
    case workout = "workout"
    case food = "food"
    case water = "water"
    
    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .workout: return "Workout"
        case .food: return "Food"
        case .water: return "Water"
        }
    }
    
    var icon: String {
        switch self {
        case .weight: return "scalemass"
        case .workout: return "figure.run"
        case .food: return "fork.knife"
        case .water: return "drop.fill"
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

// MARK: - Water Log Entry
struct WaterLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    var cupsFilled: [Bool] // Array of bools indicating which cups are filled
    let userId: String
    let createdAt: Date
    
    init(date: Date, cupsFilled: [Bool] = Array(repeating: false, count: 4), userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.cupsFilled = cupsFilled
        self.userId = userId
        self.createdAt = Date()
    }
    
    init(id: String, date: Date, cupsFilled: [Bool], userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.cupsFilled = cupsFilled
        self.userId = userId
        self.createdAt = createdAt
    }
    
    var filledCount: Int {
        cupsFilled.filter { $0 }.count
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
extension WaterLogEntry: LogEntry {}
extension ScrapbookEntry: LogEntry {} 