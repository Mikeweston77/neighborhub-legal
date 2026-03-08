# Firebase Authentication - Deployment Guide

## Quick Start

This guide walks you through enabling Firebase Authentication and deploying the updated security rules.

---

## Prerequisites

✅ **Completed:**
- FirebaseManager.swift updated with auth methods
- Firestore rules updated to require authentication
- Storage rules already secure
- Security audit completed

⏳ **Still Needed:**
- Enable Firebase Auth in Console
- Update UI for authentication flow
- Test authentication workflow

---

## Step 1: Enable Firebase Authentication

### Via Firebase Console:

1. Go to https://console.firebase.google.com
2. Select your project (NeighborHub)
3. Click **Authentication** in left sidebar
4. Click **Get Started** button
5. Click **Sign-in method** tab
6. Click **Email/Password** row
7. Toggle **Enable** switch
8. Click **Save**

### Verify:
✅ Email/Password should show as "Enabled" in Sign-in providers list

---

## Step 2: Deploy Security Rules

### Option A: Using the deployment script (Recommended)

```bash
cd "/Users/mike/Desktop/Waterfall 3 V1.04"
./deploy_firebase_rules.sh
```

The script will:
- ✅ Check if Firebase CLI is installed
- ✅ Validate Firestore rules syntax
- ✅ Deploy Firestore rules
- ✅ Deploy Storage rules
- ✅ Show success confirmation

### Option B: Manual deployment

```bash
# Login to Firebase (if not already logged in)
firebase login

# Set the correct project
firebase use --project YOUR_PROJECT_ID

# Validate Firestore rules first
firebase firestore:rules:validate firestore.rules

# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules
firebase deploy --only storage:rules
```

---

## Step 3: Understanding the Changes

### What Changed in Firestore Rules:

#### Before (Insecure):
```javascript
function isSignedIn() {
  return true;  // ❌ No real authentication
}

match /users/{userId} {
  allow read: if isSignedIn();  // Anyone could read
  allow write: if isSignedIn();  // Anyone could write
}
```

#### After (Secure):
```javascript
function isSignedIn() {
  return request.auth != null;  // ✅ Requires Firebase Auth
}

function isVerified() {
  return isSignedIn() && getUserData().verified == true;
}

match /users/{userId} {
  // Only admins and verified users can read profiles
  allow read: if isSignedIn() && 
    (isAdmin() || get(...users/{userId}).data.verified == true);
  
  // Users can only create their own profile
  allow create: if isSignedIn() && 
                   request.auth.uid == userId;
  
  // Users can update their own, admins can update any
  allow update: if isOwner(userId) || isAdmin();
}
```

### Key Security Improvements:

1. **Real Authentication**: `request.auth != null` enforced everywhere
2. **User Verification**: Content creation requires admin approval
3. **UID-based Documents**: Use `request.auth.uid` instead of email
4. **Ownership Validation**: Users can only modify their own content
5. **Role-Based Access**: Admin and committee roles properly enforced

---

## Step 4: Update App Code (TODO)

### Priority 1: Authentication Methods (Already Done ✅)

The following methods are ready to use in `FirebaseManager.swift`:

```swift
// Create new user account
FirebaseManager.shared.createUser(email: "user@example.com", password: "password123") { result in
    switch result {
    case .success(let user):
        print("Created user with UID: \(user.uid)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// Sign in existing user
FirebaseManager.shared.signIn(email: "user@example.com", password: "password123") { result in
    switch result {
    case .success(let user):
        print("Signed in user: \(user.uid)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// Get current user UID
if let uid = FirebaseManager.shared.getCurrentUserUID() {
    print("Current user UID: \(uid)")
}

// Sign out
try? FirebaseManager.shared.signOut()
```

### Priority 2: Update OnboardingView.swift (TODO)

Add password field and create Firebase Auth account:

```swift
// Add to OnboardingData
@Published var password: String = ""
@Published var confirmPassword: String = ""

// In submit action:
FirebaseManager.shared.createUser(email: data.email, password: data.password) { result in
    switch result {
    case .success(let user):
        // User created successfully, now create profile
        FirebaseManager.shared.createOrUpdateUserWithAuth(
            firstName: data.firstName,
            lastName: data.lastName,
            email: data.email,
            // ... other fields
        ) { profileResult in
            // Handle profile creation
        }
    case .failure(let error):
        // Show error to user
    }
}
```

### Priority 3: Update LoginView.swift (TODO)

