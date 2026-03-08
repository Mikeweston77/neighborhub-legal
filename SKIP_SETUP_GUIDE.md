# Skip.tools Setup Guide for NeighborHub Android

## What is Skip?
Skip transpiles your SwiftUI iOS app into Kotlin Compose for Android, allowing you to maintain a single codebase for both platforms.

## Prerequisites

### 1. Install Android Studio (Required)
Download from: https://developer.android.com/studio

After installation:
- Open Android Studio
- Go to Settings → Appearance & Behavior → System Settings → Android SDK
- Install Android SDK Platform 34 (Android 14)
- Install Android SDK Build-Tools
- Install Android Emulator

### 2. Install Java Development Kit (JDK)
```bash
brew install openjdk@17
```

### 3. Set JAVA_HOME environment variable
```bash
echo 'export JAVA_HOME="/usr/local/opt/openjdk@17"' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 4. Install Gradle (Android build system)
```bash
brew install gradle
```

## Installing Skip

### Method 1: Using Swift Package Manager (Recommended)

Skip is integrated as a Swift Package in your Xcode project.

1. Open NeighborHub.xcodeproj in Xcode
2. File → Add Packages...
3. Enter URL: `https://github.com/skiptools/skip`
4. Select version and add to project

### Method 2: Using Skip CLI

The Skip CLI isn't available via Homebrew yet. Instead, use it through Swift Package Manager plugins.

## Creating Android Version of NeighborHub

### Option A: Convert Existing Project (Complex)

This requires significant refactoring because:
- Skip supports a subset of SwiftUI
- Firebase SDK needs Skip-compatible alternatives
- Some iOS-specific features need conditional compilation

### Option B: Create New Skip Project (Recommended for Learning)

1. Install Skip template:
```bash
# Clone Skip starter template
git clone https://github.com/skiptools/skipapp-hello.git NeighborHub-Android
cd NeighborHub-Android
```

2. Build for Android:
```bash
# Open in Xcode
open Hello.xcodeproj

# Or build from command line
xcodebuild -project Hello.xcodeproj -scheme Hello-Android
```

## Alternative: Flutter Approach (Easier for NeighborHub)

Given NeighborHub's complexity (Firebase, Maps, Camera), Flutter might be easier:

### Install Flutter:
```bash
# Download Flutter
cd ~/Development
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/Development/flutter/bin"' >> ~/.zshrc
source ~/.zshrc

# Verify installation
flutter doctor
```

### Create Flutter version:
```bash
flutter create neighborhub_flutter
cd neighborhub_flutter
flutter run
```

Flutter advantages for NeighborHub:
- ✅ Full Firebase support (firebase_core, cloud_firestore, firebase_auth)
- ✅ Better Maps support (google_maps_flutter)
- ✅ Easier camera integration
- ✅ Large community and packages
- ✅ Mature tooling

## Recommendation for NeighborHub

**For fastest Android deployment:**

1. **Use Flutter** to create Android version
   - Copy business logic
   - Recreate UI in Flutter widgets
   - Reuse Firebase backend (same Firestore, same Functions)
   - Faster than Skip for this complex app

2. **Keep iOS version in SwiftUI**
   - Already complete and working
   - Optimized for iOS

**Shared backend:**
- Same Firebase project
- Same Firestore database
- Same Cloud Functions
- Same Storage buckets
- Just different clients (iOS/Android)

## Next Steps

Choose your path:

**Path 1: Skip (Experimental, Single Codebase)**
- Good for: Simple apps, SwiftUI purists
- Time: High (lots of refactoring)
- Complexity: High

**Path 2: Flutter (Production-Ready)**
- Good for: Complex apps like NeighborHub
- Time: Medium (rebuild UI, keep backend)
- Complexity: Medium
- Better support for Firebase, Maps, Camera

**Path 3: Native Android (Kotlin/Compose)**
- Good for: Maximum control
- Time: Very High
- Complexity: Very High

## My Recommendation

For NeighborHub specifically, I recommend **Flutter**:

1. Install Flutter (5 minutes)
2. Create new Flutter project (2 minutes)
3. Add Firebase packages (10 minutes)
4. Rebuild UI in Flutter widgets (2-3 weeks)
5. Connect to existing Firebase backend (1-2 days)

Want me to help you get started with Flutter instead?
