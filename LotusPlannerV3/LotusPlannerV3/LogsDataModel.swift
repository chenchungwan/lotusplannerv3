import Foundation
import FirebaseFirestore

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
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
              let weight = data["weight"] as? Double,
              let unitString = data["unit"] as? String,
              let unit = WeightUnit(rawValue: unitString),
              let userId = data["userId"] as? String else {
            return nil
        }
        
        self.id = document.documentID
        self.timestamp = timestamp
        self.weight = weight
        self.unit = unit
        self.userId = userId
    }
    
    var firestoreData: [String: Any] {
        return [
            "timestamp": Timestamp(date: timestamp),
            "weight": weight,
            "unit": unit.rawValue,
            "userId": userId
        ]
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
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let date = (data["date"] as? Timestamp)?.dateValue(),
              let name = data["name"] as? String,
              let userId = data["userId"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = document.documentID
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = createdAt
    }
    
    var firestoreData: [String: Any] {
        return [
            "date": Timestamp(date: date),
            "name": name,
            "userId": userId,
            "createdAt": Timestamp(date: createdAt)
        ]
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
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let date = (data["date"] as? Timestamp)?.dateValue(),
              let name = data["name"] as? String,
              let userId = data["userId"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = document.documentID
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = createdAt
    }
    
    var firestoreData: [String: Any] {
        return [
            "date": Timestamp(date: date),
            "name": name,
            "userId": userId,
            "createdAt": Timestamp(date: createdAt)
        ]
    }
}

// MARK: - Scrapbook Entry
struct ScrapbookEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let pdfURL: String // Firestore Storage URL
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
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let date = (data["date"] as? Timestamp)?.dateValue(),
              let pdfURL = data["pdfURL"] as? String,
              let userId = data["userId"] as? String,
              let accountKind = data["accountKind"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = document.documentID
        self.date = date
        self.pdfURL = pdfURL
        self.userId = userId
        self.accountKind = accountKind
        self.createdAt = createdAt
        self.title = data["title"] as? String
    }
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "date": Timestamp(date: date),
            "pdfURL": pdfURL,
            "userId": userId,
            "accountKind": accountKind,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let title = title {
            data["title"] = title
        }
        
        return data
    }
}

// MARK: - Log Entry Protocol
protocol LogEntry {
    var id: String { get }
    var date: Date { get }
    var userId: String { get }
    var firestoreData: [String: Any] { get }
}

extension WeightLogEntry: LogEntry {
    var date: Date { timestamp }
}

extension WorkoutLogEntry: LogEntry {}
extension FoodLogEntry: LogEntry {}
extension ScrapbookEntry: LogEntry {} 