# Camera Access Request System - Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CAMERA ACCESS REQUEST FLOW                          │
└─────────────────────────────────────────────────────────────────────────────┘


USER SIDE                                    FIRESTORE                    ADMIN SIDE
═══════════                                 ═══════════                   ══════════


Step 1: Enter Credentials
──────────────────────────

┌──────────────────┐
│  Home Settings   │
│  NeighbourHUB    │
│      Watch       │
│                  │
│ Username: [____] │                      users/{uid}/
│ Password: [____] │────────────────►   cameraAccessRequested: true
│                  │                    cameraAccessRequestedAt: now
│ ✅ Request sent  │                    watchCredential: "username"
└──────────────────┘


Step 2: Admin Notification
────────────────────────────

                                           FIRESTORE LISTENER
                                                  │
                                                  │ Real-time sync
                                                  ▼
                                        ┌───────────────────────┐
                                        │ Pending Camera        │
                                        │ Requests (3)  ⚠️      │
                                        │                       │
                                        │ ┌─────────────────┐   │
                                        │ │ Mike Wilson     │   │
                                        │ │ Watch: MikeW    │   │
                                        │ │ [Approve][Reject]   │
                                        │ └─────────────────┘   │
                                        └───────────────────────┘


Step 3: Admin Action
──────────────────────

                                        Admin clicks "Approve"
                                                  │
                                                  ▼
                                        users/{uid}/
                                        cameraAccess: true ✅
                                        cameraAccessRequested: false
                                        cameraAccessGrantedBy: {adminUID}
                                        cameraAccessUpdatedAt: now
                                                  │
                                                  │ Real-time sync
                                                  ▼

┌──────────────────┐                    FIRESTORE LISTENER
│  Watch Tab       │                            │
│                  │◄───────────────────────────┘
│  [Camera Portal] │
│  [Telegram]      │                    User gains access immediately!
└──────────────────┘


═══════════════════════════════════════════════════════════════════════════════


REJECTED FLOW
─────────────

Admin clicks "Reject"
        │
        ▼
users/{uid}/
cameraAccessRequested: false ❌
cameraAccessRejectedAt: now
        │
        ▼
User can resubmit credentials
(Fix typos, wrong username, etc.)


═══════════════════════════════════════════════════════════════════════════════


UI STATES
─────────

┌─────────────────────────────────────────────────────────────────────────────┐
│ USER VIEW - Watch Tab                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STATE 1: No Credentials Entered                                            │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │  🔒  Access Restricted                                           │       │
│  │                                                                  │       │
│  │  You are not an authorized camera user.                         │       │
│  │  Please contact an admin to request access.                     │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│  STATE 2: Credentials Entered, Pending Approval                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │  ⏳  Request Pending                                             │       │
│  │                                                                  │       │
│  │  Your camera access request is awaiting admin approval.         │       │
│  │  You'll be notified once approved.                              │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│  STATE 3: Approved                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │  📹  Security Camera Network                                     │       │
│  │                                                                  │       │
│  │  [🎥 Open Camera Portal]                                         │       │
│  │  [📱 Telegram Alerts]                                            │       │
│  │  [⚙️ Settings]                                                    │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│ ADMIN VIEW - Watch Admin Settings                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ▼ Committee Members (5)                                                    │
│                                                                             │
│  ▼ Pending Camera Requests (3) ⚠️                                           │
│     ┌───────────────────────────────────────────────────────────────┐      │
│     │  👤  Mike Wilson                                               │      │
│     │  📹  Watch Username: MikeW                                     │      │
│     │  📍  123 Main St, Suburb                                       │      │
│     │                                                                │      │
│     │  [✅ Approve]  [❌ Reject]                                      │      │
│     └───────────────────────────────────────────────────────────────┘      │
│                                                                             │
│     ┌───────────────────────────────────────────────────────────────┐      │
│     │  👤  Jane Smith                                                │      │
│     │  📹  Watch Username: JaneS                                     │      │
│     │  📍  456 Oak Ave, Suburb                                       │      │
│     │                                                                │      │
│     │  [✅ Approve]  [❌ Reject]                                      │      │
│     └───────────────────────────────────────────────────────────────┘      │
│                                                                             │
│  ▼ Pending Users (2)                                                        │
│                                                                             │
│  ▼ Approved Users (12)                                                      │
└─────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════


DATA FLOW SEQUENCE
──────────────────

