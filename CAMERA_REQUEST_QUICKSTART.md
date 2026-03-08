# Camera Access Request System - Quick Reference

## 🎯 What Changed?

**OLD SYSTEM** (Deprecated):
- Admins manually typed usernames into a text field
- Users had no visibility into the process
- Required complex migration logic
- String-based, insecure

**NEW SYSTEM** (Active):
- Users enter credentials in Home settings → automatic request submitted
- Admins see pending requests with user details
- Approve/Reject with one tap
- UID-based, secure, auditable

---

## 👥 User Flow (3 Steps)

1. **Home → Settings → NeighbourHUB Watch**
   - Enter watch username
   - Enter watch password
   - ✅ Request automatically submitted

2. **Wait for Approval**
   - Green confirmation: "Camera access requested"
   - Status: "Waiting for admin approval"

3. **Access Granted**
   - Admin approves → Watch tab unlocks
   - Camera portal loads automatically

---

## 🔧 Admin Flow (2 Steps)

1. **Watch Tab → Settings → Pending Camera Requests**
   - Orange badge shows count
   - Each request displays:
     - User name
     - Watch username
     - Address

2. **Review & Decide**
   - **Approve** (green) → User gains immediate access
   - **Reject** (red) → Request cleared, user can resubmit

---

## 📦 Files Modified

| File | Changes |
|------|---------|
| `FirebaseManager.swift` | +35 lines - Added `requestCameraAccess()` function |
| `ContentView.swift` | +150 lines - Added pending requests section & UI |
| `HomeView.swift` | +65 lines - Auto-submit on credential entry |

---

## 🔥 Firestore Fields Added

```javascript
users/{uid} {
  cameraAccessRequested: boolean     // User submitted request
  cameraAccessRequestedAt: timestamp // When submitted
  watchCredential: string            // Watch username
  cameraAccessRejectedAt: timestamp  // If rejected
}
```

---

## ✅ Testing Steps

### User Test:
1. Open Home → Settings
2. Enter watch username: `TestUser`
3. Enter watch password: `password123`
4. Verify green confirmation appears
5. Open Watch tab → Should show "Access Restricted"

### Admin Test:
1. Open Watch tab → Settings (if you're admin/committee)
2. Expand "Pending Camera Requests"
3. See the test user listed
4. Tap "Approve"
5. User should now access Watch tab

---

## 🚨 Important Notes

- ⚠️ Legacy migration section removed - all new users use request system
- ✅ Existing users with camera access keep their access
- 🔒 All operations use Firebase Auth UID (secure)
- 📱 Real-time sync via Firestore listeners

---

## 🐛 Troubleshooting

**User can't submit request**:
- Check they're logged in (Firebase Auth)
- Verify watch username is not empty
- Check console logs for errors

**Admin doesn't see requests**:
- Verify user is admin or committee member
- Check Firestore listener is active
- Refresh the admin settings sheet

**Approval doesn't grant access**:
- Check Firestore Rules allow writes
- Verify user's UID matches document ID
- Check console for error messages

---

**Full Documentation**: See `CAMERA_ACCESS_REQUEST_REDESIGN.md`  
**Implementation Date**: November 4, 2025
