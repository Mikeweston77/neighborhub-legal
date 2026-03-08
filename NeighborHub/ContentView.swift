import Combine
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// Local advert snippet is provided by `Views/AdvertSnippetRow.swift` to avoid duplication.

// MARK: - Notification Delegate for Tab Switching
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @Binding var selectedTab: Int
    init(selectedTab: Binding<Int>) {
        self._selectedTab = selectedTab
        super.init()
    }
    // Called when a notification is delivered while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.banner, .sound])
    }
    // Called when user taps a notification
    // Handle notification tap and switch to the correct tab
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let notificationType = userInfo["notificationType"] as? String {
            switch notificationType {
            case "chat":
                selectedTab = 3  // Chats tab
            case "reportit":
                selectedTab = 2  // Report It tab
            case "event":
                selectedTab = 1  // Events tab
            case "assistance":
                selectedTab = 0  // Home tab (assistance requests)
            default:
                break
            }
        } else {
            // Fallback for legacy or identifier-based notifications
            let id = response.notification.request.identifier
            if id.starts(with: "chat-") {
                selectedTab = 3  // Open chat tab (legacy)
            }
        }
        completionHandler()
    }
}

// DEPRECATED: Local helper for weather lookups - replaced by OpenWeatherMapService
// Keeping this commented out to prevent conflicts
/*
final class LocalWeatherHelper: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var locationName = "Your Location"

    private let weatherURL = "https://api.openweathermap.org/data/2.5/weather"
    private let openWeatherMapAPIKey = "REDACTED" // OpenWeatherMap API key
    let locationManager = WeatherLocationManager()

    init() {
        setupLocationObserver()
        loadWeatherData()
    }

    private func setupLocationObserver() {
        // Observe location changes
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.loadWeatherForLocation(location)
            }
            .store(in: &cancellables)

        locationManager.$currentCity
            .sink { [weak self] city in
                self?.locationName = city
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func loadWeatherData() {
        // Request location permissions first
        locationManager.requestWhenInUse()

        // Start continuous location tracking for accurate weather
        locationManager.startLocationUpdates()

        // Only load weather if we have a current location
        if let location = locationManager.currentLocation {
            loadWeatherForLocation(location)
        }
    }

    private func loadWeatherForLocation(_ location: CLLocation) {
        isLoading = true
        errorMessage = nil

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        // Construct URL for OpenWeatherMap weather only
        let weatherParams = "lat=\(lat)&lon=\(lon)&appid=\(openWeatherMapAPIKey)&units=metric"

        guard let weatherUrl = URL(string: "\(weatherURL)?\(weatherParams)") else {
            self.errorMessage = "Invalid API URL"
            self.isLoading = false
            return
        }

        Task {
            do {
                // Fetch weather data
                let (weatherData, _) = try await URLSession.shared.data(from: weatherUrl)

                // Decode response
                let weatherResponse = try JSONDecoder().decode(OpenWeatherMapResponse.self, from: weatherData)
                // Update minimal UI state from the response on the main thread
                DispatchQueue.main.async {
                    // If the API provides a city/name use it for the location display
                    if let name = weatherResponse.name, !name.isEmpty {
                        self.locationName = name
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode weather data"
                    self.isLoading = false
                }
            }
        }
    }

}
*/

