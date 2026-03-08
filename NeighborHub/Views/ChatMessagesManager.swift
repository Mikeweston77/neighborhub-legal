import Foundation
import SwiftUI
import Combine
import UserNotifications

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

/// Manager that centralizes community chat messages handling similar to NewsletterManager.
/// - Keeps a sanitized AppStorage fallback (`communityMessagesData`).
/// - When Firestore is available it watches `communityMessages` and publishes decoded messages.
/// - Sends notifications to other users when new messages arrive.
class ChatMessagesManager: ObservableObject {
    @Published var messages: [CommunityMessage] = []
    @AppStorage("communityMessagesData") private var communityMessagesData: Data = Data()
    @AppStorage("chatNotificationsEnabled") private var chatNotificationsEnabled: Bool = true
    @AppStorage("userName") private var currentUserName: String = ""
    
    private let firebaseManager = FirebaseManager.shared
    private var lastMessageCount = 0
    
    init() {
        loadCachedMessages()
        lastMessageCount = messages.count
        updateCurrentUserName()
        setupFirestoreListener()
    }
    
    private func updateCurrentUserName() {
        // Try to get the current user name from UserDefaults
        if let displayName = UserDefaults.standard.string(forKey: "displayName"), !displayName.isEmpty {
            currentUserName = displayName
        } else if let userName = UserDefaults.standard.string(forKey: "userName"), !userName.isEmpty {
            currentUserName = userName
        }
        print("ChatMessagesManager: Current user name set to: \(currentUserName)")
    }
    
    private func loadCachedMessages() {
        if let decodedMessages = try? JSONDecoder().decode([CommunityMessage].self, from: communityMessagesData) {
            messages = decodedMessages
            print("ChatMessagesManager: Loaded \(messages.count) cached messages")
        } else {
            messages = []
            print("ChatMessagesManager: No cached messages found")
        }
    }
    
    private func cacheMessages() {
        if let encodedData = try? JSONEncoder().encode(messages) {
            communityMessagesData = encodedData
            print("ChatMessagesManager: Cached \(messages.count) messages")
        }
    }
    
