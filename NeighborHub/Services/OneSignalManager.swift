import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

@MainActor
final class OneSignalManager: NSObject, ObservableObject {
    static let shared = OneSignalManager()

    @Published var showJourneyWelcomeDialog = false
    @Published var pendingTabSelection: Int?
    @Published var lastNotificationPayload: [AnyHashable: Any] = [:]

    private let appId = "1adc72e7-d7c1-4e85-a7b4-a60cf6fdc4be"
    private let defaults = UserDefaults.standard
    private let welcomeDialogShownKey = "com.neighborhub.onesignal.welcomeDialogShown"
    private var hasInitialized = false

    #if canImport(OneSignalFramework)
    private lazy var pushObserver = WelcomePushSubscriptionObserver { [weak self] in
        self?.presentWelcomeDialogIfNeeded()
        self?.persistCurrentSubscriptionIdIfPossible()
    }
    #endif

    private override init() {
        super.init()
    }

    func initialize(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        guard !hasInitialized else { return }
        hasInitialized = true

        #if canImport(OneSignalFramework)
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        #else
        OneSignal.Debug.setLogLevel(.LL_NONE)
        #endif

        OneSignal.initialize(appId, withLaunchOptions: launchOptions)
        OneSignal.User.pushSubscription.addObserver(pushObserver)
        
        // Log subscription status for debugging
        print("📱 OneSignal initialized")
        print("   App ID: \(appId)")
        print("   Push subscription ID: \(OneSignal.User.pushSubscription.id ?? "none")")
        print("   Push subscription token: \(OneSignal.User.pushSubscription.token ?? "none")")
        print("   User opted in: \(OneSignal.User.pushSubscription.optedIn)")
        #endif

        synchronizeUserTagsFromLocalState()
    }

