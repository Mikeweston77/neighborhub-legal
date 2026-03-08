# Camera Access Request System - Redesign Complete ✅

## Overview
The camera access system has been redesigned to use a request-based approval workflow. Users now submit watch credentials through Home settings, which triggers an admin approval process before granting camera access.

---

## 🔄 New Flow

### **User Perspective**

1. **Enter Credentials** (Home Settings)
   - User opens Home → Settings (gear icon)
   - Scrolls to "NeighbourHUB Watch" section
   - Enters watch username and password
   - System automatically submits camera access request

2. **Request Submitted**
   - Green confirmation appears: "Camera access requested"
   - Status message: "Waiting for admin approval"
   - Request is sent to Firestore with watch username

3. **Wait for Approval**
   - User cannot access Watch tab until approved
   - Shows "Access Restricted" message with instructions

4. **Access Granted**
   - Admin approves request → User gains immediate access
   - Watch tab becomes available
   - Camera portal loads with injected credentials

---

### **Admin Perspective**

1. **View Pending Requests** (Watch Admin Settings)
   - Orange badge appears on "Pending Camera Requests" section
   - Shows count of waiting users
   - Each request displays:
     - User profile picture/initials
     - Full name
     - Watch username (credentials they submitted)
     - Address

2. **Review & Approve**
   - **Approve Button** (Green):
     - Grants `cameraAccess: true` in Firestore
     - Clears `cameraAccessRequested` flag
     - User gains immediate access
   - **Reject Button** (Red):
     - Clears request without granting access
     - User can resubmit after fixing credentials

3. **Migration Removed**
   - Legacy string-based camera user migration section removed
   - All camera access now goes through request system

---

## 📁 File Changes

### **1. FirebaseManager.swift** (+35 lines)

#### New Function: `requestCameraAccess()`
```swift
func requestCameraAccess(
    uid: String,
    watchUsername: String,
    completion: @escaping (Result<Void, Error>) -> Void
)
```

**Purpose**: Submit camera access request to Firestore  
**Firestore Updates**:
- `cameraAccessRequested: true`
- `cameraAccessRequestedAt: Timestamp`
- `watchCredential: String` (watch username)

#### Updated Function: `updateCameraAccess()`
**New Behavior**: When granting access, automatically clears `cameraAccessRequested` flag

---

### **2. ContentView.swift** (+150 lines)

#### Updated `RegisteredUser` Model
Added fields:
```swift
let cameraAccessRequested: Bool
let watchCredential: String?
```

#### New Computed Property: `pendingCameraAccessRequests`
Filters verified users with pending camera requests:
```swift
var pendingCameraAccessRequests: [RegisteredUser] {
    firestoreRegisteredUsers.filter { 
        $0.isVerified && 
        $0.cameraAccessRequested && 
        !$0.hasCameraAccess 
    }
}
```

#### New UI Section: Pending Camera Requests
- Appears in Watch Admin Settings
- Shows orange badge with count
- Displays `CameraRequestRowView` for each pending user
- Approve/Reject buttons inline

#### New Function: `rejectCameraRequest()`
```swift
func rejectCameraRequest(for user: RegisteredUser) {
    // Clears cameraAccessRequested flag
    // Logs rejection timestamp
}
```

#### New Component: `CameraRequestRowView`
Displays:
- User profile picture or colored initials (orange)
- Full name
- Watch username (from request)
- Address
- Approve (green) / Reject (red) action buttons

---

### **3. HomeView.swift** (+65 lines)

#### HomeSettingsView Updates

**New State Variables**:
```swift
@State private var cameraAccessRequestSubmitted = false
@State private var showCameraRequestAlert = false
@State private var cameraRequestMessage = ""
@State private var previousWatchUsername = ""
```

**Enhanced Watch Credentials Section**:
- `.onChange` modifiers on both username and password fields
- Auto-submits request when both fields are filled
- Shows green confirmation box when request submitted
- Footer text: "Enter your watch credentials to request camera access. An admin will approve your request."

