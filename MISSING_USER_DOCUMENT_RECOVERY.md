# Missing User Document - Recovery Guide

## Problem

**Error Message**: `"No user document found for UID: {uid}"`

**What This Means**:
- User successfully created Firebase Auth account ✅
- Firebase Firestore user profile document creation **failed** ❌
- User can't log in because app expects both Auth + Firestore document

**Common Causes**:
1. Network interruption during registration
2. Firestore security rules blocking creation
3. Firebase quota/limits reached
4. App crash during registration process
5. Firestore offline mode issues

---

## Immediate Solution

### Option 1: Automatic Recovery (App Does This Now) ✅

The app now automatically detects missing documents and creates a recovery document:

1. User attempts to log in
2. App detects missing Firestore document
3. App creates minimal user profile automatically
4. User should see "Pending Approval" screen
5. Admin can approve normally

**Look for console logs**:
```
❌ No user document found for UID: 94oSpfOIGxctBSNLFRLOVE4g3cR2
⚠️ This indicates incomplete registration - attempting recovery...
🔧 Creating recovery user document for UID: 94oSpfOIGxctBSNLFRLOVE4g3cR2
✅ Recovery document created successfully
```

### Option 2: Manual Recovery (Firebase Console)

If automatic recovery fails:

1. **Get the User's UID**:
   - From error message: `94oSpfOIGxctBSNLFRLOVE4g3cR2`
   - Or Firebase Console → Authentication → Users → Click user → Copy UID

2. **Create Firestore Document**:
   ```
   Firebase Console → Firestore Database → users collection
   
   Document ID: 94oSpfOIGxctBSNLFRLOVE4g3cR2
   
   Fields:
   - uid: "94oSpfOIGxctBSNLFRLOVE4g3cR2" (string)
   - email: "user@example.com" (string) - from Auth
   - firstName: "FirstName" (string)
   - lastName: "LastName" (string)
   - name: "FirstName LastName" (string)
   - verified: false (boolean)
   - createdAt: [timestamp] (timestamp)
   - updatedAt: [timestamp] (timestamp)
   - privacyShareWithCommunity: true (boolean)
   - privacyShareWithCommittee: true (boolean)
   ```

3. **Save** → User can now log in

---

## Prevention

### For Developers

1. **Add Retry Logic** (Future Enhancement):
   ```swift
   // Retry Firestore document creation on failure
   func createUserWithRetry(maxAttempts: Int = 3) {
       // Implementation
   }
   ```

2. **Check Firestore Rules**:
   ```javascript
   match /users/{userId} {
     allow create: if isSignedIn() && 
                      request.auth.uid == userId &&
                      request.resource.data.uid == userId &&
                      request.resource.data.email == request.auth.token.email;
   }
   ```
   Make sure rules allow users to create their own documents!

3. **Add Transaction**:
   ```swift
   // Create Auth account and Firestore document in a transaction
   // Roll back Auth if Firestore fails
   ```

### For Admins

1. **Monitor Firebase Logs**:
   - Firebase Console → Functions → Logs
   - Look for failed document creations

2. **Check Quotas**:
   - Firebase Console → Usage
   - Verify Firestore write limits not exceeded

3. **Audit Security Rules**:
   - Ensure rules allow user creation
   - Test with Firebase Rules Playground

---

## Testing the Recovery Feature

### Test Case 1: Simulate Missing Document

1. Register new user
2. Immediately delete their Firestore document (keep Auth account)
3. Try to log in
4. Expected: Recovery document auto-created

### Test Case 2: Network Interruption

1. Start registration
2. Turn off Wi-Fi after Auth account created
3. Registration fails
4. Turn Wi-Fi back on
5. Try to log in
6. Expected: Recovery kicks in

---

## Current Implementation

### ContentView.swift

**Detection** (Line ~1493):
```swift
guard let data = snapshot?.data() else {
    print("❌ No user document found for UID: \(uid)")
    print("⚠️ This indicates incomplete registration - attempting recovery...")
    
    // Attempt to recover
    self.recoverMissingUserDocument(uid: uid, db: db)
    
    DispatchQueue.main.async {
        self.isVerified = false
    }
    return
}
```

