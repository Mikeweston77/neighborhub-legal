# Firebase Authentication - Visual Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         NeighborHub iOS App                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
│  │ OnboardingView│  │  LoginView   │  │   HomeView   │            │
│  │              │  │              │  │              │            │
│  │ - Email      │  │ - Email      │  │ - User Info  │            │
│  │ - Password   │  │ - Password   │  │ - Profile    │            │
│  │ - Profile    │  │ - Sign In    │  │ - Content    │            │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘            │
│         │                 │                 │                      │
│         └─────────────────┼─────────────────┘                      │
│                          │                                         │
│                  ┌───────▼────────┐                                │
│                  │ FirebaseManager │                                │
│                  │                │                                │
│                  │ Auth Methods:  │                                │
│                  │ - createUser() │                                │
│                  │ - signIn()     │                                │
│                  │ - signOut()    │                                │
│                  │ - getCurrentUID()                               │
│                  └───────┬────────┘                                │
│                          │                                         │
└──────────────────────────┼─────────────────────────────────────────┘
                           │
                           │ HTTPS + JWT Token
                           │
          ┌────────────────▼────────────────┐
          │      Firebase Services          │
          ├─────────────────────────────────┤
          │                                 │
          │  ┌─────────────────────────┐   │
          │  │  Firebase Authentication│   │
          │  │                         │   │
          │  │  - Email/Password       │   │
          │  │  - JWT Token Generation │   │
          │  │  - Session Management   │   │
          │  │  - Password Reset       │   │
          │  └───────────┬─────────────┘   │
          │              │                  │
          │              │ request.auth.uid │
          │              │ request.auth.token
          │              │                  │
          │  ┌───────────▼─────────────┐   │
          │  │   Firestore Database    │   │
          │  │                         │   │
          │  │  users/{uid}/           │   │
          │  │    - firstName          │   │
          │  │    - lastName           │   │
          │  │    - email              │   │
          │  │    - verified: bool     │   │
          │  │    - isAdmin: bool      │   │
          │  │    - profileImageURL    │   │
          │  │                         │   │
          │  │  communityMessages/     │   │
          │  │    - userId (uid)       │   │
          │  │    - content            │   │
          │  │    - timestamp          │   │
          │  │                         │   │
          │  │  events/                │   │
          │  │    - creatorId (uid)    │   │
          │  │    - title              │   │
          │  │    - date               │   │
          │  └─────────────────────────┘   │
          │                                 │
          │  ┌─────────────────────────┐   │
          │  │   Firebase Storage      │   │
          │  │                         │   │
          │  │  users/{uid}/profile/   │   │
          │  │    - avatar.jpg         │   │
          │  │                         │   │
          │  │  uploads/{uid}/...      │   │
          │  │    - communityMessages/ │   │
          │  │    - events/            │   │
          │  │    - incidents/         │   │
          │  └─────────────────────────┘   │
          │                                 │
          │  ┌─────────────────────────┐   │
          │  │   Security Rules        │   │
          │  │                         │   │
          │  │  Firestore Rules:       │   │
          │  │  - isSignedIn()         │   │
          │  │  - isVerified()         │   │
          │  │  - isAdmin()            │   │
          │  │  - isOwner(uid)         │   │
          │  │                         │   │
          │  │  Storage Rules:         │   │
          │  │  - auth.uid == userId   │   │
          │  │  - size limits          │   │
          │  └─────────────────────────┘   │
          │                                 │
          └─────────────────────────────────┘
```

---

## Authentication Flow

### User Registration Flow

```
┌──────────────┐
│  User opens  │
│     app      │
└──────┬───────┘
       │
       ▼
┌──────────────────────────┐
│  OnboardingView shows    │
│  6-step registration     │
└──────┬───────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│  Step 1: Welcome                    │
│  Step 2: Personal Info (email)      │
│  Step 3: Location                   │
│  Step 4: Emergency Contact          │
│  Step 5: Profile Photo              │
│  Step 6: Privacy + Password ⭐ NEW  │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│ FirebaseManager.createUser()    │
│ - Creates Auth account          │
│ - Returns user.uid              │
└──────┬──────────────────────────┘
       │
       ▼ Success
┌──────────────────────────────────────────┐
│ FirebaseManager.createOrUpdateUserWithAuth()
│ - Creates Firestore doc at users/{uid}  │
│ - Sets verified: false                  │
│ - Stores profile data                   │
└──────┬───────────────────────────────────┘
       │
       ▼
┌────────────────────────────┐
│ Upload profile photo       │
│ to users/{uid}/profile/    │
└──────┬─────────────────────┘
       │
       ▼
