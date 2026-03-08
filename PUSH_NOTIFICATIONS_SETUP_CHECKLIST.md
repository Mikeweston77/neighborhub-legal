# Push Notifications Setup Checklist

## ✅ Current Status
- [x] Cloud Functions implemented (8 notification triggers)
- [x] iOS app code updated with Firebase Messaging
- [ ] **Firebase Messaging SDK added to Xcode project** ⚠️ **ACTION REQUIRED**
- [ ] Push Notifications capability enabled
- [ ] APNs key uploaded to Firebase Console
- [ ] Cloud Functions deployed

---

## 🚀 Setup Steps (Do These Now)

### Step 1: Add Firebase Messaging SDK to Xcode

**Option A: Using Xcode UI (Recommended)**
1. Open project in Xcode:
   ```bash
   open "/Users/mike/Desktop/Waterfall 3 V1.04/NeighborHub.xcodeproj"
   ```

2. In Xcode menu: **File → Add Package Dependencies...**

3. In the search box, paste:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```

4. Click **Add Package**

5. In the product selection dialog:
   - ✅ Check **FirebaseMessaging**
   - Click **Add Package**

**Option B: If Firebase SDK already added**
1. Select project in navigator → Select **NeighborHub** target
2. Go to **General** tab → **Frameworks, Libraries, and Embedded Content**
3. Click **+** button
4. Search for **FirebaseMessaging**
5. Click **Add**

---

### Step 2: Enable Push Notifications Capability

1. In Xcode, select your project in the navigator
2. Select the **NeighborHub** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** button
5. Select **Push Notifications**
6. Click **+ Capability** again
7. Select **Background Modes**
8. Enable:
   - ✅ **Remote notifications**

---

### Step 3: Get APNs Key from Apple Developer

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Sign in with your Apple Developer account
3. Navigate to: **Certificates, Identifiers & Profiles**
4. Click **Keys** in the sidebar
5. Click the **+** button to create a new key
6. Enter name: `APNs Key for NeighborHub`
7. Enable: ✅ **Apple Push Notifications service (APNs)**
8. Click **Continue** → **Register**
9. **Download the .p8 file** (you can only download once!)
10. **Note the Key ID** (shown after download, e.g., `ABC123XYZ`)
11. **Note your Team ID** (top-right of page, 10 characters)

---

### Step 4: Upload APNs Key to Firebase

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your **NeighborHub** project
3. Click the **⚙️ gear icon** → **Project settings**
4. Go to the **Cloud Messaging** tab
5. Scroll down to **Apple app configuration**
6. Under **APNs Authentication Key**, click **Upload**
7. Upload your `.p8` file from Step 3
8. Enter the **Key ID** from Step 3
9. Enter your **Team ID** from Step 3
10. Click **Upload**

You should see: ✅ **APNs key uploaded successfully**

---

### Step 5: Build and Test the App

1. **Clean build folder** (important after adding package):
   ```
   Xcode menu → Product → Clean Build Folder
   ```

2. **Build the app**:
   ```bash
   xcodebuild -project NeighborHub.xcodeproj \
     -scheme NeighborHub \
     -configuration Debug \
     -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
     build
   ```

3. **Check for errors**:
   - If you see "Cannot find 'Messaging' in scope", the SDK isn't added yet
   - Go back to Step 1

---

### Step 6: Deploy Cloud Functions

```bash
cd "/Users/mike/Desktop/Waterfall 3 V1.04"
firebase login
cd functions && npm install && cd ..
firebase deploy --only functions
```

**Expected output:**
```
✔  functions: Finished running predeploy script.
✔  functions[onNewCommunityMessage]: Successful create operation.
✔  functions[onNewIncident]: Successful create operation.
✔  functions[onNewEvent]: Successful create operation.
✔  functions[onNewMarketplaceListing]: Successful create operation.
✔  functions[onNewNewsletter]: Successful create operation.
✔  functions[onNewPoll]: Successful create operation.
✔  functions[onPollVote]: Successful create operation.
```

---

## 🧪 Testing Push Notifications

### Prerequisites
- Two iOS devices (or one device + one simulator)
- Two different user accounts (User A and User B)
- Cloud Functions deployed
- APNs key configured in Firebase

### Test Scenario 1: Chat Message Notification
1. **Device A** (User A): Send a community chat message
2. **Device B** (User B): Should receive notification: "💬 New Community Message"
3. **Device A** (User A): Should NOT receive notification (sender excluded)

### Test Scenario 2: Poll Notification
1. **Device A** (User A): Create a new poll
2. **Device B** (User B): Should receive notification: "📊 New Community Poll"
3. **Device B** (User B): Vote on the poll
4. **Device A** (User A): Should receive notification: "🗳️ New Vote on Your Poll"
5. **Device B** (User B): Should NOT receive vote notification (only creator notified)

### Check Logs
```bash
# iOS app logs (look for FCM token)
# In Xcode: View → Debug Area → Show Debug Area
# Look for: "📱 FCM Token: ..."

