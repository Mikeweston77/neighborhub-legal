//
//  DocumentStorageManager.swift
//  NeighborHub
//
//  Centralized document storage manager for handling PDF and other file attachments
//  Stores files locally in app Documents directory to avoid Firebase Storage costs
//

import Foundation

/// Manages local document storage for PDF files and attachments
class DocumentStorageManager {
    static let shared = DocumentStorageManager()
    
    private let fileManager = FileManager.default
    private let maxFileSizeBytes: Int = 100 * 1024 * 1024 // 100MB limit
    
    private init() {}
    
    // MARK: - Directory Management
    
    /// Get the main Documents directory for the app
    private var documentsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    /// Get or create the app's document storage directory
    /// - Parameter subdirectory: Optional subdirectory name (e.g., "Newsletters", "Events")
    /// - Returns: URL to the storage directory
    func getStorageDirectory(subdirectory: String? = nil) -> URL? {
        guard let docsDir = documentsDirectory else {
            print("DocumentStorageManager: Failed to access documents directory")
            return nil
        }
        
        let baseDir = docsDir.appendingPathComponent("AppDocuments", isDirectory: true)
        let targetDir = subdirectory != nil ? baseDir.appendingPathComponent(subdirectory!, isDirectory: true) : baseDir
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: targetDir.path) {
            do {
                try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
                print("DocumentStorageManager: Created directory at \(targetDir.path)")
            } catch {
                print("DocumentStorageManager: Error creating directory: \(error)")
                return nil
            }
        }
        
