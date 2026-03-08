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
// Optional import for Auth (anonymous sign-in fallback)
#if canImport(FirebaseAuth)
    import FirebaseAuth
#endif
// Optional import for App Check (used for debug provider fallback)
#if canImport(FirebaseAppCheck)
    import FirebaseAppCheck
#endif

// Notifications for upload progress and completion for community attachments
extension Notification.Name {
    static let communityUploadProgress = Notification.Name("communityUploadProgress")
    static let communityUploadCompleted = Notification.Name("communityUploadCompleted")
    static let eventUploadProgress = Notification.Name("eventUploadProgress")
    static let eventUploadCompleted = Notification.Name("eventUploadCompleted")
    static let marketplaceUploadProgress = Notification.Name("marketplaceUploadProgress")
    static let marketplaceUploadCompleted = Notification.Name("marketplaceUploadCompleted")
}

// MARK: - Emergency Contact Data Model
struct EmergencySettings: Codable {
    var fireNumber: String
    var emergencyNumber: String
    var medicalNumber: String
    var updatedBy: String
    var updatedAt: Date
    
    init(fireNumber: String = "911", emergencyNumber: String = "911", medicalNumber: String = "911", updatedBy: String = "", updatedAt: Date = Date()) {
        self.fireNumber = fireNumber
        self.emergencyNumber = emergencyNumber
        self.medicalNumber = medicalNumber
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }
}

struct EmergencyContactData: Identifiable, Codable {
    let id: String
    let name: String
    let phone: String
    let email: String
    let organization: String
    let category: String
    let priority: String
    let availability: String
    let notes: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let isActive: Bool
    
    init(id: String = UUID().uuidString, name: String, phone: String, email: String = "", organization: String = "", category: String, priority: String, availability: String = "", notes: String = "", createdBy: String, createdAt: Date = Date(), updatedAt: Date = Date(), isActive: Bool = true) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.organization = organization
        self.category = category
        self.priority = priority
        self.availability = availability
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }
}

#if canImport(FirebaseCore)
    import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif
#if canImport(FirebaseStorage)
    import FirebaseStorage
#endif

/// Lightweight Firestore wrapper for community features (polls, messages).
final class FirebaseManager {
    static let shared = FirebaseManager()

    #if canImport(FirebaseFirestore)
        private let db: Firestore
        private var activePollListener: ListenerRegistration?
        private var archivedPollsListener: ListenerRegistration?
        // Support multiple listeners for community messages so different parts of the app
        // (HomeView, ChatMessagesManager, etc.) can independently receive snapshot updates.
        private var communityMessagesListeners: [ListenerRegistration] = []
    #endif