┌────────────────────────────┐
│ Store UID in AppStorage    │
│ for local caching          │
└──────┬─────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│ Show "Pending Approval" message  │
│ User has read-only access        │
└──────────────────────────────────┘
```

---

### User Login Flow

```
┌──────────────┐
│ User enters  │
│ credentials  │
└──────┬───────┘
       │
       ▼
┌─────────────────────────────────┐
│ FirebaseManager.signIn()        │
│ - Validates email/password      │
│ - Returns user.uid              │
└──────┬──────────────────────────┘
       │
       ▼ Success
┌────────────────────────────────────┐
│ Fetch user profile from Firestore │
│ db.collection("users")            │
│   .document(user.uid)             │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────┐
│ Check verified field           │
└──────┬─────────────────────────┘
       │
       ├─────────► verified: false
       │           │
       │           ▼
       │    ┌──────────────────────┐
       │    │ Limited read-only    │
       │    │ access granted       │
       │    └──────────────────────┘
       │
       └─────────► verified: true
                   │
                   ▼
            ┌──────────────────────┐
            │ Full access granted  │
            │ Can post content     │
            └──────────────────────┘
```

---

### Admin Approval Flow

```
┌──────────────────────┐
│ New user registers   │
│ verified: false      │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────────────────┐
│ Admin opens Watch > Settings     │
│ Sees "Pending Users" section     │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ Admin sees user with:        │
│ - Name                       │
│ - Email                      │
│ - Join date                  │
│ - 🟠 Orange clock badge      │
└──────┬───────────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ Admin taps "Approve" button  │
└──────┬───────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│ FirebaseManager.approveUser()       │
│ - Updates verified: true            │
│ - Sets approvedAt timestamp         │
└──────┬──────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ Firestore real-time listener       │
│ updates user's app automatically   │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────┐
│ User moves to "Approved Users" │
│ section with ✅ green badge    │
└──────┬─────────────────────────┘
       │
       ▼
┌────────────────────────────────┐
│ User's app receives update     │
│ Full access granted            │
│ Can now post content           │
└────────────────────────────────┘
```

---

## Security Rules Flow

### Firestore Access Control

```
┌──────────────────┐
│ Client Request   │
│ (read/write)     │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────┐
│ 1. Is user authenticated?   │
│    request.auth != null     │
└────────┬────────────────────┘
         │
         ├──► NO ──► ❌ DENY
         │
         ▼ YES
┌──────────────────────────────────┐
│ 2. Does operation match pattern? │
│    users/{uid}, messages/{id}    │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│ 3. Check specific rules:     │
│                              │
│ For READ:                    │
│ - Is user verified?          │
│ - Is user admin?             │
│ - Is document public?        │
│                              │
│ For CREATE:                  │
│ - Is user verified?          │
│ - Does userId match auth.uid?│
│ - Are required fields set?   │
│                              │
│ For UPDATE:                  │
│ - Is user owner OR admin?    │
│ - Are protected fields       │
│   unchanged (uid, email)?    │
│                              │
│ For DELETE:                  │
│ - Is user owner OR admin?    │
└────────┬─────────────────────┘
         │
         ├──► Rules pass ──► ✅ ALLOW
         │
         └──► Rules fail ──► ❌ DENY
```

---

## Data Model Comparison

### Before (Email-based) ❌

```
Firestore:
  users/
    user@example.com/          ← Email as document ID
      email: "user@example.com"
      name: "John Doe"
      verified: false

  communityMessages/
    messageId/
      userId: "user@example.com"  ← Email as foreign key
      content: "Hello!"

Storage:
  profiles/
    user_example_com/          ← Email-based path
      avatar.jpg
```

**Problems:**
- ❌ Email exposed in URLs and paths (PII)
- ❌ Cannot change email without migration
- ❌ Email in foreign keys requires updates
- ❌ No real authentication validation

---

### After (UID-based) ✅

```
Firestore:
  users/
    abc123def456/              ← Firebase Auth UID
      uid: "abc123def456"
      email: "user@example.com"
      name: "John Doe"
      verified: false

  communityMessages/
    messageId/
      userId: "abc123def456"   ← UID as foreign key
      content: "Hello!"

Storage:
  users/
    abc123def456/              ← UID-based path
      profile/
        avatar.jpg