Replace AppStorage-only login with Firebase Auth:

```swift
// Replace existing login logic with:
FirebaseManager.shared.signIn(email: email, password: password) { result in
    switch result {
    case .success(let user):
        // Fetch user profile from Firestore using user.uid
        // Store user info in AppStorage for quick access
        // Navigate to main app
    case .failure(let error):
        // Show error message
    }
}
```

### Priority 4: Update HomeView.swift (TODO)

Update registration to use authenticated UID:

```swift
// After creating Firebase Auth account:
FirebaseManager.shared.createOrUpdateUserWithAuth(
    firstName: data.firstName,
    lastName: data.lastName,
    email: data.email,
    phoneNumber: data.phoneNumber,
    // ... other profile fields
) { result in
    switch result {
    case .success(let uid):
        print("✅ Profile created with UID: \(uid)")
        // Store UID in AppStorage
        UserDefaults.standard.set(uid, forKey: "userUID")
    case .failure(let error):
        print("❌ Error creating profile: \(error)")
    }
}
```

---

## Step 5: Migration Strategy for Existing Users

### Current Situation:
- Existing users have documents at `users/{email}`
- New users will have documents at `users/{uid}`

### Option A: Gradual Migration (Recommended)

```swift
// On app launch, check if user needs migration
func migrateUserIfNeeded() {
    guard let email = UserDefaults.standard.string(forKey: "userEmail"),
          let uid = FirebaseManager.shared.getCurrentUserUID() else {
        return
    }
    
    // Check if user document exists at new location
    let newRef = Firestore.firestore().collection("users").document(uid)
    newRef.getDocument { snapshot, error in
        if snapshot?.exists == false {
            // User needs migration - copy from old location
            let oldRef = Firestore.firestore().collection("users").document(email)
            oldRef.getDocument { oldSnapshot, _ in
                if let data = oldSnapshot?.data() {
                    // Create new document with UID
                    newRef.setData(data) { error in
                        if error == nil {
                            print("✅ User migrated to UID-based document")
                            // Optional: Delete old document
                            oldRef.delete()
                        }
                    }
                }
            }
        }
    }
}
```

### Option B: Fresh Start (Simpler)

Since the app is in development:
1. All new users register with Firebase Auth
2. Existing test users re-register
3. Old email-based documents remain but are unused

---

## Step 6: Testing Checklist

### Test Authentication Flow:

```bash
# 1. Test New User Registration
- [ ] Open app on simulator/device
- [ ] Complete onboarding with email and password
- [ ] Verify Firebase Auth account created (check Firebase Console)
- [ ] Verify user profile created at users/{uid} (check Firestore)
- [ ] Verify user is marked as verified: false
- [ ] Verify user sees "pending approval" message

# 2. Test Login
- [ ] Sign out from app
- [ ] Sign in with registered email/password
- [ ] Verify correct user data loaded
- [ ] Verify unverified user has limited access

# 3. Test Admin Approval
- [ ] Admin opens Watch tab settings
- [ ] Admin sees new user in "Pending Users"
- [ ] Admin clicks approve button
- [ ] Verify user document updated with verified: true
- [ ] User app refreshes and gains full access

# 4. Test Security Rules
- [ ] Unverified user cannot post messages (should fail)
- [ ] Unverified user can read messages (should succeed)
- [ ] Verified user can post messages (should succeed)
- [ ] User cannot edit other users' content (should fail)
- [ ] Admin can edit any content (should succeed)

# 5. Test Password Features
- [ ] Test "Forgot Password" flow
- [ ] Verify password reset email sent
- [ ] Test password change
- [ ] Test wrong password shows error
```

---

## Step 7: Monitor and Verify

### Firebase Console Monitoring:

1. **Authentication Tab**
   - View all registered users
   - See last sign-in times
   - Check authentication methods

2. **Firestore Tab**
   - Verify user documents at `users/{uid}` (not `users/{email}`)
   - Check `verified` field status
   - Monitor real-time data changes

3. **Rules Tab**
   - View rules deployment history
   - Check "Usage" tab for denied requests
   - Review security warnings (if any)

### Expected Behavior:

✅ **Unauthenticated users:**
- Cannot read Firestore data (denied by rules)
- Cannot upload to Storage (denied by rules)
- Redirected to login screen

✅ **Authenticated but unverified users:**
- Can read community messages, events, marketplace
- Cannot post messages or create content
- See "pending approval" status

