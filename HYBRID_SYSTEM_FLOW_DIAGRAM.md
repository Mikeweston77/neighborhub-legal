# Hybrid PDF System - Flow Diagram

## Complete Data Flow: User → Storage → Display

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER SELECTS PDF                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              LocalListingDocumentPicker                              │
│  (Shared by both Newsletters & Local Listings)                       │
├─────────────────────────────────────────────────────────────────────┤
│  1. User picks PDF file                                              │
│  2. didPickDocumentsAt(urls) called                                  │
│  3. Calls DocumentStorageManager.storeDocument()                     │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    DocumentStorageManager                            │
│           ~/Documents/AppDocuments/[Newsletters|LocalListings]/      │
├─────────────────────────────────────────────────────────────────────┤
│  1. Check file size (max 100MB)                                      │
│  2. Generate unique filename or preserve original                    │
│  3. Handle security scoped resource access                           │
│  4. Copy file to permanent location                                  │
│  5. Return permanent URL: copiedURL                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PDFToImageConverter                               │
│                 (Local File Conversion)                              │
├─────────────────────────────────────────────────────────────────────┤
│  1. convertLocalPDFToPageImages(copiedURL)                           │
│  2. Extract page images (iOS coordinate transform applied)           │
│  3. extractLocalPDFMetadata(copiedURL)                               │
│  4. Return: [UIImage], PDFMetadata                                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     onPDFSelected Callback                           │
│              (Different handling per feature)                        │
└───────────┬─────────────────────────────────────┬───────────────────┘
            │                                     │
            │ NEWSLETTERS                         │ LOCAL LISTINGS
            │                                     │
            ▼                                     ▼
┌───────────────────────────┐     ┌─────────────────────────────────┐
│  Newsletter Handler        │     │  Local Listing Handler          │
├───────────────────────────┤     ├─────────────────────────────────┤
│  selectedImageFromDoc =    │     │  selectedImages =               │
│    pageImages.first        │     │    pageImages                   │
│  originalPDFURL =          │     │  originalFileURL =              │
│    copiedURL               │     │    copiedURL                    │
└───────────┬───────────────┘     └─────────────┬───────────────────┘
            │                                   │
            │ createNewsletter()                │ createListing()
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐     ┌─────────────────────────────────┐
│  Newsletter Object         │     │  LocalListing Object            │
├───────────────────────────┤     ├─────────────────────────────────┤
│  imageData: Data?          │     │  imagesData: [Data]?            │
│    (compressed preview)    │     │    (compressed previews)        │
│  fileURL: URL?             │     │  fileURL: URL?                  │
│    (original PDF path)     │     │    (original PDF path)          │
└───────────┬───────────────┘     └─────────────┬───────────────────┘
            │                                   │
            │ FirebaseManager.                  │ LocalListingManager.
            │ createOrUpdateNewsletter()        │ addListing()
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐     ┌─────────────────────────────────┐
│  Firestore                 │     │  Local Storage                  │
│  Collection: newsletters   │     │  (UserDefaults/AppStorage)      │
├───────────────────────────┤     ├─────────────────────────────────┤
│  {                         │     │  listing.imagesData saved       │
│    "imageData": "base64",  │     │  listing.fileURL saved          │
│    "fileURL": "file://...", │     │  (if Firestore enabled,        │
│    "title": "...",         │     │   also synced to Firestore)     │
│    ...                     │     │                                 │
│  }                         │     │                                 │
└───────────┬───────────────┘     └─────────────┬───────────────────┘
            │                                   │
            │ watchNewsletters()                │ loadListings()
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐     ┌─────────────────────────────────┐
│  newsletterFrom(data:)     │     │  LocalListing (Codable)         │
├───────────────────────────┤     ├─────────────────────────────────┤
│  1. Load fileURL string    │     │  1. Decode from JSON            │
│  2. Convert to URL         │     │  2. fileURL decoded from string │
│  3. Decode imageData       │     │  3. imagesData decoded          │
└───────────┬───────────────┘     └─────────────┬───────────────────┘
            │                                   │
            │                                   │
            ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         DISPLAY IN UI                                │
