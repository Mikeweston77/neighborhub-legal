# iOS to Android Implementation Sync Guide

## Overview
This guide documents all Create, Edit, and Delete functions in the iOS app that need to be replicated in the Android app at `/Users/mike/Desktop/Waterfall/NeighborHub_Android`.

---

## 🔧 Core CRUD Operations by Feature

### 1. Community Messages (Chat)

#### iOS Implementation
**File**: `NeighborHub/Managers/FirebaseManager.swift` & `NeighborHub/Views/CommunityChatCard.swift`

**CREATE**: Send message
```swift
func sendCommunityMessage(text: String, imageURL: String?, fileURL: String?, 
                         audioURL: String?, replyTo: String?, completion: @escaping (Result<Void, Error>) -> Void)
// Collection: communityMessages
// Fields: text, senderId, user, timestamp, imageURL, fileURL, audioURL, replyingTo
```

**EDIT**: Edit existing message  
```swift
func editMessage() // Line 3267 CommunityChatCard.swift
// Updates: text field only
// Adds: editedAt timestamp, isEdited flag
```

**DELETE**: Delete message
```swift
func deleteMessage() // Line 3523 CommunityChatCard.swift
// Soft delete: Updates status to "deleted"
// Preserves: message ID and timestamp
// Deletes: attachments from Storage
```

#### Android TODO
- [ ] Implement sendCommunityMessage in FirebaseManager.kt
- [ ] Implement editMessage function
- [ ] Implement deleteMessage with soft-delete pattern
- [ ] Handle Storage cleanup for attachments

---

### 2. Events

#### iOS Implementation
**File**: `NeighborHub/Views/EventsView.swift` & `NeighborHub/Views/ReportItTab.swift`

**CREATE**: Add event (via Firebase or local)
```swift
// Firebase: Uses FirebaseManager.shared.createEvent()
// Local: Saves to @AppStorage("eventsData")
// Collection: events
// Fields: title, description, date, eventType, creatorName, creatorSurname, 
//         imageURL, fileURL, contactName, contactCell
```

**EDIT**: Update event
```swift
// Updates event in events array
// Re-saves to Firebase & local storage
```

**DELETE**: Remove event
```swift
func deleteEventAndAttachments(_ event: LocalEvent) // Line 431-459 EventsView.swift
// Deletes: Event document from Firestore
// Deletes: Associated images/files from Storage
// Deletes: Local attachment files
// Auto-cleanup: Expired events after 2 hours (client-side)
```

**AUTO-CLEANUP**: Server-side scheduled deletion
```javascript
// File: functions/index.js
exports.cleanupExpiredEvents // Runs every 1 hour
// Deletes events 2 hours after expiry
// Preserves: "report" type events indefinitely
```

#### Android TODO
- [ ] Implement createEvent in Firestore
- [ ] Implement updateEvent function
- [ ] Implement deleteEventAndAttachments with Storage cleanup
- [ ] Add client-side expired event filtering (2 hour grace period)
- [ ] Sync with Cloud Functions for server-side cleanup

---

### 3. Incidents (Watch/Safety Reports)

#### iOS Implementation
**File**: `NeighborHub/Views/WatchView.swift`

**CREATE**: Report incident
```swift
// Collection: incidents
// Fields: title, description, severity, location, reporterId, timestamp, 
//         imageURL, status, category
```

**EDIT**: Update incident  
```swift
func updateIncident() // Line 698 WatchView.swift
// Updates: title, description, severity, status
```

**DELETE**: Remove incident
```swift
func deleteIncident(at index: Int) // Line 561 WatchView.swift
// Deletes: Document from Firestore collection "incidents"
// Deletes: Associated images from Storage
```

**ARCHIVE**: Move to archived
```swift
func deleteArchivedIncident(at index: Int) // Line 617 WatchView.swift
```

#### Android TODO
- [ ] Implement createIncident in Firestore
- [ ] Implement updateIncident function  
- [ ] Implement deleteIncident with image cleanup
- [ ] Add archive/unarchive functionality

---

### 4. Marketplace Listings

#### iOS Implementation
**File**: `NeighborHub/Views/MarketplaceTab.swift`

**CREATE**: Add listing
```swift
// Collection: marketplace
// Fields: title, description, price, category, condition, sellerId, 
//         sellerName, timestamp, imageURLs[], location
```