    /// Optional uploads UID to listen to under `uploads/{uid}/communityMessages`.
    /// This can be set at runtime so different parts of the app can choose which
    /// uploads subcollection to observe. Persisted to UserDefaults under key
    /// "communityUploadsUID" so the selection survives app restarts.
    var communityUploadsUID: String? { return _communityUploadsUID }
    private var _communityUploadsUID: String? = nil {
        didSet {
            // persist selection
            let key = "communityUploadsUID"
            if let v = _communityUploadsUID {
                UserDefaults.standard.setValue(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    // Cache management constants
    private let maxCacheSize: Int = 100 * 1024 * 1024  // 100MB
    private let cacheExpirationDays: Int = 30

    private init() {
        #if canImport(FirebaseCore)
            if FirebaseApp.app() == nil {
                // For local development and debugging, use the App Check debug provider so
                // that unregistered/dev apps don't get rejected by the App Check exchange.
                // This is enabled only in DEBUG builds and only if FirebaseAppCheck is available.
                #if canImport(FirebaseAppCheck)
                    #if DEBUG
                        // Install the debug provider. After first run you'll see a debug token in the logs
                        // which you can add to the Firebase Console App Check -> Debug tokens, or set
                        // as an environment variable for the scheme (FIRAppCheckDebugToken).
                        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
                    #endif
                #endif
                FirebaseApp.configure()
            }
        #endif
        #if canImport(FirebaseFirestore)
            db = Firestore.firestore()
        #endif
        #if canImport(FirebaseStorage)
            storage = Storage.storage()
        #endif
    }

    // Convert a Storage download URL (https://.../v0/b/<bucket>/o/<encodedPath>?...) or gs:// URL
    // into a StorageReference. This handles the common Firebase downloadURL format which
    // `Storage.reference(forURL:)` sometimes doesn't accept directly for https URLs.
    #if canImport(FirebaseStorage)
    private func storageReference(fromDownloadURLString s: String) -> StorageReference? {
        // Validate URL string before attempting conversion
        guard !s.isEmpty, 
              s.count < 2048, // Reasonable URL length limit
              (s.hasPrefix("gs://") || s.hasPrefix("http://") || s.hasPrefix("https://")) else {
            print("⚠️ Invalid storage URL format: \(s.prefix(100))...")
            return nil
        }
        
        // Try direct reference(forURL:) for gs:// URLs
        if s.hasPrefix("gs://") {
            do {
                let ref = try Storage.storage().reference(forURL: s)
                return ref
            } catch {
                print("⚠️ Failed to create reference from gs:// URL: \(error)")
                return nil
            }
        }
        
        // Parse Firebase Storage download URL: https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encodedPath>?alt=media&token=...
        if let url = URL(string: s) {
            let path = url.path
            // look for /v0/b/<bucket>/o/<encodedPath>
            if path.contains("/v0/b/") && path.contains("/o/") {
                // extract bucket between /v0/b/ and /o/
                if let bRangeStart = path.range(of: "/v0/b/")?.upperBound,
                    let oRange = path.range(of: "/o/")
                {
                    let bucket = String(path[bRangeStart..<oRange.lowerBound])
                    let encoded = String(path[oRange.upperBound...])
                    // encoded path is percent-encoded; decode it
                    let decoded = encoded.removingPercentEncoding ?? encoded
                    // build gs:// URL
                    let gs = "gs://\(bucket)/\(decoded)"
                    do {
                        let ref2 = try Storage.storage().reference(forURL: gs)
                        return ref2
                    } catch {
                        // fallback to reference().child(decoded)
                    }
                    //
                    return Storage.storage().reference().child(decoded)
                }
            }
            // If host is storage.googleapis.com and path contains /b/<bucket>/o/<encoded>
            let comps = url.pathComponents
            if comps.contains("b") && comps.contains("o") {
                // attempt to locate 'b' and 'o'
                if let bIndex = comps.firstIndex(of: "b"), bIndex + 1 < comps.count,
                    let oIndex = comps.firstIndex(of: "o"), oIndex + 1 < comps.count
                {
                    let bucket = comps[bIndex + 1]
                    let encoded = comps[oIndex + 1]
                    let decoded = encoded.removingPercentEncoding ?? encoded
                    let gs = "gs://\(bucket)/\(decoded)"
                    do {
                        let ref2 = try Storage.storage().reference(forURL: gs)
                        return ref2
                    } catch {
                        // Continue to fallback
                    }
                    return Storage.storage().reference().child(decoded)
                }
            }
        }
        return nil
    }
    #endif

    // MARK: - Local persistence helpers
    /// Persist or upsert a Codable item into a JSON array stored in UserDefaults under `key`.
    /// This is used for quick local-first fallbacks so the UI shows content immediately.
    private func upsertLocalCodableArray<T: Codable & Identifiable>(_ item: T, key: String) {
        var arr: [T] = []
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty,
            let data = existing.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([T].self, from: data)
        {
            arr = decoded
        }

        // Generic-safe id string conversion: support UUID, String, CustomStringConvertible or fallback to description
        func idToString(_ anyId: Any) -> String {
            if let u = anyId as? UUID { return u.uuidString }
            if let s = anyId as? String { return s }
            if let desc = anyId as? CustomStringConvertible { return desc.description }
            return String(describing: anyId)
        }

        let newId = idToString(item.id as Any)
        if let idx = arr.firstIndex(where: { idToString($0.id as Any) == newId }) {
            arr[idx] = item
        } else {
            arr.insert(item, at: 0)
        }
        if let encoded = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.setValue(String(data: encoded, encoding: .utf8), forKey: key)
        }
    }

    /// Save binary data to Application Support/NeighborHub/Files and return the path if successful.
    private func saveFileToApplicationSupport(data: Data, filename: String) -> String? {
        let fm = FileManager.default
        do {
            let appSupport = try fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true)
            let filesDir = appSupport.appendingPathComponent("NeighborHub/Files", isDirectory: true)
            try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
            let dest = filesDir.appendingPathComponent(filename)
            try data.write(to: dest, options: .atomic)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            var mutable = dest
            try? mutable.setResourceValues(rv)
            return dest.path
        } catch {
            print("FirebaseManager: failed to save file to Application Support: \(error)")
            return nil
        }
    }

    #if canImport(FirebaseStorage)
        private let storage: Storage
    #endif

    #if canImport(FirebaseFirestore)
        struct PollDTO: Codable {
            var id: String
            var question: String
            var options: [String]
            var votes: [Int]
            var votesByUser: [String: Int]?  // userId -> optionIdx
            var expiresAt: Timestamp?
            var createdAt: Timestamp?
        }

        // Helper to build PollDTO from Firestore document data without using JSONSerialization
        private func pollDTO(from data: [String: Any]) -> PollDTO? {
            // Check if poll is archived - if so, don't return it as an active poll
            if data["archivedAt"] != nil {
                print("🗳️ Poll is archived, ignoring in active poll listener")
                return nil
            }

            guard let id = data["id"] as? String,
                let question = data["question"] as? String,
                let options = data["options"] as? [String]
            else {
                return nil
            }
            // votes can be stored as [Int] or [NSNumber]
            var votes: [Int] = []
            if let rawVotes = data["votes"] as? [Any] {
                for v in rawVotes {
                    if let i = v as? Int {
                        votes.append(i)
                    } else if let i64 = v as? Int64 {
                        votes.append(Int(i64))
                    } else if let num = v as? NSNumber {
                        votes.append(num.intValue)
                    } else {
                        votes.append(0)
                    }
                }
            }

            // Ensure votes array matches options array length to prevent crashes
            while votes.count < options.count {
                votes.append(0)
            }
            while votes.count > options.count {
                votes.removeLast()
            }
            // votesByUser may be [String:Any] with numeric values
            var votesByUser: [String: Int]? = nil
            if let raw = data["votesByUser"] as? [String: Any] {
                var m: [String: Int] = [:]
                for (k, v) in raw {
                    if let i = v as? Int {
                        m[k] = i
                    } else if let i64 = v as? Int64 {
                        m[k] = Int(i64)
                    } else if let num = v as? NSNumber {
                        m[k] = num.intValue
                    }
                }
                votesByUser = m
            }
            let expiresAt = data["expiresAt"] as? Timestamp
            let createdAt = data["createdAt"] as? Timestamp
            return PollDTO(
                id: id, question: question, options: options, votes: votes,
                votesByUser: votesByUser, expiresAt: expiresAt, createdAt: createdAt)
        }

        /// Watch the active poll document (singleton doc at 'polls/active') and deliver decoded dicts.
        func watchActivePoll(onUpdate: @escaping (PollDTO?) -> Void) {
            stopWatchingActivePoll()
            let ref = db.collection("polls").document("active")
            activePollListener = ref.addSnapshotListener { snap, error in
                // Provide explicit diagnostics: error, snapshot presence, existence flag, and data presence.
                if let err = error {
                    print("FirebaseManager.watchActivePoll: listener returned error: \(err)")
                    onUpdate(nil)
                    return
                }
                guard let snap = snap else {
                    print("FirebaseManager.watchActivePoll: listener fired but snapshot is nil")
                    onUpdate(nil)
                    return
                }
                // If the document doesn't exist, snap.exists == false. If it exists but has no fields, snap.data() may be empty.
                if !snap.exists {
                    print(
                        "FirebaseManager.watchActivePoll: snapshot exists==false (document missing): path=\(snap.reference.path)"
                    )
                    onUpdate(nil)
                    return
                }
                guard let dataDict = snap.data() else {
                    print(
                        "FirebaseManager.watchActivePoll: snapshot exists but data() == nil for path=\(snap.reference.path)"
                    )
                    onUpdate(nil)
                    return
                }
                // Debug: surface the raw document data so we can see shapes coming from server
                print("FirebaseManager.watchActivePoll: received active poll snapshot: \(dataDict)")
                if let dto = self.pollDTO(from: dataDict) {
                    onUpdate(dto)
                } else {
                    print(
                        "FirebaseManager.watchActivePoll: failed to parse PollDTO from snapshot data"
                    )
                    onUpdate(nil)
                }
            }
        }

        func stopWatchingActivePoll() {
            activePollListener?.remove()
            activePollListener = nil
        }

        func createOrUpdateActivePoll(_ poll: PollDTO, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("polls").document("active")
            // To avoid unnecessary writes (which can cause quota/exhaustion when clients repeatedly
            // write identical data), first fetch the existing document and compare key fields.
            // If nothing changed, skip setData.
            ref.getDocument { snap, err in
                if let err = err {
                    print("Error getting document: \(err)")
                    completion?(err)
                    return
                }

                // Build desired dict
                var desired: [String: Any] = [
                    "id": poll.id,
                    "question": poll.question,
                    "options": poll.options,
                    "votes": poll.votes,
                    "votesByUser": poll.votesByUser ?? [:],
                ]
                if let expires = poll.expiresAt { desired["expiresAt"] = expires }
                if let created = poll.createdAt { desired["createdAt"] = created }

                // If there's no existing document, write the desired dict.
                guard let existing = snap?.data() else {
                    ref.setData(desired) { setErr in completion?(setErr) }
                    return
                }

                // Compare relevant fields conservatively. If equal, skip write.
                var isEqual = true
                // id
                if let exId = existing["id"] as? String {
                    if exId != poll.id { isEqual = false }
                } else {
                    isEqual = false
                }
                // question
                if let exQ = existing["question"] as? String {
                    if exQ != poll.question { isEqual = false }
                } else {
                    isEqual = false
                }
                // options (as [String])
                if let exOptions = existing["options"] as? [String] {
                    if exOptions != poll.options { isEqual = false }
                } else {
                    isEqual = false
                }
                // votes (normalize to [Int])
                if let rawVotes = existing["votes"] as? [Any] {
                    var exVotes: [Int] = []
                    for v in rawVotes {
                        if let i = v as? Int {
                            exVotes.append(i)
                        } else if let i64 = v as? Int64 {
                            exVotes.append(Int(i64))
                        } else if let num = v as? NSNumber {
                            exVotes.append(num.intValue)
                        } else {
                            exVotes.append(0)
                        }
                    }
                    if exVotes != poll.votes { isEqual = false }
                } else {
                    isEqual = false
                }
                // votesByUser (normalize)
                if let rawByUser = existing["votesByUser"] as? [String: Any] {
                    var exByUser: [String: Int] = [:]
                    for (k, v) in rawByUser {
                        if let i = v as? Int {
                            exByUser[k] = i
                        } else if let i64 = v as? Int64 {
                            exByUser[k] = Int(i64)
                        } else if let num = v as? NSNumber {
                            exByUser[k] = num.intValue
                        }
                    }
                    if exByUser != (poll.votesByUser ?? [:]) { isEqual = false }
                } else {
                    // If existing has no votesByUser but desired has entries, not equal
                    if let desiredBy = poll.votesByUser, !desiredBy.isEmpty { isEqual = false }
                }
                // expiresAt
                if let exExpires = existing["expiresAt"] as? Timestamp {
                    let desiredExpires = poll.expiresAt?.dateValue()
                    if exExpires.dateValue() != desiredExpires { isEqual = false }
                } else {
                    if poll.expiresAt != nil { isEqual = false }
                }
                // createdAt
                if let exCreated = existing["createdAt"] as? Timestamp {
                    let desiredCreated = poll.createdAt?.dateValue()
                    if exCreated.dateValue() != desiredCreated { isEqual = false }
                } else {
                    if poll.createdAt != nil { isEqual = false }
                }

                if isEqual {
                    completion?(nil)  // no-op: nothing to update
                    return
                }

                // Otherwise write the desired dict
                ref.setData(desired) { setErr in completion?(setErr) }
            }
        }

        func deleteActivePoll(completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("polls").document("active")
            ref.delete(completion: completion)
        }

        /// Archive the active poll: copy into `polls/archived/items/{id}` and mark the original with `archivedAt`.
        /// This mirrors the incident archive pattern and prevents automatic deletion of the original document.
        func archiveActivePoll(id: String, completion: ((Error?) -> Void)? = nil) {
            let srcRef = db.collection("polls").document("active")
            // The active doc is expected to contain the poll fields; we will fetch and copy to archived/items/{id}
            srcRef.getDocument { snap, err in
                if let err = err {
                    completion?(err)
                    return
                }
                guard let data = snap?.data() else {
                    completion?(
                        NSError(
                            domain: "FirebaseManager", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Active poll not found"]))
                    return
                }
                var archived = data
                archived["archivedAt"] = Timestamp(date: Date())
                let destRef = self.db.collection("polls").document("archived").collection("items")
                    .document(id)
                destRef.setData(archived) { setErr in
                    if let setErr = setErr {
                        completion?(setErr)
                        return
                    }
                    // Mark the original active poll doc as archived (set archivedAt) but do NOT delete it.
                    srcRef.setData(["archivedAt": Timestamp(date: Date())], merge: true) {
                        markErr in
                        completion?(markErr)
                    }
                }
            }
        }

        /// Create or update an archived poll document (stored under polls/archived/items/{id}).
        func createOrUpdateArchivedPoll(_ poll: PollDTO, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("polls").document("archived").collection("items").document(
                poll.id)
            var dict: [String: Any] = [
                "id": poll.id,
                "question": poll.question,
                "options": poll.options,
                "votes": poll.votes,
                "votesByUser": poll.votesByUser ?? [:],
            ]
            if let expires = poll.expiresAt { dict["expiresAt"] = expires }
            if let created = poll.createdAt { dict["createdAt"] = created }
            ref.setData(dict, completion: completion)
        }

        /// Watch archived polls collection and deliver array of dictionaries (one per archived poll).
        func watchArchivedPolls(onUpdate: @escaping ([[String: Any]]) -> Void) {
            stopWatchingArchivedPolls()
            let ref = db.collection("polls").document("archived").collection("items").order(
                by: "createdAt", descending: true)
            archivedPollsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                let items = snap.documents.map { doc -> [String: Any] in
                    var d = doc.data()
                    // convert Firestore Timestamp to TimeInterval for consistency with other watchers
                    if let ts = d["createdAt"] as? Timestamp {
                        d["createdAt"] = ts.dateValue().timeIntervalSince1970
                    }
                    if let ts2 = d["expiresAt"] as? Timestamp {
                        d["expiresAt"] = ts2.dateValue().timeIntervalSince1970
                    }
                    return d
                }
                onUpdate(items)
            }
        }

        func stopWatchingArchivedPolls() {
            archivedPollsListener?.remove()
            archivedPollsListener = nil
        }

        /// Delete an archived poll document so it is removed for all clients.
        func deleteArchivedPoll(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("polls").document("archived").collection("items").document(id)
            ref.delete(completion: completion)
        }

        /// Vote safely using a transaction: increment target option if user hasn't voted yet.
        func voteOnActivePoll(
            userId: String, optionIndex: Int, completion: @escaping (Error?) -> Void
        ) {
            voteOnActivePollWithRetry(
                userId: userId, optionIndex: optionIndex, retryCount: 3, completion: completion)
        }

        private func voteOnActivePollWithRetry(
            userId: String, optionIndex: Int, retryCount: Int,
            completion: @escaping (Error?) -> Void
        ) {
            let ref = db.collection("polls").document("active")
            db.runTransaction(
                { (transaction, errorPointer) -> Any? in
                    print(
                        "FirebaseManager.voteOnActivePoll: starting transaction for user=\(userId) option=\(optionIndex)"
                    )
                    let snap: DocumentSnapshot
                    do {
                        snap = try transaction.getDocument(ref)
                    } catch let fetchError as NSError {
                        print(
                            "FirebaseManager.voteOnActivePoll: failed to fetch active poll doc: \(fetchError)"
                        )
                        errorPointer?.pointee = fetchError
                        return nil
                    }
                    guard let dataDict = snap.data() else {
                        print("FirebaseManager.voteOnActivePoll: active poll doc has no data")
                        let noDataError = NSError(
                            domain: "FirebaseManager", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No active poll found"])
                        errorPointer?.pointee = noDataError
                        return nil
                    }
                    guard var dto = self.pollDTO(from: dataDict) else {
                        print(
                            "FirebaseManager.voteOnActivePoll: failed to parse PollDTO from data: \(dataDict)"
                        )
                        let parseError = NSError(
                            domain: "FirebaseManager", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to parse poll data"])
                        errorPointer?.pointee = parseError
                        return nil
                    }
                    var votesByUser = dto.votesByUser ?? [:]
                    if votesByUser[userId] != nil {
                        // already voted: no-op
                        print(
                            "FirebaseManager.voteOnActivePoll: user \(userId) already voted (ignored)"
                        )
                        return nil
                    }
                    // ensure votes array length and validate option index
                    if optionIndex < 0 || optionIndex >= dto.votes.count {
                        let indexError = NSError(
                            domain: "FirebaseManager", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid option index"])
                        errorPointer?.pointee = indexError
                        return nil
                    }
                    dto.votes[optionIndex] += 1
                    votesByUser[userId] = optionIndex
                    dto.votesByUser = votesByUser
                    // write back as dictionary
                    var outDict: [String: Any] = [
                        "id": dto.id,
                        "question": dto.question,
                        "options": dto.options,
                        "votes": dto.votes,
                        "votesByUser": dto.votesByUser ?? [:],
                    ]
                    if let expires = dto.expiresAt { outDict["expiresAt"] = expires }
                    if let created = dto.createdAt { outDict["createdAt"] = created }
                    print("FirebaseManager.voteOnActivePoll: writing updated poll data: \(outDict)")
                    transaction.setData(outDict, forDocument: ref)
                    return nil
                },
                completion: { _, err in
                    if let err = err {
                        print(
                            "FirebaseManager.voteOnActivePoll: transaction completed with error: \(err)"
                        )

                        // Retry logic for transient failures
                        if retryCount > 0 && (err as NSError).domain == "FIRFirestoreErrorDomain" {
                            let retryDelay = DispatchTime.now() + 0.5  // 500ms delay
                            DispatchQueue.global().asyncAfter(deadline: retryDelay) {
                                print(
                                    "FirebaseManager.voteOnActivePoll: retrying transaction (attempts left: \(retryCount-1))"
                                )
                                self.voteOnActivePollWithRetry(
                                    userId: userId, optionIndex: optionIndex,
                                    retryCount: retryCount - 1, completion: completion)
                            }
                        } else {
                            completion(err)
                        }
                    } else {
                        print(
                            "FirebaseManager.voteOnActivePoll: transaction completed successfully for user=\(userId)"
                        )
                        completion(nil)
                    }
                })
        }

        /// Watch community messages collection and deliver array of dictionaries.
        func watchCommunityMessages(
            uploadsUID: String? = nil, onUpdate: @escaping ([[String: Any]]) -> Void
        ) {
            // Prefer explicitly-provided uploadsUID; if nil, fall back to persisted _communityUploadsUID.
            let effectiveUID =
                (uploadsUID != nil && !(uploadsUID!.isEmpty)) ? uploadsUID : _communityUploadsUID
            let ref: Query
            if let uid = effectiveUID, !uid.isEmpty {
                ref = db.collection("uploads").document(uid).collection("communityMessages").order(
                    by: "timestamp", descending: false)
            } else {
                ref = db.collection("communityMessages").order(by: "timestamp", descending: false)
            }

            let registration = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                let items = snap.documents.map { doc -> [String: Any] in
                    var d = doc.data()
                    // convert Firestore Timestamp to TimeInterval
                    if let ts = d["timestamp"] as? Timestamp {
                        d["timestamp"] = ts.dateValue().timeIntervalSince1970
                    }
                    return d
                }
                onUpdate(items)
            }
            communityMessagesListeners.append(registration)
        }

        func stopWatchingCommunityMessages() {
            for reg in communityMessagesListeners { reg.remove() }
            communityMessagesListeners.removeAll()
        }

        /// Set which uploads UID to listen to. Passing nil clears the selection and
        /// reverts to watching the top-level `communityMessages` collection.
        /// Changing the UID will stop any existing listeners so callers should re-register if needed.
        func setCommunityUploadsUID(_ uid: String?) {
            // If value didn't change, no-op
            if _communityUploadsUID == uid { return }
            // stop existing listeners
            stopWatchingCommunityMessages()
            _communityUploadsUID = uid
        }

        /// Returns whether a community messages listener is currently active.
        func isWatchingCommunityMessages() -> Bool {
            return !communityMessagesListeners.isEmpty
        }

        /// Create or update a community message document. Store imageData directly in Firestore for instant loading.
        func createOrUpdateCommunityMessage(
            _ message: CommunityMessage, completion: ((Error?) -> Void)? = nil
        ) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion?(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
                return
            }
            
            let ref = db.collection("communityMessages").document(message.id.uuidString)
            print("FirebaseManager: Writing message to communityMessages/\(message.id.uuidString)")

            var dict: [String: Any] = [
                "id": message.id.uuidString,
                "user": message.user,
                "text": message.text,
                "messageType": message.messageType.rawValue,
                "isEdited": message.isEdited,
                "userId": uid,  // Required by security rules
            ]

            dict["timestamp"] = Timestamp(date: message.timestamp)
            if let reply = message.replyTo { dict["replyTo"] = reply.uuidString }
            if let editedAt = message.editedAt { dict["editedAt"] = Timestamp(date: editedAt) }

            // Store imageData directly in Firestore for instant loading (like newsletters)
            if let imageData = message.imageData {
                dict["imageData"] = imageData.base64EncodedString()
            }
            
            // Include file/audio URLs if present (files/audio still use Storage for larger files)
            if let fileURL = message.fileURL {
                dict["fileURL"] = fileURL.absoluteString
                if let fname = message.fileName { dict["fileName"] = fname }
            }
            if let audioURL = message.audioURL {
                dict["audioURL"] = audioURL.absoluteString
                if let afn = message.audioFileName { dict["audioFileName"] = afn }
            }
            
            // Include pinned status
            dict["pinned"] = message.pinned
            if let pinnedBy = message.pinnedBy { dict["pinnedBy"] = pinnedBy }
            if let pinnedAt = message.pinnedAt { dict["pinnedAt"] = Timestamp(date: pinnedAt) }

            // Write to Firestore
            ref.setData(dict, merge: true) { err in
                completion?(err)
            }
        }

        func deleteCommunityMessage(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("communityMessages").document(id)
            // Attempt to delete any Storage objects referenced by this document (images, files, audio)
            ref.getDocument { [weak self] snap, err in
                guard let strongSelf = self else {
                    // manager gone; best-effort delete
                    ref.delete(completion: completion)
                    return
                }
                if err != nil {
                    // fallback: try delete document anyway
                    ref.delete(completion: completion)
                    return
                }
                var urlsToDelete: [String] = []
                if let d = snap?.data() {
                    if let s = d["imageURL"] as? String { urlsToDelete.append(s) }
                    if let arr = d["additionalImageURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr)
                    }
                    if let arr2 = d["imageDatasURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr2)
                    }
                    if let f = d["fileURL"] as? String { urlsToDelete.append(f) }
                    if let a = d["audioURL"] as? String { urlsToDelete.append(a) }
                }
                let group = DispatchGroup()
                // Delete by explicit URLs (if they map to Storage refs)
                for u in urlsToDelete {
                    if let storageRef = strongSelf.storageReference(fromDownloadURLString: u) {
                        group.enter()
                        storageRef.delete { _ in group.leave() }
                    }
                }

                // Also attempt to delete any uploaded files under the current user's uploads prefix and final prefix
                // Include GIF-specific paths (gifs/{messageId}/)
                let uid = Auth.auth().currentUser?.uid ?? "anon"
                let possiblePrefixes = [
                    "uploads/\(uid)/communityMessages/\(id)", 
                    "final/communityMessages/\(id)",
                    "uploads/\(uid)/communityMessages/gifs/\(id)",
                    "final/communityMessages/gifs/\(id)",
                    "thumbs/communityMessages/gifs/\(id)",
                ]
                for pref in possiblePrefixes {
                    let r = strongSelf.storage.reference().child(pref)
                    group.enter()
                    r.listAll { res, listErr in
                        if let items = res?.items {
                            let inner = DispatchGroup()
                            for it in items {
                                inner.enter()
                                it.delete { _ in inner.leave() }
                            }
                            inner.notify(queue: .main) { group.leave() }
                        } else {
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    // Now delete the Firestore document
                    ref.delete(completion: completion)
                }
            }
        }

        // MARK: - Newsletters
        private var newslettersListener: ListenerRegistration?

        private func newsletterFrom(data: [String: Any]) -> Newsletter? {
            guard let idStr = data["id"] as? String,
                let id = UUID(uuidString: idStr),
                let title = data["title"] as? String,
                let summary = data["summary"] as? String,
                let content = data["content"] as? String,
                let author = data["author"] as? String,
                let authorEmail = data["authorEmail"] as? String,
                let categoryRaw = data["category"] as? String,
                let category = NewsletterCategory(rawValue: categoryRaw)
            else {
                return nil
            }

            let date: Date
            if let ts = data["date"] as? Timestamp {
                date = ts.dateValue()
            } else if let timeInterval = data["date"] as? TimeInterval {
                date = Date(timeIntervalSince1970: timeInterval)
            } else {
                date = Date()
            }

            let isPinned = data["isPinned"] as? Bool ?? false
            let readCount = data["readCount"] as? Int ?? 0
            let tags = data["tags"] as? [String] ?? []
            let isPublished = data["isPublished"] as? Bool ?? true
            let requiresApproval = data["requiresApproval"] as? Bool ?? false

            var imageData: Data? = nil
            if let b64 = data["imageData"] as? String, let d = Data(base64Encoded: b64) {
                imageData = d
            }

            var fileURL: URL? = nil
            var fileData: Data? = nil
            var fileName: String? = nil
            
            fileName = data["fileName"] as? String
            
            // Hybrid approach: Check for file in multiple storage methods (WhatsApp-style)
            
            // Method 1: Firebase Storage URL (PREFERRED for large files)
            #if canImport(FirebaseStorage)
            if let storageURLString = data["fileStorageURL"] as? String {
                print("☁️ FirebaseManager: Found file in Firebase Storage: \(fileName ?? "unknown")")
                print("   - Storage URL: \(storageURLString)")
                
                // Download file from Storage to local cache on-demand
                if let fileName = fileName {
                    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let cachedFile = cacheDir.appendingPathComponent("newsletters/\(id.uuidString)/\(fileName)")
                    
                    // Check if already cached
                    if FileManager.default.fileExists(atPath: cachedFile.path) {
                        fileURL = cachedFile
                        print("✅ FirebaseManager: Using cached file at: \(cachedFile.path)")
                    } else {
                        // Download from Storage in background
                        print("⬇️ FirebaseManager: Downloading file from Storage to cache...")
                        print("   - Target path: \(cachedFile.path)")
                        if let storageRef = self.storageReference(fromDownloadURLString: storageURLString) {
                            // Create cache directory if needed
                            try? FileManager.default.createDirectory(at: cachedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                            
                            // Trigger async download (UI will monitor for completion)
                            storageRef.write(toFile: cachedFile) { url, error in
                                if let error = error {
                                    print("❌ FirebaseManager: Failed to download file: \(error.localizedDescription)")
                                } else {
                                    print("✅ FirebaseManager: File downloaded to cache: \(cachedFile.path)")
                                    // Post notification for UI update
                                    NotificationCenter.default.post(name: NSNotification.Name("NewsletterFileDownloaded"), object: nil, userInfo: ["newsletterId": id.uuidString])
                                }
                            }
                        } else {
                            print("❌ FirebaseManager: Failed to create storage reference from URL")
                        }
                        // DON'T set fileURL yet - file doesn't exist until download completes
                        // UI will receive notification when ready
                        print("⏳ FirebaseManager: Download in progress, fileURL will be set after completion")
                    }
                }
            }
            #endif
            
            // Method 2: Direct Firestore base64 data (for small files)
            if fileURL == nil, let fileDataString = data["fileData"] as? String,
               let decodedData = Data(base64Encoded: fileDataString) {
                fileData = decodedData
                let fileSize = data["fileSize"] as? Int ?? decodedData.count
                print("📦 FirebaseManager: Found file data in Firestore (\(fileSize) bytes)")
                
                // Create temporary file for immediate access
                if let fileName = fileName {
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempFile = tempDir.appendingPathComponent("newsletter_\(id.uuidString)_\(fileName)")
                    
                    do {
                        try decodedData.write(to: tempFile)
                        fileURL = tempFile
                        print("✅ FirebaseManager: Created temp file from Firestore data: \(tempFile.path)")
                    } catch {
                        print("❌ FirebaseManager: Error creating temp file: \(error)")
                    }
                }
            }
            // Method 3: Legacy fileURL (backwards compatibility)
            else if fileURL == nil, let fileURLString = data["fileURL"] as? String, let url = URL(string: fileURLString) {
                fileURL = url
                print("⚠️ FirebaseManager: Found legacy fileURL (may not work on other devices): \(url.lastPathComponent)")
            }
            
            if fileURL == nil && fileData == nil {
                print("ℹ️ FirebaseManager: No file attachment found for newsletter")
            }


            var n = Newsletter(
                id: id, title: title, summary: summary, content: content, author: author,
                authorEmail: authorEmail, category: category)
            n.date = date
            n.isPinned = isPinned
            n.readCount = readCount
            n.tags = tags
            n.isPublished = isPublished
            n.requiresApproval = requiresApproval
            n.imageData = imageData
            n.fileURL = fileURL
            n.fileData = fileData
            n.fileName = fileName
            n.isFormEnabled = data["isFormEnabled"] as? Bool ?? false
            n.allowPublicSubmissionView = data["allowPublicSubmissionView"] as? Bool ?? false
            // Parse form fields
            if let fieldsArray = data["formFields"] as? [[String: Any]] {
                var fields: [NewsletterFormField] = []
                for fieldDict in fieldsArray {
                    guard let idStr = fieldDict["id"] as? String,
                          let fieldId = UUID(uuidString: idStr),
                          let label = fieldDict["label"] as? String,
                          let typeStr = fieldDict["fieldType"] as? String,
                          let fieldType = NewsletterFormFieldType(rawValue: typeStr)
                    else { continue }
                    
                    let field = NewsletterFormField(
                        id: fieldId,
                        label: label,
                        fieldType: fieldType,
                        isRequired: fieldDict["isRequired"] as? Bool ?? false,
                        placeholder: fieldDict["placeholder"] as? String ?? "",
                        options: fieldDict["options"] as? [String] ?? [],
                        helpText: fieldDict["helpText"] as? String ?? ""
                    )
                    fields.append(field)
                }
                n.formFields = fields
            }
            return n
        }

        /// Watch the newsletters collection and deliver Newsletter models in real-time.
        func watchNewsletters(onUpdate: @escaping ([Newsletter]) -> Void) {
            stopWatchingNewsletters()
            let ref = db.collection("newsletters").order(by: "date", descending: true)
            newslettersListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [Newsletter] = []
                for doc in snap.documents {
                    let d = doc.data()
                    if let n = self.newsletterFrom(data: d) {
                        items.append(n)
                    }
                }
                onUpdate(items)
            }
        }

        func stopWatchingNewsletters() {
            newslettersListener?.remove()
            newslettersListener = nil
        }

        func createOrUpdateNewsletter(
            _ newsletter: Newsletter, completion: ((Error?) -> Void)? = nil
        ) {
            print("🔵 FirebaseManager: createOrUpdateNewsletter called for: \(newsletter.title)")
            #if canImport(FirebaseStorage)
            print("   ✅ FirebaseStorage is AVAILABLE")
            #else
            print("   ❌ FirebaseStorage is NOT AVAILABLE")
            #endif
            
            let ref = db.collection("newsletters").document(newsletter.id.uuidString)
            var dict: [String: Any] = [
                "id": newsletter.id.uuidString,
                "title": newsletter.title,
                "summary": newsletter.summary,
                "content": newsletter.content,
                "author": newsletter.author,
                "authorEmail": newsletter.authorEmail,
                "category": newsletter.category.rawValue,
                "isPinned": newsletter.isPinned,
                "readCount": newsletter.readCount,
                "tags": newsletter.tags,
                "isPublished": newsletter.isPublished,
                "requiresApproval": newsletter.requiresApproval,
                "isFormEnabled": newsletter.isFormEnabled,
                "allowPublicSubmissionView": newsletter.allowPublicSubmissionView,
            ]
            // date as Timestamp
            dict["date"] = Timestamp(date: newsletter.date)
            if let data = newsletter.imageData {
                dict["imageData"] = data.base64EncodedString()
            }
            
            // Serialize form fields
            if !newsletter.formFields.isEmpty {
                var fieldsArray: [[String: Any]] = []
                for field in newsletter.formFields {
                    let fieldDict: [String: Any] = [
                        "id": field.id.uuidString,
                        "label": field.label,
                        "fieldType": field.fieldType.rawValue,
                        "isRequired": field.isRequired,
                        "placeholder": field.placeholder,
                        "options": field.options,
                        "helpText": field.helpText
                    ]
                    fieldsArray.append(fieldDict)
                }
                dict["formFields"] = fieldsArray
            }
            
            // Handle file attachment using hybrid approach (like WhatsApp):
            // 1. Preview image stored in Firestore (imageData - already handled above)
            // 2. Full PDF uploaded to Firebase Storage and URL stored in Firestore
            #if canImport(FirebaseStorage)
            if let fileData = newsletter.fileData, let fileName = newsletter.fileName {
                let fileSizeInBytes = fileData.count
                let fileSizeInKB = Double(fileSizeInBytes) / 1024.0
                let fileSizeInMB = fileSizeInKB / 1024.0
                let threshold = 1024 * 1024 // 1MB
                
                print("📄 FirebaseManager: Processing newsletter file attachment:")
                print("   - File name: \(fileName)")
                print("   - File size: \(fileSizeInBytes) bytes (\(String(format: "%.2f", fileSizeInKB)) KB / \(String(format: "%.2f", fileSizeInMB)) MB)")
                print("   - Threshold: \(threshold) bytes (1.00 MB)")
                print("   - Will use: \(fileSizeInBytes <= threshold ? "Firestore (base64)" : "Firebase Storage")")
                
                // For small files (<1MB), store directly in Firestore as base64
                if fileSizeInBytes <= threshold {
                    dict["fileData"] = fileData.base64EncodedString()
                    dict["fileName"] = fileName
                    dict["fileSize"] = fileSizeInBytes
                    print("📦 FirebaseManager: Storing small file directly in Firestore (\(fileSizeInBytes) bytes)")
                }
                // For larger files, upload to Firebase Storage (WhatsApp-style)
                else {
                    print("☁️ FirebaseManager: File EXCEEDS 1MB threshold, uploading to Firebase Storage...")
                    print("   - File size: \(fileSizeInBytes) bytes (\(String(format: "%.2f", fileSizeInMB)) MB)")
                    let storagePath = "newsletters/\(newsletter.id.uuidString)/\(fileName)"
                    print("   - Storage path: \(storagePath)")
                    print("   - Starting upload with retry logic (3 attempts)...")
                    
                    // Upload with retry logic (3 attempts with exponential backoff)
                    uploadDataWithRetry(fileData, path: storagePath, retries: 3) { url, error in
                        if let error = error {
                            print("❌ FirebaseManager: Failed to upload file to Storage after retries: \(error.localizedDescription)")
                            // Fallback: Store in Firestore if file is now small enough after all retries failed
                            if fileData.count <= 1024 * 1024 { // Allow up to 1MB as fallback
                                dict["fileData"] = fileData.base64EncodedString()
                                dict["fileName"] = fileName
                                dict["fileSize"] = fileData.count
                                print("⚠️ FirebaseManager: Falling back to Firestore storage for failed upload")
                            }
                        } else if let url = url {
                            dict["fileStorageURL"] = url.absoluteString
                            dict["fileName"] = fileName
                            dict["fileSize"] = fileData.count
                            print("✅ FirebaseManager: Successfully uploaded file to Storage: \(url.absoluteString)")
                        }
                        
                        // Save newsletter to Firestore after upload completes
                        print("FirebaseManager: Saving newsletter to Firestore: \(newsletter.title)")
                        ref.setData(dict) { err in
                            if let err = err {
                                print("FirebaseManager: Error saving newsletter to Firestore: \(err)")
                            } else {
                                print("FirebaseManager: Successfully saved newsletter to Firestore: \(newsletter.title)")
                            }
                            completion?(err)
                        }
                    }
                    return // Exit early, completion handled in upload callback
                }
            }
            #else
            // Fallback when Firebase Storage is not available
            if let fileData = newsletter.fileData, let fileName = newsletter.fileName {
                if fileData.count <= 1024 * 1024 {
                    dict["fileData"] = fileData.base64EncodedString()
                    dict["fileName"] = fileName
                    dict["fileSize"] = fileData.count
                }
            }
            #endif
            
            // Save newsletter to Firestore (only for small files or no attachment)
            // Large files save after upload completes in the callback above
            print("FirebaseManager: Saving newsletter to Firestore: \(newsletter.title)")
            ref.setData(dict) { err in
                if let err = err {
                    print("FirebaseManager: Error saving newsletter to Firestore: \(err)")
                } else {
                    print("FirebaseManager: Successfully saved newsletter to Firestore: \(newsletter.title)")
                }
                completion?(err)
            }
        }

        func deleteNewsletter(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("newsletters").document(id)
            
            #if canImport(FirebaseStorage)
            // First, check if there are Storage files to clean up
            ref.getDocument { snap, err in
                var storageCleanupComplete = false
                
                if let data = snap?.data() {
                    // Method 1: Delete using fileStorageURL if available
                    if let storageURLString = data["fileStorageURL"] as? String {
                        print("🗑️ FirebaseManager: Deleting newsletter file from Firebase Storage using URL...")
                        if let storageRef = self.storageReference(fromDownloadURLString: storageURLString) {
                            storageRef.delete { error in
                                if let error = error {
                                    print("⚠️ FirebaseManager: Failed to delete Storage file via URL: \(error.localizedDescription)")
                                } else {
                                    print("✅ FirebaseManager: Deleted Storage file via URL")
                                }
                                storageCleanupComplete = true
                            }
                        } else {
                            print("⚠️ FirebaseManager: Could not parse storage URL, will try path-based deletion")
                        }
                    }
                    
                    // Method 2: Delete entire newsletters/{id}/ folder to catch all files
                    let newsletterStoragePath = "newsletters/\(id)"
                    print("🗑️ FirebaseManager: Deleting all files in Storage path: \(newsletterStoragePath)")
                    
                    let folderRef = self.storage.reference().child(newsletterStoragePath)
                    folderRef.listAll { result, error in
                        if let error = error {
                            print("⚠️ FirebaseManager: Error listing Storage files: \(error.localizedDescription)")
                        } else if let items = result?.items {
                            print("📂 FirebaseManager: Found \(items.count) files to delete in Storage")
                            for item in items {
                                item.delete { deleteError in
                                    if let deleteError = deleteError {
                                        print("⚠️ FirebaseManager: Failed to delete \(item.name): \(deleteError.localizedDescription)")
                                    } else {
                                        print("✅ FirebaseManager: Deleted Storage file: \(item.name)")
                                    }
                                }
                            }
                        } else {
                            print("ℹ️ FirebaseManager: No files found in Storage path: \(newsletterStoragePath)")
                        }
                    }
                    
                    // Also clean up local cache
                    if let fileName = data["fileName"] as? String {
                        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        let cachedFile = cacheDir.appendingPathComponent("newsletters/\(id)/\(fileName)")
                        try? FileManager.default.removeItem(at: cachedFile)
                        print("🗑️ FirebaseManager: Cleaned up local cache for: \(fileName)")
                    }
                    
                    // Clean up entire cache folder for this newsletter
                    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let cacheFolderPath = cacheDir.appendingPathComponent("newsletters/\(id)")
                    try? FileManager.default.removeItem(at: cacheFolderPath)
                    print("🗑️ FirebaseManager: Cleaned up local cache folder")
                }
                
                // Delete the Firestore document
                ref.delete { err in
                    if let err = err {
                        print("❌ FirebaseManager: Error deleting newsletter from Firestore: \(err)")
                    } else {
                        print("✅ FirebaseManager: Successfully deleted newsletter from Firestore: \(id)")
                    }
                    completion?(err)
                }
            }
            #else
            // Fallback: just delete the document
            ref.delete { err in
                if let err = err {
                    print("❌ FirebaseManager: Error deleting newsletter from Firestore: \(err)")
                } else {
                    print("✅ FirebaseManager: Successfully deleted newsletter from Firestore: \(id)")
                }
                completion?(err)
            }
            #endif
        }
        
        // MARK: - Cache Management
        
        /// Clean up newsletter cache based on size limits and file age
        func cleanupNewsletterCache() {
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("newsletters")
            
            guard FileManager.default.fileExists(atPath: cacheDir.path) else {
                print("ℹ️ FirebaseManager: No cache directory to clean")
                return
            }
            
            do {
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles)
                
                var totalSize = 0
                var filesToDelete: [(url: URL, date: Date)] = []
                let now = Date()
                let expirationDate = Calendar.current.date(byAdding: .day, value: -cacheExpirationDays, to: now)!
                
                // Collect file info
                for file in files {
                    let attributes = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    if let size = attributes.fileSize {
                        totalSize += size
                    }
                    
                    // Mark expired files for deletion
                    if let modDate = attributes.contentModificationDate, modDate < expirationDate {
                        filesToDelete.append((url: file, date: modDate))
                        print("🗑️ FirebaseManager: Marking expired file for deletion: \(file.lastPathComponent)")
                    }
                }
                
                // Delete expired files
                for item in filesToDelete {
                    try? fileManager.removeItem(at: item.url)
                    if let attrs = try? item.url.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                        totalSize -= size
                    }
                }
                
                print("📊 FirebaseManager: Cache size after expiration cleanup: \(totalSize / 1024 / 1024)MB / \(maxCacheSize / 1024 / 1024)MB")
                
                // If still over size limit, delete oldest files first
                if totalSize > maxCacheSize {
                    let allFiles = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles)
                    
                    var filesWithDates: [(url: URL, date: Date, size: Int)] = []
                    for file in allFiles {
                        let attrs = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        if let modDate = attrs.contentModificationDate, let size = attrs.fileSize {
                            filesWithDates.append((url: file, date: modDate, size: size))
                        }
                    }
                    
                    // Sort by date (oldest first)
                    filesWithDates.sort { $0.date < $1.date }
                    
                    // Delete oldest files until under limit
                    var currentSize = totalSize
                    for fileInfo in filesWithDates {
                        if currentSize <= maxCacheSize { break }
                        try? fileManager.removeItem(at: fileInfo.url)
                        currentSize -= fileInfo.size
                        print("🗑️ FirebaseManager: Deleted old cache file to free space: \(fileInfo.url.lastPathComponent)")
                    }
                    
                    print("✅ FirebaseManager: Cache cleanup complete. Final size: \(currentSize / 1024 / 1024)MB")
                }
            } catch {
                print("❌ FirebaseManager: Error cleaning cache: \(error)")
            }
        }

        // MARK: - Newsletter Form Submissions
        private var newsletterSubmissionsListener: ListenerRegistration?

        func watchNewsletterSubmissions(onUpdate: @escaping ([NewsletterFormSubmission]) -> Void) {
            stopWatchingNewsletterSubmissions()
            let ref = db.collection("newsletterSubmissions").order(by: "submissionDate", descending: true)
            newsletterSubmissionsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [NewsletterFormSubmission] = []
                for doc in snap.documents {
                    let d = doc.data()
                    if let submission = self.newsletterSubmissionFrom(data: d) {
                        items.append(submission)
                    }
                }
                onUpdate(items)
            }
        }

        func stopWatchingNewsletterSubmissions() {
            newsletterSubmissionsListener?.remove()
            newsletterSubmissionsListener = nil
        }

        private func newsletterSubmissionFrom(data: [String: Any]) -> NewsletterFormSubmission? {
            guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
                  let newsletterIdStr = data["newsletterId"] as? String, let newsletterId = UUID(uuidString: newsletterIdStr),
                  let submitterId = data["submitterId"] as? String,
                  let submitterName = data["submitterName"] as? String,
                  let submitterEmail = data["submitterEmail"] as? String,
                  let submissionDateTS = data["submissionDate"] as? Timestamp
            else { return nil }
            
            let submissionDate = submissionDateTS.dateValue()
            let responsesDict = data["responses"] as? [String: String] ?? [:]
            var responses: [UUID: String] = [:]
            for (key, value) in responsesDict {
                if let fieldId = UUID(uuidString: key) {
                    responses[fieldId] = value
                }
            }
            
            let statusStr = data["status"] as? String ?? NewsletterFormSubmission.SubmissionStatus.pending.rawValue
            let status = NewsletterFormSubmission.SubmissionStatus(rawValue: statusStr) ?? .pending
            
            var submission = NewsletterFormSubmission(
                id: id,
                newsletterId: newsletterId,
                submitterId: submitterId,
                submitterName: submitterName,
                submitterEmail: submitterEmail,
                responses: responses,
                allowPublicSubmissionView: data["allowPublicSubmissionView"] as? Bool ?? false
            )
            submission.submissionDate = submissionDate
            submission.status = status
            return submission
        }

        func createOrUpdateNewsletterSubmission(_ submission: NewsletterFormSubmission, newsletter: Newsletter? = nil, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("newsletterSubmissions").document(submission.id.uuidString)
            
            // Convert UUID keys to strings for Firestore
            var responsesDict: [String: String] = [:]
            for (fieldId, response) in submission.responses {
                responsesDict[fieldId.uuidString] = response
            }
            
            var dict: [String: Any] = [
                "id": submission.id.uuidString,
                "newsletterId": submission.newsletterId.uuidString,
                "submitterId": submission.submitterId,
                "submitterName": submission.submitterName,
                "submitterEmail": submission.submitterEmail,
                "submissionDate": Timestamp(date: submission.submissionDate),
                "responses": responsesDict,
                "status": submission.status.rawValue,
                "allowPublicSubmissionView": submission.allowPublicSubmissionView
            ]
            
            // Update from newsletter if provided (for initial creation)
            if let newsletter = newsletter {
                dict["allowPublicSubmissionView"] = newsletter.allowPublicSubmissionView
            }
            
            ref.setData(dict) { err in
                completion?(err)
            }
        }

        func deleteNewsletterSubmission(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("newsletterSubmissions").document(id)
            ref.delete(completion: completion)
        }

        // MARK: - Incidents (Active & Archived)
        private var incidentsListener: ListenerRegistration?
        private var archivedIncidentsListener: ListenerRegistration?

        /// Lightweight Incident model used for Firestore mapping
        struct Incident: Codable, Identifiable {
            let id: UUID
            var title: String
            var description: String?
            var date: Date
            var showOnHome: Bool
            var creatorName: String?
            var creatorSurname: String?
            var archivedAt: Date?
            // New fields: incident type (fire/emergency/medical/etc), human-readable location,
            // contact details for responders, and optional metadata map.
            var incidentType: String?
            var location: String?
            var contactName: String?
            var contactPhone: String?
            var metadata: [String: String]?
            var imageURL: URL?
            var imageData: Data?
            var imageLocalPath: String?

            // Custom coding keys to handle optional fields properly
            enum CodingKeys: String, CodingKey {
                case id, title, description, date, showOnHome
                case creatorName, creatorSurname, archivedAt
                case incidentType, location, contactName, contactPhone, metadata
                case imageURL, imageLocalPath
                // Note: imageData is intentionally excluded from Codable as it's only used during uploads
            }

            // Custom decoder that excludes imageData (binary data shouldn't be encoded in local storage)
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(UUID.self, forKey: .id)
                title = try container.decode(String.self, forKey: .title)
                description = try container.decodeIfPresent(String.self, forKey: .description)
                date = try container.decode(Date.self, forKey: .date)
                showOnHome = try container.decode(Bool.self, forKey: .showOnHome)
                creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
                creatorSurname = try container.decodeIfPresent(String.self, forKey: .creatorSurname)
                archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
                incidentType = try container.decodeIfPresent(String.self, forKey: .incidentType)
                location = try container.decodeIfPresent(String.self, forKey: .location)
                contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
                contactPhone = try container.decodeIfPresent(String.self, forKey: .contactPhone)
                metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
                imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
                imageLocalPath = try container.decodeIfPresent(String.self, forKey: .imageLocalPath)
                // imageData is always nil when decoding from storage
                imageData = nil
            }

            // Custom encoder that excludes imageData
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(date, forKey: .date)
                try container.encode(showOnHome, forKey: .showOnHome)
                try container.encodeIfPresent(creatorName, forKey: .creatorName)
                try container.encodeIfPresent(creatorSurname, forKey: .creatorSurname)
                try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
                try container.encodeIfPresent(incidentType, forKey: .incidentType)
                try container.encodeIfPresent(location, forKey: .location)
                try container.encodeIfPresent(contactName, forKey: .contactName)
                try container.encodeIfPresent(contactPhone, forKey: .contactPhone)
                try container.encodeIfPresent(metadata, forKey: .metadata)
                try container.encodeIfPresent(imageURL, forKey: .imageURL)
                try container.encodeIfPresent(imageLocalPath, forKey: .imageLocalPath)
                // imageData is intentionally not encoded
            }

            // Standard initializer for creating new incidents
            init(
                id: UUID, title: String, description: String?, date: Date, showOnHome: Bool,
                creatorName: String?, creatorSurname: String?, archivedAt: Date?,
                incidentType: String? = nil, location: String? = nil,
                contactName: String? = nil, contactPhone: String? = nil,
                metadata: [String: String]? = nil,
                imageURL: URL?, imageData: Data?, imageLocalPath: String?
            ) {
                self.id = id
                self.title = title
                self.description = description
                self.date = date
                self.showOnHome = showOnHome
                self.creatorName = creatorName
                self.creatorSurname = creatorSurname
                self.archivedAt = archivedAt
                self.incidentType = incidentType
                self.location = location
                self.contactName = contactName
                self.contactPhone = contactPhone
                self.metadata = metadata
                self.imageURL = imageURL
                self.imageData = imageData
                self.imageLocalPath = imageLocalPath
            }
        }

