import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

#if canImport(FirebaseFunctions)
    import FirebaseFunctions
#endif

final class ChatManager {
    static let shared = ChatManager()
    private let storage = Storage.storage()
    #if canImport(FirebaseFunctions)
        private let functions = Functions.functions()
    #endif
    private let db = Firestore.firestore()

    // Real-time listeners for active chats
    private var chatListeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Chat Message Model
    struct ChatMessage: Codable, Identifiable {
        let id: String
        var senderId: String
        var text: String?
        var createdAt: Timestamp?
        var status: String  // "pending", "uploaded", "processed", "failed"
        var error: String?
        var attachmentURLs: [String]?
        var isPinned: Bool?
        var reactions: [String: Int]?  // emoji -> count

        var timestamp: Date {
            return createdAt?.dateValue() ?? Date()
        }
    }

    // MARK: - Real-time Chat Listeners

    /// Watch messages in a specific chat for real-time updates
    func watchChatMessages(chatId: String, onUpdate: @escaping ([ChatMessage]) -> Void) {
        stopWatchingChat(chatId: chatId)

        let messagesRef = db.collection("chats").document(chatId).collection("messages")
            .order(by: "createdAt", descending: false)

        let listener = messagesRef.addSnapshotListener { snapshot, error in
            guard error == nil, let snapshot = snapshot else {
                print(
                    "ChatManager: Error watching messages for chat \(chatId): \(error?.localizedDescription ?? "unknown")"
                )
                onUpdate([])
                return
            }

            var messages: [ChatMessage] = []
            for doc in snapshot.documents {
                if let message = self.chatMessageFrom(documentID: doc.documentID, data: doc.data())
                {
                    messages.append(message)
                }
            }
            onUpdate(messages)
        }

        chatListeners[chatId] = listener
    }

    /// Stop watching a specific chat
    func stopWatchingChat(chatId: String) {
        chatListeners[chatId]?.remove()
        chatListeners.removeValue(forKey: chatId)
    }

    /// Stop watching all chats
    func stopWatchingAllChats() {
        for (_, listener) in chatListeners {
            listener.remove()
        }
        chatListeners.removeAll()
    }

    /// Convert Firestore document data to ChatMessage model
    private func chatMessageFrom(documentID: String, data: [String: Any]) -> ChatMessage? {
        guard let senderId = data["senderId"] as? String else { return nil }

        let message = ChatMessage(
            id: documentID,
            senderId: senderId,
            text: data["text"] as? String,
            createdAt: data["createdAt"] as? Timestamp,
            status: data["status"] as? String ?? "unknown",
            error: data["error"] as? String,
            attachmentURLs: data["attachmentURLs"] as? [String],
            isPinned: data["isPinned"] as? Bool,
            reactions: data["reactions"] as? [String: Int]
        )

        return message
    }

    // Create a new message document and upload attachment(s) to uploads/{uid}/{chatId}/{messageId}/filename
    func createMessageWithAttachments(
        chatId: String, text: String?, attachments: [Data], contentTypes: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(
                .failure(
                    NSError(
                        domain: "auth", code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let messagesRef = db.collection("chats").document(chatId).collection("messages")
        let newMsgRef = messagesRef.document()
        var msgData: [String: Any] = [
            "senderId": user.uid,
            "createdAt": FieldValue.serverTimestamp(),
            "status": "pending",
        ]
        if let t = text { msgData["text"] = t }

        newMsgRef.setData(msgData) { err in
            if let err = err {
                completion(.failure(err))
                return
            }

            let group = DispatchGroup()
            var uploadErrors: [Error] = []

            for (idx, data) in attachments.enumerated() {
                group.enter()
                let ct =
                    contentTypes.indices.contains(idx)
                    ? contentTypes[idx] : "application/octet-stream"
                let filename = UUID().uuidString + self.fileExtension(for: ct)
                let path = "uploads/\(user.uid)/\(chatId)/\(newMsgRef.documentID)/\(filename)"
                let ref = self.storage.reference(withPath: path)
                let meta = StorageMetadata()
                meta.contentType = ct
                ref.putData(data, metadata: meta) { meta, err in
                    if let err = err { uploadErrors.append(err) }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let err = uploadErrors.first {
                    // mark message failed
                    newMsgRef.updateData(["status": "failed", "error": err.localizedDescription])
                    completion(.failure(err))
                } else {
                    // mark message waiting for processing
                    newMsgRef.updateData(["status": "uploaded"]) { err in
                        if let err = err {
                            completion(.failure(err))
                            return
                        }
                        completion(.success(newMsgRef.documentID))
                    }
                }
            }
        }
    }

    // MARK: - Message Management

    /// Send a simple text message to a chat
    func sendTextMessage(
        chatId: String, text: String, completion: @escaping (Result<String, Error>) -> Void
    ) {
        createMessageWithAttachments(
            chatId: chatId, text: text, attachments: [], contentTypes: [], completion: completion)
    }

    /// Delete a message from a chat
    func deleteMessage(
        chatId: String, messageId: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let messageRef = db.collection("chats").document(chatId).collection("messages").document(
            messageId)

        messageRef.delete { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    /// Update message reactions
    func updateMessageReaction(
        chatId: String, messageId: String, emoji: String, increment: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let messageRef = db.collection("chats").document(chatId).collection("messages").document(
            messageId)

        messageRef.updateData([
            "reactions.\(emoji)": increment
                ? FieldValue.increment(Int64(1)) : FieldValue.increment(Int64(-1))
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func fileExtension(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return ".jpg" }
        if contentType.hasPrefix("video/") { return ".mp4" }
        if contentType.hasPrefix("audio/") { return ".m4a" }
        return ""
    }

    // Call the pinMessage callable
    func pinMessage(
        chatId: String, messageId: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
            functions.httpsCallable("pinMessage").call(["chatId": chatId, "messageId": messageId]) {
                result, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(()))
            }
        #else
            completion(
                .failure(
                    NSError(
                        domain: "functions", code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "FirebaseFunctions not available in this build"
                        ])))
        #endif
    }
}
