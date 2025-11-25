import Foundation

class JournalFilePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue
    private let changeHandler: (URL) throws -> Void
    
    init(presentedItemURL: URL, changeHandler: @escaping (URL) throws -> Void) {
        self.presentedItemURL = presentedItemURL
        self.changeHandler = changeHandler
        self.presentedItemOperationQueue = OperationQueue()
        self.presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }
    
    private func handleChange(for url: URL) {
        do {
            try changeHandler(url)
        } catch {
            devLog("📝 Error handling file change: \(error)")
        }
    }
    
    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        handleChange(for: url)
    }
    
    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        handleChange(for: newURL)
    }
    
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        guard let url = presentedItemURL else {
            completionHandler(nil)
            return
        }
        handleChange(for: url)
        completionHandler(nil)
    }
    
    func presentedItemDidGain(_ version: NSFileVersion) {
        guard let url = presentedItemURL else { return }
        handleChange(for: url)
    }
    
    func presentedItemDidLose(_ version: NSFileVersion) {
        guard let url = presentedItemURL else { return }
        handleChange(for: url)
    }
}
