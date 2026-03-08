# NeighborHub - Comprehensive Neighborhood Community App

NeighborHub is a comprehensive iOS app built with SwiftUI that brings neighborhood communities together through digital tools for safety, social connection, resource sharing, and local commerce. The app combines features from NextDoor, neighborhood watch systems, and local marketplace platforms.

## 🌟 Features

### 🔒 Neighborhood Watch 2.0
- **Digital patrol schedules** with volunteer coordination
- **License plate recognition** for tracking unusual vehicles
- **Security camera network** sharing between neighbors
- **Emergency contact tree** with automated calling
- **Safety event calendar** with community meetings
- **Crime trend analysis** with heat maps

### 🤝 Community Connection & Social
- **Hyperlocal social feed** with radius-based posts
- **Neighbor verification system** using address confirmation
- **Community event planning** with RSVP tracking
- **Local business promotion** with neighbor reviews
- **Lost & found marketplace** with photo matching
- **Neighborhood awards** for helpful community members

### 🛠️ Resource Sharing & Services
- **Tool library** with reservation system and calendar integration
- **Community workshop coordination** for shared projects
- **Emergency help requests** with immediate notifications
- **Skill-sharing marketplace** (tutoring, repairs, cooking)

### 🛒 HyperLocal Marketplace
- **Neighborhood-only buying/selling** with pickup locations
- **Community garage sale** coordination
- **Local produce sharing** from home gardens
- **Bulk buying groups** for discounts
- **Barter system** for non-monetary exchanges
- **Sustainability scoring** for eco-friendly transactions

### 🏡 Community Management
- **Property maintenance reminders** shared with neighbors
- **Contractor recommendations** with neighbor reviews
- **Neighborhood improvement projects** with voting
- **Utility outage reporting** and status updates
- **Community garden management** with plot assignments
- **Petition creation** and signature collection
- **Community issue tracking** with resolution progress

## 🛠️ Technical Stack

- **Framework**: SwiftUI with iOS 17+ deployment target
- **Data**: Core Data for local persistence
- **Location**: CoreLocation and MapKit for GPS and mapping features
- **AI/ML**: CoreML for content moderation and safety analytics
- **Backend**: Firebase for cloud services, real-time messaging, and user authentication
- **Notifications**: UserNotifications framework for push notifications
- **Camera**: AVFoundation for camera integration and license plate recognition

## 📱 App Structure

### Main Navigation
The app uses a tab-based navigation with 5 main sections:
1. **Home** - Social feed and community updates
2. **Watch** - Neighborhood watch and safety features
3. **Market** - Local marketplace and commerce
4. **Events** - Community events and calendar
5. **Tools** - Resource sharing and community management

### Core Data Models
- **User**: Neighbor profiles with verification, reputation, skills, and interests
- **Post**: Community posts with categories, location, and engagement metrics
- **Event**: Community events with RSVP tracking and resource coordination
- **MarketplaceListing**: Local commerce with sustainability scoring
- **SecurityIncident**: Safety reports with severity levels and evidence
- **PatrolSchedule**: Volunteer coordination for neighborhood watch
- **SharedResource**: Community tool library and resource sharing
- **CommunityIssue**: Issue tracking with voting and resolution progress
- **Petition**: Community petitions with signature collection
- **EmergencyContact**: Emergency response coordination

## 🔧 Key Managers & Services

### LocationManager
- GPS-based neighbor verification
- Radius-based content filtering
- Emergency location sharing

### SafetyManager
- Real-time safety score calculation
- Incident reporting and classification
- Emergency notification system

### ContentModerationManager
- AI-powered content filtering
- Community reporting system
- Automated spam detection

### ReputationManager
- Community contribution scoring
- Verification status tracking
- Neighbor reliability metrics

### PushNotificationManager
- Emergency alert system
- Community event notifications
- Real-time messaging

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0 or later
- Swift 5.9 or later

### Installation
1. Clone the repository
2. Open `NeighborHub.xcodeproj` in Xcode
3. Build and run the project

### Building the Project
You can build the project using the provided VS Code task:
```bash
xcodebuild -project NeighborHub.xcodeproj -scheme NeighborHub -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
```

### Configuration
The app requires the following permissions:
- Location Services (for neighborhood verification)
- Camera Access (for photo sharing and license plate recognition)
- Notifications (for emergency alerts and community updates)
- Contacts (for emergency contact integration)

## 📈 Current Development Status

