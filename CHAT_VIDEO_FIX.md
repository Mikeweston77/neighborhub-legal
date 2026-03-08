# Chat Video Visibility Fix

## Problem
Chat videos are only visible to the user who uploaded them. Other users cannot see or play the videos.

## Root Cause
The issue is with Firebase Storage security rules. When videos are uploaded, they are stored in a user-specific path:
```
uploads/{userId}/communityMessages/{messageId}/files/{filename}
```

If the Firebase Storage security rules restrict read access based on the user ID in the path, other users cannot download these videos even though they can see the message in Firestore.

## Solution

### Update Firebase Storage Security Rules

You need to update your Firebase Storage security rules to allow **authenticated users** to read chat attachments uploaded by any user.

#### Go to Firebase Console:
1. Open [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Storage** → **Rules**

#### Replace with these rules:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // Allow authenticated users to read all chat attachments
    // This enables video sharing in community chat
    match /uploads/{userId}/communityMessages/{messageId}/{allPaths=**} {
      // Anyone authenticated can read (download) chat attachments
      allow read: if request.auth != null;
      
      // Only the uploader can write/delete
      allow write, delete: if request.auth != null && request.auth.uid == userId;
    }
    
    // Allow authenticated users to upload to their own folders
    match /uploads/{userId}/{allPaths=**} {
      // Anyone authenticated can read
      allow read: if request.auth != null;
      
      // Only the user can write to their own folder
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Incident images (emergency reports)
    match /incidents/{incidentId}/{allPaths=**} {
      // Anyone authenticated can read incident images
      allow read: if request.auth != null;
      
      // Anyone authenticated can upload incident images
      allow write: if request.auth != null;
    }
    
    // Active alert images
    match /activeAlerts/{alertId}/{allPaths=**} {
      // Anyone authenticated can read alert images
      allow read: if request.auth != null;
      
      // Anyone authenticated can upload alert images
      allow write: if request.auth != null;
    }
    
    // Marketplace images
    match /marketplace/{itemId}/{allPaths=**} {
      // Anyone can read marketplace images (public)
      allow read: if true;
      
      // Only authenticated users can upload
      allow write: if request.auth != null;
    }
    
    // User profile pictures
    match /users/{userId}/profile/{allPaths=**} {
      // Anyone authenticated can read profile pictures
      allow read: if request.auth != null;
      
      // Only the user can update their own profile picture
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Default: deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

### Key Changes:
1. **Community Messages** (`uploads/{userId}/communityMessages/...`): 
   - ✅ Any authenticated user can **read** (download) attachments
   - ✅ Only the uploader can **write** (upload) or delete
   
2. **General Uploads** (`uploads/{userId}/...`):
   - ✅ Any authenticated user can **read**
   - ✅ Only the owner can **write**

3. **Incidents & Alerts**: Public read for all authenticated users

4. **Marketplace**: Public read for everyone (even unauthenticated)

### Test the Fix

After deploying these rules:

1. **User A** uploads a video in community chat
2. **User B** should now be able to:
   - See the video thumbnail/preview
   - Tap to play the video
   - Download and view the video

### Firestore Security Rules (Optional Enhancement)

While you're in the Firebase Console, also verify your Firestore security rules allow all authenticated users to read community messages:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Community messages - all authenticated users can read
    match /communityMessages/{messageId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        (resource.data.user == request.auth.token.name || 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
    }
    
    // User profiles
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Active alerts
    match /activeAlerts/{alertId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow delete: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }
    
    // Incidents
    match /incidents/{incidentId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null;
    }
    
    // Marketplace items
    match /marketplaceItems/{itemId} {
      allow read: if true; // Public read
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null;
    }
    
    // Default deny
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## Verification Checklist

- [ ] Deploy Firebase Storage rules in Firebase Console
- [ ] Test with two different user accounts
- [ ] User A uploads a video in chat
- [ ] User B can see the video message
- [ ] User B can tap and play the video
- [ ] Check Firebase Console logs for any denied requests
- [ ] Verify videos show up in Firebase Storage console

## Additional Notes

### Why This Happens
- Firebase Storage creates authenticated download URLs
- These URLs include authentication tokens
- The tokens are validated against storage rules
- If rules check `request.auth.uid == userId` for reads, only the uploader can access
- Changing to `request.auth != null` allows any authenticated user to read

### Security Considerations
- ✅ Videos are still protected (must be authenticated)
- ✅ Only members of your app can view videos
- ✅ Upload permission still restricted to file owner
- ✅ This is appropriate for a community app where content is meant to be shared
- ⚠️ If you need more granular permissions (e.g., neighborhood-specific), you'll need to enhance the rules with custom claims

### Performance Impact
- ✅ No code changes needed in the app
- ✅ Videos continue to work exactly as before for the uploader
- ✅ Videos now work for all other users too
- ✅ No performance degradation

## Troubleshooting

If videos still don't work after updating rules:

1. **Clear app data and re-login**
   - Force quit the app
   - Delete and reinstall if necessary
   - Login again to refresh authentication tokens

2. **Check Firebase Console → Storage → Usage**
   - Look for denied requests
   - Click on failed requests to see which rule blocked them

3. **Test with Firebase Storage Console**
   - Navigate to the uploaded video in Storage console
   - Try to get the download URL
   - Test the URL in a browser while logged in

4. **Verify Authentication**
   - Ensure users are properly authenticated with Firebase Auth
   - Check that `Auth.auth().currentUser` is not nil when viewing messages

5. **Check Firestore Document**
   - Open Firebase Console → Firestore
   - Find the message document in `communityMessages` collection
   - Verify `fileURL` field contains a valid Firebase Storage URL
   - URL should look like: `https://firebasestorage.googleapis.com/v0/b/your-project.appspot.com/o/uploads%2F...`

## Success Confirmation

You'll know it's working when:
- ✅ Different users can all see and play the same video
- ✅ Video thumbnails appear in chat bubbles for everyone
- ✅ Tapping videos opens the player for all users
- ✅ No "Access Denied" or "Failed to download" errors in console logs
