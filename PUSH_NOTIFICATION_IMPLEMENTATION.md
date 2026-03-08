# Push Notification Implementation

## Overview
NeighborHub now has complete Firebase Cloud Messaging (FCM) integration to send push notifications to all users when new content is added to the app. The sender/creator of content never receives their own notifications.

## Architecture

### iOS App (Client-Side)
1. **Token Registration** (`NeighborHubApp.swift`)
   - App registers for remote notifications on launch
   - APNs device token is captured in `didRegisterForRemoteNotificationsWithDeviceToken`
   - Token is stored in Firestore: `users/{uid}/tokens/{token}`
   - Token structure:
     ```json
     {
       "token": "apns_device_token_string",
       "platform": "ios",
       "createdAt": "timestamp",
       "lastUsed": "timestamp"
     }
     ```

2. **FirebaseManager Integration**
   - Added `storeFCMToken(apnsToken:completion:)` method
   - Stores tokens in user-specific subcollection for multi-device support
   - Automatically updates `lastUsed` timestamp on re-registration

### Cloud Functions (Server-Side)
Located in `functions/index.js`, the following triggers are implemented:

#### 1. Community Chat Messages
- **Trigger**: `onNewCommunityMessage` on `communityMessages/{messageId}` create
- **Notification**: "💬 New Community Message"
- **Body**: "{SenderName}: {first 100 chars of message}"
- **Excludes**: Message sender

#### 2. Incident Reports
- **Trigger**: `onNewIncident` on `incidents/{incidentId}` create
- **Notification**: "⚠️ New Incident Report" (🚨 for Critical, ⛔ for High)
- **Body**: "{Title} - Severity: {severity}"
- **Excludes**: Incident reporter

#### 3. Events
- **Trigger**: `onNewEvent` on `events/{eventId}` create
- **Notification**: "📅 New Event" (varies by event type)
- **Body**: "{Event title}"
- **Excludes**: Event creator

#### 4. Marketplace Listings
- **Trigger**: `onNewMarketplaceListing` on `marketplace/{listingId}` create
- **Notification**: "🛒 New Marketplace Listing"
- **Body**: "{Title} - {category}"
- **Excludes**: Listing seller

#### 5. Newsletters
- **Trigger**: `onNewNewsletter` on `newsletters/{newsletterId}` create
- **Notification**: "📰 New Newsletter"
- **Body**: "{Newsletter title}"
- **Excludes**: Newsletter author

#### 6. Polls
- **Trigger**: `onNewPoll` on `polls/active` update (when polls array grows)
- **Notification**: "📊 New Community Poll"
- **Body**: "{Poll question}"
- **Excludes**: Poll creator

#### 7. Poll Votes
- **Trigger**: `onPollVote` on `polls/active` update (when vote count increases)
- **Notification**: "🗳️ New Vote on Your Poll"
- **Body**: "Someone voted on: {question}"
- **Sent to**: Poll creator ONLY (not broadcast)

## Helper Functions

### `getUserTokensExceptSender(senderUid)`
- Uses `collectionGroup('tokens')` to query all user tokens
- Filters out sender's UID
- Returns array of `{token, uid}` objects

### `sendNotifications(tokens, notification, data)`
- Sends FCM multicast message to multiple tokens
- Handles success/failure counts
- Logs invalid tokens for cleanup
- Supports custom data payload for deep linking

## Firestore Structure

```
users/
  {uid}/
    tokens/
      {tokenId}/
        - token: string
        - platform: string ("ios")
        - createdAt: timestamp
        - lastUsed: timestamp
```

## Data Flow

1. **User Action**: User creates content (message, incident, event, etc.)
2. **Firestore Write**: Content document written to collection
3. **Cloud Function Trigger**: `onCreate` or `onUpdate` fires
4. **Token Query**: Function queries all user tokens except sender
5. **FCM Send**: `admin.messaging().sendMulticast()` sends notifications
6. **Device Delivery**: APNs delivers to all devices with valid tokens
7. **App Display**: iOS shows notification banner with title/body