### ✅ Recently Completed
- **Core SwiftUI Structure**: Main navigation and tab-based architecture
- **Enhanced Marketplace View**: Search functionality, category filters, sample listings, and new listing modal
- **Enhanced Events View**: Tabbed event lists, sample event cards, and new event modal
- **Enhanced Community Tools View**: Category filters, sample tool/service/resource/skill cards, and new item modal
- **Enhanced Social Feed View**: Sample posts, interactive like/comment/share actions, and comments modal
- **Enhanced New Post View**: Category selection, text entry, photo attachment (placeholder), and post options
- **Weather Integration**: Local weather display with hourly forecasts
- **Core Data Models**: Comprehensive data models for all major features
- **Manager Classes**: Service managers for location, safety, content moderation, and reputation
- **Build System**: Successful builds and error resolution
- **SwiftUI Previews**: Fixed preview code errors and added comprehensive preview examples
- **Neighborhood Watch Views**: Enhanced patrol scheduling, security cameras, and crime trends
- **Xcode 16.0 Compatibility**: Resolved Canvas, console, and simulator issues

### ✅ Current Features (UI Complete)
- 🏠 **Home Tab**: Social feed with community posts and weather
  - Clean homescreen design with no card backgrounds
  - Horizontal weather layout with main temperature and 4-hour forecast side by side
  - Enhanced weather section integration with greeting area
- 🛒 **Marketplace Tab**: Local commerce with search and categories
- 📅 **Events Tab**: Community events with RSVP tracking
- 🛠️ **Tools Tab**: Resource sharing and community services
- 🔒 **Watch Tab**: Neighborhood watch features with patrol scheduling, security cameras, and crime trends

### ✅ Fixed Issues
- **SwiftUI Preview Errors**: All preview code now uses correct view constructors and parameters
- **Build Errors**: Resolved type-checking issues and missing arguments in preview code
- **Xcode Canvas**: Added comprehensive troubleshooting steps for Canvas/Preview not working
- **iOS Simulator**: Provided reset procedures and alternative debugging methods
- **Console Issues**: Added multiple troubleshooting approaches for Xcode 16.0 console problems

### In Progress
- 🔄 **Neighborhood Watch Views**: Enhanced safety and patrol features
- 🔄 **Real Data Integration**: Connecting UI to Core Data models
- 🔄 **Backend Integration**: Firebase setup and real-time features
- 🔄 **Camera Integration**: Real photo picker and image handling
- 🔄 **Location Services**: GPS-based neighbor verification

### Next Steps
- 📝 **Unit Testing**: Comprehensive test coverage
- 🔐 **Security Implementation**: Privacy controls and data encryption
- 🎨 **UI Polish**: Animations, transitions, and accessibility
- 📱 **Performance Optimization**: Memory management and async operations
- 🌐 **Backend Services**: Real-time messaging and push notifications

## 🎨 UI/UX Guidelines

### Design Principles
- Clean, accessible interface with clear navigation
- Privacy-first design with granular sharing controls
- Emergency-optimized quick actions
- Community-focused color scheme and iconography
- Responsive design for various screen sizes

### Navigation Structure
- Tab-based navigation with 5 main sections
- Feature-specific drill-down navigation
- Quick action buttons for emergency features
- Search and filter capabilities across all sections

## 🔐 Security & Privacy

- Address verification required for access
- Anonymous reporting options available
- Granular privacy controls for all shared data
- Encrypted emergency contact storage
- User consent required for location sharing

## 🔧 Troubleshooting

### Xcode Canvas and Simulator Issues in Xcode 16.0

If you're experiencing issues with SwiftUI Canvas previews or iOS Simulator after updating to Xcode 16.0, try these solutions:

#### 1. **SwiftUI Canvas/Preview Issues**
If SwiftUI Canvas is not loading or showing previews:

**Step 1: Check Preview Code**
- Ensure all `#Preview` blocks have valid view constructors
- Verify that all required parameters are provided for view initializers
- Check that all referenced views exist and are properly imported

**Step 2: Clean and Rebuild**
```bash
# Clean build folder
cmd+shift+k

# Clean derived data
cmd+shift+option+k

# Rebuild project
cmd+b
```

**Step 3: Reset SwiftUI Canvas**
1. In Xcode, go to **Editor → Canvas → Reset Canvas**
2. If Canvas doesn't appear, go to **Editor → Canvas → Show Canvas**
3. Try using the keyboard shortcut `⌥⌘↩` (Option+Command+Return)

**Step 4: Check Canvas Device Settings**
1. In Canvas preview, click the device name at the bottom
2. Try different device types (iPhone 15 Pro, iPhone 16 Pro, etc.)
3. Try different iOS versions if available

#### 2. **iOS Simulator Problems**
If iOS Simulator is not working properly:

**Step 1: Reset iOS Simulator**
1. Open iOS Simulator
2. Go to **Device → Erase All Content and Settings**
3. Restart the simulator

