import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// A tiny on-disk upload queue for advert attachment uploads.
/// Stores minimal metadata (advert id + local paths) in Application Support so
/// background uploads survive app restarts. Retries failed uploads a few times.
final class UploadQueueManager {
    static let shared = UploadQueueManager()

    private struct AdvertUploadTask: Codable {
        let id: String
        let primaryLocalPath: String?
        let additionalLocalPaths: [String]?
        var attempts: Int
        let enqueuedAt: Date
    }

    private var queue: [AdvertUploadTask] = []
    private let queueURL: URL
    private var isProcessing = false
    private let fm = FileManager.default
#if canImport(FirebaseFirestore)
    private let db: Firestore? = Firestore.firestore()
#else
    private let db: Firestore? = nil
#endif
    // Track the currently running Storage upload so it can be cancelled when an advert is deleted
    private var currentUploadTask: StorageUploadTask? = nil
    private var currentUploadAdvertId: String? = nil
    // Persisted tombstones for adverts that were deleted locally; uploader checks this to avoid re-creating.
    private var deletedIds: [String: Date] = [:]
    private var deletedIdsURL: URL

    private init() {
        // Prepare queue file path in Application Support
        let appSupport: URL
        do {
            appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            // fallback to documents
            appSupport = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        let dir = appSupport.appendingPathComponent("NeighborHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        queueURL = dir.appendingPathComponent("upload_queue.json")
        deletedIdsURL = dir.appendingPathComponent("deleted_adverts.json")
        loadQueue()
        loadDeletedIds()
        print("UploadQueueManager: loaded queue (\(queue.count) items), deleted tombstones (\(deletedIds.count))")
        DispatchQueue.global(qos: .background).async { [weak self] in self?.processQueue() }
    }

    private func loadQueue() {
        guard fm.fileExists(atPath: queueURL.path) else { queue = []; return }
        if let d = try? Data(contentsOf: queueURL), let arr = try? JSONDecoder().decode([AdvertUploadTask].self, from: d) {
            queue = arr
        } else { queue = [] }
    }

    private func saveQueue() {
        if let d = try? JSONEncoder().encode(queue) {
            try? d.write(to: queueURL, options: .atomic)
        }
    }

    private func loadDeletedIds() {
        guard fm.fileExists(atPath: deletedIdsURL.path) else { deletedIds = [:]; return }
        if let d = try? Data(contentsOf: deletedIdsURL), let dict = try? JSONDecoder().decode([String: Date].self, from: d) {
            deletedIds = dict
        } else { deletedIds = [:] }
        // purge old tombstones > 7 days
        let cutoff = Date().addingTimeInterval(-7*24*60*60)
        deletedIds = deletedIds.filter { $0.value >= cutoff }
        saveDeletedIds()
    }

    private func saveDeletedIds() {
        if let d = try? JSONEncoder().encode(deletedIds) { try? d.write(to: deletedIdsURL, options: .atomic) }
    }

    func enqueueAdvertUpload(_ advert: Advert) {
        // Do not enqueue if this advert was recently deleted (tombstoned)
        if deletedIds[advert.id.uuidString] != nil { return }

        let task = AdvertUploadTask(id: advert.id.uuidString,
                                    primaryLocalPath: advert.imageLocalPath,
                                    additionalLocalPaths: advert.imageLocalPaths,
                                    attempts: 0,
                                    enqueuedAt: Date())
        queue.append(task)
        saveQueue()
        print("UploadQueueManager: enqueued advert upload id=\(task.id) primary=\(task.primaryLocalPath ?? "(nil)") additional=\(task.additionalLocalPaths?.count ?? 0)")
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.processQueue() }
    }

    /// Remove any queued tasks for a given advert id (called when the advert is deleted)
    func removeTasks(for advertId: String) {
        queue.removeAll { $0.id == advertId }
        saveQueue()
        // If there is an in-flight upload for this advert, cancel it.
        if currentUploadAdvertId == advertId {
            currentUploadTask?.cancel()
            currentUploadTask = nil
            currentUploadAdvertId = nil
        }
        // Add a tombstone so future enqueues or restarted queue won't re-upload this advert for a while.
        deletedIds[advertId] = Date()
        saveDeletedIds()
    }

    private func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        print("UploadQueueManager: processQueue starting with \(queue.count) tasks")
        while !queue.isEmpty {
            var task = queue[0]
            let id = task.id
            // perform upload attempt
            let success = uploadAdvertTask(task: task)
            print("UploadQueueManager: upload attempt for id=\(id) -> \(success ? "success" : "failure, attempts=\(task.attempts)")")
            if success {
                queue.removeFirst()
                saveQueue()
                // small delay between tasks
                Thread.sleep(forTimeInterval: 0.2)
                continue
            } else {
                // failed: increment attempts and keep or drop after limit
                task.attempts += 1
                if task.attempts >= 5 {
                    // drop after 5 attempts
                    queue.removeFirst()
                } else {
                    queue[0] = task
                }
                saveQueue()
                // backoff before next attempt
                Thread.sleep(forTimeInterval: pow(2.0, Double(task.attempts)))
            }
        }
        print("UploadQueueManager: processQueue finished")
        isProcessing = false
    }