✅ **Verified users:**
- Full access to all features
- Can post messages, create events, add marketplace items
- Can update/delete their own content

✅ **Admins:**
- All verified user permissions
- Can approve/reject new users
- Can moderate any content (delete inappropriate posts)
- Can manage roles (assign committee members)

---

## Step 8: Rollback Plan (If Needed)

If you encounter issues and need to rollback:

### Option 1: Revert Rules in Firebase Console

1. Go to Firebase Console > Firestore > Rules
2. Click **Deployment history** tab
3. Select previous deployment
4. Click **Restore**

### Option 2: Deploy Old Rules

```bash
# If you have a backup of old rules
firebase deploy --only firestore:rules

# Or temporarily allow all access (TESTING ONLY)
# Add to firestore.rules:
function isSignedIn() {
  return true;  // Temporary - allows all access
}
```

⚠️ **Warning:** Only use permissive rules temporarily for debugging. Always return to secure rules for production.

---

## Common Issues and Solutions

### Issue 1: "Permission Denied" Errors

**Symptom:** App shows permission denied when accessing Firestore.

**Cause:** User not authenticated or rules too restrictive.

**Solution:**
```swift
// Verify user is authenticated
if let user = FirebaseManager.shared.getCurrentUser() {
    print("✅ User authenticated: \(user.uid)")
} else {
    print("❌ User not authenticated - need to sign in")
}
```

### Issue 2: Users Can't See Their Own Content

**Symptom:** User creates content but can't see it.

**Cause:** Document using old email-based ID instead of UID.

**Solution:**
```swift
// When creating documents, always use Auth UID:
let uid = FirebaseManager.shared.getCurrentUserUID()!
let data: [String: Any] = [
    "userId": uid,  // ✅ Use UID, not email
    "content": "...",
    // ...
]
```

### Issue 3: Migration Errors

**Symptom:** Existing users see errors after rules deployed.

**Cause:** User documents still at `users/{email}` instead of `users/{uid}`.

**Solution:** Run migration script (see Step 5) or have users re-register.

### Issue 4: Storage Upload Fails

**Symptom:** Profile photo or file uploads fail.

**Cause:** Storage path still using email instead of UID.

**Solution:**
```swift
// Update upload path to use UID:
let uid = FirebaseManager.shared.getCurrentUserUID()!
let storageRef = Storage.storage().reference()
    .child("users/\(uid)/profile/avatar.jpg")  // ✅ Use UID
```

---

## Next Steps

### Immediate (Before App Launch):
1. ✅ Deploy updated Firestore rules
2. ✅ Enable Firebase Authentication
3. ⏳ Update OnboardingView with password field
4. ⏳ Update LoginView with Firebase sign-in
5. ⏳ Test complete registration → approval → access flow

### Short Term (Within 1 Week):
6. Add password reset functionality
7. Add email verification
8. Implement password strength validation
9. Add biometric authentication (Face ID/Touch ID)
10. Test all security rules thoroughly

### Long Term (Future Enhancements):
11. Add 2FA (Two-Factor Authentication)
12. Implement session timeout
13. Add audit logging for admin actions
14. Set up App Check for rate limiting
15. Add account deletion feature (GDPR compliance)

---

## Resources

### Documentation:
- [Firebase Auth iOS Guide](https://firebase.google.com/docs/auth/ios/start)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Storage Security Rules](https://firebase.google.com/docs/storage/security)

### Firebase Console:
- **Authentication:** https://console.firebase.google.com/project/YOUR_PROJECT/authentication
- **Firestore:** https://console.firebase.google.com/project/YOUR_PROJECT/firestore
- **Storage:** https://console.firebase.google.com/project/YOUR_PROJECT/storage
- **Rules:** https://console.firebase.google.com/project/YOUR_PROJECT/database/firestore/rules

### Support:
- [Firebase Support](https://firebase.google.com/support)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/firebase)
- [GitHub Issues](https://github.com/firebase/firebase-ios-sdk/issues)

---

## Summary

✅ **Completed:**
- Firebase Authentication methods in FirebaseManager
- Secure Firestore rules (require auth + verification)
- Security audit and documentation
- Deployment scripts

⏳ **In Progress:**
- UI updates for authentication flow
- Testing and validation

🎯 **Goal:**
Secure, production-ready authentication system using Firebase Auth UIDs instead of email-based identification.

---

**Last Updated:** November 1, 2025  
**Status:** Ready for deployment and testing  
**Next Step:** Enable Firebase Auth in Console and deploy rules