```

**Benefits:**
- ✅ Email can be changed (just update field)
- ✅ UID is immutable and secure
- ✅ No PII in document paths
- ✅ Proper JWT token validation
- ✅ Foreign keys remain valid if email changes

---

## Permission Matrix

### Firestore Collections

| Collection | Unauth | Unverified User | Verified User | Committee | Admin |
|------------|--------|-----------------|---------------|-----------|-------|
| **users** |
| - Read all | ❌ | ❌ | Own + verified | All | ✅ All |
| - Create | ❌ | Own only | Own only | Own only | ✅ Any |
| - Update | ❌ | Own only | Own only | Own only | ✅ Any |
| - Delete | ❌ | ❌ | ❌ | ❌ | ✅ Any |
| **communityMessages** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Create | ❌ | ❌ | ✅ | ✅ | ✅ |
| - Update | ❌ | ❌ | Own only | Own only | ✅ Any |
| - Delete | ❌ | ❌ | Own only | Own only | ✅ Any |
| **pinnedMessages** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Create | ❌ | ❌ | ❌ | ✅ | ✅ |
| - Delete | ❌ | ❌ | ❌ | ✅ | ✅ |
| **events** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Create | ❌ | ❌ | ✅ | ✅ | ✅ |
| - Update | ❌ | ❌ | Own only | Own only | ✅ Any |
| - Delete | ❌ | ❌ | Own only | Own only | ✅ Any |
| **newsletters** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Create | ❌ | ❌ | ❌ | ✅ | ✅ |
| - Update | ❌ | ❌ | ❌ | ❌ | ✅ |
| - Delete | ❌ | ❌ | ❌ | ❌ | ✅ |
| **marketplace** |
| - Read | ✅ Public | ✅ Public | ✅ Public | ✅ Public | ✅ |
| - Create | ❌ | ❌ | ✅ | ✅ | ✅ |
| - Update | ❌ | ❌ | Own only | Own only | ✅ Any |
| - Delete | ❌ | ❌ | Own only | Own only | ✅ Any |

### Firebase Storage

| Path | Unauth | Unverified | Verified | Owner | Admin |
|------|--------|------------|----------|-------|-------|
| **users/{uid}/profile/** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Write | ❌ | ❌ | ❌ | ✅ Own | ✅ Own |
| **uploads/{uid}/** |
| - Read | ❌ | ✅ | ✅ | ✅ | ✅ |
| - Write | ❌ | ❌ | ❌ | ✅ Own | ✅ Own |
| **marketplace/** |
| - Read | ✅ Public | ✅ | ✅ | ✅ | ✅ |
| - Write | ❌ | ❌ | ✅ | ✅ | ✅ |
| **final/** (processed) |
| - Read | Varies | ✅ | ✅ | ✅ | ✅ |
| - Write | ❌ | ❌ | ❌ | ❌ | ❌ CF only |

---

## Implementation Checklist

### ✅ Completed (Backend)

- [x] Add Firebase Auth methods to FirebaseManager
- [x] Create `getCurrentUser()` method
- [x] Create `getCurrentUserUID()` method
- [x] Create `signIn()` method
- [x] Create `createUser()` method
- [x] Create `signOut()` method
- [x] Create `sendPasswordReset()` method
- [x] Create `createOrUpdateUserWithAuth()` method
- [x] Update Firestore rules to require authentication
- [x] Update Firestore rules to check verification
- [x] Add isVerified() helper function
- [x] Add owner validation to all collections
- [x] Update user document rules for UID-based IDs
- [x] Verify Storage rules are secure
- [x] Create comprehensive documentation
- [x] Create deployment script
- [x] Create security audit report

### ⏳ Pending (Frontend)

- [ ] Enable Firebase Auth in Firebase Console
- [ ] Deploy updated Firestore rules
- [ ] Add password field to OnboardingView
- [ ] Add password confirmation field
- [ ] Add password strength indicator
- [ ] Update OnboardingView submit to create Auth account
- [ ] Update LoginView to use Firebase sign-in
- [ ] Update HomeView to use Auth UID
- [ ] Add auth state listener to ContentView/App
- [ ] Update all userId references to use UID
- [ ] Test registration flow end-to-end
- [ ] Test login flow
- [ ] Test admin approval workflow
- [ ] Test password reset
- [ ] Deploy to TestFlight/App Store

---

## Quick Commands

### Deploy Rules:
```bash
./deploy_firebase_rules.sh
```

### Validate Rules:
```bash
firebase firestore:rules:validate firestore.rules
```

### View Deployment History:
```bash
firebase firestore:rules:list
```

### Test Rules Locally:
```bash
firebase emulators:start --only firestore
```

---

## Key Files

| File | Purpose | Status |
|------|---------|--------|
| `FirebaseManager.swift` | Auth methods | ✅ Complete |
| `firestore.rules` | Security rules | ✅ Complete |
| `firebase-storage.rules` | Storage security | ✅ Already good |
| `OnboardingView.swift` | Registration UI | ⏳ Needs password |
| `LoginView.swift` | Sign-in UI | ⏳ Needs Firebase Auth |
| `HomeView.swift` | User creation | ⏳ Needs UID usage |
| `ContentView.swift` | Auth state | ⏳ Needs listener |

---

**Created:** November 1, 2025  
**Last Updated:** November 1, 2025  
**Status:** Backend Ready, Frontend Updates Needed
