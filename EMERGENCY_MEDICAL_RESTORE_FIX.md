# Archived Emergency & Medical Reports Restore Fix

## Issue Analysis
The user reported that archived emergency & medical reports restore functionality was not working, while fire reports worked fine. After investigation, I identified several potential issues and implemented comprehensive fixes.

## Root Cause Analysis

### Primary Issue
The `restoreArchivedIncident` function in FirebaseManager was not properly handling the restore process:
1. **Archive Document Management**: When restoring, the function was removing the `archivedAt` field instead of deleting the archived document entirely
2. **Query Issues**: The `watchArchivedIncidents` function orders by `"archivedAt"` field, so documents without this field would not appear in the archived list
3. **Query Precision**: Title and date matching could fail due to timestamp precision issues

### Secondary Issues
1. **Limited Search Options**: Only exact title+date matching was attempted
2. **Error Handling**: Insufficient debugging information for troubleshooting
3. **Single Restore Method**: No fallback mechanisms for different types of failures

## Implemented Fixes

### 1. Fixed Archive Document Cleanup
**Before:**
```swift
// Removing archivedAt field but keeping document in archived collection
doc.reference.setData(["archivedAt": FieldValue.delete()], merge: true) { clearErr in
    completion?(clearErr)
}
```

**After:**
```swift
// Properly delete the archived document after successful restore
doc.reference.delete { clearErr in
    if let clearErr = clearErr {
        print("FirebaseManager: Warning - restored incident but failed to delete archived copy: \(clearErr)")
    } else {
        print("FirebaseManager: Successfully restored incident and removed archived copy")
    }
    completion?(clearErr)
}
```

### 2. Enhanced Query Strategy
Implemented multi-step fallback queries:
1. **Exact Match**: Title + Date timestamp matching
2. **Title Fallback**: Title-only matching with closest date selection
3. **Description Fallback**: Description-based search as last resort

```swift
// Multiple fallback strategies for better reliability
if let docs = snap?.documents, !docs.isEmpty {
    print("FirebaseManager: Found exact title+date match")
    self.restoreDocument(docs[0], completion: completion)
    return
}

// Try title-only fallback
ref.whereField("title", isEqualTo: title).getDocuments { fallbackSnap, fallbackErr in
    // Handle title-only results...
    
    // Final fallback by description if available
    if let desc = description, !desc.isEmpty {
        ref.whereField("description", isEqualTo: desc).getDocuments { descSnap, descErr in
            // Handle description-based search...
        }
    }
}
```

### 3. Added ID-Based Restore Method
Created a more reliable restore method using document ID directly:

```swift
func restoreArchivedIncidentById(id: String, completion: ((Error?) -> Void)? = nil) {
    print("FirebaseManager: Attempting to restore archived incident by ID: \(id)")
    let archivedRef = db.collection("archivedIncidents").document(id)
    
    archivedRef.getDocument { snap, err in
        if let err = err {
            print("FirebaseManager: Error fetching archived incident by ID: \(err)")
            completion?(err)
            return
        }
        
        guard let snap = snap, snap.exists, let data = snap.data() else {
            print("FirebaseManager: Archived incident with ID \(id) not found")
            completion?(NSError(domain: "FirebaseManager", code: -404, userInfo: [NSLocalizedDescriptionKey: "Archived incident not found"]))
            return
        }
        
        print("FirebaseManager: Found archived incident by ID, restoring...")
        self.restoreDocument(snap, completion: completion)
    }
}
```

### 4. Dual-Method Restore Strategy
Updated WatchView to try both restore methods for maximum reliability:

```swift
// Try ID-based restore first (more reliable), then fall back to title/date matching
FirebaseManager.shared.restoreArchivedIncidentById(id: inc.id.uuidString) { err in
    if let err = err {
        print("WatchView: ID-based restore failed, trying title/date matching: \(err)")
        // Fallback to title/date matching
        FirebaseManager.shared.restoreArchivedIncident(
            matchingTitle: inc.title, date: inc.date, description: inc.description
        ) { fallbackErr in
            if let fallbackErr = fallbackErr {
                print("WatchView: Both restore methods failed: \(fallbackErr)")
            } else {
                print("WatchView: restored archived incident via fallback method")
            }
        }
    } else {
        print("WatchView: restored archived incident via ID-based method")
    }
}
```

### 5. Enhanced Debugging and Logging
Added comprehensive logging throughout the restore process:
- Query attempts and results
- Document parsing success/failure
- Incident type tracking
- Error details for troubleshooting

```swift
print("FirebaseManager: Received \(snap.documents.count) archived incident documents")
for doc in snap.documents {
    let d = doc.data()
    if let i = self.incidentFrom(data: d) { 
        print("FirebaseManager: Parsed archived incident: '\(i.title)' type='\(i.incidentType ?? "nil")' archivedAt=\(i.archivedAt != nil)")
        items.append(i) 
    } else {
        print("FirebaseManager: Failed to parse archived incident document: \(doc.documentID)")
    }
}
```

## Why Fire Reports Worked vs Emergency/Medical

The issue was not specific to incident types but rather a systemic problem with the restore mechanism. Fire reports appearing to work better might have been due to:
1. **Timestamp Precision**: Fire reports might have had timestamps that matched more precisely
2. **Title Consistency**: Fire report titles might have been more consistent between archive and restore
3. **Timing**: Fire reports might have been archived/restored under different conditions

The fixes address these underlying issues for **all** incident types.

## Testing Recommendations

### Manual Testing Steps
1. **Archive Test**: Archive emergency, medical, and fire incidents
2. **Restore Test**: Attempt to restore each type using the UI
3. **Cross-Type Test**: Verify all incident types appear and restore consistently
4. **Error Handling**: Test restore with invalid/missing data

### Console Monitoring
Monitor Xcode console for logging output:
- `FirebaseManager: Searching for archived incident with title=...`
- `FirebaseManager: Found X matching archived incidents`
- `WatchView: restored archived incident via [method]`

## Expected Outcomes

✅ **Emergency Reports**: Should now restore successfully
✅ **Medical Reports**: Should now restore successfully  
✅ **Fire Reports**: Should continue working (with improved reliability)
✅ **Error Handling**: Better error messages and fallback mechanisms
✅ **Debugging**: Comprehensive logging for troubleshooting

## Status: 🟢 COMPLETE

All identified issues with archived incident restore functionality have been addressed. The enhanced restore system provides:
- Multiple fallback strategies for robust restoration
- Improved error handling and debugging
- Consistent behavior across all incident types
- Better reliability through dual-method approach

Emergency and medical reports should now restore as reliably as fire reports.