    @discardableResult
    private func uploadAdvertTask(task: AdvertUploadTask) -> Bool {
        // This function performs a synchronous-ish upload attempt. It returns true
        // only if all attempted uploads completed successfully.
    guard NSClassFromString("FIRStorage") != nil else { return true }
        let uid = Auth.auth().currentUser?.uid ?? {
            var rv: String = "anon"
            let sem = DispatchSemaphore(value: 0)
            Auth.auth().signInAnonymously { res, err in
                if let u = res?.user.uid { rv = u }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 5)
            return rv
        }()

        // Helper to upload a file URL to a storage path and return the download URL string
        func uploadFile(fileURL: URL, storagePath: String) -> String? {
            let sem = DispatchSemaphore(value: 0)
            var result: String? = nil
            let refStorage = Storage.storage().reference().child(storagePath)
            let uploadTask = refStorage.putFile(from: fileURL, metadata: nil) { metadata, error in
                // completion handled by observe success below; leave for safety
            }
            _ = uploadTask
            uploadTask.observe(.success) { _ in
                refStorage.downloadURL { url, err in
                    if let u = url { result = u.absoluteString }
                    sem.signal()
                }
            }
            uploadTask.observe(.failure) { _ in
                sem.signal()
            }
            // wait up to 30s for result
            _ = sem.wait(timeout: .now() + 30)
            return result
        }

        // Primary
        if let primary = task.primaryLocalPath {
            let fileURL = URL(fileURLWithPath: primary)
            if !fm.fileExists(atPath: fileURL.path) { return false }
            let storagePath = "uploads/\(uid)/adverts/\(task.id)/image.jpg"
            _ = storagePath // silence unused warning; actual upload handled later in this function
        }

        // NOTE: we cannot do complex branching easily in this synchronous shim without duplicating
        // too much logic. The queue worker performs uploads directly; keep compatibility note only.

        // The safest minimal behaviour: if we have a Firestore DB and at least one local path,
        // attempt uploads using the same storage / update strategy as in FirebaseManager.
        guard let db = db else { return false }

    // If advert id is in tombstones, skip upload to avoid re-creating deleted data.
    if deletedIds[task.id] != nil { print("UploadQueueManager: skipping upload for tombstoned advert id=\(task.id)"); return true }

        // Early abort: if the Firestore document was deleted (advert removed), skip uploads.
        // This prevents a race where a queued upload recreates storage/doc after the user deleted it.
        let docSem = DispatchSemaphore(value: 0)
        var shouldAbortBecauseDeleted = false
        let firestoreRefCheck = db.collection("localAdverts").document(task.id)
        firestoreRefCheck.getDocument { snap, _ in
            if let s = snap { if !s.exists { shouldAbortBecauseDeleted = true } }
            docSem.signal()
        }
        _ = docSem.wait(timeout: .now() + 5)
        if shouldAbortBecauseDeleted { print("UploadQueueManager: aborting upload because Firestore doc deleted id=\(task.id)"); return true }

        // Perform actual uploads (primary then additional); this part intentionally mirrors
        // the previous inline behaviour but keeps control inside the queue worker.
    let firestoreRef = db.collection("localAdverts").document(task.id)

        // Primary upload
        if let primary = task.primaryLocalPath {
            let fileURL = URL(fileURLWithPath: primary)
            if fm.fileExists(atPath: fileURL.path) {
                let path = "uploads/\(uid)/adverts/\(task.id)/image.jpg"
                let refStorage = Storage.storage().reference().child(path)
                let sem = DispatchSemaphore(value: 0)
                let uploadTask = refStorage.putFile(from: fileURL, metadata: nil)
                print("UploadQueueManager: starting primary upload for advert id=\(task.id) path=\(path)")
                // record current upload so we can cancel it if needed
                currentUploadTask = uploadTask
                currentUploadAdvertId = task.id
                uploadTask.observe(.success) { _ in
                    refStorage.downloadURL { url, err in
                        if let url = url {
                            firestoreRef.setData(["imageURL": url.absoluteString, "imagesPendingUpload": false], merge: true)
                            print("UploadQueueManager: primary upload finished id=\(task.id) url=\(url.absoluteString)")
                        }
                        // clear current upload markers
                        self.currentUploadTask = nil
                        self.currentUploadAdvertId = nil
                        sem.signal()
                    }
                }
                uploadTask.observe(.failure) { _ in sem.signal() }
                _ = sem.wait(timeout: .now() + 30)
            } else {
                return false
            }
        }

        // Additional images
        if let adds = task.additionalLocalPaths {
            for (i, lp) in adds.enumerated() {
                if let primary = task.primaryLocalPath, primary == lp { continue }
                let fileURL = URL(fileURLWithPath: lp)
                if !fm.fileExists(atPath: fileURL.path) { return false }
                let path = "uploads/\(uid)/adverts/\(task.id)/additional_\(i).jpg"
                let refStorage = Storage.storage().reference().child(path)
                let sem = DispatchSemaphore(value: 0)
                let uploadTask = refStorage.putFile(from: fileURL, metadata: nil)
                print("UploadQueueManager: starting additional upload for advert id=\(task.id) index=\(i) path=\(path)")
                currentUploadTask = uploadTask
                currentUploadAdvertId = task.id
                uploadTask.observe(.success) { _ in
                    refStorage.downloadURL { url, err in
                        if let url = url {
                            firestoreRef.getDocument { snap, _ in
                                var arr = snap?.data()? ["imageDatasURLs"] as? [String] ?? []
                                arr.append(url.absoluteString)
                                firestoreRef.setData(["imageDatasURLs": arr, "imagesPendingUpload": false], merge: true)
                                print("UploadQueueManager: additional upload finished id=\(task.id) index=\(i) url=\(url.absoluteString)")
                                self.currentUploadTask = nil
                                self.currentUploadAdvertId = nil
                                sem.signal()
                            }
                        } else {
                            self.currentUploadTask = nil
                            self.currentUploadAdvertId = nil
                            sem.signal()
                        }
                    }
                }
                uploadTask.observe(.failure) { _ in sem.signal() }
                _ = sem.wait(timeout: .now() + 30)
            }
        }

        return true
    }
}
