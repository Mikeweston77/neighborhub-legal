<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# NeighborHub - Comprehensive Neighborhood Community App

## Project Overview
NeighborHub is a comprehensive iOS app built with SwiftUI that brings neighborhood communities together through digital tools for safety, social connection, resource sharing, and local commerce. The app combines features from NextDoor, neighborhood watch systems, and local marketplace platforms.

## Architecture & Technologies
- **Framework**: SwiftUI with iOS 17+ deployment target
- **Data**: Core Data for local persistence
- **Location**: CoreLocation and MapKit for GPS and mapping features
- **AI/ML**: CoreML for content moderation and safety analytics
- **Backend**: Firebase for cloud services, real-time messaging, and user authentication
- **Notifications**: UserNotifications framework for push notifications
- **Camera**: AVFoundation for camera integration and license plate recognition

## Key Features Implemented

### 1. Neighborhood Watch 2.0
- Digital patrol schedules with volunteer coordination
- Security camera network sharing between neighbors
- Emergency contact tree with automated calling
- Safety event calendar with community meetings
- Crime trend analysis with heat maps
- Real-time incident reporting system

### 2. NextDoor Clone Plus (Community Social)
- Hyperlocal social feed with radius-based posts
- Neighbor verification system using address confirmation
- Community event planning with RSVP tracking
- Local business promotion with neighbor reviews
- Lost & found marketplace with photo matching
- Neighborhood awards for helpful community members

### 3. Resource Sharing & Services
<!-- Short, practical instructions for AI coding assistants working on NeighborHub. Keep this file concise and actionable. -->

# NeighborHub — AI Agent Guide (short)

Focus on rapid, safe edits. The repo contains an iOS SwiftUI app (`NeighborHub/`), Firebase Cloud Functions (`functions/`), and a Flutter subfolder (`neighborhub_flutter/`). Work locally against files listed below and prefer small, reversible patches.

Key patterns & examples
- Local-first data: managers persist to UserDefaults and Application Support before remote writes. See `NeighborHub/Managers/FirebaseManager.swift` (keys like `communityMessagesData`, `eventsData`, `marketplaceData`) and `NeighborHub/Persistence.swift` (`PersistenceController.preview`).
- Firestore collections & contracts: `polls/active` (singleton), `communityMessages`, `incidents`, `events`, `marketplace`, `chats/{chatId}/messages`. See `FirebaseManager` for exact field names and read/write patterns (timestamps, `imageURL`, `fileURL`).
- Storage upload flow: client uploads to `uploads/{uid}/...` and Cloud Functions move/process files into `final/{id}/` and `thumbs/{id}/`. See `functions/index.js` for processing, moderation, and Firestore updates.

Developer workflows (discoverable)
- iOS build (Xcode): open `NeighborHub.xcodeproj` or use the VS Code task labeled "Build NeighborHub iOS App". Example used by CI/local scripts:
```bash
xcodebuild -project NeighborHub.xcodeproj -scheme NeighborHub -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
```
- Firebase functions: code is under `functions/` and expects `admin.initializeApp()`. Deploy with the Firebase CLI (use emulator for local work when possible).

Conventions & gotchas
- Prefer small edits that respect the local-first pattern (update local persistence before remote writes). Many managers call `upsertLocalCodableArray` and save to Application Support — preserve that flow when refactoring.
- Storage URL handling: code contains helpers that convert download URLs to StorageReferences; avoid assuming downloadURL == reference path. See `storageReference(fromDownloadURLString:)` in `FirebaseManager.swift`.
- Feature flags & compile-time availability: many files use `#if canImport(FirebaseStorage)` / `canImport(FirebaseAuth)` to provide fallbacks. When adding features, mirror these guards.

Files to reference when editing (most important)
- `NeighborHub/Managers/FirebaseManager.swift` — central Firestore + Storage logic and many patterns to follow
- `NeighborHub/Persistence.swift` — Core Data container and preview usage
- `functions/index.js` — Cloud Functions for image/video processing and moderation
- `NeighborHub/ContentView.swift` and `NeighborHub/Preview Content/` — SwiftUI entry points and preview patterns

When you change public behavior
- Add or update small unit tests under `NeighborHubTests/` when possible.
- Run the Xcode build task and, for functions, use the Firebase emulator to validate end-to-end behavior.

If anything is unclear, ask for the intended runtime (device vs simulator), Firebase project config (GoogleService-Info.plist is present), or whether you should modify server-side Rules (firestore.rules / firebase-storage.rules).

End of file — keep this short and update with repository-specific findings.
## Key Managers & Services
