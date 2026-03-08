import Foundation
import UIKit

/// AttachmentRecoveryManager monitors and recovers lost marketplace and advert attachments
final class AttachmentRecoveryManager {
    static let shared = AttachmentRecoveryManager()

    private var recoveryTimer: Timer?
    private let recoveryInterval: TimeInterval = 30.0  // Check every 30 seconds

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // stopMonitoring()
        // recoveryTimer = Timer.scheduledTimer(withTimeInterval: recoveryInterval, repeats: true) {
        //     [weak self] _ in
        //     self?.performRecoveryCheck()
        // }
        print("AttachmentRecoveryManager: Monitoring is currently disabled to prevent upload loops.")
    }

    func stopMonitoring() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }

    private func performRecoveryCheck() {
        DispatchQueue.global(qos: .utility).async {
            self.recoverMarketplaceAttachments()
            self.recoverAdvertAttachments()
        }
    }

    // MARK: - Marketplace Recovery

    private func recoverMarketplaceAttachments() {
        // Check for marketplace items with pending uploads that may have been lost
        guard
            let data = UserDefaults.standard.string(forKey: "marketplaceData")?.data(using: .utf8),
            let items = try? JSONDecoder().decode([MarketplaceItemRecovery].self, from: data)
        else {
            return
        }

        for item in items {
            // Check if upload has been pending for more than 5 minutes
            if let lastAttempt = item.lastUploadAttempt,
                Date().timeIntervalSince(lastAttempt) > 300,  // 5 minutes
                item.uploadRetryCount < 3
            {

                print("AttachmentRecoveryManager: Recovering marketplace item \(item.id)")
                retryMarketplaceUpload(item)
            }
        }
    }

    private func retryMarketplaceUpload(_ item: MarketplaceItemRecovery) {
        // Check if we have local image files to retry upload
        var hasLocalImages = false
        var primaryData: Data?
        var additionalData: [Data] = []

        // Load primary image
        if let path = item.imageLocalPath,
            FileManager.default.fileExists(atPath: path),
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        {
            primaryData = data
            hasLocalImages = true
        }

        // Load additional images
        if let paths = item.additionalLocalPaths {
            for path in paths {
                if FileManager.default.fileExists(atPath: path),
                    let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                {
                    additionalData.append(data)
                    hasLocalImages = true
                }
            }
        }

        if hasLocalImages {
            // Create a minimal DTO for retry
            let dto = FirebaseManager.MarketplaceDTO(
                id: item.id,
                owner: item.owner,
                title: item.title,
                description: item.description,
                price: item.price,
                category: item.category,
                condition: ItemCondition(rawValue: item.condition) ?? .good,
                date: item.date,
                contact: item.contact,
                isSold: item.isSold,
                soldDate: item.soldDate,
                isNegotiable: false,
                tags: [],
                location: "Recovery",
                imageURL: nil,
                additionalImageURLs: []
            )

            // Update retry count in local storage
            updateMarketplaceRetryCount(itemId: item.id, newCount: item.uploadRetryCount + 1)

            // Retry upload
            FirebaseManager.shared.createOrUpdateMarketplaceItem(
                dto,
                primaryImageData: primaryData,
                additionalImageData: additionalData
            ) { error in
                if let error = error {
                    print(
                        "AttachmentRecoveryManager: Marketplace retry failed for \(item.id): \(error)"
                    )
                } else {
                    print("AttachmentRecoveryManager: Marketplace retry succeeded for \(item.id)")
                    // Clear retry count on success
                    self.clearMarketplaceRetryCount(itemId: item.id)
                }
            }
        }
    }

    private func updateMarketplaceRetryCount(itemId: UUID, newCount: Int) {
        guard
            let data = UserDefaults.standard.string(forKey: "marketplaceData")?.data(using: .utf8),
            var items = try? JSONDecoder().decode([MarketplaceItemRecovery].self, from: data)
        else {
            return
        }

        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].uploadRetryCount = newCount
            items[index].lastUploadAttempt = Date()

            if let encoded = try? JSONEncoder().encode(items),
                let string = String(data: encoded, encoding: .utf8)
            {
                UserDefaults.standard.set(string, forKey: "marketplaceData")
            }
        }
    }

    private func clearMarketplaceRetryCount(itemId: UUID) {
        updateMarketplaceRetryCount(itemId: itemId, newCount: 0)
    }

    // MARK: - Advert Recovery

    private func recoverAdvertAttachments() {
        // Check AdvertManager's saved data for items with local images but missing storage URLs
        guard let data = UserDefaults.standard.data(forKey: "neighborhub.local.adverts.v1"),
            let adverts = try? JSONDecoder().decode([Advert].self, from: data)
        else {
            return
        }

        for advert in adverts {
            // Check if advert has local images but missing storage URLs
            let hasLocalImages =
                (advert.imageLocalPath != nil)
                || (advert.imageLocalPaths != nil && !advert.imageLocalPaths!.isEmpty)
            let missingStorageURL =
                advert.imageStorageURL == nil
                || (advert.imageStorageURLs == nil || advert.imageStorageURLs!.isEmpty)

            if hasLocalImages && missingStorageURL {
                print("AttachmentRecoveryManager: Recovering advert \(advert.id)")
                retryAdvertUpload(advert)
            }
        }
    }

    private func retryAdvertUpload(_ advert: Advert) {
        // Load images from local paths
        var advertWithData = advert

        // Load primary image
        if let path = advert.imageLocalPath,
            FileManager.default.fileExists(atPath: path),
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        {
            advertWithData.imageData = data
        }

        // Load additional images
        if let paths = advert.imageLocalPaths {
            var datas: [Data] = []
            for path in paths {
                if FileManager.default.fileExists(atPath: path),
                    let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                {
                    datas.append(data)
                }
            }
            if !datas.isEmpty {
                advertWithData.imageDatas = datas
            }
        }

        // Retry upload through FirebaseManager
        FirebaseManager.shared.createOrUpdateAdvert(advertWithData) {
            error, primaryURL, additionalURLs in
            if let error = error {
                print("AttachmentRecoveryManager: Advert retry failed for \(advert.id): \(error)")
            } else {
                print("AttachmentRecoveryManager: Advert retry succeeded for \(advert.id)")
                if let primaryURL = primaryURL {
                    print("  - Primary URL: \(primaryURL)")
                }
                if let additionalURLs = additionalURLs, !additionalURLs.isEmpty {
                    print("  - Additional URLs: \(additionalURLs.count)")
                }
                // Update the advert in UserDefaults with new storage URLs
                self.updateAdvertInUserDefaults(advertWithData)
            }
        }
    }

    private func updateAdvertInUserDefaults(_ updatedAdvert: Advert) {
        guard var adverts = AdvertManager.shared.loadLocalAdverts() else { return }
        if let index = adverts.firstIndex(where: { $0.id == updatedAdvert.id }) {
            adverts[index] = updatedAdvert
            AdvertManager.shared.saveLocalAdverts(adverts)
            print("AttachmentRecoveryManager: Updated advert \(updatedAdvert.id) in UserDefaults with new storage URLs.")
        }
    }

    // MARK: - Supporting Models

    // MARK: - Manual Recovery Triggers

    func forceRecoveryCheck() {
        print("AttachmentRecoveryManager: Force recovery check initiated")
        performRecoveryCheck()
    }

    func recoverSpecificMarketplaceItem(_ itemId: UUID) {
        print("AttachmentRecoveryManager: Specific recovery for marketplace item \(itemId)")
        guard
            let data = UserDefaults.standard.string(forKey: "marketplaceData")?.data(using: .utf8),
            let items = try? JSONDecoder().decode([MarketplaceItemRecovery].self, from: data),
            let item = items.first(where: { $0.id == itemId })
        else {
            return
        }

        retryMarketplaceUpload(item)
    }

    func recoverSpecificAdvert(_ advertId: UUID) {
        print("AttachmentRecoveryManager: Specific recovery for advert \(advertId)")
        guard let data = UserDefaults.standard.data(forKey: "neighborhub.local.adverts.v1"),
            let adverts = try? JSONDecoder().decode([Advert].self, from: data),
            let advert = adverts.first(where: { $0.id == advertId })
        else {
            return
        }

        retryAdvertUpload(advert)
    }
}

// MARK: - Supporting Models

private struct MarketplaceItemRecovery: Codable, Identifiable {
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

// MARK: - Notification Extensions

extension Notification.Name {
    static let attachmentRecoveryStarted = Notification.Name("attachmentRecoveryStarted")
    static let attachmentRecoveryCompleted = Notification.Name("attachmentRecoveryCompleted")
    static let attachmentRecoveryFailed = Notification.Name("attachmentRecoveryFailed")
}
