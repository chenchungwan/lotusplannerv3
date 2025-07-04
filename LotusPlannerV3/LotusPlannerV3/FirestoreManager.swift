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
    private func getCollectionRef(for type: LogType, accountKind: GoogleAuthManager.AccountKind) -> CollectionReference {
        let userId = getUserId(for: accountKind)
        return db.collection("users")
            .document(userId)
            .collection(accountKind.rawValue)
            .document("logs")
            .collection(type.rawValue)
    }
    
    private func getScrapbookCollectionRef(for accountKind: GoogleAuthManager.AccountKind) -> CollectionReference {
        let userId = getUserId(for: accountKind)
        return db.collection("users")
            .document(userId)
            .collection(accountKind.rawValue)
            .document("scrapbook")
            .collection("entries")
    }
    
    private func getRecurringTasksCollectionRef(for accountKind: GoogleAuthManager.AccountKind) -> CollectionReference {
        let userId = getUserId(for: accountKind)
        return db.collection("users")
            .document(userId)
            .collection(accountKind.rawValue)
            .document("tasks")
            .collection("recurring")
    }
    
    private func getRecurringTaskInstancesCollectionRef(for accountKind: GoogleAuthManager.AccountKind) -> CollectionReference {
        let userId = getUserId(for: accountKind)
        return db.collection("users")
            .document(userId)
            .collection(accountKind.rawValue)
            .document("tasks")
            .collection("instances")
    }
    
    private func getUserId(for accountKind: GoogleAuthManager.AccountKind) -> String {
        let email = authManager.getEmail(for: accountKind)
        let userId = email.isEmpty ? "anonymous" : email
        print("🔍 FirestoreManager getUserId for \(accountKind): \(userId)")
        return userId
    }
    
    // MARK: - Weight Logs
    func addWeightEntry(_ entry: WeightLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .weight, accountKind: accountKind)
        print("💾 Saving weight entry to path: \(collection.path)/\(entry.id)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Weight entry saved successfully to Firestore")
    }
    
    func updateWeightEntry(_ entry: WeightLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .weight, accountKind: accountKind)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteWeightEntry(_ entryId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .weight, accountKind: accountKind)
        try await collection.document(entryId).delete()
    }
    
    func getWeightEntries(for date: Date, accountKind: GoogleAuthManager.AccountKind) async throws -> [WeightLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId(for: accountKind)
        
        let collection = getCollectionRef(for: .weight, accountKind: accountKind)
        print("🔍 Loading weight entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        // Remove userId filter since collection path is already user-specific
        let snapshot = try await collection
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("timestamp", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        // Sort in memory to avoid compound index requirement
        let entries = snapshot.documents.compactMap { WeightLogEntry(document: $0) }
            .sorted { $0.timestamp < $1.timestamp }
        
        print("📊 Found \(entries.count) weight entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Workout Logs
    func addWorkoutEntry(_ entry: WorkoutLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .workout, accountKind: accountKind)
        print("💾 Saving workout entry to path: \(collection.path)/\(entry.id) for user: \(entry.userId)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Workout entry saved successfully to Firestore")
    }
    
    func updateWorkoutEntry(_ entry: WorkoutLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .workout, accountKind: accountKind)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteWorkoutEntry(_ entryId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .workout, accountKind: accountKind)
        try await collection.document(entryId).delete()
    }
    
    func getWorkoutEntries(for date: Date, accountKind: GoogleAuthManager.AccountKind) async throws -> [WorkoutLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId(for: accountKind)
        
        let collection = getCollectionRef(for: .workout, accountKind: accountKind)
        print("🔍 Loading workout entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        // Remove userId filter since collection path is already user-specific
        let snapshot = try await collection
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        // Sort in memory to avoid compound index requirement
        let entries = snapshot.documents.compactMap { WorkoutLogEntry(document: $0) }
            .sorted { $0.date < $1.date }
        
        print("📊 Found \(entries.count) workout entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Food Logs
    func addFoodEntry(_ entry: FoodLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .food, accountKind: accountKind)
        print("💾 Saving food entry to path: \(collection.path)/\(entry.id) for user: \(entry.userId)")
        try await collection.document(entry.id).setData(entry.firestoreData)
        print("✅ Food entry saved successfully to Firestore")
    }
    
    func updateFoodEntry(_ entry: FoodLogEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .food, accountKind: accountKind)
        try await collection.document(entry.id).updateData(entry.firestoreData)
    }
    
    func deleteFoodEntry(_ entryId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getCollectionRef(for: .food, accountKind: accountKind)
        try await collection.document(entryId).delete()
    }
    
    func getFoodEntries(for date: Date, accountKind: GoogleAuthManager.AccountKind) async throws -> [FoodLogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId(for: accountKind)
        
        let collection = getCollectionRef(for: .food, accountKind: accountKind)
        print("🔍 Loading food entries from: \(collection.path) for user: \(currentUserId), date range: \(startOfDay) to \(endOfDay)")
        
        // Remove userId filter since collection path is already user-specific
        let snapshot = try await collection
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        // Sort in memory to avoid compound index requirement
        let entries = snapshot.documents.compactMap { FoodLogEntry(document: $0) }
            .sorted { $0.date < $1.date }
        
        print("📊 Found \(entries.count) food entries for user: \(currentUserId)")
        return entries
    }
    
    // MARK: - Recurring Tasks
    func addRecurringTask(_ task: RecurringTask, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getRecurringTasksCollectionRef(for: accountKind)
        print("💾 Saving recurring task to path: \(collection.path)/\(task.id)")
        try await collection.document(task.id).setData(task.firestoreData)
        print("✅ Recurring task saved successfully to Firestore")
    }
    
    func updateRecurringTask(_ task: RecurringTask, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getRecurringTasksCollectionRef(for: accountKind)
        try await collection.document(task.id).updateData(task.firestoreData)
        print("✅ Recurring task updated successfully")
    }
    
    func deleteRecurringTask(_ taskId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getRecurringTasksCollectionRef(for: accountKind)
        try await collection.document(taskId).delete()
        print("✅ Recurring task deleted successfully")
    }
    
    func getRecurringTasks(for accountKind: GoogleAuthManager.AccountKind) async throws -> [RecurringTask] {
        let collection = getRecurringTasksCollectionRef(for: accountKind)
        let currentUserId = getUserId(for: accountKind)
        
        print("🔍 Loading recurring tasks from: \(collection.path) for user: \(currentUserId)")
        
        let snapshot = try await collection
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let tasks = snapshot.documents.compactMap { RecurringTask(document: $0) }
        print("📊 Found \(tasks.count) recurring tasks for user: \(currentUserId)")
        return tasks
    }
    
    func getRecurringTask(by id: String, for accountKind: GoogleAuthManager.AccountKind) async throws -> RecurringTask? {
        let collection = getRecurringTasksCollectionRef(for: accountKind)
        let document = try await collection.document(id).getDocument()
        return RecurringTask(document: document)
    }
    
    // MARK: - Recurring Task Instances
    func addRecurringTaskInstance(_ instance: RecurringTaskInstance, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getRecurringTaskInstancesCollectionRef(for: accountKind)
        print("💾 Saving recurring task instance to path: \(collection.path)/\(instance.id)")
        try await collection.document(instance.id).setData(instance.firestoreData)
        print("✅ Recurring task instance saved successfully to Firestore")
    }
    
    func updateRecurringTaskInstance(_ instance: RecurringTaskInstance, for accountKind: GoogleAuthManager.AccountKind) async throws {
        let collection = getRecurringTaskInstancesCollectionRef(for: accountKind)
        try await collection.document(instance.id).updateData(instance.firestoreData)
        print("✅ Recurring task instance updated successfully")
    }
    
    func getRecurringTaskInstances(for recurringTaskId: String, accountKind: GoogleAuthManager.AccountKind) async throws -> [RecurringTaskInstance] {
        let collection = getRecurringTaskInstancesCollectionRef(for: accountKind)
        let currentUserId = getUserId(for: accountKind)
        
        print("🔍 Loading recurring task instances from: \(collection.path) for recurring task: \(recurringTaskId), user: \(currentUserId)")
        
        let snapshot = try await collection
            .whereField("recurringTaskId", isEqualTo: recurringTaskId)
            .getDocuments()
        
        let instances = snapshot.documents.compactMap { RecurringTaskInstance(document: $0) }
        print("📊 Found \(instances.count) instances for recurring task: \(recurringTaskId)")
        return instances
    }
    
    func getRecurringTaskInstanceByGoogleTaskId(_ googleTaskId: String, for accountKind: GoogleAuthManager.AccountKind) async throws -> RecurringTaskInstance? {
        let collection = getRecurringTaskInstancesCollectionRef(for: accountKind)
        
        let snapshot = try await collection
            .whereField("googleTaskId", isEqualTo: googleTaskId)
            .limit(to: 1)
            .getDocuments()
        
        return snapshot.documents.compactMap { RecurringTaskInstance(document: $0) }.first
    }
    
    // MARK: - Scrapbook Entries (TEMPORARILY DISABLED)
    func getScrapbookEntries(for date: Date, accountKind: GoogleAuthManager.AccountKind) async throws -> [ScrapbookEntry] {
        print("📖 Scrapbook operations temporarily disabled - returning empty array")
        return []
    }
    
    func addScrapbookEntry(_ entry: ScrapbookEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping add operation")
    }
    
    func updateScrapbookEntry(_ entry: ScrapbookEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping update operation")
    }
    
    func deleteScrapbookEntry(_ entry: ScrapbookEntry, for accountKind: GoogleAuthManager.AccountKind) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping delete operation")
    }
    
    func uploadPDFToStorage(_ pdfData: Data, fileName: String, for accountKind: GoogleAuthManager.AccountKind) async throws -> String {
        print("📖 Scrapbook operations temporarily disabled - returning dummy URL")
        return "disabled://scrapbook-temporarily-disabled"
    }
    
    func deletePDFFromStorage(url: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        print("📖 Scrapbook operations temporarily disabled - skipping storage delete")
    }
    
    // MARK: - Real-time Listeners
    func startListening(for date: Date, accountKind: GoogleAuthManager.AccountKind) {
        removeAllListeners()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let currentUserId = getUserId(for: accountKind)
        
        print("🎧 Starting real-time listeners for date: \(date), account: \(accountKind), user: \(currentUserId)")
        
        // Weight entries listener - removed userId filter since collection path is already user-specific
        let weightListener = getCollectionRef(for: .weight, accountKind: accountKind)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("timestamp", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else {
                    if let error = error {
                        print("❌ Weight listener error: \(error)")
                        self?.errorMessage = error.localizedDescription
                    }
                    return
                }
                
                let newEntries = snapshot.documents.compactMap { WeightLogEntry(document: $0) }
                
                // Merge with existing entries, avoiding duplicates
                var mergedEntries = self.weightEntries.filter { existing in
                    !newEntries.contains { new in new.id == existing.id }
                }
                mergedEntries.append(contentsOf: newEntries)
                // Sort in memory to avoid compound index requirement
                mergedEntries.sort { $0.timestamp < $1.timestamp }
                
                self.weightEntries = mergedEntries
                print("🔄 Weight entries updated: \(mergedEntries.count) total for user: \(currentUserId)")
            }
        
        // Workout entries listener - removed userId filter since collection path is already user-specific
        let workoutListener = getCollectionRef(for: .workout, accountKind: accountKind)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else {
                    if let error = error {
                        print("❌ Workout listener error: \(error)")
                        self?.errorMessage = error.localizedDescription
                    }
                    return
                }
                
                let newEntries = snapshot.documents.compactMap { WorkoutLogEntry(document: $0) }
                
                // Merge with existing entries, avoiding duplicates
                var mergedEntries = self.workoutEntries.filter { existing in
                    !newEntries.contains { new in new.id == existing.id }
                }
                mergedEntries.append(contentsOf: newEntries)
                // Sort in memory to avoid compound index requirement
                mergedEntries.sort { $0.date < $1.date }
                
                self.workoutEntries = mergedEntries
                print("🔄 Workout entries updated: \(mergedEntries.count) total for user: \(currentUserId)")
            }
        
        // Food entries listener - removed userId filter since collection path is already user-specific
        let foodListener = getCollectionRef(for: .food, accountKind: accountKind)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else {
                    if let error = error {
                        print("❌ Food listener error: \(error)")
                        self?.errorMessage = error.localizedDescription
                    }
                    return
                }
                
                let newEntries = snapshot.documents.compactMap { FoodLogEntry(document: $0) }
                
                // Merge with existing entries, avoiding duplicates
                var mergedEntries = self.foodEntries.filter { existing in
                    !newEntries.contains { new in new.id == existing.id }
                }
                mergedEntries.append(contentsOf: newEntries)
                // Sort in memory to avoid compound index requirement
                mergedEntries.sort { $0.date < $1.date }
                
                self.foodEntries = mergedEntries
                print("🔄 Food entries updated: \(mergedEntries.count) total for user: \(currentUserId)")
            }
        
        // Scrapbook entries listener - TEMPORARILY DISABLED
        print("📖 Scrapbook listener temporarily disabled - setting empty array")
        self.scrapbookEntries = []
        
        // Update listeners array to include only active listeners (no scrapbook)
        listeners = [weightListener, workoutListener, foodListener]
        print("✅ All real-time listeners started for user: \(currentUserId)")
    }
    
    func removeAllListeners() {
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
    
    private func uploadPDFToStorage(_ pdfData: Data, for date: Date, accountKind: GoogleAuthManager.AccountKind) async throws -> String {
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