// MARK: - New Post View
struct NewPostView: View {
    var body: some View {
        NavigationView {
            Form {
                // Post content section
                Section(header: Text("Post Content")) {
                    TextEditor(text: .constant(""))
                        .frame(height: 200)
                        .padding(8)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

                    Button(action: {
                        // Action for posting
                    }) {
                        Text("Post")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                }

                // Media attachment section
                Section(header: Text("Attach Media")) {
                    HStack {
                        Spacer()
                        Button(action: {
                            // Action for adding photo
                        }) {
                            Image(systemName: "photo.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Button(action: {
                            // Action for adding video
                        }) {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }

                        Spacer()
                    }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Neighborhood Watch View
struct NeighborhoodWatchView: View {
    var body: some View {
        VStack {
            Text("Neighbourhood Watch")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 32)

            Text("Feature coming soon...")
                .foregroundColor(.secondary)
                .font(.title3)
                .padding(.top, 8)

            Spacer()
        }
        .padding()
        .navigationTitle("Neighborhood Watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Marketplace View
struct MarketplaceView: View {
    var body: some View {
        NavigationView {
            List {
                // Sample marketplace items
                ForEach(0..<20) { index in
                    HStack {
                        Image(systemName: "bag.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color.blue.opacity(0.1), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Item Title \(index + 1)")
                                .fontWeight(.bold)

                            Text("Description of item \(index + 1).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("$\(index * 10 + 9).99")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Shared struct for registered users
struct RegisteredUser: Identifiable, Equatable {
    let id: String  // Firebase Auth UID (unique identifier)
    let name: String
    let email: String  // User's email address
    let street: String
    let suburb: String
    let city: String
    let postalCode: String
    let cell: String
    // Emergency contact details
    let emergencyContactName: String
    let emergencyContactPhone: String
    let emergencyContactRelationship: String
    // Verification and profile
    let isVerified: Bool
    let joinedDate: Date?
    let profileImageURL: String?
    // Role flags
    let isAdmin: Bool
    let isCommittee: Bool
    let hasCameraAccess: Bool
    // Camera access request fields
    let cameraAccessRequested: Bool
    let watchCredential: String?

    var display: String {
        "\(name), \(email), \(street), \(suburb), \(city), \(postalCode), \(cell) — Emergency: \(emergencyContactName) (\(emergencyContactPhone))"
    }
    
    var isPending: Bool {
        !isVerified
    }
}

// MARK: - Watch Tab with Admin Settings
struct WatchTabWithAdminSettings: View {
    @State private var expandedUserIDs: Set<String> = []
    // Helper to compute initials
    var initials: String {
        let first =
            userName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? ""
        let last =
            userSurname.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) }
            ?? ""
        return (first + last).uppercased()
    }

    // Helper to check if current user is a committee member by full first name and full surname
    var isCommitteeMemberByName: Bool {
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameFull = userSurname.trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
        let members = committeeMembers.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces).capitalized
        }

        for member in members {
            let comps = member.split(separator: " ").map {
                String($0).trimmingCharacters(in: .whitespaces).capitalized
            }
            guard let first = comps.first else { continue }

            if comps.count > 1 {
                let last = comps.dropFirst().joined(separator: " ")
                if userFirst == first && userSurnameFull == last {
                    return true
                }
            } else if comps.count == 1 {
                // Handle single name matches
                if userFirst == first && userSurnameFull.isEmpty {
                    return true
                }
            }
        }
        return false
    }

    // Helper to check privacy consent status for a user
    private func getPrivacyConsentStatus(for userEmail: String) -> Bool {
        return UserDefaults.standard.object(forKey: "userPrivacyShareWithCommunity_\(userEmail)")
            as? Bool ?? true
    }

    // Static helper for camera user unlock logic
    static func getCameraUserList() -> [String] {
        let users = UserDefaults.standard.string(forKey: "cameraUsers") ?? ""
        return users.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
    }
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
    @AppStorage("profileImageURL") private var profileImageURL: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    @AppStorage("cameraUsers") private var cameraUsers: String = ""
    @AppStorage("registeredUsers") private var registeredUsers: String = ""
    // Privacy settings for filtering user visibility
    @AppStorage("userPrivacyShareWithCommunity") private var userPrivacyShareWithCommunity: Bool =
        true
    @AppStorage("userPrivacyShareWithCommittee") private var userPrivacyShareWithCommittee: Bool =
        true
    @EnvironmentObject var appState: AppState
    // Local state for editing, search, and disclosure
    @State private var editCommitteeMembers: String = ""
    @State private var editCameraUsers: String = ""
    @State private var cameraUserSearch: String = ""
    @State private var registeredUserSearch: String = ""
    @State private var committeeSearch: String = ""
    @State private var showAdminSection = false
    @State private var showCameraSection = false
    @State private var showUserListSection = false
    @State private var showSettings = false
    @State private var showSubscriptionTracker = false
    
    // Camera migration states
    @State private var isMigrating = false
    @State private var migrationResult: (granted: Int, notFound: [String], conflicts: [String: [[String: String]]])? = nil
    @State private var showConflictResolutionSheet = false

    // Confirmation dialog states
    @State private var showDeleteCommitteeConfirmation = false
    @State private var showDeleteCameraUserConfirmation = false
    @State private var showDeleteRegisteredUserConfirmation = false
    @State private var committeeToDelete: String = ""
    @State private var cameraUserToDelete: String = ""
    @State private var registeredUserToDelete: RegisteredUser?
    
    // Role assignment state for user approval
    @State private var showRoleSelectionSheet = false
    @State private var userToApprove: RegisteredUser?
    @State private var approveAsAdmin = false
    @State private var approveAsCommittee = false
    
    // Firestore-backed registered users (preferred). If empty, UI will fall back to AppStorage string.
    @State private var firestoreRegisteredUsers: [RegisteredUser] = []
    @State private var registeredUsersListener: ListenerRegistration? = nil
    
    // Real-time listener for current user's role changes
    @State private var currentUserRolesListener: ListenerRegistration? = nil

    // Edit this list in code to change the default committee members
    static let defaultCommitteeMembers = [
        "Mike W",
        "Brendan B",
        "Janine B",
        "Riette W",
    ]

    // On appear, set default if empty
    private func initializeCommitteeMembersIfNeeded() {
        if committeeMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            committeeMembers = Self.defaultCommitteeMembers.joined(separator: ", ")
        }
    }

    // Helper to get/set committee members as array
    var committeeList: [String] {
        (editCommitteeMembers.isEmpty ? committeeMembers : editCommitteeMembers)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
                !$0.isEmpty
            }
    }
    // Helper to get/set camera users as array
    var cameraUserList: [String] {
        (editCameraUsers.isEmpty ? cameraUsers : editCameraUsers)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
                !$0.isEmpty
            }
    }
    // Prefer Firestore data when available, otherwise use the local AppStorage string
    var registeredUserList: [RegisteredUser] {
        if !firestoreRegisteredUsers.isEmpty { return firestoreRegisteredUsers }
        return registeredUsers.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0)
            }
            // support legacy 7-field and extended 10-field (AppStorage doesn't have verification info)
            if parts.count == 7 {
                return RegisteredUser(
                    id: parts[0],
                    name: parts[1],
                    email: "",  // Legacy data doesn't have email
                    street: parts[2],
                    suburb: parts[3],
                    city: parts[4],
                    postalCode: parts[5],
                    cell: parts[6],
                    emergencyContactName: "",
                    emergencyContactPhone: "",
                    emergencyContactRelationship: "",
                    isVerified: false,  // Legacy data not verified
                    joinedDate: nil,
                    profileImageURL: nil,
                    isAdmin: false,
                    isCommittee: false,
                    hasCameraAccess: false,
                    cameraAccessRequested: false,
                    watchCredential: nil
                )
            } else if parts.count == 10 {
                return RegisteredUser(
                    id: parts[0],
                    name: parts[1],
                    email: "",  // Legacy data doesn't have email
                    street: parts[2],
                    suburb: parts[3],
                    city: parts[4],
                    postalCode: parts[5],
                    cell: parts[6],
                    emergencyContactName: parts[7],
                    emergencyContactPhone: parts[8],
                    emergencyContactRelationship: parts[9],
                    isVerified: false,  // Legacy data not verified
                    joinedDate: nil,
                    profileImageURL: nil,
                    isAdmin: false,
                    isCommittee: false,
                    hasCameraAccess: false,
                    cameraAccessRequested: false,
                    watchCredential: nil
                )
            } else {
                return nil
            }
        }
    }

    // Start listening to Firestore `users` collection (writes into `firestoreRegisteredUsers`).
    private func startWatchingRegisteredUsers() {
        stopWatchingRegisteredUsers()
        print("🔍 Starting Firestore listener for registered users...")
        registeredUsersListener = FirebaseManager.shared.watchRegisteredUsers(onlyVerified: false) { docs in
            print("📥 Received \(docs.count) user documents from Firestore")
            
            let mapped: [RegisteredUser] = docs.compactMap { d in
                let uid = (d["uid"] as? String) ?? (d["email"] as? String) ?? ""
                let email = (d["email"] as? String) ?? ""
                let first = (d["firstName"] as? String) ?? ""
                let last = (d["lastName"] as? String) ?? ""
                let street = (d["street"] as? String) ?? ""
                let suburb = (d["suburb"] as? String) ?? ""
                let city = (d["city"] as? String) ?? ""
                let postal = (d["postalCode"] as? String) ?? ""
                let phone = (d["phone"] as? String) ?? ""
                let emName = (d["emergencyContactName"] as? String) ?? ""
                let emPhone = (d["emergencyContactPhone"] as? String) ?? ""
                let emRel = (d["emergencyContactRelationship"] as? String) ?? ""
                let verified = (d["verified"] as? Bool) ?? false
                let profileURL = (d["profileImageURL"] as? String) ?? ""
                let isAdmin = (d["isAdmin"] as? Bool) ?? false
                let isCommittee = (d["isCommittee"] as? Bool) ?? false
                let hasCameraAccess = (d["cameraAccess"] as? Bool) ?? false
                let cameraAccessRequested = (d["cameraAccessRequested"] as? Bool) ?? false
                let watchCredential = (d["watchCredential"] as? String)
                let name = [first, last].filter({ !$0.isEmpty }).joined(separator: " ")
                
                // Cache current user's profile image URL to AppStorage
                if uid == Auth.auth().currentUser?.uid, !profileURL.isEmpty {
                    self.profileImageURL = profileURL
                }
                
                print("   👤 User: \(name) (\(uid)) - Email: \(email) - Verified: \(verified)")
                if cameraAccessRequested {
                    print("      📹 Camera access requested with watch username: \(watchCredential ?? "N/A")")
                }
                
                // Parse joinedDate
                var joinedDate: Date?
                if let timestamp = d["createdAt"] as? Timestamp {
                    joinedDate = timestamp.dateValue()
                } else if let timestamp = d["joinedDate"] as? Timestamp {
                    joinedDate = timestamp.dateValue()
                }
                
                return RegisteredUser(
                    id: uid,
                    name: name,
                    email: email,
                    street: street,
                    suburb: suburb,
                    city: city,
                    postalCode: postal,
                    cell: phone,
                    emergencyContactName: emName,
                    emergencyContactPhone: emPhone,
                    emergencyContactRelationship: emRel,
                    isVerified: verified,
                    joinedDate: joinedDate,
                    profileImageURL: profileURL.isEmpty ? nil : profileURL,
                    isAdmin: isAdmin,
                    isCommittee: isCommittee,
                    hasCameraAccess: hasCameraAccess,
                    cameraAccessRequested: cameraAccessRequested,
                    watchCredential: watchCredential
                )
            }
            
            print("✅ Mapped \(mapped.count) users successfully")
            print("   Pending: \(mapped.filter { !$0.isVerified }.count)")
            print("   Approved: \(mapped.filter { $0.isVerified }.count)")
            
            DispatchQueue.main.async { 
                self.firestoreRegisteredUsers = mapped
                print("📊 Updated firestoreRegisteredUsers array with \(mapped.count) users")
            }
        }
    }

    private func stopWatchingRegisteredUsers() {
        registeredUsersListener?.remove()
        registeredUsersListener = nil
    }
    
    // MARK: - Real-time Role Monitoring
    
    /// Start watching current user's document for role changes
    private func startWatchingCurrentUserRoles() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot watch roles - user not logged in")
            return
        }
        
        stopWatchingCurrentUserRoles()
        
        print("👀 Starting real-time listener for user roles (UID: \(uid))")
        
        currentUserRolesListener = Firestore.firestore().collection("users").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error watching user roles: \(error.localizedDescription)")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("⚠️ No data in user document")
                    return
                }
                
                let newIsAdmin = data["isAdmin"] as? Bool ?? false
                let newIsCommittee = data["isCommittee"] as? Bool ?? false
                let newHasCameraAccess = data["cameraAccess"] as? Bool ?? false
                
                // Check if roles changed
                let oldIsAdmin = self.userIsAdmin
                let oldIsCommittee = self.userIsCommittee
                let oldHasCameraAccess = self.userHasCameraAccess
                
                if newIsAdmin != oldIsAdmin || newIsCommittee != oldIsCommittee || newHasCameraAccess != oldHasCameraAccess {
                    print("🔄 Role change detected!")
                    print("   Admin: \(oldIsAdmin) → \(newIsAdmin)")
                    print("   Committee: \(oldIsCommittee) → \(newIsCommittee)")
                    print("   Camera Access: \(oldHasCameraAccess) → \(newHasCameraAccess)")
                } else {
                    print("✓ Syncing roles from Firestore - Admin: \(newIsAdmin), Committee: \(newIsCommittee), Camera: \(newHasCameraAccess)")
                }
                
                // ALWAYS update cached values from Firestore (source of truth)
                // This ensures roles sync even if user restarts app after being promoted
                DispatchQueue.main.async {
                    self.userIsAdmin = newIsAdmin
                    self.userIsCommittee = newIsCommittee
                    self.userHasCameraAccess = newHasCameraAccess
                    print("✅ Roles synced from Firestore - Admin: \(newIsAdmin), Committee: \(newIsCommittee), Camera: \(newHasCameraAccess)")
                }
            }
    }
    
    /// Stop watching current user's roles
    private func stopWatchingCurrentUserRoles() {
        currentUserRolesListener?.remove()
        currentUserRolesListener = nil
    }
    
    @AppStorage("emergencyContactName") private var emergencyContactName: String = ""
    @AppStorage("emergencyContactPhone") private var emergencyContactPhone: String = ""
    @AppStorage("emergencyContactRelationship") private var emergencyContactRelationship: String =
        ""
    
    // Cached admin/committee/camera status from Firestore
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    @AppStorage("userHasCameraAccess") private var userHasCameraAccess: Bool = false

    // Check if current user is a committee member or admin (Firestore-based)
    var isCommitteeMember: Bool {
        // Primary check: Firestore roles (cached in UserDefaults)
        if userIsAdmin || userIsCommittee {
            return true
        }
        
        // Legacy fallback: name-based check (for backward compatibility during migration)
        return isCommitteeMemberByName_Legacy
    }
    
    // LEGACY: Name-based committee check (kept for backward compatibility)
    private var isCommitteeMemberByName_Legacy: Bool {
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameFull = userSurname.trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
        let members = committeeMembers.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces).capitalized
        }