# Cloud Functions logs
firebase functions:log

# Look for:
# "📱 Found X tokens (excluding sender ...)"
# "✅ Successfully sent X notifications"
```

---

## 🐛 Troubleshooting

### Problem: "Cannot find 'Messaging' in scope"
**Solution**: Firebase Messaging SDK not added to Xcode project
- Follow **Step 1** above to add the package
- Clean build folder: Product → Clean Build Folder
- Restart Xcode

### Problem: "No FCM token received"
**Checklist**:
1. ✅ Firebase Messaging SDK added?
2. ✅ Push Notifications capability enabled?
3. ✅ APNs key uploaded to Firebase Console?
4. ✅ Testing on real device (not simulator for production)?
5. ✅ User granted notification permissions?

### Problem: "APNs token not delivered to Firebase"
**Check**:
1. Open Xcode Console while app is running
2. Look for: `📱 APNs Device Token: ...`
3. Look for: `✅ APNs token passed to Firebase Messaging`
4. If missing, check **Step 2** (capabilities)

### Problem: "Cloud Functions not triggering"
**Check**:
```bash
# List deployed functions
firebase functions:list

# Check function logs
firebase functions:log --limit 50

# Test manually by creating data in Firestore Console
```

### Problem: "Notifications not showing up"
**Check**:
1. Settings → NeighborHub → Notifications → Allow Notifications (enabled?)
2. Check if notifications show in Notification Center (swipe down from top)
3. Check Cloud Functions logs for "Successfully sent X notifications"
4. Try sending from Firebase Console: Cloud Messaging → Send test message

---

## 📊 Verify Setup

Run these commands to verify everything is ready:

```bash
# 1. Check Firebase project is configured
firebase projects:list

# 2. Check which functions are deployed
firebase functions:list

# 3. Check recent function invocations
firebase functions:log --limit 10

# 4. Build iOS app to verify Firebase Messaging compiles
cd "/Users/mike/Desktop/Waterfall 3 V1.04"
xcodebuild -project NeighborHub.xcodeproj \
  -scheme NeighborHub \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  build
```

---

## 🎯 Success Criteria

You'll know it's working when:
1. ✅ App builds without "Cannot find 'Messaging'" errors
2. ✅ Console shows: `📱 FCM Token: ...` when app launches
3. ✅ Token stored in Firestore: `users/{uid}/tokens/{token}`
4. ✅ Cloud Functions show in Firebase Console
5. ✅ User B receives notification when User A creates content
6. ✅ User A does NOT receive notification for their own content

---

## 📝 Quick Reference

### Key Files Modified
- `NeighborHub/NeighborHubApp.swift` - FCM integration
- `NeighborHub/Managers/FirebaseManager.swift` - Token storage
- `functions/index.js` - 8 notification triggers

### Firestore Structure
```
users/
  {uid}/
    tokens/
      {fcmToken}/
        - token: string
        - platform: "ios"
        - createdAt: timestamp
        - lastUsed: timestamp
```

### Cloud Functions Deployed
1. `onNewCommunityMessage` - Chat notifications
2. `onNewIncident` - Incident reports
3. `onNewEvent` - Event creation
4. `onNewMarketplaceListing` - Marketplace items
5. `onNewNewsletter` - Newsletters
6. `onNewPoll` - New polls
7. `onPollVote` - Poll votes (creator only)
8. Plus existing: `processAdvertUpload`, `onChatAttachmentFinalize`, `pinMessage`

---

## 🔗 Helpful Links

- [Firebase iOS Setup](https://firebase.google.com/docs/ios/setup)
- [Firebase Cloud Messaging iOS](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [Apple Developer Portal](https://developer.apple.com/account)
- [Firebase Console](https://console.firebase.google.com)

---

**Start with Step 1** and work through each step in order. Once complete, notifications will work! 🎉
