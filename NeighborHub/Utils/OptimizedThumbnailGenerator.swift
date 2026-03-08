//
//  OptimizedThumbnailGenerator.swift
//  NeighborHub
//
//  Created for performance optimized thumbnail generation
//

import Foundation
import UIKit
import PDFKit
import UniformTypeIdentifiers

/// Optimized thumbnail generation with caching and size constraints
func generateThumbnailFromFile(url: URL, maxSize: CGSize = CGSize(width: 150, height: 150)) -> UIImage? {
    // Check for cached thumbnail first
    let cacheKey = "\(url.lastPathComponent)_\(Int(maxSize.width))x\(Int(maxSize.height))"
    if let cachedImage = ThumbnailCache.shared.getThumbnail(key: cacheKey) {
        return cachedImage
    }
    
    guard url.startAccessingSecurityScopedResource() else {
        print("OptimizedThumbnailGenerator: Cannot access security scoped resource: \(url)")
        return nil
    }
    defer { url.stopAccessingSecurityScopedResource() }
    
    let fileExtension = url.pathExtension.lowercased()
    var thumbnail: UIImage?
    
    switch fileExtension {
    case "pdf":
        thumbnail = generatePDFThumbnail(url: url, maxSize: maxSize)
    case "jpg", "jpeg", "png", "heic", "heif":
        thumbnail = generateImageThumbnail(url: url, maxSize: maxSize)
    case "mp4", "mov", "avi":
        thumbnail = generateVideoThumbnail(url: url, maxSize: maxSize)
    default:
        thumbnail = generateGenericFileThumbnail(url: url, maxSize: maxSize)
    }
    
    // Cache the generated thumbnail
    if let thumbnail = thumbnail {
        ThumbnailCache.shared.setThumbnail(image: thumbnail, key: cacheKey)
    }
    
    return thumbnail
}

private func generatePDFThumbnail(url: URL, maxSize: CGSize) -> UIImage? {
    guard let pdfDocument = PDFDocument(url: url),
          let firstPage = pdfDocument.page(at: 0) else {
        return nil
    }
    
    let pageRect = firstPage.bounds(for: .mediaBox)
    let scale = min(maxSize.width / pageRect.width, maxSize.height / pageRect.height)
    let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
    
    let renderer = UIGraphicsImageRenderer(size: scaledSize)
    return renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: scaledSize))
        
        context.cgContext.scaleBy(x: scale, y: scale)
        firstPage.draw(with: .mediaBox, to: context.cgContext)
    }
}

private func generateImageThumbnail(url: URL, maxSize: CGSize) -> UIImage? {
    // Use ImageIO for memory-efficient thumbnail generation
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(maxSize.width, maxSize.height)
    ]
    
    guard let thumbnailCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
        return nil
    }
    
    return UIImage(cgImage: thumbnailCGImage)
}

private func generateVideoThumbnail(url: URL, maxSize: CGSize) -> UIImage? {
    // Placeholder for video thumbnail - could use AVAssetImageGenerator
    return generateGenericFileThumbnail(url: url, maxSize: maxSize)
}

private func generateGenericFileThumbnail(url: URL, maxSize: CGSize) -> UIImage? {
    let fileExtension = url.pathExtension.lowercased()
    let fileName = url.deletingPathExtension().lastPathComponent
    
    let renderer = UIGraphicsImageRenderer(size: maxSize)
    return renderer.image { context in
        // Background
        UIColor.systemGray5.setFill()
        context.fill(CGRect(origin: .zero, size: maxSize))
        
        // File icon (simplified)
        let iconRect = CGRect(x: maxSize.width * 0.3, y: maxSize.height * 0.2, 
                             width: maxSize.width * 0.4, height: maxSize.height * 0.4)
        UIColor.systemBlue.setFill()
        context.fill(iconRect)
        
        // Extension text
        let text = fileExtension.uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: min(maxSize.width * 0.15, 12)),
            .foregroundColor: UIColor.label
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (maxSize.width - textSize.width) / 2,
            y: maxSize.height * 0.7,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
    }
}

/// In-memory thumbnail cache for performance
class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB
    
    private init() {
        cache.totalCostLimit = maxCacheSize
        cache.countLimit = 100
    }
    
    func getThumbnail(key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setThumbnail(image: UIImage, key: String) {
        let cost = Int(image.size.width * image.size.height * 4) // Approximate bytes
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}