        for member in members {
            let comps = member.split(separator: " ").map {
                String($0).trimmingCharacters(in: .whitespaces).capitalized
            }
            guard let first = comps.first else { continue }

            if comps.count > 1 {
                let last = comps.dropFirst().joined(separator: " ")
                if userFirst == first && userSurnameFull == last {
                    return true
                }
            } else if comps.count == 1 {
                // Handle single name matches
                if userFirst == first && userSurnameFull.isEmpty {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Camera Access Check (Firestore-based, UID-secured)
    @AppStorage("watchUsername") private var watchUsername: String = ""
    var isCameraUser: Bool {
        // Primary check: Firestore cameraAccess field (cached in UserDefaults)
        if userHasCameraAccess {
            return true
        }
        
        // Legacy fallback: username string matching (for backward compatibility during migration)
        return isCameraUserByName_Legacy
    }
    
    // LEGACY: Name-based camera access check (kept for backward compatibility)
    private var isCameraUserByName_Legacy: Bool {
        let userWatchUsername = watchUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        for cameraUser in cameraUserList {
            if cameraUser.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                userWatchUsername) == .orderedSame
            {
                return true
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isCameraUser {
                    WatchView()
                } else {
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.gray)
                        Text("Access Restricted")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(
                            "You are not an authorized camera user. Please contact an admin to request access."
                        )
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        Spacer()
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Use Firestore roles (not legacy name-based check)
                    if isCommitteeMember {
                        Button(action: { showSettings = true }) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .shadow(
                                        color: Color.accentColor.opacity(0.25), radius: 8, x: 0,
                                        y: 4)
                                Text(initials)
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .accessibilityLabel("Settings")
                    }
                    // If not a committee member, do not show any button or icon
                }
            }
        }
        .onAppear {
            initializeCommitteeMembersIfNeeded()
            // Start watching for real-time role changes
            startWatchingCurrentUserRoles()
        }
        .onDisappear {
            // Clean up role listener when view disappears
            stopWatchingCurrentUserRoles()
        }
        .sheet(isPresented: $showSettings) {
            AdminPanelView()
        }
    }
    // Filtered lists for search
    var filteredCameraUserList: [String] {
        let list = cameraUserList
        if cameraUserSearch.isEmpty { return list }
        return list.filter { $0.localizedCaseInsensitiveContains(cameraUserSearch) }
    }
    var filteredRegisteredUserList: [RegisteredUser] {
        // Admins should see all users regardless of privacy settings
        let isAdmin = userIsAdmin || isCommitteeMember
        
        // First filter by privacy settings - only show users who have consented to share their details
        let privacyFilteredUsers = registeredUserList.compactMap { user -> RegisteredUser? in
            // Admins bypass privacy filtering
            if isAdmin {
                return user
            }
            
            // Get privacy settings for each user (this is a simplified approach)
            // In a real implementation, you'd need a way to store per-user privacy settings
            // For now, we'll use a UserDefaults lookup based on user UID
            let userShareWithCommunity =
                UserDefaults.standard.object(forKey: "userPrivacyShareWithCommunity_\(user.id)")
                as? Bool ?? true
            let userShareWithCommittee =
                UserDefaults.standard.object(forKey: "userPrivacyShareWithCommittee_\(user.id)")
                as? Bool ?? true

            // Determine if current viewer is a committee member
            let currentUserIsCommittee = isCommitteeMember

            // Show user if they consent to share with community, or if they consent to share with committee and viewer is committee
            if userShareWithCommunity || (userShareWithCommittee && currentUserIsCommittee) {
                return user
            } else {
                // Return anonymous user data if no consent
                return RegisteredUser(
                    id: user.id,
                    name: "Private User",
                    email: "Hidden",
                    street: "Hidden",
                    suburb: "Hidden",
                    city: "Hidden",
                    postalCode: "Hidden",
                    cell: "Hidden",
                    emergencyContactName: "",
                    emergencyContactPhone: "",
                    emergencyContactRelationship: "",
                    isVerified: user.isVerified,
                    joinedDate: user.joinedDate,
                    profileImageURL: nil,
                    isAdmin: user.isAdmin,
                    isCommittee: user.isCommittee,
                    hasCameraAccess: user.hasCameraAccess,
                    cameraAccessRequested: user.cameraAccessRequested,
                    watchCredential: user.watchCredential
                )
            }
        }

        // Then apply search filter
        if registeredUserSearch.isEmpty {
            return privacyFilteredUsers
        }
        return privacyFilteredUsers.filter {
            $0.name.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.street.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.suburb.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.city.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.postalCode.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.cell.localizedCaseInsensitiveContains(registeredUserSearch)
                || $0.id.localizedCaseInsensitiveContains(registeredUserSearch)
        }
    }
    
    // Separate pending and approved users
    var pendingUsers: [RegisteredUser] {
        let pending = filteredRegisteredUserList.filter { !$0.isVerified }
        print("📋 Pending users count: \(pending.count)")
        return pending
    }
    
    var approvedUsers: [RegisteredUser] {
        let approved = filteredRegisteredUserList.filter { $0.isVerified }
        print("📋 Approved users count: \(approved.count)")
        return approved
    }
    
    // Users with pending camera access requests (verified users who have submitted credentials)
    var pendingCameraAccessRequests: [RegisteredUser] {
        let requests = firestoreRegisteredUsers.filter { user in
            user.isVerified && user.cameraAccessRequested && !user.hasCameraAccess
        }
        
        // Apply search filter
        if cameraUserSearch.isEmpty {
            return requests
        }
        return requests.filter {
            $0.name.localizedCaseInsensitiveContains(cameraUserSearch) ||
            $0.watchCredential?.localizedCaseInsensitiveContains(cameraUserSearch) == true ||
            $0.email.localizedCaseInsensitiveContains(cameraUserSearch)
        }
    }
    
    // Admin and committee users (verified users with special roles)
    var adminUsers: [RegisteredUser] {
        let allUsers = registeredUserList.filter { $0.isVerified }
        
        // Get admin status from Firestore (needs to be cached in RegisteredUser or queried separately)
        // For now, we'll filter based on the firestoreRegisteredUsers which should have role data
        let admins = firestoreRegisteredUsers.filter { user in
            user.isVerified && user.isAdmin
        }
        
        // Apply search filter
        if committeeSearch.isEmpty {
            return admins
        }
        return admins.filter {
            $0.name.localizedCaseInsensitiveContains(committeeSearch) ||
            $0.street.localizedCaseInsensitiveContains(committeeSearch) ||
            $0.email.localizedCaseInsensitiveContains(committeeSearch)
        }
    }
    
    var committeeOnlyUsers: [RegisteredUser] {
        // Committee members who are NOT admins
        let committeeOnly = firestoreRegisteredUsers.filter { user in
            user.isVerified && user.isCommittee && !user.isAdmin
        }
        
        // Apply search filter
        if committeeSearch.isEmpty {
            return committeeOnly
        }
        return committeeOnly.filter {
            $0.name.localizedCaseInsensitiveContains(committeeSearch) ||
            $0.street.localizedCaseInsensitiveContains(committeeSearch) ||
            $0.email.localizedCaseInsensitiveContains(committeeSearch)
        }
    }
    
    // Combined list: all users with committee or admin access, sorted by role (admins first)
    var allCommitteeMembers: [RegisteredUser] {
        let members = firestoreRegisteredUsers.filter { user in
            user.isVerified && (user.isCommittee || user.isAdmin)
        }
        
        // Apply search filter
        let filtered: [RegisteredUser]
        if committeeSearch.isEmpty {
            filtered = members
        } else {
            filtered = members.filter {
                $0.name.localizedCaseInsensitiveContains(committeeSearch) ||
                $0.street.localizedCaseInsensitiveContains(committeeSearch) ||
                $0.email.localizedCaseInsensitiveContains(committeeSearch)
            }
        }
        
        // Sort: Admins first, then committee members, then by name
        return filtered.sorted { user1, user2 in
            if user1.isAdmin && !user2.isAdmin {
                return true
            } else if !user1.isAdmin && user2.isAdmin {
                return false
            } else {
                return user1.name < user2.name
            }
        }
    }

    // Committee member management functions
    func requestDeleteCommitteeMember(_ name: String) {
        committeeToDelete = name
        showDeleteCommitteeConfirmation = true
    }

    private func confirmDeleteCommitteeMember() {
        var members = committeeList
        members.removeAll {
            $0.trimmingCharacters(in: .whitespaces)
                == committeeToDelete.trimmingCharacters(in: .whitespaces)
        }
        editCommitteeMembers = members.joined(separator: ", ")
        committeeMembers = editCommitteeMembers
        committeeToDelete = ""
    }

    // MARK: - Camera Access Management (UID-based, Firestore-backed)
    
    /// Toggle committee/admin access - unified toggle that controls both roles
    func toggleCommitteeAccess(for user: RegisteredUser, granted: Bool) {
        if granted {
            // Grant committee access (and optionally admin if they already have it)
            FirebaseManager.shared.updateCommitteeRole(uid: user.id, granted: true) { result in
                switch result {
                case .success:
                    print("✅ Committee access granted to \(user.name) (UID: \(user.id))")
                case .failure(let error):
                    print("❌ Failed to grant committee access to \(user.name): \(error.localizedDescription)")
                }
            }
        } else {
            // Revoke both admin and committee access
            FirebaseManager.shared.updateAdminRole(uid: user.id, granted: false) { _ in }
            FirebaseManager.shared.updateCommitteeRole(uid: user.id, granted: false) { result in
                switch result {
                case .success:
                    print("✅ Committee access revoked from \(user.name) (UID: \(user.id))")
                case .failure(let error):
                    print("❌ Failed to revoke committee access from \(user.name): \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Toggle camera access for a specific user
    func toggleCameraAccess(for user: RegisteredUser, granted: Bool) {
        FirebaseManager.shared.updateCameraAccess(uid: user.id, granted: granted) { result in
            switch result {
            case .success:
                print("✅ Camera access \(granted ? "granted to" : "revoked from") \(user.name) (UID: \(user.id))")
            case .failure(let error):
                print("❌ Failed to update camera access for \(user.name): \(error.localizedDescription)")
            }
        }
    }
    
    /// Toggle admin role for a specific user
    func toggleAdminRole(for user: RegisteredUser, granted: Bool) {
        FirebaseManager.shared.updateAdminRole(uid: user.id, granted: granted) { result in
            switch result {
            case .success:
                print("✅ Admin role \(granted ? "granted to" : "revoked from") \(user.name) (UID: \(user.id))")
            case .failure(let error):
                print("❌ Failed to update admin role for \(user.name): \(error.localizedDescription)")
            }
        }
    }
    
    /// Toggle committee role for a specific user
    func toggleCommitteeRole(for user: RegisteredUser, granted: Bool) {
        FirebaseManager.shared.updateCommitteeRole(uid: user.id, granted: granted) { result in
            switch result {
            case .success:
                print("✅ Committee role \(granted ? "granted to" : "revoked from") \(user.name) (UID: \(user.id))")
            case .failure(let error):
                print("❌ Failed to update committee role for \(user.name): \(error.localizedDescription)")
            }
        }
    }
    
    // LEGACY: Old string-based camera management (deprecated, kept for migration compatibility)
    func inviteCameraUser() {
        print("⚠️ DEPRECATED: Use toggleCameraAccess(for:granted:) instead")
    }

    func approveCameraUser(_ name: String) {
        print("⚠️ DEPRECATED: Use toggleCameraAccess(for:granted:) instead")
    }

    func requestDeleteCameraUser(_ name: String) {
        cameraUserToDelete = name
        showDeleteCameraUserConfirmation = true
    }

    private func confirmDeleteCameraUser() {
        var users = cameraUserList
        users.removeAll {
            $0.trimmingCharacters(in: .whitespaces)
                == cameraUserToDelete.trimmingCharacters(in: .whitespaces)
        }
        editCameraUsers = users.joined(separator: ", ")
        cameraUsers = editCameraUsers
        cameraUserToDelete = ""
    }
    
    // Migration function for legacy camera users
    private func migrateLegacyCameraUsers() {
        guard !isMigrating else { return }
        
        isMigrating = true
        migrationResult = nil
        
        // Get legacy user names from @AppStorage
        let legacyNames = cameraUserList
        
        guard !legacyNames.isEmpty else {
            print("⚠️ No legacy camera users to migrate")
            isMigrating = false
            return
        }
        
        print("🔄 Starting migration for \(legacyNames.count) legacy camera users...")
        
        FirebaseManager.shared.migrateLegacyCameraUsers(legacyUsernames: legacyNames) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let migrationData):
                    self.migrationResult = migrationData
                    self.isMigrating = false
                    
                    print("✅ Migration complete: \(migrationData.granted) granted, \(migrationData.notFound.count) not found, \(migrationData.conflicts.count) conflicts")
                    
                    // If all users were successfully migrated (no conflicts or not found), clear the legacy list
                    if migrationData.notFound.isEmpty && migrationData.conflicts.isEmpty && migrationData.granted > 0 {
                        print("🎉 All users successfully migrated! Clearing legacy camera users list...")
                        self.cameraUsers = ""
                        self.editCameraUsers = ""
                    } else if migrationData.granted > 0 {
                        // Partial success - remove the successfully migrated users from the legacy list
                        print("⚙️ Partial migration - removing successfully migrated users from legacy list...")
                        
                        // Keep only the users that weren't found or have conflicts
                        var usersToKeep: [String] = []
                        usersToKeep.append(contentsOf: migrationData.notFound)
                        usersToKeep.append(contentsOf: migrationData.conflicts.keys)
                        
                        if !usersToKeep.isEmpty {
                            self.cameraUsers = usersToKeep.joined(separator: ", ")
                            self.editCameraUsers = self.cameraUsers
                            print("   Kept in legacy list: \(usersToKeep.joined(separator: ", "))")
                        } else {
                            self.cameraUsers = ""
                            self.editCameraUsers = ""
                            print("   Legacy list cleared - all migrated!")
                        }
                    }
                    
                    if !migrationData.notFound.isEmpty {
                        print("⚠️ Users not found in Firestore: \(migrationData.notFound.joined(separator: ", "))")
                    }
                    
                    if !migrationData.conflicts.isEmpty {
                        print("⚠️ Conflicts requiring manual selection:")
                        for (legacyName, matches) in migrationData.conflicts {
                            print("   '\(legacyName)' → \(matches.count) possible users")
                        }
                    }
                    
                case .failure(let error):
                    print("❌ Migration failed: \(error.localizedDescription)")
                    self.isMigrating = false
                }
            }
        }
    }
    
    // Manual conflict resolution - grant access to selected user
    private func resolveConflict(legacyUsername: String, selectedUID: String) {
        FirebaseManager.shared.updateCameraAccess(uid: selectedUID, granted: true) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Conflict resolved: '\(legacyUsername)' → UID: \(selectedUID)")
                    
                    // Update migration result to remove this conflict and increment granted count
                    if var result = self.migrationResult {
                        result.conflicts.removeValue(forKey: legacyUsername)
                        let newGranted = result.granted + 1
                        self.migrationResult = (granted: newGranted, notFound: result.notFound, conflicts: result.conflicts)
                    }
                    
                case .failure(let error):
                    print("❌ Failed to resolve conflict: \(error.localizedDescription)")
                }
            }
        }
    }

    // Registered user management functions
    func approveRegisteredUser(_ user: RegisteredUser) {
        guard !user.isVerified else {
            print("User \(user.name) is already verified")
            return
        }
        
        // Show role selection sheet
        userToApprove = user
        approveAsAdmin = false
        approveAsCommittee = false
        showRoleSelectionSheet = true
    }
    
    private func confirmApproveUser() {
        guard let user = userToApprove else { return }
        
        // Use role-based approval if any roles selected
        if approveAsAdmin || approveAsCommittee {
            FirebaseManager.shared.approveUserWithRole(
                uid: user.id,
                asAdmin: approveAsAdmin,
                asCommittee: approveAsCommittee
            ) { result in
                switch result {
                case .success:
                    let roles = [
                        approveAsAdmin ? "Admin" : nil,
                        approveAsCommittee ? "Committee" : nil
                    ].compactMap { $0 }.joined(separator: ", ")
                    print("✅ Successfully approved \(user.name) as \(roles.isEmpty ? "Regular User" : roles)")
                case .failure(let error):
                    print("❌ Failed to approve user \(user.name): \(error.localizedDescription)")
                }
            }
        } else {
            // Standard approval (regular user)
            FirebaseManager.shared.approveUser(uid: user.id) { result in
                switch result {
                case .success:
                    print("✅ Successfully approved user: \(user.name) (UID: \(user.id)) as Regular User")
                case .failure(let error):
                    print("❌ Failed to approve user \(user.name): \(error.localizedDescription)")
                }
            }
        }
        
        userToApprove = nil
        showRoleSelectionSheet = false
    }
    
    // MARK: - Camera Access Request Management
    
    func rejectCameraRequest(for user: RegisteredUser) {
        // Update Firestore to clear the camera request flag
        Firestore.firestore().collection("users").document(user.id).updateData([
            "cameraAccessRequested": false,
            "cameraAccessRejectedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ Failed to reject camera request for \(user.name): \(error.localizedDescription)")
            } else {
                print("✅ Rejected camera access request from \(user.name) (UID: \(user.id))")
            }
        }
    }
    
    func rejectRegisteredUser(_ user: RegisteredUser) {
        guard !user.isVerified else {
            print("Cannot reject already verified user: \(user.name)")
            return
        }
        
        // Update Firestore to mark user as rejected (using UID)
        FirebaseManager.shared.rejectUser(uid: user.id) { result in
            switch result {
            case .success:
                print("✅ Successfully rejected user: \(user.name) (UID: \(user.id))")
                // The Firestore listener will automatically update the UI
            case .failure(let error):
                print("❌ Failed to reject user \(user.name): \(error.localizedDescription)")
            }
        }
    }

    func requestDeleteRegisteredUser(_ user: RegisteredUser) {
        registeredUserToDelete = user
        showDeleteRegisteredUserConfirmation = true
    }

    private func confirmDeleteRegisteredUser() {
        guard let userToDelete = registeredUserToDelete else { return }
        
        // Delete user from Firestore (using UID)
        FirebaseManager.shared.deleteUser(uid: userToDelete.id) { result in
            switch result {
            case .success:
                print("✅ Successfully deleted user: \(userToDelete.name) (UID: \(userToDelete.id))")
                // The Firestore listener will automatically update the UI
            case .failure(let error):
                print("❌ Failed to delete user \(userToDelete.name): \(error.localizedDescription)")
            }
        }
        
        registeredUserToDelete = nil
    }
    
    private func confirmDeleteRegisteredUser_Legacy() {
        guard let userToDelete = registeredUserToDelete else { return }

        var userList = registeredUserList
        userList.removeAll { $0.id == userToDelete.id }

        // Convert back to string format for storage
        let userStrings = userList.map { user in
            [
                user.id,
                user.name,
                user.street,
                user.suburb,
                user.city,
                user.postalCode,
                user.cell,
                user.emergencyContactName,
                user.emergencyContactPhone,
                user.emergencyContactRelationship,
            ].joined(separator: "|")
        }
        registeredUsers = userStrings.joined(separator: ";")
        registeredUserToDelete = nil
    }

    func sendInvitations() {
        // Could implement email/SMS invitation system
        // For now, show a simple alert or print
        print("Sending invitations to new users...")
    }
}

