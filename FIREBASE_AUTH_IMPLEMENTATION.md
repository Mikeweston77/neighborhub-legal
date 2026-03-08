# Firebase Authentication Implementation

## Overview
This document outlines the implementation of Firebase Authentication in NeighborHub, replacing the previous AppStorage-only approach with proper Firebase Auth integration.

## Key Changes

### 1. Authentication Architecture

**Previous Approach:**
- Used email as document ID in Firestore (`users/{email}`)
- No Firebase Authentication
- AppStorage for local user state
- Permissive security rules (allowed all authenticated requests)

**New Approach:**
- Firebase Authentication with email/password
- Use Firebase Auth UID as document ID (`users/{uid}`)
- AppStorage still used for local caching
- Strict security rules based on authenticated user and verification status

### 2. Benefits of Using Firebase Auth UID

#### ✅ Advantages:
1. **Immutable Identifier**: UID never changes, even if user updates email
2. **Better Security**: Built-in authentication tokens with JWT
3. **No Email Migration**: Users can change email without data migration
4. **Industry Standard**: Best practice for user identification
5. **Better Privacy**: Email not exposed in URLs or document paths
6. **Firebase Integration**: Works seamlessly with other Firebase services

#### ⚠️ Email as Document ID Issues:
1. **Cannot Change Email**: Changing email requires complex data migration
2. **Exposed PII**: Email visible in Firestore paths and logs
3. **Security Concerns**: Email in URLs can be cached/logged
4. **No Real Auth**: AppStorage alone doesn't provide server-side verification

### 3. Implementation Details

#### FirebaseManager Updates

**New Authentication Methods:**
```swift
// Get current authenticated user
func getCurrentUser() -> User?

// Get current user's UID
func getCurrentUserUID() -> String?

// Sign in with email/password
func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void)

// Create new user account
func createUser(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void)

// Sign out
func signOut() throws

// Send password reset email
func sendPasswordReset(email: String, completion: @escaping (Result<Void, Error>) -> Void)

// Create user profile with Auth UID
func createOrUpdateUserWithAuth(
    firstName: String,
    lastName: String,
    email: String,
    // ... other profile fields
    completion: @escaping (Result<String, Error>) -> Void
)
```

#### Firestore Rules Updates

**Helper Functions:**
```javascript
// Check if user is authenticated with Firebase Auth
function isSignedIn() {
  return request.auth != null;
}

// Get current user's document
function getUserData() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
}

// Check if user is verified by admin
function isVerified() {
  return isSignedIn() && getUserData().verified == true;
}

// Check if user owns the document
function isOwner(userId) {
  return isSignedIn() && request.auth.uid == userId;
}
```

**Key Security Improvements:**
- ✅ Only authenticated users can access data
- ✅ Only verified users can post content (after admin approval)
- ✅ Users can only modify their own content
- ✅ Admins can moderate any content
- ✅ Document ownership verified via Firebase Auth UID

### 4. Updated Workflow

#### User Registration Flow:
1. **UI**: User fills out onboarding form (6 steps)
2. **Create Auth Account**: Call `FirebaseManager.shared.createUser(email, password)`
3. **Get UID**: Extract `user.uid` from successful auth result
4. **Create Profile**: Call `createOrUpdateUserWithAuth()` with user details
5. **Store Locally**: Save user info in AppStorage for quick access
6. **Admin Approval**: User marked as `verified: false` until admin approves
7. **Limited Access**: Unverified users can read but not post content

#### User Login Flow:
1. **UI**: User enters email/password
2. **Sign In**: Call `FirebaseManager.shared.signIn(email, password)`
3. **Fetch Profile**: Get user document from `users/{uid}` using returned UID
4. **Check Verification**: Check `verified` field in user document
5. **Store Locally**: Update AppStorage with user info
6. **Full Access**: Verified users can post and interact fully

#### Admin Approval Flow:
1. **Admin Panel**: Shows pending users where `verified: false`
2. **Approve**: Admin taps approve button
3. **Update Firestore**: Sets `verified: true, approvedAt: timestamp`
4. **Real-time Update**: User's app receives Firestore update via listener
5. **Access Granted**: User can now post messages, create events, etc.

### 5. Migration Strategy

#### For Existing Users (with email-based documents):

**Option A: Gradual Migration (Recommended)**
1. Keep both systems running temporarily
2. On next login, create Firebase Auth account
3. Migrate user data from `users/{email}` to `users/{uid}`
4. Add email-to-uid mapping in Firestore
5. Update all references (messages, events, etc.)
6. Archive old email-based document

**Option B: One-Time Migration Script**
1. Export all users from `users/{email}` collection
2. Create Firebase Auth accounts for each user
3. Create new documents at `users/{uid}`
4. Update all foreign key references
5. Delete old email-based documents