**New Function**: `submitCameraAccessRequest()`
- Validates user is authenticated
- Checks watch username is not empty
- Calls `FirebaseManager.shared.requestCameraAccess()`
- Shows success/failure alert

---

## 🔥 Firestore Schema Changes

### `users/{uid}` Document Fields

#### New Fields:
```javascript
{
  "cameraAccessRequested": Boolean,      // User has submitted request
  "cameraAccessRequestedAt": Timestamp,  // When request was submitted
  "watchCredential": String,             // Watch username (for admin review)
  "cameraAccessRejectedAt": Timestamp    // If admin rejected request
}
```

#### Updated Fields:
```javascript
{
  "cameraAccess": Boolean,               // Admin-granted permission
  "cameraAccessUpdatedAt": Timestamp,    // Last access change
  "cameraAccessGrantedBy": String        // Admin UID who granted access
}
```

---

## 🎯 User Experience Improvements

### ✅ **For Regular Users**:
1. **Simpler Process**: Just enter credentials in settings → automatic request
2. **Clear Status**: Visual confirmation that request was submitted
3. **No Confusion**: Can't access Watch tab until approved
4. **Transparent**: Knows request is pending admin review

### ✅ **For Admins**:
1. **Centralized Queue**: All requests in one place (no manual migration)
2. **Full Context**: See watch username user submitted (verify it's correct)
3. **Quick Actions**: Approve or reject with one tap
4. **Clean UI**: Orange badge shows pending count at a glance
5. **No Legacy Issues**: Migration section removed, no string-based lists

---

## 🔒 Security Enhancements

### **UID-Based System**
- All operations use Firebase Auth UID (not names)
- Watch credentials stored securely in Firestore
- Admin approval required before any access granted

### **Audit Trail**
- `cameraAccessRequestedAt`: When user submitted request
- `cameraAccessGrantedBy`: Which admin approved
- `cameraAccessUpdatedAt`: Last change timestamp
- `cameraAccessRejectedAt`: If request was denied

### **Two-Layer Security** (Preserved)
1. **Permission Layer** (Firestore): Admin controls WHO can access
2. **Authentication Layer** (Local): User's actual camera login credentials

---

## 🚀 Migration Path

### **Phase 1: Dual System** (Current)
- New request system active
- Legacy migration section removed
- Users with existing `cameraAccess: true` keep access
- New users must use request system

### **Phase 2: Cleanup** (Next Steps)
1. Remove `@AppStorage("cameraUsers")` string-based list
2. Remove `isCameraUserByName_Legacy` function
3. Update Firestore Rules to require `cameraAccess` field

---

## 📊 Admin Dashboard View

```
Watch Admin Settings
├── Committee Members (5)
├── Camera Users (Legacy - deprecated)
├── 🆕 Pending Camera Requests (3) ⚠️
│   ├── Mike Wilson
│   │   └── Watch Username: MikeW
│   │   └── [Approve] [Reject]
│   ├── Jane Smith
│   │   └── Watch Username: JaneS
│   │   └── [Approve] [Reject]
│   └── ...
├── Pending Users (2)
└── Approved Users (12)
```

---

## 🧪 Testing Checklist

### **User Flow**:
- [ ] User enters watch username in Home settings
- [ ] User enters watch password
- [ ] Green confirmation appears automatically
- [ ] Status shows "Waiting for admin approval"
- [ ] Watch tab shows "Access Restricted" message
- [ ] Request appears in Firestore with correct fields

### **Admin Flow**:
- [ ] Admin sees orange badge on "Pending Camera Requests"
- [ ] Badge shows correct count (matches Firestore)
- [ ] Each request shows user name, watch username, address
- [ ] Approve button grants access → request disappears
- [ ] Reject button clears request → user can resubmit
- [ ] User gains immediate access after approval

### **Edge Cases**:
- [ ] User modifies watch username → new request submitted
- [ ] User clears credentials → request remains (admin can still approve)
- [ ] Admin approves → user can access Watch tab immediately
- [ ] Multiple admins see same pending requests (real-time sync)
- [ ] Offline: Request queued and submitted when online

---

## 🔄 vs. Legacy System

| Feature | Legacy (Deprecated) | New Request System |
|---------|--------------------|--------------------|
| **Activation** | Admin manually adds name to string list | User enters credentials → auto-request |
| **Admin Action** | Type username into text field | Tap Approve/Reject button |
| **User Knowledge** | No idea they need to request | Clear instructions and status |
| **Security** | Name-based (insecure) | UID-based (secure) |
| **Migration** | Manual string matching | None needed |
| **Audit Trail** | None | Full timestamps and admin tracking |
| **Real-time Sync** | No (AppStorage local) | Yes (Firestore listeners) |
| **Watch Credentials** | Stored locally only | Submitted with request for admin review |

---

## 📝 Developer Notes

### **Why This Redesign?**

**Problems with Legacy System**:
1. Admins had to manually type usernames → typos, inconsistencies
2. No visibility for users → they didn't know to request access
3. Migration required complex name-matching logic
4. String-based lists not scalable or secure

**Benefits of New System**:
1. Self-service request → users initiate the flow
2. Admin sees exactly what username user wants to use
3. No migration needed → direct Firestore integration
4. Scalable, secure, auditable

### **Code Patterns to Follow**

When adding similar features:
```swift
// 1. User submits request
FirebaseManager.shared.requestFeatureAccess(uid: uid, data: data) { result in
    // Show confirmation UI
}

// 2. Admin sees pending requests
var pendingRequests: [User] {
    users.filter { $0.featureRequested && !$0.hasFeature }
}

// 3. Admin approves/rejects
func approveRequest(for user: User) {
    FirebaseManager.shared.updateFeatureAccess(uid: user.id, granted: true) { ... }
}
```

---

## 🎨 UI/UX Guidelines

### **Color Coding**:
- 🟢 **Green**: Approved users, success states
- 🟠 **Orange**: Pending requests, warnings
- 🔵 **Blue**: Committee members
- 🔴 **Red**: Admins, rejection actions

### **Badge Counts**:
Always show count when section has items:
```swift
Label("Pending Camera Requests", systemImage: "video.badge.checkmark")
    .badge(pendingCameraAccessRequests.count)
```

### **Confirmation Messages**:
Keep success messages visible but not intrusive:
```swift
HStack {
    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
    Text("Camera access requested")
}
.padding(8)
.background(Color.green.opacity(0.1))
.cornerRadius(8)
```

---

## 🔗 Related Documentation

- `CAMERA_ACCESS_MODERNIZATION.md` - Original two-layer security model
- `FRONTEND_AUTH_IMPLEMENTATION_COMPLETE.md` - UID-based authentication
- `FIREBASE_RULES_DEPLOYMENT.md` - Firestore security rules

---

## ✅ Implementation Status

**Completed**:
- ✅ FirebaseManager request function
- ✅ RegisteredUser model updated
- ✅ HomeView auto-submit on credential entry
- ✅ ContentView pending requests section
- ✅ CameraRequestRowView component
- ✅ Approve/Reject functionality
- ✅ Real-time Firestore sync

**Next Steps**:
1. Update Firestore Rules to validate camera access fields
2. Add push notifications for request status changes
3. Remove legacy migration UI completely
4. Add analytics tracking for request → approval time

---

## 🐛 Known Issues / TODO

- [ ] Add rate limiting (prevent spam requests)
- [ ] Handle case where user changes watch username after request
- [ ] Admin notification when new request arrives
- [ ] User notification when request is approved/rejected
- [ ] Expiry for old pending requests (e.g., auto-reject after 30 days)

---

**Last Updated**: November 4, 2025  
**Status**: ✅ Complete and Ready for Testing
