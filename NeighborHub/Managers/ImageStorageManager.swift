import Foundation
import UIKit

/// Lightweight shim for historical ImageStorageManager references in the project.
/// For now it forwards to ImageFileManager utilities used for caching advert images.
final class ImageStorageManager {
    static let shared = ImageStorageManager()

    private init() {}

    /// Save image data to cache and return local path (or nil on failure)
    func saveImageData(_ data: Data, suggestedName: String? = nil) -> String? {
        let name = suggestedName ?? UUID().uuidString
        return (try? ImageFileManager.saveImageData(data, suggestedName: name))
    }

    /// Load UIImage from a local path
    func loadImage(atPath path: String) -> UIImage? {
        return ImageFileManager.loadImage(atPath: path)
    }

    /// Delete a cached image file
    func deleteImage(atPath path: String) {
        ImageFileManager.deleteFile(atPath: path)
    }
}