**EDIT**: Update listing
```swift
// Updates existing document fields
// Can update: title, description, price, condition, images
```

**DELETE**: Remove listing
```swift
func deleteItem(_ item: MarketplaceItem) // Line 1099 MarketplaceTab.swift
// Deletes: Document from "marketplace" collection
// Deletes: All images from Storage (imageURLs array)
```

#### Android TODO
- [ ] Implement createMarketplaceListing
- [ ] Implement updateMarketplaceListing
- [ ] Implement deleteMarketplaceListing with multi-image cleanup

---

### 5. Polls

#### iOS Implementation
**File**: `NeighborHub/Views/HomeView.swift`

**CREATE**: Create poll
```swift
func createPoll(question: String, options: [String]) // Line 1967 HomeView.swift
// Collection: polls/active (singleton document)
// Structure: polls array with {id, question, options[], votes[], creatorUid, timestamp}
```

**DELETE**: Remove active poll
```swift
func deleteActivePoll() // Line 1192 HomeView.swift
// Removes from polls array in polls/active document
// Moves to archived polls (optional)
```

**DELETE**: Remove archived poll
```swift
func deleteArchivedPoll(at offsets: IndexSet) // Line 1227 HomeView.swift
```

#### Android TODO
- [ ] Implement createPoll (array-based structure)
- [ ] Implement deleteActivePoll
- [ ] Implement poll archival system

---

### 6. Newsletters & Form Submissions

#### iOS Implementation
**File**: `NeighborHub/Views/NewsletterFormViews.swift`

**CREATE**: Submit newsletter form
```swift
// Collection: newsletters/{newsletterId}/submissions
// Fields: responses{}, submittedBy, submittedAt, status
```

**UPDATE**: Change submission status
```swift
func updateSubmissionStatus(_ id: UUID, status: NewsletterFormSubmission.SubmissionStatus) 
// Line 710 NewsletterFormViews.swift
```

**DELETE**: Remove submission
```swift
func deleteSubmission(_ id: UUID) // Line 726 NewsletterFormViews.swift
```

#### Android TODO
- [ ] Implement newsletter form submission
- [ ] Implement status update function
- [ ] Implement submission deletion

---

### 7. Emergency/User Contacts

#### iOS Implementation
**File**: `NeighborHub/Views/HomeView.swift`

**CREATE**: Add contact
```swift
func addUserContact(name, phone, email, organization, category, priority, availability, notes) 
// Line 5346 HomeView.swift
// Storage: UserDefaults "userEmergencyContacts"
```

**UPDATE**: Edit contact
```swift
func updateUserContact(_ updatedContact) // Line 5398 HomeView.swift
```

**DELETE**: Remove contact
```swift
func deleteUserContact(at index: Int) // Line 5377 HomeView.swift
```

#### Android TODO
- [ ] Implement addUserContact (SharedPreferences or local DB)
- [ ] Implement updateUserContact
- [ ] Implement deleteUserContact

---

### 8. Category Contacts (Report It Departments)

#### iOS Implementation
**File**: `NeighborHub/Managers/FirebaseManager.swift` (Lines 5289-5382)

**CREATE/UPDATE**: Update department contact
```swift
func updateCategoryContact(_ contact: CategoryContact, completion: @escaping (Result<Void, Error>) -> Void)
// Collection: categoryContacts
// Document ID: category name (e.g., "Electricity", "Water", "Lighting")
// Fields: name (department), number (phone), updatedAt, updatedBy
```

**READ**: Watch contacts
```swift
func watchCategoryContacts(callback: @escaping ([CategoryContact]) -> Void)
// Real-time listener on categoryContacts collection
```

#### Android TODO
- [ ] Implement updateCategoryContact in FirebaseManager.kt
- [ ] Implement watchCategoryContacts with LiveData/Flow
- [ ] Add admin permission checks

---

## 🔄 Common Patterns to Replicate

### Firebase Storage Cleanup Pattern
```swift
// iOS Pattern (replicate in Android)
1. Get download URL from document field
2. Convert URL to StorageReference using storageReference(fromDownloadURLString:)
3. Call ref.delete()
4. Handle errors gracefully (file might already be deleted)
```

### Local + Remote Sync Pattern
```swift
// iOS Pattern
1. Save to local storage (UserDefaults/AppStorage) immediately
2. Upload to Firestore asynchronously
3. Update local with Firestore response (for IDs, timestamps)
4. Use Firestore listeners to keep local data fresh
```

