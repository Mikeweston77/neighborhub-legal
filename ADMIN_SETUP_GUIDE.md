# Admin Setup Guide - NeighborHub

## Overview

NeighborHub uses a **two-tier role system**:
- **Admin**: Full permissions (approve users, delete content, manage all features)
- **Committee Member**: Elevated permissions (create newsletters, pin messages, manage emergency contacts)

Both roles are stored in Firebase Firestore as boolean fields on user documents.

---

## 🚀 Quick Start: Setting Up Your First Admin

### Step 1: Create Your Account
1. Launch the app
2. Tap **"Sign Up"** on the welcome screen
3. Complete all 7 onboarding steps
4. You'll see the "Pending Approval" screen

### Step 2: Grant Admin Access (Firebase Console)

Since no admins exist yet, you'll need to manually grant yourself admin privileges:

#### A. Open Firebase Console
1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Select your NeighborHub project
3. Click **Firestore Database** in the left sidebar

#### B. Find Your User Document
1. Click on the **`users`** collection
2. Find your document (document ID = your Firebase Auth UID)
3. You can identify it by your email field

#### C. Add Admin Fields
1. Click on your user document
2. Click **"Add field"** (or edit if upgrading existing user)
3. Add these fields:

   **Field 1: Admin Role**
   - Field name: `isAdmin`
   - Type: `boolean`
   - Value: `true`
   
   **Field 2: Verification**
   - Field name: `verified`
   - Type: `boolean`
   - Value: `true`
   
   **Field 3 (Optional): Committee Role**
   - Field name: `isCommittee`
   - Type: `boolean`
   - Value: `true`

4. Click **Save**

#### D. Verify Changes
1. Close and reopen the app (or wait ~5 seconds)
2. You should now see the main app interface
3. Go to **Watch** tab → tap Settings icon (profile circle)
4. You should see admin panels: "Pending Users", "Committee Members", etc.

---

## 👥 Approving New Users (Standard Workflow)

Once you're an admin, you can approve new registrations through the app:

### 1. Access Admin Panel
- Open app
- Go to **Watch** tab
- Tap the **profile circle icon** (top right)

### 2. View Pending Users
- Look for the **"Pending Users"** section
- Users awaiting approval have an 🟠 **orange clock badge**
- Expand to see: name, email, address, join date

### 3. Approve or Reject
- **Approve**: Tap the ✅ **green checkmark** button
  - Sets `verified: true` in Firestore
  - User immediately gains full access
  - Moves to "Approved Users" section
  
- **Reject**: Tap the 🟧 **orange X** button
  - Sets `rejected: true` in Firestore
  - User remains in pending state
  - Can be deleted if needed

### 4. Grant Admin/Committee Roles
To make an approved user an admin or committee member:

1. Open **Firebase Console** → **Firestore Database**
2. Navigate to: `users` → `{user's UID}`
3. Add field:
   - `isAdmin: true` (for full admin)
   - `isCommittee: true` (for committee member)
4. Save changes

---

## 🔑 Role Permissions Matrix

| Feature | Regular User | Committee Member | Admin |
|---------|-------------|------------------|-------|
| Read messages | ✅ (verified) | ✅ | ✅ |
| Post messages | ✅ (verified) | ✅ | ✅ |
| Create events | ✅ (verified) | ✅ | ✅ |
| Create newsletters | ❌ | ✅ | ✅ |
| Pin messages | ❌ | ✅ | ✅ |
| Manage emergency contacts | ❌ | ✅ | ✅ |
| Approve users | ❌ | ❌ | ✅ |
| Delete any content | ❌ | ❌ | ✅ |
| Update any user profile | ❌ | ❌ | ✅ |
| Delete users | ❌ | ❌ | ✅ |

---

## 📋 Admin Features Overview

### Watch Tab Admin Panel

**Access**: Watch tab → Profile icon (top right)

**Features Available**:

#### 1. Pending Users Section
- View all unverified registrations
- See user details: name, email, address, phone
- **Approve** button (sets `verified: true`)
- **Reject** button (sets `rejected: true`)
- **Delete** button (removes user completely)

#### 2. Approved Users Section
- View all verified community members
- Filter/search by name or address
- View full profiles with emergency contacts
- **Delete** button for each user

#### 3. Committee Members Section
- **LEGACY**: Will be removed in next update
- Currently uses name-based matching
- Being replaced with Firestore role system

#### 4. Camera Users Section
- Manage users with camera network access
- Grant/revoke camera system permissions

