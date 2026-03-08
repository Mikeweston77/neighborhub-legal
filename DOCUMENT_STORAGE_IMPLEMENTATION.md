# Document Storage Implementation - NeighborHub

## Overview
Implemented a centralized document storage system for managing PDF files and attachments (0.1MB - 100MB) across the app, avoiding Firebase Storage costs by storing files locally in the app's Documents directory.

## Architecture

### DocumentStorageManager (Singleton)
**Location**: `NeighborHub/Managers/DocumentStorageManager.swift`

**Key Features**:
- Centralized file storage in app Documents directory
- Automatic directory creation and management
- File size validation (100MB limit)
- Security scoped resource handling
- File cleanup and maintenance utilities

**Directory Structure**:
```
~/Documents/AppDocuments/
├── Newsletters/     # Newsletter PDF attachments
├── LocalListings/   # Local listing documents
├── Events/          # Event attachments
└── [other features as needed]
```

## Implementation Details

### Core Methods

#### 1. Store Document
```swift
DocumentStorageManager.shared.storeDocument(
    from: sourceURL,
    subdirectory: "Newsletters",  // Optional organization
    preserveFilename: false        // Generate unique names by default
) -> URL?
```

**Features**:
- Validates file size before copying (max 100MB)
- Handles security scoped resources automatically
- Generates unique filenames to prevent collisions
- Falls back to data read/write if copy fails
- Returns permanent URL in app storage

#### 2. Delete Document
```swift
DocumentStorageManager.shared.deleteDocument(at: fileURL) -> Bool
```

**Safety**:
- Only deletes files within AppDocuments directory
- Prevents accidental deletion of system files
- Returns success/failure status

#### 3. File Information
```swift
// Check if file exists
DocumentStorageManager.shared.fileExists(at: fileURL) -> Bool

// Get file size
DocumentStorageManager.shared.getFileSize(at: fileURL) -> Int?

// Format file size for display
DocumentStorageManager.shared.formatFileSize(bytes) -> String  // "2.5 MB"
```

#### 4. Storage Management
```swift
// Get total storage used
DocumentStorageManager.shared.getTotalStorageSize() -> Int

// Clean up old files
DocumentStorageManager.shared.cleanupOldDocuments(
    olderThanDays: 90,              // Delete files older than 90 days
    maxTotalSize: 500 * 1024 * 1024 // Keep total under 500MB
)

// List all documents
DocumentStorageManager.shared.listDocuments(in: "Newsletters") -> [URL]
```

## Integration Points

### 1. Newsletter PDF Attachments

**Workflow**:
1. User selects PDF via `LocalListingDocumentPicker`
2. PDF is copied to `AppDocuments/LocalListings/` (or could be "Newsletters")
3. PDF is converted to preview image for fast display
4. Original PDF URL is saved in `newsletter.fileURL`
5. Preview image is saved in `newsletter.imageData`

**Benefits**:
- Fast preview loading (compressed image)
- Full PDF access via "View Full PDF" button
- No Firebase Storage costs
- Persistent across app launches

### 2. Local Listings
**Updated**: `LocalListingsCard.swift` - Document picker now uses centralized storage

### 3. Events
**Updated**: `EventsView.swift` - Document picker now uses centralized storage

## File Storage vs Firestore Strategy

| Data Type | Storage Method | Reason |
|-----------|---------------|---------|
| Preview images | Firestore (base64) | Small, compressed, fast loading |
| PDF files (0.1-100MB) | Local Documents | Too large for Firestore, avoid Storage costs |
| File URL reference | Firestore (string) | Points to local file for full viewing |
| File metadata | Firestore | File name, size, page count |

## Usage Examples

### Newsletter with PDF Attachment

