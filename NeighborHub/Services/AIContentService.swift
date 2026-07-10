import Foundation

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

public protocol AIContentProviding {
    func generateHomeChatReply(message: String, history: [[String: Any]], contextLimits: [String: Any]) async -> String?
    func generateNewsletterSuggestion(title: String, category: String, subcategory: String?) async -> String?
    func generateListingSuggestion(title: String, category: String, subcategory: String?) async -> String?
}

public struct AIContentService: AIContentProviding {
    public static let shared = AIContentService()

    private let callableName = "assistantProxyReply"

    public func generateHomeChatReply(message: String, history: [[String: Any]], contextLimits: [String: Any] = [:]) async -> String? {
        let resolvedContextLimits: [String: Any] = contextLimits.isEmpty ? [
            "listings": 20,
            "events": 20,
            "incidents": 20,
            "communityMessages": 20,
            "newsletters": 20
        ] : contextLimits

        let payload: [String: Any] = [
            "message": message,
            "history": history,
            "context": "home_ai_chat",
            "model": "gemini-2.0-flash",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "currentTimestamp": ISO8601DateFormatter().string(from: Date()),
            "contextLimits": resolvedContextLimits
        ]

        return await hostedReply(payload: payload)
    }

    public func generateNewsletterSuggestion(title: String, category: String, subcategory: String?) async -> String? {
        let prompt = buildPrompt(
            kind: "newsletter",
            title: title,
            category: category,
            subcategory: subcategory,
            instructions: "Write a polished neighborhood newsletter draft. Keep the tone warm, concise, and ready to publish. Return only the draft text."
        )
        return await hostedReply(payload: [
            "message": prompt,
            "history": [],
            "context": "newsletters",
            "model": "gemini-2.0-flash",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "currentTimestamp": ISO8601DateFormatter().string(from: Date()),
            "contextLimits": [
                "listings": 24,
                "newsletters": 24,
                "events": 0,
                "incidents": 0,
                "communityMessages": 0
            ]
        ])
    }

    public func generateListingSuggestion(title: String, category: String, subcategory: String?) async -> String? {
        let prompt = buildPrompt(
            kind: "listing",
            title: title,
            category: category,
            subcategory: subcategory,
            instructions: "Write a polished neighborhood listing draft. Keep it practical, friendly, and ready to post. Return only the draft text."
        )
        return await hostedReply(payload: [
            "message": prompt,
            "history": [],
            "context": "listings",
            "model": "gemini-2.0-flash",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "currentTimestamp": ISO8601DateFormatter().string(from: Date()),
            "contextLimits": [
                "listings": 24,
                "newsletters": 24,
                "events": 0,
                "incidents": 0,
                "communityMessages": 0
            ]
        ])
    }

    private func buildPrompt(kind: String, title: String, category: String, subcategory: String?, instructions: String) -> String {
        var lines = [
            instructions,
            "Title: \(title)",
            "Category: \(category)"
        ]

        if let subcategory, !subcategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Subcategory: \(subcategory)")
        }

        lines.append("Audience: local neighborhood residents")
        lines.append("Kind: \(kind)")
        return lines.joined(separator: "\n")
    }

    private func hostedReply(payload: [String: Any]) async -> String? {
        #if canImport(FirebaseFunctions)
        let callable = Functions.functions().httpsCallable(callableName)

        do {
            let result = try await callable.call(payload)
            if let data = result.data as? [String: Any] {
                if let reply = data["reply"] as? String,
                   !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return reply
                }
                if let reply = data["text"] as? String,
                   !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return reply
                }
            }
        } catch {
            print("⚠️ AIContentService hosted draft failed: \(error)")
        }
        #endif

        return nil
    }
}