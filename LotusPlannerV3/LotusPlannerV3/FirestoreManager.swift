import Foundation
import FirebaseFirestore
import FirebaseStorage
import PencilKit

@MainActor
class FirestoreManager: ObservableObject {
    static let shared = FirestoreManager()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let authManager = GoogleAuthManager.shared
    
    // Published properties for real-time updates
    @Published var weightEntries: [WeightLogEntry] = []
    @Published var workoutEntries: [WorkoutLogEntry] = []
    @Published var foodEntries: [FoodLogEntry] = []
    @Published var scrapbookEntries: [ScrapbookEntry] = []
    @Published var goals: [Goal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    deinit {
        Task { @MainActor in
            removeAllListeners()
        }
    }
    
    // MARK: - Collection References
    private func getCollectionRef(for type: LogType) -> CollectionReference {
        let userId = getUserId()
        return db.collection("users")
            .document(userId)
            .collection("personal")
            .document("logs")
            .collection(type.rawValue)
    }
    
    private func getScrapbookCollectionRef() -> CollectionReference {
        let userId = getUserId()
        return db.collection("users")
            .document(userId)
            .collection("personal")
            .document("scrapbook")
            .collection("entries")
    }
    
    private func getGoalsCollectionRef() -> CollectionReference {
        let userId = getUserId()
        return db.collection("users")
            .document(userId)
            .collection("personal")
            .document("goals")
            .collection("items")
    }
    
    private func getUserId() -> String {
        let email = authManager.getEmail(for: .personal)
        let userId = email.isEmpty ? "anonymous" : email
        print("🔍 FirestoreManager getUserId: \(userId)")
        return userId
    }
    
    // MARK: - Weight Logs
    func addWeightEntry(_ entry: WeightLogEntry) async throws {
        let collection = getCollectionRef(for: .weight)
        print("💾 Saving weight entry to path: \(collection.path)/\(entry.id)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Weight entry saved successfully to Firestore")
    }
    
    func updateWeightEntry(_ entry: WeightLogEntry) async throws {
        let collection = getCollectionRef(for: .weight)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteWeightEntry(_ entryId: String) async throws {
        let collection = getCollectionRef(for: .weight)
        try await collection.document(entryId).delete()
    }
    
    func getWeightEntries(for date: Date) async throws -> [WeightLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId()
        
        let collection = getCollectionRef(for: .weight)
        print("🔍 Loading weight entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        let snapshot = try await collection
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("timestamp", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        let entries = snapshot.documents.compactMap { WeightLogEntry(document: $0) }
            .sorted { $0.timestamp < $1.timestamp }
        
        print("📊 Found \(entries.count) weight entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Workout Logs
    func addWorkoutEntry(_ entry: WorkoutLogEntry) async throws {
        let collection = getCollectionRef(for: .workout)
        print("💾 Saving workout entry to path: \(collection.path)/\(entry.id) for user: \(entry.userId)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Workout entry saved successfully to Firestore")
    }
    
    func updateWorkoutEntry(_ entry: WorkoutLogEntry) async throws {
        let collection = getCollectionRef(for: .workout)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteWorkoutEntry(_ entryId: String) async throws {
        let collection = getCollectionRef(for: .workout)
        try await collection.document(entryId).delete()
    }
    
    func getWorkoutEntries(for date: Date) async throws -> [WorkoutLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId()
        
        let collection = getCollectionRef(for: .workout)
        print("🔍 Loading workout entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        let snapshot = try await collection
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        let entries = snapshot.documents.compactMap { WorkoutLogEntry(document: $0) }
            .sorted { $0.date < $1.date }
        
        print("📊 Found \(entries.count) workout entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Food Logs
    func addFoodEntry(_ entry: FoodLogEntry) async throws {
        let collection = getCollectionRef(for: .food)
        print("💾 Saving food entry to path: \(collection.path)/\(entry.id) for user: \(entry.userId)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Food entry saved successfully to Firestore")
    }
    
    func updateFoodEntry(_ entry: FoodLogEntry) async throws {
        let collection = getCollectionRef(for: .food)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteFoodEntry(_ entryId: String) async throws {
        let collection = getCollectionRef(for: .food)
        try await collection.document(entryId).delete()
    }
    
    func getFoodEntries(for date: Date) async throws -> [FoodLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId()
        
        let collection = getCollectionRef(for: .food)
        print("🔍 Loading food entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        let snapshot = try await collection
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        let entries = snapshot.documents.compactMap { FoodLogEntry(document: $0) }
            .sorted { $0.date < $1.date }
        
        print("📊 Found \(entries.count) food entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Scrapbook Entries (TEMPORARILY DISABLED)
    func getScrapbookEntries(for date: Date) async throws -> [ScrapbookEntry] {
        print("📖 Scrapbook operations temporarily disabled - returning empty array")
        return []
    }
    
    func addScrapbookEntry(_ entry: ScrapbookEntry) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping add operation")
    }
    
    func updateScrapbookEntry(_ entry: ScrapbookEntry) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping update operation")
    }
    
    func deleteScrapbookEntry(_ entry: ScrapbookEntry) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping delete operation")
    }
    
    func uploadPDFToStorage(_ pdfData: Data, fileName: String) async throws -> String {
        print("📖 Scrapbook operations temporarily disabled - returning dummy URL")
        return "disabled://scrapbook-temporarily-disabled"
    }
    
    func deletePDFFromStorage(url: String) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping storage delete")
    }
    
    // MARK: - Goals CRUD
    func addGoal(_ goal: Goal) async throws {
        let collection = getGoalsCollectionRef()
        try await collection.document(goal.id).setData(goalFirestoreData(goal))
    }
    
    func updateGoal(_ goal: Goal) async throws {
        let collection = getGoalsCollectionRef()
        try await collection.document(goal.id).setData(goalFirestoreData(goal))
    }
    
    func deleteGoal(_ goalId: String) async throws {
        let collection = getGoalsCollectionRef()
        try await collection.document(goalId).delete()
    }
    
    func loadGoals() async throws -> [Goal] {
        let snapshot = try await getGoalsCollectionRef().getDocuments()
        let loaded: [Goal] = snapshot.documents.compactMap { doc in
            guard let data = doc.data() as? [String: Any],
                  let description = data["description"] as? String,
                  let categoryIdStr = data["categoryId"] as? String,
                  let categoryUUID = UUID(uuidString: categoryIdStr),
                  let userId = data["userId"] as? String else { return nil }
            let dueTimestamp = data["dueDate"] as? Timestamp
            let dueDate = dueTimestamp?.dateValue()
            let linksArr = data["taskLinks"] as? [[String: Any]] ?? []
            let links: [Goal.TaskLink] = linksArr.compactMap { dict in
                if let taskId = dict["taskId"] as? String,
                   let listId = dict["listId"] as? String,
                   let kind = dict["accountKindRaw"] as? String {
                    return Goal.TaskLink(taskId: taskId, listId: listId, accountKindRaw: kind)
                }
                return nil
            }
            return Goal(id: doc.documentID, description: description, dueDate: dueDate, categoryId: categoryUUID, taskLinks: links, userId: userId)
        }
        return loaded
    }
    
    private func goalFirestoreData(_ goal: Goal) -> [String: Any] {
        var data: [String: Any] = [
            "description": goal.description,
            "categoryId": goal.categoryId.uuidString,
            "userId": goal.userId
        ]
        if let due = goal.dueDate {
            data["dueDate"] = Timestamp(date: due)
        }
        if !goal.taskLinks.isEmpty {
            data["taskLinks"] = goal.taskLinks.map { [
                "taskId": $0.taskId,
                "listId": $0.listId,
                "accountKindRaw": $0.accountKindRaw
            ] }
        }
        return data
    }
    
    // MARK: - Real-time Updates
    func startListening(for date: Date) {
        print("🎧 Starting real-time listeners for date: \(date)")
        removeAllListeners()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Weight entries listener
        let weightListener = getCollectionRef(for: .weight)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("timestamp", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to weight entries: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let entries = snapshot.documents.compactMap { WeightLogEntry(document: $0) }
                    .sorted { $0.timestamp < $1.timestamp }
                
                Task { @MainActor in
                    self.weightEntries = entries
                }
            }
        
        // Workout entries listener
        let workoutListener = getCollectionRef(for: .workout)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to workout entries: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let entries = snapshot.documents.compactMap { WorkoutLogEntry(document: $0) }
                    .sorted { $0.date < $1.date }
                
                Task { @MainActor in
                    self.workoutEntries = entries
                }
            }
        
        // Food entries listener
        let foodListener = getCollectionRef(for: .food)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to food entries: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let entries = snapshot.documents.compactMap { FoodLogEntry(document: $0) }
                    .sorted { $0.date < $1.date }
                
                Task { @MainActor in
                    self.foodEntries = entries
                }
            }
        
        listeners.append(contentsOf: [weightListener, workoutListener, foodListener])
    }
    
    private func removeAllListeners() {
        print("🔕 Removing all Firestore listeners")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Helper Methods
    private func convertCanvasToPDF(_ canvasView: PKCanvasView) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let bounds = canvasView.bounds
                let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
                
                let pdfData = pdfRenderer.pdfData { context in
                    context.beginPage()
                    canvasView.drawHierarchy(in: bounds, afterScreenUpdates: true)
                }
                
                continuation.resume(returning: pdfData)
            }
        }
    }
    
    private func uploadPDFToStorage(_ pdfData: Data, for date: Date) async throws -> String {
        // TEMPORARILY DISABLED - Storage operations suspended
        print("📖 Storage upload temporarily disabled")
        return "disabled://scrapbook-temporarily-disabled"
    }
    
    private func deleteFromStorage(url: String) async throws {
        // TEMPORARILY DISABLED - Storage operations suspended
        print("📖 Storage deletion temporarily disabled")
    }
    
    // MARK: - Test Functions (for debugging)
    func testFirestoreConnection() async {
        print("🧪 Testing Firestore connection...")
        do {
            let testData: [String: Any] = [
                "message": "Hello from LotusPlannerV3!",
                "timestamp": Timestamp(date: Date()),
                "testId": UUID().uuidString
            ]
            
            try await db.collection("test").document("connection-test").setData(testData)
            print("✅ Firestore connection test successful! Check your Firebase console.")
        } catch {
            print("❌ Firestore connection test failed: \(error)")
        }
    }
} 