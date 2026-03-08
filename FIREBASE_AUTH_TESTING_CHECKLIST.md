# Firebase Authentication Testing Checklist

**Date**: November 1, 2025  
**Project**: NeighborHub (neighborhub-cd47d)  
**Status**: Ready for Testing

---

## ✅ Pre-Testing Setup (COMPLETE)

- [x] Firebase Authentication enabled in Console
- [x] Email/Password provider enabled
- [x] Firestore security rules deployed
- [x] Storage security rules deployed
- [x] App compiled without errors
- [x] OnboardingView collects password
- [x] HomeView uses UID-based paths

---

## 📋 Testing Checklist

### 1. Firebase Console Setup ⚠️ MANUAL STEP REQUIRED

**Action Required Now:**

1. Open Firebase Console: https://console.firebase.google.com/project/neighborhub-cd47d/authentication
2. Click **"Get Started"** (if first time) or **"Sign-in method"** tab
3. Find **"Email/Password"** in the provider list
4. Click on it to expand
5. **Toggle ON** the first switch (Email/Password)
6. Click **"Save"**

**Expected Result:**
- Email/Password provider shows as "Enabled"
- Users tab becomes available

---

### 2. Build and Run App

**Action:**
```bash
# Option 1: Use VS Code task
# Press Cmd+Shift+P → "Tasks: Run Task" → "Build NeighborHub iOS App"

# Option 2: Use xcodebuild directly
xcodebuild -project NeighborHub.xcodeproj \
  -scheme NeighborHub \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  build

# Option 3: Open in Xcode
open NeighborHub.xcodeproj
```

**Expected Result:**
- [ ] App builds successfully
- [ ] Launches in simulator/device
- [ ] Onboarding screens appear

---

### 3. Test New User Registration

**Action:**
1. Complete onboarding flow:
   - **First Name**: Test
   - **Last Name**: User
   - **Email**: test@neighborhub.com
   - **Street Address**: 123 Test Street
   - **Postal Code**: 12345
   - **Phone**: (555) 123-4567
   - **Profile Photo**: Select any image
   - **Password**: TestPass123! (meets requirements)
   - **Confirm Password**: TestPass123!

2. Tap "Complete Registration"

**Expected Result:**
- [ ] All validation passes (green checkmarks)
- [ ] "Creating account..." appears
- [ ] Success message or redirect to main app
- [ ] No error alerts

**If Error Occurs:**
- Check Xcode console for error messages
- Verify Firebase Auth is enabled in console
- Check network connectivity

---

### 4. Verify Firebase Authentication Created User

**Action:**
1. Open Firebase Console: https://console.firebase.google.com/project/neighborhub-cd47d/authentication/users
2. Look for new user in Users list

**Expected Result:**
- [ ] User appears with email: test@neighborhub.com
- [ ] User has a UID (e.g., `xYz123AbC456...`)
- [ ] Created date shows current timestamp
- [ ] Sign-in provider shows "Password"

**Screenshot Location:** Authentication > Users tab

---

### 5. Verify Firestore Document Created

**Action:**
1. Open Firestore Console: https://console.firebase.google.com/project/neighborhub-cd47d/firestore/data
2. Navigate to `users` collection
3. Find document with ID matching the user's UID

**Expected Result:**
- [ ] Document exists at path: `users/{uid}` (NOT `users/{email}`)
- [ ] Document contains:
  ```
  {
    name: "Test User"
    firstName: "Test"
    lastName: "User"
    email: "test@neighborhub.com"
    address: "123 Test Street"
    postalCode: "12345"
    phone: "(555) 123-4567"
    verified: false
    isAdmin: false
    role: "User"
    joinedDate: <timestamp>
    profileImageURL: "https://..." (if image uploaded)
  }
  ```

**Screenshot Location:** Firestore > users > {uid}

---

### 6. Verify Storage Profile Image Uploaded

**Action:**
1. Open Storage Console: https://console.firebase.google.com/project/neighborhub-cd47d/storage
2. Navigate to folder structure: `users/{uid}/profile/`
3. Look for `avatar.jpg` or `profile.jpg`

**Expected Result:**
- [ ] Image exists at path: `users/{uid}/profile/avatar.jpg` (NOT `profiles/{email}/`)
- [ ] Image is viewable (click to preview)
- [ ] File size is reasonable (< 5 MB)
- [ ] downloadURL is stored in Firestore user document

**Screenshot Location:** Storage > users > {uid} > profile

---

### 7. Test Security Rules - Unauthenticated Access

**Action:**
1. Sign out of the app (if sign-out exists) OR clear app data/reinstall
2. Try to access data without authentication

**Expected Result:**
- [ ] CANNOT read Firestore documents
- [ ] CANNOT write Firestore documents
- [ ] CANNOT download Storage files
- [ ] App shows "Please sign in" or similar

**Testing via Firebase CLI:**
```bash
# Should fail with permission denied
firebase firestore:get /users/test123
```

---

### 8. Test Security Rules - Authenticated Unverified User

**Action:**
1. Sign in with test@neighborhub.com
2. Try to access other users' data
3. Try to create events/posts

