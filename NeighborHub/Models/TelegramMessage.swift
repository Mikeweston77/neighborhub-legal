import Foundation

/// Represents a single Telegram message persisted to Firestore by the
/// `telegramWebhook` Cloud Function.
struct TelegramMessage: Identifiable, Codable, Equatable {
    let id: String          // Firestore doc ID  ("{chatId}_{messageId}")
    let messageId: Int
    let chatId: Int
    let chatTitle: String
    let senderName: String
    let text: String
    let mediaType: String   // "photo" | "video" | "audio" | "document" | "none"
    let fileId: String      // Telegram file_id (empty if no media)
    let category: String
    let categories: [String]
    let date: Date

    var hasMedia: Bool { mediaType != "none" && !mediaType.isEmpty }

    var mediaIcon: String {
        switch mediaType {
        case "photo":    return "photo"
        case "video":    return "video"
        case "audio":    return "waveform"
        case "document": return "doc"
        default:         return "ellipsis"
        }
    }
    
    // Compute the Telegram media proxy URL for this message
    func mediaProxyURL(functionBaseURL: String = "https://us-central1-neighborhub-cd47d.cloudfunctions.net") -> URL? {
        guard hasMedia, !fileId.isEmpty else { return nil }
        let urlString = "\(functionBaseURL)/telegramMedia?fileId=\(fileId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fileId)"
        return URL(string: urlString)
    }
}
