import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// Manager that centralizes community chat messages handling similar to NewsletterManager.
/// - Keeps a sanitized AppStorage fallback (`communityMessagesData`).
/// - When Firestore is available it watches `communityMessages` and publishes decoded messages.
final class ChatMessagesManagerFixed: ObservableObject {
    @Published var messages: [CommunityMessage] = []
    @AppStorage("communityMessagesData") private var communityMessagesData: String = ""

    private var usingFirestore: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        #if canImport(FirebaseFirestore)
        usingFirestore = true
        // Load persisted messages first so cached attachments are visible immediately
        loadMessages()
        
        print("ChatMessagesManagerFixed: Initializing with \(messages.count) cached messages")

        // Persist sanitized messages whenever the array changes (keeps AppStorage up-to-date)
        $messages
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] newMessages in
                print("ChatMessagesManagerFixed: Messages updated to \(newMessages.count) messages")
                self?.saveSanitizedMessagesToAppStorage()
            }
            .store(in: &cancellables)

        // Set up Firestore listener
        setupFirestoreListener()
        #else
        loadMessages()
        #endif
    }
    
    #if canImport(FirebaseFirestore)
    private func setupFirestoreListener() {
        print("ChatMessagesManagerFixed: Setting up Firestore listener")
        
        FirebaseManager.shared.watchCommunityMessages(uploadsUID: "M66ohfE5AibirfOWyAEWwBRZ9mK2") { [weak self] items in
            guard let self = self else { return }
            
            print("ChatMessagesManagerFixed: Firestore listener fired with \(items.count) items")
            
            var incoming: [CommunityMessage] = []
            for item in items {
                if let idStr = item["id"] as? String, let id = UUID(uuidString: idStr) {
                    let user = item["user"] as? String ?? "Anonymous"
                    let text = item["text"] as? String ?? ""
                    let ts = item["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                    let typeRaw = item["messageType"] as? String ?? "text"
                    let type = MessageType(rawValue: typeRaw) ?? .text

                    var imageURL: URL? = nil
                    var fileURL: URL? = nil
                    var audioURL: URL? = nil
                    if let s = item["imageURL"] as? String { imageURL = URL(string: s) }
                    if let s = item["fileURL"] as? String { fileURL = URL(string: s) }
                    if let s = item["audioURL"] as? String { audioURL = URL(string: s) }

                    let msg = CommunityMessage(
                        id: id, user: user, text: text, timestamp: Date(timeIntervalSince1970: ts), 
                        messageType: type, isEdited: item["isEdited"] as? Bool ?? false, editedAt: nil, 
                        replyTo: nil, imageData: nil, imageLocalURL: nil, imageURL: imageURL, 
                        fileURL: fileURL, audioURL: audioURL, fileData: nil, fileName: item["fileName"] as? String, 
                        fileLocalURL: nil, audioFileName: item["audioFileName"] as? String, audioFileURL: nil, 
                        isRead: false
                    )
                    incoming.append(msg)
                }
            }

            DispatchQueue.main.async {
                // Simple approach: just replace all messages with incoming ones, sorted by timestamp
                let sortedMessages = incoming.sorted { $0.timestamp < $1.timestamp }
                print("ChatMessagesManagerFixed: Updating messages to \(sortedMessages.count) from Firestore")
                self.messages = sortedMessages
            }
        }
    }
    #endif

    private func loadMessages() {
        guard !communityMessagesData.isEmpty,
              let data = communityMessagesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CommunityMessage].self, from: data) else { 
            print("ChatMessagesManagerFixed: No cached messages found")
            return 
        }
        messages = decoded.sorted { $0.timestamp < $1.timestamp }
        print("ChatMessagesManagerFixed: Loaded \(messages.count) cached messages")
    }

    func saveMessagesLocally() {
        saveSanitizedMessagesToAppStorage()
    }

    // Helper to persist the current sanitized messages array into AppStorage.
    private func saveSanitizedMessagesToAppStorage() {
        let sanitized = self.messages.map { msg -> CommunityMessage in
            return CommunityMessage(
                id: msg.id,
                user: msg.user,
                text: msg.text,
                timestamp: msg.timestamp,
                messageType: msg.messageType,
                isEdited: msg.isEdited,
                editedAt: msg.editedAt,
                replyTo: msg.replyTo,
                imageData: nil,
                imageURL: msg.imageURL,
                fileURL: msg.fileURL,
                audioURL: msg.audioURL,
                fileData: nil,
                fileName: msg.fileName,
                fileLocalURL: msg.fileLocalURL,
                audioFileName: msg.audioFileName,
                audioFileURL: msg.audioFileURL,
                isRead: msg.isRead
            )
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            communityMessagesData = String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// Add or persist a message. If Firestore is available, delegate to FirebaseManager which will handle uploads.
    func addMessage(_ message: CommunityMessage) {
        if usingFirestore {
            print("ChatMessagesManagerFixed: Adding message via FirebaseManager")
            FirebaseManager.shared.createOrUpdateCommunityMessage(message) { err in
                if let err = err { 
                    print("ChatMessagesManagerFixed: failed to persist message: \(err)") 
                } else {
                    print("ChatMessagesManagerFixed: Successfully added message to Firestore")
                }
            }
        } else {
            print("ChatMessagesManagerFixed: Adding message locally")
            messages.append(message)
            saveMessagesLocally()
        }
    }
}