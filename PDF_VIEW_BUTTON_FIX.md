# "View Full PDF" Button Fix - Implementation Complete

## Problem Summary
When users attached PDF documents to newsletters and local listings, the "View Full PDF" button was not appearing in the detail views, preventing access to the full document.

## Root Causes Identified

### 1. Newsletters Issue
**Problem**: Newsletter `fileURL` was being saved to Firestore but NOT being loaded back when fetching newsletters.

**Location**: `FirebaseManager.swift` - `newsletterFrom(data:)` function (lines 867-970)

**Root Cause**: The function was only checking for `fileData` in Firestore and creating temporary files from that data, but it never checked if there was a stored `fileURL` string in Firestore.

**Fix Applied**: Added code to first check for and load the `fileURL` from Firestore before attempting to create temporary files from `fileData`.

```swift
// First, check if we have a stored fileURL (for locally saved PDFs)
if let fileURLString = data["fileURL"] as? String, let url = URL(string: fileURLString) {
    fileURL = url
    print("FirebaseManager: Found newsletter fileURL in Firestore: \(url.lastPathComponent)")
}
```

### 2. Local Listings Issues

#### Issue A: PDF URL Being Cleared After Conversion
**Problem**: After converting a PDF to preview images, the original PDF URL was being cleared.

**Location**: `LocalListingsCard.swift` - `handlePDFConversionResults` function

**Root Cause**: Lines that explicitly cleared the URLs:
```swift
selectedFileURL = nil
originalFileURL = nil
```

**Fix Applied**: Changed to preserve the original PDF URL:
```swift
// Keep the original PDF URL for full viewing
originalFileURL = copiedURL
selectedFileURL = nil  // Clear temp URL
```

#### Issue B: PDF URL Not Saved When Creating Listing
**Problem**: The `createListing()` function didn't save the `originalFileURL` to the listing object.

**Location**: `LocalListingsCard.swift` - `createListing()` function

**Fix Applied**: Added code to save the original PDF URL:
```swift
// Store original PDF URL if we converted a PDF (for hybrid preview/full view system)
if let pdfURL = originalFileURL, pdfURL.pathExtension.lowercased() == "pdf" {
    listing.fileURL = pdfURL
    print("CreateListingView: Stored original PDF URL for full viewing: \(pdfURL.lastPathComponent)")
}
```

#### Issue C: PDF URL Cleared When Editing Listing
**Problem**: The `EditListingView` save function was clearing `fileURL` whenever images were present.

**Location**: `LocalListingsCard.swift` - EditListingView save logic

**Root Cause**: Every image branch set `updatedListing.fileURL = nil`

**Fix Applied**: Preserve the original PDF URL instead of clearing it:
```swift
// Keep original PDF URL if we have one (for hybrid preview/full view system)
if let pdfURL = originalFileURL, pdfURL.pathExtension.lowercased() == "pdf" {
    updatedListing.fileURL = pdfURL
    print("EditListingView: Preserved original PDF URL for full viewing: \(pdfURL.lastPathComponent)")
} else {
    updatedListing.fileURL = nil
}
```

#### Issue D: No "View Full PDF" Button in Detail View
**Problem**: Local listing detail view had no button to open the full PDF.

**Location**: `LocalListingsCard.swift` - `ListingDetailView`

**Fix Applied**: Added "View Full PDF" button matching newsletter implementation:
```swift
// If this is a PDF preview, show "View Full PDF" button
if let fileURL = listing.fileURL, fileURL.pathExtension.lowercased() == "pdf" {
    Button(action: { showFilePreview = true }) {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundColor(.accentColor)
            Text("View Full PDF")
                .font(.caption)
                .foregroundColor(.accentColor)
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }
    .buttonStyle(PlainButtonStyle())
}
```

#### Issue E: No Sheet Presentation for PDF Preview
**Problem**: No sheet modifier to display the PDF when button is tapped.

**Location**: `LocalListingsCard.swift` - `ListingDetailView`

**Fix Applied**: Added sheet presentation using `QuickLookPreview`:
```swift
.sheet(isPresented: $showFilePreview) {
    if let fileURL = listing.fileURL {
        NavigationView {
            QuickLookPreview(url: fileURL)
                .navigationTitle("PDF Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text(fileURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showFilePreview = false
                        }
                    }
                }
        }
    }
}
```

## Files Modified

1. **FirebaseManager.swift**
   - Updated `newsletterFrom(data:)` to load `fileURL` from Firestore
   - Now checks for stored PDF URLs before creating temporary files

2. **LocalListingsCard.swift**
   - `handlePDFConversionResults`: Preserves original PDF URL
   - `createListing()`: Saves original PDF URL to listing
   - `EditListingView`: Preserves PDF URL when updating listing
   - `ListingDetailView`: Added "View Full PDF" button and sheet presentation

## How It Works Now

### Hybrid PDF System
Both newsletters and local listings now use a hybrid approach:

1. **Preview Images** (imageData/imagesData)
   - PDF is converted to preview images for fast loading
   - Images stored in Firestore for quick display
   - Shows in card/list views

2. **Original PDF** (fileURL)
   - Original PDF file stored in local app Documents folder
   - URL string saved to Firestore
   - Accessible via "View Full PDF" button
   - Opens in QuickLookPreview for full document viewing

### User Flow
1. User attaches a PDF to a newsletter or local listing
2. PDF is copied to DocumentStorageManager (~/Documents/AppDocuments/)
3. PDF is converted to preview images for display
4. Both preview images AND original PDF URL are saved
5. Card shows preview images with "View Full PDF" button
6. Tapping button opens full PDF in QuickLook viewer

## Testing Checklist

- [ ] Create new newsletter with PDF attachment - verify button appears
- [ ] Create new local listing with PDF attachment - verify button appears
- [ ] Edit existing newsletter with PDF - verify URL preserved
- [ ] Edit existing local listing with PDF - verify URL preserved
- [ ] Tap "View Full PDF" button - verify PDF opens in QuickLook
- [ ] Check Firestore - verify `fileURL` field is saved
- [ ] Restart app - verify PDF URL loaded from Firestore
- [ ] Verify PDF files persist in app Documents folder

## Related Documentation
- DOCUMENT_STORAGE_IMPLEMENTATION.md - Details on centralized storage system
- PDF_CONVERSION_FIXES.md - Details on upside-down PDF fix
