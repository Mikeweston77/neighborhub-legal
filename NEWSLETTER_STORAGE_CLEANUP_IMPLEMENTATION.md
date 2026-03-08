# Newsletter Storage Cleanup Implementation

## Overview
Enhanced the `deleteNewsletter` function in `FirebaseManager.swift` to properly clean up associated Firebase Storage files when deleting community newsletters.

## Changes Made

### Enhanced `deleteNewsletter` Function
**File**: `NeighborHub/Managers/FirebaseManager.swift`

**Previous Implementation**:
- Only deleted the Firestore document
- Left associated storage files orphaned

**New Implementation**:
- Reads the newsletter document first to identify storage files
- Uses `DispatchGroup` to coordinate multiple storage deletions
- Deletes all associated storage files before removing the Firestore document

## Storage Files Cleaned Up

### 1. **File Attachments** (`fileURL` field)
- Documents, PDFs, and other files attached to newsletters
- Retrieved from the newsletter's `fileURL` field in Firestore
- Uses the existing `storageReference(fromDownloadURLString:)` helper method

### 2. **Newsletter Images** 
- Images uploaded to `newsletters/images/{id}.jpg`
- Direct image uploads from the newsletter creation/editing interface
- Stored at a predictable path based on newsletter UUID

### 3. **Processed Images** (Future-Proofing)
- Potential processed images in `final/{id}/` directory
- Potential thumbnails in `thumbs/{id}/` directory
- Covers cases where Cloud Functions might process newsletter images in the future

## Implementation Details

### Error Handling
- Individual storage deletion failures don't prevent document deletion
- Logs informative messages for both successful and failed deletions
- Expected failures (like missing images) are logged appropriately

### Asynchronous Coordination
- Uses `DispatchGroup` to wait for all storage deletions to complete
- Only deletes the Firestore document after storage cleanup is attempted
- Ensures atomic cleanup operation

### Conditional Compilation
- Wrapped in `#if canImport(FirebaseStorage)` guards
- Gracefully handles environments without Firebase Storage

## Code Pattern
Follows the same pattern as other delete functions in the codebase:
- `deleteIncident`
- `deleteArchivedIncident` 
- `deleteActiveAlert`

## Benefits
1. **No Storage Orphans**: Prevents accumulation of unused storage files
2. **Cost Optimization**: Reduces Firebase Storage costs
3. **Data Integrity**: Maintains consistency between Firestore and Storage
4. **Future-Proof**: Handles potential processed image variations
5. **Robust Error Handling**: Continues deletion even if some storage operations fail

## Testing Recommendations
1. Test deleting newsletters with file attachments
2. Test deleting newsletters with images
3. Test deleting newsletters with no attachments
4. Verify proper cleanup in Firebase Console
5. Test error scenarios (network issues, permission problems)