    #if canImport(FirebaseFirestore)
    private func setupFirestoreListener() {
        // Use top-level communityMessages collection for consistency
        let db = Firestore.firestore()
        print("ChatMessagesManager: Setting up listener for communityMessages")
        
        db.collection("communityMessages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] querySnapshot, error in
                if let error = error {
                    print("ChatMessagesManager: Error listening for messages: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else { 
                    print("ChatMessagesManager: No documents found")
                    return 
                }
                
                print("ChatMessagesManager: Received \(documents.count) messages from Firestore")
                
                DispatchQueue.main.async {
                    self?.updateFromFirestore(documents)
                }
            }
    }
    
    private func updateFromFirestore(_ documents: [QueryDocumentSnapshot]) {
        var newMessages: [CommunityMessage] = []
        
        for document in documents {
            let data = document.data()
            
            // Parse the document into a CommunityMessage
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let user = data["user"] as? String,
                  let text = data["text"] as? String,
                  let typeRaw = data["messageType"] as? String,
                  let messageType = MessageType(rawValue: typeRaw) else {
                print("ChatMessagesManager: Failed to parse message document: \(document.documentID)")
                continue
            }
            
            let isEdited = data["isEdited"] as? Bool ?? false
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let editedAt = (data["editedAt"] as? Timestamp)?.dateValue()
            let replyToString = data["replyTo"] as? String
            let replyTo = replyToString != nil ? UUID(uuidString: replyToString!) : nil
            let isRead = data["isRead"] as? Bool ?? false
            
            // Parse media-related fields
            // Decode imageData from base64 (like newsletters/events/incidents)
            var imageData: Data? = nil
            if let base64String = data["imageData"] as? String,
               let decodedData = Data(base64Encoded: base64String) {
                imageData = decodedData
                print("ChatMessagesManager: Decoded imageData (\(decodedData.count) bytes) from base64")
            }
            
            let imageURLString = data["imageURL"] as? String
            let imageURL = imageURLString != nil ? URL(string: imageURLString!) : nil
            let imageLocalURL = data["imageLocalURL"] as? String
            let fileURLString = data["fileURL"] as? String
            let fileURL = fileURLString != nil ? URL(string: fileURLString!) : nil
            let audioURLString = data["audioURL"] as? String
            let audioURL = audioURLString != nil ? URL(string: audioURLString!) : nil
            let fileName = data["fileName"] as? String
            let audioFileName = data["audioFileName"] as? String
            let audioFileURL = data["audioFileURL"] as? String
            let audioFileLocalURL = data["audioFileLocalURL"] as? String
            let fileLocalURL = data["fileLocalURL"] as? String
            
            // Parse pinned fields
            let pinned = data["pinned"] as? Bool ?? false
            let pinnedBy = data["pinnedBy"] as? String
            let pinnedAt = (data["pinnedAt"] as? Timestamp)?.dateValue()
            
            print("ChatMessagesManager: Parsing message with imageData: \(imageData != nil ? "\(imageData!.count) bytes" : "nil"), imageURL: \(imageURLString ?? "nil"), imageLocalURL: \(imageLocalURL ?? "nil"), audioURL: \(audioURLString ?? "nil"), audioFileName: \(audioFileName ?? "nil"), audioFileURL: \(audioFileURL ?? "nil"), pinned: \(pinned)")
            
            let message = CommunityMessage(
                id: id,
                user: user,
                text: text,
                timestamp: timestamp,
                messageType: messageType,
                isEdited: isEdited,
                editedAt: editedAt,
                replyTo: replyTo,
                imageData: imageData,  // Now populated from Firestore
                imageLocalURL: imageLocalURL,
                imageURL: imageURL,
                fileURL: fileURL,
                audioURL: audioURL,
                fileName: fileName,
                fileLocalURL: fileLocalURL,
                audioFileName: audioFileName,
                audioFileURL: audioFileLocalURL ?? audioFileURL,
                isRead: isRead,
                pinned: pinned,
                pinnedBy: pinnedBy,
                pinnedAt: pinnedAt
            )
            
            newMessages.append(message)
        }
        
        let previousMessages = messages
        messages = newMessages.sorted { $0.timestamp < $1.timestamp }
        cacheMessages()
        
        // Check for new messages to send notifications
        checkForNewMessagesAndNotify(previousMessages: previousMessages, newMessages: messages)
        
        print("ChatMessagesManager: Updated with \(messages.count) messages")
    }
    
    private func checkForNewMessagesAndNotify(previousMessages: [CommunityMessage], newMessages: [CommunityMessage]) {
        // Only send notifications if we have previous messages (not on first load)
        guard !previousMessages.isEmpty else { return }
        
        let previousIds = Set(previousMessages.map { $0.id })
        let trulyNewMessages = newMessages.filter { !previousIds.contains($0.id) }
        
        for message in trulyNewMessages {
            // Only notify if this message is from someone else
            if message.user != currentUserName && chatNotificationsEnabled {
                sendNotificationForMessage(message)
            }
        }
    }
    
    private func sendNotificationForMessage(_ message: CommunityMessage) {
        let content = UNMutableNotificationContent()
        content.title = "New Community Chat Message"
        
        // Create appropriate notification body based on message type
        var bodyText = message.text
        if message.imageURL != nil || !message.imageLocalURL.isNilOrEmpty {
            bodyText = "📷 Sent a photo" + (message.text.isEmpty ? "" : ": \(message.text)")
        } else if message.audioURL != nil || !message.audioFileName.isNilOrEmpty {
            bodyText = "🎤 Sent a voice message" + (message.text.isEmpty ? "" : ": \(message.text)")
        } else if message.fileURL != nil || !message.fileName.isNilOrEmpty {
            bodyText = "📎 Sent a file" + (message.text.isEmpty ? "" : ": \(message.text)")
        }
        
        content.body = "\(message.user): \(bodyText.prefix(100))"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "chat"
        
        let request = UNNotificationRequest(identifier: "chat-incoming-\(message.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("ChatMessagesManager: Failed to send notification: \(error)")
            } else {
                print("ChatMessagesManager: Sent notification for message from \(message.user)")
            }
        }
    }
    #else
    private func setupFirestoreListener() {
        print("ChatMessagesManager: Firebase not available, using cached messages only")
    }
    #endif
    
