# Push Notifications Deployment Guide

## Quick Start

This guide will help you deploy the FCM push notification system for NeighborHub.

## Prerequisites

1. **Firebase CLI installed**
   ```bash
   npm install -g firebase-tools
   ```

2. **Firebase Project configured**
   - GoogleService-Info.plist in NeighborHub folder ✅
   - Firebase project exists in Firebase Console

3. **APNs Certificate**
   - Upload APNs certificate to Firebase Console
   - Navigate to: Project Settings → Cloud Messaging → iOS App
   - Upload your .p8 key or .p12 certificate

## Deployment Steps

### Step 1: Login to Firebase
```bash
firebase login
```

### Step 2: Navigate to Project Directory
```bash
cd "/Users/mike/Desktop/Waterfall 3 V1.04"
```

### Step 3: Install Cloud Functions Dependencies
```bash
cd functions
npm install
cd ..
```

### Step 4: Deploy Cloud Functions
```bash
firebase deploy --only functions
```

This will deploy all 8 notification functions:
- `onNewCommunityMessage` - Chat notifications
- `onNewIncident` - Incident report notifications
- `onNewEvent` - Event notifications
- `onNewMarketplaceListing` - Marketplace notifications
- `onNewNewsletter` - Newsletter notifications
- `onNewPoll` - New poll notifications
- `onPollVote` - Poll vote notifications (to creator only)
- Plus existing functions: `processAdvertUpload`, `onChatAttachmentFinalize`, `pinMessage`

### Step 5: Verify Deployment
After deployment completes, you should see:
```
✔  functions: Finished running predeploy script.
i  functions: ensuring required API cloudfunctions.googleapis.com is enabled...
✔  functions: all necessary APIs are enabled
i  functions: preparing functions directory for uploading...
✔  functions: functions folder uploaded successfully
i  functions: creating/updating functions...
✔  functions[onNewCommunityMessage]: Successful create operation.
✔  functions[onNewIncident]: Successful create operation.
... (etc.)
```

### Step 6: Test Notifications

#### Test Chat Notification
1. Open app on Device A (logged in as User A)
2. Send a community chat message
3. Check Device B (logged in as User B) - should receive notification
4. User A should NOT receive notification

#### Test Incident Notification
1. User A creates an incident report
2. All users except User A should receive notification
3. Check severity icon matches (🚨 Critical, ⛔ High, ⚠️ Medium/Low)

#### Test Poll Notifications
1. User A creates a poll
2. All users except User A receive "📊 New Community Poll" notification
3. User B votes on the poll
4. ONLY User A receives "🗳️ New Vote on Your Poll" notification

## Monitoring

### View Cloud Functions Logs
```bash
firebase functions:log
```

### Real-time Logs (with filter)
```bash
firebase functions:log --only onNewCommunityMessage
```

### Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to Functions → Dashboard
4. View invocations, errors, and performance metrics

## Troubleshooting

### Issue: "Function not found"
- **Solution**: Re-deploy functions with `firebase deploy --only functions`

### Issue: No notifications received
1. **Check APNs certificate**: Firebase Console → Project Settings → Cloud Messaging
2. **Check device token**: Verify token stored in Firestore at `users/{uid}/tokens/{token}`
3. **Check Cloud Functions logs**: `firebase functions:log` - look for "Successfully sent X notifications"
4. **Check iOS permissions**: Settings → NeighborHub → Notifications → Allow Notifications

### Issue: Sender receives own notifications
- **Check logs**: Look for sender UID extraction in Cloud Functions logs
- **Verify document fields**: Ensure `senderId`, `uid`, `reporterId`, etc. are set correctly
- **Debug**: Add console.log in Cloud Functions to print sender UID and filtered tokens

### Issue: "Permission denied" errors
- **Solution**: Update Firestore security rules to allow functions to read user tokens:
  ```javascript
  match /users/{userId}/tokens/{token} {
    allow read: if request.auth != null && request.auth.uid == userId;
    allow write: if request.auth != null && request.auth.uid == userId;
  }
  ```

## Updating Functions

If you make changes to `functions/index.js`:

1. Save the file
2. Re-deploy:
   ```bash
   firebase deploy --only functions
   ```
3. Wait for deployment to complete (1-2 minutes)
4. Test changes immediately - no app rebuild required

## Cost Considerations

### Firebase Cloud Functions Pricing
- **Free tier**: 2M invocations/month, 400K GB-seconds/month
- **Typical usage**: 
  - 100 users, 50 messages/day = 5,000 invocations/day
  - Well within free tier for small communities

### Firebase Cloud Messaging
- **Free**: Unlimited notifications
- No cost for sending notifications

### Firestore Reads
- **Cost**: Collection group query (`tokens`) counts as 1 read per token
- **Optimization**: Implement notification preferences to reduce unnecessary reads

## Security Best Practices

1. **Never expose FCM server key** in client code
2. **Use Firestore security rules** to protect user tokens
3. **Validate data** in Cloud Functions before sending notifications
4. **Clean up invalid tokens** to reduce costs and improve delivery rates

## Next Steps

### Add Notification Preferences (Optional)
See `PUSH_NOTIFICATION_IMPLEMENTATION.md` for details on:
- Adding user preferences UI
- Filtering notifications based on user settings
- Implementing do-not-disturb mode

### Deep Linking (Optional)
Implement notification tap handling to navigate to specific content:
1. Parse `data` payload in `didReceive response` delegate
2. Use `type` and `{contentType}Id` to navigate
3. Update `ContentView` to handle deep links

## Support

For issues or questions:
1. Check Cloud Functions logs: `firebase functions:log`
2. Check Firebase Console for deployment status
3. Review `PUSH_NOTIFICATION_IMPLEMENTATION.md` for architecture details

## Rollback

If you need to rollback to previous version:
```bash
firebase functions:delete onNewCommunityMessage
firebase functions:delete onNewIncident
firebase functions:delete onNewEvent
firebase functions:delete onNewMarketplaceListing
firebase functions:delete onNewNewsletter
firebase functions:delete onNewPoll
firebase functions:delete onPollVote
```

Then re-deploy the previous version of `functions/index.js`.

---

**Last Updated**: November 6, 2025  
**Status**: ✅ Production Ready