**Option C: Fresh Start (Current Approach)**
- Since app is in development, simplest approach
- All new users use Firebase Auth from registration
- Legacy email-based data remains read-only (if any)

### 6. Code Changes Required

#### High Priority:
1. ✅ **FirebaseManager.swift**: Added auth methods (DONE)
2. ✅ **firestore.rules**: Updated security rules (DONE)
3. ⏳ **OnboardingView.swift**: Add password field and auth creation
4. ⏳ **LoginView.swift**: Update to use Firebase Auth sign-in
5. ⏳ **HomeView.swift**: Update registerUser to use auth UID
6. ⏳ **ContentView.swift**: Add auth state listener

#### Medium Priority:
7. **WatchView.swift**: Update user lookup to use UID
8. **ChatMessagesManager.swift**: Store userId (UID) instead of email
9. **EventsCard.swift**: Store creatorId (UID) instead of email
10. **MarketplaceCard.swift**: Store sellerId (UID) instead of email

#### Low Priority:
11. **Settings**: Add change email functionality
12. **Password Reset**: Add forgot password flow
13. **Email Verification**: Add email verification step
14. **Re-authentication**: For sensitive operations

### 7. Security Checklist

- [x] Enable Firebase Authentication in project
- [x] Update Firestore rules to require authentication
- [x] Update Firestore rules to check user verification status
- [x] Add `isVerified()` helper function to rules
- [x] Ensure document ownership checked via UID
- [x] Storage rules already use proper authentication
- [ ] Add rate limiting for auth operations
- [ ] Enable reCAPTCHA for web (if applicable)
- [ ] Set up proper error handling for auth failures
- [ ] Add session management (token refresh)

### 8. Testing Checklist

#### Registration Tests:
- [ ] New user can create account with email/password
- [ ] User profile created at `users/{uid}` (not `users/{email}`)
- [ ] User marked as `verified: false` initially
- [ ] Profile photo uploaded to correct Storage path
- [ ] User sees "pending approval" message after registration

#### Login Tests:
- [ ] Existing user can sign in with correct credentials
- [ ] Wrong password shows appropriate error
- [ ] Unverified user has limited access (read-only)
- [ ] Verified user has full access (can post)

#### Admin Tests:
- [ ] Admin can see pending users
- [ ] Admin can approve users (sets `verified: true`)
- [ ] Approved users immediately get full access
- [ ] Admin can reject users

#### Security Tests:
- [ ] Unauthenticated users cannot read Firestore data
- [ ] Users cannot modify other users' documents
- [ ] Unverified users cannot create messages/events
- [ ] Admins can moderate all content

### 9. Firebase Console Configuration

#### Enable Authentication:
1. Go to Firebase Console > Authentication
2. Click "Get Started"
3. Enable "Email/Password" provider
4. Configure email verification (optional but recommended)
5. Set up password requirements (min 6 characters by default)

#### Deploy Updated Rules:
```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules (already good)
firebase deploy --only storage:rules
```

#### Monitor Authentication:
1. Firebase Console > Authentication > Users
2. View sign-in methods and user accounts
3. Monitor authentication logs
4. Set up alerts for suspicious activity

### 10. Best Practices

#### Password Requirements:
- Minimum 8 characters (configure in Firebase Console)
- Require uppercase, lowercase, numbers, symbols
- Implement password strength indicator in UI
- Add password confirmation field

#### Security:
- Never store passwords in AppStorage
- Use secure keychain for sensitive data
- Implement proper logout (clear local data)
- Add session timeout for inactive users
- Implement 2FA (optional future enhancement)

#### Error Handling:
- Handle network failures gracefully
- Show user-friendly error messages
- Log auth errors for debugging
- Implement retry logic for failed operations

#### UX Considerations:
- Remember email (not password) for convenience
- Add "Stay signed in" option
- Implement biometric authentication (Face ID/Touch ID)
- Show loading states during auth operations
- Provide clear feedback on auth errors

## Summary

This implementation provides a robust, secure, and scalable authentication system using Firebase Auth UIDs as the primary user identifier. The key improvement is decoupling user identity (UID) from changeable user attributes (email), allowing users to update their email without complex data migrations.

**Status**: 
- ✅ Backend infrastructure ready (FirebaseManager + Rules)
- ⏳ Frontend UI updates needed (OnboardingView, LoginView, etc.)
- ⏳ Testing and validation required

**Next Steps**:
1. Update OnboardingView to create Firebase Auth account
2. Update LoginView to use Firebase sign-in
3. Add password fields to both flows
4. Test complete registration → approval → access workflow
5. Deploy updated Firestore rules to Firebase