        private func incidentFrom(data: [String: Any]) -> Incident? {
            guard let idStr = data["id"] as? String,
                let id = UUID(uuidString: idStr),
                let title = data["title"] as? String
            else {
                print(
                    "FirebaseManager: Failed to parse basic incident fields. Available keys: \(data.keys)"
                )
                if let idStr = data["id"] as? String {
                    print(
                        "FirebaseManager: ID string '\(idStr)' valid UUID: \(UUID(uuidString: idStr) != nil)"
                    )
                }
                return nil
            }

            let date: Date
            if let ts = data["date"] as? Timestamp {
                date = ts.dateValue()
            } else if let ti = data["date"] as? TimeInterval {
                date = Date(timeIntervalSince1970: ti)
            } else {
                print("FirebaseManager: No valid date found for incident '\(title)'")
                date = Date()
            }

            let description = data["description"] as? String
            let showOnHome = data["showOnHome"] as? Bool ?? false
            let creatorName = data["creatorName"] as? String
            let creatorSurname = data["creatorSurname"] as? String
            var archivedAt: Date? = nil
            if let a = data["archivedAt"] as? Timestamp { archivedAt = a.dateValue() }

            // Parse imageData from base64 (instant loading like newsletters)
            var imageData: Data? = nil
            if let b64 = data["imageData"] as? String {
                if let d = Data(base64Encoded: b64) {
                    imageData = d
                    print("✅ FirebaseManager: Decoded imageData for incident '\(title)' (\(d.count) bytes from \(b64.count) base64 chars)")
                } else {
                    print("❌ FirebaseManager: Failed to decode base64 imageData for incident '\(title)'")
                }
            } else {
                print("ℹ️ FirebaseManager: No imageData field found for incident '\(title)'")
            }

            var imageURL: URL? = nil
            if let imageURLString = data["imageURL"] as? String {
                imageURL = URL(string: imageURLString)
            }

            // parse extended fields
            let incidentType = data["incidentType"] as? String
            let location = data["location"] as? String
            let contactName = data["contactName"] as? String
            let contactPhone = data["contactPhone"] as? String
            var metadata: [String: String]? = nil
            if let rawMeta = data["metadata"] as? [String: Any] {
                var m: [String: String] = [:]
                for (k, v) in rawMeta {
                    if let s = v as? String { m[k] = s } else { m[k] = String(describing: v) }
                }
                metadata = m
            }

            return Incident(
                id: id, title: title, description: description, date: date, showOnHome: showOnHome,
                creatorName: creatorName, creatorSurname: creatorSurname, archivedAt: archivedAt,
                incidentType: incidentType, location: location, contactName: contactName,
                contactPhone: contactPhone, metadata: metadata, imageURL: imageURL, imageData: imageData,
                imageLocalPath: nil)
        }