## Sender Exclusion Logic

All notification functions extract the sender/creator UID from the document:
- `senderId`, `uid`, `reporterId`, `creatorUid`, `sellerId`, `authorId`

These patterns cover all content types in the app.

## Testing

### Prerequisites
1. Two or more iOS devices/simulators with different Firebase Auth users
2. Valid APNs certificates configured in Firebase Console
3. Cloud Functions deployed: `firebase deploy --only functions`

### Test Scenarios
1. **Chat Message**: User A sends message → User B receives notification
2. **Incident Report**: User A reports incident → All users except A notified
3. **Poll Creation**: User A creates poll → All users except A notified
4. **Poll Vote**: User B votes on User A's poll → Only User A notified
5. **Multi-Device**: User A has 2 devices → notifications sent to both

### Verification
- Check Cloud Functions logs: `firebase functions:log`
- Check iOS Console for APNs delivery
- Verify `successCount` and `failureCount` in logs

## Future Enhancements

### Notification Preferences (Planned)
Add to Firestore `users/{uid}`:
```json
{
  "notificationsEnabled": true,
  "notificationPreferences": {
    "chat": true,
    "incidents": true,
    "events": true,
    "marketplace": true,
    "newsletters": true,
    "polls": true,
    "pollVotes": true
  }
}
```

### Implementation Steps
1. Add settings UI for notification preferences
2. Update Cloud Functions to check preferences before sending
3. Filter tokens based on user preferences

### Deep Linking
- Notifications include `type` and `{contentType}Id` in data payload
- iOS app can parse notification data and navigate to specific content
- Implement `UNUserNotificationCenterDelegate` handling in `AppDelegate`

## Troubleshooting

### No Notifications Received
1. Check APNs certificate in Firebase Console
2. Verify device token stored in Firestore: `users/{uid}/tokens`
3. Check Cloud Functions logs for errors
4. Ensure app has notification permissions granted

### Sender Receiving Own Notifications
1. Verify sender UID is correctly extracted from document
2. Check `getUserTokensExceptSender` filtering logic
3. Confirm document has `senderId`, `uid`, or equivalent field

### Token Cleanup
Invalid tokens (expired, uninstalled app) should be removed from Firestore:
- Monitor `failureCount` in Cloud Functions logs
- Implement token cleanup job to remove tokens with repeated failures

## Deployment

### Deploy Cloud Functions
```bash
cd /Users/mike/Desktop/Waterfall\ 3\ V1.04
firebase deploy --only functions
```

### Deploy Firestore Rules (if needed)
```bash
firebase deploy --only firestore:rules
```

### iOS App Build
```bash
xcodebuild -project NeighborHub.xcodeproj \
  -scheme NeighborHub \
  -configuration Release \
  -destination "generic/platform=iOS" \
  archive
```

## Monitoring

### Key Metrics
- Token registration success rate
- Notification delivery success rate
- Average notification latency
- Invalid token cleanup rate

### Cloud Functions Dashboard
- Navigate to Firebase Console → Functions
- Monitor invocations, errors, and execution time
- Set up alerts for high error rates

## Security Considerations

1. **Token Storage**: Tokens stored in user-specific subcollection (UID-secured)
2. **Firestore Rules**: Ensure users can only write to their own tokens subcollection
3. **Sender Verification**: Cloud Functions run with admin privileges, trusted source
4. **Token Cleanup**: Remove tokens on logout or app uninstall

## Performance

- **Collection Group Query**: Efficient for small-medium communities (<10K users)
- **Multicast Send**: Batch sends to 500 tokens per call (automatically handled)
- **Cold Start**: First invocation may take 1-2 seconds, subsequent calls <500ms

## Implementation Date
November 6, 2025

## Contributors
- Mike W (Implementation)
- GitHub Copilot (Code generation)