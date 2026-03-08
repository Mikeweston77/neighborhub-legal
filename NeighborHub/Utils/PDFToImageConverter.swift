//
//  PDFToImageConverter.swift
//  NeighborHub
//
//  Created for Firebase Storage-free PDF handling
//

import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
typealias PlatformImageRenderer = UIGraphicsImageRenderer
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformImageRenderer = NSGraphicsContext
#endif

/// Converts PDFs to images to avoid Firebase Storage complications
class PDFToImageConverter {
    
    /// Convert PDF to a single preview image (first page) - for security scoped resources
    static func convertPDFToPreviewImage(_ pdfURL: URL, maxSize: CGSize = CGSize(width: 400, height: 600)) -> PlatformImage? {
        print("PDFToImageConverter: Starting PDF preview conversion for: \(pdfURL.lastPathComponent)")
        
        guard pdfURL.startAccessingSecurityScopedResource() else {
            print("PDFToImageConverter: Cannot access security scoped resource")
            return nil
        }
        defer { pdfURL.stopAccessingSecurityScopedResource() }
        
        return convertLocalPDFToPreviewImage(pdfURL, maxSize: maxSize)
    }
    
    /// Convert local PDF to a single preview image (first page) - for files already in app directory
    static func convertLocalPDFToPreviewImage(_ pdfURL: URL, maxSize: CGSize = CGSize(width: 400, height: 600)) -> PlatformImage? {
        print("PDFToImageConverter: Starting local PDF preview conversion for: \(pdfURL.lastPathComponent)")
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            print("PDFToImageConverter: Cannot create PDF document from URL")
            return nil
        }
        
        print("PDFToImageConverter: PDF loaded successfully, has \(pdfDocument.pageCount) pages")
        
        let pageRect = firstPage.bounds(for: .mediaBox)
        let scale = min(maxSize.width / pageRect.width, maxSize.height / pageRect.height)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            // White background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            // Fix orientation for iOS coordinate system
            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: scaledSize.height)
            cgContext.scaleBy(x: scale, y: -scale)
            
            // Draw PDF page
            firstPage.draw(with: .mediaBox, to: cgContext)
        }
        #else
        // macOS fallback
        let image = NSImage(size: scaledSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: scaledSize).fill()
        let context = NSGraphicsContext.current?.cgContext
        context?.scaleBy(x: scale, y: scale)
        firstPage.draw(with: .mediaBox, to: context!)
        image.unlockFocus()
        #endif
        
        print("PDFToImageConverter: Successfully converted PDF to preview image (\(Int(scaledSize.width))x\(Int(scaledSize.height)))")
        return image
    }
    
    /// Convert PDF to multiple page images (for multi-page documents) - for security scoped resources
    static func convertPDFToPageImages(_ pdfURL: URL, maxSize: CGSize = CGSize(width: 400, height: 600)) -> [PlatformImage] {
        guard pdfURL.startAccessingSecurityScopedResource() else {
            print("PDFToImageConverter: Cannot access security scoped resource")
            return []
        }
        defer { pdfURL.stopAccessingSecurityScopedResource() }
        
        return convertLocalPDFToPageImages(pdfURL, maxSize: maxSize)
    }
    
    /// Convert local PDF to multiple page images (for multi-page documents) - for files already in app directory
    static func convertLocalPDFToPageImages(_ pdfURL: URL, maxSize: CGSize = CGSize(width: 400, height: 600)) -> [PlatformImage] {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            print("PDFToImageConverter: Cannot create PDF document from URL")
            return []
        }
        
        var images: [PlatformImage] = []
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<min(pageCount, 5) { // Limit to first 5 pages
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            let pageRect = page.bounds(for: .mediaBox)
            let scale = min(maxSize.width / pageRect.width, maxSize.height / pageRect.height)
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            #if canImport(UIKit)
            let renderer = UIGraphicsImageRenderer(size: scaledSize)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: scaledSize))
                
                // Fix orientation for iOS coordinate system
                let cgContext = context.cgContext
                cgContext.translateBy(x: 0, y: scaledSize.height)
                cgContext.scaleBy(x: scale, y: -scale)
                
                page.draw(with: .mediaBox, to: cgContext)
            }
            #else
            let image = NSImage(size: scaledSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: scaledSize).fill()
            let context = NSGraphicsContext.current?.cgContext
            context?.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context!)
            image.unlockFocus()
            #endif
            
            images.append(image)
        }
        
        print("PDFToImageConverter: Converted \(images.count) pages from PDF")
        return images
    }
    
    /// Store PDF metadata and page count for reference - for security scoped resources
    static func extractPDFMetadata(_ pdfURL: URL) -> PDFMetadata? {
        guard pdfURL.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { pdfURL.stopAccessingSecurityScopedResource() }
        
        return extractLocalPDFMetadata(pdfURL)
    }
    
    /// Store PDF metadata and page count for reference - for files already in app directory
    static func extractLocalPDFMetadata(_ pdfURL: URL) -> PDFMetadata? {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            return nil
        }
        
        let fileName = pdfURL.lastPathComponent
        let pageCount = pdfDocument.pageCount
        let fileSize = (try? pdfURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        
        return PDFMetadata(
            fileName: fileName,
            pageCount: pageCount,
            fileSize: fileSize,
            originalURL: pdfURL
        )
    }
}

/// Metadata structure for PDF files
struct PDFMetadata: Codable {
    let fileName: String
    let pageCount: Int
    let fileSize: Int
    let originalURL: URL?
    
    var displaySize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

/// Enhanced image compression specifically for PDF-converted images
#if canImport(UIKit)
extension UIImage {
    func compressedForPDFPreview() -> Data? {
        // Higher quality for PDF text readability
        return jpegData(compressionQuality: 0.85)?.compressed()
    }
}
#else
extension NSImage {
    func compressedForPDFPreview() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.compressed()
    }
}
#endif

extension Data {
    func compressed() -> Data? {
        do {
            return try (self as NSData).compressed(using: .lzfse) as Data?
        } catch {
            print("PDFToImageConverter: Failed to compress data: \(error)")
            return nil
        }
    }
}