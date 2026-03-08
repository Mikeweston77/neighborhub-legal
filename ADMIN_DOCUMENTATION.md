# NeighborHub - Admin Documentation

## Table of Contents
1. [Admin Panel Access](#admin-panel-access)
2. [User Management](#user-management)
3. [Content Moderation](#content-moderation)
4. [Emergency Settings](#emergency-settings)
5. [System Monitoring](#system-monitoring)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

---

## Admin Panel Access

### Becoming an Admin
1. Navigate to the **Home** tab
2. Tap on your profile/settings
3. Access the **Admin Panel** (visible only to admin users)

### Admin Capabilities
- User verification and role management
- Emergency number configuration
- Pinned notifications management
- Content moderation and deletion
- System-wide settings configuration

---

## User Management

### User Verification Process

**Purpose**: Ensure only legitimate neighborhood residents access the community features.

**Steps**:
1. Go to **Admin Panel** → **User Management**
2. View **Pending Approvals** list
3. Review user details:
   - Name
   - Email
   - Address (if provided)
   - Registration date
4. **Verify** or **Reject** the user
   - ✅ Verified users gain full access to all community features
   - ❌ Rejected users remain in pending state or can be deleted

**Firebase Path**: `users/{userId}`
- Field: `verified: true/false`
- Field: `isAdmin: true/false`
- Field: `isCommittee: true/false`

### Role Assignment

**Admin Role**:
- Full system access
- Can verify users
- Can modify emergency settings
- Can delete any content
- Can assign/revoke committee roles

**Committee Role**:
- Can moderate content
- Can create official announcements
- Can manage events
- **Cannot** verify users or modify emergency settings

**To Assign Roles**:
1. Admin Panel → User Management
2. Select user
3. Toggle "Make Admin" or "Make Committee Member"
4. Changes sync immediately to Firestore

**Firebase Update**:
```javascript
// In Firestore Console or via Cloud Functions
db.collection('users').doc(userId).update({
  isAdmin: true,  // or false
  isCommittee: true  // or false
});
```

### User Deletion
- Admins can delete user accounts
- Deletes user document from Firestore
- **Does NOT** delete Firebase Auth account (must be done in Firebase Console)
- User's content (messages, posts) remains but shows "[Deleted User]"

---

## Content Moderation

### Report It Tab - Incident Management

**Viewing Incidents**:
- All verified users can see incident reports
- Admins can delete inappropriate incidents

**Deleting Incidents**:
1. Open incident card
2. Tap delete icon (admin only)
3. Confirm deletion
4. Incident removed from Firestore

**Firebase Path**: `incidents/{incidentId}`

### Community Chat Moderation

**Message Types**:
- Text messages
- Images/Videos
- Files
- Business cards
- Voice messages
- Announcements (admin/committee only)

**Moderating Messages**:
1. Open Community Chat
2. Long-press on message (admin only)
3. Select "Delete Message"
4. Message removed for all users

**Firebase Path**: `communityMessages/{messageId}`

**Cloud Functions**:
- Auto-moderation runs on image uploads
- Flags inappropriate content
- Quarantines flagged files to `/quarantine/` in Storage

### Marketplace Moderation

**Listing Review**:
- Monitor new marketplace listings
- Delete spam or inappropriate listings
- Contact users via chat if needed

**Firebase Path**: `marketplace/{listingId}`

### Newsletter Moderation

**Viewing Submissions**:
- Admin Panel → Newsletters
- Review pending submissions
- Approve or reject content

**Firebase Path**: `newsletterSubmissions/{submissionId}`

---

## Emergency Settings

### Configuring Emergency Numbers

**Access**: Admin Panel → Emergency Settings

**Three Number Types**:
1. **Fire Department**
2. **Emergency Services** (Police)
3. **Medical/Ambulance**

**Default**: All default to "911"

**To Update**:
1. Tap on number type
2. Enter new number (e.g., non-emergency line, local dispatch)
3. Tap "Update"
4. Changes sync immediately to all users

**Firebase Path**: `emergencySettings/global`
```json
{
  "fireNumber": "911",
  "emergencyNumber": "911",
  "medicalNumber": "911",
  "updatedBy": "Admin Name",
  "updatedAt": "timestamp"
}
```

**Real-time Sync**:
- All users see updated numbers instantly
- Appears on Home tab emergency contact cards
- Used in Emergency Contacts list

### Pinned Notifications

**Purpose**: Display important community-wide announcements

**Creating Pinned Notifications**:
1. Admin Panel → Pinned Notifications
2. Tap "Add Pinned Notification"
3. Enter:
   - Title (e.g., "Community Meeting")
   - Message (detailed information)
   - Priority: High/Medium/Low
4. Tap "Post"

**Display**:
- Shows as banner on Home tab for all verified users
- Color-coded by priority:
  - 🔴 High: Red
  - 🟠 Medium: Orange
  - 🟢 Low: Blue

**Dismissing**:
- Users can dismiss (hides for them)
- Admins can delete permanently

**Firebase Path**: `pinnedNotifications/{notificationId}`

---

## System Monitoring

### Firebase Console Access

**Access Required**:
- Firebase project: [Your Firebase Project Name]
- Role: Editor or Owner

**Key Areas to Monitor**:

1. **Firestore Database**:
   - Monitor document counts
   - Check for unusual activity
   - Review security rules compliance

2. **Storage**:
   - Monitor storage usage
   - Review `/quarantine/` for flagged content
   - Clean up old uploads if needed

3. **Authentication**:
   - View registered users
   - Disable compromised accounts
   - Review sign-in methods

4. **Cloud Functions**:
   - Check function execution logs
   - Monitor errors
   - Review image processing status

5. **Analytics** (if enabled):
   - User engagement metrics
   - Feature usage statistics
   - Screen view tracking

6. **Crashlytics** (if enabled):
   - App crash reports
   - Error tracking
   - User feedback

### Usage Metrics to Track

**Daily Active Users (DAU)**:
- Check Firebase Analytics dashboard

**Top Features**:
- Community Chat message count
- Incident reports created
- Events created
- Marketplace listings

**Storage Usage**:
- Images: `/uploads/`, `/final/`, `/thumbs/`
- Videos: Can be large, monitor size
- Quarantined content: Review and delete periodically

---

## Best Practices

### User Verification
✅ **DO**:
- Verify users within 24-48 hours
- Request proof of residency if uncertain
- Communicate verification status via email

❌ **DON'T**:
- Verify users without confirming neighborhood residency
- Share user information publicly
- Reject without explanation

### Content Moderation
✅ **DO**:
- Review flagged content within 24 hours
- Provide warnings before deleting content
- Document moderation decisions
- Be consistent with community guidelines

❌ **DON'T**:
- Delete content without review
- Engage in arguments with users
- Show favoritism

### Emergency Settings
✅ **DO**:
- Test emergency numbers before updating
- Announce changes via pinned notification
- Coordinate with local authorities
- Keep records of changes

❌ **DON'T**:
- Update numbers without verification
- Change numbers without announcement
- Use personal phone numbers

### System Security
✅ **DO**:
- Regularly review Firebase security rules
- Monitor for suspicious activity
- Keep Firebase SDK updated
- Review admin access quarterly
- Enable two-factor authentication

❌ **DON'T**:
- Share admin credentials
- Disable security rules
- Grant admin access casually
- Ignore security alerts

---

## Troubleshooting

### Common Issues

#### Users Can't See Content
**Possible Causes**:
- User not verified
- Firestore rules blocking access
- User's device offline

**Solution**:
1. Check user's `verified` status in Firestore
2. Have user log out and log back in
3. Check Firestore rules in Firebase Console

#### Emergency Numbers Not Updating
**Possible Causes**:
- User's app version outdated
- Firestore listener not attached
- Network connectivity issue

**Solution**:
1. Verify `emergencySettings/global` document exists
2. Check Firestore rules allow read access
3. Have user force-close and reopen app

#### Messages Not Sending
**Possible Causes**:
- Firestore write permissions issue
- User not verified
- Network offline

**Solution**:
1. Check user's verified status
2. Review Firestore security rules
3. Check Cloud Functions logs for errors

#### Images Not Uploading
**Possible Causes**:
- Storage rules blocking upload
- File size too large (>200MB)
- Cloud Functions not processing

**Solution**:
1. Check Storage rules in Firebase Console
2. Review Cloud Functions logs (`functions/index.js`)
3. Check Storage bucket permissions

#### Crashes or Errors
**Check**:
1. Firebase Crashlytics dashboard
2. Firebase Functions logs
3. Xcode console output
4. User reports

**Steps**:
1. Identify crash pattern (specific feature/screen)
2. Review error logs
3. Test on device matching user's configuration
4. Deploy hotfix via App Store

---

## Support Contacts

### Firebase Issues
- Firebase Console: https://console.firebase.google.com
- Firebase Support: https://firebase.google.com/support

### App Development
- Contact: [Your contact information]
- Email: [Your support email]

### Community Guidelines
- Create a "Community Guidelines" document
- Share in app and via website
- Reference in Terms of Service

---

## Quick Reference Commands

### Firebase Deployment
```bash
# Deploy all Firebase resources
firebase deploy

# Deploy only Firestore rules
firebase deploy --only firestore:rules

# Deploy only Storage rules  
firebase deploy --only storage

# Deploy only Cloud Functions
firebase deploy --only functions
```

### Firestore Quick Queries (Firebase Console)
```javascript
// Find all admins
db.collection('users').where('isAdmin', '==', true).get()

// Find unverified users
db.collection('users').where('verified', '==', false).get()

// Count incidents
db.collection('incidents').get().then(snap => snap.size)

// Recent chat messages (last 50)
db.collection('communityMessages')
  .orderBy('timestamp', 'desc')
  .limit(50)
  .get()
```

### User Management Shortcuts
- **Verify user**: Set `verified: true` in user document
- **Make admin**: Set `isAdmin: true` in user document  
- **Make committee**: Set `isCommittee: true` in user document
- **Revoke access**: Set `verified: false` (user can't access features)

---

## Version History

**Version 1.0** (Current)
- Initial release
- Core features: Chat, Events, Marketplace, Report It
- Emergency settings management
- User verification system
- Firebase integration

---

*Last Updated: December 26, 2025*
*Document Maintained By: Admin Team*
