import Foundation
import UIKit

/// Simple helper for saving/loading/deleting images for Adverts.
/// Stores images in Caches/Adverts to avoid being backed up.
final class ImageFileManager {
    static let advertsDirectoryName = "Adverts"

    /// Returns the directory URL for Caches/Adverts, creating it if needed.
    private static func advertsDirectory() throws -> URL {
        let fm = FileManager.default
        // Use Application Support to store user-generated advert images so they persist across app restarts
        // and are not subject to the system clearing Caches. Exclude from iCloud backups as needed.
    let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var dir = appSupport.appendingPathComponent(advertsDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            // Exclude from iCloud backup
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? dir.setResourceValues(resourceValues)
        }
        return dir
    }

    /// Save image data to disk with a suggested filename (will be uniqued). Returns the absolute file path.
    /// - Parameters:
    ///   - data: image data (jpeg/png)
    ///   - suggestedName: base name to use for the file
    /// - Returns: absolute file path string
    static func saveImageData(_ data: Data, suggestedName: String) throws -> String {
        let dir = try advertsDirectory()
        let ext = imageExtension(for: data) ?? "jpg"
        let base = sanitizeFileName(suggestedName)
        var filename = "\(base).\(ext)"
        var attempt = 0
        let fm = FileManager.default
        while fm.fileExists(atPath: dir.appendingPathComponent(filename).path) {
            attempt += 1
            filename = "\(base)-\(attempt).\(ext)"
        }
        let path = dir.appendingPathComponent(filename)
        try data.write(to: path, options: .atomic)
        return path.path
    }

    /// Load UIImage from disk path.
    static func loadImage(atPath path: String) -> UIImage? {
        return UIImage(contentsOfFile: path)
    }

    /// Delete a file at given path if exists.
    static func deleteFile(atPath path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    // MARK: - Migration helpers
    /// Returns the old caches adverts directory if it exists (used by older app versions)
    private static func oldCachesDirectoryIfExists() -> URL? {
        let fm = FileManager.default
        if let caches = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let oldDir = caches.appendingPathComponent(advertsDirectoryName, isDirectory: true)
            if fm.fileExists(atPath: oldDir.path) { return oldDir }
        }
        return nil
    }

    /// Move any existing images from Caches/Adverts into Application Support/Adverts and return a mapping of oldPath->newPath
    static func migrateFromCachesIfNeeded() -> [String: String] {
        var mapping: [String: String] = [:]
        let fm = FileManager.default
        guard let old = oldCachesDirectoryIfExists() else { return mapping }
        do {
            let items = try fm.contentsOfDirectory(atPath: old.path)
            if items.isEmpty { return mapping }
            let newDir = try advertsDirectory()
            for item in items {
                let oldPath = old.appendingPathComponent(item).path
                let newPath = newDir.appendingPathComponent(item).path
                if !fm.fileExists(atPath: newPath) {
                    do { try fm.moveItem(atPath: oldPath, toPath: newPath); mapping[oldPath] = newPath } catch {
                        // If move fails, try copy then delete
                        if (try? fm.copyItem(atPath: oldPath, toPath: newPath)) != nil { try? fm.removeItem(atPath: oldPath); mapping[oldPath] = newPath }
                    }
                } else {
                    // target exists, just remove old
                    try? fm.removeItem(atPath: oldPath)
                    mapping[oldPath] = newPath
                }
            }
            // Optionally remove old dir if empty
            if (try? fm.contentsOfDirectory(atPath: old.path))?.isEmpty ?? false {
                try? fm.removeItem(atPath: old.path)
            }
        } catch {
            print("[ImageFileManager] migration error: \(error)")
        }
        return mapping
    }

    // MARK: - Helpers
    private static func sanitizeFileName(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r\t")
        return s.components(separatedBy: illegal).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imageExtension(for data: Data) -> String? {
        var values = [UInt8](repeating: 0, count: 1)
        data.copyBytes(to: &values, count: 1)
        switch values[0] {
        case 0xFF:
            return "jpg"
        case 0x89:
            return "png"
        case 0x47:
            return "gif"
        case 0x49, 0x4D:
            return "tiff"
        default:
            return nil
        }
    }
}