    // Local storage fallback when Firebase isn't available
    private func saveMessagesLocally() {
        cacheMessages()
    }
    
    func addMessage(_ message: CommunityMessage) {
        #if canImport(FirebaseFirestore)
        print("🔵 ChatMessagesManager: Adding message via Firebase")
        print("   - Message ID: \(message.id)")
        print("   - Message Type: \(message.messageType)")
        print("   - Has fileData: \(message.fileData != nil) (size: \(message.fileData?.count ?? 0) bytes)")
        print("   - Has fileName: \(message.fileName != nil) (\(message.fileName ?? "nil"))")
        print("   - Has fileLocalURL: \(message.fileLocalURL != nil) (\(message.fileLocalURL ?? "nil"))")
        print("   - Has fileURL: \(message.fileURL != nil)")
        print("   - Has audioFileName: \(message.audioFileName != nil) (\(message.audioFileName ?? "nil"))")
        print("   - Has audioFileURL: \(message.audioFileURL != nil) (\(message.audioFileURL ?? "nil"))")
        
        // Check for audio file that needs uploading
        if let audioFileName = message.audioFileName, let audioLocalPath = message.audioFileURL {
            print("   - File type: 🎤 AUDIO")
            print("🎤 ChatMessagesManager: Audio detected (\(audioFileName)), uploading to Storage before Firestore write")
            uploadAudioAttachment(message: message, audioFileName: audioFileName, audioLocalPath: audioLocalPath)
            return
        }
        
        // Check if message has file data that needs uploading (video/large files)
        if let fileData = message.fileData, let fileName = message.fileName {
            let isVideo = isVideoFile(fileName)
            let isGif = fileName.lowercased().hasSuffix(".gif")
            
            if isGif {
                print("   - File type: 🎭 GIF")
                print("🎭 ChatMessagesManager: GIF detected (\(fileName)), uploading to Storage before Firestore write")
                uploadGifAttachment(message: message, fileData: fileData, fileName: fileName)
            } else if isVideo {
                print("   - File type: 🎬 VIDEO")
                print("🎬 ChatMessagesManager: Video detected (\(fileName)), uploading to Storage before Firestore write")
                uploadVideoAttachment(message: message, fileData: fileData, fileName: fileName)
            } else {
                print("   - File type: 📄 OTHER")
                // Non-video/non-GIF files can be handled directly (or uploaded if large)
                firebaseManager.createOrUpdateCommunityMessage(message) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ ChatMessagesManager: Error adding message: \(error)")
                        } else {
                            print("✅ ChatMessagesManager: Successfully added message to Firestore")
                        }
                    }
                }
            }
        } else {
            print("   - NO fileData or fileName, writing directly to Firestore")
            if message.fileName != nil && message.fileData == nil {
                print("   - ⚠️ WARNING: fileName exists but fileData is nil!")
            }
            // No file attachment or fileURL already set - direct Firestore write
            firebaseManager.createOrUpdateCommunityMessage(message) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ ChatMessagesManager: Error adding message: \(error)")
                    } else {
                        print("✅ ChatMessagesManager: Successfully added message to Firestore")
                    }
                }
            }
        }
        #else
        print("ChatMessagesManager: Adding message locally")
        messages.append(message)
        saveMessagesLocally()
        #endif
    }
    
    #if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseStorage)
    /// Upload video file to Firebase Storage before writing message to Firestore
    private func uploadVideoAttachment(message: CommunityMessage, fileData: Data, fileName: String) {
        print("📤 uploadVideoAttachment() called")
        print("   - Message ID: \(message.id)")
        print("   - File name: \(fileName)")
        print("   - File size: \(fileData.count) bytes")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ ChatMessagesManager: Cannot upload video - user not authenticated")
            // Fallback: write message without fileURL
            firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
            return
        }
        
        // Validate file size (limit to 100MB to prevent excessive uploads)
        let maxSize: Int64 = 100 * 1024 * 1024  // 100MB
        if fileData.count > maxSize {
            print("❌ ChatMessagesManager: Video file too large (\(fileData.count) bytes), maximum is \(maxSize) bytes")
            // Show error notification
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoUploadError"),
                object: "Video file is too large. Maximum size is 100MB."
            )
            return
        }
        
        print("✅ ChatMessagesManager: File size validated, proceeding with upload...")
        
        // Write to temporary file for upload
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try fileData.write(to: tempURL)
            print("✅ Temp file written: \(tempURL.path)")
        } catch {
            print("❌ ChatMessagesManager: Failed to write temp file: \(error)")
            return
        }
        
        // Upload to Storage at: uploads/{uid}/communityMessages/{messageId}/{fileName}
        let storagePath = "uploads/\(uid)/communityMessages/\(message.id.uuidString)/\(fileName)"
        print("📤 Uploading to Storage path: \(storagePath)")
        
        // Post upload start notification
        NotificationCenter.default.post(
            name: .communityUploadProgress,
            object: nil,
            userInfo: ["id": message.id.uuidString, "type": "uploading", "progress": 0.0]
        )
        
        firebaseManager.uploadFile(from: tempURL, path: storagePath) { url, error in
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            print("🗑️ Temp file cleaned up")
            
            DispatchQueue.main.async {
                if let url = url {
                    print("✅ ChatMessagesManager: Video uploaded successfully!")
                    print("   - Download URL: \(url.absoluteString)")
                    
                    // Update message with remote URL and clear large binary data
                    var updatedMessage = message
                    updatedMessage.fileURL = url
                    updatedMessage.fileData = nil  // Clear to save memory
                    
                    print("📝 Updating Firestore message with fileURL...")
                    // Now write to Firestore with the download URL
                    self.firebaseManager.createOrUpdateCommunityMessage(updatedMessage) { err in
                        if let err = err {
                            print("❌ ChatMessagesManager: Failed to update message with video URL: \(err)")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                            )
                        } else {
                            print("✅ ChatMessagesManager: Message updated with video URL successfully")
                            print("   - Recipients will now be able to download and view video")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "complete", "progress": 1.0]
                            )
                        }
                    }
                } else {
                    print("❌ ChatMessagesManager: Video upload failed!")
                    print("   - Error: \(error?.localizedDescription ?? "Unknown error")")
                    NotificationCenter.default.post(
                        name: .communityUploadProgress,
                        object: nil,
                        userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                    )
                    
                    // Fallback: write message without fileURL (local playback only)
                    print("⚠️ Writing message to Firestore without fileURL (fallback)")
                    self.firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
                }
            }
        }
    }
    
    /// Upload GIF file to Firebase Storage before writing message to Firestore
    /// GIFs use a separate storage path: uploads/{uid}/communityMessages/gifs/{messageId}/{fileName}
    private func uploadGifAttachment(message: CommunityMessage, fileData: Data, fileName: String) {
        print("📤 uploadGifAttachment() called")
        print("   - Message ID: \(message.id)")
        print("   - File name: \(fileName)")
        print("   - File size: \(fileData.count) bytes")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ ChatMessagesManager: Cannot upload GIF - user not authenticated")
            // Fallback: write message without fileURL
            firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
            return
        }
        
        // Validate file size (limit to 50MB for GIFs)
        let maxSize: Int64 = 50 * 1024 * 1024  // 50MB
        if fileData.count > maxSize {
            print("❌ ChatMessagesManager: GIF file too large (\(fileData.count) bytes), maximum is \(maxSize) bytes")
            // Show error notification
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoUploadError"),
                object: "GIF file is too large. Maximum size is 50MB."
            )
            return
        }
        
        print("✅ ChatMessagesManager: GIF size validated, proceeding with upload...")
        
        // Write to temporary file for upload
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try fileData.write(to: tempURL)
            print("✅ Temp GIF file written: \(tempURL.path)")
        } catch {
            print("❌ ChatMessagesManager: Failed to write temp GIF file: \(error)")
            return
        }
        
        // Upload to Storage at: uploads/{uid}/communityMessages/gifs/{messageId}/{fileName}
        // Note: Separate path to distinguish GIFs from videos in storage
        let storagePath = "uploads/\(uid)/communityMessages/gifs/\(message.id.uuidString)/\(fileName)"
        print("📤 Uploading GIF to Storage path: \(storagePath)")
        
        // Post upload start notification
        NotificationCenter.default.post(
            name: .communityUploadProgress,
            object: nil,
            userInfo: ["id": message.id.uuidString, "type": "uploading", "progress": 0.0]
        )
        
        firebaseManager.uploadFile(from: tempURL, path: storagePath) { url, error in
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            print("🗑️ Temp GIF file cleaned up")
            
            DispatchQueue.main.async {
                if let url = url {
                    print("✅ ChatMessagesManager: GIF uploaded successfully!")
                    print("   - Download URL: \(url.absoluteString)")
                    
                    // Update message with remote URL and clear large binary data
                    var updatedMessage = message
                    updatedMessage.fileURL = url
                    updatedMessage.fileData = nil  // Clear to save memory
                    
                    print("📝 Updating Firestore message with GIF fileURL...")
                    // Now write to Firestore with the download URL
                    self.firebaseManager.createOrUpdateCommunityMessage(updatedMessage) { err in
                        if let err = err {
                            print("❌ ChatMessagesManager: Failed to update message with GIF URL: \(err)")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                            )
                        } else {
                            print("✅ ChatMessagesManager: Message updated with GIF URL successfully")
                            print("   - Recipients will now be able to download and view GIF")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "complete", "progress": 1.0]
                            )
                        }
                    }
                } else {
                    print("❌ ChatMessagesManager: GIF upload failed!")
                    print("   - Error: \(error?.localizedDescription ?? "Unknown error")")
                    NotificationCenter.default.post(
                        name: .communityUploadProgress,
                        object: nil,
                        userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                    )
                    
                    // Fallback: write message without fileURL (local playback only)
                    print("⚠️ Writing message to Firestore without fileURL (fallback)")
                    self.firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
                }
            }
        }
    }
    
    /// Upload audio file to Firebase Storage before writing message to Firestore
    /// Audio files use path: uploads/{uid}/communityMessages/audio/{messageId}/{fileName}
    private func uploadAudioAttachment(message: CommunityMessage, audioFileName: String, audioLocalPath: String) {
        print("📤 uploadAudioAttachment() called")
        print("   - Message ID: \(message.id)")
        print("   - Audio file name: \(audioFileName)")
        print("   - Local path: \(audioLocalPath)")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ ChatMessagesManager: Cannot upload audio - user not authenticated")
            // Fallback: write message without audioURL (local playback only)
            firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
            return
        }
        
        // Load audio data from local file
        let audioURL = URL(fileURLWithPath: audioLocalPath)
        guard let audioData = try? Data(contentsOf: audioURL) else {
            print("❌ ChatMessagesManager: Failed to load audio data from path: \(audioLocalPath)")
            // Fallback: write message without audioURL
            firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
            return
        }
        
        print("✅ ChatMessagesManager: Audio data loaded (\(audioData.count) bytes)")
        
        // Validate file size (limit to 10MB for audio - voice messages are typically small)
        let maxSize: Int64 = 10 * 1024 * 1024  // 10MB
        if audioData.count > maxSize {
            print("❌ ChatMessagesManager: Audio file too large (\(audioData.count) bytes), maximum is \(maxSize) bytes")
            // Show error notification
            NotificationCenter.default.post(
                name: NSNotification.Name("AudioUploadError"),
                object: "Audio file is too large. Maximum size is 10MB."
            )
            return
        }
        
        print("✅ ChatMessagesManager: Audio size validated, proceeding with upload...")
        
        // Write to temporary file for upload
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFileName)
        do {
            try audioData.write(to: tempURL)
            print("✅ Temp audio file written: \(tempURL.path)")
        } catch {
            print("❌ ChatMessagesManager: Failed to write temp audio file: \(error)")
            return
        }
        
        // Upload to Storage at: uploads/{uid}/communityMessages/audio/{messageId}/{fileName}
        let storagePath = "uploads/\(uid)/communityMessages/audio/\(message.id.uuidString)/\(audioFileName)"
        print("📤 Uploading audio to Storage path: \(storagePath)")
        
        // Post upload start notification
        NotificationCenter.default.post(
            name: .communityUploadProgress,
            object: nil,
            userInfo: ["id": message.id.uuidString, "type": "uploading", "progress": 0.0]
        )
        
        firebaseManager.uploadFile(from: tempURL, path: storagePath) { url, error in
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            print("🗑️ Temp audio file cleaned up")
            
            DispatchQueue.main.async {
                if let url = url {
                    print("✅ ChatMessagesManager: Audio uploaded successfully!")
                    print("   - Download URL: \(url.absoluteString)")
                    
                    // Update message with remote URL and clear local path
                    var updatedMessage = message
                    updatedMessage.audioURL = url
                    updatedMessage.audioFileURL = nil  // Clear local path to save space
                    
                    print("📝 Updating Firestore message with audioURL...")
                    // Now write to Firestore with the download URL
                    self.firebaseManager.createOrUpdateCommunityMessage(updatedMessage) { err in
                        if let err = err {
                            print("❌ ChatMessagesManager: Failed to update message with audio URL: \(err)")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                            )
                        } else {
                            print("✅ ChatMessagesManager: Message updated with audio URL successfully")
                            print("   - All users can now stream this voice message from cloud")
                            NotificationCenter.default.post(
                                name: .communityUploadProgress,
                                object: nil,
                                userInfo: ["id": message.id.uuidString, "type": "complete", "progress": 1.0]
                            )
                        }
                    }
                } else {
                    print("❌ ChatMessagesManager: Audio upload failed!")
                    print("   - Error: \(error?.localizedDescription ?? "Unknown error")")
                    NotificationCenter.default.post(
                        name: .communityUploadProgress,
                        object: nil,
                        userInfo: ["id": message.id.uuidString, "type": "error", "progress": 0.0]
                    )
                    
                    // Fallback: write message without audioURL (local playback only)
                    print("⚠️ Writing message to Firestore without audioURL (fallback)")
                    self.firebaseManager.createOrUpdateCommunityMessage(message) { _ in }
                }
            }
        }
    }
    
    /// Helper to check if file is a video
    private func isVideoFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(ext)
    }
    #endif
    
    // Public methods for notification settings
    func updateNotificationSettings(enabled: Bool) {
        chatNotificationsEnabled = enabled
        print("ChatMessagesManager: Notifications \(enabled ? "enabled" : "disabled")")
    }
    
    func updateCurrentUser(name: String) {
        currentUserName = name
        print("ChatMessagesManager: Current user updated to: \(name)")
    }
}

// Helper extension for checking if optional string is nil or empty
private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}