    func requestNotificationPermission(completion: ((Bool) -> Void)? = nil) {
        #if canImport(OneSignalFramework)
        // Use OneSignal's permission request to properly integrate with OneSignal's subscription system
        // This ensures users are subscribed to push notifications in OneSignal's system
        OneSignal.Notifications.requestPermission({ accepted in
            print("🔔 OneSignal notification permission: \(accepted ? "granted" : "denied")")
            
            if accepted {
                print("   Push subscription ID: \(OneSignal.User.pushSubscription.id ?? "none")")
                print("   Push subscription token: \(OneSignal.User.pushSubscription.token ?? "none")")
                print("   User opted in: \(OneSignal.User.pushSubscription.optedIn)")
                #if canImport(FirebaseAuth)
                self.persistCurrentSubscriptionIdIfPossible()
                #endif
            }
            
            DispatchQueue.main.async {
                completion?(accepted)
            }
        }, fallbackToSettings: true)
        #else
        // Fallback for when OneSignal is not available
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, error in
            if let error {
                print("❌ Notification authorization error: \(error.localizedDescription)")
            }

            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            DispatchQueue.main.async {
                completion?(granted)
            }
        }
        #endif
    }

    func handleAuthStateChange(user: FirebaseAuth.User?) {
        #if canImport(OneSignalFramework) && canImport(FirebaseAuth)
        guard hasInitialized else { return }

        if let user {
            let uid = user.uid
            print("👤 OneSignal: Logging in user \(uid)")
            
            // Login with retry mechanism in case OneSignal isn't fully ready
            OneSignal.login(uid)
            
            // Verify login succeeded and retry if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if OneSignal.User.externalId == nil {
                    print("⚠️ External ID not set after first login attempt, retrying...")
                    OneSignal.login(uid)
                    
                    // Check again after second attempt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if OneSignal.User.externalId == nil {
                            print("❌ ERROR: External ID still not set after retry!")
                            print("   UID we tried to set: \(uid)")
                            print("   Current external ID: \(OneSignal.User.externalId ?? "none")")
                        } else {
                            print("✅ External ID set successfully on retry: \(OneSignal.User.externalId!)")
                        }
                    }
                } else {
                    print("✅ External ID set successfully: \(OneSignal.User.externalId!)")
                }
            }
            
            if let email = user.email, !email.isEmpty {
                OneSignal.User.addEmail(email)
                print("   Email added: \(email)")
            }
            
            synchronizeUserTagsFromLocalState()
            
            // Ensure user is opted in to push notifications
            // This is critical for OneSignal SDK v5+ to create a subscription
            if !OneSignal.User.pushSubscription.optedIn {
                print("⚠️ User not opted in, attempting to opt in...")
                OneSignal.User.pushSubscription.optIn()
            }
            
            // Log subscription status after login and persist subscription ID to Firestore
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("📊 OneSignal subscription status after login:")
                print("   External user ID: \(OneSignal.User.externalId ?? "❌ NOT SET")")
                let subscriptionId = OneSignal.User.pushSubscription.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                print("   Push subscription ID: \(subscriptionId.isEmpty ? "none" : subscriptionId)")
                print("   Push token: \(OneSignal.User.pushSubscription.token ?? "none")")
                print("   Opted in: \(OneSignal.User.pushSubscription.optedIn)")
                print("   User has any subscriptions: \(!subscriptionId.isEmpty)")
                
                // Save subscription ID to Firestore so other users can send them notifications.
                // Retry a few times because OneSignal may expose the subscription ID slightly after login.
                self.persistCurrentSubscriptionIdIfPossible(uid: uid)
                
                if OneSignal.User.externalId == nil {
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("❌ CRITICAL: External user ID is NOT SET!")
                    print("   This user will NOT receive push notifications.")
                    print("   Firebase Functions cannot target users without external ID.")
                    print("   Please report this issue with logs.")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }
                
                if OneSignal.User.pushSubscription.id == nil {
                    print("❌ WARNING: No push subscription created! User will NOT receive notifications.")
                    print("   This usually means:")
                    print("   1. Permission was denied")
                    print("   2. App is running in simulator (push doesn't work in simulator)")
                    print("   3. APNs is not properly configured in OneSignal dashboard")
                }
            }
        } else {
            print("👤 OneSignal: Logging out user")
            OneSignal.logout()
            pendingTabSelection = nil
            lastNotificationPayload = [:]
        }
        #endif
    }

    func login(externalId: String) {
        #if canImport(OneSignalFramework)
        guard !externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        OneSignal.login(externalId)
        #endif
    }

    func logout() {
        #if canImport(OneSignalFramework)
        OneSignal.logout()
        #endif
    }

    func setEmail(_ email: String) {
        #if canImport(OneSignalFramework)
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        OneSignal.User.addEmail(email)
        #endif
    }

    func setSMSNumber(_ number: String) {
        #if canImport(OneSignalFramework)
        guard !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        OneSignal.User.addSms(number)
        #endif
    }

    func setTag(key: String, value: String) {
        #if canImport(OneSignalFramework)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        OneSignal.User.addTag(key: key, value: trimmedValue)
        #endif
    }

    func synchronizeUserTagsFromLocalState() {
        let isAdmin = defaults.bool(forKey: "userIsAdmin")
        let isCommittee = defaults.bool(forKey: "userIsCommittee")
        let hasCameraAccess = defaults.bool(forKey: "hasCameraAccess")
        let neighborhood = defaults.string(forKey: "userNeighborhood") ?? ""
        let watchUsername = defaults.string(forKey: "watchUsername") ?? ""
        let firstName = defaults.string(forKey: "userName") ?? ""
        let surname = defaults.string(forKey: "userSurname") ?? ""
        let fullName = "\(firstName) \(surname)".trimmingCharacters(in: .whitespacesAndNewlines)

        let role: String
        if isAdmin {
            role = "admin"
        } else if isCommittee {
            role = "committee"
        } else {
            role = "resident"
        }

        setTag(key: "role", value: role)
        setTag(key: "is_admin", value: isAdmin ? "true" : "false")
        setTag(key: "is_committee", value: isCommittee ? "true" : "false")
        setTag(key: "camera_access", value: hasCameraAccess ? "true" : "false")

        if !neighborhood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setTag(key: "neighborhood", value: neighborhood)
        }

        if !watchUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setTag(key: "watch_username", value: watchUsername)
        }

        if !fullName.isEmpty {
            setTag(key: "full_name", value: fullName)
        }
    }

    func handleNotificationOpen(userInfo: [AnyHashable: Any]) {
        lastNotificationPayload = userInfo

        guard let tab = Self.tabIndex(for: userInfo) else { return }
        pendingTabSelection = tab
        NotificationCenter.default.post(name: Notification.Name("openTab"), object: nil, userInfo: ["tab": tab])
    }

    func consumePendingNavigation() {
        pendingTabSelection = nil
    }
    
    /// Saves this device's OneSignal subscription ID to the user's Firestore document
    /// so other devices/users can send them push notifications without relying on Cloud Function queries
    func saveSubscriptionIdToFirestore(uid: String, subscriptionId: String) {
        FirebaseManager.shared.saveOneSignalSubscriptionId(uid: uid, subscriptionId: subscriptionId)
    }

    #if canImport(OneSignalFramework) && canImport(FirebaseAuth)
    private func persistCurrentSubscriptionIdIfPossible(uid: String? = nil, attempt: Int = 1, maxAttempts: Int = 5) {
        let resolvedUid = uid ?? Auth.auth().currentUser?.uid
        guard let resolvedUid else { return }

        let subscriptionId = (OneSignal.User.pushSubscription.id ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subscriptionId.isEmpty else {
            guard attempt < maxAttempts else {
                print("⚠️ OneSignal: Subscription ID still unavailable after \(maxAttempts) attempt(s)")
                return
            }

            let nextAttempt = attempt + 1
            let delaySeconds = Double(nextAttempt) * 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                self?.persistCurrentSubscriptionIdIfPossible(uid: resolvedUid, attempt: nextAttempt, maxAttempts: maxAttempts)
            }
            return
        }

        saveSubscriptionIdToFirestore(uid: resolvedUid, subscriptionId: subscriptionId)
    }
    #endif

    /// Debug function to log current OneSignal subscription status
    func logSubscriptionStatus() {
        #if canImport(OneSignalFramework)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 OneSignal Subscription Status Debug")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("External User ID: \(OneSignal.User.externalId ?? "❌ NOT SET")")
        print("Push Subscription ID: \(OneSignal.User.pushSubscription.id ?? "❌ NOT SET")")
        print("Push Token: \(OneSignal.User.pushSubscription.token ?? "❌ NOT SET")")
        print("Opted In: \(OneSignal.User.pushSubscription.optedIn ? "✅ YES" : "❌ NO")")
        print("Has Subscription: \(OneSignal.User.pushSubscription.id != nil ? "✅ YES" : "❌ NO")")
        
        // Check system notification settings
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("System Authorization: \(settings.authorizationStatus == .authorized ? "✅ Authorized" : "❌ Not Authorized (\(settings.authorizationStatus.rawValue))")")
                print("Alert Setting: \(settings.alertSetting == .enabled ? "✅ Enabled" : "❌ Disabled")")
                print("Badge Setting: \(settings.badgeSetting == .enabled ? "✅ Enabled" : "❌ Disabled")")
                print("Sound Setting: \(settings.soundSetting == .enabled ? "✅ Enabled" : "❌ Disabled")")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
        #else
        print("⚠️ OneSignal framework not available")
        #endif
    }
    
    /// Force login with Firebase UID - useful for debugging
    func forceLoginWithFirebaseUser() {
        #if canImport(OneSignalFramework) && canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            print("❌ Cannot force login: No Firebase user signed in")
            return
        }
        
        let uid = user.uid
        print("🔄 Force login with Firebase UID: \(uid)")
        
        // Clear any existing session first
        if OneSignal.User.externalId != nil {
            print("   Logging out current user: \(OneSignal.User.externalId!)")
            OneSignal.logout()
            
            // Wait a bit before logging in again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("   Logging in with UID: \(uid)")
                OneSignal.login(uid)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.logSubscriptionStatus()
                }
            }
        } else {
            OneSignal.login(uid)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.logSubscriptionStatus()
            }
        }
        #endif
    }

    func triggerFirstJourney() {
        defaults.set(true, forKey: welcomeDialogShownKey)
        showJourneyWelcomeDialog = false

        #if canImport(OneSignalFramework)
        OneSignal.InAppMessages.addTrigger("ai_implementation_campaign_email_journey", withValue: "true")
        #endif
    }

    private func presentWelcomeDialogIfNeeded() {
        let alreadyShown = defaults.bool(forKey: welcomeDialogShownKey)
        guard !alreadyShown else { return }
        showJourneyWelcomeDialog = true
    }

    private static func tabIndex(for userInfo: [AnyHashable: Any]) -> Int? {
        let candidates = notificationRouteCandidates(from: userInfo)

        for candidate in candidates {
            switch candidate {
            case "chat", "message", "messages", "communitychat":
                return 3
            case "event", "events", "calendar":
                return 1
            case "reportit", "report", "issue", "incident":
                return 2
            case "watch", "watchtab", "emergency", "emergencyalert", "safety":
                return 4
            case "home", "assistance", "marketplace", "listing", "subscription", "newsletter", "community":
                return 0
            default:
                continue
            }
        }

        return nil
    }

    private static func notificationRouteCandidates(from userInfo: [AnyHashable: Any]) -> [String] {
        var results: [String] = []

        func walk(_ value: Any) {
            if let string = value as? String {
                let normalized = string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "-", with: "")
                if !normalized.isEmpty {
                    results.append(normalized)
                }
            } else if let dictionary = value as? [AnyHashable: Any] {
                for key in ["route", "deepLink", "deep_link", "type", "notificationType", "screen", "target"] {
                    if let nested = dictionary[key] {
                        walk(nested)
                    }
                }

                for nested in dictionary.values {
                    walk(nested)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }

        walk(userInfo)
        return results
    }
}

#if canImport(OneSignalFramework)
private final class WelcomePushSubscriptionObserver: NSObject, OSPushSubscriptionObserver {
    private let onSubscribed: () -> Void

    init(onSubscribed: @escaping () -> Void) {
        self.onSubscribed = onSubscribed
        super.init()
    }

    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        let previousId = state.previous.id
        let currentId = state.current.id

        if (previousId == nil || previousId?.isEmpty == true),
           let currentId,
           !currentId.isEmpty {
            DispatchQueue.main.async { [onSubscribed] in
                onSubscribed()
            }
        }
    }
}
#endif
