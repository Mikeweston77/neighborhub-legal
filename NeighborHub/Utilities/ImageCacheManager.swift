import Foundation
import UIKit

/// Manages on-disk caching for chat attachments and marketplace images.
/// - Stores files under Application Support/NeighborHub/ChatImages and MarketplaceImages
/// - Marks files/dir to be excluded from backups
/// - Provides TTL and size-based pruning
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cacheDir: URL
    private let marketplaceCacheDir: URL
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.neighborhub.imagecache")
    
    // In-memory cache for immediate access (while disk write completes)
    private var memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200  // Keep up to 200 images in memory (increased)
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB max (increased)
        cache.evictsObjectsWithDiscardedContent = false  // Don't auto-evict
        return cache
    }()

    // Configurable pruning policy
    var maxCacheSizeBytes: Int64 = 200 * 1024 * 1024  // 200 MB default
    var fileTTL: TimeInterval = 60 * 60 * 24 * 30  // 30 days default

    private init() {
        // Application Support/NeighborHub/ChatImages
        let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let base = appSupport ?? fileManager.temporaryDirectory
        cacheDir = base.appendingPathComponent("NeighborHub/ChatImages", isDirectory: true)
        marketplaceCacheDir = base.appendingPathComponent(
            "NeighborHub/MarketplaceImages", isDirectory: true)

        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: marketplaceCacheDir, withIntermediateDirectories: true)
            try setExcludeFromBackup(url: cacheDir)
            try setExcludeFromBackup(url: marketplaceCacheDir)
        } catch {
            // Non-fatal: log and continue
            print("ImageCacheManager: failed to create cache dir: \(error)")
        }

        // Perform background pruning on init
        ioQueue.async { [weak self] in
            self?.pruneIfNeeded()
        }
    }

    // Compute local filename for a message id
    func localPathForMessage(id: UUID, ext: String = "jpg") -> String {
        return cacheDir.appendingPathComponent("img-\(id.uuidString).\(ext)").path
    }

    // Save data to the cache (atomic) and mark excluded from backup
    func saveData(_ data: Data, forMessage id: UUID, ext: String = "jpg") throws -> String {
        let dest = cacheDir.appendingPathComponent("img-\(id.uuidString).\(ext)")
        try data.write(to: dest, options: .atomic)
        try setExcludeFromBackup(url: dest)
        return dest.path
    }

    // Check if a cached file exists for the message
    func cachedURL(forMessage id: UUID, ext: String = "jpg") -> URL? {
        let url = cacheDir.appendingPathComponent("img-\(id.uuidString).\(ext)")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Pruning
    func pruneIfNeeded() {
        pruneCacheDirectory(cacheDir)
        pruneCacheDirectory(marketplaceCacheDir)
    }

    private func pruneCacheDirectory(_ directory: URL) {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles)

            // Remove files older than TTL
            let cutoff = Date().addingTimeInterval(-fileTTL)
            for url in contents {
                if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                    let mod = attrs.contentModificationDate, mod < cutoff
                {
                    try? fileManager.removeItem(at: url)
                }
            }

            // Recompute contents and enforce max size (split between chat and marketplace)
            let maxSizePerDir = maxCacheSizeBytes / 2
            let remaining = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles)
            var files: [(url: URL, size: Int64, modDate: Date)] = []
            var total: Int64 = 0
            for url in remaining {
                let rv = try url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
                let size = Int64(rv.fileSize ?? 0)
                let mod = rv.contentModificationDate ?? Date()
                files.append((url: url, size: size, modDate: mod))
                total += size
            }

            if total <= maxSizePerDir { return }

            // Sort by oldest first and delete until under budget
            files.sort { $0.modDate < $1.modDate }
            var idx = 0
            while total > maxSizePerDir && idx < files.count {
                let f = files[idx]
                try? fileManager.removeItem(at: f.url)
                total -= f.size
                idx += 1
            }
        } catch {
            print("ImageCacheManager prune error for \(directory): \(error)")
        }
    }

    // Set NSURLIsExcludedFromBackupKey attribute
    private func setExcludeFromBackup(url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(resourceValues)
    }

    // MARK: - Marketplace Image Caching

    /// Cache a marketplace item image
    /// - Parameters:
    ///   - image: The UIImage to cache
    ///   - itemId: Marketplace item ID
    ///   - imageType: Type of image (primary, additional_0, additional_1, etc.)
    func cacheMarketplaceImage(_ image: UIImage, itemId: UUID, imageType: String = "primary") {
        let cacheKey = "marketplace-\(itemId.uuidString)-\(imageType)" as NSString
        
        // Store in memory cache immediately for instant access
        memoryCache.setObject(image, forKey: cacheKey)
        print("[ImageCache] ✅ Cached \(imageType) for item \(itemId) in MEMORY")
        
        // Then write to disk asynchronously
        ioQueue.async { [weak self] in
            guard let self = self else { return }

            let filename = "item-\(itemId.uuidString)-\(imageType).jpg"
            let url = self.marketplaceCacheDir.appendingPathComponent(filename)

            guard let data = image.jpegData(compressionQuality: 0.8) else { return }

            do {
                try data.write(to: url, options: .atomic)
                try self.setExcludeFromBackup(url: url)
                print("[ImageCache] ✅ Cached \(imageType) for item \(itemId) to DISK")
            } catch {
                print("[ImageCache] ❌ Failed to cache \(imageType) to disk: \(error)")
            }
        }
    }

    /// Retrieve a cached marketplace image synchronously
    /// - Parameters:
    ///   - itemId: Marketplace item ID
    ///   - imageType: Type of image (primary, additional_0, additional_1, etc.)
    /// - Returns: Cached UIImage if available
    func cachedMarketplaceImage(itemId: UUID, imageType: String = "primary") -> UIImage? {
        let cacheKey = "marketplace-\(itemId.uuidString)-\(imageType)" as NSString
        
        // Check memory cache first for instant access
        if let cached = memoryCache.object(forKey: cacheKey) {
            print("[ImageCache] ✅ Found \(imageType) for item \(itemId) in MEMORY")
            return cached
        }
        
        // Fall back to disk cache
        let filename = "item-\(itemId.uuidString)-\(imageType).jpg"
        let url = marketplaceCacheDir.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: url.path) else {
            print("[ImageCache] ❌ NOT FOUND \(imageType) for item \(itemId) (neither memory nor disk)")
            return nil
        }

        // Update modification date for LRU
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        let image = UIImage(contentsOfFile: url.path)
        
        // Store in memory cache for next access
        if let image = image {
            memoryCache.setObject(image, forKey: cacheKey)
            print("[ImageCache] ✅ Loaded \(imageType) for item \(itemId) from DISK → cached to MEMORY")
        } else {
            print("[ImageCache] ❌ Failed to load \(imageType) from disk for item \(itemId)")
        }
        
        return image
    }

    /// Retrieve a cached marketplace image asynchronously
    /// - Parameters:
    ///   - itemId: Marketplace item ID
    ///   - imageType: Type of image (primary, additional_0, additional_1, etc.)
    ///   - completion: Completion handler with the cached image
    func cachedMarketplaceImageAsync(
        itemId: UUID, imageType: String = "primary", completion: @escaping (UIImage?) -> Void
    ) {
        ioQueue.async { [weak self] in
            let image = self?.cachedMarketplaceImage(itemId: itemId, imageType: imageType)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Remove cached images for a marketplace item
    /// - Parameter itemId: Marketplace item ID
    func removeCachedMarketplaceImages(itemId: UUID) {
        // Remove from memory cache
        let keyPrefix = "marketplace-\(itemId.uuidString)-"
        for imageType in ["primary"] + (0..<10).map({ "additional_\($0)" }) {
            let cacheKey = "\(keyPrefix)\(imageType)" as NSString
            memoryCache.removeObject(forKey: cacheKey)
        }
        
        // Remove from disk cache
        ioQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let contents = try self.fileManager.contentsOfDirectory(
                    at: self.marketplaceCacheDir, includingPropertiesForKeys: nil)
                let itemPrefix = "item-\(itemId.uuidString)-"

                for url in contents {
                    if url.lastPathComponent.hasPrefix(itemPrefix) {
                        try? self.fileManager.removeItem(at: url)
                    }
                }
            } catch {
                print("Failed to remove cached marketplace images: \(error)")
            }
        }
    }

    /// Get marketplace cache size in bytes
    func getMarketplaceCacheSize() -> Int64 {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: marketplaceCacheDir, includingPropertiesForKeys: [.fileSizeKey])
            return contents.compactMap { url -> Int64? in
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                return Int64(resourceValues?.fileSize ?? 0)
            }.reduce(0, +)
        } catch {
            return 0
        }
    }
}

// MARK: - UIImage Extension for Marketplace Caching

extension UIImage {
    /// Cache this image for a marketplace item
    /// - Parameters:
    ///   - itemId: Marketplace item ID
    ///   - imageType: Type of image (primary, additional_0, additional_1, etc.)
    func cacheForMarketplace(itemId: UUID, imageType: String = "primary") {
        ImageCacheManager.shared.cacheMarketplaceImage(self, itemId: itemId, imageType: imageType)
    }

    /// Retrieve a cached marketplace image
    /// - Parameters:
    ///   - itemId: Marketplace item ID
    ///   - imageType: Type of image (primary, additional_0, additional_1, etc.)
    /// - Returns: Cached UIImage if available
    static func cachedMarketplace(itemId: UUID, imageType: String = "primary") -> UIImage? {
        return ImageCacheManager.shared.cachedMarketplaceImage(itemId: itemId, imageType: imageType)
    }
}
