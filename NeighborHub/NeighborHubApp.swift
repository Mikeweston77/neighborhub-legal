import FirebaseAnalytics
import FirebaseCore
import SwiftUI
import UserNotifications

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

@main
struct NeighborHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared
    @StateObject private var appState = AppState()

    // Register for push notifications on launch
    init() {
        registerForPushNotifications()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Request notification permissions again if needed
                    registerForPushNotifications()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification)
                ) { _ in
                    // App entered background - location updates will continue automatically
                    print("📱 App entered background - location tracking continues")
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    // App entering foreground - refresh location and weather
                    print("📱 App entering foreground - refreshing location")
                    Task {
                        // Give location services a moment to reactivate
                        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                        await MainActor.run {
                            appState.refreshLocationAndWeather()
                        }
                    }
                    
                    #if canImport(FirebaseFirestore)
                    // Re-cache user roles and profile data in case they changed while app was in background
                    FirebaseManager.shared.cacheCurrentUserRoles {
                        print("✅ User roles refreshed on foreground")
                    }
                    
                    // Reload user profile data (including profile image URL)
                    FirebaseManager.shared.loadCurrentUserProfile { result in
                        print("✅ User profile data refreshed on foreground")
                    }
                    
                    // Clean up cache on app launch to manage storage
                    FirebaseManager.shared.cleanupNewsletterCache()
                    #endif
                }
        }
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = appDelegate

        // Register notification categories
        let chatCategory = UNNotificationCategory(
            identifier: "chat",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let communityCategory = UNNotificationCategory(
            identifier: "community",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let emergencyCategory = UNNotificationCategory(
            identifier: "emergency",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            chatCategory, communityCategory, emergencyCategory,
        ])

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, error in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - AppDelegate for Push Notifications
    class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool {
            // Initialize Firebase early in app lifecycle
            FirebaseApp.configure()
            
            // Set up Firebase Messaging delegate
            #if canImport(FirebaseMessaging)
            Messaging.messaging().delegate = self
            print("📱 Firebase Messaging delegate configured")
            #endif
            
            // Disable App Check enforcement for development (App Check not configured in Firebase Console)
            #if DEBUG
            print("⚠️ DEBUG MODE: Using placeholder App Check tokens")
            // App Check will use placeholder tokens automatically when not configured
            #endif
            
            // Ensure Analytics is enabled so Firebase In-App Messaging can function
            Analytics.setAnalyticsCollectionEnabled(true)
            // Log an app_open event so Analytics is initialized
            Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
            
            // Enable Crashlytics for crash reporting
            #if canImport(FirebaseCrashlytics)
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            print("✅ Firebase Crashlytics enabled")
            
            // Set user identifier for crash reports (if authenticated)
            if let userId = Auth.auth().currentUser?.uid {
                Crashlytics.crashlytics().setUserID(userId)
            }
            #endif

            // Start attachment recovery monitoring
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AttachmentRecoveryManager.shared.startMonitoring()
                print("AttachmentRecoveryManager: Started monitoring for lost attachments")
            }

            return true
        }
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            // Convert deviceToken to string
            let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
            let token = tokenParts.joined()
            print("📱 APNs Device Token: \(token)")
            
            // Pass APNs token to Firebase Messaging
            #if canImport(FirebaseMessaging)
            Messaging.messaging().apnsToken = deviceToken
            print("✅ APNs token passed to Firebase Messaging")
            #else
            // Fallback: Store APNs token directly if Firebase Messaging not available
            #if canImport(FirebaseFirestore)
            FirebaseManager.shared.storeFCMToken(apnsToken: token) { result in
                switch result {
                case .success:
                    print("✅ APNs token stored successfully")
                case .failure(let error):
                    print("❌ Failed to store APNs token: \(error.localizedDescription)")
                }
            }
            #endif
            #endif
        }

        func application(
            _ application: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: Error
        ) {
            print("Failed to register for remote notifications: \(error)")
        }

        // Handle notification when app is in foreground
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
                -> Void
        ) {
            // Show notifications even when app is in foreground for chat messages
            let categoryId = notification.request.content.categoryIdentifier
            if categoryId == "chat" || categoryId == "community" || categoryId == "emergency" {
                completionHandler([.banner, .sound, .badge])
            } else {
                completionHandler([.banner, .sound, .badge])
            }
        }

        // Handle notification tap
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            let categoryId = response.notification.request.content.categoryIdentifier
            let identifier = response.notification.request.identifier

            // Handle different notification categories
            switch categoryId {
            case "chat":
                // Will be handled by ContentView's NotificationDelegate
                break
            case "community":
                // Will be handled by ContentView's NotificationDelegate
                break
            case "emergency":
                // Emergency notifications might need special handling
                break
            default:
                // Legacy handling for notifications without categories
                if identifier.starts(with: "chat-") {
                    // Will be handled by ContentView's NotificationDelegate
                }
            }

            completionHandler()
        }

    }  // End of AppDelegate
}  // End of NeighborHubApp

#if canImport(FirebaseMessaging)
// MARK: - Firebase Messaging Delegate
extension NeighborHubApp.AppDelegate: MessagingDelegate {
    /// Called when FCM token is refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else {
            print("⚠️ FCM token is nil")
            return
        }
        
        print("📱 FCM Token: \(fcmToken)")
        
        #if canImport(FirebaseFirestore)
        // Store FCM token in Firestore for push notifications
        FirebaseManager.shared.storeFCMToken(apnsToken: fcmToken) { result in
            switch result {
            case .success:
                print("✅ FCM token stored successfully in Firestore")
            case .failure(let error):
                print("❌ Failed to store FCM token: \(error.localizedDescription)")
            }
        }
        #endif
        
        // Optional: Send token to your backend server if needed
        // This is useful if you want to send notifications from your own server
        let dataDict: [String: String] = ["token": fcmToken]
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: dataDict
        )
    }
}
#endif