#### 5. Invitations & Approvals
- Send invitation links to new users
- Bulk approval tools (coming soon)

---

## 🛡️ Security Rules & Admin Powers

### Firestore Rules (Behind the Scenes)

The `isAdmin()` function in `firestore.rules` grants special permissions:

```javascript
function isAdmin() {
  return isSignedIn() && getUserData().isAdmin == true;
}
```

**Admin Overrides:**
- Can read **all** user profiles (even unverified)
- Can update **any** user document (assign roles, verification)
- Can delete **any** user
- Can update/delete **any** community message
- Can update/delete **any** marketplace listing
- Can update/delete **any** event
- Can update/delete **any** newsletter

---

## 🔧 Troubleshooting

### I can't see the admin panel
**Possible causes:**
1. **Not an admin**: Check Firestore → users → {your UID} → `isAdmin: true` exists
2. **Not verified**: Check `verified: true` in your document
3. **Cache issue**: Close app completely and reopen
4. **Name mismatch (legacy)**: Temporarily, check if your name is in committeeMembers AppStorage

**Solution:**
- Use Firebase Console to verify your user document has both:
  - `isAdmin: true`
  - `verified: true`

### Users I approve still can't access features
**Check:**
1. Firebase Console → Authentication → verify user has account
2. Firestore → users → {their UID} → `verified: true`
3. Ask user to close and reopen app (forces refresh)

### I accidentally deleted an admin
**Recovery:**
1. If you have another admin account, log in and create a new admin
2. If no admins left, follow "Setting Up Your First Admin" steps above
3. Use Firebase Console to manually add `isAdmin: true` to a user document

### Changes not taking effect
**Try:**
1. **Force logout/login**: Settings → Sign Out → Sign In
2. **Clear app data**: Delete app → Reinstall → Login
3. **Check Firestore**: Verify fields updated successfully
4. **Check rules**: Ensure `firestore.rules` deployed correctly

---

## 🎓 Best Practices

### Admin Account Security
- ✅ Use strong passwords (12+ characters)
- ✅ Enable two-factor authentication (Firebase Console)
- ✅ Don't share admin credentials
- ✅ Create separate admin accounts per person
- ✅ Revoke admin access when someone leaves committee

### User Approval Workflow
- ✅ Verify user's address matches neighborhood boundaries
- ✅ Check profile looks legitimate (photo, real name)
- ✅ Use reject for suspicious accounts
- ✅ Delete spam/fake accounts immediately
- ✅ Monitor community for inappropriate content

### Role Assignment
- ✅ Only grant `isAdmin` to trusted committee members
- ✅ Use `isCommittee` for newsletter authors, event organizers
- ✅ Review roles quarterly
- ✅ Document role changes for accountability

---

## 📞 Support & Next Steps

### Need Help?
- Check `FIREBASE_AUTH_TESTING_CHECKLIST.md` for testing procedures
- See `SECURITY_RULES_AUDIT.md` for security documentation
- Review `FIREBASE_AUTH_DEPLOYMENT_GUIDE.md` for deployment details

### Planned Improvements
- [ ] In-app admin invitation system (no Firebase Console needed)
- [ ] Admin activity logs
- [ ] Bulk user approval tools
- [ ] Role management UI in app
- [ ] Emergency admin override codes

---

## 🔄 Migration: Old → New Admin System

### Before (Legacy - Being Removed)
- Admins identified by name in `committeeMembers` AppStorage string
- Format: `"Mike W, Brendan B, Janine B"`
- Required exact name match against userName + userSurname
- Local only, not synced across devices

### After (Current - UID-Based)
- Admins identified by `isAdmin: true` in Firestore user document
- Based on unique Firebase Auth UID
- Synced across all devices
- Secure and verifiable via Firebase rules

### No Action Needed
The migration is handled automatically by the app. Your existing admin access will continue to work.

---

## ⚠️ Important Notes

### UID vs Email
- **Old system**: Used email as document ID
- **New system**: Uses Firebase Auth UID as document ID
- Some code still references email for backward compatibility
- Full UID migration coming in next update

### First Admin Bootstrap Problem
- Someone must manually create the first admin via Firebase Console
- After first admin exists, they can approve others through the app
- This is a security feature to prevent unauthorized admin access

### Admin Accountability
- All admin actions are logged with timestamps in Firestore
- `approvedAt`, `updatedAt` fields track changes
- Consider implementing admin activity logs for full audit trail

---

**Last Updated**: November 1, 2025  
**Version**: 1.0 (UID-based system)  
**App Version**: NeighborHub v1.04