└─────────────────────────────────────────────────────────────────────┘
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐     ┌─────────────────────────────────┐
│  NewsletterCard            │     │  LocalListingCard               │
├───────────────────────────┤     ├─────────────────────────────────┤
│  Shows imageData preview   │     │  Shows imagesData previews      │
│                            │     │                                 │
│  if fileURL exists &&      │     │  if fileURL exists &&           │
│     .pdf extension:        │     │     .pdf extension:             │
│                            │     │                                 │
│    [View Full PDF] button  │     │    [View Full PDF] button       │
└───────────┬───────────────┘     └─────────────┬───────────────────┘
            │                                   │
            │ User taps button                  │ User taps button
            │                                   │
            ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      QuickLookPreview(url: fileURL)                  │
├─────────────────────────────────────────────────────────────────────┤
│  Displays full PDF document from local file system                   │
│  File still at: ~/Documents/AppDocuments/[subdirectory]/filename.pdf │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Shared Document Picker
Both newsletters and local listings use `LocalListingDocumentPicker` - this ensures:
- ✅ Consistent file handling
- ✅ Single source of truth for PDF conversion
- ✅ Reduced code duplication
- ✅ Easier maintenance

### 2. Dual Storage Strategy

**Preview Data (Firestore):**
- Compressed image(s) stored as base64
- Fast loading for card views
- Small payload (~50-200KB per preview)
- Synced across devices (if Firestore enabled)

**Original PDF (Local Storage):**
- Full document in app Documents directory
- No Firebase Storage costs
- Accessible via file:// URL
- Persists across app launches

### 3. Why Both?

**Card/List View:**
- Shows compressed preview images
- Fast load time
- Minimal data transfer

**Full View:**
- Shows complete original PDF
- All pages accessible
- Full quality maintained
- No additional download needed

### 4. File Lifecycle

**Creation:**
```
Temp URL → DocumentStorageManager → Permanent URL → Both Preview + Original saved
```

**Edit:**
```
Load existing fileURL → Preserve during edit → Save updated listing/newsletter
```

**Delete:**
```
Delete listing/newsletter → File remains in Documents (manual cleanup available)
```

**App Reinstall:**
```
Firestore data restored → fileURL points to local file → File may not exist
(User would need to re-attach PDF)
```

## Storage Locations

### Newsletters
```
~/Library/Developer/CoreSimulator/Devices/[UDID]/data/Containers/Data/Application/[APP_ID]/Documents/AppDocuments/Newsletters/[uuid]-filename.pdf
```

### Local Listings
```
~/Library/Developer/CoreSimulator/Devices/[UDID]/data/Containers/Data/Application/[APP_ID]/Documents/AppDocuments/LocalListings/[uuid]-filename.pdf
```

### Events
```
~/Library/Developer/CoreSimulator/Devices/[UDID]/data/Containers/Data/Application/[APP_ID]/Documents/AppDocuments/Events/[uuid]-filename.pdf
```

## Size Considerations

### Per Document
- **PDF Original:** 0.1MB - 100MB (enforced limit)
- **Preview Images:** ~50-200KB compressed (in Firestore)
- **Metadata:** ~1-2KB (title, author, etc.)

### Total App Storage
- **100 newsletters @ 10MB each:** ~1GB
- **100 listings @ 5MB each:** ~500MB
- **Preview data in Firestore:** ~20MB total

### Cleanup Strategy
DocumentStorageManager provides:
- `getTotalStorageSize()` - Check current usage
- `cleanupOldDocuments(olderThan:)` - Remove old files
- `deleteDocument(at:)` - Manual deletion

## Error Handling

### File Too Large
```
DocumentStorageManager: File too large (105.2 MB), max allowed is 100 MB
→ User sees error, attachment not saved
```

### PDF Conversion Failed
```
PDFToImageConverter: Failed to convert PDF
→ Callback with empty pageImages array
→ fileURL still saved for later viewing
```

### File Not Found (After App Reinstall)
```
QuickLook: Cannot open file:///nonexistent/path.pdf
→ User sees error
→ Solution: Re-attach PDF
```

### Firestore Sync Failed
```
FirebaseManager: Error saving newsletter
→ Local data preserved
→ Retry on next sync
```
