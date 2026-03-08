import SwiftUI
import UIKit
import OSLog

struct SearchResultCard: View {
    let result: SearchResult
    let onTap: () -> Void
    let onJumpToMessage: (() -> Void)?
    @State private var isHighlighted: Bool = false
    @State private var logger = Logger(subsystem: "com.ml5ar66rq7.neighborhub", category: "AI.Search")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(.blue)
                Text(result.message.user)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(result.message.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(result.message.text)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if !result.matchedText.isEmpty {
                Text("Match: \(result.matchedText)")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(6)
            }

            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                Text("Relevance: \(Int(result.relevanceScore))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(isHighlighted ? Color(.systemGray5) : Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: isHighlighted ? 1.5 : 0.5)
        )
    // Single-tap selection removed: navigation now happens via long-press/context-menu only.
    // Keep a visible highlight and haptic when the user chooses "Jump to Message" from the context menu.
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = result.message.text
                logger.log("AI search result copied: \(result.message.id.uuidString, privacy: .public)")
            }) {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            Button(action: {
                // Provide immediate visual feedback and haptic, then perform the jump and dismiss keyboard.
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHighlighted = true
                }
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onJumpToMessage?()
                    logger.log("AI search result jump requested: \(result.message.id.uuidString, privacy: .public)")
                    // Dismiss keyboard
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.easeOut(duration: 0.18)) {
                        isHighlighted = false
                    }
                }
            }) {
                Label("Jump to Message", systemImage: "arrowshape.turn.up.left")
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