        return targetDir
    }
    
    // MARK: - File Operations
    
    /// Copy a document from a temporary/external location to permanent app storage
    /// - Parameters:
    ///   - sourceURL: The temporary URL from document picker or external source
    ///   - subdirectory: Optional subdirectory for organization (e.g., "Newsletters", "Events")
    ///   - preserveFilename: If true, keeps original filename; if false, generates unique name
    /// - Returns: Permanent URL in app storage, or nil if copy failed
    func storeDocument(from sourceURL: URL, subdirectory: String? = nil, preserveFilename: Bool = false) -> URL? {
        guard let storageDir = getStorageDirectory(subdirectory: subdirectory) else {
            print("DocumentStorageManager: Failed to get storage directory")
            return nil
        }
        
        // Check file size before copying
        if let fileSize = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            if fileSize > maxFileSizeBytes {
                print("DocumentStorageManager: File too large (\(formatFileSize(fileSize))), max allowed is \(formatFileSize(maxFileSizeBytes))")
                return nil
            }
            print("DocumentStorageManager: File size: \(formatFileSize(fileSize))")
        }
        
        // Generate destination URL
        let filename = preserveFilename ? sourceURL.lastPathComponent : "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destinationURL = storageDir.appendingPathComponent(filename)
        
        // Start accessing security scoped resource if needed
        var didStartAccessing = false
        if sourceURL.startAccessingSecurityScopedResource() {
            didStartAccessing = true
        }
        
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.removeItem(at: destinationURL)
                print("DocumentStorageManager: Removed existing file at destination")
            } catch {
                print("DocumentStorageManager: Error removing existing file: \(error)")
            }
        }
        
        // Try to copy file
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            print("DocumentStorageManager: Successfully copied file to \(destinationURL.path)")
            
            // Verify the file was actually copied
            if fileManager.fileExists(atPath: destinationURL.path) {
                print("DocumentStorageManager: Verified file exists at destination")
                return destinationURL
            } else {
                print("DocumentStorageManager: ERROR - Copy reported success but file doesn't exist!")
                return nil
            }
        } catch {
            print("DocumentStorageManager: Copy failed, trying fallback method: \(error)")
            
            // Fallback: read data and write
            do {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: destinationURL)
                print("DocumentStorageManager: Successfully wrote file using fallback method")
                
                // Verify the file was actually written
                if fileManager.fileExists(atPath: destinationURL.path) {
                    print("DocumentStorageManager: Verified file exists at destination (fallback)")
                    return destinationURL
                } else {
                    print("DocumentStorageManager: ERROR - Write reported success but file doesn't exist!")
                    return nil
                }
            } catch {
                print("DocumentStorageManager: Fallback also failed: \(error)")
                return nil
            }
        }
    }
    
    /// Delete a document from app storage
    /// - Parameter fileURL: The URL of the file to delete
    /// - Returns: True if deletion succeeded, false otherwise
    @discardableResult
    func deleteDocument(at fileURL: URL) -> Bool {
        // Safety check: only delete files in our AppDocuments directory
        guard let storageDir = getStorageDirectory(),
              fileURL.path.hasPrefix(storageDir.path) else {
            print("DocumentStorageManager: Refusing to delete file outside app storage: \(fileURL.path)")
            return false
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("DocumentStorageManager: File doesn't exist: \(fileURL.path)")
            return false
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("DocumentStorageManager: Deleted file: \(fileURL.lastPathComponent)")
            return true
        } catch {
            print("DocumentStorageManager: Error deleting file: \(error)")
            return false
        }
    }
    
    /// Check if a file exists in app storage
    /// - Parameter fileURL: The URL to check
    /// - Returns: True if file exists and is readable
    func fileExists(at fileURL: URL) -> Bool {
        return fileManager.fileExists(atPath: fileURL.path) && fileManager.isReadableFile(atPath: fileURL.path)
    }
    
    /// Get file size in bytes
    /// - Parameter fileURL: The URL of the file
    /// - Returns: File size in bytes, or nil if unavailable
    func getFileSize(at fileURL: URL) -> Int? {
        return try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    
    /// Get formatted file size string
    /// - Parameter bytes: Size in bytes
    /// - Returns: Human-readable string like "2.5 MB"
    func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Storage Management
    
    /// Get total size of all stored documents
    /// - Returns: Total size in bytes
    func getTotalStorageSize() -> Int {
        guard let storageDir = getStorageDirectory() else { return 0 }
        
        var totalSize = 0
        
        if let enumerator = fileManager.enumerator(at: storageDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += fileSize
                }
            }
        }
        
        return totalSize
    }
    
    /// Clean up old documents based on age or size limits
    /// - Parameters:
    ///   - olderThanDays: Delete files older than this many days (nil = don't check age)
    ///   - maxTotalSize: If total storage exceeds this, delete oldest files (nil = no limit)
    func cleanupOldDocuments(olderThanDays: Int? = nil, maxTotalSize: Int? = nil) {
        guard let storageDir = getStorageDirectory() else { return }
        
        var files: [(url: URL, date: Date, size: Int)] = []
        
        // Collect all files with metadata
        if let enumerator = fileManager.enumerator(at: storageDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let date = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    files.append((url: fileURL, date: date, size: size))
                }
            }
        }
        
        // Sort by date (oldest first)
        files.sort { $0.date < $1.date }
        
        var deletedCount = 0
        var freedSpace = 0
        
        // Delete files older than specified days
        if let maxAge = olderThanDays {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAge, to: Date()) ?? Date()
            
            for file in files where file.date < cutoffDate {
                if deleteDocument(at: file.url) {
                    deletedCount += 1
                    freedSpace += file.size
                }
            }
        }
        
        // Delete oldest files if total size exceeds limit
        if let maxSize = maxTotalSize {
            var currentTotal = getTotalStorageSize()
            
            for file in files where currentTotal > maxSize {
                if deleteDocument(at: file.url) {
                    deletedCount += 1
                    freedSpace += file.size
                    currentTotal -= file.size
                }
            }
        }
        
        if deletedCount > 0 {
            print("DocumentStorageManager: Cleanup deleted \(deletedCount) files, freed \(formatFileSize(freedSpace))")
        }
    }
    
    /// List all documents in storage
    /// - Parameter subdirectory: Optional subdirectory to list
    /// - Returns: Array of file URLs
    func listDocuments(in subdirectory: String? = nil) -> [URL] {
        guard let storageDir = getStorageDirectory(subdirectory: subdirectory) else { return [] }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            return files.filter { !$0.hasDirectoryPath }
        } catch {
            print("DocumentStorageManager: Error listing documents: \(error)")
            return []
        }
    }
}

// MARK: - Document Info

struct DocumentInfo {
    let url: URL
    let filename: String
    let fileSize: Int
    let creationDate: Date?
    let modificationDate: Date?
    let fileExtension: String
    
    var formattedSize: String {
        DocumentStorageManager.shared.formatFileSize(fileSize)
    }
    
    var isPDF: Bool {
        fileExtension.lowercased() == "pdf"
    }
    
    init?(url: URL) {
        guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]) else {
            return nil
        }
        
        self.url = url
        self.filename = url.lastPathComponent
        self.fileSize = resources.fileSize ?? 0
        self.creationDate = resources.creationDate
        self.modificationDate = resources.contentModificationDate
        self.fileExtension = url.pathExtension
    }
}
