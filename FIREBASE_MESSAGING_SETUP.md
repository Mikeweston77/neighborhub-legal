# Firebase Cloud Messaging Setup Guide

## Problem
Push notifications are not working because Firebase Messaging SDK is not configured in the iOS app.

## Solution: Add Firebase Messaging SDK

### Step 1: Add Firebase Messaging Package to Xcode

1. **Open Xcode project**
   ```bash
   open "/Users/mike/Desktop/Waterfall 3 V1.04/NeighborHub.xcodeproj"
   ```

2. **Add Firebase Messaging Package**
   - In Xcode, go to: **File → Add Package Dependencies...**
   - Search for: `https://github.com/firebase/firebase-ios-sdk`
   - Select **FirebaseMessaging** from the list of products
   - Click **Add Package**

   **OR** if Firebase is already added:
   - Select your project in the navigator
   - Select your app target
   - Go to **General → Frameworks, Libraries, and Embedded Content**
   - Click **+** and search for **FirebaseMessaging**
   - Add it to your target

### Step 2: Update NeighborHubApp.swift

The app needs to:
1. Import FirebaseMessaging
2. Configure Messaging delegate
3. Get FCM token (not just APNs token)

### Step 3: Enable Push Notifications Capability

1. In Xcode, select your project
2. Select the **NeighborHub** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes** and enable:
   - ✅ Remote notifications

### Step 4: Upload APNs Key to Firebase Console

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to: **Certificates, Identifiers & Profiles → Keys**
3. Click **+** to create a new key
4. Name it "APNs Key for NeighborHub"
5. Enable **Apple Push Notifications service (APNs)**
6. Click **Continue** → **Register** → **Download**
7. Save the `.p8` file and note the **Key ID** and **Team ID**

8. Upload to Firebase:
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Go to **Project Settings** (gear icon) → **Cloud Messaging**
   - Under **Apple app configuration**, click **Upload**
   - Upload your `.p8` key file
   - Enter **Key ID** and **Team ID**
   - Click **Upload**

### Step 5: Deploy Cloud Functions

```bash
cd "/Users/mike/Desktop/Waterfall 3 V1.04"
firebase deploy --only functions
```

## Quick Setup Script

I'll provide updated code files that include Firebase Messaging integration.

---

## Troubleshooting

### "Firebase Messaging not available"
- Make sure you added FirebaseMessaging package in Xcode
- Clean build folder: Product → Clean Build Folder
- Restart Xcode

### "APNs token not registered"
- Check that Push Notifications capability is enabled
- Verify you're testing on a real device (not simulator for production)
- Check Console.app for APNs registration errors

### "Functions not triggering"
- Verify functions are deployed: `firebase functions:list`
- Check function logs: `firebase functions:log`
- Ensure Firestore has data in the expected collections

---

**Next**: I'll update the app code to integrate Firebase Messaging properly.