        /// Watch the active incidents collection and deliver Incident models in real-time.
        func watchIncidents(onUpdate: @escaping ([Incident]) -> Void) {
            stopWatchingIncidents()
            let ref = db.collection("incidents").order(by: "date", descending: true)
            incidentsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [Incident] = []
                for doc in snap.documents {
                    let d = doc.data()
                    if let i = self.incidentFrom(data: d) { items.append(i) }
                }
                onUpdate(items)
            }
        }

        func stopWatchingIncidents() {
            incidentsListener?.remove()
            incidentsListener = nil
        }

        /// Create or update an incident document in Firestore with image upload support.
        func createOrUpdateIncident(
            _ incident: Incident, completion: ((Error?, String?) -> Void)? = nil
        ) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion?(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
                return
            }
            
            print("📝 FirebaseManager: Creating incident '\(incident.title)' with imageData: \(incident.imageData != nil ? "✅ YES (\(incident.imageData!.count) bytes)" : "❌ NO")")
            
            let ref = db.collection("incidents").document(incident.id.uuidString)
            var dict: [String: Any] = [
                "id": incident.id.uuidString,
                "title": incident.title,
                "description": incident.description ?? "",
                "showOnHome": incident.showOnHome,
                "reporterId": uid,  // Required by security rules
            ]
            // include extended incident details when available
            if let t = incident.incidentType { dict["incidentType"] = t }
            if let loc = incident.location { dict["location"] = loc }
            if let cn = incident.contactName { dict["contactName"] = cn }
            if let cp = incident.contactPhone { dict["contactPhone"] = cp }
            if let md = incident.metadata { dict["metadata"] = md }
            dict["date"] = Timestamp(date: incident.date)
            if let name = incident.creatorName { dict["creatorName"] = name }
            if let s = incident.creatorSurname { dict["creatorSurname"] = s }

            // Store imageData directly in Firestore for instant loading (like newsletters)
            if let imageData = incident.imageData {
                let base64String = imageData.base64EncodedString()
                dict["imageData"] = base64String
                print("✅ FirebaseManager: Encoded imageData to base64 (\(base64String.count) characters)")
            } else {
                print("⚠️ FirebaseManager: No imageData to store")
            }

            // Write to Firestore
            ref.setData(dict, merge: true) { err in
                if let err = err {
                    print("❌ FirebaseManager: Failed to write incident: \(err.localizedDescription)")
                } else {
                    print("✅ FirebaseManager: Successfully wrote incident '\(incident.title)' to Firestore")
                }
                completion?(err, nil)
            }
        }

        /// Archive an active incident: copy into `archivedIncidents` with `archivedAt` metadata and remove the original.
        func archiveIncident(id: String, completion: ((Error?) -> Void)? = nil) {
            let srcRef = db.collection("incidents").document(id)
            srcRef.getDocument { snap, err in
                if let err = err {
                    completion?(err)
                    return
                }
                guard let data = snap?.data() else {
                    completion?(
                        NSError(
                            domain: "FirebaseManager", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Incident not found"]))
                    return
                }
                var archived = data
                // Mark archived timestamp on the archived copy metadata
                archived["archivedAt"] = Timestamp(date: Date())
                let destRef = self.db.collection("archivedIncidents").document(id)
                // Write an archived copy for archive listings, then delete the original so it no longer
                // appears in the active `incidents` collection.
                destRef.setData(archived) { setErr in
                    if let setErr = setErr {
                        completion?(setErr)
                        return
                    }
                    // Successfully wrote archived copy. Now remove the original incident document.
                    srcRef.delete { delErr in
                        if let delErr = delErr {
                            // If deletion fails, surface error to caller so the UI can retry or notify the user.
                            completion?(delErr)
                        } else {
                            completion?(nil)
                        }
                    }
                }
            }
        }

        /// Archive a LocalEvent by converting it to an incident and calling the ID-based archive method
        func archiveIncident(_ event: LocalEvent, completion: ((Error?) -> Void)? = nil) {
            // Use the existing ID-based method
            archiveIncident(id: event.id.uuidString, completion: completion)
        }

        /// Restore an archived incident back to the active `incidents` collection by matching
        /// on title and date. Many clients only store a pipe-delimited representation locally
        /// (without the Firestore doc id), so this helper attempts to find the archived
        /// document and move it back into `incidents`.
        func restoreArchivedIncident(
            matchingTitle title: String, date: Date, description: String?,
            completion: ((Error?) -> Void)? = nil
        ) {
            // Query archivedIncidents for a document matching the title and date
            let ref = db.collection("archivedIncidents")
            let ts = Timestamp(date: date)
            print(
                "FirebaseManager: Searching for archived incident with title='\(title)' and date=\(date)"
            )

            // First, try exact match by title and date
            ref.whereField("title", isEqualTo: title).whereField("date", isEqualTo: ts).getDocuments
            { snap, err in
                if let err = err {
                    print("FirebaseManager: Error querying archived incidents: \(err)")
                    completion?(err)
                    return
                }

                if let docs = snap?.documents, !docs.isEmpty {
                    print(
                        "FirebaseManager: Found \(docs.count) matching archived incidents with exact title+date match"
                    )
                    self.restoreDocument(docs[0], completion: completion)
                    return
                }

                print("FirebaseManager: No exact match found, trying title-only query")
                // Try a fallback query by title only
                ref.whereField("title", isEqualTo: title).getDocuments {
                    fallbackSnap, fallbackErr in
                    if let fallbackErr = fallbackErr {
                        print("FirebaseManager: Fallback query also failed: \(fallbackErr)")
                        completion?(
                            NSError(
                                domain: "FirebaseManager", code: -404,
                                userInfo: [NSLocalizedDescriptionKey: "Archived incident not found"]
                            ))
                        return
                    }

                    guard let fallbackDocs = fallbackSnap?.documents, !fallbackDocs.isEmpty else {
                        print(
                            "FirebaseManager: No archived incident found even with title-only fallback"
                        )
                        // Try one more fallback - search by description if available
                        if let desc = description, !desc.isEmpty {
                            print("FirebaseManager: Trying description-based search as last resort")
                            ref.whereField("description", isEqualTo: desc).getDocuments {
                                descSnap, descErr in
                                if let descErr = descErr {
                                    print("FirebaseManager: Description query failed: \(descErr)")
                                    completion?(
                                        NSError(
                                            domain: "FirebaseManager", code: -404,
                                            userInfo: [
                                                NSLocalizedDescriptionKey:
                                                    "Archived incident not found with any search method"
                                            ]))
                                    return
                                }

                                if let descDocs = descSnap?.documents, !descDocs.isEmpty {
                                    print(
                                        "FirebaseManager: Found \(descDocs.count) incidents with matching description"
                                    )
                                    self.restoreDocument(descDocs[0], completion: completion)
                                } else {
                                    completion?(
                                        NSError(
                                            domain: "FirebaseManager", code: -404,
                                            userInfo: [
                                                NSLocalizedDescriptionKey:
                                                    "Archived incident not found"
                                            ]))
                                }
                            }
                        } else {
                            completion?(
                                NSError(
                                    domain: "FirebaseManager", code: -404,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Archived incident not found"
                                    ]))
                        }
                        return
                    }

                    print(
                        "FirebaseManager: Found \(fallbackDocs.count) incidents with matching title (using fallback)"
                    )
                    // If multiple matches, prefer the one with closest date
                    let sortedDocs = fallbackDocs.sorted { doc1, doc2 in
                        let date1 =
                            (doc1.data()["date"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        let date2 =
                            (doc2.data()["date"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        return abs(date1.timeIntervalSince(date))
                            < abs(date2.timeIntervalSince(date))
                    }
                    self.restoreDocument(sortedDocs[0], completion: completion)
                }
            }
        }

        private func restoreDocument(_ doc: DocumentSnapshot, completion: ((Error?) -> Void)?) {
            guard var data = doc.data() else {
                print("FirebaseManager: Cannot restore document - no data found")
                completion?(
                    NSError(
                        domain: "FirebaseManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No data found in document"]))
                return
            }
            print(
                "FirebaseManager: Restoring incident with incidentType='\(data["incidentType"] as? String ?? "nil")'"
            )
            // Remove archivedAt metadata when restoring
            data.removeValue(forKey: "archivedAt")
            let id = doc.documentID
            let destRef = self.db.collection("incidents").document(id)

            // Write (or overwrite) the active incident document and clear its archivedAt flag
            destRef.setData(data) { setErr in
                if let setErr = setErr {
                    print(
                        "FirebaseManager: Failed to restore incident to active collection: \(setErr)"
                    )
                    completion?(setErr)
                    return
                }
                print("FirebaseManager: Successfully wrote incident back to active collection")
                // Delete the archived copy since we've successfully restored it to active incidents
                doc.reference.delete { clearErr in
                    if let clearErr = clearErr {
                        print(
                            "FirebaseManager: Warning - restored incident but failed to delete archived copy: \(clearErr)"
                        )
                    } else {
                        print(
                            "FirebaseManager: Successfully restored incident and removed archived copy"
                        )
                    }
                    completion?(clearErr)
                }
            }
        }

        /// Alternative restore method using document ID directly (more reliable)
        func restoreArchivedIncidentById(id: String, completion: ((Error?) -> Void)? = nil) {
            print("FirebaseManager: Attempting to restore archived incident by ID: \(id)")
            let archivedRef = db.collection("archivedIncidents").document(id)

            archivedRef.getDocument { snap, err in
                if let err = err {
                    print("FirebaseManager: Error fetching archived incident by ID: \(err)")
                    completion?(err)
                    return
                }

                guard let snap = snap, snap.exists, snap.data() != nil else {
                    print("FirebaseManager: Archived incident with ID \(id) not found")
                    completion?(
                        NSError(
                            domain: "FirebaseManager", code: -404,
                            userInfo: [NSLocalizedDescriptionKey: "Archived incident not found"]))
                    return
                }

                print("FirebaseManager: Found archived incident by ID, restoring...")
                self.restoreDocument(snap, completion: completion)
            }
        }

        /// Watch archived incidents collection.
        func watchArchivedIncidents(onUpdate: @escaping ([Incident]) -> Void) {
            stopWatchingArchivedIncidents()
            let ref = db.collection("archivedIncidents").order(by: "archivedAt", descending: true)
            archivedIncidentsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    print(
                        "FirebaseManager: Error watching archived incidents: \(error?.localizedDescription ?? "unknown")"
                    )
                    onUpdate([])
                    return
                }
                var items: [Incident] = []
                print(
                    "FirebaseManager: Received \(snap.documents.count) archived incident documents")
                for doc in snap.documents {
                    let d = doc.data()
                    if let i = self.incidentFrom(data: d) {
                        print(
                            "FirebaseManager: Parsed archived incident: '\(i.title)' type='\(i.incidentType ?? "nil")' archivedAt=\(i.archivedAt != nil)"
                        )
                        items.append(i)
                    } else {
                        print(
                            "FirebaseManager: Failed to parse archived incident document: \(doc.documentID)"
                        )
                    }
                }
                print("FirebaseManager: Returning \(items.count) parsed archived incidents")
                onUpdate(items)
            }
        }

        func stopWatchingArchivedIncidents() {
            archivedIncidentsListener?.remove()
            archivedIncidentsListener = nil
        }

        func deleteIncident(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("incidents").document(id)
            // Read the document first to see if it has an imageURL we should delete from Storage
            ref.getDocument { snap, err in
                if let err = err {
                    completion?(err)
                    return
                }
                if let data = snap?.data(), let imageURLString = data["imageURL"] as? String {
                    if let storageRef = self.storageReference(fromDownloadURLString: imageURLString)
                    {
                        storageRef.delete { storageErr in
                            if let storageErr = storageErr {
                                print(
                                    "FirebaseManager: failed to delete storage object for incident \(id): \(storageErr)"
                                )
                                // proceed to delete Firestore doc anyway
                            } else {
                                print("FirebaseManager: deleted storage object for incident \(id)")
                            }
                            ref.delete(completion: completion)
                        }
                        return
                    }
                }
                // No storage object found or unable to resolve — just delete the doc
                ref.delete(completion: completion)
            }
        }

        func deleteArchivedIncident(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("archivedIncidents").document(id)
            ref.getDocument { snap, err in
                if let err = err {
                    completion?(err)
                    return
                }
                if let data = snap?.data(), let imageURLString = data["imageURL"] as? String {
                    if let storageRef = self.storageReference(fromDownloadURLString: imageURLString)
                    {
                        storageRef.delete { storageErr in
                            if let storageErr = storageErr {
                                print(
                                    "FirebaseManager: failed to delete archived storage object for incident \(id): \(storageErr)"
                                )
                            } else {
                                print(
                                    "FirebaseManager: deleted archived storage object for incident \(id)"
                                )
                            }
                            ref.delete(completion: completion)
                        }
                        return
                    }
                }
                ref.delete(completion: completion)
            }
        }

        // MARK: - Events & Issues
        private var eventsListener: ListenerRegistration?
        private var issuesListener: ListenerRegistration?

        // MARK: - Active Alerts
        struct ActiveAlert: Codable, Identifiable {
            var id: String
            var title: String
            var message: String?
            var location: String?
            var contactName: String?
            var contactPhone: String?
            var imageURL: String?
            var createdAt: Timestamp?
            var createdBy: String?
        }
        private var activeAlertsListener: ListenerRegistration?

        func watchActiveAlerts(onUpdate: @escaping ([ActiveAlert]) -> Void) {
            stopWatchingActiveAlerts()
            let ref = db.collection("activeAlerts").order(by: "createdAt", descending: true)
            activeAlertsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [ActiveAlert] = []
                for doc in snap.documents {
                    let d = doc.data()
                    let aa = ActiveAlert(
                        id: doc.documentID,
                        title: d["title"] as? String ?? "",
                        message: d["message"] as? String,
                        location: d["location"] as? String,
                        contactName: d["contactName"] as? String,
                        contactPhone: d["contactPhone"] as? String,
                        imageURL: d["imageURL"] as? String,
                        createdAt: d["createdAt"] as? Timestamp,
                        createdBy: d["createdBy"] as? String)
                    items.append(aa)
                }
                onUpdate(items)
            }
        }

        func stopWatchingActiveAlerts() {
            activeAlertsListener?.remove()
            activeAlertsListener = nil
        }

        func createActiveAlert(_ alert: ActiveAlert, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("activeAlerts").document(alert.id)
            var dict: [String: Any] = ["title": alert.title, "createdAt": Timestamp(date: Date())]
            if let m = alert.message { dict["message"] = m }
            if let l = alert.location { dict["location"] = l }
            if let cn = alert.contactName { dict["contactName"] = cn }
            if let cp = alert.contactPhone { dict["contactPhone"] = cp }
            if let img = alert.imageURL { dict["imageURL"] = img }
            if let cb = alert.createdBy { dict["createdBy"] = cb }
            ref.setData(dict) { err in completion?(err) }
        }

        func deleteActiveAlert(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("activeAlerts").document(id)
            // Attempt to delete associated Storage image if present, then delete doc
            ref.getDocument { snap, err in
                if let err = err {
                    completion?(err)
                    return
                }
                if let data = snap?.data(), let imageURLString = data["imageURL"] as? String {
                    if let storageRef = self.storageReference(fromDownloadURLString: imageURLString)
                    {
                        storageRef.delete { storageErr in
                            if let storageErr = storageErr {
                                print(
                                    "FirebaseManager: failed to delete active alert storage object for alert \(id): \(storageErr)"
                                )
                            }
                            ref.delete(completion: completion)
                        }
                        return
                    }
                }
                ref.delete(completion: completion)
            }
        }

        // MARK: - Admin helpers
        /// Check whether a given uid (or current user if nil) is an admin by reading users/{uid}.isAdmin
        func isUserAdmin(uid: String? = nil, completion: @escaping (Bool) -> Void) {
            // If a uid is provided, check that uid. Otherwise fall back to the currently signed-in user.
            let checkUID: String
            if let explicit = uid {
                checkUID = explicit
            } else {
                guard let current = Auth.auth().currentUser else {
                    completion(false)
                    return
                }
                checkUID = current.uid
            }
            let ref = db.collection("users").document(checkUID)
            ref.getDocument { snap, err in
                if let data = snap?.data(), let isAdmin = data["isAdmin"] as? Bool {
                    completion(isAdmin)
                } else {
                    completion(false)
                }
            }
        }

        func isCurrentUserAdmin(completion: @escaping (Bool) -> Void) {
            isUserAdmin(uid: nil, completion: completion)
        }
        
        /// Check whether a given uid (or current user if nil) is a committee member
        func isUserCommittee(uid: String? = nil, completion: @escaping (Bool) -> Void) {
            let checkUID: String
            if let explicit = uid {
                checkUID = explicit
            } else {
                guard let current = Auth.auth().currentUser else {
                    completion(false)
                    return
                }
                checkUID = current.uid
            }
            let ref = db.collection("users").document(checkUID)
            ref.getDocument { snap, err in
                if let data = snap?.data(), let isCommittee = data["isCommittee"] as? Bool {
                    completion(isCommittee)
                } else {
                    completion(false)
                }
            }
        }
        
        /// Check if current user is admin OR committee member
        func isCurrentUserAdminOrCommittee(completion: @escaping (Bool) -> Void) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion(false)
                return
            }
            let ref = db.collection("users").document(uid)
            ref.getDocument { snap, err in
                if let data = snap?.data() {
                    let isAdmin = data["isAdmin"] as? Bool ?? false
                    let isCommittee = data["isCommittee"] as? Bool ?? false
                    completion(isAdmin || isCommittee)
                } else {
                    completion(false)
                }
            }
        }
        
        /// Fetch and cache current user's roles in UserDefaults
        func cacheCurrentUserRoles(completion: @escaping () -> Void) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion()
                return
            }
            let ref = db.collection("users").document(uid)
            ref.getDocument { snap, err in
                if let data = snap?.data() {
                    let isAdmin = data["isAdmin"] as? Bool ?? false
                    let isCommittee = data["isCommittee"] as? Bool ?? false
                    UserDefaults.standard.set(isAdmin, forKey: "userIsAdmin")
                    UserDefaults.standard.set(isCommittee, forKey: "userIsCommittee")
                    print("✅ Cached user roles: isAdmin=\(isAdmin), isCommittee=\(isCommittee)")
                }
                completion()
            }
        }

        /// Load current user's profile data (including profile image URL) and cache it locally
        func loadCurrentUserProfile(completion: @escaping (Result<Void, Error>) -> Void) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])))
                return
            }
            
            let ref = db.collection("users").document(uid)
            ref.getDocument { snap, err in
                if let err = err {
                    print("❌ Failed to load user profile: \(err.localizedDescription)")
                    completion(.failure(err))
                    return
                }
                
                if let data = snap?.data() {
                    // Cache profile image URL if available
                    if let profileImageURL = data["profileImageURL"] as? String, !profileImageURL.isEmpty {
                        UserDefaults.standard.set(profileImageURL, forKey: "profileImageURL")
                        print("✅ Cached profile image URL: \(profileImageURL)")
                    }
                    
                    // Cache other profile data
                    if let firstName = data["firstName"] as? String {
                        UserDefaults.standard.set(firstName, forKey: "userName")
                    }
                    if let lastName = data["lastName"] as? String {
                        UserDefaults.standard.set(lastName, forKey: "userSurname")
                    }
                    if let email = data["email"] as? String {
                        UserDefaults.standard.set(email, forKey: "userEmail")
                    }
                    
                    print("✅ User profile data cached successfully")
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user data found"])))
                }
            }
        }

        /// Watch the `users` collection and deliver an array of document dictionaries.
        /// This is useful to keep a UI in sync with server-registered users. Returns the listener registration
        /// so callers can remove it when appropriate.
        @discardableResult
        func watchRegisteredUsers(
            onlyVerified: Bool = true, onUpdate: @escaping ([[String: Any]]) -> Void
        ) -> ListenerRegistration? {
            print("🔧 Setting up Firestore listener (onlyVerified: \(onlyVerified))")
            let base: Query = db.collection("users")
            let query: Query = onlyVerified ? base.whereField("verified", isEqualTo: true) : base
            let listener = query.addSnapshotListener { snap, err in
                if let err = err {
                    print("❌ Firestore listener error: \(err.localizedDescription)")
                    onUpdate([])
                    return
                }
                
                guard let docs = snap?.documents else {
                    print("⚠️ No documents found in users collection")
                    onUpdate([])
                    return
                }
                
                print("📡 Firestore listener received \(docs.count) documents")
                
                let arr = docs.map { doc -> [String: Any] in
                    var d = doc.data()
                    d["uid"] = doc.documentID
                    return d
                }
                onUpdate(arr)
            }
            return listener
        }
        
        /// Create or update a user profile in Firestore 'users' collection
        func createOrUpdateUser(
            email: String,
            firstName: String,
            lastName: String,
            phoneNumber: String? = nil,
            street: String? = nil,
            suburb: String? = nil,
            city: String? = nil,
            postalCode: String? = nil,
            emergencyContactName: String? = nil,
            emergencyContactPhone: String? = nil,
            emergencyContactRelationship: String? = nil,
            profileImageURL: String? = nil,
            shareWithCommunity: Bool = true,
            shareWithCommittee: Bool = true,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            // Use email as the document ID (unique identifier)
            let userRef = db.collection("users").document(email)
            
            var userData: [String: Any] = [
                "uid": email,
                "email": email,
                "firstName": firstName,
                "lastName": lastName,
                "name": "\(firstName) \(lastName)",
                "verified": false, // Requires admin approval
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "privacyShareWithCommunity": shareWithCommunity,
                "privacyShareWithCommittee": shareWithCommittee
            ]
            
            // Add optional fields if provided
            if let phone = phoneNumber, !phone.isEmpty {
                userData["phone"] = phone
            }
            if let street = street, !street.isEmpty {
                userData["street"] = street
            }
            if let suburb = suburb, !suburb.isEmpty {
                userData["suburb"] = suburb
            }
            if let city = city, !city.isEmpty {
                userData["city"] = city
            }
            if let postal = postalCode, !postal.isEmpty {
                userData["postalCode"] = postal
            }
            if let emName = emergencyContactName, !emName.isEmpty {
                userData["emergencyContactName"] = emName
            }
            if let emPhone = emergencyContactPhone, !emPhone.isEmpty {
                userData["emergencyContactPhone"] = emPhone
            }
            if let emRel = emergencyContactRelationship, !emRel.isEmpty {
                userData["emergencyContactRelationship"] = emRel
            }
            if let profileURL = profileImageURL, !profileURL.isEmpty {
                userData["profileImageURL"] = profileURL
            }
            
            // Create full address string
            let addressParts = [street, suburb, city, postalCode].compactMap { $0 }.filter { !$0.isEmpty }
            if !addressParts.isEmpty {
                userData["address"] = addressParts.joined(separator: ", ")
            }
            
            userRef.setData(userData, merge: true) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(email))
                }
            }
        }
        
        /// Upload profile image to Firebase Storage and return the download URL
        func uploadProfileImage(
            _ image: UIImage,
            forUserEmail email: String,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            // Resize image to reasonable size (max 500x500)
            let resizedImage = resizeImage(image, targetSize: CGSize(width: 500, height: 500))
            
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.7) else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])))
                return
            }
            
            let safeEmail = email.replacingOccurrences(of: "@", with: "_at_").replacingOccurrences(of: ".", with: "_")
            let storageRef = Storage.storage().reference().child("profiles/\(safeEmail)/avatar.jpg")
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            storageRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                storageRef.downloadURL { url, error in
                    if let error = error {
                        completion(.failure(error))
                    } else if let url = url {
                        completion(.success(url.absoluteString))
                    } else {
                        completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No download URL returned"])))
                    }
                }
            }
        }
        
        /// Helper to resize images for efficient storage
        private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio  = targetSize.width  / size.width
            let heightRatio = targetSize.height / size.height
            let ratio = min(widthRatio, heightRatio)
            
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let rect = CGRect(origin: .zero, size: newSize)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage ?? image
        }
        
        /// Approve a registered user (set verified to true)
        func approveUser(
            uid: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            db.collection("users").document(uid).updateData([
                "verified": true,
                "approvedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
        
        /// Approve a registered user with role assignment
        func approveUserWithRole(
            uid: String,
            asAdmin: Bool = false,
            asCommittee: Bool = false,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            var updateData: [String: Any] = [
                "verified": true,
                "approvedAt": FieldValue.serverTimestamp()
            ]
            
            // Add role fields if specified
            if asAdmin {
                updateData["isAdmin"] = true
            }
            if asCommittee {
                updateData["isCommittee"] = true
            }
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    let roles = [
                        asAdmin ? "Admin" : nil,
                        asCommittee ? "Committee" : nil
                    ].compactMap { $0 }.joined(separator: ", ")
                    
                    let roleText = roles.isEmpty ? "Regular User" : roles
                    print("✅ User approved as: \(roleText)")
                    completion(.success(()))
                }
            }
        }
        
        /// Update user roles (can be done after approval)
        func updateUserRoles(
            uid: String,
            isAdmin: Bool? = nil,
            isCommittee: Bool? = nil,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            var updateData: [String: Any] = [
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let isAdmin = isAdmin {
                updateData["isAdmin"] = isAdmin
            }
            if let isCommittee = isCommittee {
                updateData["isCommittee"] = isCommittee
            }
            
            guard !updateData.isEmpty else {
                completion(.success(()))
                return
            }
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
        
        /// Reject a registered user (mark as rejected)
        func rejectUser(
            uid: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            db.collection("users").document(uid).updateData([
                "verified": false,
                "rejected": true,
                "rejectedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
        
        // MARK: - Camera Access Management
        
        /// Submit a camera access request when user enters watch credentials
        func requestCameraAccess(
            uid: String,
            watchUsername: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            let updateData: [String: Any] = [
                "cameraAccessRequested": true,
                "cameraAccessRequestedAt": FieldValue.serverTimestamp(),
                "watchCredential": watchUsername
            ]
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Camera access requested for user \(uid) with watch username: \(watchUsername)")
                    completion(.success(()))
                }
            }
        }
        
        /// Update camera access permission for a user (UID-based, secure)
        func updateCameraAccess(
            uid: String,
            granted: Bool,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            var updateData: [String: Any] = [
                "cameraAccess": granted,
                "cameraAccessUpdatedAt": FieldValue.serverTimestamp()
            ]
            
            // If granting access, record who granted it
            if granted, let adminUID = Auth.auth().currentUser?.uid {
                updateData["cameraAccessGrantedBy"] = adminUID
                // Clear the pending request flag when access is granted
                updateData["cameraAccessRequested"] = false
            }
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Camera access \(granted ? "granted" : "revoked") for user \(uid)")
                    completion(.success(()))
                }
            }
        }
        
        /// Get camera access status for current user (UID-based)
        func checkCameraAccess(
            uid: String,
            completion: @escaping (Result<Bool, Error>) -> Void
        ) {
            db.collection("users").document(uid).getDocument { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let hasCameraAccess = snapshot?.data()?["cameraAccess"] as? Bool ?? false
                completion(.success(hasCameraAccess))
            }
        }
        
        // MARK: - Admin & Committee Role Management
        
        /// Update admin role for a user
        func updateAdminRole(
            uid: String,
            granted: Bool,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            var updateData: [String: Any] = [
                "isAdmin": granted,
                "adminRoleUpdatedAt": FieldValue.serverTimestamp()
            ]
            
            // If granting admin role, record who granted it
            if granted, let adminUID = Auth.auth().currentUser?.uid {
                updateData["adminRoleGrantedBy"] = adminUID
            }
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Admin role \(granted ? "granted" : "revoked") for user \(uid)")
                    
                    // Update local cache if this is the current user
                    if uid == Auth.auth().currentUser?.uid {
                        UserDefaults.standard.set(granted, forKey: "userIsAdmin")
                    }
                    
                    completion(.success(()))
                }
            }
        }
        
        /// Update committee role for a user
        func updateCommitteeRole(
            uid: String,
            granted: Bool,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            var updateData: [String: Any] = [
                "isCommittee": granted,
                "committeeRoleUpdatedAt": FieldValue.serverTimestamp()
            ]
            
            // If granting committee role, record who granted it
            if granted, let adminUID = Auth.auth().currentUser?.uid {
                updateData["committeeRoleGrantedBy"] = adminUID
            }
            
            db.collection("users").document(uid).updateData(updateData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Committee role \(granted ? "granted" : "revoked") for user \(uid)")
                    
                    // Update local cache if this is the current user
                    if uid == Auth.auth().currentUser?.uid {
                        UserDefaults.standard.set(granted, forKey: "userIsCommittee")
                    }
                    
                    completion(.success(()))
                }
            }
        }
        
        // MARK: - Camera Access Migration
        
        /// Migrate legacy camera users from watchUsername string list to Firestore cameraAccess
        /// This finds all registered users whose names match the legacy cameraUsers list
        /// and grants them Firestore camera access
        func migrateLegacyCameraUsers(
            legacyUsernames: [String],
            completion: @escaping (Result<(granted: Int, notFound: [String], conflicts: [String: [[String: String]]]), Error>) -> Void
        ) {
            print("🔄 Starting migration of \(legacyUsernames.count) legacy camera users...")
            print("   Legacy usernames to migrate: \(legacyUsernames.joined(separator: ", "))")
            
            // Fetch all users from Firestore
            db.collection("users").getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Migration failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success((granted: 0, notFound: legacyUsernames, conflicts: [:])))
                    return
                }
                
                print("📊 Found \(documents.count) users in Firestore")
                
                var grantedCount = 0
                var notFoundUsernames: [String] = []
                var conflicts: [String: [[String: String]]] = [:] // legacyUsername -> [matching users]
                let group = DispatchGroup()
                
                // Build a dictionary to track ALL matches per legacy username
                var matchesPerLegacyUsername: [String: [(uid: String, fullName: String, watchCredential: String, alreadyHasAccess: Bool)]] = [:]
                
                // Check each Firestore user
                for doc in documents {
                    let data = doc.data()
                    let firstName = (data["firstName"] as? String) ?? ""
                    let lastName = (data["lastName"] as? String) ?? ""
                    let uid = doc.documentID
                    let alreadyHasCamera = (data["cameraAccess"] as? Bool) ?? false
                    
                    guard !firstName.isEmpty else { continue }
                    
                    // Build name variations
                    let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    let lastInitial = lastName.first.map { String($0).uppercased() } ?? ""
                    let watchCredentialFormat = "\(firstName)\(lastInitial)".trimmingCharacters(in: .whitespaces)
                    
                    // Check each legacy username
                    for legacyUsername in legacyUsernames {
                        let legacyLower = legacyUsername.lowercased().trimmingCharacters(in: .whitespaces)
                        
                        // All variations to check
                        let variations = [
                            watchCredentialFormat.lowercased(),       // "mikew" (PRIMARY)
                            fullName.lowercased(),                    // "mike wilson"
                            firstName.lowercased(),                   // "mike"
                            "\(firstName) \(lastInitial)".lowercased(), // "mike w"
                        ]
                        
                        // Check if any variation matches
                        if variations.contains(legacyLower) {
                            // Found a match!
                            if matchesPerLegacyUsername[legacyUsername] == nil {
                                matchesPerLegacyUsername[legacyUsername] = []
                            }
                            matchesPerLegacyUsername[legacyUsername]?.append((
                                uid: uid,
                                fullName: fullName,
                                watchCredential: watchCredentialFormat,
                                alreadyHasAccess: alreadyHasCamera
                            ))
                            let accessStatus = alreadyHasCamera ? "✓ Already has access" : "○ Needs access"
                            print("   🔍 Match found: '\(legacyUsername)' → \(fullName) (Watch: \(watchCredentialFormat)) [\(accessStatus)]")
                        }
                    }
                }
                
                // Process matches
                for legacyUsername in legacyUsernames {
                    guard let matches = matchesPerLegacyUsername[legacyUsername] else {
                        // No matches found
                        notFoundUsernames.append(legacyUsername)
                        print("   ⚠️ No match for: '\(legacyUsername)'")
                        continue
                    }
                    
                    if matches.count == 1 {
                        // Single match
                        let match = matches[0]
                        
                        if match.alreadyHasAccess {
                            // Already has access - count as granted (skip API call)
                            grantedCount += 1
                            print("   ✅ ALREADY GRANTED: '\(legacyUsername)' → \(match.fullName) (already has camera access)")
                        } else {
                            // Grant access
                            print("   ✅ SINGLE MATCH: '\(legacyUsername)' → \(match.fullName)")
                            
                            group.enter()
                            self.updateCameraAccess(uid: match.uid, granted: true) { result in
                                switch result {
                                case .success:
                                    grantedCount += 1
                                    print("      ✅ Camera access granted to \(match.fullName) (UID: \(match.uid))")
                                case .failure(let error):
                                    print("      ❌ Failed to grant access to \(match.fullName): \(error.localizedDescription)")
                                }
                                group.leave()
                            }
                        }
                    } else {
                        // Multiple matches - conflict! Store for manual resolution
                        print("   ⚠️ CONFLICT: '\(legacyUsername)' has \(matches.count) possible matches:")
                        
                        var conflictUsers: [[String: String]] = []
                        for match in matches {
                            let accessStatus = match.alreadyHasAccess ? "✓ Has access" : "○ No access"
                            print("      - \(match.fullName) (Watch: \(match.watchCredential), UID: \(match.uid)) [\(accessStatus)]")
                            conflictUsers.append([
                                "uid": match.uid,
                                "fullName": match.fullName,
                                "watchCredential": match.watchCredential,
                                "hasAccess": String(match.alreadyHasAccess)
                            ])
                        }
                        conflicts[legacyUsername] = conflictUsers
                    }
                }
                
                // Wait for all grants to complete
                group.notify(queue: .main) {
                    print("✅ Migration complete:")
                    print("   Auto-granted: \(grantedCount)")
                    print("   Not found: \(notFoundUsernames.count)")
                    print("   Conflicts: \(conflicts.count)")
                    
                    if !notFoundUsernames.isEmpty {
                        print("   ⚠️ Users not matched: \(notFoundUsernames.joined(separator: ", "))")
                    }
                    
                    if !conflicts.isEmpty {
                        print("   ⚠️ Conflicts require manual selection:")
                        for (legacyName, matches) in conflicts {
                            print("      '\(legacyName)' → \(matches.count) possible users")
                        }
                    }
                    
                    completion(.success((granted: grantedCount, notFound: notFoundUsernames, conflicts: conflicts)))
                }
            }
        }
        
        /// Delete a user completely (admin only)
        func deleteUser(
            uid: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            let userRef = db.collection("users").document(uid)
            
            // First fetch user data to get profile image URL
            userRef.getDocument { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Delete profile image from Storage if exists
                if let data = snapshot?.data(),
                   let imageURLString = data["profileImageURL"] as? String,
                   let storageRef = self.storageReference(fromDownloadURLString: imageURLString) {
                    storageRef.delete { _ in
                        // Continue with user deletion even if image deletion fails
                    }
                }
                
                // Delete the user document
                userRef.delete { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
        
        // MARK: - Firebase Authentication Methods
        
        /// Get current Firebase Auth user
        func getCurrentUser() -> FirebaseAuth.User? {
            #if canImport(FirebaseAuth)
                return Auth.auth().currentUser
            #else
                return nil
            #endif
        }
        
        /// Get current user's UID
        func getCurrentUserUID() -> String? {
            #if canImport(FirebaseAuth)
                return Auth.auth().currentUser?.uid
            #else
                return nil
            #endif
        }
        
        /// Sign in with email and password
        func signIn(email: String, password: String, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
            #if canImport(FirebaseAuth)
                Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
                    if let error = error {
                        completion(.failure(error))
                    } else if let user = authResult?.user {
                        completion(.success(user))
                    } else {
                        completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown sign-in error"])))
                    }
                }
            #else
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase Auth not available"])))
            #endif
        }
        
        /// Create new user with email and password
        func createUser(email: String, password: String, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
            #if canImport(FirebaseAuth)
                Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
                    if let error = error {
                        completion(.failure(error))
                    } else if let user = authResult?.user {
                        completion(.success(user))
                    } else {
                        completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown account creation error"])))
                    }
                }
            #else
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase Auth not available"])))
            #endif
        }
        
        /// Sign out current user
        func signOut() throws {
            #if canImport(FirebaseAuth)
                try Auth.auth().signOut()
            #endif
        }
        
        /// Send password reset email
        func sendPasswordReset(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
            #if canImport(FirebaseAuth)
                Auth.auth().sendPasswordReset(withEmail: email) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            #else
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase Auth not available"])))
            #endif
        }
        
        /// Store FCM token for push notifications
        /// This allows the backend to send push notifications to this device
        func storeFCMToken(apnsToken: String, completion: @escaping (Result<Void, Error>) -> Void) {
            #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
                guard let uid = getCurrentUserUID() else {
                    completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
                    return
                }
                
                let tokenData: [String: Any] = [
                    "token": apnsToken,
                    "platform": "ios",
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastUsed": FieldValue.serverTimestamp()
                ]
                
                // Store token in subcollection: users/{uid}/tokens/{tokenId}
                // Using the token itself as the document ID ensures uniqueness per device
                let tokenRef = db.collection("users").document(uid).collection("tokens").document(apnsToken)
                
                tokenRef.setData(tokenData, merge: true) { error in
                    if let error = error {
                        print("❌ Failed to store FCM token: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ FCM token stored successfully for user \(uid)")
                        completion(.success(()))
                    }
                }
            #else
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase Auth or Firestore not available"])))
            #endif
        }
        
        /// Update createOrUpdateUser to use Firebase Auth UID instead of email as document ID
        func createOrUpdateUserWithAuth(
            firstName: String,
            lastName: String,
            email: String,
            phoneNumber: String? = nil,
            street: String? = nil,
            suburb: String? = nil,
            city: String? = nil,
            postalCode: String? = nil,
            emergencyContactName: String? = nil,
            emergencyContactPhone: String? = nil,
            emergencyContactRelationship: String? = nil,
            profileImageURL: String? = nil,
            shareWithCommunity: Bool = true,
            shareWithCommittee: Bool = true,
            wellnessOptIn: Bool = true,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            guard let uid = getCurrentUserUID() else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
                return
            }
            
            // Debug logging - what data was received
            print("🔍 DEBUG: Creating Firestore user document")
            print("   UID: \(uid)")
            print("   Name: \(firstName) \(lastName)")
            print("   Email: \(email)")
            print("   Phone: \(phoneNumber ?? "nil")")
            print("   Street: \(street ?? "nil")")
            print("   Suburb: \(suburb ?? "nil")")
            print("   City: \(city ?? "nil")")
            print("   Postal: \(postalCode ?? "nil")")
            print("   Emergency Contact: \(emergencyContactName ?? "nil")")
            print("   Emergency Phone: \(emergencyContactPhone ?? "nil")")
            print("   Emergency Relationship: \(emergencyContactRelationship ?? "nil")")
            
            // Use UID as the document ID instead of email
            let userRef = db.collection("users").document(uid)
            
            var userData: [String: Any] = [
                "uid": uid,
                "email": email,
                "firstName": firstName,
                "lastName": lastName,
                "name": "\(firstName) \(lastName)",
                "verified": false, // Requires admin approval
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "privacyShareWithCommunity": shareWithCommunity,
                "privacyShareWithCommittee": shareWithCommittee,
                "wellnessOptIn": wellnessOptIn
            ]
            
            // Add optional fields if provided
            if let phone = phoneNumber, !phone.isEmpty {
                userData["phone"] = phone
                print("   ✅ Adding phone to Firestore: \(phone)")
            } else {
                print("   ⚠️ Phone not added (empty or nil)")
            }
            
            if let street = street, !street.isEmpty {
                userData["street"] = street
                print("   ✅ Adding street to Firestore: \(street)")
            } else {
                print("   ⚠️ Street not added (empty or nil)")
            }
            
            if let suburb = suburb, !suburb.isEmpty {
                userData["suburb"] = suburb
                print("   ✅ Adding suburb to Firestore: \(suburb)")
            } else {
                print("   ⚠️ Suburb not added (empty or nil)")
            }
            
            if let city = city, !city.isEmpty {
                userData["city"] = city
                print("   ✅ Adding city to Firestore: \(city)")
            } else {
                print("   ⚠️ City not added (empty or nil)")
            }
            
            if let postal = postalCode, !postal.isEmpty {
                userData["postalCode"] = postal
                print("   ✅ Adding postalCode to Firestore: \(postal)")
            } else {
                print("   ⚠️ PostalCode not added (empty or nil)")
            }
            
            if let emName = emergencyContactName, !emName.isEmpty {
                userData["emergencyContactName"] = emName
                print("   ✅ Adding emergencyContactName to Firestore: \(emName)")
            } else {
                print("   ⚠️ EmergencyContactName not added (empty or nil)")
            }
            
            if let emPhone = emergencyContactPhone, !emPhone.isEmpty {
                userData["emergencyContactPhone"] = emPhone
                print("   ✅ Adding emergencyContactPhone to Firestore: \(emPhone)")
            } else {
                print("   ⚠️ EmergencyContactPhone not added (empty or nil)")
            }
            
            if let emRel = emergencyContactRelationship, !emRel.isEmpty {
                userData["emergencyContactRelationship"] = emRel
                print("   ✅ Adding emergencyContactRelationship to Firestore: \(emRel)")
            } else {
                print("   ⚠️ EmergencyContactRelationship not added (empty or nil)")
            }
            
            if let profileURL = profileImageURL, !profileURL.isEmpty {
                userData["profileImageURL"] = profileURL
                print("   ✅ Adding profileImageURL to Firestore: \(profileURL)")
            } else {
                print("   ⚠️ ProfileImageURL not added (empty or nil)")
            }
            
            print("📤 Saving to Firestore: users/\(uid)")
            print("   Total fields: \(userData.keys.count)")
            
            userRef.setData(userData, merge: true) { error in
                if let error = error {
                    let nsError = error as NSError
                    print("❌ Failed to create/update user in Firestore: \(error.localizedDescription)")
                    print("   Error domain: \(nsError.domain)")
                    print("   Error code: \(nsError.code)")
                    
                    // Check if it's a network error and suggest retry
                    if nsError.domain == "NSPOSIXErrorDomain" || 
                       nsError.code == 50 ||
                       error.localizedDescription.contains("network") {
                        print("⚠️ NETWORK ERROR: Please check your internet connection")
                        print("   The user profile will be created when connectivity is restored")
                        print("   Recovery mechanism will handle this on next login")
                    }
                    
                    completion(.failure(error))
                } else {
                    print("✅ Successfully created/updated user profile in Firestore")
                    print("   Document path: users/\(uid)")
                    print("   Fields saved: \(userData.keys.sorted().joined(separator: ", "))")
                    completion(.success(uid))
                }
            }
        }

        private func eventFrom(data: [String: Any]) -> LocalEvent? {
            guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
                let title = data["title"] as? String,
                let dateVal = data["date"]
            else { return nil }

            let date: Date
            if let ts = dateVal as? Timestamp {
                date = ts.dateValue()
            } else if let ti = dateVal as? TimeInterval {
                date = Date(timeIntervalSince1970: ti)
            } else {
                date = Date()
            }

            let description = data["description"] as? String
            let location = data["location"] as? String
            let typeRaw = data["eventType"] as? String ?? EventType.event.rawValue
            let eventType = EventType(rawValue: typeRaw) ?? .event

            var comments: [EventComment] = []
            if let rawComments = data["comments"] as? [[String: Any]] {
                for c in rawComments {
                    if let cid = c["id"] as? String, let uuid = UUID(uuidString: cid),
                        let author = c["author"] as? String, let content = c["content"] as? String,
                        let ts = c["timestamp"] as? Timestamp
                    {
                        let comm = EventComment(
                            id: uuid, author: author, content: content, timestamp: ts.dateValue())
                        comments.append(comm)
                    }
                }
            }
            
            var messages: [IncidentMessage] = []
            if let rawMessages = data["messages"] as? [[String: Any]] {
                for m in rawMessages {
                    if let mid = m["id"] as? String, let uuid = UUID(uuidString: mid),
                        let senderUID = m["senderUID"] as? String,
                        let senderName = m["senderName"] as? String,
                        let messageText = m["message"] as? String,
                        let ts = m["timestamp"] as? Timestamp
                    {
                        let isAdmin = m["isAdmin"] as? Bool ?? false
                        let message = IncidentMessage(
                            id: uuid,
                            senderUID: senderUID,
                            senderName: senderName,
                            message: messageText,
                            timestamp: ts.dateValue(),
                            isAdmin: isAdmin
                        )
                        messages.append(message)
                    }
                }
            }

            var imageData: Data? = nil
            if let b64 = data["imageData"] as? String, let d = Data(base64Encoded: b64) {
                imageData = d
            }
            var fileURL: URL? = nil
            if let fileURLStr = data["fileURL"] as? String { fileURL = URL(string: fileURLStr) }

            var le = LocalEvent(
                id: id, title: title, description: description, location: location, date: date,
                eventType: eventType)
            le.comments = comments
            le.messages = messages
            le.imageData = imageData
            le.fileURL = fileURL
            le.thumbsUp = data["thumbsUp"] as? Int ?? 0
            le.heart = data["heart"] as? Int ?? 0
            le.party = data["party"] as? Int ?? 0
            le.creatorName = data["creatorName"] as? String
            le.creatorSurname = data["creatorSurname"] as? String
            le.creatorUID = data["creatorUID"] as? String
            le.contactName = data["contactName"] as? String
            le.contactCell = data["contactCell"] as? String
            if let meta = data["metadata"] as? [String: String] { le.metadata = meta }
            
            // Admin status
            le.isResolved = data["isResolved"] as? Bool ?? false
            if let ts = data["resolvedAt"] as? Timestamp {
                le.resolvedAt = ts.dateValue()
            }
            le.resolvedBy = data["resolvedBy"] as? String
            
            return le
        }

        /// Watch the events collection in real-time and deliver LocalEvent models.
        func watchEvents(onUpdate: @escaping ([LocalEvent]) -> Void) {
            stopWatchingEvents()
            let ref = db.collection("events").order(by: "date", descending: true)
            eventsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [LocalEvent] = []
                for doc in snap.documents {
                    var d = doc.data()
                    if let ts = d["date"] as? Timestamp { d["date"] = ts }
                    // Build the LocalEvent with imageData from Firestore (instant loading)
                    if let event = self.eventFrom(data: d) {
                        items.append(event)
                    }
                }
                onUpdate(items)
            }
        }

        func stopWatchingEvents() {
            eventsListener?.remove()
            eventsListener = nil
        }

        /// Create or update an event. Uploads attachments to Storage if available.
        func createOrUpdateEvent(_ event: LocalEvent, completion: ((Error?) -> Void)? = nil) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion?(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
                return
            }
            
            let ref = db.collection("events").document(event.id.uuidString)
            var dict: [String: Any] = [
                "id": event.id.uuidString,
                "title": event.title,
                "description": event.description ?? "",
                "location": event.location ?? "",
                "eventType": event.eventType.rawValue,
                "thumbsUp": event.thumbsUp,
                "heart": event.heart,
                "party": event.party,
                "creatorId": uid,  // Required by security rules
                "creatorName": event.creatorName ?? "",
                "creatorSurname": event.creatorSurname ?? "",
                "creatorUID": event.creatorUID ?? "",
                "contactName": event.contactName ?? "",
                "contactCell": event.contactCell ?? "",
            ]
            dict["date"] = Timestamp(date: event.date)
            if let meta = event.metadata { dict["metadata"] = meta }
            
            // Admin status tracking
            dict["isResolved"] = event.isResolved
            if let resolvedAt = event.resolvedAt {
                dict["resolvedAt"] = Timestamp(date: resolvedAt)
            }
            if let resolvedBy = event.resolvedBy {
                dict["resolvedBy"] = resolvedBy
            }

            // Store imageData directly in Firestore for instant loading (like newsletters)
            if let data = event.imageData {
                dict["imageData"] = data.base64EncodedString()
            }
            if let url = event.fileURL {
                dict["fileURL"] = url.absoluteString
            }

            // serialize comments
            if !event.comments.isEmpty {
                var out: [[String: Any]] = []
                for c in event.comments {
                    out.append([
                        "id": c.id.uuidString, "author": c.author, "content": c.content,
                        "timestamp": Timestamp(date: c.timestamp),
                    ])
                }
                dict["comments"] = out
            }
            
            // serialize messages
            if !event.messages.isEmpty {
                var messagesOut: [[String: Any]] = []
                for m in event.messages {
                    messagesOut.append([
                        "id": m.id.uuidString,
                        "senderUID": m.senderUID,
                        "senderName": m.senderName,
                        "message": m.message,
                        "timestamp": Timestamp(date: m.timestamp),
                        "isAdmin": m.isAdmin,
                    ])
                }
                dict["messages"] = messagesOut
            }

            ref.setData(dict, merge: true) { err in
                completion?(err)
            }
        }

        func deleteEvent(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("events").document(id)
            ref.getDocument { snap, err in
                if err != nil {
                    ref.delete(completion: completion)
                    return
                }
                var urlsToDelete: [String] = []
                if let d = snap?.data() {
                    if let s = d["imageURL"] as? String { urlsToDelete.append(s) }
                    if let f = d["fileURL"] as? String { urlsToDelete.append(f) }
                    if let arr = d["additionalImageURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr)
                    }
                }
                let group = DispatchGroup()
                for u in urlsToDelete {
                    // Use safe helper to avoid crashes on invalid URLs
                    guard let storageRef = self.storageReference(fromDownloadURLString: u) else {
                        print("⚠️ Skipping invalid storage URL during event deletion: \(u)")
                        continue
                    }
                    group.enter()
                    storageRef.delete { _ in group.leave() }
                }
                let uid = Auth.auth().currentUser?.uid ?? "anon"
                let possiblePrefixes = ["uploads/\(uid)/events/\(id)", "final/events/\(id)"]
                for pref in possiblePrefixes {
                    group.enter()
                    self.storage.reference().child(pref).listAll { res, listErr in
                        if let items = res?.items {
                            let inner = DispatchGroup()
                            for it in items {
                                inner.enter()
                                it.delete { _ in inner.leave() }
                            }
                            inner.notify(queue: .main) { group.leave() }
                        } else {
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) { ref.delete(completion: completion) }
            }
        }

        #if canImport(FirebaseStorage)
            /// Upload raw data to Storage at the given path and return the download URL.
            func uploadData(
                _ data: Data, path: String, completion: @escaping (URL?, Error?) -> Void
            ) {
                // Ensure we have an authenticated user (anonymous sign-in fallback) before uploading.
                ensureSignedIn { signInErr in
                    if let signInErr = signInErr {
                        completion(nil, signInErr)
                        return
                    }
                    let ref = self.storage.reference().child(path)
                    ref.putData(data, metadata: nil) { _, error in
                        if let error = error {
                            completion(nil, error)
                            return
                        }
                        // Use resilient downloadURL with retries to avoid transient objectNotFound errors
                        self.downloadURLWithRetries(from: ref) { url, err in
                            completion(url, err)
                        }
                    }
                }
            }
            
            /// Upload data with retry logic and exponential backoff
            func uploadDataWithRetry(
                _ data: Data, path: String, retries: Int, attempt: Int = 1, completion: @escaping (URL?, Error?) -> Void
            ) {
                print("📤 FirebaseManager: Upload attempt \(attempt)/\(retries) for \(path)")
                
                uploadData(data, path: path) { url, error in
                    if let error = error {
                        if attempt < retries {
                            // Exponential backoff: 2^attempt seconds
                            let delay = pow(2.0, Double(attempt))
                            print("⏱️ FirebaseManager: Upload failed, retrying in \(delay)s...")
                            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                self.uploadDataWithRetry(data, path: path, retries: retries, attempt: attempt + 1, completion: completion)
                            }
                        } else {
                            print("❌ FirebaseManager: Upload failed after \(retries) attempts: \(error.localizedDescription)")
                            completion(nil, error)
                        }
                    } else {
                        print("✅ FirebaseManager: Upload successful on attempt \(attempt)")
                        completion(url, nil)
                    }
                }
            }

            /// Upload a local file URL to Storage at the given path and return the download URL.
            func uploadFile(
                from localURL: URL, path: String, completion: @escaping (URL?, Error?) -> Void
            ) {
                // Ensure we have an authenticated user (anonymous sign-in fallback) before uploading.
                ensureSignedIn { signInErr in
                    if let signInErr = signInErr {
                        completion(nil, signInErr)
                        return
                    }
                    let ref = self.storage.reference().child(path)
                    let uploadTask = ref.putFile(from: localURL, metadata: nil) { _, error in
                        if let error = error {
                            completion(nil, error)
                            return
                        }
                        // Use resilient downloadURL with retries
                        self.downloadURLWithRetries(from: ref) { url, err in
                            completion(url, err)
                        }
                    }
                    // Optional: observe progress
                    _ = uploadTask
                }
            }

            /// Attempt to fetch a Storage downloadURL with retries and exponential backoff.
            /// This mitigates transient 'objectNotFound' errors immediately after upload.
            func downloadURLWithRetries(
                from ref: StorageReference, attempts: Int = 4, initialDelay: TimeInterval = 0.15,
                completion: @escaping (URL?, Error?) -> Void
            ) {
                var tries = 0

                func attempt(_ delay: TimeInterval) {
                    tries += 1
                    ref.downloadURL { url, err in
                        if let url = url {
                            completion(url, nil)
                            return
                        }
                        // If we've exhausted attempts, return last error
                        if tries >= attempts {
                            completion(
                                nil,
                                err
                                    ?? NSError(
                                        domain: "FirebaseManager", code: -999,
                                        userInfo: [
                                            NSLocalizedDescriptionKey: "Failed to fetch downloadURL"
                                        ]))
                            return
                        }
                        // Schedule next attempt with exponential backoff
                        let nextDelay = delay * 2
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            attempt(nextDelay)
                        }
                    }
                }

                // start immediately
                attempt(initialDelay)
            }
            #if canImport(FirebaseAuth)
                /// Ensure there is a signed-in Firebase user. If none, sign in anonymously.
                func ensureSignedIn(completion: @escaping (Error?) -> Void) {
                    if Auth.auth().currentUser != nil {
                        print(
                            "[FirebaseManager] already signed in with uid=\(Auth.auth().currentUser?.uid ?? "(none)")"
                        )
                        completion(nil)
                        return
                    }
                    Auth.auth().signInAnonymously { _, err in
                        if let err = err {
                            print("[FirebaseManager] anonymous sign-in failed: \(err)")
                        } else {
                            print(
                                "[FirebaseManager] anonymous sign-in succeeded uid=\(Auth.auth().currentUser?.uid ?? "(none)")"
                            )
                        }
                        completion(err)
                    }
                }
            #else
                func ensureSignedIn(completion: @escaping (Error?) -> Void) {
                    // FirebaseAuth not available in this build — cannot sign in. Return nil to allow
                    // uploads to proceed if rules permit unauthenticated writes, otherwise caller will
                    // receive permission errors from Storage.
                    completion(nil)
                }
            #endif
        #endif

        // MARK: - Marketplace
        private var marketplaceListener: ListenerRegistration?

        private func marketplaceItemFrom(data: [String: Any]) -> MarketplaceDTO? {
            // Lightweight DTO to map Firestore data to app model
            guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
                let owner = data["owner"] as? String,
                let title = data["title"] as? String
            else { return nil }

            let price = data["price"] as? Double ?? 0.0
            let category = data["category"] as? String ?? ""
            let conditionRaw = data["condition"] as? String ?? "Good"
            let condition = ItemCondition(rawValue: conditionRaw) ?? .good
            let dateVal = data["date"]
            let date: Date
            if let ts = dateVal as? Timestamp {
                date = ts.dateValue()
            } else if let ti = dateVal as? TimeInterval {
                date = Date(timeIntervalSince1970: ti)
            } else {
                date = Date()
            }

            let contact = data["contact"] as? String ?? ""
            let description = data["description"] as? String ?? ""
            let isSold = data["isSold"] as? Bool ?? false
            let soldDateVal = data["soldDate"]
            var soldDate: Date? = nil
            if let ts = soldDateVal as? Timestamp {
                soldDate = ts.dateValue()
            } else if let ti = soldDateVal as? TimeInterval {
                soldDate = Date(timeIntervalSince1970: ti)
            }
            let isNegotiable = data["isNegotiable"] as? Bool ?? false
            let tags = data["tags"] as? [String] ?? []
            let location = data["location"] as? String ?? ""

            var imageURL: URL? = nil
            if let s = data["imageURL"] as? String { imageURL = URL(string: s) }
            var additionalURLs: [URL] = []
            if let arr = data["additionalImageURLs"] as? [String] {
                additionalURLs = arr.compactMap { URL(string: $0) }
            }

            return MarketplaceDTO(
                id: id, owner: owner, title: title, description: description, price: price, category: category,
                condition: condition, date: date, contact: contact, isSold: isSold, soldDate: soldDate,
                isNegotiable: isNegotiable, tags: tags, location: location, imageURL: imageURL,
                additionalImageURLs: additionalURLs)
        }

        struct MarketplaceDTO {
            let id: UUID
            let owner: String
            let title: String
            let description: String
            let price: Double
            let category: String
            let condition: ItemCondition
            let date: Date
            let contact: String
            let isSold: Bool
            let soldDate: Date?
            let isNegotiable: Bool
            let tags: [String]
            let location: String
            let imageURL: URL?
            let additionalImageURLs: [URL]
        }

        func watchMarketplaceItems(onUpdate: @escaping ([MarketplaceDTO]) -> Void) {
            stopWatchingMarketplaceItems()
            let ref = db.collection("marketplace").order(by: "date", descending: true)
            marketplaceListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [MarketplaceDTO] = []
                for doc in snap.documents {
                    let d = doc.data()
                    if let dto = self.marketplaceItemFrom(data: d) { items.append(dto) }
                }
                onUpdate(items)
            }
        }

        func stopWatchingMarketplaceItems() {
            marketplaceListener?.remove()
            marketplaceListener = nil
        }

        // MARK: - Local Listings
        private var localListingsListener: ListenerRegistration?
        
        struct LocalListingDTO {
            let id: UUID
            let title: String
            let summary: String
            let content: String
            let author: String
            let authorEmail: String
            let authorUID: String?
            let date: Date
            let category: String  // NewsletterCategory rawValue
            let businessSubcategory: String?
            let advertSubcategory: String?
            let tags: [String]
            let isPublished: Bool
            let imageURL: URL?
            let imagesURLs: [URL]
            let fileURL: URL?
            var fileData: Data?
            var fileName: String?
            let contactName: String?
            let contactPhone: String?
            let isSold: Bool?
            let soldDate: Date?
        }
        
        private func localListingFrom(data: [String: Any]) -> LocalListingDTO? {
            guard let idStr = data["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let title = data["title"] as? String,
                  let summary = data["summary"] as? String,
                  let content = data["content"] as? String,
                  let author = data["author"] as? String,
                  let authorEmail = data["authorEmail"] as? String,
                  let category = data["category"] as? String
            else { return nil }
            
            let authorUID = data["authorUID"] as? String
            let businessSubcategory = data["businessSubcategory"] as? String
            let advertSubcategory = data["advertSubcategory"] as? String
            let tags = data["tags"] as? [String] ?? []
            let isPublished = data["isPublished"] as? Bool ?? true
            let contactName = data["contactName"] as? String
            let contactPhone = data["contactPhone"] as? String
            let isSold = data["isSold"] as? Bool
            
            var date = Date()
            if let ts = data["date"] as? Timestamp {
                date = ts.dateValue()
            }
            
            var soldDate: Date?
            if let soldTs = data["soldDate"] as? Timestamp {
                soldDate = soldTs.dateValue()
            }
            
            var imageURL: URL?
            if let urlStr = data["imageURL"] as? String {
                imageURL = URL(string: urlStr)
            }
            
            var imagesURLs: [URL] = []
            if let urlStrs = data["imagesURLs"] as? [String] {
                imagesURLs = urlStrs.compactMap { URL(string: $0) }
            }
            
            var fileURL: URL? = nil
            var fileData: Data? = nil
            var fileName: String? = nil
            
            fileName = data["fileName"] as? String
            
            // Hybrid approach: Check for file in multiple storage methods (WhatsApp-style)
            
            // Method 1: Firebase Storage URL (PREFERRED for large files)
            #if canImport(FirebaseStorage)
            if let storageURLString = data["fileStorageURL"] as? String {
                print("☁️ FirebaseManager: Found local listing file in Firebase Storage: \(fileName ?? "unknown")")
                
                if let fileName = fileName {
                    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let cachedFile = cacheDir.appendingPathComponent("localListings/\(id.uuidString)/\(fileName)")
                    
                    if FileManager.default.fileExists(atPath: cachedFile.path) {
                        fileURL = cachedFile
                        print("✅ FirebaseManager: Using cached file at: \(cachedFile.path)")
                    } else {
                        print("⬇️ FirebaseManager: Downloading local listing file from Storage to cache...")
                        if let storageRef = self.storageReference(fromDownloadURLString: storageURLString) {
                            try? FileManager.default.createDirectory(at: cachedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                            
                            storageRef.write(toFile: cachedFile) { url, error in
                                if let error = error {
                                    print("❌ FirebaseManager: Failed to download local listing file: \(error.localizedDescription)")
                                } else {
                                    print("✅ FirebaseManager: Local listing file downloaded to cache: \(cachedFile.path)")
                                    NotificationCenter.default.post(name: NSNotification.Name("LocalListingFileDownloaded"), object: nil, userInfo: ["listingId": id.uuidString])
                                }
                            }
                        }
                        print("⏳ FirebaseManager: Download in progress, fileURL will be set after completion")
                    }
                }
            }
            #endif
            
            // Method 2: Direct Firestore base64 data (for small files)
            if fileURL == nil, let fileDataString = data["fileData"] as? String,
               let decodedData = Data(base64Encoded: fileDataString) {
                fileData = decodedData
                let fileSize = data["fileSize"] as? Int ?? decodedData.count
                print("📦 FirebaseManager: Found local listing file data in Firestore (\(fileSize) bytes)")
                
                if let fileName = fileName {
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempFile = tempDir.appendingPathComponent("locallisting_\(id.uuidString)_\(fileName)")
                    
                    do {
                        try decodedData.write(to: tempFile)
                        fileURL = tempFile
                        print("✅ FirebaseManager: Created temp file from Firestore data: \(tempFile.path)")
                    } catch {
                        print("❌ FirebaseManager: Error creating temp file: \(error)")
                    }
                }
            }
            // Method 3: Legacy fileURL (backwards compatibility)
            else if fileURL == nil, let fileURLString = data["fileURL"] as? String, let url = URL(string: fileURLString) {
                fileURL = url
                print("⚠️ FirebaseManager: Found legacy fileURL (may not work on other devices): \(url.lastPathComponent)")
            }
            
            if fileURL == nil && fileData == nil {
                print("ℹ️ FirebaseManager: No file attachment found for local listing")
            }
            
            var listing = LocalListingDTO(
                id: id, title: title, summary: summary, content: content,
                author: author, authorEmail: authorEmail, authorUID: authorUID,
                date: date, category: category, businessSubcategory: businessSubcategory,
                advertSubcategory: advertSubcategory, tags: tags, isPublished: isPublished,
                imageURL: imageURL, imagesURLs: imagesURLs, fileURL: fileURL,
                contactName: contactName, contactPhone: contactPhone, isSold: isSold, soldDate: soldDate
            )
            listing.fileData = fileData
            listing.fileName = fileName
            return listing
        }
        
        func watchLocalListings(onUpdate: @escaping ([LocalListingDTO]) -> Void) {
            print("FirebaseManager: Setting up localListings listener")
            stopWatchingLocalListings()
            let ref = db.collection("localListings").order(by: "date", descending: true)
            localListingsListener = ref.addSnapshotListener { snap, error in
                if let error = error {
                    print("FirebaseManager: Error watching localListings: \(error)")
                    onUpdate([])
                    return
                }
                guard let snap = snap else {
                    print("FirebaseManager: No snapshot for localListings")
                    onUpdate([])
                    return
                }
                print("FirebaseManager: Received \(snap.documents.count) localListings documents")
                var items: [LocalListingDTO] = []
                for doc in snap.documents {
                    let d = doc.data()
                    if let dto = self.localListingFrom(data: d) { 
                        items.append(dto) 
                        print("FirebaseManager: Successfully parsed listing: \(dto.title)")
                    } else {
                        print("FirebaseManager: Failed to parse document: \(doc.documentID)")
                    }
                }
                print("FirebaseManager: Calling onUpdate with \(items.count) parsed items")
                onUpdate(items)
            }
        }
        
        func stopWatchingLocalListings() {
            localListingsListener?.remove()
            localListingsListener = nil
        }
        
        func createOrUpdateLocalListing(
            _ listing: LocalListingDTO, primaryImageData: Data?, additionalImageData: [Data],
            completion: ((Error?) -> Void)? = nil
        ) {
            let ref = db.collection("localListings").document(listing.id.uuidString)
            
            var dict: [String: Any] = [
                "id": listing.id.uuidString,
                "title": listing.title,
                "summary": listing.summary,
                "content": listing.content,
                "author": listing.author,
                "authorEmail": listing.authorEmail,
                "date": Timestamp(date: listing.date),
                "category": listing.category,
                "tags": listing.tags,
                "isPublished": listing.isPublished
            ]
            
            if let authorUID = listing.authorUID {
                dict["authorUID"] = authorUID
            }
            if let businessSubcategory = listing.businessSubcategory {
                dict["businessSubcategory"] = businessSubcategory
            }
            if let advertSubcategory = listing.advertSubcategory {
                dict["advertSubcategory"] = advertSubcategory
            }
            if let contactName = listing.contactName {
                dict["contactName"] = contactName
            }
            if let contactPhone = listing.contactPhone {
                dict["contactPhone"] = contactPhone
            }
            if let isSold = listing.isSold {
                dict["isSold"] = isSold
            }
            if let soldDate = listing.soldDate {
                dict["soldDate"] = Timestamp(date: soldDate)
            }
            
            // Handle file attachment using hybrid approach (like WhatsApp):
            // 1. Small files (<1MB) stored in Firestore as base64
            // 2. Large files uploaded to Firebase Storage
            #if canImport(FirebaseStorage)
            if let fileData = listing.fileData, let fileName = listing.fileName {
                let fileSizeInBytes = fileData.count
                let fileSizeInMB = Double(fileSizeInBytes) / 1024.0 / 1024.0
                let threshold = 1024 * 1024 // 1MB
                
                print("📄 FirebaseManager: Processing local listing file attachment:")
                print("   - File name: \(fileName)")
                let fileSizeMBString = String(format: "%.2f", fileSizeInMB)
                print("   - File size: \(fileSizeInBytes) bytes (\(fileSizeMBString) MB)")
                let storageMethod = fileSizeInBytes <= threshold ? "Firestore (base64)" : "Firebase Storage"
                print("   - Will use: \(storageMethod)")
                
                if fileSizeInBytes <= threshold {
                    dict["fileData"] = fileData.base64EncodedString()
                    dict["fileName"] = fileName
                    dict["fileSize"] = fileSizeInBytes
                    print("📦 FirebaseManager: Storing small file directly in Firestore")
                } else {
                    print("☁️ FirebaseManager: File EXCEEDS 1MB threshold, uploading to Firebase Storage...")
                    let storagePath = "localListings/\(listing.id.uuidString)/\(fileName)"
                    
                    uploadDataWithRetry(fileData, path: storagePath, retries: 3) { url, error in
                        if let error = error {
                            print("❌ FirebaseManager: Failed to upload local listing file after retries: \(error.localizedDescription)")
                            if fileData.count <= 1024 * 1024 {
                                dict["fileData"] = fileData.base64EncodedString()
                                dict["fileName"] = fileName
                                dict["fileSize"] = fileData.count
                                print("⚠️ FirebaseManager: Falling back to Firestore storage")
                            }
                        } else if let url = url {
                            dict["fileStorageURL"] = url.absoluteString
                            dict["fileName"] = fileName
                            dict["fileSize"] = fileData.count
                            print("✅ FirebaseManager: Successfully uploaded local listing file to Storage")
                        }
                        
                        // Continue with image uploads after file upload completes
                        self.handleImageUploadsForLocalListing(listing: listing, primaryImageData: primaryImageData, additionalImageData: additionalImageData, dict: dict, ref: ref, completion: completion)
                    }
                    return // Exit early, continuation handled in callback
                }
            }
            #else
            if let fileData = listing.fileData, let fileName = listing.fileName {
                if fileData.count <= 1024 * 1024 {
                    dict["fileData"] = fileData.base64EncodedString()
                    dict["fileName"] = fileName
                    dict["fileSize"] = fileData.count
                }
            }
            #endif
            
            // Proceed with image uploads (for small files or no attachment)
            handleImageUploadsForLocalListing(listing: listing, primaryImageData: primaryImageData, additionalImageData: additionalImageData, dict: dict, ref: ref, completion: completion)
        }
        
        private func handleImageUploadsForLocalListing(
            listing: LocalListingDTO, primaryImageData: Data?, additionalImageData: [Data],
            dict: [String: Any], ref: DocumentReference, completion: ((Error?) -> Void)?
        ) {
            var mutableDict = dict // Create a mutable copy
            
            // Handle image uploads to Firebase Storage
            if let primaryData = primaryImageData {
                let imagePath = "localListings/\(listing.id.uuidString)/primary.jpg"
                uploadImageToStorage(data: primaryData, path: imagePath) { [weak self] imageURL in
                    if let imageURL = imageURL {
                        mutableDict["imageURL"] = imageURL.absoluteString
                    }
                    
                    // Handle additional images
                    if !additionalImageData.isEmpty {
                        self?.uploadMultipleImagesToStorage(imagesData: additionalImageData, basePath: "localListings/\(listing.id.uuidString)/additional") { additionalURLs in
                            mutableDict["imagesURLs"] = additionalURLs.map { $0.absoluteString }
                            ref.setData(mutableDict) { error in
                                completion?(error)
                            }
                        }
                    } else {
                        ref.setData(mutableDict) { error in
                            completion?(error)
                        }
                    }
                }
            } else if !additionalImageData.isEmpty {
                uploadMultipleImagesToStorage(imagesData: additionalImageData, basePath: "localListings/\(listing.id.uuidString)/additional") { additionalURLs in
                    mutableDict["imagesURLs"] = additionalURLs.map { $0.absoluteString }
                    ref.setData(mutableDict) { error in
                        completion?(error)
                    }
                }
            } else {
                // No images to upload
                ref.setData(mutableDict) { error in
                    completion?(error)
                }
            }
        }
        
        func deleteLocalListing(id: String, completion: ((Error?) -> Void)? = nil) {
            #if canImport(FirebaseStorage)
            // Step 1: Delete all files from Firebase Storage (same as newsletters)
            let storageRef = storage.reference().child("localListings/\(id)")
            storageRef.listAll { result, error in
                if let error = error {
                    print("FirebaseManager: Error listing files for local listing \(id): \(error)")
                } else if let result = result {
                    print("FirebaseManager: Found \(result.items.count) storage files for local listing \(id)")
                    
                    // Delete all files in the folder
                    let deleteGroup = DispatchGroup()
                    for item in result.items {
                        deleteGroup.enter()
                        item.delete { error in
                            if let error = error {
                                print("FirebaseManager: Error deleting storage file \(item.fullPath): \(error)")
                            } else {
                                print("FirebaseManager: Successfully deleted storage file: \(item.fullPath)")
                            }
                            deleteGroup.leave()
                        }
                    }
                    
                    deleteGroup.notify(queue: .main) {
                        // Step 2: Delete from cache
                        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("localListings/\(id)")
                        try? FileManager.default.removeItem(at: cacheURL)
                        print("FirebaseManager: Cleaned up cache for local listing \(id)")
                        
                        // Step 3: Delete Firestore document
                        self.db.collection("localListings").document(id).delete { error in
                            if let error = error {
                                print("FirebaseManager: Error deleting local listing document \(id): \(error)")
                            } else {
                                print("FirebaseManager: Successfully deleted local listing \(id)")
                            }
                            completion?(error)
                        }
                    }
                }
            }
            #else
            // No Storage available, just delete the document
            db.collection("localListings").document(id).delete { error in
                completion?(error)
            }
            #endif
        }
        
        // MARK: - Local Listings Image Upload Helpers
        private func uploadImageToStorage(data: Data, path: String, completion: @escaping (URL?) -> Void) {
            #if canImport(FirebaseStorage)
            print("FirebaseManager: Starting image upload to path: \(path), size: \(data.count) bytes")
            let storageRef = storage.reference().child(path)
            storageRef.putData(data, metadata: nil) { metadata, error in
                if let error = error {
                    print("FirebaseManager: Error uploading image to \(path): \(error)")
                    completion(nil)
                    return
                }
                
                print("FirebaseManager: Image uploaded successfully, getting download URL for \(path)")
                storageRef.downloadURL { url, error in
                    if let error = error {
                        print("FirebaseManager: Error getting download URL for \(path): \(error)")
                        completion(nil)
                    } else {
                        print("FirebaseManager: Successfully got download URL for \(path): \(url?.absoluteString ?? "nil")")
                        completion(url)
                    }
                }
            }
            #else
            completion(nil)
            #endif
        }
        
        private func uploadMultipleImagesToStorage(imagesData: [Data], basePath: String, completion: @escaping ([URL]) -> Void) {
            guard !imagesData.isEmpty else {
                completion([])
                return
            }
            
            var uploadedURLs: [URL] = []
            let group = DispatchGroup()
            
            for (index, imageData) in imagesData.enumerated() {
                group.enter()
                let imagePath = "\(basePath)_\(index).jpg"
                uploadImageToStorage(data: imageData, path: imagePath) { url in
                    if let url = url {
                        uploadedURLs.append(url)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(uploadedURLs)
            }
        }
        
        /// Create or update a marketplace item. Uploads primary and additional images to Storage when available.
        func createOrUpdateMarketplaceItem(
            _ item: MarketplaceDTO, primaryImageData: Data?, additionalImageData: [Data],
            completion: ((Error?) -> Void)? = nil
        ) {
            let ref = db.collection("marketplace").document(item.id.uuidString)

            // Minimal Firestore metadata
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "owner": item.owner,
                "title": item.title,
                "description": item.description,
                "price": item.price,
                "category": item.category,
                "condition": item.condition.rawValue,
                "date": Timestamp(date: item.date),
                "contact": item.contact,
                "isSold": item.isSold,
                "soldDate": item.soldDate.map { Timestamp(date: $0) } ?? NSNull(),
                "isNegotiable": item.isNegotiable,
                "tags": item.tags,
                "location": item.location,
            ]

            // LOCAL-FIRST: persist a lightweight local DTO and save images to disk
            struct LocalMarketItem: Codable, Identifiable {
                let id: UUID
                let owner: String
                let title: String
                let description: String
                let price: Double
                let category: String
                let condition: String
                let date: Date
                let contact: String
                let isSold: Bool
                let soldDate: Date?
                var imageLocalPath: String?
                var additionalLocalPaths: [String]?
                var lastUploadAttempt: Date?
                var uploadRetryCount: Int
            }

            var local = LocalMarketItem(
                id: item.id, owner: item.owner, title: item.title, description: item.description,
                price: item.price, category: item.category, condition: item.condition.rawValue,
                date: item.date, contact: item.contact, isSold: item.isSold, soldDate: item.soldDate,
                imageLocalPath: nil, additionalLocalPaths: nil,
                lastUploadAttempt: Date(), uploadRetryCount: 0)

            // Save primary image to ImageCache if available
            if let data = primaryImageData {
                if let saved = try? ImageCacheManager.shared.saveData(data, forMessage: item.id) {
                    local.imageLocalPath = saved
                }
            }

            // Save additional images to Application Support
            if !additionalImageData.isEmpty {
                var paths: [String] = []
                for (i, d) in additionalImageData.enumerated() {
                    let fname = "market-\(item.id.uuidString)-additional_\(i).jpg"
                    if let p = saveFileToApplicationSupport(data: d, filename: fname) {
                        paths.append(p)
                    }
                }
                if !paths.isEmpty { local.additionalLocalPaths = paths }
            }

            // Persist locally for UI and offline
            upsertLocalCodableArray(local, key: "marketplaceData")

            // Enhanced attachment tracking with metadata
            var attachmentsCount = 0
            if primaryImageData != nil || local.imageLocalPath != nil { attachmentsCount += 1 }
            attachmentsCount += additionalImageData.count
            if let lp = local.additionalLocalPaths { attachmentsCount += lp.count }

            if attachmentsCount > 0 {
                dict["attachmentsCount"] = attachmentsCount
                dict["attachmentsPendingUpload"] = true
                dict["attachmentMetadata"] = [
                    "uploadStarted": Timestamp(date: Date()),
                    "expectedCount": attachmentsCount,
                    "retryCount": 0,
                ]
            }

            ref.setData(dict, merge: true) { err in
                completion?(err)
            }

            #if canImport(FirebaseStorage)
                // Enhanced background uploads with better error handling
                DispatchQueue.global(qos: .utility).async {
                    let _ = Auth.auth().currentUser?.uid ?? "anon"
                    var uploadTasks: [StorageUploadTask] = []
                    let uploadGroup = DispatchGroup()

                    if let data = primaryImageData {
                        uploadGroup.enter()
                        // Upload directly to marketplace/{itemId}/ so it's publicly readable per storage rules
                        let path = "marketplace/\(item.id.uuidString)/image.jpg"
                        let refStorage = self.storage.reference().child(path)
                        self.ensureSignedIn { signInErr in
                            if let signInErr = signInErr {
                                print(
                                    "FirebaseManager: sign-in error before marketplace primary upload: \(signInErr)"
                                )
                                uploadGroup.leave()
                                return
                            }

                            let metadata = StorageMetadata()
                            metadata.contentType = "image/jpeg"
                            metadata.customMetadata = [
                                "itemId": item.id.uuidString,
                                "attachmentType": "primary",
                                "uploadTimestamp": "\(Date().timeIntervalSince1970)",
                            ]

                            let task = refStorage.putData(data, metadata: metadata)
                            uploadTasks.append(task)

                            // Enhanced progress tracking
                            task.observe(.progress) { snapshot in
                                let progress =
                                    Double(snapshot.progress?.completedUnitCount ?? 0)
                                    / Double(snapshot.progress?.totalUnitCount ?? 1)
                                NotificationCenter.default.post(
                                    name: .marketplaceUploadProgress, object: nil,
                                    userInfo: [
                                        "id": item.id.uuidString,
                                        "type": "image",
                                        "progress": progress,
                                        "timestamp": Date(),
                                    ])
                            }

                            task.observe(.success) { _ in
                                self.downloadURLWithRetries(from: refStorage, attempts: 3) {
                                    url, err in
                                    if let url = url {
                                        ref.setData(
                                            [
                                                "imageURL": url.absoluteString,
                                                "attachmentsPendingUpload": false,
                                                "attachmentMetadata.primaryUploaded": Timestamp(
                                                    date: Date()),
                                            ], merge: true)

                                        NotificationCenter.default.post(
                                            name: .marketplaceUploadCompleted, object: nil,
                                            userInfo: [
                                                "id": item.id.uuidString,
                                                "type": "image",
                                                "success": true,
                                                "url": url.absoluteString,
                                            ])
                                    }
                                    uploadGroup.leave()
                                }
                            }

                            task.observe(.failure) { snapshot in
                                let error =
                                    snapshot.error
                                    ?? NSError(
                                        domain: "FirebaseManager", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
                                NotificationCenter.default.post(
                                    name: .marketplaceUploadCompleted, object: nil,
                                    userInfo: [
                                        "id": item.id.uuidString,
                                        "type": "image",
                                        "error": error.localizedDescription,
                                    ])
                                uploadGroup.leave()
                            }
                        }
                    } else if let localPath = local.imageLocalPath {
                        uploadGroup.enter()
                        let fileURL = URL(fileURLWithPath: localPath)
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            // Upload directly to marketplace/{itemId}/ so it's publicly readable per storage rules
                            let path = "marketplace/\(item.id.uuidString)/image.jpg"
                            let refStorage = self.storage.reference().child(path)
                            self.ensureSignedIn { signInErr in
                                if let signInErr = signInErr {
                                    print(
                                        "FirebaseManager: sign-in error before marketplace primary file upload: \(signInErr)"
                                    )
                                    uploadGroup.leave()
                                    return
                                }

                                let metadata = StorageMetadata()
                                metadata.contentType = "image/jpeg"
                                metadata.customMetadata = [
                                    "itemId": item.id.uuidString,
                                    "attachmentType": "primary",
                                    "uploadTimestamp": "\(Date().timeIntervalSince1970)",
                                    "sourceType": "localFile",
                                ]

                                let task = refStorage.putFile(from: fileURL, metadata: metadata)
                                uploadTasks.append(task)

                                task.observe(.progress) { snapshot in
                                    let progress =
                                        Double(snapshot.progress?.completedUnitCount ?? 0)
                                        / Double(snapshot.progress?.totalUnitCount ?? 1)
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadProgress, object: nil,
                                        userInfo: [
                                            "id": item.id.uuidString,
                                            "type": "image",
                                            "progress": progress,
                                            "timestamp": Date(),
                                        ])
                                }

                                task.observe(.success) { _ in
                                    self.downloadURLWithRetries(from: refStorage, attempts: 3) {
                                        url, err in
                                        if let url = url {
                                            ref.setData(
                                                [
                                                    "imageURL": url.absoluteString,
                                                    "attachmentsPendingUpload": false,
                                                    "attachmentMetadata.primaryUploaded": Timestamp(
                                                        date: Date()),
                                                ], merge: true)

                                            NotificationCenter.default.post(
                                                name: .marketplaceUploadCompleted, object: nil,
                                                userInfo: [
                                                    "id": item.id.uuidString,
                                                    "type": "image",
                                                    "success": true,
                                                    "url": url.absoluteString,
                                                ])
                                        }
                                        uploadGroup.leave()
                                    }
                                }

                                task.observe(.failure) { snapshot in
                                    let error =
                                        snapshot.error
                                        ?? NSError(
                                            domain: "FirebaseManager", code: -1,
                                            userInfo: [
                                                NSLocalizedDescriptionKey: "File upload failed"
                                            ])
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadCompleted, object: nil,
                                        userInfo: [
                                            "id": item.id.uuidString,
                                            "type": "image",
                                            "error": error.localizedDescription,
                                        ])
                                    uploadGroup.leave()
                                }
                            }
                        } else {
                            uploadGroup.leave()
                        }
                    }

                    // Upload additional images with enhanced tracking
                    if !additionalImageData.isEmpty {
                        for (i, d) in additionalImageData.enumerated() {
                            uploadGroup.enter()
                            // Upload directly to marketplace/{itemId}/ so it's publicly readable per storage rules
                            let path = "marketplace/\(item.id.uuidString)/additional_\(i).jpg"
                            let refStorage = self.storage.reference().child(path)
                            let attachmentKey = "additional_\(i)"

                            self.ensureSignedIn { signInErr in
                                if let signInErr = signInErr {
                                    print(
                                        "FirebaseManager: sign-in error before marketplace additional upload: \(signInErr)"
                                    )
                                    uploadGroup.leave()
                                    return
                                }

                                let metadata = StorageMetadata()
                                metadata.contentType = "image/jpeg"
                                metadata.customMetadata = [
                                    "itemId": item.id.uuidString,
                                    "attachmentType": "additional",
                                    "attachmentIndex": "\(i)",
                                    "uploadTimestamp": "\(Date().timeIntervalSince1970)",
                                ]

                                let task = refStorage.putData(d, metadata: metadata)
                                uploadTasks.append(task)

                                task.observe(.progress) { snapshot in
                                    let progress =
                                        Double(snapshot.progress?.completedUnitCount ?? 0)
                                        / Double(snapshot.progress?.totalUnitCount ?? 1)
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadProgress, object: nil,
                                        userInfo: [
                                            "id": item.id.uuidString,
                                            "type": attachmentKey,
                                            "progress": progress,
                                            "timestamp": Date(),
                                        ])
                                }

                                task.observe(.success) { _ in
                                    self.downloadURLWithRetries(from: refStorage, attempts: 3) {
                                        url, err in
                                        if let url = url {
                                            ref.getDocument { snap, _ in
                                                var arr =
                                                    snap?.data()?["additionalImageURLs"]
                                                    as? [String] ?? []

                                                // Ensure array is properly sized and insert at correct index
                                                while arr.count <= i { arr.append("") }
                                                arr[i] = url.absoluteString

                                                ref.setData(
                                                    [
                                                        "additionalImageURLs": arr,
                                                        "attachmentMetadata.additional_\(i)_uploaded":
                                                            Timestamp(date: Date()),
                                                    ], merge: true)

                                                NotificationCenter.default.post(
                                                    name: .marketplaceUploadCompleted, object: nil,
                                                    userInfo: [
                                                        "id": item.id.uuidString,
                                                        "type": attachmentKey,
                                                        "success": true,
                                                        "url": url.absoluteString,
                                                        "index": i,
                                                    ])
                                            }
                                        }
                                        uploadGroup.leave()
                                    }
                                }

                                task.observe(.failure) { snapshot in
                                    let error =
                                        snapshot.error
                                        ?? NSError(
                                            domain: "FirebaseManager", code: -1,
                                            userInfo: [
                                                NSLocalizedDescriptionKey:
                                                    "Additional image upload failed"
                                            ])
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadCompleted, object: nil,
                                        userInfo: [
                                            "id": item.id.uuidString,
                                            "type": attachmentKey,
                                            "error": error.localizedDescription,
                                            "index": i,
                                        ])
                                    uploadGroup.leave()
                                }
                            }
                        }
                    } else if let paths = local.additionalLocalPaths {
                        for (i, p) in paths.enumerated() {
                            uploadGroup.enter()
                            let fileURL = URL(fileURLWithPath: p)
                            let attachmentKey = "additional_\(i)"

                            if FileManager.default.fileExists(atPath: fileURL.path) {
                                // Upload directly to marketplace/{itemId}/ so it's publicly readable per storage rules
                                let path = "marketplace/\(item.id.uuidString)/additional_\(i).jpg"
                                let refStorage = self.storage.reference().child(path)

                                self.ensureSignedIn { signInErr in
                                    if let signInErr = signInErr {
                                        print(
                                            "FirebaseManager: sign-in error before marketplace additional file upload: \(signInErr)"
                                        )
                                        uploadGroup.leave()
                                        return
                                    }

                                    let metadata = StorageMetadata()
                                    metadata.contentType = "image/jpeg"
                                    metadata.customMetadata = [
                                        "itemId": item.id.uuidString,
                                        "attachmentType": "additional",
                                        "attachmentIndex": "\(i)",
                                        "uploadTimestamp": "\(Date().timeIntervalSince1970)",
                                        "sourceType": "localFile",
                                    ]

                                    let task = refStorage.putFile(from: fileURL, metadata: metadata)
                                    uploadTasks.append(task)

                                    task.observe(.progress) { snapshot in
                                        let progress =
                                            Double(snapshot.progress?.completedUnitCount ?? 0)
                                            / Double(snapshot.progress?.totalUnitCount ?? 1)
                                        NotificationCenter.default.post(
                                            name: .marketplaceUploadProgress, object: nil,
                                            userInfo: [
                                                "id": item.id.uuidString,
                                                "type": attachmentKey,
                                                "progress": progress,
                                                "timestamp": Date(),
                                            ])
                                    }

                                    task.observe(.success) { _ in
                                        self.downloadURLWithRetries(from: refStorage, attempts: 3) {
                                            url, err in
                                            if let url = url {
                                                ref.getDocument { snap, _ in
                                                    var arr =
                                                        snap?.data()?["additionalImageURLs"]
                                                        as? [String] ?? []

                                                    // Ensure array is properly sized and insert at correct index
                                                    while arr.count <= i { arr.append("") }
                                                    arr[i] = url.absoluteString

                                                    ref.setData(
                                                        [
                                                            "additionalImageURLs": arr,
                                                            "attachmentMetadata.additional_\(i)_uploaded":
                                                                Timestamp(date: Date()),
                                                        ], merge: true)

                                                    NotificationCenter.default.post(
                                                        name: .marketplaceUploadCompleted,
                                                        object: nil,
                                                        userInfo: [
                                                            "id": item.id.uuidString,
                                                            "type": attachmentKey,
                                                            "success": true,
                                                            "url": url.absoluteString,
                                                            "index": i,
                                                        ])
                                                }
                                            }
                                            uploadGroup.leave()
                                        }
                                    }

                                    task.observe(.failure) { snapshot in
                                        let error =
                                            snapshot.error
                                            ?? NSError(
                                                domain: "FirebaseManager", code: -1,
                                                userInfo: [
                                                    NSLocalizedDescriptionKey:
                                                        "Additional file upload failed"
                                                ])
                                        NotificationCenter.default.post(
                                            name: .marketplaceUploadCompleted, object: nil,
                                            userInfo: [
                                                "id": item.id.uuidString,
                                                "type": attachmentKey,
                                                "error": error.localizedDescription,
                                                "index": i,
                                            ])
                                        uploadGroup.leave()
                                    }
                                }
                            } else {
                                uploadGroup.leave()
                            }
                        }
                    }

                    // When all uploads complete, mark attachment upload as finished
                    uploadGroup.notify(queue: .main) {
                        ref.setData(
                            [
                                "attachmentsPendingUpload": false,
                                "attachmentMetadata.allUploadsCompleted": Timestamp(date: Date()),
                            ], merge: true)
                    }
                }
            #endif
        }

        /// Re-upload a single marketplace attachment (primary image or an additional image) and update the Firestore document.
        /// - Parameters:
        ///   - itemId: document id (uuid string)
        ///   - attachmentKey: "image" or "additional_<index>"
        ///   - index: optional index for additional attachments
        ///   - data: the raw image data to upload
        ///   - completion: completion with optional error
        func reuploadMarketplaceAttachment(
            itemId: String, attachmentKey: String, index: Int? = nil, data: Data,
            completion: ((Error?) -> Void)? = nil
        ) {
            #if canImport(FirebaseStorage)
                let storagePath: String
                if attachmentKey == "image" {
                    storagePath = "marketplace/\(itemId)/image.jpg"
                } else if attachmentKey.starts(with: "additional_") {
                    let idx = index ?? 0
                    storagePath = "marketplace/\(itemId)/additional_\(idx).jpg"
                } else {
                    // unknown key
                    completion?(
                        NSError(
                            domain: "FirebaseManager", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown attachment key"]))
                    return
                }

                let refStorage = storage.reference().child(storagePath)
                let uploadTask = refStorage.putData(data, metadata: nil)
                // progress notifications
                uploadTask.observe(.progress) { snap in
                    let fraction = snap.progress?.fractionCompleted ?? 0
                    NotificationCenter.default.post(
                        name: .marketplaceUploadProgress, object: nil,
                        userInfo: ["id": itemId, "type": attachmentKey, "progress": fraction])
                }
                uploadTask.observe(.success) { _ in
                    // use resilient downloadURL fetch
                    self.downloadURLWithRetries(from: refStorage) { url, err in
                        if let err = err {
                            NotificationCenter.default.post(
                                name: .marketplaceUploadCompleted, object: nil,
                                userInfo: ["id": itemId, "type": attachmentKey, "error": err])
                            completion?(err)
                            return
                        }
                        guard let url = url else {
                            let e =
                                NSError(
                                    domain: "FirebaseManager", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "No download URL"])
                                as Error
                            NotificationCenter.default.post(
                                name: .marketplaceUploadCompleted, object: nil,
                                userInfo: ["id": itemId, "type": attachmentKey, "error": e])
                            completion?(e)
                            return
                        }

                        // Update Firestore document with the new URL
                        let docRef = self.db.collection("marketplace").document(itemId)
                        docRef.getDocument { snap, getErr in
                            if let getErr = getErr {
                                NotificationCenter.default.post(
                                    name: .marketplaceUploadCompleted, object: nil,
                                    userInfo: [
                                        "id": itemId, "type": attachmentKey, "error": getErr,
                                    ])
                                completion?(getErr)
                                return
                            }
                            var updateData: [String: Any] = [:]
                            if attachmentKey == "image" {
                                updateData["imageURL"] = url.absoluteString
                            } else {
                                // update additionalImageURLs array: attempt to replace index if present, otherwise append
                                var arr = snap?.data()?["additionalImageURLs"] as? [String] ?? []
                                let idx = index ?? arr.count
                                if idx < arr.count {
                                    arr[idx] = url.absoluteString
                                } else {
                                    // append up to the index
                                    if idx == arr.count {
                                        arr.append(url.absoluteString)
                                    } else {
                                        // fill missing slots with empty strings then set
                                        while arr.count < idx { arr.append("") }
                                        arr.append(url.absoluteString)
                                    }
                                }
                                updateData["additionalImageURLs"] = arr
                            }
                            docRef.setData(updateData, merge: true) { setErr in
                                if let setErr = setErr {
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadCompleted, object: nil,
                                        userInfo: [
                                            "id": itemId, "type": attachmentKey, "error": setErr,
                                        ])
                                    completion?(setErr)
                                } else {
                                    NotificationCenter.default.post(
                                        name: .marketplaceUploadCompleted, object: nil,
                                        userInfo: ["id": itemId, "type": attachmentKey])
                                    completion?(nil)
                                }
                            }
                        }
                    }
                }
                uploadTask.observe(.failure) { snap in
                    if let err = snap.error {
                        NotificationCenter.default.post(
                            name: .marketplaceUploadCompleted, object: nil,
                            userInfo: ["id": itemId, "type": attachmentKey, "error": err])
                        completion?(err)
                    } else {
                        let e =
                            NSError(
                                domain: "FirebaseManager", code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Upload failed"]) as Error
                        NotificationCenter.default.post(
                            name: .marketplaceUploadCompleted, object: nil,
                            userInfo: ["id": itemId, "type": attachmentKey, "error": e])
                        completion?(e)
                    }
                }
            #else
                // Storage not available
                completion?(
                    NSError(
                        domain: "FirebaseManager", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Storage not available"]))
            #endif
        }

        func deleteMarketplaceItem(id: String, completion: ((Error?) -> Void)? = nil) {
            let ref = db.collection("marketplace").document(id)
            ref.getDocument { snap, err in
                if err != nil {
                    ref.delete(completion: completion)
                    return
                }
                var urlsToDelete: [String] = []
                if let d = snap?.data() {
                    if let s = d["imageURL"] as? String { urlsToDelete.append(s) }
                    if let arr = d["additionalImageURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr)
                    }
                }
                let group = DispatchGroup()
                for u in urlsToDelete {
                    // Use safe helper to avoid crashes on invalid URLs
                    guard let storageRef = self.storageReference(fromDownloadURLString: u) else {
                        print("⚠️ Skipping invalid storage URL during marketplace deletion: \(u)")
                        continue
                    }
                    group.enter()
                    storageRef.delete { _ in group.leave() }
                }
                // Remove items under uploads/{uid}/marketplace/{id}, final/marketplace/{id}, and marketplace/{id}
                let uid = Auth.auth().currentUser?.uid ?? "anon"
                let prefixes = ["uploads/\(uid)/marketplace/\(id)", "final/marketplace/\(id)", "marketplace/\(id)"]
                for p in prefixes {
                    group.enter()
                    self.storage.reference().child(p).listAll { res, listErr in
                        if let items = res?.items {
                            let inner = DispatchGroup()
                            for it in items {
                                inner.enter()
                                it.delete { _ in inner.leave() }
                            }
                            inner.notify(queue: .main) { group.leave() }
                        } else {
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) { ref.delete(completion: completion) }
            }
        }

        /// Update only the isSold/soldDate fields for a marketplace item using merge/update semantics.
        /// This avoids re-uploading images or overwriting other fields when toggling sold state.
        func updateIsSold(
            itemId: String, isSold: Bool, soldDate: Date?, completion: ((Error?) -> Void)? = nil
        ) {
            let docRef = db.collection("marketplace").document(itemId)
            var updateData: [String: Any] = ["isSold": isSold]
            if let sd = soldDate {
                updateData["soldDate"] = Timestamp(date: sd)
            } else {
                // Remove the soldDate field when nil
                updateData["soldDate"] = FieldValue.delete()
            }
            docRef.setData(updateData, merge: true) { err in
                completion?(err)
            }
        }

        // MARK: - Local Adverts
        private var advertsListener: ListenerRegistration?

        private func advertFrom(data: [String: Any]) -> Advert? {
            guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
                let title = data["title"] as? String,
                let category = data["category"] as? String,
                let sellerName = data["sellerName"] as? String
            else { return nil }

            let summary = data["summary"] as? String ?? ""
            let price = data["price"] as? Double
            let currency = data["currency"] as? String ?? "USD"
            var imageData: Data? = nil
            if let b64 = data["imageData"] as? String, let d = Data(base64Encoded: b64) {
                imageData = d
            }
            var imageDatas: [Data]? = nil
            if let arr = data["imageDatas"] as? [String] {
                imageDatas = arr.compactMap { Data(base64Encoded: $0) }
            }
            // small metadata: imageCount and imagesPendingUpload
            let imageCount = data["imageCount"] as? Int
            let imagesPendingUpload = data["imagesPendingUpload"] as? Bool
            let locationName = data["locationName"] as? String
            let createdAt: Date = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let expiresAt: Date? = (data["expiresAt"] as? Timestamp)?.dateValue()
            let isPinned = data["isPinned"] as? Bool ?? false
            let sellerVerified = data["sellerVerified"] as? Bool ?? false
            let sellerContact = data["sellerContact"] as? String
            let sellerReputation = data["sellerReputation"] as? Double

            return Advert(
                id: id, title: title, summary: summary, price: price, currency: currency,
                imageData: imageData, imageDatas: imageDatas, imageLocalPath: nil,
                imageLocalPaths: nil, imageStorageURL: nil, imageStorageURLs: nil,
                imageCount: imageCount, imagesPendingUpload: imagesPendingUpload,
                category: category, locationName: locationName, createdAt: createdAt,
                expiresAt: expiresAt, isPinned: isPinned, sellerName: sellerName,
                sellerVerified: sellerVerified, sellerContact: sellerContact,
                sellerReputation: sellerReputation)
        }

        func watchAdverts(onUpdate: @escaping ([Advert]) -> Void) {
            stopWatchingAdverts()
            let ref = db.collection("localAdverts").order(by: "createdAt", descending: true)
            advertsListener = ref.addSnapshotListener { snap, error in
                guard error == nil, let snap = snap else {
                    onUpdate([])
                    return
                }
                var items: [Advert] = []
                let outerGroup = DispatchGroup()
                for doc in snap.documents {
                    outerGroup.enter()
                    let d = doc.data()
                    // Build base advert from data (this will pick up embedded base64 if present)
                    if var a = self.advertFrom(data: d) {
                        // If Firestore stored imageURL(s) instead, download them
                        if let imageURLString = d["imageURL"] as? String,
                            let imageURL = URL(string: imageURLString)
                        {
                            URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                                if let data = data { a.imageData = data }
                                // Additional images
                                if let arr = d["imageDatasURLs"] as? [String], !arr.isEmpty {
                                    let addGroup = DispatchGroup()
                                    var downloaded: [Data] = []
                                    for urlStr in arr {
                                        if let u = URL(string: urlStr) {
                                            addGroup.enter()
                                            URLSession.shared.dataTask(with: u) { dd, _, _ in
                                                if let dd = dd { downloaded.append(dd) }
                                                addGroup.leave()
                                            }.resume()
                                        }
                                    }
                                    addGroup.notify(queue: .main) {
                                        if !downloaded.isEmpty { a.imageDatas = downloaded }
                                        items.append(a)
                                        outerGroup.leave()
                                    }
                                } else {
                                    items.append(a)
                                    outerGroup.leave()
                                }
                            }.resume()
                        } else if let arr = d["imageDatasURLs"] as? [String], !arr.isEmpty {
                            // No primary URL but additional images present
                            let addGroup = DispatchGroup()
                            var downloaded: [Data] = []
                            for urlStr in arr {
                                if let u = URL(string: urlStr) {
                                    addGroup.enter()
                                    URLSession.shared.dataTask(with: u) { dd, _, _ in
                                        if let dd = dd { downloaded.append(dd) }
                                        addGroup.leave()
                                    }.resume()
                                }
                            }
                            addGroup.notify(queue: .main) {
                                if !downloaded.isEmpty { a.imageDatas = downloaded }
                                items.append(a)
                                outerGroup.leave()
                            }
                        } else {
                            // no remote URLs, deliver the advert as-is
                            items.append(a)
                            outerGroup.leave()
                        }
                    } else {
                        outerGroup.leave()
                    }
                }
                outerGroup.notify(queue: .main) { onUpdate(items) }
            }
        }

        func stopWatchingAdverts() {
            advertsListener?.remove()
            advertsListener = nil
        }

        func createOrUpdateAdvert(
            _ advert: Advert, completion: ((Error?, String?, [String]?) -> Void)? = nil
        ) {
            let ref = db.collection("localAdverts").document(advert.id.uuidString)

            // Build the base Firestore dict (minimal metadata only)
            var dict: [String: Any] = [
                "id": advert.id.uuidString,
                "title": advert.title,
                "summary": advert.summary,
                "price": advert.price ?? NSNull(),
                "currency": advert.currency,
                "category": advert.category,
                "locationName": advert.locationName ?? "",
                "createdAt": Timestamp(date: advert.createdAt),
                "expiresAt": advert.expiresAt != nil
                    ? Timestamp(date: advert.expiresAt!) : NSNull(),
                "isPinned": advert.isPinned,
                "sellerName": advert.sellerName,
                "sellerVerified": advert.sellerVerified,
            ]
            if let contact = advert.sellerContact { dict["sellerContact"] = contact }
            if let rep = advert.sellerReputation { dict["sellerReputation"] = rep }

            // LOCAL-FIRST: persist a sanitized local copy and save attachments to disk
            var sanitized = advert
            sanitized.imageData = nil
            sanitized.imageDatas = nil

            // Save primary image to ImageCache if present
            if sanitized.imageLocalPath == nil, let data = advert.imageData {
                if let saved = try? ImageCacheManager.shared.saveData(data, forMessage: advert.id) {
                    sanitized.imageLocalPath = saved
                }
            }

            // Save additional images to Application Support/NeighborHub/Files
            if sanitized.imageLocalPaths == nil, let datas = advert.imageDatas, !datas.isEmpty {
                var paths: [String] = []
                for (i, d) in datas.enumerated() {
                    let fname = "advert-\(advert.id.uuidString)-additional_\(i).jpg"
                    if let p = saveFileToApplicationSupport(data: d, filename: fname) {
                        paths.append(p)
                    }
                }
                if !paths.isEmpty { sanitized.imageLocalPaths = paths }
            }

            // Upsert into local AppStorage for immediate UI visibility and persistence
            upsertLocalCodableArray(sanitized, key: "advertsData")

            // Enhanced Firestore doc: record imageCount and indicate uploads are pending when attachments exist
            // Count unique local image sources to avoid double-counting when imageLocalPath
            // is also present inside imageLocalPaths (UI saves both). Use a Set to dedupe.
            var uniqueLocalPaths = Set<String>()
            if let p = advert.imageLocalPath { uniqueLocalPaths.insert(p) }
            if let ps = advert.imageLocalPaths {
                for p in ps { uniqueLocalPaths.insert(p) }
            }
            let localCount = uniqueLocalPaths.count
            let imageCount =
                (advert.imageData != nil ? 1 : 0) + (advert.imageDatas?.count ?? 0) + localCount
            if imageCount > 0 {
                dict["imageCount"] = imageCount
                dict["imagesPendingUpload"] = true
                dict["attachmentMetadata"] = [
                    "uploadStarted": Timestamp(date: Date()),
                    "expectedCount": imageCount,
                    "retryCount": 0,
                    "localPaths": Array(uniqueLocalPaths),
                ]
            }

            // Debug: log local attachment sources
            print(
                "FirebaseManager: createOrUpdateAdvert id=\(advert.id) imageCount=\(imageCount) localPaths=\(Array(uniqueLocalPaths)) imageDataCount=\(advert.imageDatas?.count ?? 0)"
            )

            // Write minimal Firestore doc immediately (merge to avoid clobbering fields)
            ref.setData(dict, merge: true) { err in
                // Return immediately after writing the minimal doc. Attachments will be uploaded in background.
                if err == nil {
                    print(
                        "FirebaseManager: wrote minimal advert doc id=\(advert.id) imagesPendingUpload=\(dict["imagesPendingUpload"] ?? false)"
                    )
                } else {
                    print(
                        "FirebaseManager: failed to write minimal advert doc id=\(advert.id) err=\(String(describing: err))"
                    )
                }
                completion?(err, nil, nil)
            }

            #if canImport(FirebaseStorage)
                // Enqueue upload via the persisted UploadQueueManager so uploads survive restarts.
                DispatchQueue.global(qos: .utility).async {
                    UploadQueueManager.shared.enqueueAdvertUpload(advert)
                }
            #endif
        }

        func deleteAdvert(id: String, completion: ((Error?) -> Void)? = nil) {
            // Ensure any pending queued uploads for this advert are removed before we delete Storage/docs.
            #if canImport(FirebaseStorage)
                UploadQueueManager.shared.removeTasks(for: id)
            #endif
            let ref = db.collection("localAdverts").document(id)
            ref.getDocument { [weak self] snap, err in
                guard let strongSelf = self else {
                    // If manager is gone, attempt to delete the document as a best-effort fallback.
                    ref.delete(completion: completion)
                    return
                }
                if err != nil {
                    ref.delete(completion: completion)
                    return
                }
                var urlsToDelete: [String] = []
                if let d = snap?.data() {
                    if let s = d["imageURL"] as? String { urlsToDelete.append(s) }
                    if let arr = d["imageDatasURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr)
                    }
                    if let arr2 = d["additionalImageURLs"] as? [String] {
                        urlsToDelete.append(contentsOf: arr2)
                    }
                }
                let group = DispatchGroup()
                for u in urlsToDelete {
                    // Use safe helper to avoid crashes on invalid URLs
                    guard let storageRef = strongSelf.storageReference(fromDownloadURLString: u) else {
                        print("⚠️ Skipping invalid storage URL during advert deletion: \(u)")
                        continue
                    }
                    group.enter()
                    storageRef.delete { _ in group.leave() }
                }
                // Also delete objects under staging/final prefixes (recursively, including nested prefixes).
                let uid = Auth.auth().currentUser?.uid ?? "anon"
                let prefixes = ["uploads/\(uid)/adverts/\(id)", "final/adverts/\(id)"]
                // recursive delete helper
                func deletePrefixRecursively(
                    _ path: String, _ completionPrefix: @escaping () -> Void
                ) {
                    let storageRef = strongSelf.storage.reference().child(path)
                    storageRef.listAll { res, listErr in
                        if listErr != nil {
                            // ignore individual errors but finish
                            completionPrefix()
                            return
                        }
                        let inner = DispatchGroup()
                        // delete files at this level
                        if let items = res?.items {
                            for it in items {
                                inner.enter()
                                it.delete { _ in inner.leave() }
                            }
                        }
                        // recurse into prefixes (subfolders)
                        if let prefixes = res?.prefixes, !prefixes.isEmpty {
                            for pref in prefixes {
                                inner.enter()
                                // StorageReference.fullPath gives the child path; recurse on that
                                deletePrefixRecursively(pref.fullPath) { inner.leave() }
                            }
                        }
                        inner.notify(queue: .main) { completionPrefix() }
                    }
                }

                for p in prefixes {
                    group.enter()
                    deletePrefixRecursively(p) { group.leave() }
                }
                group.notify(queue: .main) { ref.delete(completion: completion) }
            }
        }
        
        // MARK: - Emergency Contacts
        
        func watchEmergencyContacts(
            callback: @escaping ([EmergencyContactData]) -> Void
        ) {
            // Ensure user is authenticated
            if Auth.auth().currentUser == nil {
                Auth.auth().signInAnonymously { result, error in
                    if let error = error {
                        print("❌ FirebaseManager: Anonymous auth failed: \(error.localizedDescription)")
                        callback([])
                        return
                    }
                    self.watchEmergencyContactsInternal(callback: callback)
                }
                return
            }
            watchEmergencyContactsInternal(callback: callback)
        }
        
        // MARK: - Emergency Settings
        private var emergencySettingsListener: ListenerRegistration?
        private var emergencySettingsCallbacks: [(EmergencySettings) -> Void] = []
        
        func watchEmergencySettings(onUpdate: @escaping (EmergencySettings) -> Void) {
            // Add this callback to the list
            emergencySettingsCallbacks.append(onUpdate)
            print("👀 FirebaseManager: Added emergency settings watcher (total: \(emergencySettingsCallbacks.count))")
            
            // If listener doesn't exist yet, create it
            if emergencySettingsListener == nil {
                print("👀 FirebaseManager: Creating new Firestore listener for emergency settings")
                let ref = db.collection("emergencySettings").document("global")
                emergencySettingsListener = ref.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("❌ FirebaseManager: Error watching emergency settings: \(error.localizedDescription)")
                        let defaultSettings = EmergencySettings()
                        self.emergencySettingsCallbacks.forEach { $0(defaultSettings) }
                        return
                    }
                    
                    guard let data = snap?.data() else {
                        print("⚠️ FirebaseManager: No emergency settings found in Firestore, using default (911)")
                        let defaultSettings = EmergencySettings()
                        self.emergencySettingsCallbacks.forEach { $0(defaultSettings) }
                        return
                    }
                    
                    let fireNumber = data["fireNumber"] as? String ?? "911"
                    let emergencyNumber = data["emergencyNumber"] as? String ?? "911"
                    let medicalNumber = data["medicalNumber"] as? String ?? "911"
                    let updatedBy = data["updatedBy"] as? String ?? ""
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    print("📞 FirebaseManager: Received emergency settings update:")
                    print("   Fire Number: \(fireNumber)")
                    print("   Emergency Number: \(emergencyNumber)")
                    print("   Medical Number: \(medicalNumber)")
                    print("   Updated By: \(updatedBy)")
                    print("   Updated At: \(updatedAt)")
                    print("   Notifying \(self.emergencySettingsCallbacks.count) subscribers")
                    
                    let settings = EmergencySettings(
                        fireNumber: fireNumber,
                        emergencyNumber: emergencyNumber,
                        medicalNumber: medicalNumber,
                        updatedBy: updatedBy,
                        updatedAt: updatedAt
                    )
                    
                    // Notify all subscribers
                    self.emergencySettingsCallbacks.forEach { callback in
                        callback(settings)
                    }
                }
            } else {
                // Listener already exists, fetch current value and call the new callback
                print("👀 FirebaseManager: Listener already exists, fetching current value")
                let ref = db.collection("emergencySettings").document("global")
                ref.getDocument { snap, error in
                    if let data = snap?.data() {
                        let fireNumber = data["fireNumber"] as? String ?? "911"
                        let emergencyNumber = data["emergencyNumber"] as? String ?? "911"
                        let medicalNumber = data["medicalNumber"] as? String ?? "911"
                        let updatedBy = data["updatedBy"] as? String ?? ""
                        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                        
                        onUpdate(EmergencySettings(
                            fireNumber: fireNumber,
                            emergencyNumber: emergencyNumber,
                            medicalNumber: medicalNumber,
                            updatedBy: updatedBy,
                            updatedAt: updatedAt
                        ))
                    } else {
                        onUpdate(EmergencySettings())
                    }
                }
            }
        }
        
        func stopWatchingEmergencySettings() {
            emergencySettingsListener?.remove()
            emergencySettingsListener = nil
            emergencySettingsCallbacks.removeAll()
            print("🛑 FirebaseManager: Stopped watching emergency settings, cleared all callbacks")
        }
        
func updateEmergencyNumber(_ number: String, forType type: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ FirebaseManager: Cannot update emergency number - user not authenticated")
            completion?(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("📞 FirebaseManager: Updating \(type) number to: \(number)")
        print("   Updated by UID: \(uid)")
        
        let ref = db.collection("emergencySettings").document("global")
        let data: [String: Any] = [
            "\(type)Number": number,
            "updatedBy": uid,
            "updatedAt": Timestamp(date: Date())
        ]
        
        ref.setData(data, merge: true) { error in
            if let error = error {
                print("❌ FirebaseManager: Error updating \(type) number: \(error)")
                print("   Error details: \(error.localizedDescription)")
            } else {
                print("✅ FirebaseManager: \(type) number successfully updated to: \(number)")
                }
                completion?(error)
            }
        }
        
        private func watchEmergencyContactsInternal(
            callback: @escaping ([EmergencyContactData]) -> Void
        ) {
            let collection = db.collection("emergencyContacts")
            collection.addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ FirebaseManager: Error watching emergency contacts: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    callback([])
                    return
                }
                
                let contacts = documents.compactMap { doc -> EmergencyContactData? in
                    let data = doc.data()
                    let isActive = data["isActive"] as? Bool ?? true
                    
                    // Skip inactive contacts
                    guard isActive else { return nil }
                    
                    return EmergencyContactData(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "",
                        phone: data["phone"] as? String ?? "",
                        email: data["email"] as? String ?? "",
                        organization: data["organization"] as? String ?? "",
                        category: data["category"] as? String ?? "Emergency",
                        priority: data["priority"] as? String ?? "Normal",
                        availability: data["availability"] as? String ?? "",
                        notes: data["notes"] as? String ?? "",
                        createdBy: data["createdBy"] as? String ?? "",
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        isActive: isActive
                    )
                }
                
                callback(contacts)
            }
        }
        
        func createOrUpdateEmergencyContact(
            _ contact: EmergencyContactData,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            // Ensure user is authenticated
            if Auth.auth().currentUser == nil {
                Auth.auth().signInAnonymously { result, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    self.createOrUpdateEmergencyContactInternal(contact, completion: completion)
                }
                return
            }
            createOrUpdateEmergencyContactInternal(contact, completion: completion)
        }
        
        private func createOrUpdateEmergencyContactInternal(
            _ contact: EmergencyContactData,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            guard let uid = Auth.auth().currentUser?.uid else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
                return
            }
            
            let ref = db.collection("emergencyContacts").document(contact.id)
            
            var data: [String: Any] = [
                "name": contact.name,
                "phone": contact.phone,
                "email": contact.email,
                "organization": contact.organization,
                "category": contact.category,
                "priority": contact.priority,
                "availability": contact.availability,
                "notes": contact.notes,
                "createdBy": contact.createdBy,
                "createdAt": Timestamp(date: contact.createdAt),
                "updatedAt": Timestamp(date: contact.updatedAt),
                "isActive": contact.isActive,
                "userId": uid  // Required by security rules
            ]
            
            ref.setData(data, merge: true) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(contact.id))
                }
            }
        }
        
        func deleteEmergencyContact(
            id: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            // Ensure user is authenticated
            if Auth.auth().currentUser == nil {
                Auth.auth().signInAnonymously { result, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    self.deleteEmergencyContactInternal(id: id, completion: completion)
                }
                return
            }
            deleteEmergencyContactInternal(id: id, completion: completion)
        }
        
        private func deleteEmergencyContactInternal(
            id: String,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            let ref = db.collection("emergencyContacts").document(id)
            
            // Soft delete by marking as inactive
            ref.updateData([
                "isActive": false,
                "updatedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }

    // MARK: - Category Contacts (Report It Department Contacts)
    
    func watchCategoryContacts(
        callback: @escaping ([CategoryContact]) -> Void
    ) {
        // Ensure user is authenticated
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    print("❌ FirebaseManager: Anonymous auth failed: \(error.localizedDescription)")
                    callback([])
                    return
                }
                self.watchCategoryContactsInternal(callback: callback)
            }
            return
        }
        watchCategoryContactsInternal(callback: callback)
    }
    
    private func watchCategoryContactsInternal(
        callback: @escaping ([CategoryContact]) -> Void
    ) {
        let collection = db.collection("categoryContacts")
        collection.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ FirebaseManager: Error watching category contacts: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                callback([])
                return
            }
            
            let contacts = documents.compactMap { doc -> CategoryContact? in
                let data = doc.data()
                
                return CategoryContact(
                    id: doc.documentID,
                    name: data["name"] as? String ?? "",
                    number: data["number"] as? String ?? "",
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedBy: data["updatedBy"] as? String ?? ""
                )
            }
            
            callback(contacts)
        }
    }
    
    func updateCategoryContact(
        _ contact: CategoryContact,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Ensure user is authenticated
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                self.updateCategoryContactInternal(contact, completion: completion)
            }
            return
        }
        updateCategoryContactInternal(contact, completion: completion)
    }
    
    private func updateCategoryContactInternal(
        _ contact: CategoryContact,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        let ref = db.collection("categoryContacts").document(contact.id)
        
        let data: [String: Any] = [
            "name": contact.name,
            "number": contact.number,
            "updatedAt": Timestamp(date: Date()),
            "updatedBy": uid,
            "userId": uid  // Required by security rules (matches emergency contacts pattern)
        ]
        
        ref.setData(data, merge: true) { error in
            if let error = error {
                print("❌ FirebaseManager: Failed to update category contact: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ FirebaseManager: Successfully updated category contact '\(contact.id)'")
                completion(.success(()))
            }
        }
    }

    #endif
}