1. User enters credentials
   ├─► watchUsername saved to @AppStorage (device-local)
   ├─► watchPassword saved to @AppStorage (device-local)
   └─► FirebaseManager.requestCameraAccess() called
       └─► Firestore update:
           ├─► cameraAccessRequested = true
           ├─► watchCredential = watchUsername
           └─► cameraAccessRequestedAt = now

2. Admin sees request
   ├─► Firestore listener triggers
   ├─► ContentView.pendingCameraAccessRequests updates
   └─► UI shows orange badge with count

3. Admin approves
   ├─► FirebaseManager.updateCameraAccess(granted: true)
   └─► Firestore update:
       ├─► cameraAccess = true ✅
       ├─► cameraAccessRequested = false
       ├─► cameraAccessGrantedBy = {adminUID}
       └─► cameraAccessUpdatedAt = now

4. User gains access
   ├─► Firestore listener triggers
   ├─► ContentView.userHasCameraAccess = true
   ├─► ContentView.isCameraUser returns true
   └─► WatchView loads with camera portal


═══════════════════════════════════════════════════════════════════════════════


SECURITY MODEL
──────────────

┌─────────────────────────────────────────────────────────────────────────────┐
│                          TWO-LAYER SECURITY                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LAYER 1: Permission (Firestore - Admin Controlled)                         │
│  ─────────────────────────────────────────────────────                      │
│  Field: cameraAccess: Boolean                                               │
│  Controls: WHO can access the camera system                                 │
│  Managed by: Admins via approval workflow                                   │
│  Checked at: ContentView.isCameraUser                                       │
│                                                                             │
│  LAYER 2: Authentication (Local - User Controlled)                          │
│  ────────────────────────────────────────────────────────                   │
│  Fields: watchUsername, watchPassword (@AppStorage)                         │
│  Controls: Actual camera hardware login                                     │
│  Managed by: Each user enters their own credentials                         │
│  Used at: WebView auto-login injection                                      │
│                                                                             │
│  BOTH LAYERS REQUIRED for full camera access ✅                             │
└─────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════


TIMELINE EXAMPLE
────────────────

10:00 AM - User Mike enters credentials in Home settings
           ├─► watchUsername: "MikeW"
           └─► watchPassword: "••••••••"

10:00 AM - System auto-submits request
           ├─► Firestore: cameraAccessRequested = true
           ├─► Firestore: watchCredential = "MikeW"
           └─► UI shows: "✅ Camera access requested"

10:05 AM - Admin Jane opens Watch admin settings
           ├─► Sees: "Pending Camera Requests (1) ⚠️"
           └─► Clicks to expand section

10:06 AM - Admin reviews request
           ├─► User: Mike Wilson
           ├─► Watch Username: MikeW
           └─► Address: 123 Main St

10:07 AM - Admin approves
           ├─► Firestore: cameraAccess = true
           ├─► Firestore: cameraAccessGrantedBy = "jane_uid"
           └─► Firestore: cameraAccessUpdatedAt = now

10:07 AM - User Mike's device receives update
           ├─► Firestore listener triggers
           ├─► userHasCameraAccess = true
           └─► Watch tab unlocks immediately

10:08 AM - User Mike opens Watch tab
           ├─► Camera portal loads
           ├─► WebView injects credentials
           └─► Auto-login successful ✅


═══════════════════════════════════════════════════════════════════════════════


MIGRATION COMPARISON
────────────────────

┌─────────────────────────────────┬─────────────────────────────────────────┐
│        LEGACY SYSTEM            │          NEW REQUEST SYSTEM             │
├─────────────────────────────────┼─────────────────────────────────────────┤
│                                 │                                         │
│  Admin manually types names     │  User submits credentials               │
│  into text field                │  automatically                          │
│                                 │                                         │
│  "Mike W, John D, Jane S..."    │  User fills form → Request sent         │
│                                 │                                         │
│  ❌ Typos common                 │  ✅ No typos (direct input)              │
│  ❌ User has no visibility       │  ✅ User sees status                     │
│  ❌ Name-based (insecure)        │  ✅ UID-based (secure)                   │
│  ❌ Migration required           │  ✅ No migration needed                  │
│  ❌ No audit trail               │  ✅ Full timestamps & tracking           │
│  ❌ AppStorage (local only)      │  ✅ Firestore (real-time sync)           │
│                                 │                                         │
└─────────────────────────────────┴─────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════
```
