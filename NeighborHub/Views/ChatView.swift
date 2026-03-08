import SwiftUI

/// Example view demonstrating how to use the new real-time chat functionality
struct ChatView: View {
    let chatId: String

    @State private var messages: [ChatManager.ChatMessage] = []
    @State private var newMessageText: String = ""
    @State private var isLoading: Bool = false

    private let chatManager = ChatManager.shared

    var body: some View {
        VStack {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    // Auto-scroll to bottom when new messages arrive
                    if let lastMessage = messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Message input
            HStack {
                TextField("Type a message...", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isLoading)

                Button("Send") {
                    sendMessage()
                }
                .disabled(
                    newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isLoading)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startListening()
        }
        .onDisappear {
            stopListening()
        }
    }

    private func startListening() {
        chatManager.watchChatMessages(chatId: chatId) { newMessages in
            DispatchQueue.main.async {
                self.messages = newMessages
            }
        }
    }

    private func stopListening() {
        chatManager.stopWatchingChat(chatId: chatId)
    }

    private func sendMessage() {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isLoading = true
        newMessageText = ""

        chatManager.sendTextMessage(chatId: chatId, text: text) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let messageId):
                    print("Message sent successfully: \(messageId)")
                case .failure(let error):
                    print("Failed to send message: \(error.localizedDescription)")
                // Could show an error alert here
                }
            }
        }
    }
}

/// Individual message row view
private struct ChatMessageRow: View {
    let message: ChatManager.ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.senderId)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let text = message.text {
                Text(text)
                    .font(.body)
            }

            // Show attachment indicators
            if let attachments = message.attachmentURLs, !attachments.isEmpty {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(.blue)
                    Text("\(attachments.count) attachment(s)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            // Show status for pending/failed messages
            if message.status != "processed" {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(message.status.capitalized)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }

            // Show reactions if any
            if let reactions = message.reactions, !reactions.isEmpty {
                HStack {
                    ForEach(Array(reactions.keys), id: \.self) { emoji in
                        Button(action: {
                            // Handle reaction tap
                        }) {
                            Text("\(emoji) \(reactions[emoji] ?? 0)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal, 4)
    }

    private var statusIcon: String {
        switch message.status {
        case "pending": return "clock"
        case "uploaded": return "arrow.up.circle"
        case "processed": return "checkmark.circle"
        case "failed": return "exclamationmark.triangle"
        default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch message.status {
        case "pending": return .orange
        case "uploaded": return .blue
        case "processed": return .green
        case "failed": return .red
        default: return .gray
        }
    }
}

#Preview {
    NavigationView {
        ChatView(chatId: "sample-chat-id")
    }
}