**CreateNewsletterView**:
```swift
// When PDF is selected
onPDFSelected: { copiedURL, pageImages, metadata in
    // copiedURL is already in AppDocuments directory
    selectedImageFromDoc = pageImages.first  // Preview
    originalPDFURL = copiedURL               // Full PDF reference
}

// When saving newsletter
newsletter.imageData = preview.compressedForFirestore()  // Fast preview
newsletter.fileURL = originalPDFURL                       // Full PDF access
```

**NewsletterDetailView**:
```swift
// Display preview image
Image(uiImage: previewImage)

// "View Full PDF" button
if let pdfURL = newsletter.fileURL, pdfURL.pathExtension == "pdf" {
    Button("View Full PDF") {
        showFullPDF = true  // Opens QLPreviewController
    }
}
```

### Local Listing with Document

**Similar pattern**:
```swift
// Document picker automatically stores in AppDocuments/LocalListings/
let storedURL = DocumentStorageManager.shared.storeDocument(
    from: selectedFile,
    subdirectory: "LocalListings"
)
```

## File Size Management

**Limits**:
- Individual file: 100MB maximum
- Total app storage: Unlimited (but can be managed)

**Cleanup Strategy** (Optional):
```swift
// Run periodically (e.g., on app launch)
DocumentStorageManager.shared.cleanupOldDocuments(
    olderThanDays: 90,              // Delete files older than 3 months
    maxTotalSize: 500 * 1024 * 1024 // Keep total under 500MB
)
```

## Advantages

### 1. Cost Savings
- ✅ No Firebase Storage fees
- ✅ No egress bandwidth charges
- ✅ Unlimited local storage (device dependent)

### 2. Performance
- ✅ Fast preview loading (compressed images)
- ✅ Instant full document access (local files)
- ✅ No network required for viewing

### 3. User Experience
- ✅ Works offline
- ✅ Fast image previews
- ✅ Full PDF functionality (zoom, search, copy)
- ✅ Similar to WhatsApp/Signal pattern

### 4. Maintainability
- ✅ Centralized storage logic
- ✅ Consistent across all features
- ✅ Easy to add new document types
- ✅ Built-in cleanup utilities

## Future Enhancements

### Potential Additions:
1. **Cloud Backup** (Optional)
   - Backup important documents to iCloud Drive
   - User-controlled sync across devices

2. **Storage Analytics**
   - Show user how much space documents are using
   - Per-category storage breakdown

3. **Compression**
   - Auto-compress PDFs over certain size
   - Offer quality vs size tradeoffs

4. **Sharing**
   - Export documents via share sheet
   - Send to other apps

5. **Search & Organization**
   - Search document contents (OCR)
   - Tag and categorize documents
   - Recently viewed documents list

## Testing Checklist

- [x] Create document storage manager
- [x] Update LocalListingDocumentPicker to use centralized storage
- [x] Update EventDocumentPicker to use centralized storage
- [x] Newsletter PDF workflow preserves file URL
- [ ] Test PDF files from 0.1MB to 100MB
- [ ] Verify files persist across app restarts
- [ ] Test file size limit enforcement
- [ ] Verify cleanup utilities work correctly
- [ ] Test "View Full PDF" button in newsletters
- [ ] Confirm no Firebase Storage costs

## Files Modified

1. **Created**:
   - `NeighborHub/Managers/DocumentStorageManager.swift` - Core storage manager

2. **Updated**:
   - `NeighborHub/Views/LocalListingsCard.swift` - Use centralized storage
   - `NeighborHub/Views/EventsView.swift` - Use centralized storage
   - `NeighborHub/Managers/FirebaseManager.swift` - Save fileURL to Firestore
   - `NeighborHub/Views/NewslettersCard.swift` - Preserve originalPDFURL

## Summary

The document storage system provides a robust, cost-effective solution for handling PDF attachments in newsletters and other features. Files are stored locally in a well-organized directory structure, with automatic size validation, security handling, and cleanup utilities. The hybrid preview/full-view approach gives users fast loading times with full document functionality when needed.