**Expected Result:**
- [ ] CAN read own user document (`users/{own_uid}`)
- [ ] CANNOT read other users' documents
- [ ] CANNOT read marketplace/events (verified=false blocks access)
- [ ] CAN upload to own Storage paths (`users/{own_uid}/`)

---

### 9. Test Admin Approval Workflow

**Action:**
1. Sign in as admin account (create one if needed)
2. Navigate to Admin tab
3. Look for "Pending Approval" section

**Expected Result:**
- [ ] Test user appears in "Pending Approval"
- [ ] Shows profile picture, name, email
- [ ] Has "Approve" and "Reject" buttons

**Approve the User:**
- [ ] Tap "Approve" button
- [ ] User moves to "Approved Users" section
- [ ] Verify in Firestore: `verified: true`

**After Approval:**
- [ ] Sign in as test@neighborhub.com again
- [ ] Should now have access to marketplace, events, community posts
- [ ] Profile shows verified badge/status

---

### 10. Test Security Rules - Authenticated Verified User

**Action:**
1. Sign in with verified test@neighborhub.com
2. Test reading various collections

**Expected Result:**
- [ ] CAN read marketplace items
- [ ] CAN read events
- [ ] CAN read community messages
- [ ] CAN read other verified users' profiles
- [ ] CAN create new posts/events/marketplace items
- [ ] CANNOT read admin-only data

---

### 11. Test Password Reset Flow (Optional)

**Action:**
1. Sign out
2. Tap "Forgot Password?" (if UI exists)
3. Enter: test@neighborhub.com
4. Check email inbox

**Expected Result:**
- [ ] Success message appears
- [ ] Email received with reset link
- [ ] Can reset password via link
- [ ] Can sign in with new password

---

### 12. Test Edge Cases

**Test 1: Duplicate Email Registration**
- [ ] Try registering test@neighborhub.com again
- [ ] Should show error: "Email already in use"

**Test 2: Weak Password**
- [ ] Try password "123" (too short)
- [ ] Should show validation errors
- [ ] Submit button disabled

**Test 3: Mismatched Passwords**
- [ ] Enter different passwords in confirm field
- [ ] Should show "Passwords don't match"
- [ ] Submit button disabled

**Test 4: Invalid Email Format**
- [ ] Try email "notanemail"
- [ ] Should show "Invalid email format"

---

## 🐛 Common Issues & Solutions

### Issue: "Auth domain not configured"
**Solution:** Add app to Firebase project settings

### Issue: "Permission denied" errors
**Solution:** Check that:
1. User is authenticated (Auth.auth().currentUser exists)
2. Security rules deployed correctly
3. User document has `verified: true` if accessing protected data

### Issue: Profile image not uploading
**Solution:** Check that:
1. Storage rules allow write to `users/{uid}/profile/`
2. File size < 5 MB
3. User is authenticated
4. UID is correctly extracted from Auth.auth().currentUser.uid

### Issue: User document created with email as ID
**Solution:** Verify HomeView uses:
```swift
let uid = UserDefaults.standard.string(forKey: "firebase_uid") ?? ""
```
NOT the email address

### Issue: Can't see pending users in admin panel
**Solution:** Check that:
1. Admin user has `isAdmin: true` in Firestore
2. Query uses `.whereField("verified", isEqualTo: false)`
3. Admin panel uses proper FirebaseManager methods

---

## 📊 Success Criteria

### All Tests Pass When:

✅ **Authentication:**
- New users can register with email/password
- Users appear in Firebase Console with UIDs
- Passwords are securely hashed (not visible in console)

✅ **Firestore:**
- Documents created at `users/{uid}` (UID-based)
- Documents contain correct user data
- Unverified users cannot access protected data
- Verified users can access public data

✅ **Storage:**
- Profile images upload to `users/{uid}/profile/`
- Images are accessible by authenticated users
- Unauthenticated users cannot download files

✅ **Security Rules:**
- Unauthenticated access blocked
- Authenticated users can only access their own data
- Verified users can access community features
- Admins can manage all users

---

## 📸 Evidence Collection

### Screenshots to Take:
1. Firebase Auth > Users tab (showing new user)
2. Firestore > users/{uid} document
3. Storage > users/{uid}/profile/avatar.jpg
4. App onboarding completion
5. Admin panel showing pending approval
6. Admin panel showing approved user

### Logs to Check:
- Xcode console during registration
- Firebase Functions logs (if any)
- Network requests in Xcode Network inspector

---

## ✅ Sign-Off

**Tested By:** _________________  
**Date:** _________________  
**Result:** ☐ Pass  ☐ Fail  ☐ Partial

**Notes:**
_______________________________________________________
_______________________________________________________
_______________________________________________________

---

## 🚀 Next Steps After Testing

1. [ ] Create additional test users for different scenarios
2. [ ] Test on physical device (not just simulator)
3. [ ] Monitor Firebase Analytics for auth events
4. [ ] Set up Firebase Performance Monitoring
5. [ ] Configure production vs. development environments
6. [ ] Add error tracking (Crashlytics)
7. [ ] Implement sign-out functionality (if not exists)
8. [ ] Create LoginView for existing users
9. [ ] Add "Remember Me" functionality
10. [ ] Implement email verification (optional)

---

**Quick Test Command:**
```bash
./test_auth_and_rules.sh
```

This will guide you through the verification process.