**Step 2: Alternative Terminal Reset**
```bash
# Reset all iOS simulators
xcrun simctl shutdown all
xcrun simctl erase all
```

**Step 3: Create New Simulator**
1. Open Xcode
2. Go to **Window → Devices and Simulators**
3. Click **Simulators** tab
4. Click **+** to create a new simulator
5. Choose iOS version and device type

**Step 4: Check Simulator Settings**
1. In Simulator, go to **Device → Device Settings**
2. Ensure hardware keyboard is properly configured
3. Check accessibility settings if needed

#### 3. **Console Issues in Xcode 16.0**

**Step 1: Manual Console Reset in Xcode**
1. Open your project in Xcode
2. Open the Debug Area: **View → Debug Area → Show Debug Area** (or `⇧⌘Y`)
3. In the Debug Area, click the Console button (right side of the debug area)
4. Try running your app again to see if console output appears

**Step 2: Reset Debug Console Layout**
1. In Xcode, go to **View → Debug Area → Reset Debug Area**
2. This will reset the debug area layout to default settings

**Step 3: Alternative Console Viewing Methods**
- **Console.app**: Use macOS Console app to view system logs
  - Open Console.app from `/Applications/Utilities/`
  - Filter by your app name "NeighborHub"
- **Xcode Simulator Logs**: View logs directly in iOS Simulator
  - Device → Log Location → Show Log in Finder
- **Terminal Debugging**: Add print statements in your code:
  ```swift
  print("Debug message: \(someVariable)")
  NSLog("NSLog message: %@", someVariable)
  ```

**Step 4: Check Console Settings**
1. In Xcode, go to **Xcode → Settings → Behaviors**
2. Under "Build → Succeeds", ensure "Show debugger with Console View" is checked
3. Under "Run → Starts", ensure "Show debugger with Console View" is checked

#### 4. **Comprehensive Reset Procedure**

If multiple issues persist, try this comprehensive reset:

**Step 1: Clear All Caches**
```bash
# Close Xcode first, then run:
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/com.apple.dt.Xcode
rm -rf ~/Library/Developer/CoreSimulator/Devices
```

**Step 2: Reset Xcode Preferences**
```bash
# Close Xcode first
defaults delete com.apple.dt.Xcode
```

**Step 3: Reset iOS Simulators**
```bash
xcrun simctl shutdown all
xcrun simctl erase all
```

**Step 4: Restart and Rebuild**
1. Restart your Mac
2. Open Xcode
3. Open your project
4. Clean Build Folder (`⌘⇧K`)
5. Rebuild (`⌘B`)

#### 5. **Advanced Troubleshooting**

**Enable All Exception Breakpoints**
1. Open the Breakpoint Navigator (`⌘8`)
2. Click `+` → "Exception Breakpoint"
3. This will help catch runtime issues that might not appear in console

**Check Xcode Version Compatibility**
1. Ensure your project deployment target is compatible with Xcode 16.0
2. Update iOS deployment target if necessary (iOS 17.0+ recommended)
3. Check for deprecated APIs that might cause issues

**Alternative Preview Methods**
If Canvas still doesn't work, you can test views by:
1. Creating a simple test view in your app
2. Using the iOS Simulator to test interactions
3. Using Xcode's View Debugger: **Debug → View Debugging → Capture View Hierarchy**

#### 6. **System Information**
If issues persist, gather this information for further troubleshooting:
- macOS version
- Xcode version (16.0 build number)
- iOS Simulator version
- Project deployment target
- Mac hardware specifications

### Build Warnings

The project currently shows some deprecation warnings for MapKit:
- Map initializers are deprecated in iOS 17.0+
- MapAnnotation is deprecated in iOS 17.0+

These are cosmetic warnings and don't affect functionality. Consider updating to the new Map builders when convenient.

### SwiftUI Canvas/Preview Issues in Xcode 16.0

If SwiftUI Previews (Canvas) are not working, try these solutions in order:

#### 1. **Basic Canvas Reset**
1. In Xcode, open any SwiftUI file with previews
2. Press `⌥⌘P` (Option+Command+P) to resume previews
3. Or click **Resume** button in the Canvas area
4. If Canvas isn't visible: **Editor → Canvas** or `⌥⌘⏎`

#### 2. **Clean and Rebuild for Previews**
```bash
# Clean build folder completely
rm -rf ~/Library/Developer/Xcode/DerivedData/NeighborHub-*

# Clean and rebuild
xcodebuild clean -project NeighborHub.xcodeproj -scheme NeighborHub
xcodebuild -project NeighborHub.xcodeproj -scheme NeighborHub -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
```

