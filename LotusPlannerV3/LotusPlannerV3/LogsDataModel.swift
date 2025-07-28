import Foundation

// MARK: - Log Entry Types
enum LogType: String, CaseIterable, Codable {
    case weight = "weight"
    case workout = "workout"
    case food = "food"
    
    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .workout: return "Workout"
        case .food: return "Food"
        }
    }
    
    var icon: String {
        switch self {
        case .weight: return "scalemass"
        case .workout: return "figure.run"
        case .food: return "fork.knife"
        }
    }
}

// MARK: - Weight Log Entry
struct WeightLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let weight: Double
    let unit: WeightUnit
    let userId: String
    
    init(weight: Double, unit: WeightUnit, userId: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.weight = weight
        self.unit = unit
        self.userId = userId
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
    var date: Date { timestamp }
}

extension WorkoutLogEntry: LogEntry {}
extension FoodLogEntry: LogEntry {}
extension ScrapbookEntry: LogEntry {} 