### Soft Delete vs Hard Delete
```swift
// Soft delete (Messages): Update status field to "deleted"
// Hard delete (Events, Marketplace): Delete document + storage files
```

---

## 📱 WhatsApp Pre-fill Implementation

### iOS Implementation
**Files**: `ReportItTab.swift`, `HomeView.swift`

**Pattern**:
```swift
let message = "Hi, I would like to report a *Category* issue.%0A%0A" +
              "*Reporter Details:*%0A" +
              "Name: \(userName) \(userSurname)%0A" +
              "Address: \(userAddress)%0A" +
              "Contact: \(userCell)%0A"
              
let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(message)")
UIApplication.shared.open(url)
```

### Android TODO
```kotlin
// Replicate in Android
val intent = Intent(Intent.ACTION_VIEW)
intent.data = Uri.parse("https://wa.me/$phoneNumber?text=$message")
startActivity(intent)
```

**Locations in iOS**:
1. Category Contact Cards (ReportItTab.swift:1925-1948)
2. Event Contact Details (ReportItTab.swift:1154-1183)
3. Emergency Contacts (HomeView.swift:5158-5180)
4. Business Directory (HomeView.swift:4087-4105)

---

## 🧪 Testing Checklist

After implementing in Android, test:

- [ ] Create operations save to Firestore correctly
- [ ] Edit operations update existing documents
- [ ] Delete operations remove Firestore docs AND Storage files
- [ ] WhatsApp pre-fill opens with correct message
- [ ] Local + remote data stays in sync
- [ ] Real-time listeners update UI
- [ ] Expired events are filtered (2 hour grace period)
- [ ] Category contacts update in real-time

---

## 🚀 Deployment Steps

1. **iOS Changes**: Already deployed
2. **Cloud Functions**: Deploy once, affects both platforms
   ```bash
   cd functions
   firebase deploy --only functions:cleanupExpiredEvents
   ```
3. **Android Changes**: Implement above TODOs
4. **Test**: Both platforms against same Firebase project

---

## 📝 Code Location Reference

### iOS Project Structure
```
NeighborHub/
├── Managers/
│   └── FirebaseManager.swift (Core CRUD operations)
├── Views/
│   ├── CommunityChatCard.swift (Message edit/delete)
│   ├── EventsView.swift (Event CRUD)
│   ├── ReportItTab.swift (Report/Event CRUD, WhatsApp)
│   ├── WatchView.swift (Incident CRUD)
│   ├── MarketplaceTab.swift (Marketplace CRUD)
│   └── HomeView.swift (Polls, Contacts, WhatsApp)
└── Models/
    └── HomeUIModels.swift (Data models)
```

### Android Project Structure (Expected)
```
NeighborHub_Android/app/src/main/java/com/neighborhub/app/
├── managers/
│   └── FirebaseManager.kt (TO IMPLEMENT)
├── ui/
│   ├── chat/ (Message operations)
│   ├── events/ (Event operations)
│   ├── incidents/ (Incident operations)
│   ├── marketplace/ (Marketplace operations)
│   └── home/ (Polls, contacts)
└── models/ (Data classes)
```

---

## 💡 Quick Implementation Priority

**High Priority** (Core features):
1. Message create/edit/delete
2. Event create/delete
3. Incident create/delete
4. Marketplace create/delete
5. WhatsApp pre-fill (all locations)

**Medium Priority**:
6. Poll create/delete
7. Category contacts update
8. Emergency contacts CRUD

**Low Priority**:
9. Newsletter submissions
10. Advanced filtering/sorting

---

## 🔗 Shared Backend (Already Configured)

These Cloud Functions work for both iOS and Android:
- ✅ `cleanupExpiredEvents` - Auto-deletes old events
- ✅ `onNewCommunityMessage` - Push notifications
- ✅ `onNewEvent` - Push notifications
- ✅ `onNewIncident` - Push notifications
- ✅ `onNewMarketplaceListing` - Push notifications
- ✅ `processAdvertUpload` - Image processing
- ✅ `onChatAttachmentFinalize` - Attachment processing

No changes needed - Android will use these automatically!

---

**Last Updated**: February 7, 2026
**iOS Version**: 1.07
**Android Version**: TO SYNC