#### 3. **Reset Canvas and Simulator**
1. **Reset Canvas**: In Xcode, go to **Developer → Reset Preview Cache**
2. **Reset Simulator**: `iOS Simulator → Device → Erase All Content and Settings`
3. **Restart Xcode** completely
4. **Restart Mac** (if above steps don't work)

#### 4. **Fix Common Preview Code Issues**
Make sure your SwiftUI previews are properly structured:

```swift
#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
```

#### 5. **Preview Device Selection**
1. In Canvas, click the device name at the bottom
2. Try different simulators: iPhone 15, iPhone 16 Pro, etc.
3. Ensure the selected device is available in Simulator

#### 6. **Enable Canvas Diagnostics**
1. Go to **Xcode → Settings → Components**
2. Install additional simulators if missing
3. Check **Xcode → Settings → Accounts** for valid developer account

#### 7. **Alternative Preview Methods**
If Canvas still doesn't work:
- **Live Preview**: Build and run in iOS Simulator instead
- **SwiftUI Inspector**: Use the inspector tool in running simulator
- **Manual Testing**: Test UI changes by running the full app

#### 8. **Check Preview-Specific Issues**
Common preview blockers in your code:
- **Core Data**: Ensure preview context is properly set up
- **@StateObject**: Use `@State` for previews when possible  
- **Environment Objects**: Provide mock objects in preview
- **File Paths**: Use bundle resources, not file system paths

#### 9. **Xcode 16 Specific Fixes**
```bash
# Clear all Xcode caches
rm -rf ~/Library/Developer/Xcode/UserData/Previews
rm -rf ~/Library/Developer/CoreSimulator/Caches
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# Reset iOS Simulator
xcrun simctl erase all
```

#### 10. **Fallback: Disable Previews Temporarily**
If previews remain broken, you can disable them and use full app testing:
1. Comment out `#Preview` blocks temporarily
2. Use iOS Simulator for all testing
3. Re-enable previews after Xcode updates

### Preview Performance Tips
- Limit preview complexity - use simple mock data
- Use `PreviewProvider` for complex setups
- Test on multiple device types in Canvas
- Use `previewLayout(.sizeThatFits)` for view components

## 🧪 Testing Strategy

- Unit tests for all manager classes
- Integration tests for Core Data operations
- UI tests for critical user flows
- Location and privacy permission testing
- Emergency scenario testing

## 🔮 Future Enhancements

- Integration with Ring/Nest cameras
- AI-powered license plate recognition
- Multi-language support
- City services integration
- Advanced analytics and reporting
- Voice-to-text for emergency reporting
- Machine learning for content recommendations

## 📝 Code Organization

```
NeighborHub/
├── NeighborHubApp.swift           # Main app entry point
├── ContentView.swift              # Main UI with tab navigation and all views
├── Persistence.swift              # Core Data stack configuration
├── Models/
│   └── CoreDataModels.swift       # Core Data models and sample data
├── Views/
│   └── NeighborhoodWatchViews.swift  # Safety and patrol views
├── Managers/
│   └── NeighborhoodManagers.swift    # Service managers and utilities
├── Assets.xcassets/               # App icons and color assets
├── NeighborHub.xcdatamodeld/      # Core Data model file
└── Preview Content/               # Preview assets for SwiftUI
```

### Key Files
- **ContentView.swift**: Contains all main UI views including HomeView, MarketplaceView, EventsView, CommunityToolsView, and SocialFeedView
- **CoreDataModels.swift**: Defines all Core Data entities and relationships
- **NeighborhoodManagers.swift**: Contains LocationManager, SafetyManager, and other service classes
- **NeighborhoodWatchViews.swift**: Specialized views for neighborhood watch features

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support, please contact the development team or open an issue in the repository.

---

Built with ❤️ for stronger neighborhood communities

## Firestore Polls (Realtime)

This project includes a lightweight Firestore wrapper at `NeighborHub/Managers/FirebaseManager.swift` to support realtime Polls under the `polls` collection.

Required Firestore structure (recommended):
- Collection: `polls`
  - Document: `active` (singleton for the currently active poll)
    - Fields: `id`, `question`, `options` (array of strings), `votes` (array of ints), `votesByUser` (map userId->optionIdx), `expiresAt`, `createdAt`

The app will automatically watch `polls/active` when `HomeView` appears and will use Firestore transactions to record votes safely across users.

Notes:
- For proper user-specific vote tracking, integrate Firebase Authentication and pass `Auth.auth().currentUser?.uid` into `FirebaseManager.voteOnActivePoll(userId:optionIndex:completion:)` instead of the simple AppStorage-based fallback.
- If Firestore isn't available (compile-time), the app will fall back to local AppStorage persistence.