**Recovery Method** (Line ~1525):
```swift
private func recoverMissingUserDocument(uid: String, db: Firestore) {
    // Creates minimal user document from cached UserDefaults data
    // Sets recoveredDocument: true flag
    // Automatically re-checks verification after creation
}
```

---

## Recovery Document Fields

Automatically created documents include:

| Field | Value | Source |
|-------|-------|--------|
| `uid` | User's UID | Firebase Auth |
| `email` | User's email | Auth.currentUser.email |
| `firstName` | First name | UserDefaults cache |
| `lastName` | Last name | UserDefaults cache |
| `name` | Full name | Computed |
| `verified` | false | Default |
| `recoveredDocument` | true | Flag |
| `createdAt` | Current time | Server timestamp |
| `updatedAt` | Current time | Server timestamp |

**Missing Fields** (user must complete in profile):
- Phone number
- Address (street, suburb, city, postal)
- Emergency contacts
- Profile photo

---

## Manual Steps for Affected User (UID: 94oSpfOIGxctBSNLFRLOVE4g3cR2)

### Step 1: Verify Auth Account Exists

```
Firebase Console → Authentication → Users
Search for: 94oSpfOIGxctBSNLFRLOVE4g3cR2
Status: Should show email and creation date
```

### Step 2: Check Firestore

```
Firebase Console → Firestore Database → users
Document ID: 94oSpfOIGxctBSNLFRLOVE4g3cR2
Status: Missing or incomplete?
```

### Step 3A: If Document Exists

- Check if `verified: false` is set
- Admin should approve through admin panel
- User should be able to log in

### Step 3B: If Document Missing

**Option 1**: Let user try logging in (triggers auto-recovery)

**Option 2**: Create manually in Firebase Console:

1. Click "Start collection" or "Add document"
2. Document ID: `94oSpfOIGxctBSNLFRLOVE4g3cR2`
3. Add fields (see "Manual Recovery" section above)
4. Click "Save"

### Step 4: Test Login

1. User opens app
2. Taps "Sign In"
3. Enters email + password
4. Should see "Pending Approval" screen
5. Admin approves
6. User gets full access

---

## Long-Term Fix

### Recommended Changes

1. **Two-Phase Commit Pattern**:
   ```swift
   // Phase 1: Create Firestore document (can be rolled back)
   createFirestoreDocument() { success in
       if success {
           // Phase 2: Create Auth account
           createAuthAccount()
       }
   }
   ```

2. **Idempotent Registration**:
   ```swift
   // Allow re-running registration if incomplete
   // Check if Auth exists → create Firestore only
   // Check if Firestore exists → skip both
   ```

3. **Better Error Messages**:
   ```swift
   // Show user-friendly error in UI
   "Registration incomplete. Please contact support."
   // Include recovery steps in app
   ```

4. **Admin Dashboard Alert**:
   ```swift
   // Notify admins of orphaned Auth accounts
   // Show "Incomplete Registrations" section
   ```

---

## FAQ

### Q: Will this affect existing users?
**A**: No. Only affects users who had incomplete registration. Recovery is automatic on next login.

### Q: Is user data lost?
**A**: Minimal data loss. Recovery uses cached data (name, email). User may need to re-enter address/phone.

### Q: Can admin still approve?
**A**: Yes! Recovery document has `verified: false`, so normal approval workflow applies.

### Q: What if recovery fails?
**A**: Manual creation via Firebase Console is always available. See "Option 2" above.

### Q: Should we delete the orphaned Auth account?
**A**: No. Keep it and let recovery create the document. User can then log in normally.

---

## Support Checklist

When user reports this issue:

- [ ] Get user's email address
- [ ] Look up UID in Firebase Authentication
- [ ] Check if Firestore document exists at `users/{uid}`
- [ ] If missing, have user try logging in (triggers recovery)
- [ ] If recovery fails, create manually in Firebase Console
- [ ] Verify user can log in and see "Pending Approval"
- [ ] Approve user as admin
- [ ] Confirm user has full access

---

**Status**: ✅ Recovery feature implemented  
**Auto-Recovery**: ✅ Enabled by default  
**Manual Override**: ✅ Available via Firebase Console  
**User Impact**: ⚠️ Minimal (one-time login delay)

**Last Updated**: November 1, 2025