// MARK: - Watch User Row View Component (for Watch Admin Panel)
struct WatchUserRowView: View {
    let user: RegisteredUser
    let isExpanded: Bool
    let privacyStatus: Bool
    @Binding var expandedUserIDs: Set<String>
    let emergencyContactName: String
    let emergencyContactPhone: String
    let emergencyContactRelationship: String
    let userEmail: String
    let isPending: Bool
    let onApprove: (() -> Void)?
    let onReject: (() -> Void)?
    let onDelete: () -> Void
    let onToggleExpand: () -> Void
    let onToggleCameraAccess: ((Bool) -> Void)?
    let onToggleCommittee: ((Bool) -> Void)?
    let onToggleAdmin: ((Bool) -> Void)?
    
    @State private var hasCameraAccess: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // Profile picture or colored initials
                if let imageURL = user.profileImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    // Color based on verification status
                    let backgroundColor = user.isVerified ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)
                    let foregroundColor = user.isVerified ? Color.green : Color.orange
                    
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(user.name.prefix(2).uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(foregroundColor)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        // Verification badge
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        Text(user.name).font(.body).bold()
                        Text("(")
                            + Text(user.street).font(.caption)
                            + Text(")")
                    }
                    // Privacy consent indicators
                    PrivacyStatusView(privacyStatus: privacyStatus)
                }
                Spacer()
                
                // Action buttons
                if isPending, let onApprove = onApprove {
                    Button(action: onApprove) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if isPending, let onReject = onReject {
                    Button(action: onReject) {
                        Image(systemName: "x.circle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onToggleExpand) {
                    Image(
                        systemName: isExpanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Street: \(user.street)").font(.caption)
                    Text("Suburb: \(user.suburb)").font(.caption)
                    Text("City: \(user.city)").font(.caption)
                    Text("Postal Code: \(user.postalCode)").font(.caption)
                    
                    if let joinedDate = user.joinedDate {
                        Text("Joined: \(joinedDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Email address with communication options
                    if !user.email.isEmpty {
                        HStack {
                            Text("Email: ").font(.caption)
                            Button(action: {
                                if let url = URL(string: "mailto:\(user.email)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                            Menu {
                                Button(action: {
                                    if let url = URL(string: "mailto:\(user.email)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Send Email", systemImage: "envelope.fill")
                                }
                                Button(action: {
                                    UIPasteboard.general.string = user.email
                                }) {
                                    Label("Copy Email", systemImage: "doc.on.doc.fill")
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "envelope.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    Text("Email")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                .frame(width: 70, height: 44)
                                .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuOrder(.priority)
                        }
                    }
                    
                    // Cell phone with communication options
                    if !user.cell.isEmpty {
                        HStack {
                            Text("Cell: ").font(.caption)
                            Menu {
                                Button(action: {
                                    if let url = URL(string: "tel:\(user.cell)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Call \(user.cell)", systemImage: "phone.fill")
                                }
                                Button(action: {
                                    var waNumber = user.cell.filter { $0.isNumber }
                                    if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                        waNumber = "27" + waNumber.dropFirst()
                                    }
                                    if let url = URL(string: "https://wa.me/\(waNumber)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("WhatsApp Call / Message", systemImage: "message.circle.fill")
                                }
                                Divider()
                                Button(action: {
                                    UIPasteboard.general.string = user.cell
                                }) {
                                    Label("Copy Number", systemImage: "doc.on.doc")
                                }
                            } label: {
                                Text(user.cell)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .menuStyle(.borderlessButton)
                            .menuOrder(.priority)
                        }
                    }
                    
                    // Emergency contact - show each user's own emergency contacts from Firestore
                    if !user.emergencyContactName.isEmpty
                        || !user.emergencyContactPhone.isEmpty
                        || !user.emergencyContactRelationship.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Emergency Contact:").font(.caption).foregroundColor(.secondary)
                            if !user.emergencyContactName.isEmpty {
                                Text("Name: \(user.emergencyContactName)").font(.caption)
                            }
                            if !user.emergencyContactPhone.isEmpty {
                                HStack {
                                    Text("Phone: ").font(.caption)
                                    Menu {
                                        Button(action: {
                                            if let url = URL(string: "tel:\(user.emergencyContactPhone)") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Label("Call \(user.emergencyContactPhone)", systemImage: "phone.fill")
                                        }
                                        Button(action: {
                                            var waNumber = user.emergencyContactPhone.filter { $0.isNumber }
                                            if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                                waNumber = "27" + waNumber.dropFirst()
                                            }
                                            if let url = URL(string: "https://wa.me/\(waNumber)") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Label("WhatsApp Call / Message", systemImage: "message.circle.fill")
                                        }
                                        Divider()
                                        Button(action: {
                                            UIPasteboard.general.string = user.emergencyContactPhone
                                        }) {
                                            Label("Copy Number", systemImage: "doc.on.doc")
                                        }
                                    } label: {
                                        Text(user.emergencyContactPhone)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .underline()
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .menuStyle(.borderlessButton)
                                    .menuOrder(.priority)
                                }
                            }
                            if !user.emergencyContactRelationship.isEmpty {
                                Text("Relationship: \(user.emergencyContactRelationship)").font(.caption)
                            }
                        }
                    }
                    
                    // Committee/Admin Role Toggles (for verified users)
                    if user.isVerified, let onToggleCommittee = onToggleCommittee, let onToggleAdmin = onToggleAdmin {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(spacing: 12) {
                            // Committee Toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Committee Member", systemImage: "person.2.fill")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(user.isCommittee ? .blue : .primary)
                                    
                                    Text("Can manage users and schedules")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { user.isCommittee || user.isAdmin },
                                    set: { newValue in
                                        if !newValue && user.isAdmin {
                                            // Also revoke admin when revoking committee
                                            onToggleAdmin(false)
                                        }
                                        onToggleCommittee(newValue)
                                    }
                                ))
                                .labelsHidden()
                                .tint(.blue)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill((user.isCommittee || user.isAdmin) ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke((user.isCommittee || user.isAdmin) ? Color.blue : Color.clear, lineWidth: 1)
                            )
                            
                            // Admin Promotion Toggle (only show if committee member)
                            if user.isCommittee && !user.isAdmin {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Promote to Admin", systemImage: "arrow.up.circle.fill")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.red)
                                        
                                        Text("Grant full system access")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { user.isAdmin },
                                        set: { newValue in
                                            if newValue {
                                                onToggleAdmin(true)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(.red)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                    
                    // Camera Access Toggle (Firestore-based, UID-secured)
                    if let onToggleCameraAccess = onToggleCameraAccess, user.isVerified {
                        Divider()
                            .padding(.vertical, 8)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Security Camera Access", systemImage: "video.fill")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                Text("Allows viewing live security camera feeds")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $hasCameraAccess)
                                .labelsHidden()
                                .onChange(of: hasCameraAccess) {
                                    onToggleCameraAccess(hasCameraAccess)
                                }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hasCameraAccess ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hasCameraAccess ? Color.blue : Color.clear, lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpand()
        }
        .onAppear {
            // Load camera access status from Firestore when expanded
            if isExpanded {
                loadCameraAccessStatus()
            }
        }
        .onChange(of: isExpanded) {
            if isExpanded {
                loadCameraAccessStatus()
            }
        }
    }
    
    private func loadCameraAccessStatus() {
        FirebaseManager.shared.checkCameraAccess(uid: user.id) { result in
            switch result {
            case .success(let hasAccess):
                DispatchQueue.main.async {
                    self.hasCameraAccess = hasAccess
                }
            case .failure(let error):
                print("❌ Failed to load camera access for \(user.name): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.hasCameraAccess = false
                }
            }
        }
    }
}

// Privacy Status View Component
struct PrivacyStatusView: View {
    let privacyStatus: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: privacyStatus ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundColor(privacyStatus ? .green : .red)
            Text("Consent Given")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - App ContentView (root tab container)
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Int = 0
    @AppStorage("appTheme") private var appTheme: String = "auto"
    
    // Auth state management
    @State private var isAuthenticated: Bool = false
    @State private var isVerified: Bool = false
    @State private var isCheckingAuth: Bool = true
    @State private var currentUserUID: String? = nil

    private var showingSettingsBinding: Binding<Bool> {
        Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })
    }

    var body: some View {
        ZStack {
            if isCheckingAuth {
                // Loading screen while checking auth status
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if !isAuthenticated {
                // Show welcome screen with sign in/sign up options
                AuthWelcomeView(isAuthenticated: $isAuthenticated)
            } else if !isVerified {
                // Show pending approval screen if authenticated but not verified
                PendingApprovalView(isVerified: $isVerified)
            } else {
                // Show main app if authenticated and verified
                mainAppView
            }
        }
        .onAppear {
            checkAuthenticationStatus()
            setupAuthStateListener()
        }
    }
    
    // Main app TabView
    private var mainAppView: some View {
        TabView(selection: $selectedTab) {
            HomeView(showingSettings: showingSettingsBinding, selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(1)

            ReportItTab()
                .tabItem { Label("Report It", systemImage: "exclamationmark.triangle") }
                .tag(2)

            // Chats tab - Full featured community chat
            NavigationStack {
                CommunityChatCard()
                    .navigationTitle("Community Chat")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Chats", systemImage: "message") }
            .tag(3)

            // Watch tab with admin settings (uses AppState internally)
            WatchTabWithAdminSettings()
                .tabItem { Label("Watch", systemImage: "applewatch") }
                .tag(4)
        }
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:  // "auto"
            return nil
        }
    }
    
    // MARK: - Authentication Methods
    
    /// Check authentication status on app launch
    private func checkAuthenticationStatus() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        // Check if user is signed in with Firebase Auth
        if let user = Auth.auth().currentUser {
            print("✅ User is authenticated: \(user.uid)")
            currentUserUID = user.uid
            isAuthenticated = true
            
            // Check verification status from Firestore
            fetchVerificationStatus(uid: user.uid)
        } else {
            print("ℹ️ No authenticated user found")
            isAuthenticated = false
            isCheckingAuth = false
        }
        #else
        // If Firebase not available, check UserDefaults as fallback
        if let uid = UserDefaults.standard.string(forKey: "userUID"), !uid.isEmpty {
            currentUserUID = uid
            isAuthenticated = true
            isVerified = UserDefaults.standard.bool(forKey: "userIsVerified")
        } else {
            isAuthenticated = false
        }
        isCheckingAuth = false
        #endif
    }
    
    /// Fetch user's verification status from Firestore
    private func fetchVerificationStatus(uid: String) {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isCheckingAuth = false
            }
            
            if let error = error {
                print("❌ Error fetching verification status: \(error)")
                // Default to unverified if error
                DispatchQueue.main.async {
                    self.isVerified = false
                }
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ No user document found for UID: \(uid)")
                print("⚠️ User document deleted or never created")
                
                // Check if document was explicitly deleted (vs never created)
                // If the document doesn't exist at all, this might be:
                // 1. Admin deleted the user
                // 2. Incomplete registration from network failure
                
                // Check UserDefaults to see if this was a previously registered user
                let hadPreviousData = UserDefaults.standard.string(forKey: "userName") != nil
                
                if hadPreviousData {
                    print("⚠️ User had previous data - likely admin deleted account")
                    print("🔓 Signing out user to show welcome screen")
                    
                    // Sign out the user so they see welcome screen instead of pending
                    #if canImport(FirebaseAuth)
                    do {
                        try Auth.auth().signOut()
                        
                        // Clear all cached user data
                        UserDefaults.standard.removeObject(forKey: "userUID")
                        UserDefaults.standard.removeObject(forKey: "userName")
                        UserDefaults.standard.removeObject(forKey: "userSurname")
                        UserDefaults.standard.removeObject(forKey: "userEmail")
                        UserDefaults.standard.removeObject(forKey: "userIsVerified")
                        UserDefaults.standard.removeObject(forKey: "userIsAdmin")
                        UserDefaults.standard.removeObject(forKey: "userIsCommittee")
                        UserDefaults.standard.removeObject(forKey: "userHasCameraAccess")
                        
                        DispatchQueue.main.async {
                            self.isAuthenticated = false
                            self.isVerified = false
                            print("✅ User signed out - will show welcome screen")
                        }
                    } catch {
                        print("❌ Error signing out: \(error.localizedDescription)")
                        
                        // Fallback: at least clear the authenticated state
                        DispatchQueue.main.async {
                            self.isAuthenticated = false
                            self.isVerified = false
                        }
                    }
                    #endif
                } else {
                    print("ℹ️ No previous data found - attempting recovery for incomplete registration")
                    
                    // Attempt to recover by creating a minimal user document
                    self.recoverMissingUserDocument(uid: uid, db: db)
                    
                    DispatchQueue.main.async {
                        self.isVerified = false
                    }
                }
                return
            }
            
            let verified = data["verified"] as? Bool ?? false
            let isAdmin = data["isAdmin"] as? Bool ?? false
            let isCommittee = data["isCommittee"] as? Bool ?? false
            let hasCameraAccess = data["cameraAccess"] as? Bool ?? false
            
            // Fetch user profile data
            let firstName = data["firstName"] as? String ?? ""
            let lastName = data["lastName"] as? String ?? ""
            let email = data["email"] as? String ?? ""
            let phone = data["phone"] as? String ?? ""
            
            // Fetch address data
            let street = data["street"] as? String ?? ""
            let suburb = data["suburb"] as? String ?? ""
            let city = data["city"] as? String ?? ""
            let postalCode = data["postalCode"] as? String ?? ""
            
            // Fetch emergency contact details
            let emName = data["emergencyContactName"] as? String ?? ""
            let emPhone = data["emergencyContactPhone"] as? String ?? ""
            let emRel = data["emergencyContactRelationship"] as? String ?? ""
            
            // Fetch watch credentials
            let watchCred = data["watchCredential"] as? String ?? ""
            
            // Fetch privacy settings
            let shareWithCommunity = data["privacyShareWithCommunity"] as? Bool ?? true
            let shareWithCommittee = data["privacyShareWithCommittee"] as? Bool ?? true
            
            print("ℹ️ User status - Verified: \(verified), Admin: \(isAdmin), Committee: \(isCommittee)")
            if !emName.isEmpty {
                print("ℹ️ Emergency contact loaded: \(emName)")
            }
            if !watchCred.isEmpty {
                print("ℹ️ Watch credential loaded: \(watchCred)")
            }
            
            DispatchQueue.main.async {
                self.isVerified = verified
                
                // Cache all user roles for offline access and quick checks
                UserDefaults.standard.set(verified, forKey: "userIsVerified")
                UserDefaults.standard.set(isAdmin, forKey: "userIsAdmin")
                UserDefaults.standard.set(isCommittee, forKey: "userIsCommittee")
                UserDefaults.standard.set(hasCameraAccess, forKey: "userHasCameraAccess")
                
                // Restore user profile data to @AppStorage
                if !firstName.isEmpty {
                    UserDefaults.standard.set(firstName, forKey: "userName")
                }
                if !lastName.isEmpty {
                    UserDefaults.standard.set(lastName, forKey: "userSurname")
                }
                if !email.isEmpty {
                    UserDefaults.standard.set(email, forKey: "userEmail")
                }
                if !phone.isEmpty {
                    UserDefaults.standard.set(phone, forKey: "userCell")
                }
                
                // Restore address data to @AppStorage
                if !street.isEmpty {
                    UserDefaults.standard.set(street, forKey: "userStreet")
                }
                if !suburb.isEmpty {
                    UserDefaults.standard.set(suburb, forKey: "userSuburb")
                }
                if !city.isEmpty {
                    UserDefaults.standard.set(city, forKey: "userCity")
                }
                if !postalCode.isEmpty {
                    UserDefaults.standard.set(postalCode, forKey: "userPostalCode")
                }
                
                // Restore emergency contact details to @AppStorage
                if !emName.isEmpty {
                    UserDefaults.standard.set(emName, forKey: "emergencyContactName")
                }
                if !emPhone.isEmpty {
                    UserDefaults.standard.set(emPhone, forKey: "emergencyContactPhone")
                }
                if !emRel.isEmpty {
                    UserDefaults.standard.set(emRel, forKey: "emergencyContactRelationship")
                }
                
                // Restore watch username to @AppStorage
                if !watchCred.isEmpty {
                    UserDefaults.standard.set(watchCred, forKey: "watchUsername")
                }
                
                // Restore privacy settings to @AppStorage
                UserDefaults.standard.set(shareWithCommunity, forKey: "userPrivacyShareWithCommunity")
                UserDefaults.standard.set(shareWithCommittee, forKey: "userPrivacyShareWithCommittee")
                
                print("✅ User profile data restored to local storage")
            }
        }
        #endif
    }
    
    /// Recover from missing user document by creating a minimal profile
    /// This handles cases where Firebase Auth account was created but Firestore document creation failed
    private func recoverMissingUserDocument(uid: String, db: Firestore) {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ Cannot recover - no authenticated user")
            return
        }
        
        print("🔧 Creating recovery user document for UID: \(uid)")
        
        // Get cached user data from UserDefaults (stored during registration)
        let firstName = UserDefaults.standard.string(forKey: "userName") ?? "Unknown"
        let lastName = UserDefaults.standard.string(forKey: "userSurname") ?? "User"
        let email = currentUser.email ?? UserDefaults.standard.string(forKey: "userEmail") ?? "unknown@example.com"
        
        // Create minimal user document
        let userData: [String: Any] = [
            "uid": uid,
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "name": "\(firstName) \(lastName)",
            "verified": false, // Requires admin approval
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "recoveredDocument": true, // Flag to indicate this was auto-recovered
            "privacyShareWithCommunity": true,
            "privacyShareWithCommittee": true
        ]
        
        db.collection("users").document(uid).setData(userData, merge: true) { error in
            if let error = error {
                print("❌ Failed to create recovery document: \(error.localizedDescription)")
                print("⚠️ MANUAL ACTION REQUIRED: Please create user document in Firebase Console")
                print("   Path: users/\(uid)")
                print("   Required fields: uid, email, firstName, lastName, verified:false")
            } else {
                print("✅ Recovery document created successfully")
                print("ℹ️ User will need to complete profile through app settings")
                
                // Refresh verification status now that document exists
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.fetchVerificationStatus(uid: uid)
                }
            }
        }
        #endif
    }
    
    /// Setup Firebase Auth state listener to handle sign-in/sign-out
    private func setupAuthStateListener() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        // Store listener handle (suppress unused result warning)
        _ = Auth.auth().addStateDidChangeListener { auth, user in
            DispatchQueue.main.async {
                if let user = user {
                    print("🔄 Auth state changed: User signed in - \(user.uid)")
                    self.currentUserUID = user.uid
                    self.isAuthenticated = true
                    
                    // Fetch latest verification status
                    self.fetchVerificationStatus(uid: user.uid)
                } else {
                    print("🔄 Auth state changed: User signed out")
                    self.currentUserUID = nil
                    self.isAuthenticated = false
                    self.isVerified = false
                    self.isCheckingAuth = false
                }
            }
        }
        #endif
    }
}

// MARK: - Admin User Row View Component
struct AdminUserRowView: View {
    let user: RegisteredUser
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleAdmin: (Bool) -> Void
    let onToggleCommittee: (Bool) -> Void
    let onToggleCameraAccess: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row - always visible
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Profile image or initials
                    if let imageURL = user.profileImageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(user.isAdmin ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(user.name.prefix(2).uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(user.isAdmin ? .red : .orange)
                            )
                    }
                    
                    // User info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if user.isAdmin {
                                Label("Admin", systemImage: "shield.fill")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            if user.isCommittee {
                                Label("Committee", systemImage: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if user.hasCameraAccess {
                                Label("Camera", systemImage: "video.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    // Contact info
                    VStack(alignment: .leading, spacing: 8) {
                        if !user.email.isEmpty && user.email != "Hidden" {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(user.email)
                                    .font(.caption)
                            }
                        }
                        
                        if !user.street.isEmpty && user.street != "Hidden" {
                            HStack {
                                Image(systemName: "house.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text("\(user.street), \(user.suburb)")
                                    .font(.caption)
                            }
                        }
                        
                        if !user.cell.isEmpty && user.cell != "Hidden" {
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(user.cell)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Role toggles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        // Combined Committee/Admin toggle
                        Toggle(isOn: Binding(
                            get: { user.isCommittee || user.isAdmin },
                            set: { newValue in onToggleCommittee(newValue) }
                        )) {
                            HStack {
                                Image(systemName: user.isAdmin ? "shield.fill" : "person.2.fill")
                                    .foregroundColor(user.isAdmin ? .red : .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.isAdmin ? "Admin" : "Committee Member")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text(user.isAdmin ? "Full system access" : "Can manage users and schedules")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(user.isAdmin ? .red : .blue)
                        
                        // Admin role upgrade (only show if already committee member)
                        if user.isCommittee && !user.isAdmin {
                            Toggle(isOn: Binding(
                                get: { user.isAdmin },
                                set: { newValue in 
                                    if newValue {
                                        // Promote to admin (also keeps committee status)
                                        onToggleAdmin(true)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Promote to Admin")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("Grant full system access")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tint(.red)
                        }
                        
                        // Camera access toggle
                        Toggle(isOn: Binding(
                            get: { user.hasCameraAccess },
                            set: { newValue in onToggleCameraAccess(newValue) }
                        )) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Camera Access")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("Can view security cameras")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(.blue)
                    }
                }
                .padding(.vertical, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

// MARK: - Conflict Resolution Card Component
struct ConflictResolutionCard: View {
    let legacyUsername: String
    let matches: [[String: String]]
    let onSelect: (String) -> Void
    
    @State private var selectedUID: String?
    @State private var showConfirmation = false
    
    var body: some View {
        GroupBox(label: HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text("Legacy Username: \(legacyUsername)")
                .fontWeight(.semibold)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select the correct user from the \(matches.count) possible matches:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(matches, id: \.self) { match in
                    let uid = match["uid"] ?? ""
                    let fullName = match["fullName"] ?? "Unknown"
                    let watchCredential = match["watchCredential"] ?? ""
                    
                    Button(action: {
                        selectedUID = uid
                    }) {
                        HStack(spacing: 12) {
                            // Radio button
                            Image(systemName: selectedUID == uid ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedUID == uid ? .blue : .gray)
                                .font(.title3)
                            
                            // User info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fullName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 8) {
                                    Label("Watch: \(watchCredential)", systemImage: "eye.fill")
                                    
                                    Text("UID: \(uid.prefix(8))...")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(selectedUID == uid ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Grant access button
                Button(action: {
                    if selectedUID != nil {
                        showConfirmation = true
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Grant Camera Access")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedUID == nil)
                .alert("Confirm Selection", isPresented: $showConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Confirm") {
                        if let uid = selectedUID {
                            onSelect(uid)
                        }
                    }
                } message: {
                    if let selectedMatch = matches.first(where: { $0["uid"] == selectedUID }) {
                        Text("Grant camera access to \(selectedMatch["fullName"] ?? "this user")?")
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
    }
}

// MARK: - Camera Request Row View
struct CameraRequestRowView: View {
    let user: RegisteredUser
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // User profile image or initial circle
                if let imageURL = user.profileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image.resizable()
                            .scaledToFill()
                    } placeholder: {
                        initialCircle
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                } else {
                    initialCircle
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.headline)
                    
                    if let watchCredential = user.watchCredential {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Watch Username: \(watchCredential)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("\(user.street), \(user.suburb)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onApprove) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Approve")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                
                Button(action: onReject) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Reject")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var initialCircle: some View {
        let initials = user.name.split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)) }
            .joined()
            .uppercased()
        
        return ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 48, height: 48)
            Text(initials)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}


