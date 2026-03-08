import Foundation
import UIKit

public struct Advert: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var title: String
    public var summary: String
    public var price: Double?
    public var currency: String
    // support multiple images; UI will convert to UIImage when needed
    public var imageData: Data?
    public var imageDatas: [Data]?
    // optional local disk path for attached image file(s)
    public var imageLocalPath: String?
    /// Optional list of local disk paths for multiple attached images.
    public var imageLocalPaths: [String]?
    // optional remote storage URL(s) (preferred when local not available)
    public var imageStorageURL: String?
    public var imageStorageURLs: [String]?
    // Small metadata returned from Firestore when image bytes couldn't be embedded
    // imageCount: number of images attached to the advert
    public var imageCount: Int?
    // imagesPendingUpload: true if Storage uploads haven't completed yet
    public var imagesPendingUpload: Bool?
    public var category: String
    public var locationName: String?
    public var createdAt: Date
    public var expiresAt: Date?
    public var isPinned: Bool
    public var sellerName: String
    public var sellerVerified: Bool
    public var sellerContact: String?
    public var sellerReputation: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        price: Double? = nil,
        currency: String = "USD",
    imageData: Data? = nil,
    imageDatas: [Data]? = nil,
    imageLocalPath: String? = nil,
    imageLocalPaths: [String]? = nil,
    imageStorageURL: String? = nil,
    imageStorageURLs: [String]? = nil,
    imageCount: Int? = nil,
    imagesPendingUpload: Bool? = nil,
        category: String = "General",
        locationName: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        isPinned: Bool = false,
        sellerName: String = "Neighbor",
        sellerVerified: Bool = false
    , sellerContact: String? = nil,
    sellerReputation: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.price = price
        self.currency = currency
        self.imageData = imageData
        // Enforce a maximum of 12 images across arrays to avoid excessive payloads
        if let datas = imageDatas, datas.count > 12 {
            self.imageDatas = Array(datas.prefix(12))
        } else {
            self.imageDatas = imageDatas
        }
        self.imageLocalPath = imageLocalPath
        if let paths = imageLocalPaths, paths.count > 12 {
            self.imageLocalPaths = Array(paths.prefix(12))
        } else {
            self.imageLocalPaths = imageLocalPaths
        }
        self.imageStorageURL = imageStorageURL
        if let urls = imageStorageURLs, urls.count > 12 {
            self.imageStorageURLs = Array(urls.prefix(12))
        } else {
            self.imageStorageURLs = imageStorageURLs
        }
        self.imageCount = imageCount
        self.imagesPendingUpload = imagesPendingUpload
        self.category = category
        self.locationName = locationName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.isPinned = isPinned
        self.sellerName = sellerName
        self.sellerVerified = sellerVerified
    self.sellerContact = sellerContact
    self.sellerReputation = sellerReputation
    }

    public var uiImage: UIImage? {
        // Prefer local disk files if present (support multiple local paths)
        if let paths = imageLocalPaths {
            for path in paths {
                if FileManager.default.fileExists(atPath: path), let img = UIImage(contentsOfFile: path) {
                    return img
                }
            }
        }
        // Backwards compatibility: single local path
        if let path = imageLocalPath {
            if FileManager.default.fileExists(atPath: path), let img = UIImage(contentsOfFile: path) {
                return img
            }
        }
        // Next prefer embedded imageDatas
        if let arr = imageDatas, let first = arr.first {
            return UIImage(data: first)
        }
        // Then single imageData
        if let data = imageData { return UIImage(data: data) }
        // Remote URLs are handled by views (AsyncImage) to avoid blocking sync image creation here
        return nil
    }

    /// Human-friendly price string used by UI cards (e.g. "$12.00")
    public var priceDisplay: String? {
        guard let p = price else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        // Try to set currency code if available
        formatter.currencyCode = currency
        // Fallback: show plain number if formatter fails
        if let s = formatter.string(from: NSNumber(value: p)) {
            return s
        }
        return String(format: "%.2f %@", p, currency)
    }
}
