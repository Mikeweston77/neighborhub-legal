import SwiftUI
import UIKit
import OSLog

// MARK: - AI Message Search Result Display

/// A modern, modular AI message search overlay for chat.
struct AIMessagesSearchOverlay: View {
    let allMessages: [ChatMessage] // All chat messages
    let searchTerm: String
    let onSelect: (ChatMessage) -> Void
    @Binding var isPresented: Bool

    // Interaction state
    @State private var highlightedMessageID: UUID?
    @State private var dragOffset: CGSize = .zero
    private let logger = AnalyticsLogger()

    // Filter messages containing the search term (case-insensitive)
    var filteredMessages: [ChatMessage] {
        guard !searchTerm.isEmpty else { return [] }
        return allMessages.filter { $0.text.localizedCaseInsensitiveContains(searchTerm) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("AI Search Results")
                        .font(.headline)
                        .padding(.leading)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 12)
                .background(BlurView(style: .systemMaterial))

                if filteredMessages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        (
                            Text("No messages found for '") +
                            Text(searchTerm).bold() +
                            Text("'.")
                        )
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredMessages) { message in
                                // Individual message card — interactive
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Text(message.senderInitials)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.accentColor)
                                        )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.text)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .lineLimit(3)
                                        Text(message.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal)
                                .background(
                                    Group {
                                        if highlightedMessageID == message.id {
                                            Color.accentColor.opacity(0.12)
                                        } else {
                                            Color(.systemBackground).opacity(0.95)
                                        }
                                    }
                                )
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                // Tap to select
                                .onTapGesture {
                                    highlightedMessageID = message.id
                                    // small selection delay for visual feedback
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                        // Haptic feedback
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        // Log analytics
                                        logger.logSelect(messageID: message.id, searchTerm: searchTerm)
                                        isPresented = false
                                        onSelect(message)
                                    }
                                }
                                // Long press for context actions
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = message.text
                                        logger.logCopy(messageID: message.id, searchTerm: searchTerm)
                                    }) {
                                        Label("Copy Text", systemImage: "doc.on.doc")
                                    }
                                    Button(action: {
                                        logger.logJump(messageID: message.id, searchTerm: searchTerm)
                                        isPresented = false
                                        onSelect(message)
                                    }) {
                                        Label("Jump to Message", systemImage: "arrow.turn.up.right")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxWidth: 420)
            .background(BlurView(style: .systemMaterial))
            .cornerRadius(18)
            .shadow(radius: 16)
            .padding(.horizontal, 16)
            // draggable to dismiss
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { v in
                        // only allow downward drag
                        if v.translation.height > 0 {
                            dragOffset = v.translation
                        }
                    }
                    .onEnded { v in
                        if v.translation.height > 160 {
                            // dismiss
                            logger.logDismiss(searchTerm: searchTerm)
                            withAnimation(.spring()) { isPresented = false }
                        }
                        dragOffset = .zero
                    }
            )
            .onAppear {
                logger.logShow(searchTerm: searchTerm, resultsCount: filteredMessages.count)
            }
        }
        .transition(.opacity.combined(with: .scale))
        .animation(.spring(), value: isPresented)
    }
}

// MARK: - Analytics Logger
fileprivate struct AnalyticsLogger {
    private let logger = Logger(subsystem: "com.ml5ar66rq7.neighborhub", category: "AI.Search")

    func logShow(searchTerm: String, resultsCount: Int) {
        logger.log("AI Search shown: term=\(searchTerm, privacy: .public) results=\(resultsCount)")
    }

    func logSelect(messageID: UUID, searchTerm: String) {
        logger.log("AI Search select: id=\(messageID.uuidString, privacy: .public) term=\(searchTerm, privacy: .public)")
    }

    func logCopy(messageID: UUID, searchTerm: String) {
        logger.log("AI Search copy: id=\(messageID.uuidString, privacy: .public) term=\(searchTerm, privacy: .public)")
    }

    func logJump(messageID: UUID, searchTerm: String) {
        logger.log("AI Search jump: id=\(messageID.uuidString, privacy: .public) term=\(searchTerm, privacy: .public)")
    }

    func logDismiss(searchTerm: String) {
        logger.log("AI Search dismissed: term=\(searchTerm, privacy: .public)")
    }
}

// MARK: - Supporting Types

/// Minimal chat message model for search overlay (replace with your actual model if needed)
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let senderInitials: String
    let timestamp: Date
}

// MARK: - BlurView Helper
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Usage Example (to be called from parent chat view)
/*
// In your parent chat view:
@State private var showAISearchOverlay = false
@State private var aiSearchTerm = ""
@State private var allMessages: [ChatMessage] = ...

var body: some View {
    ZStack {
        // ...existing chat UI...
        if showAISearchOverlay {
            AIMessagesSearchOverlay(
                allMessages: allMessages,
                searchTerm: aiSearchTerm,
                onSelect: { message in
                    // Scroll to the selected message in your chat scrollview
                    scrollToMessage(message)
                },
                isPresented: $showAISearchOverlay
            )
        }
    }
}
*/
// MARK: - Search Action Button View
struct ChatSearchActionButton: View {
    let actionType: ChatSearchActionType
    let handler: ChatSearchActionHandler
    var body: some View {
        Button(action: { handler(actionType) }) {
            VStack(spacing: 6) {
                Image(systemName: actionType.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(actionType.color)
                    .padding(14)
                    .background(
                        Circle()
                            .fill(actionType.color.opacity(0.18))
                    )
                Text(actionType.label)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Fading Modifier for Other Action Buttons
struct FadeOtherActionsModifier: ViewModifier {
    let fade: Bool
    func body(content: Content) -> some View {
        content
            .opacity(fade ? 0.25 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: fade)
    }
}

extension View {
    func fadeIf(_ condition: Bool) -> some View {
        self.modifier(FadeOtherActionsModifier(fade: condition))
    }
}
import SwiftUI

/// Enum for search-specific chat actions
enum ChatSearchActionType: String, CaseIterable, Identifiable {
    case searchMessages
    case searchBusinesses
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .searchMessages: return "text.magnifyingglass"
        case .searchBusinesses: return "building.2.crop.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .searchMessages: return .blue
        case .searchBusinesses: return .teal
        }
    }
    
    var label: String {
        switch self {
        case .searchMessages: return "Search Messages"
        case .searchBusinesses: return "Search Businesses"
        }
    }
}

typealias ChatSearchActionHandler = (ChatSearchActionType) -> Void
