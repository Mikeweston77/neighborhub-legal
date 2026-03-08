import Combine
import CoreData
import CoreLocation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
    import FirebaseAuth
#endif
#if canImport(FirebaseStorage)
    import FirebaseStorage
#endif

// Define HomeSection enum locally to avoid compilation issues
enum HomeSection: Int, CaseIterable, Codable {
    case weather
    case websiteLink
    case polls
    case requestHelp
    case stats
    case reminders
    case events
    case newsletters
    case localListings
}

// MARK: - Custom Color for Lighter Background in Dark Mode
extension Color {
    static var appBackground: Color {
        Color(
            UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)  // lighter than systemBackground in dark
                } else {
                    return UIColor.systemGray6
                }
            })
    }
}

// MARK: - Camera Image Picker Helper
struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    var sourceType: UIImagePickerController.SourceType = .camera

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}


    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let ui = info[.originalImage] as? UIImage,
                let d = ui.jpegData(compressionQuality: 0.7)
            {
                parent.imageData = d
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// Precise coordinates helper using weatherService's location manager (exposed via environment here)
extension HomeView {
    private var firePreciseCoordinates: String {
        if let loc = weatherService.locationManager.currentLocation {
            return String(
                format: "Lat: %.5f, Lon: %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return requestHelpLocationDescription
    }
}

extension HomeView {
    // Reverse geocode the current device location to a human-readable address
    fileprivate func resolveDeviceAddressIfNeeded() async {
        guard fireUseDeviceLocationBinding.wrappedValue,
            let loc = weatherService.locationManager.currentLocation
        else { return }
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            if let p = placemarks.first {
                var lines: [String] = []
                if let name = p.name { lines.append(name) }
                if let thoroughfare = p.thoroughfare { lines.append(thoroughfare) }
                if let locality = p.locality { lines.append(locality) }
                if let administrative = p.administrativeArea { lines.append(administrative) }
                if let postal = p.postalCode { lines.append(postal) }
                let composed = lines.joined(separator: ", ")
                await MainActor.run {
                    // populate the centralized view model so UI and sending can read from it
                    fireResolvedAddressBinding.wrappedValue = composed
                    fireVM.report.resolvedAddress = composed
                    if let loc = weatherService.locationManager.currentLocation {
                        fireVM.report.coordinates = loc.coordinate
                    }
                }
                return
            }
        } catch {
            // ignore and leave fireResolvedAddress empty (UI will show coords)
        }
    }
}

// MARK: - HomeView (Main Home Tab UI)
struct HomeView: View {
    // MARK: - Type Definitions
    // Help type selection for Request Help
    enum HelpType: String, Codable, CaseIterable, Hashable {
        case fire = "Fire"
        case emergency = "Emergency"
        case medical = "Medical"

        var iconName: String {
            switch self {
            case .fire: return "flame.fill"
            case .emergency: return "exclamationmark.triangle.fill"
            case .medical: return "bandage.fill"
            }
        }

        var color: Color {
            switch self {
            case .fire: return Color.orange
            case .emergency: return Color.yellow
            case .medical: return Color.green
            }
        }
        
        var description: String {
            switch self {
            case .fire: return "Report fires and smoke"
            case .emergency: return "General emergencies"
            case .medical: return "Medical assistance needed"
            }
        }
    }

    // MARK: - Emergency Contacts Models
    /// Model for community-wide emergency contacts that can be managed by admins/committee members
    struct CommunityEmergencyContact: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let phoneNumber: String
        let email: String?
        let organization: String?
        let category: ContactCategory
        let priority: ContactPriority
        let availability: String?
        let notes: String?
        let createdBy: String // Admin/committee member who created this
        let createdAt: Date
        let updatedAt: Date
        let isActive: Bool
        
        enum ContactCategory: String, CaseIterable, Codable {
            case emergency = "emergency"           // 911, Police, Fire, Ambulance
            case medical = "medical"               // Hospital, Clinic, Doctor
            case security = "security"             // Security company, Guards
            case utility = "utility"               // Power, Water, Gas
            case maintenance = "maintenance"       // Plumber, Electrician, Handyman
            case community = "community"           // Committee members, Coordinators
            case government = "government"         // Municipality, Council
            case neighborhood = "neighborhood"     // Watch coordinator, HOA
            
            var displayName: String {
                switch self {
                case .emergency: return "Emergency Services"
                case .medical: return "Medical Services"
                case .security: return "Security"
                case .utility: return "Utilities"
                case .maintenance: return "Maintenance"
                case .community: return "Community"
                case .government: return "Government"
                case .neighborhood: return "Neighborhood"
                }
            }
            
            var iconName: String {
                switch self {
                case .emergency: return "exclamationmark.triangle.fill"
                case .medical: return "cross.case.fill"
                case .security: return "shield.fill"
                case .utility: return "lightbulb.fill"
                case .maintenance: return "wrench.and.screwdriver.fill"
                case .community: return "person.3.fill"
                case .government: return "building.columns.fill"
                case .neighborhood: return "house.fill"
                }
            }
            
            var color: String {
                switch self {
                case .emergency: return "red"
                case .medical: return "blue"
                case .security: return "orange"
                case .utility: return "yellow"
                case .maintenance: return "green"
                case .community: return "purple"
                case .government: return "gray"
                case .neighborhood: return "indigo"
                }
            }
        }
        
        enum ContactPriority: String, CaseIterable, Codable {
            case critical = "critical"
            case high = "high"
            case normal = "normal"
            case low = "low"
            
            var displayName: String {
                switch self {
                case .critical: return "Critical"
                case .high: return "High"
                case .normal: return "Normal"
                case .low: return "Low"
                }
            }
            
            var badgeColor: String {
                switch self {
                case .critical: return "red"
                case .high: return "orange"
                case .normal: return "blue"
                case .low: return "gray"
                }
            }
        }
        
        init(id: String = UUID().uuidString, 
             name: String, 
             phoneNumber: String, 
             email: String? = nil,
             organization: String? = nil,
             category: ContactCategory, 
             priority: ContactPriority = .normal,
             availability: String? = nil,
             notes: String? = nil,
             createdBy: String,
             createdAt: Date = Date(),
             updatedAt: Date = Date(),
             isActive: Bool = true) {
            self.id = id
            self.name = name
            self.phoneNumber = phoneNumber
            self.email = email
            self.organization = organization
            self.category = category
            self.priority = priority
            self.availability = availability
            self.notes = notes
            self.createdBy = createdBy
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isActive = isActive
        }
        
        static let defaultContacts: [CommunityEmergencyContact] = [
            CommunityEmergencyContact(
                name: "Emergency Services",
                phoneNumber: "911",
                organization: "Emergency Dispatch",
                category: .emergency,
                priority: .critical,
                availability: "24/7",
                notes: "Police, Fire, Ambulance - Primary emergency contact",
                createdBy: "system"
            ),
            CommunityEmergencyContact(
                name: "Police Non-Emergency",
                phoneNumber: "(555) 123-4567",
                organization: "Local Police Department",
                category: .emergency,
                priority: .high,
                availability: "24/7",
                notes: "Non-emergency police matters",
                createdBy: "system"
            ),
            CommunityEmergencyContact(
                name: "Hospital Emergency",
                phoneNumber: "(555) 234-5678",
                organization: "City General Hospital",
                category: .medical,
                priority: .critical,
                availability: "24/7",
                notes: "Emergency room direct line",
                createdBy: "system"
            )
        ]
    }

    /// Manager for community-wide emergency contacts that admins/committee members can edit
    class CommunityEmergencyContactManager: ObservableObject {
        @Published var contacts: [CommunityEmergencyContact] = []
        @Published var isLoading = false
        @Published var errorMessage: String?
        
        private let userDefaults = UserDefaults.standard
        private let contactsKey = "communityEmergencyContacts"
        
        // Admin/committee authentication
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
        @AppStorage("userName") private var userName: String = ""
        @AppStorage("userSurname") private var userSurname: String = ""
        
        var canEdit: Bool {
            return userIsAdmin || userIsCommittee
        }
        
        var currentUserName: String {
            return "\(userName) \(userSurname)".trimmingCharacters(in: .whitespaces)
        }
        
        init() {
            loadLocalContacts()
            
            // Initialize with default contacts if empty
            if contacts.isEmpty {
                contacts = CommunityEmergencyContact.defaultContacts
                saveLocalContacts()
            }
        }
        
        private func loadLocalContacts() {
            if let data = userDefaults.data(forKey: contactsKey),
               let decodedContacts = try? JSONDecoder().decode([CommunityEmergencyContact].self, from: data) {
                self.contacts = decodedContacts.filter { $0.isActive }.sorted { contact1, contact2 in
                    // Sort by priority first, then by category
                    if contact1.priority.rawValue != contact2.priority.rawValue {
                        return priorityOrder(contact1.priority) < priorityOrder(contact2.priority)
                    }
                    return contact1.category.rawValue < contact2.category.rawValue
                }
            }
        }
        
        private func saveLocalContacts() {
            if let encoded = try? JSONEncoder().encode(contacts) {
                userDefaults.set(encoded, forKey: contactsKey)
            }
        }
        
        private func priorityOrder(_ priority: CommunityEmergencyContact.ContactPriority) -> Int {
            switch priority {
            case .critical: return 0
            case .high: return 1
            case .normal: return 2
            case .low: return 3
            }
        }
        
        func callContact(_ contact: CommunityEmergencyContact) {
            guard let url = URL(string: "tel:\(contact.phoneNumber)") else {
                errorMessage = "Invalid phone number: \(contact.phoneNumber)"
                return
            }
            
            // Track emergency contact action
            AnalyticsService.shared.trackEmergencyContact(
                contactType: contact.category.rawValue,
                action: "call"
            )
            
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                errorMessage = "Unable to make phone calls on this device"
            }
        }
        
        func criticalContacts() -> [CommunityEmergencyContact] {
            return contacts.filter { $0.priority == .critical }
        }
    }

    // Fire report data structure for passing to parent
    struct FireReportData {
        let dateTime: Date
        let buildingType: String
        let useDeviceLocation: Bool
        let locationInput: String
        let detailedLocationDescription: String  // Added for full address details
        let useProfileContact: Bool
        let contactName: String
        let contactPhone: String
    }

    // Reminder Info Model
    struct ReminderInfo: Identifiable, Codable {
        let id: String
        let title: String
        let body: String
        let date: Date
    }

    // MARK: - State Properties
    @State private var selectedHelpType: HelpType? = nil
    @FocusState private var helpEditorFocused: Bool
    // Fire-specific inputs shown when HelpType.fire is selected
    // Many of these are now kept in the FireAlertReportViewModel.report to centralize state
    @State private var fireLocationInput: String = ""
    @State private var fireDateTime: Date = Date()
    // Redesigned fire inputs (default values mirror the report defaults)
    private var fireBuildingTypeBinding: Binding<String> {
        Binding(get: { fireVM.report.buildingType }, set: { fireVM.report.buildingType = $0 })
    }
    private var fireBuildingOtherDescriptionBinding: Binding<String> {
        Binding(
            get: { fireVM.report.buildingOtherDescription },
            set: { fireVM.report.buildingOtherDescription = $0 })
    }
    private var fireUseDeviceLocationBinding: Binding<Bool> {
        Binding(
            get: { fireVM.report.useDeviceLocation }, set: { fireVM.report.useDeviceLocation = $0 })
    }
    private var fireResolvedAddressBinding: Binding<String> {
        Binding(get: { fireVM.report.resolvedAddress }, set: { fireVM.report.resolvedAddress = $0 })
    }

    // Photo picker for fire evidence
    @State private var firePhotoItem: PhotosPickerItem? = nil
    @State private var firePhotoData: Data? = nil
    @State private var showingCameraPicker: Bool = false
    // Allow user to choose whether to use their profile details for fire requests (mirrors VM)
    private var fireUseMyDetailsBinding: Binding<Bool> {
        Binding(
            get: { fireVM.report.useProfileContact }, set: { fireVM.report.useProfileContact = $0 })
    }
    private var fireContactNameBinding: Binding<String> {
        Binding(get: { fireVM.report.contactName }, set: { fireVM.report.contactName = $0 })
    }
    private var fireContactPhoneBinding: Binding<String> {
        Binding(get: { fireVM.report.contactPhone }, set: { fireVM.report.contactPhone = $0 })
    }
    // ViewModel for fire reports (new centralized state holder)
    @StateObject private var fireVM = FireAlertReportViewModel()
    // Poll creation sheet
    @State private var showCreatePollSheet = false
    @State private var newPollQuestion = ""
    @State private var newPollOptions: [String] = ["", ""]
    @State private var pollOptionsRefreshID = UUID() // Force UI refresh when options change

    // Missing state variables for sheets and functionality
    @State private var showRequestHelpSheet = false
    @State private var showScheduleSheet = false
    @State private var showPollCreationSheet = false
    @State private var helpRequestText = ""

    // Public initializer to allow construction from ContentView
    public init(
        allowEveryoneToCreatePolls: Bool = false,
        allowEveryoneToCreateNewsletters: Bool = false,
        homeSectionOrder: [HomeSection] = HomeSection.allCases,
        homeSectionVisibility: [HomeSection: Bool] = Dictionary(
            uniqueKeysWithValues: HomeSection.allCases.map { ($0, true) }),
        showingSettings: Binding<Bool>,
        selectedTab: Binding<Int>
    ) {
        self._allowEveryoneToCreatePolls = State(initialValue: allowEveryoneToCreatePolls)
        self._allowEveryoneToCreateNewsletters = State(
            initialValue: allowEveryoneToCreateNewsletters)
        self._homeSectionOrder = State(initialValue: homeSectionOrder)
        self._homeSectionVisibility = State(initialValue: homeSectionVisibility)
        self._showingSettings = showingSettings
        self._selectedTab = selectedTab
    }
    // Allow everyone to create polls/newsletters (from ContentView)
    @State var allowEveryoneToCreatePolls: Bool = false
    @State var allowEveryoneToCreateNewsletters: Bool = false
    // Home UI section order and visibility (from ContentView)
    @State var homeSectionOrder: [HomeSection] = HomeSection.allCases
    @State var homeSectionVisibility: [HomeSection: Bool] = Dictionary(
        uniqueKeysWithValues: HomeSection.allCases.map { ($0, true) })

    // Persistent settings using AppStorage
    @AppStorage("allowEveryoneToCreatePolls") private var storedAllowPolls: Bool = false
    @AppStorage("allowEveryoneToCreateNewsletters") private var storedAllowNewsletters: Bool = false
    @AppStorage("homeSectionOrderData") private var storedSectionOrderData: String = ""
    @AppStorage("homeSectionVisibilityData") private var storedSectionVisibilityData: String = ""

    // For full-screen event view (Request Assistance)
    @State private var selectedRequestEvent: LocalEvent? = nil
    @EnvironmentObject var appState: AppState
    // Collapsible state for Polls section
    @State private var pollsExpanded: Bool = false
    
    // Emergency settings - separate numbers for each type
    @State private var fireNumber: String = "911"
    @State private var emergencyNumber: String = "911"
    @State private var medicalNumber: String = "911"
    @State private var showEditEmergencyNumber: Bool = false

    // MARK: - Static helper to remove scheduled reminder for a deleted event
    static func removeScheduledReminder(for eventID: UUID) {
        #if canImport(FirebaseFirestore)
            // don't attempt to call instance listeners from static context
        #endif
        let key = "scheduledRemindersData"
        let id = "event_reminder_\(eventID.uuidString)"
        let defaults = UserDefaults.standard
        guard let dataStr = defaults.string(forKey: key), !dataStr.isEmpty,
            let data = dataStr.data(using: .utf8)
        else { return }
        if var reminders = try? JSONDecoder().decode([ReminderInfo].self, from: data) {
            reminders.removeAll { $0.id == id }
            if let newData = try? JSONEncoder().encode(reminders) {
                let newString = String(data: newData, encoding: .utf8) ?? ""
                defaults.set(newString, forKey: key)
            }
        }
        // Also remove pending notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    // MARK: - Reminders State
    @State private var scheduledReminders: [ReminderInfo] = []

    // Admin logic
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    @AppStorage("userCell") private var userCell: String = ""
    // Address fallbacks (used when Core Data User.address is empty)
    @AppStorage("userStreet") private var userStreet: String = ""
    @AppStorage("userSuburb") private var userSuburb: String = ""
    @AppStorage("userCity") private var userCity: String = ""
    @AppStorage("userPostalCode") private var userPostalCode: String = ""
    @AppStorage("emergencyContactName") private var emergencyContactName: String = ""
    @AppStorage("emergencyContactPhone") private var emergencyContactPhone: String = ""
    @AppStorage("emergencyContactRelationship") private var emergencyContactRelationship: String =
        ""
    // Server-backed help sending (optional). Configure a secure server that will send via WhatsApp Business API.
    @AppStorage("helpServerURL") private var helpServerURL: String = ""
    @AppStorage("helpServerAPIKey") private var helpServerAPIKey: String = ""
    // Optional recipient override on the server call (E.164 format, e.g. "27831234567"). If empty, emergency contact or cell will be used.
    @AppStorage("helpRecipientPhone") private var helpRecipientPhone: String = ""
    // Floating Action Button position
    @AppStorage("floatingHelpButtonPosition") private var floatingHelpButtonPosition: String =
        "right"  // values: left, center, right
    
    // Cached admin/committee status from Firestore
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        return isCommitteeMember
    }

    private var isCommitteeMember: Bool {
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

    // Helper function to get consistent user ID for voting
    private func getCurrentUserId() -> String {
        var voteUserId: String = ""
        #if canImport(FirebaseAuth)
            if let uid = Auth.auth().currentUser?.uid {
                voteUserId = uid
            }
        #endif
        if voteUserId.isEmpty {
            // Use stored fallback id if present, otherwise generate and persist one
            if fallbackUserId.isEmpty {
                fallbackUserId = UUID().uuidString
            }
            voteUserId = fallbackUserId
        }
        return voteUserId
    }

    @State private var showingOnboarding: Bool = false

    // MARK: - Core Data User Registration Helper
    private func registerUser(data: OnboardingData, completion: @escaping (Bool) -> Void = { _ in }) {
        // Get the Firebase Auth UID that was stored during account creation
        guard let userUID = UserDefaults.standard.string(forKey: "userUID") else {
            print("❌ No Firebase Auth UID found - user must create account first")
            completion(false)
            return
        }
        
        // Store basic data in AppStorage for immediate availability
        userName = data.firstName
        userSurname = data.surname
        
        // Store privacy settings per user (now use UID instead of email)
        UserDefaults.standard.set(data.shareWithCommunity, forKey: "userPrivacyShareWithCommunity_\(userUID)")
        UserDefaults.standard.set(data.shareWithCommittee, forKey: "userPrivacyShareWithCommittee_\(userUID)")
        
        // Store emergency contact in AppStorage - use direct assignment to @AppStorage bindings
        emergencyContactName = data.emergencyContactName
        emergencyContactPhone = data.emergencyContactPhone
        emergencyContactRelationship = data.emergencyContactRelationship
        
        // Store user email and phone
        UserDefaults.standard.set(data.email, forKey: "userEmail")
        userCell = data.phoneNumber.isEmpty ? "" : data.phoneNumber
        if !data.phoneNumber.isEmpty {
            UserDefaults.standard.set(data.phoneNumber, forKey: "userPhone")
        }
        
        // Store address fields in AppStorage - directly update @AppStorage bindings
        userStreet = data.street.isEmpty ? "" : data.street
        userSuburb = data.suburb.isEmpty ? "" : data.suburb
        userCity = data.city.isEmpty ? "" : data.city
        userPostalCode = data.postalCode.isEmpty ? "" : data.postalCode

        // Create Core Data entry with all fields
        let context = PersistenceController.shared.container.viewContext
        let newUser = User(context: context)
        newUser.id = UUID()
        newUser.name = "\(data.firstName) \(data.surname)"
        newUser.email = data.email
        
        // Build full address
        let addressParts = [data.street, data.suburb, data.city, data.postalCode].filter { !$0.isEmpty }
        newUser.address = addressParts.isEmpty ? nil : addressParts.joined(separator: ", ")
        
        newUser.profileImageURL = nil  // Will be set after upload
        newUser.isVerified = false
        newUser.reputationScore = 0
        newUser.joinedDate = Date()
        newUser.lastActive = Date()
        
        // Store privacy settings as JSON string
        let privacyDict: [String: Bool] = [
            "shareWithCommunity": data.shareWithCommunity,
            "shareWithCommittee": data.shareWithCommittee,
            "receiveNotifications": data.receiveNotifications
        ]
        if let privacyJSON = try? JSONSerialization.data(withJSONObject: privacyDict),
           let privacyString = String(data: privacyJSON, encoding: .utf8) {
            newUser.privacySettings = privacyString
        }
        
        // Store emergency contact as JSON string
        if !data.emergencyContactName.isEmpty || !data.emergencyContactPhone.isEmpty {
            let emergencyDict: [String: String] = [
                "name": data.emergencyContactName,
                "phone": data.emergencyContactPhone,
                "relationship": data.emergencyContactRelationship
            ]
            if let emergencyJSON = try? JSONSerialization.data(withJSONObject: emergencyDict),
               let emergencyString = String(data: emergencyJSON, encoding: .utf8) {
                newUser.emergencyContact = emergencyString
            }
        }
        
        newUser.skillsOffered = nil
        newUser.interests = nil

        do {
            try context.save()
            
            // Upload profile image to Firebase if provided (now use UID-based path)
            if let profileImage = data.profileImage {
                // Upload to UID-based path: users/{uid}/profile/avatar.jpg
                uploadProfileImageWithUID(profileImage, uid: userUID, data: data, context: context, newUser: newUser, completion: completion)
            } else {
                // No profile image, create Firebase user directly
                createFirebaseUserWithAuth(data: data, profileImageURL: nil, completion: completion)
            }

        } catch {
            print("Failed to register user: \(error)")
            completion(false)
        }
    }
    
    // Helper to upload profile image using UID-based path
    private func uploadProfileImageWithUID(_ image: UIImage, uid: String, data: OnboardingData, context: NSManagedObjectContext, newUser: User, completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseStorage)
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to convert image to JPEG")
                createFirebaseUserWithAuth(data: data, profileImageURL: nil, completion: completion)
                return
            }
            
            let storageRef = Storage.storage().reference()
            let profileRef = storageRef.child("users/\(uid)/profile/avatar.jpg")
            
            profileRef.putData(imageData, metadata: nil) { metadata, error in
                if let error = error {
                    print("❌ Failed to upload profile image: \(error)")
                    self.createFirebaseUserWithAuth(data: data, profileImageURL: nil, completion: completion)
                    return
                }
                
                profileRef.downloadURL { url, error in
                    if let error = error {
                        print("❌ Failed to get download URL: \(error)")
                        self.createFirebaseUserWithAuth(data: data, profileImageURL: nil, completion: completion)
                    } else if let downloadURL = url?.absoluteString {
                        print("✅ Profile image uploaded: \(downloadURL)")
                        // Update Core Data with profile image URL
                        newUser.profileImageURL = downloadURL
                        try? context.save()
                        
                        // Create Firebase user with profile image URL
                        self.createFirebaseUserWithAuth(data: data, profileImageURL: downloadURL, completion: completion)
                    }
                }
            }
        #else
            // Firebase Storage not available
            createFirebaseUserWithAuth(data: data, profileImageURL: nil, completion: completion)
        #endif
    }
    
    // Helper to create Firebase user profile using Auth UID
    private func createFirebaseUserWithAuth(data: OnboardingData, profileImageURL: String?, completion: @escaping (Bool) -> Void) {
        print("🔍 DEBUG: HomeView calling createOrUpdateUserWithAuth")
        print("   First Name: '\(data.firstName)'")
        print("   Last Name: '\(data.surname)'")
        print("   Email: '\(data.email)'")
        print("   Phone: '\(data.phoneNumber)'")
        print("   Street: '\(data.street)'")
        print("   Suburb: '\(data.suburb)'")
        print("   City: '\(data.city)'")
        print("   Postal: '\(data.postalCode)'")
        print("   Emergency Name: '\(data.emergencyContactName)'")
        print("   Emergency Phone: '\(data.emergencyContactPhone)'")
        print("   Emergency Rel: '\(data.emergencyContactRelationship)'")
        
        FirebaseManager.shared.createOrUpdateUserWithAuth(
            firstName: data.firstName,
            lastName: data.surname,
            email: data.email,
            phoneNumber: data.phoneNumber.isEmpty ? nil : data.phoneNumber,
            street: data.street.isEmpty ? nil : data.street,
            suburb: data.suburb.isEmpty ? nil : data.suburb,
            city: data.city.isEmpty ? nil : data.city,
            postalCode: data.postalCode.isEmpty ? nil : data.postalCode,
            emergencyContactName: data.emergencyContactName.isEmpty ? nil : data.emergencyContactName,
            emergencyContactPhone: data.emergencyContactPhone.isEmpty ? nil : data.emergencyContactPhone,
            emergencyContactRelationship: data.emergencyContactRelationship.isEmpty ? nil : data.emergencyContactRelationship,
            profileImageURL: profileImageURL,
            shareWithCommunity: data.shareWithCommunity,
            shareWithCommittee: data.shareWithCommittee,
            wellnessOptIn: data.wellnessOptIn
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let uid):
                    print("✅ Firebase user profile created successfully with UID: \(uid)")
                    print("ℹ️ User document path: users/\(uid)")
                    print("ℹ️ User should now appear in admin approval list")
                    completion(true)
                case .failure(let error):
                    print("❌ Failed to create Firebase user profile: \(error.localizedDescription)")
                    print("⚠️ CRITICAL: User has Auth account but no Firestore document!")
                    print("   This will cause login issues. User should try logging in to trigger recovery.")
                    completion(false)
                }
            }
        }
    }
    
    // Helper for posts today count
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    // Helper for unread messages count
    private var unreadMessagesCount: Int {
        let lastReadTime = Date(timeIntervalSince1970: lastChatReadTimestamp)
        return messages.filter { message in
            message.timestamp > lastReadTime
                && message.user != "\(userName) \(userSurname.prefix(1).uppercased())"  // Don't count own messages as unread
        }.count
    }

    private var postsTodayCount: Int {
        let postsToday = posts.compactMap { post in
            post.createdDate
        }.filter { date in
            Calendar.current.isDate(date, inSameDayAs: today)
        }.count
        let eventsToday = events.compactMap { event in
            event.date
        }.filter { date in
            Calendar.current.isDate(date, inSameDayAs: today)
        }.count
        return postsToday + eventsToday
    }
    // Removed duplicate @Binding userName and userSurname declarations
    @Binding var showingSettings: Bool
    @Binding var selectedTab: Int  // Add binding for tab navigation
    @StateObject private var weatherService = OpenWeatherMapService(
        apiKey: "REDACTED")
    @StateObject private var emergencyRequestManager = EmergencyRequestManager()
    @StateObject private var localListingManager = LocalListingManager()
    @FetchRequest(
        entity: User.entity(),
        sortDescriptors: [],
        animation: .default
    ) private var users: FetchedResults<User>
    @AppStorage("eventsData") private var eventsData: String = ""
    @AppStorage("communityMessagesData") private var communityMessagesData: String = ""  // Add messages data
    @AppStorage("lastChatReadTimestamp") private var lastChatReadTimestamp: Double = 0  // Track when user last read chat
    @State private var events: [LocalEvent] = []
    @State private var posts: [Post] = []  // If Post is not defined, you can comment this out or define a placeholder struct
    @State private var messages: [CommunityMessage] = []  // Add messages state

    // CommunityMessage and MessageType are defined in CommunityChatCard.swift and used across the app
    @State private var weatherExpanded = false

    private var initials: String {
        let first =
            userName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? ""
        let last =
            userSurname.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) }
            ?? ""
        return (first + last).uppercased()
    }

    // Computed helpers used by the Request Help sheet to avoid declaring locals inside ViewBuilder
    private var requestHelpFirstInitial: String {
        return users.first?.name?.first.map { String($0) } ?? userName.first.map { String($0) }
            ?? ""
    }

    private var requestHelpSecondInitial: String {
        if let name = users.first?.name {
            let parts = name.split(separator: " ")
            if parts.count > 1, let c = parts[1].first {
                return String(c)
            }
        }
        return userSurname.first.map { String($0) } ?? ""
    }

    private var requestHelpInitials: String {
        (requestHelpFirstInitial + requestHelpSecondInitial).uppercased()
    }

    private var requestHelpDisplayName: String {
        if let coreName = users.first?.name,
            coreName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return coreName
        }
        return "\(userName) \(userSurname)"
    }

    private var requestHelpDisplayCell: String? {
        // prefer Core Data user cell if available (not present in model here), else AppStorage userCell
        let coreUserCell: String? = nil
        if let core = coreUserCell,
            core.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return core
        }
        return userCell.isEmpty ? nil : userCell
    }

    private var requestHelpEmergencyContact: EmergencyContact? {
        if let set = users.first?.emergencyContacts as? Set<EmergencyContact>, !set.isEmpty {
            return set.sorted { $0.priority < $1.priority }.first
        }
        return nil
    }

    // Human-friendly location string for the Request Help sheet
    private var requestHelpLocationDescription: String {
        // Prefer weatherService's resolved location name when available
        let name = weatherService.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != "Your Location" {
            return name
        }

        // Fall back to coordinates if present
        if let loc = weatherService.locationManager.currentLocation {
            let lat = String(format: "%.5f", loc.coordinate.latitude)
            let lon = String(format: "%.5f", loc.coordinate.longitude)
            return "Lat: \(lat), Lon: \(lon)"
        }

        // Last fallback: composed AppStorage address
        let composed: [String] = [userStreet, userSuburb, userCity, userPostalCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !composed.isEmpty {
            return composed.joined(separator: ", ")
        }

        return "Location not available"
    }

    private var detailedLocationDescription: String {
        // Try to get detailed address from device location
        if weatherService.locationManager.currentLocation != nil {
            // Use CLGeocoder to get detailed address components
            // Note: This is a synchronous property, so we'll use cached data or fallback
            // The actual geocoding should be done asynchronously elsewhere

            // Check if we have cached detailed location in weatherService
            let name = weatherService.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && name != "Your Location" && name.contains(",") {
                // If locationName contains commas, it's likely a detailed address
                return name
            }
        }

        // Fall back to the regular location description
        return requestHelpLocationDescription
    }

    // MARK: - Polls State
    struct Poll: Identifiable, Codable {
        let id: UUID
        let question: String
        let options: [String]
        var votes: [Int]  // index-matched to options
        var userVote: Int?  // index of user's vote, if any
        var expiresAt: Date?  // Optional expiration date/time
    }
    // State for poll expiration
    @State private var newPollHasTimeLimit: Bool = false
    @State private var newPollExpiresAt: Date =
        Calendar.current.date(byAdding: .day, value: 1, to: Date())
        ?? Date().addingTimeInterval(86400)
    @AppStorage("activePollData") private var activePollData: String = ""
    @AppStorage("archivedPollsData") private var archivedPollsData: String = ""
    // Persistent fallback user id when Firebase Auth uid is not available.
    @AppStorage("fallbackUserId") private var fallbackUserId: String = ""
    @State private var activePoll: Poll? = nil
    @State private var archivedPolls: [Poll] = []
    @State private var archivedPollsExpanded: Bool = false
    @State private var isDeletingPoll: Bool = false
    @State private var showDeletePollConfirmation: Bool = false
    @State private var votingOptionIndex: Int? = nil

    // User poll statistics
    private var userPollStats: (participated: Int, total: Int) {
        var participatedCount = 0
        var totalPolls = 0

        // Count active poll
        if let poll = activePoll {
            totalPolls += 1
            if poll.userVote != nil {
                participatedCount += 1
            }
        }

        // Count archived polls
        totalPolls += archivedPolls.count
        participatedCount += archivedPolls.filter { $0.userVote != nil }.count

        return (participatedCount, totalPolls)
    }

    // Save poll to AppStorage
    private func saveActivePoll() {
        // Remove expired poll if needed
        if let poll = activePoll, let expiresAt = poll.expiresAt, expiresAt < Date() {
            archivePoll(poll)
            activePoll = nil
            activePollData = ""
            // Also delete from Firebase to clean up expired polls
            #if canImport(FirebaseFirestore)
                FirebaseManager.shared.deleteActivePoll { err in
                    if let err = err {
                        print("Failed to delete expired poll from Firebase: \(err)")
                    } else {
                        print("Expired poll successfully removed from Firebase")
                    }
                }
            #endif
            return
        }
        #if canImport(FirebaseFirestore)
            // If Firebase available, push to Firestore instead of local AppStorage
            if let poll = activePoll {
                let dto = FirebaseManager.PollDTO(
                    id: poll.id.uuidString,
                    question: poll.question,
                    options: poll.options,
                    votes: poll.votes,
                    votesByUser: nil,
                    expiresAt: poll.expiresAt.map { Timestamp(date: $0) },
                    createdAt: Timestamp(date: Date())
                )
                FirebaseManager.shared.createOrUpdateActivePoll(dto) { err in
                    if let err = err {
                        print("Failed to save active poll to Firestore: \(err)")
                        // fallback to AppStorage
                        if let data = try? JSONEncoder().encode(poll) {
                            activePollData = String(data: data, encoding: .utf8) ?? ""
                        }
                    }
                }
                return
            } else {
                // If activePoll is nil locally, do not auto-delete the remote active poll.
                // Instead, mark it as archived via FirebaseManager.archiveActivePoll when archiving action is explicitly taken.
                activePollData = ""
                return
            }
        #else
            if let poll = activePoll, let data = try? JSONEncoder().encode(poll) {
                activePollData = String(data: data, encoding: .utf8) ?? ""
            } else {
                activePollData = ""
            }
        #endif
    }

    // Load poll from AppStorage
    private func loadActivePoll() {
        // Load archived polls
        if let data = archivedPollsData.data(using: .utf8), !archivedPollsData.isEmpty {
            if let decoded = try? JSONDecoder().decode([Poll].self, from: data) {
                // Preserve order but deduplicate by id in case the same poll was archived multiple times
                var seen: Set<UUID> = []
                archivedPolls = decoded.filter { p in
                    if seen.contains(p.id) { return false }
                    seen.insert(p.id)
                    return true
                }
            }
        } else {
            archivedPolls = []
        }
        // If Firestore is available, start watching the active poll document
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.watchActivePoll { dto in
                DispatchQueue.main.async {
                    // Don't update if we're currently deleting a poll or voting is in progress
                    guard !self.isDeletingPoll && self.votingOptionIndex == nil else {
                        print("🗳️ Ignoring Firebase poll update - deletion or voting in progress")
                        return
                    }

                    guard let dto = dto else {
                        print("🗳️ No active poll data - clearing local poll")
                        self.activePoll = nil
                        self.activePollData = ""
                        return
                    }

                    // map DTO -> local Poll
                    let id = UUID(uuidString: dto.id) ?? UUID()
                    let expires = dto.expiresAt?.dateValue()
                    // Use consistent user ID logic
                    let currentUserId = self.getCurrentUserId()
                    print("🗳️ Loading poll for user ID: \(currentUserId)")

                    var userVote: Int? = nil
                    if let byUser = dto.votesByUser {
                        if let idx = byUser[currentUserId] {
                            userVote = idx
                            print("🗳️ Found existing vote: option \(idx)")
                        } else {
                            print("🗳️ No existing vote found for user")
                        }
                    }
                    // Ensure votes array matches options array length to prevent crashes
                    var safeVotes = dto.votes
                    while safeVotes.count < dto.options.count {
                        safeVotes.append(0)
                    }
                    while safeVotes.count > dto.options.count {
                        safeVotes.removeLast()
                    }

                    let poll = Poll(
                        id: id, question: dto.question, options: dto.options, votes: safeVotes,
                        userVote: userVote, expiresAt: expires)
                    // if expired, archive
                    if let e = poll.expiresAt, e < Date() {
                        print("🗳️ Poll has expired, archiving locally and clearing active poll")
                        self.archivePoll(poll)
                        self.activePoll = nil
                        self.activePollData = ""
                    } else {
                        print("🗳️ Setting active poll: \(poll.question)")
                        self.activePoll = poll
                        // Persist sanitized poll to AppStorage (newsletter pattern)
                        if let data = try? JSONEncoder().encode(poll) {
                            self.activePollData = String(data: data, encoding: .utf8) ?? ""
                        }
                    }
                }
            }
        #else
            guard !activePollData.isEmpty, let data = activePollData.data(using: .utf8) else {
                activePoll = nil
                return
            }
            if let poll = try? JSONDecoder().decode(Poll.self, from: data) {
                // If poll is expired, archive it
                if let expiresAt = poll.expiresAt, expiresAt < Date() {
                    archivePoll(poll)
                    activePoll = nil
                    activePollData = ""
                } else {
                    activePoll = poll
                }
            } else {
                activePoll = nil
            }
        #endif
    }

    // Archive poll
    private func archivePoll(_ poll: Poll) {
        // Remove any existing entry with same id to avoid duplicates, then insert at front
        archivedPolls.removeAll { $0.id == poll.id }
        archivedPolls.insert(poll, at: 0)
        // Keep only 5 most recent archived polls
        if archivedPolls.count > 5 {
            archivedPolls = Array(archivedPolls.prefix(5))
        }
        if let data = try? JSONEncoder().encode(archivedPolls) {
            archivedPollsData = String(data: data, encoding: .utf8) ?? ""
        }
        #if canImport(FirebaseFirestore)
            // Also persist archived poll to Firestore so other clients can see it.
            // Use archiveActivePoll to copy the active doc into archived/items/{id}
            FirebaseManager.shared.archiveActivePoll(id: poll.id.uuidString) { err in
                if let err = err {
                    print("Failed to archive active poll in Firestore: \(err)")
                }
            }
        #endif
    }

    // Delete poll (admin only)
    private func deleteActivePoll() {
        isDeletingPoll = true
        #if canImport(FirebaseFirestore)
            // First archive the poll, then delete the active document completely
            if let poll = activePoll {
                FirebaseManager.shared.archiveActivePoll(id: poll.id.uuidString) { err in
                    if let err = err {
                        print("Failed to archive poll: \(err)")
                    }
                    // Whether archive succeeded or failed, delete the active poll document completely
                    FirebaseManager.shared.deleteActivePoll { deleteErr in
                        DispatchQueue.main.async {
                            if let deleteErr = deleteErr {
                                print("Failed to delete active poll in Firestore: \(deleteErr)")
                            } else {
                                print("Successfully deleted active poll from Firebase")
                            }
                            // Clear locally regardless of Firebase result
                            self.activePoll = nil
                            self.activePollData = ""
                            self.isDeletingPoll = false
                        }
                    }
                }
            } else {
                // No active poll to delete
                self.isDeletingPoll = false
            }
        #else
            // If no Firebase, delete locally only
            activePoll = nil
            activePollData = ""
            isDeletingPoll = false
        #endif
    }
    private func deleteArchivedPoll(at offsets: IndexSet) {
        // Delete locally and remotely (if available). Determine IDs to remove.
        let toRemove = offsets.compactMap { idx in
            archivedPolls.indices.contains(idx) ? archivedPolls[idx].id : nil
        }
        archivedPolls.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(archivedPolls) {
            archivedPollsData = String(data: data, encoding: .utf8) ?? ""
        }
        #if canImport(FirebaseFirestore)
            for id in toRemove {
                FirebaseManager.shared.deleteArchivedPoll(id: id.uuidString) { err in
                    if let err = err {
                        print("Failed to delete archived poll in Firestore: \(err)")
                    }
                }
            }
        #endif
    }

    var body: some View {
        ZStack {
            if showingOnboarding {
                OnboardingView(showingOnboarding: $showingOnboarding, registerUser: registerUser)
            } else {
                mainContentView
            }
        }
        .sheet(isPresented: $showRequestHelpSheet) {
            RequestHelpSheet(
                isPresented: $showRequestHelpSheet,
                locationDescription: requestHelpLocationDescription,
                weatherService: weatherService,
                onSendHelp: { helpType, message, photoData, fireData in
                    // Update the parent's firePhotoData if provided
                    if let photoData = photoData {
                        firePhotoData = photoData
                    }

                    // Update fireVM with data from the sheet if it's a fire report
                    if let fireData = fireData, helpType == .fire {
                        #if DEBUG
                            print("🔥 Updating fireVM with sheet data:")
                            print("  - Building Type: \(fireData.buildingType)")
                            print("  - Use Device Location: \(fireData.useDeviceLocation)")
                            print("  - Location Input: '\(fireData.locationInput)'")
                            print(
                                "  - Detailed Location: '\(fireData.detailedLocationDescription)'")
                            print("  - Message: '\(message)'")
                            print("  - Photo Data: \(photoData?.count ?? 0) bytes")
                        #endif

                        fireVM.report.buildingType = fireData.buildingType
                        fireVM.report.useDeviceLocation = fireData.useDeviceLocation
                        fireVM.report.useProfileContact = fireData.useProfileContact
                        fireVM.report.contactName = fireData.contactName
                        fireVM.report.contactPhone = fireData.contactPhone
                        fireVM.report.reportedAt = fireData.dateTime
                        fireVM.report.notes = message  // Set the message as notes

                        // Ensure reporter info is maintained
                        fireVM.report.reporterName = userName
                        fireVM.report.reporterSurname = userSurname
                        fireVM.report.reporterCell = userCell

                        fireDateTime = fireData.dateTime
                        fireLocationInput = fireData.locationInput

                        // Update photo data in fireVM
                        if let photoData = photoData {
                            fireVM.report.photoData = photoData
                        }

                        // Handle location - if not using device location, set the manual input as resolved address
                        if !fireData.useDeviceLocation && !fireData.locationInput.isEmpty {
                            fireVM.report.resolvedAddress = fireData.locationInput
                            fireVM.report.location = fireData.locationInput
                        } else if fireData.useDeviceLocation {
                            // Use the detailed location from the sheet
                            fireVM.report.resolvedAddress = fireData.detailedLocationDescription
                            fireVM.report.location = fireData.detailedLocationDescription
                            // Store detailed location temporarily for the incident report
                            UserDefaults.standard.set(
                                fireData.detailedLocationDescription,
                                forKey: "tempFireDetailedLocation")
                        }

                        #if DEBUG
                            print("🔥 FireVM updated. Final state:")
                            print("  - Notes: '\(fireVM.report.notes)'")
                            print(
                                "  - Reporter: \(fireVM.report.reporterName) \(fireVM.report.reporterSurname)"
                            )
                            print(
                                "  - Contact: \(fireVM.report.contactName) / \(fireVM.report.contactPhone)"
                            )
                            print("  - Location: '\(fireVM.report.resolvedAddress)'")
                        #endif
                    } else {
                        // For Emergency/Medical: Store detailed location from fireData
                        if let fireData = fireData {
                            // Always use the detailed location for emergency/medical incidents
                            let locationToUse =
                                fireData.useDeviceLocation
                                ? fireData.detailedLocationDescription : fireData.locationInput

                            if !locationToUse.isEmpty {
                                UserDefaults.standard.set(
                                    locationToUse, forKey: "tempManualLocation")
                                UserDefaults.standard.set(true, forKey: "tempManualLocationUsed")
                            }
                        }
                    }

                    Task {
                        await sendHelpRequest(type: helpType, message: message)
                    }
                },
                fireNumber: $fireNumber,
                emergencyNumber: $emergencyNumber,
                medicalNumber: $medicalNumber
            )
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleReminderSheet(
                isPresented: $showScheduleSheet,
                scheduledReminders: $scheduledReminders,
                saveReminders: saveReminders
            )
        }
        .sheet(isPresented: $showPollCreationSheet) {
            PollCreationSheet(isPresented: $showPollCreationSheet, createPoll: createPoll)
        }
        .sheet(isPresented: $showingSettings) {
            HomeSettingsView(
                homeSectionOrder: $homeSectionOrder,
                homeSectionVisibility: $homeSectionVisibility,
                allowEveryoneToCreatePolls: $allowEveryoneToCreatePolls,
                allowEveryoneToCreateNewsletters: $allowEveryoneToCreateNewsletters,
                isPresented: $showingSettings,
                onSave: saveSettings,
                onRestartOnboarding: {
                    showingSettings = false
                    showingOnboarding = true
                }
            )
        }
        .onAppear {
            // Track screen view
            AnalyticsService.shared.trackScreenView("Home")
            
            // Watch emergency settings for real-time updates
            print("🎬 HomeView: Setting up emergency settings watcher")
            FirebaseManager.shared.watchEmergencySettings { settings in
                print("📞 HomeView: Received emergency settings update")
                print("   Fire: \(settings.fireNumber), Emergency: \(settings.emergencyNumber), Medical: \(settings.medicalNumber)")
                DispatchQueue.main.async {
                    self.fireNumber = settings.fireNumber
                    self.emergencyNumber = settings.emergencyNumber
                    self.medicalNumber = settings.medicalNumber
                }
            }
        }
    }

    private var mainContentView: some View {
        ZStack {
            navigationStackContent
            floatingHelpButton
        }
    }

    private var navigationStackContent: some View {
        NavigationStack {
            scrollableContent
                .refreshable {
                    weatherService.refreshWeather()
                    fetchScheduledReminders()
                }
                .navigationTitle("NeighbourHUB")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        settingsButton
                    }
                }
                .onAppear(perform: handleOnAppear)
                .onDisappear(perform: handleOnDisappear)
                .onChange(of: eventsData) { _, _ in
                    Task { @MainActor in
                        loadEvents()
                        fetchScheduledReminders()
                    }
                }
                .onChange(of: communityMessagesData) { _, _ in
                    Task { @MainActor in
                        loadMessages()
                    }
                }
        }
    }

    private var scrollableContent: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                homeSectionsContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { appState.showingSettings = true }) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 8, x: 0, y: 4)
                Text(initials)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
        }
        .accessibilityLabel("Settings")
    }

    private func handleOnAppear() {
        // Note: ContentView now handles showing onboarding for unauthenticated users
        // This check is only for authenticated users who haven't completed their profile
        // (edge case where auth exists but profile incomplete)
        checkAndShowOnboarding()

        loadSettings()  // Load user settings from AppStorage
        loadEvents()  // Always reload events to get latest data
        loadMessages()
        startHomeCommunityMessagesListener()
        fetchScheduledReminders()
        loadActivePoll()
        watchArchivedPolls()

        // Request location and weather data
        setupWeatherService()
    }

    private func checkAndShowOnboarding() {
        // Only show onboarding overlay if authenticated user has incomplete profile
        // ContentView handles authentication-level onboarding
        #if canImport(FirebaseAuth)
        guard Auth.auth().currentUser != nil else {
            // User not authenticated - ContentView will handle this
            return
        }
        #endif
        
        // Check if user has completed registration
        let hasUserData =
            !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userSurname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Check if we have any registered users in Core Data
        let hasRegisteredUsers = !users.isEmpty

        // Show onboarding if authenticated user has no profile data
        // (edge case: auth account exists but profile incomplete)
        if !hasUserData && !hasRegisteredUsers {
            showingOnboarding = true
        }
    }

    private func setupWeatherService() {
        // Request location permission if needed
        weatherService.locationManager.requestWhenInUse()

        // Start continuous location tracking for accurate weather
        weatherService.locationManager.startLocationUpdates()

        // Also try to refresh weather data with current location
        weatherService.refreshWeather()
    }

    private func handleOnDisappear() {
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.stopWatchingActivePoll()
            FirebaseManager.shared.stopWatchingCommunityMessages()
            FirebaseManager.shared.stopWatchingArchivedPolls()
        #endif
        // Note: Keep location updates running for accurate weather even when view is not visible
        // Location updates are lightweight and provide better user experience
    }

    private func watchArchivedPolls() {
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.watchArchivedPolls { items in
                var mapped: [Poll] = []
                for item in items {
                    if let idStr = item["id"] as? String, let id = UUID(uuidString: idStr),
                        let question = item["question"] as? String,
                        let options = item["options"] as? [String],
                        let votesAny = item["votes"] as? [Any]
                    {
                        var votes: [Int] = []
                        for v in votesAny {
                            if let i = v as? Int {
                                votes.append(i)
                            } else if let i64 = v as? Int64 {
                                votes.append(Int(i64))
                            } else if let num = v as? NSNumber {
                                votes.append(num.intValue)
                            } else {
                                votes.append(0)
                            }
                        }
                        var expires: Date? = nil
                        if let exp = item["expiresAt"] as? TimeInterval {
                            expires = Date(timeIntervalSince1970: exp)
                        }

                        // Parse user vote from votesByUser data
                        var userVote: Int? = nil
                        if let votesByUser = item["votesByUser"] as? [String: Any] {
                            let currentUserId = getCurrentUserId()
                            if let userVoteIndex = votesByUser[currentUserId] as? Int {
                                userVote = userVoteIndex
                            } else if let userVoteIndex = votesByUser[currentUserId] as? Int64 {
                                userVote = Int(userVoteIndex)
                            } else if let userVoteIndex = votesByUser[currentUserId] as? NSNumber {
                                userVote = userVoteIndex.intValue
                            }
                        }

                        let poll = Poll(
                            id: id, question: question, options: options, votes: votes,
                            userVote: userVote, expiresAt: expires)
                        mapped.append(poll)
                    }
                }
                DispatchQueue.main.async {
                    archivedPolls = mapped
                    if let data = try? JSONEncoder().encode(archivedPolls) {
                        archivedPollsData = String(data: data, encoding: .utf8) ?? ""
                    }
                }
            }
        #endif
    }

    private var floatingHelpButton: some View {
        VStack {
            Spacer()
            HStack {
                if floatingHelpButtonPosition == "left" {
                    helpButton
                    Spacer()
                } else if floatingHelpButtonPosition == "center" {
                    Spacer()
                    helpButton
                    Spacer()
                } else {
                    Spacer()
                    helpButton
                }
            }
            .padding()
            .accessibilityLabel("Request Help")
        }
    }

    private var helpButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            showRequestHelpSheet = true
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundColor(.white)
                    .font(.title2)
            }
        }
    }

    // MARK: - Request Help Sheet and other sheets handled by body's .sheet modifiers

    // MARK: - Section View Dispatcher
    // Centralized send helper for request help
    private func sendHelpRequest(type: HelpType, message: String) async {
        // Haptic to confirm send
        let h = UIImpactFeedbackGenerator(style: .heavy)
        h.impactOccurred()

        // Compose shared details
        let name = users.first?.name ?? "\(userName) \(userSurname)"
        let address: String = {
            if let addr = users.first?.address,
                !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return addr
            }
            let parts = [userStreet, userSuburb, userCity, userPostalCode].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            return parts.joined(separator: ", ")
        }()

        let cell = userCell

        // If the user chooses not to use their profile contact details for a fire report,
        // prefer the manually entered contact details and persist them on the LocalEvent so
        // the message card can display who responders should contact. Also keep the view model in sync.
        var contactInfo: EmergencyRequestManager.RecipientInfo? = nil
        if type == .fire {
            fireVM.report.useProfileContact = fireUseMyDetailsBinding.wrappedValue
            if !fireUseMyDetailsBinding.wrappedValue {
                let trimmedName = fireContactNameBinding.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let trimmedPhone = fireContactPhoneBinding.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                fireVM.report.contactName = trimmedName
                fireVM.report.contactPhone = trimmedPhone
                if !trimmedName.isEmpty || !trimmedPhone.isEmpty {
                    contactInfo = EmergencyRequestManager.RecipientInfo(
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        phone: trimmedPhone.isEmpty ? nil : trimmedPhone, relationship: nil)
                }
            }
            // populate reporter info from AppStorage/CoreData
            fireVM.report.reporterName = userName
            fireVM.report.reporterSurname = userSurname
            fireVM.report.reporterCell = userCell
        }

        // Compute location and date
        // Determine location description. For fire this may use fire-specific resolved address.
        var locationDesc: String = requestHelpLocationDescription
        // If fire and using device location, prefer resolved address from fireResolvedAddressBinding
        if type == .fire {
            if fireUseDeviceLocationBinding.wrappedValue {
                // Use the detailed location from FireReportData if available
                if let fireData = UserDefaults.standard.string(forKey: "tempFireDetailedLocation"),
                    !fireData.isEmpty
                {
                    locationDesc = fireData
                    UserDefaults.standard.removeObject(forKey: "tempFireDetailedLocation")
                } else {
                    locationDesc =
                        fireResolvedAddressBinding.wrappedValue.isEmpty
                        ? requestHelpLocationDescription : fireResolvedAddressBinding.wrappedValue
                }
            } else {
                let trimmed = fireLocationInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { locationDesc = trimmed }
            }
        } else {
            // For emergency and medical: check if manual location was provided
            if let manualLocation = UserDefaults.standard.string(forKey: "tempManualLocation"),
                !manualLocation.isEmpty
            {
                locationDesc = manualLocation
                UserDefaults.standard.removeObject(forKey: "tempManualLocation")  // Clean up
            } else if let loc = weatherService.locationManager.currentLocation {
                // Try reverse-geocoding to a human address
                let geocoder = CLGeocoder()
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(loc)
                    if let p = placemarks.first {
                        var lines: [String] = []
                        if let name = p.name { lines.append(name) }
                        if let thoroughfare = p.thoroughfare { lines.append(thoroughfare) }
                        if let locality = p.locality { lines.append(locality) }
                        if let administrative = p.administrativeArea {
                            lines.append(administrative)
                        }
                        if let postal = p.postalCode { lines.append(postal) }
                        let composed = lines.joined(separator: ", ")
                        if !composed.isEmpty {
                            locationDesc = composed
                        } else {
                            // fallback to precise coords string
                            locationDesc = String(
                                format: "Lat: %.5f, Lon: %.5f", loc.coordinate.latitude,
                                loc.coordinate.longitude)
                        }
                        // Also set fireVM.report coordinates so other code can use them if needed
                        await MainActor.run {
                            fireVM.report.resolvedAddress = locationDesc
                            fireVM.report.coordinates = loc.coordinate
                        }
                    }
                } catch {
                    // If geocode fails, fall back to coords if available
                    locationDesc = String(
                        format: "Lat: %.5f, Lon: %.5f", loc.coordinate.latitude,
                        loc.coordinate.longitude)
                }
            } else {
                locationDesc = requestHelpLocationDescription
            }
        }
        let eventDate: Date = (type == .fire) ? fireDateTime : Date()

        // Additional fire metadata
        var fireMeta: [String: String] = [:]
        if type == .fire {
            fireMeta["buildingType"] = fireVM.report.buildingType
            fireMeta["usedDeviceLocation"] = fireVM.report.useDeviceLocation ? "yes" : "no"
            if fireVM.report.buildingType == "Other"
                && !fireVM.report.buildingOtherDescription.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                fireMeta["buildingOtherDescription"] = fireVM.report.buildingOtherDescription
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            // For emergency/medical, add location metadata
            let usedManualLocation =
                UserDefaults.standard.object(forKey: "tempManualLocationUsed") != nil
            if usedManualLocation {
                fireMeta["usedDeviceLocation"] = "no"
                fireMeta["manualLocationProvided"] = "yes"
                UserDefaults.standard.removeObject(forKey: "tempManualLocationUsed")  // Clean up
            } else if let loc = weatherService.locationManager.currentLocation {
                fireMeta["usedDeviceLocation"] = "yes"
                fireMeta["deviceLat"] = String(format: "%.7f", loc.coordinate.latitude)
                fireMeta["deviceLon"] = String(format: "%.7f", loc.coordinate.longitude)
            } else {
                fireMeta["usedDeviceLocation"] = "no"
            }
        }

        // Map local HelpType to manager type
        let mgrType: EmergencyRequestManager.EmergencyType
        switch type {
        case .fire: mgrType = .fire
        case .emergency: mgrType = .emergency
        case .medical: mgrType = .medical
        }

        // Build and persist LocalEvent via the manager
        // At this point the view model should already be in sync via bindings and onChange handlers.

        let event = emergencyRequestManager.buildLocalEvent(
            type: mgrType,
            message: message.isEmpty ? nil : message,
            location: locationDesc.isEmpty ? nil : locationDesc,
            date: eventDate,
            creatorName: userName.isEmpty ? nil : userName,
            creatorSurname: userSurname.isEmpty ? nil : userSurname,
            contact: contactInfo,
            metadata: fireMeta,
            imageData: firePhotoData)
        events.insert(event, at: 0)
        saveEvents()
        // Also save a lightweight copy for the Watch UI (watchIncidents AppStorage key)
        // Format: "<ts>|<title>|<description>|<showOnHome>" and entries are semicolon-separated.
        do {
            let ts = event.date.timeIntervalSince1970
            let titleSafe = event.title.replacingOccurrences(of: "|", with: " ")
            let descSafe = (event.description ?? "").replacingOccurrences(of: "|", with: " ")
            let showOnHomeFlag = "1"  // requests are shown on the watch UI by default
            let newEntry = "\(ts)|\(titleSafe)|\(descSafe)|\(showOnHomeFlag)"
            let key = "watchIncidents"
            let defaults = UserDefaults.standard
            let existing = defaults.string(forKey: key) ?? ""
            let updated = existing.isEmpty ? newEntry : (newEntry + ";" + existing)
            defaults.setValue(updated, forKey: key)
        }

        // Create an Incident document in Firestore so all users (and the Watch UI backed by server) can see the request.
        // Include any captured photo data and detailed metadata so FirebaseManager can upload it to Storage and save searchable fields.
        let incident = FirebaseManager.Incident(
            id: UUID(),
            title: event.title,
            description: event.description,
            date: event.date,
            showOnHome: true,
            creatorName: userName.isEmpty ? nil : userName,
            creatorSurname: userSurname.isEmpty ? nil : userSurname,
            archivedAt: nil,
            incidentType: mgrType.rawValue,
            location: locationDesc.isEmpty ? nil : locationDesc,
            // Prefer any explicit contactInfo (manual fire contact or emergency contact). If not provided,
            // fall back to the reporting user's profile name and cell so the incident always contains
            // a tappable contact for responders.
            contactName: contactInfo?.name
                ?? (userName.isEmpty
                    ? nil : userName + (userSurname.isEmpty ? "" : " " + userSurname)),
            contactPhone: contactInfo?.phone ?? (userCell.isEmpty ? nil : userCell),
            metadata: fireMeta.isEmpty ? nil : fireMeta,
            imageURL: nil,
            imageData: firePhotoData,
            imageLocalPath: nil
        )
        FirebaseManager.shared.createOrUpdateIncident(incident) { err, imageURL in
            if let err = err {
                #if DEBUG
                    print("Failed to create incident in Firestore: \(err)")
                #endif
            }
            // Create a global active alert so all users are notified in real-time.
            // If an image was uploaded, include the imageURL in the alert.
            let alert = FirebaseManager.ActiveAlert(
                id: UUID().uuidString,
                title: event.title,
                message: event.description,
                location: event.location,
                contactName: event.contactName ?? event.creatorName,
                contactPhone: event.contactCell ?? (event.creatorName == nil ? nil : userCell),
                imageURL: imageURL,
                createdAt: nil,
                createdBy: Auth.auth().currentUser?.uid
            )
            FirebaseManager.shared.createActiveAlert(alert) { aerr in
                #if DEBUG
                    if let aerr = aerr { print("Failed to create active alert: \(aerr)") }
                #endif
            }
        }

        // Build full message body


        // Resolve recipient phone: prefer configured helpRecipientPhone, then (for fire) user-provided fire contact,
        // then emergency contact, then user cell.
        let resolvedRecipient: String = {
            let override = helpRecipientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !override.isEmpty { return override }
            // If fire and user provided a fireContactPhone, prefer that
            if type == .fire && !fireUseMyDetailsBinding.wrappedValue {
                let f = fireContactPhoneBinding.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if !f.isEmpty { return f }
            }
            if let emergencyPhone = contactInfo?.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
                !emergencyPhone.isEmpty
            {
                return emergencyPhone
            }
            return cell.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // Normalize for WhatsApp (assume local country code when needed)
        var waNumber: String? = nil
        let candidate = resolvedRecipient.filter { $0.isNumber }
        if !candidate.isEmpty {
            if candidate.hasPrefix("0") && candidate.count == 10 {
                waNumber = "27" + candidate.dropFirst()
            } else {
                waNumber = candidate
            }
        }

        // Delegate send to manager (server send with WhatsApp fallback handled by manager)
        let serverURL = URL(string: helpServerURL.trimmingCharacters(in: .whitespacesAndNewlines))
        if mgrType == .fire {
            // Use the view model to send fire reports (validation + state)
            // Note: fireVM data is already updated in the sheet callback
            let apiKey =
                helpServerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : helpServerAPIKey

            #if DEBUG
                print("🔥 Sending fire report via fireVM.send()")
                print("  - Final fireVM notes: '\(fireVM.report.notes)'")
                print("  - Final fireVM location: '\(fireVM.report.location)'")
                print("  - Final fireVM resolved address: '\(fireVM.report.resolvedAddress)'")
            #endif

            fireVM.send(
                serverURL: serverURL,
                serverAPIKey: apiKey,
                waNumber: waNumber,
                manager: emergencyRequestManager)
        } else {
            emergencyRequestManager.sendRequest(
                type: mgrType,
                name: name,
                address: address.isEmpty ? nil : address,
                cell: cell.isEmpty ? nil : cell,
                emergencyContact: contactInfo,
                description: message.isEmpty ? nil : message,
                metadata: fireMeta.isEmpty ? nil : fireMeta,
                reportedDate: eventDate,
                photoAttached: firePhotoData != nil,
                serverURL: serverURL,
                serverAPIKey: helpServerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? nil : helpServerAPIKey,
                waNumber: waNumber)
        }

        // Dismiss and clear UI state
        showRequestHelpSheet = false
        helpRequestText = ""
        selectedHelpType = nil
    }

    // MARK: - Missing Functions
    private func fetchScheduledReminders() {
        let key = "scheduledRemindersData"
        let defaults = UserDefaults.standard
        guard let dataStr = defaults.string(forKey: key), !dataStr.isEmpty,
            let data = dataStr.data(using: .utf8)
        else {
            scheduledReminders = []
            return
        }
        if let reminders = try? JSONDecoder().decode([ReminderInfo].self, from: data) {
            // Clean up expired reminders (older than 2 hours)
            let cleanedReminders = cleanupExpiredReminders(reminders)
            scheduledReminders = cleanedReminders
            
            // Save cleaned reminders back to storage if any were removed
            if cleanedReminders.count != reminders.count {
                saveReminders()
            }
        } else {
            scheduledReminders = []
        }
    }
    
    private func cleanupExpiredReminders(_ reminders: [ReminderInfo]) -> [ReminderInfo] {
        let now = Date()
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60 // 2 hours
        
        return reminders.filter { reminder in
            let timeSinceReminder = now.timeIntervalSince(reminder.date)
            return timeSinceReminder <= twoHoursInSeconds
        }
    }

    private func saveReminders() {
        let key = "scheduledRemindersData"
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(scheduledReminders) {
            let dataString = String(data: data, encoding: .utf8) ?? ""
            defaults.set(dataString, forKey: key)
        }
    }

    private func createPoll(question: String, options: [String]) {
        // Implement poll creation logic
        // This would typically involve saving to Firebase or local storage
        print("Creating poll: \(question) with options: \(options)")
        // Close the sheet
        showPollCreationSheet = false
    }

    // MARK: - Settings Persistence
    private func loadSettings() {
        // Load boolean settings
        allowEveryoneToCreatePolls = storedAllowPolls
        allowEveryoneToCreateNewsletters = storedAllowNewsletters

        // Load section order
        if !storedSectionOrderData.isEmpty,
            let data = storedSectionOrderData.data(using: .utf8),
            let sections = try? JSONDecoder().decode([HomeSection].self, from: data)
        {
            homeSectionOrder = sections
        }

        // Load section visibility
        if !storedSectionVisibilityData.isEmpty,
            let data = storedSectionVisibilityData.data(using: .utf8),
            let visibility = try? JSONDecoder().decode([String: Bool].self, from: data)
        {
            // Convert string keys back to HomeSection enum
            var newVisibility: [HomeSection: Bool] = [:]
            for (key, value) in visibility {
                if let section = HomeSection.allCases.first(where: { "\($0)" == key }) {
                    newVisibility[section] = value
                }
            }
            homeSectionVisibility = newVisibility
        }
    }

    private func saveSettings() {
        // Save boolean settings
        storedAllowPolls = allowEveryoneToCreatePolls
        storedAllowNewsletters = allowEveryoneToCreateNewsletters

        // Save section order
        if let data = try? JSONEncoder().encode(homeSectionOrder),
            let string = String(data: data, encoding: .utf8)
        {
            storedSectionOrderData = string
        }

        // Save section visibility (convert enum keys to strings for JSON)
        let stringKeysVisibility = Dictionary(
            uniqueKeysWithValues:
                homeSectionVisibility.map { (key, value) in ("\(key)", value) }
        )
        if let data = try? JSONEncoder().encode(stringKeysVisibility),
            let string = String(data: data, encoding: .utf8)
        {
            storedSectionVisibilityData = string
        }
    }

    @ViewBuilder
    // MARK: - Home Sections Content
    private var homeSectionsContent: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            WellnessCheckPromptView()
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(homeSectionOrder, id: \.self) { section in
                if homeSectionVisibility[section, default: true] {
                    sectionView(for: section)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sectionView(for section: HomeSection) -> AnyView {
        switch section {
        case .weather:
            return AnyView(weatherSectionView)
        case .websiteLink:
            return AnyView(WebsiteLinkCard())
        case .polls:
            return AnyView(pollsSectionView)
        case .requestHelp:
            return AnyView(EmptyView())  // moved to floating button overlay
        case .stats:
            return AnyView(statsSectionView)
        case .reminders:
            return AnyView(remindersSectionView)
        case .events:
            return AnyView(eventsSectionView)
        case .newsletters:
            return AnyView(
                NewslettersCard(allowEveryoneToCreateNewsletters: allowEveryoneToCreateNewsletters))
        case .localListings:
            return AnyView(LocalListingsCard(listingManager: localListingManager))
        }
    }

    // MARK: - Section Views
    private var weatherSectionView: some View {
        VStack(spacing: 0) {
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.2)) {
                    weatherExpanded.toggle()
                }
            }) {
                HStack {
                    if weatherService.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 4)
                            .accessibilityLabel("Loading weather data")
                    } else if weatherService.currentWeather == nil {
                        Image(systemName: "cloud.slash.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 4)
                            .accessibilityLabel("Weather unavailable")
                    }
                    WeatherHeaderView(weatherService: weatherService)
                        .accessibilityLabel("Weather summary")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(weatherService.locationName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Image(systemName: weatherExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityAddTraits(.isButton)
            if weatherExpanded {
                Divider()
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                WeatherDetailsView(weatherService: weatherService)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .background(Color.appBackground.opacity(0.95))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 2)
    }

    private var pollsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { pollsExpanded.toggle() }) {
                HStack {
                    Image(systemName: pollsExpanded ? "chart.bar.fill" : "chart.bar")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Polls & Votes")
                            .font(.headline)
                            .foregroundColor(.purple)
                        if isCommitteeMember {
                            Text("Committee Member")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else if allowEveryoneToCreatePolls {
                            Text("Create Enabled")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else {
                            Text("View Only")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: pollsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.purple)
                        .font(.caption)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            if pollsExpanded {
                // User poll participation statistics
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundColor(.purple)
                        Text("Your Participation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.purple)
                        Spacer()
                        Text("\(userPollStats.participated)/\(userPollStats.total)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }

                    if userPollStats.total > 0 {
                        HStack {
                            Text("Participation Rate:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            let rate =
                                Double(userPollStats.participated) / Double(userPollStats.total)
                                * 100
                            Text("\(Int(rate))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(rate >= 80 ? .green : rate >= 50 ? .orange : .red)
                        }
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(10)
                .padding(.bottom, 8)

                if allowEveryoneToCreatePolls || isCommitteeMember {
                    Button(action: {
                        showCreatePollSheet = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.purple)
                            Text("Create New Poll")
                                .font(.headline)
                                .foregroundColor(.purple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showCreatePollSheet) {
                        NavigationView {
                            Form {
                                Section(header: Text("Poll Question")) {
                                    SmartTextField(
                                        "Enter poll question",
                                        text: $newPollQuestion,
                                        keyboardType: .default,
                                        autocapitalization: .sentences,
                                        autocorrection: true
                                    )
                                }
                                Section(header: Text("Options (at least 2)")) {
                                    ForEach(Array(newPollOptions.enumerated()), id: \.offset) {
                                        offset, option in
                                        let idx = offset
                                        HStack {
                                            SmartTextField(
                                                "Option \(idx + 1)",
                                                text: Binding(
                                                    get: {
                                                        // Safe access with bounds checking
                                                        idx < newPollOptions.count
                                                            ? newPollOptions[idx] : ""
                                                    },
                                                    set: {
                                                        // Safe assignment with bounds checking
                                                        if idx < newPollOptions.count {
                                                            newPollOptions[idx] = $0
                                                        }
                                                    }
                                                ),
                                                keyboardType: .default,
                                                autocapitalization: .sentences,
                                                autocorrection: true
                                            )
                                            if newPollOptions.count > 2
                                                && idx < newPollOptions.count
                                            {
                                                Button(action: {
                                                    // Safe removal with bounds checking
                                                    if idx < newPollOptions.count {
                                                        print("🗑️ Removing poll option at index \(idx)")
                                                        newPollOptions.remove(at: idx)
                                                        pollOptionsRefreshID = UUID() // Force refresh
                                                        print("📊 Poll options count after removal: \(newPollOptions.count)")
                                                    }
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundColor(.red)
                                                }
                                            }
                                        }
                                    }
                                    
                                    Button(action: {
                                        print("➕ Add Option button tapped")
                                        print("📊 Poll options before: \(newPollOptions.count)")
                                        newPollOptions.append("")
                                        print("📊 Poll options after: \(newPollOptions.count)")
                                        pollOptionsRefreshID = UUID() // Force refresh
                                        print("🔄 Refresh ID updated: \(pollOptionsRefreshID)")
                                    }) {
                                        Label("Add Option", systemImage: "plus.circle")
                                    }
                                }
                                .id(pollOptionsRefreshID) // Force re-render of entire section when ID changes
                                Section(header: Text("Poll Time Limit (optional)")) {
                                    Toggle(
                                        "Set a time limit for this poll", isOn: $newPollHasTimeLimit
                                    )
                                    if newPollHasTimeLimit {
                                        DatePicker(
                                            "Expires At", selection: $newPollExpiresAt,
                                            in: Date()...,
                                            displayedComponents: [.date, .hourAndMinute])
                                    }
                                }
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .navigationTitle("Create Poll")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        showCreatePollSheet = false
                                        newPollQuestion = ""
                                        newPollOptions = ["", ""]
                                        pollOptionsRefreshID = UUID() // Reset refresh ID
                                        newPollHasTimeLimit = false
                                        newPollExpiresAt =
                                            Calendar.current.date(
                                                byAdding: .day, value: 1, to: Date())
                                            ?? Date().addingTimeInterval(86400)
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Create") {
                                        let options = newPollOptions.map {
                                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                        }.filter { !$0.isEmpty }
                                        if !newPollQuestion.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty && options.count >= 2 {
                                            activePoll = Poll(
                                                id: UUID(),
                                                question: newPollQuestion.trimmingCharacters(
                                                    in: .whitespacesAndNewlines),
                                                options: options,
                                                votes: Array(repeating: 0, count: options.count),
                                                userVote: nil,
                                                expiresAt: newPollHasTimeLimit
                                                    ? newPollExpiresAt : nil
                                            )
                                            saveActivePoll()
                                            showCreatePollSheet = false
                                            newPollQuestion = ""
                                            newPollOptions = ["", ""]
                                            pollOptionsRefreshID = UUID() // Reset refresh ID
                                            newPollHasTimeLimit = false
                                            newPollExpiresAt =
                                                Calendar.current.date(
                                                    byAdding: .day, value: 1, to: Date())
                                                ?? Date().addingTimeInterval(86400)
                                        }
                                    }
                                    .disabled(
                                        newPollQuestion.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                            || newPollOptions.map {
                                                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }.filter { !$0.isEmpty }.count < 2)
                                }
                            }
                        }
                    }
                }
                if let poll = activePoll, (poll.expiresAt == nil || poll.expiresAt! >= Date()) {
                    PollSection(
                        poll: poll,
                        votingOptionIndex: votingOptionIndex,
                        onVote: { selectedIndex in
                            // Check if user has already voted or voting is in progress
                            guard activePoll?.userVote == nil && votingOptionIndex == nil else {
                                print(
                                    "User has already voted or voting in progress, ignoring vote attempt"
                                )
                                return
                            }

                            // Set voting state to prevent conflicts and track which option is being voted on
                            votingOptionIndex = selectedIndex

                            // If using Firestore, vote via transaction to ensure consistency across users
                            #if canImport(FirebaseFirestore)
                                let voteUserId = getCurrentUserId()
                                print("🗳️ Attempting to vote with user ID: \(voteUserId)")

                                FirebaseManager.shared.voteOnActivePoll(
                                    userId: voteUserId, optionIndex: selectedIndex
                                ) { err in
                                    DispatchQueue.main.async {
                                        self.votingOptionIndex = nil

                                        if let err = err {
                                            print("🗳️ Vote failed: \(err)")
                                        } else {
                                            print(
                                                "🗳️ Vote successfully recorded for option \(selectedIndex)"
                                            )
                                            // Don't do optimistic update - let Firebase listener handle it
                                        }
                                    }
                                }
                            #else
                                // Local storage voting
                                activePoll?.votes[selectedIndex] += 1
                                activePoll?.userVote = selectedIndex
                                saveActivePoll()
                                votingOptionIndex = nil
                                print(
                                    "Local vote successfully recorded for option \(selectedIndex)")
                            #endif
                        })
                    if isCommitteeMember {
                        Button(role: .destructive) {
                            showDeletePollConfirmation = true
                        } label: {
                            HStack {
                                if isDeletingPoll {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.red)
                                } else {
                                    Image(systemName: "trash")
                                }
                                Text(isDeletingPoll ? "Deleting..." : "Delete Poll")
                            }
                            .foregroundColor(.red)
                        }
                        .disabled(isDeletingPoll)
                        .padding(.top, 4)
                        .confirmationDialog(
                            "Delete Active Poll",
                            isPresented: $showDeletePollConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete Poll", role: .destructive) {
                                deleteActivePoll()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(
                                "Are you sure you want to delete this poll? This action cannot be undone."
                            )
                        }
                    }
                }
                if !archivedPolls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { archivedPollsExpanded.toggle() }) {
                            HStack {
                                Image(
                                    systemName: archivedPollsExpanded
                                        ? "archivebox.fill" : "archivebox"
                                )
                                .foregroundColor(.gray)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Archived Polls")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    Text(
                                        "\(archivedPolls.count) poll\(archivedPolls.count == 1 ? "" : "s")"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(
                                    systemName: archivedPollsExpanded
                                        ? "chevron.up" : "chevron.down"
                                )
                                .foregroundColor(.gray)
                                .font(.caption)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        if archivedPollsExpanded {
                            // Archived polls summary
                            if !archivedPolls.isEmpty {
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Archived History")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.gray)
                                        Spacer()
                                        let participatedArchived = archivedPolls.filter {
                                            $0.userVote != nil
                                        }.count
                                        Text(
                                            "Participated in \(participatedArchived) of \(archivedPolls.count)"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }

                            ForEach(Array(archivedPolls.enumerated()), id: \.element.id) {
                                idx, poll in
                                PollSection(poll: poll, votingOptionIndex: nil, onVote: { _ in })
                                    .opacity(0.7)
                                if isCommitteeMember {
                                    Button(role: .destructive) {
                                        deleteArchivedPoll(at: IndexSet(integer: idx))
                                    } label: {
                                        Label("Delete Archived Poll", systemImage: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .padding(.bottom, 4)
                                }
                            }
                        }
                    }
                    .background(Color.gray.opacity(0.07))
                    .cornerRadius(12)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var requestHelpSectionView: some View {
        // Explicitly return the composed Button so `some View` can be inferred.
        return Button(action: {
            showRequestHelpSheet = true
        }) {
            HStack {
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.red))
                Text("Request Help")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .accessibilityLabel("Request Help Quick Action")
    }

    private var statsSectionView: some View {
        // Count upcoming non-request events for the Events stat card (ignore request-type events)
        let upcomingEventsCount = events.filter { $0.eventType == .event && $0.date >= Date() }
            .count
        let reportCount = events.filter { $0.eventType == .report }.count
        return StatMiniCardsRow(
            eventsCount: upcomingEventsCount,
            reportCount: reportCount,
            chatsCount: messages.count,
            unreadCount: unreadMessagesCount,
            onCardTap: { card in
                switch card {
                case .events:
                    selectedTab = 1  // Navigate to Events tab
                case .reports:
                    selectedTab = 2  // Navigate to Report It tab
                case .chats:
                    selectedTab = 3  // Navigate to Chats tab
                    // Update last read timestamp when navigating to chats
                    lastChatReadTimestamp = Date().timeIntervalSince1970
                }
            }
        )
        .padding(.vertical, 4)
    }

    private var remindersSectionView: some View {
        let eventIDs = Set(events.map { $0.id })
        let now = Date()
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60 // 2 hours
        
        let filteredReminders = scheduledReminders.filter { reminder in
            // First check if reminder has expired (older than 2 hours)
            let timeSinceReminder = now.timeIntervalSince(reminder.date)
            guard timeSinceReminder <= twoHoursInSeconds else {
                return false // Exclude expired reminders
            }
            
            // Extract UUID from reminder ID format: "event_reminder_UUID"
            let uuidString = reminder.id.replacingOccurrences(of: "event_reminder_", with: "")
            if let uuid = UUID(uuidString: uuidString) {
                return eventIDs.contains(uuid)
            }
            return false
        }
        return RemindersSection(reminders: filteredReminders)
    }

    private var eventsSectionView: some View {
        let now = Date()
        // Filter out request-type events AND expired events (past their date)
        let nonRequestEvents = events.filter { 
            $0.eventType != .request && $0.date >= now
        }.sorted {
            abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow)
        }
        return Group {
            if !nonRequestEvents.isEmpty {
                // Show only the next upcoming/closest event
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Next Event")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: { selectedTab = 1 }) {
                            Text("View All")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    HomeEventCard(event: nonRequestEvents[0])
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var newslettersSectionView: some View {
        NewslettersCard(allowEveryoneToCreateNewsletters: allowEveryoneToCreateNewsletters)
    }
    // MARK: - Poll Section (for voting on community projects)
    struct PollSection: View {
        let poll: HomeView.Poll
        let votingOptionIndex: Int?
        var onVote: (Int) -> Void

        // Validate poll data to prevent crashes
        private var isValidPoll: Bool {
            return poll.options.count > 0 && poll.votes.count == poll.options.count
        }

        private var totalVotes: Int {
            guard isValidPoll else { return 0 }
            return poll.votes.reduce(0, +)
        }

        private var totalVoteCountView: some View {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Total votes: \(totalVotes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if poll.userVote != nil {
                    participatedBadgeView
                }
            }
        }

        private var participatedBadgeView: some View {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Participated")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }

        private func voteStatsView(for idx: Int) -> some View {
            VStack(alignment: .trailing, spacing: 2) {
                // Safely access votes array with bounds checking
                let voteCount = idx < poll.votes.count ? poll.votes[idx] : 0
                let voteText = voteCount == 1 ? "vote" : "votes"
                Text("\(voteCount) \(voteText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if totalVotes > 0 {
                    let percentage = Int((Double(voteCount) / Double(totalVotes)) * 100)
                    Text("(\(percentage)%)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }

        var body: some View {
            Group {
                if isValidPoll {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(poll.question)
                            .font(.headline)
                            .foregroundColor(.purple)
                            .onAppear {
                                if let userVote = poll.userVote {
                                    print(
                                        "🗳️ PollSection: Displaying poll with user vote for option \(userVote)"
                                    )
                                } else {
                                    print("🗳️ PollSection: Displaying poll with no user vote")
                                }
                            }

                        // Total vote count display with enhanced statistics
                        totalVoteCountView

                        if let expiresAt = poll.expiresAt {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Expires: ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiresAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiresAt, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ForEach(Array(poll.options.enumerated()), id: \.offset) { offset, option in
                            let idx = offset
                            Button(action: {
                                // Only call onVote if user hasn't voted yet and not currently voting
                                // Also ensure the index is valid for the votes array
                                if poll.userVote == nil && votingOptionIndex == nil
                                    && idx < poll.votes.count
                                {
                                    onVote(idx)
                                    // Don't modify poll.userVote here - let the parent handle it
                                }
                            }) {
                                HStack {
                                    // Safely access options array with bounds checking
                                    Text(option)
                                        .fontWeight(poll.userVote == idx ? .bold : .regular)
                                    Spacer()
                                    if votingOptionIndex == idx {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else if poll.userVote != nil {
                                        voteStatsView(for: idx)
                                    }
                                    if poll.userVote == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(10)
                                .background(
                                    poll.userVote == idx
                                        ? Color.purple.opacity(0.13) : Color.purple.opacity(0.06)
                                )
                                .cornerRadius(10)
                            }
                            .disabled(poll.userVote != nil || votingOptionIndex != nil)
                        }
                        if poll.userVote != nil {
                            Text("Thank you for voting!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.vertical, 8)
                } else {
                    VStack {
                        Text("Poll data error")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Options: \(poll.options.count), Votes: \(poll.votes.count)")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Reminders Section (Collapsible)
    struct RemindersSection: View {
        let reminders: [HomeView.ReminderInfo]
        @State private var expanded: Bool = true
        var body: some View {
            if reminders.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { expanded.toggle() }) {
                        HStack {
                            Image(systemName: expanded ? "bell.badge.fill" : "bell")
                                .foregroundColor(.blue)
                            Text("Scheduled Reminders")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    if expanded {
                        ForEach(reminders) { reminder in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(reminder.body)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(reminder.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                    Text(reminder.date, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(10)
                            .background(Color.blue.opacity(0.07))
                            .cornerRadius(10)
                        }
                    }
                }
                .background(Color.blue.opacity(0.08))
                .cornerRadius(14)
                .padding(.vertical, 8)
            }
        }
    }

    // Load events from AppStorage
    private func loadEvents() {
        guard let data = eventsData.data(using: .utf8), !eventsData.isEmpty else { 
            events = []
            return 
        }
        if let decoded = try? JSONDecoder().decode([LocalEvent].self, from: data) {
            // Always update events to reflect latest data
            events = decoded
            #if DEBUG
                print("[HomeView] Loaded \(decoded.count) events from AppStorage")
            #endif
        }
    }

    // Save events to AppStorage
    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            eventsData = String(data: data, encoding: .utf8) ?? ""
        }
    }

    // MARK: - Community Messages Firestore Integration (optional)
    #if canImport(FirebaseFirestore)
        private var homeCommunityMessagesListener: ListenerRegistration?

        private func startHomeCommunityMessagesListener() {
            if homeCommunityMessagesListener != nil { return }
            FirebaseManager.shared.watchCommunityMessages { items in
                var incoming: [CommunityMessage] = []
                for item in items {
                    if let idStr = item["id"] as? String, let id = UUID(uuidString: idStr) {
                        let user = item["user"] as? String ?? "Anonymous"
                        let text = item["text"] as? String ?? ""
                        let ts = item["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                        let typeRaw = item["messageType"] as? String ?? "text"
                        let type = MessageType(rawValue: typeRaw) ?? .text
                        // parse optional remote URLs if present
                        var imageURL: URL? = nil
                        var fileURL: URL? = nil
                        var audioURL: URL? = nil
                        if let imageURLString = item["imageURL"] as? String {
                            imageURL = URL(string: imageURLString)
                        }
                        if let fileURLString = item["fileURL"] as? String {
                            fileURL = URL(string: fileURLString)
                        }
                        if let audioURLString = item["audioURL"] as? String {
                            audioURL = URL(string: audioURLString)
                        }

                        let msg = CommunityMessage(
                            id: id, user: user, text: text,
                            timestamp: Date(timeIntervalSince1970: ts), messageType: type,
                            isEdited: false, editedAt: nil, replyTo: nil, imageData: nil,
                            imageLocalURL: nil, imageURL: imageURL, fileURL: fileURL,
                            audioURL: audioURL, fileData: nil, fileName: nil, isRead: false)
                        incoming.append(msg)
                    }
                }
                let uiWork = DispatchWorkItem {
                    self.messages = incoming.sorted { $0.timestamp < $1.timestamp }
                    // Also save locally for offline fallback - sanitize to remove binary blobs
                    let sanitized = self.messages.map { msg -> CommunityMessage in
                        // Preserve metadata and remote URLs, and preserve local cached paths so attachments survive restarts
                        return CommunityMessage(
                            id: msg.id,
                            user: msg.user,
                            text: msg.text,
                            timestamp: msg.timestamp,
                            messageType: msg.messageType,
                            isEdited: msg.isEdited,
                            editedAt: msg.editedAt,
                            replyTo: msg.replyTo,
                            imageData: nil,
                            imageLocalURL: msg.imageLocalURL,
                            imageURL: msg.imageURL,
                            fileURL: msg.fileURL,
                            audioURL: msg.audioURL,
                            fileData: nil,
                            fileName: msg.fileName,
                            fileLocalURL: msg.fileLocalURL,
                            isRead: msg.isRead
                        )
                    }
                    if let data = try? JSONEncoder().encode(sanitized) {
                        self.communityMessagesData = String(data: data, encoding: .utf8) ?? ""
                    }
                }
                DispatchQueue.main.async(execute: uiWork)
            }
        }
    #endif

    // Load messages from AppStorage for unread counting
    private func loadMessages() {
        guard let data = communityMessagesData.data(using: .utf8), !communityMessagesData.isEmpty
        else {
            messages = []
            return
        }
        if let decoded = try? JSONDecoder().decode([CommunityMessage].self, from: data) {
            messages = decoded
        } else {
            messages = []
        }
    }

    // MARK: - Weather Details View (Expanded)
    struct WeatherDetailsView: View {
        @ObservedObject var weatherService: OpenWeatherMapService
        var body: some View {
            Group {
                if let weather = weatherService.currentWeather {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Humidity", systemImage: "humidity")
                                .foregroundColor(.blue)
                            Spacer()
                            Text(weather.humidityString)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Label("Wind", systemImage: "wind")
                                .foregroundColor(.blue)
                            Spacer()
                            Text(weather.windSpeedString)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Label("Visibility", systemImage: "eye")
                                .foregroundColor(.blue)
                            Spacer()
                            Text(weather.visibilityString)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Label("Cloud Cover", systemImage: "cloud.fill")
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(weather.cloudCover ?? 0)%")
                                .foregroundColor(.primary)
                        }
                        // Add more details as needed
                    }
                    .padding()
                } else if weatherService.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading details...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Text("Weather details unavailable.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
    }

    // MARK: - Home Event Card (compact event preview for HomeView)
    struct HomeEventCard: View {
        let event: LocalEvent
        @State private var showMapChoice: Bool = false
        @State private var pendingAddress: String? = nil
        @State private var showContactChoice: Bool = false
        @State private var pendingContact: String? = nil
        private var eventTypeColor: Color {
            switch event.eventType {
            case .event:
                return .blue
            case .report:
                // Softer red for report
                return Color(red: 1.0, green: 0.45, blue: 0.45)  // soft red
            case .request:
                return .red
            }
        }
        private var cardGradient: LinearGradient {
            LinearGradient(
                gradient: Gradient(colors: [
                    eventTypeColor.opacity(0.18),
                    Color(.systemBackground).opacity(0.92),
                    eventTypeColor.opacity(0.14),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardGradient)
                    .shadow(color: eventTypeColor.opacity(0.14), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.primary.opacity(0.07), radius: 2, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [eventTypeColor.opacity(0.22), .clear]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(eventTypeColor)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(eventTypeColor.opacity(0.13), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.eventType.rawValue)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(eventTypeColor)
                                .padding(.bottom, 1)
                            Text(event.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            // Reporter name (if available)
                            if let creator = event.creatorName, !creator.isEmpty {
                                Text(
                                    "Reporter: \(creator)\(event.creatorSurname != nil ? " \(event.creatorSurname!)" : "")"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            if let location = event.location, !location.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    Button(action: {
                                        pendingAddress = location
                                        showMapChoice = true
                                    }) {
                                        Text(location)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            // If request has fire metadata, display a compact row summarizing it
                            if event.eventType == .request, let meta = event.metadata, !meta.isEmpty
                            {
                                HStack(spacing: 8) {
                                    if let b = meta["buildingType"] {
                                        if b == "Other",
                                            let other = meta["buildingOtherDescription"],
                                            !other.isEmpty
                                        {
                                            Text(other)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .padding(6)
                                                .background(Color.gray.opacity(0.06))
                                                .cornerRadius(6)
                                        } else {
                                            Text(b)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .padding(6)
                                                .background(Color.gray.opacity(0.06))
                                                .cornerRadius(6)
                                        }
                                    }
                                    if let p = meta["peopleAtRisk"] {
                                        Text("People: \(p)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(6)
                                            .background(Color.gray.opacity(0.06))
                                            .cornerRadius(6)
                                    }
                                    if let v = meta["visibleFlamesOrSmoke"] {
                                        Text(
                                            v.lowercased() == "yes"
                                                ? "Flames/Smoke" : "No visible flames"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(6)
                                        .background(Color.gray.opacity(0.06))
                                        .cornerRadius(6)
                                    }
                                    Spacer()
                                    if let data = event.imageData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipped()
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.top, 6)
                            }
                            // Compact contact display for request cards (show manual contact if present)
                            if event.eventType == .request, let cName = event.contactName,
                                !cName.isEmpty || (event.contactCell ?? "").isEmpty == false
                            {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let cName = event.contactName, !cName.isEmpty {
                                        Text(cName)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if let cCell = event.contactCell, !cCell.isEmpty {
                                        Button(action: {
                                            pendingContact = cCell
                                            showContactChoice = true
                                        }) {
                                            Text(cCell)
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    Spacer()
                                }
                            }
                        }
                        Spacer()
                    }
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(eventTypeColor)
                        Text("Reported:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(event.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.primary)
                        Text(event.date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(14)
            }
            .padding(.horizontal, 2)
            .confirmationDialog("Open in…", isPresented: $showMapChoice, titleVisibility: .visible)
            {
                Button("Google Maps") {
                    if let addr = pendingAddress {
                        let encoded =
                            addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                            ?? ""
                        if let g = URL(string: "comgooglemaps://?q=\(encoded)"),
                            UIApplication.shared.canOpenURL(g)
                        {
                            UIApplication.shared.open(g)
                        } else if let web = URL(string: "https://maps.google.com/?q=\(encoded)") {
                            UIApplication.shared.open(web)
                        }
                    }
                }
                Button("Apple Maps") {
                    if let addr = pendingAddress {
                        let encoded =
                            addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                            ?? ""
                        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { pendingAddress = nil }
            }
            .confirmationDialog(
                "Contact via…", isPresented: $showContactChoice, titleVisibility: .visible
            ) {
                Button("Call") {
                    if let c = pendingContact {
                        let cleaned = c.filter { $0.isNumber }
                        if let tel = URL(string: "tel://\(cleaned)"),
                            UIApplication.shared.canOpenURL(tel)
                        {
                            UIApplication.shared.open(tel)
                        }
                    }
                }
                Button("WhatsApp — Detailed") {
                    if let c = pendingContact {
                        var digits = c.filter { $0.isNumber }
                        if digits.hasPrefix("0") && digits.count == 10 {
                            digits = "27" + digits.dropFirst()
                        }
                        let mgr = EmergencyRequestManager()
                        // Detailed polite template with date/time and location when available
                        let df = DateFormatter()
                        df.dateStyle = .medium
                        df.timeStyle = .short
                        let dateStr = df.string(from: event.date)
                        let locPart = (event.location ?? "").isEmpty ? "" : " at \(event.location!)"
                        let body =
                            "Hello — I saw your request titled \"\(event.title)\" reported on \(dateStr)\(locPart). I'm contacting to offer assistance. — NeighborHub"
                        mgr.openWhatsAppFallback(body: body, toPhone: digits)
                    }
                }
                Button("Cancel", role: .cancel) { pendingContact = nil }
            }
            .background(Color.clear)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: event)
        }
    }

    // MARK: - Fire WhatsApp Message Card
    struct FireWhatsAppCard: View {
        @ObservedObject var manager: EmergencyRequestManager
        let event: LocalEvent
        let waNumberOverride: String?
        let serverURL: URL?

        private var emergencyContact: EmergencyRequestManager.RecipientInfo? {
            if let n = event.contactName, !n.isEmpty || (event.contactCell ?? "").isEmpty == false {
                return EmergencyRequestManager.RecipientInfo(
                    name: event.contactName, phone: event.contactCell, relationship: nil)
            }
            return nil
        }

        private var messageBody: String {
            manager.buildMessageBody(
                type: .fire,
                name: (event.creatorName ?? "")
                    + (event.creatorSurname != nil ? " \(event.creatorSurname!)" : ""),
                address: event.location,
                cell: event.creatorName == nil ? nil : event.creatorName,  // keep reporter cell blank here; actual cell may be provided separately
                emergencyContact: emergencyContact,
                description: event.description,
                metadata: event.metadata,
                reportedDate: event.date,
                photoAttached: event.imageData != nil
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "message.fill")
                        .foregroundColor(.green)
                    Text("WhatsApp Message Preview")
                        .font(.headline)
                    Spacer()
                }

                ScrollView(.vertical) {
                    Text(messageBody)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .frame(minHeight: 120)

                HStack(spacing: 12) {
                    Button(action: {
                        // Open WhatsApp using manager convenience
                        manager.openWhatsAppFallback(body: messageBody, toPhone: waNumberOverride)
                    }) {
                        Label("Open in WhatsApp", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        UIPasteboard.general.string = messageBody
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: 100)
                    }
                    .buttonStyle(.bordered)
                }

                if let url = serverURL {
                    Button(action: {
                        // Use manager to attempt server send with fallback
                        manager.sendRequest(
                            type: .fire,
                            name: (event.creatorName ?? "")
                                + (event.creatorSurname != nil ? " \(event.creatorSurname!)" : ""),
                            address: event.location,
                            cell: nil,
                            emergencyContact: emergencyContact,
                            description: event.description,
                            metadata: event.metadata,
                            reportedDate: event.date,
                            photoAttached: event.imageData != nil,
                            serverURL: url,
                            serverAPIKey: nil,
                            waNumber: waNumberOverride
                        )
                    }) {
                        Label("Send via Server", systemImage: "server.rack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 6)
        }
    }

    // MARK: - StatMiniCardsRow (row of stat cards for HomeView)

    enum StatCardType { case events, reports, chats }

    struct StatMiniCardsRow: View {
        let eventsCount: Int
        let reportCount: Int
        let chatsCount: Int
        let unreadCount: Int  // Add unread count parameter
        var onCardTap: ((StatCardType) -> Void)? = nil
        var body: some View {
            HStack(spacing: 16) {
                StatMiniCard(
                    title: "Events",
                    value: eventsCount,
                    color: .blue,
                    systemImage: "calendar",
                    onTap: { onCardTap?(.events) }
                )

                StatMiniCard(
                    title: "Report Issue",
                    value: reportCount,
                    color: .orange,
                    systemImage: "exclamationmark.triangle.fill",
                    onTap: { onCardTap?(.reports) }
                )

                StatMiniCard(
                    title: "Messages",
                    value: chatsCount,
                    unreadCount: unreadCount,
                    color: .green,
                    systemImage: "message.fill",
                    onTap: { onCardTap?(.chats) }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - StatMiniCard (small stat card for HomeView)
    struct StatMiniCard: View {
        let title: String
        let value: Int
        var unreadCount: Int = 0  // Optional unread count for badges
        let color: Color
        let systemImage: String
        var onTap: (() -> Void)? = nil  // Add tap handler

        private var cardGradient: LinearGradient {
            LinearGradient(
                gradient: Gradient(colors: [
                    color.opacity(0.18),
                    Color(.systemBackground).opacity(0.92),
                    color.opacity(0.14),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        var body: some View {
            Button(action: {
                // Add haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                onTap?()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(cardGradient)
                        .shadow(color: color.opacity(0.14), radius: 8, x: 0, y: 4)
                        .shadow(color: Color.primary.opacity(0.07), radius: 2, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        gradient: Gradient(colors: [color.opacity(0.22), .clear]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                    VStack(spacing: 8) {
                        ZStack {
                            Image(systemName: systemImage)
                                .foregroundColor(color)
                                .frame(width: 36, height: 36)
                                .background(color.opacity(0.13), in: Circle())

                            // Unread badge
                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(10)
                                    .offset(x: 15, y: -15)
                            }
                        }

                        Text("\(value)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(color)
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 90, height: 90)
        }
    }

    // MARK: - Weather Header View (compact summary)
    struct WeatherHeaderView: View {
        @ObservedObject var weatherService: OpenWeatherMapService

        var body: some View {
            HStack(spacing: 8) {
                if let weather = weatherService.currentWeather {
                    // Weather icon based on description
                    Image(systemName: weatherIcon(for: weather.description))
                        .foregroundColor(.blue)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        if let temp = weather.temperature {
                            Text(String(format: "%.1f°C", temp))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .onAppear {
                                    print("🌤️ Displaying temperature: \(temp)°C")
                                }
                        } else {
                            Text("No temp")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .onAppear {
                                    print("🌤️ No temperature available in weather data")
                                }
                        }
                        if let desc = weather.description {
                            Text(desc.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if weatherService.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading details...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Text("Weather details unavailable.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }

        private func weatherIcon(for description: String?) -> String {
            guard let desc = description?.lowercased() else { return "cloud" }
            if desc.contains("clear") {
                return "sun.max.fill"
            } else if desc.contains("cloud") {
                return "cloud.fill"
            } else if desc.contains("rain") {
                return "cloud.rain.fill"
            } else if desc.contains("snow") {
                return "cloud.snow.fill"
            } else if desc.contains("storm") || desc.contains("thunder") {
                return "cloud.bolt.fill"
            } else {
                return "cloud"
            }
        }
    }

    // MARK: - Home Settings View
    struct HomeSettingsView: View {
        @Binding var homeSectionOrder: [HomeSection]
        @Binding var homeSectionVisibility: [HomeSection: Bool]
        @Binding var allowEveryoneToCreatePolls: Bool
        @Binding var allowEveryoneToCreateNewsletters: Bool
        @Binding var isPresented: Bool
        let onSave: () -> Void
        let onRestartOnboarding: () -> Void

        // User Profile Settings
        @AppStorage("userName") private var userName: String = ""
        @AppStorage("userSurname") private var userSurname: String = ""
        @AppStorage("userCell") private var userCell: String = ""
        @AppStorage("userStreet") private var userStreet: String = ""
        @AppStorage("userSuburb") private var userSuburb: String = ""
        @AppStorage("userCity") private var userCity: String = ""
        @AppStorage("userPostalCode") private var userPostalCode: String = ""

        // Emergency Contact Settings
        @AppStorage("emergencyContactName") private var emergencyContactName: String = ""
        @AppStorage("emergencyContactPhone") private var emergencyContactPhone: String = ""
        @AppStorage("emergencyContactRelationship") private var emergencyContactRelationship:
            String = ""

        // App Appearance Settings
        @AppStorage("appTheme") private var appTheme: String = "auto"

        // Help Button Settings
        @AppStorage("floatingHelpButtonPosition") private var floatingHelpButtonPosition: String =
            "right"

        // Watch Credentials
        @AppStorage("watchUsername") private var watchUsername: String = ""
        @AppStorage("watchPassword") private var watchPassword: String = ""

        // Chat Settings
        @AppStorage("chatNotificationsEnabled") private var chatNotificationsEnabled: Bool = true
        @AppStorage("chatSoundEnabled") private var chatSoundEnabled: Bool = true
        @AppStorage("chatShowTimestamps") private var chatShowTimestamps: Bool = true
        @AppStorage("chatFontSize") private var chatFontSize: Double = 16.0
        @AppStorage("chatTheme") private var chatTheme: String = "auto"
        @AppStorage("chatBackgroundStyle") private var chatBackgroundStyle: String = "default"
        @AppStorage("chatAutoScroll") private var chatAutoScroll: Bool = true
        @AppStorage("chatShowTypingIndicators") private var chatShowTypingIndicators: Bool = true

        // Community Settings
        @AppStorage("showEmergencyAlerts") private var showEmergencyAlerts: Bool = true
        @AppStorage("allowAnonymousPosting") private var allowAnonymousPosting: Bool = true
        @AppStorage("enablePostModeration") private var enablePostModeration: Bool = true
        @AppStorage("showNeighborhoodStats") private var showNeighborhoodStats: Bool = true
        @AppStorage("emergencyContactsEnabled") private var emergencyContactsEnabled: Bool = true
        @AppStorage("communityNotificationsEnabled") private var communityNotificationsEnabled:
            Bool = true
        @AppStorage("showIncidentAlerts") private var showIncidentAlerts: Bool = true
        @AppStorage("allowPublicPetitions") private var allowPublicPetitions: Bool = true

        // Marketplace Settings
        @AppStorage("notifyMarketplace") private var notifyMarketplace: Bool = true
        @AppStorage("userNeighborhood") private var userNeighborhood: String = "Your Neighborhood"
        @AppStorage("marketplaceSafetyTips") private var marketplaceSafetyTips: Bool = true
        @AppStorage("marketplaceAutoCleanup") private var marketplaceAutoCleanup: Bool = true
        @AppStorage("showWishlistNotifications") private var showWishlistNotifications: Bool = true
        @AppStorage("allowMarketplaceMessages") private var allowMarketplaceMessages: Bool = true
        @AppStorage("showMarketplaceDeals") private var showMarketplaceDeals: Bool = true
        @AppStorage("enablePriceAlerts") private var enablePriceAlerts: Bool = true

        // Server Configuration (Advanced)
        @AppStorage("helpServerURL") private var helpServerURL: String = ""
        @AppStorage("helpServerAPIKey") private var helpServerAPIKey: String = ""
        @AppStorage("helpRecipientPhone") private var helpRecipientPhone: String = ""

        // Committee Member Settings
        @AppStorage("committeeMembers") private var committeeMembers: String = ""
        
        // Cached admin/committee status from Firestore
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false

        @State private var selectedPosition = 1  // 0=left, 1=right, 2=center
        @State private var cameraAccessRequestSubmitted = false
        @State private var showCameraRequestAlert = false
        @State private var cameraRequestMessage = ""
        
        // Track previous watch username to detect changes
        @State private var previousWatchUsername = ""

        // Check if current user is a committee member
        private var isCommitteeMember: Bool {
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

        var body: some View {
            NavigationView {
                List {
                    // User Profile Section
                    Section("User Profile") {
                        HStack {
                            Text("First Name")
                            Spacer()
                            TextField("First Name", text: $userName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                        }

                        HStack {
                            Text("Surname")
                            Spacer()
                            TextField("Surname", text: $userSurname)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                        }

                        HStack {
                            Text("Cell Phone")
                            Spacer()
                            TextField("Cell Phone", text: $userCell)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                        }

                        NavigationLink(destination: WellnessSettingsView()) {
                            HStack {
                                Image(systemName: "heart.text.square")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text("Wellness Check-in Settings")
                                        .font(.body)
                                    Text("Manage your daily wellness check-in preferences.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        NavigationLink(destination: UserHouseholdManagementView()) {
                            HStack {
                                Image(systemName: "house.fill")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading) {
                                    Text("My Household")
                                        .font(.body)
                                    Text("Manage household members and subscription.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    // Address Section
                    Section("Address") {
                        TextField("Street Address", text: $userStreet)
                            .textFieldStyle(.roundedBorder)

                        TextField("Suburb", text: $userSuburb)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            TextField("City", text: $userCity)
                                .textFieldStyle(.roundedBorder)

                            TextField("Postal Code", text: $userPostalCode)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                        }
                    }

                    // Emergency Contact Section
                    Section("Emergency Contact") {
                        TextField("Name", text: $emergencyContactName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Phone", text: $emergencyContactPhone)
                            .textFieldStyle(.roundedBorder)

                        TextField("Relationship", text: $emergencyContactRelationship)
                            .textFieldStyle(.roundedBorder)
                    }

                    // App Appearance
                    Section("Appearance") {
                        Picker("Theme", selection: $appTheme) {
                            Text("Auto").tag("auto")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Help Button Settings
                    Section("Help Button") {
                        Picker("Button Position", selection: $selectedPosition) {
                            Text("Left").tag(0)
                            Text("Right").tag(1)
                            Text("Center").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedPosition) { _, newValue in
                            switch newValue {
                            case 0: floatingHelpButtonPosition = "left"
                            case 1: floatingHelpButtonPosition = "right"
                            case 2: floatingHelpButtonPosition = "center"
                            default: floatingHelpButtonPosition = "right"
                            }
                        }
                    }

                    // NeighbourHUB Watch Credentials
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Watch Username", text: $watchUsername)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .onChange(of: watchUsername) { _, newValue in
                                    // Trigger camera access request when credentials are entered
                                    if !newValue.trimmingCharacters(in: .whitespaces).isEmpty &&
                                       !watchPassword.trimmingCharacters(in: .whitespaces).isEmpty &&
                                       !cameraAccessRequestSubmitted {
                                        submitCameraAccessRequest()
                                    }
                                }

                            SecureField("Watch Password", text: $watchPassword)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: watchPassword) { _, newValue in
                                    // Trigger camera access request when credentials are entered
                                    if !newValue.trimmingCharacters(in: .whitespaces).isEmpty &&
                                       !watchUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
                                       !cameraAccessRequestSubmitted {
                                        submitCameraAccessRequest()
                                    }
                                }
                            
                            if cameraAccessRequestSubmitted {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Camera access requested")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        Text("Waiting for admin approval")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    } header: {
                        Text("NeighbourHUB Watch")
                    } footer: {
                        Text("Enter your watch credentials to request camera access. An admin will approve your request.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // App Permissions (Admin/Committee Only)
                    if isCommitteeMember {
                        Section("App Permissions") {
                            Toggle(
                                "Allow everyone to create polls", isOn: $allowEveryoneToCreatePolls
                            )
                            .toggleStyle(SwitchToggleStyle())

                            Toggle(
                                "Allow everyone to create newsletters",
                                isOn: $allowEveryoneToCreateNewsletters
                            )
                            .toggleStyle(SwitchToggleStyle())
                        }
                    }

                    // Home Sections Management
                    Section("Home Sections") {
                        // Section Order (with drag to reorder)
                        ForEach(homeSectionOrder, id: \.self) { section in
                            HStack {
                                // Visibility toggle
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { homeSectionVisibility[section, default: true] },
                                        set: { homeSectionVisibility[section] = $0 }
                                    )
                                )
                                .toggleStyle(SwitchToggleStyle())
                                .frame(width: 50)

                                // Section info
                                Image(systemName: sectionIcon(section))
                                    .foregroundColor(.blue)
                                    .frame(width: 20)

                                Text(sectionDisplayName(section))

                                Spacer()

                                // Drag handle
                                Image(systemName: "line.horizontal.3")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onMove(perform: moveSection)
                    }

                    // Advanced Settings - HIDDEN
                    // Section("Advanced Settings") {
                    //     TextField("Help Server URL", text: $helpServerURL)
                    //         .textFieldStyle(.roundedBorder)
                    //
                    //     TextField("Help Server API Key", text: $helpServerAPIKey)
                    //         .textFieldStyle(.roundedBorder)
                    //
                    //     TextField("Help Recipient Phone", text: $helpRecipientPhone)
                    //         .textFieldStyle(.roundedBorder)
                    // }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Set initial position selector value
                    switch floatingHelpButtonPosition {
                    case "left": selectedPosition = 0
                    case "right": selectedPosition = 1
                    case "center": selectedPosition = 2
                    default: selectedPosition = 1
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            onSave()
                            isPresented = false
                        }
                    }
                }
            }
        }

        private func moveSection(from source: IndexSet, to destination: Int) {
            homeSectionOrder.move(fromOffsets: source, toOffset: destination)
        }
        
        // MARK: - Camera Access Request
        
        private func submitCameraAccessRequest() {
            guard let uid = Auth.auth().currentUser?.uid else {
                print("⚠️ Cannot submit camera access request - user not authenticated")
                return
            }
            
            let trimmedUsername = watchUsername.trimmingCharacters(in: .whitespaces)
            guard !trimmedUsername.isEmpty else {
                print("⚠️ Cannot submit camera access request - watch username is empty")
                return
            }
            
            print("📹 Submitting camera access request for user \(uid) with watch username: \(trimmedUsername)")
            
            FirebaseManager.shared.requestCameraAccess(uid: uid, watchUsername: trimmedUsername) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.cameraAccessRequestSubmitted = true
                        self.cameraRequestMessage = "Camera access request submitted successfully!"
                        self.showCameraRequestAlert = true
                        print("✅ Camera access request submitted successfully")
                    case .failure(let error):
                        self.cameraRequestMessage = "Failed to submit request: \(error.localizedDescription)"
                        self.showCameraRequestAlert = true
                        print("❌ Failed to submit camera access request: \(error.localizedDescription)")
                    }
                }
            }
        }

        private func sectionDisplayName(_ section: HomeSection) -> String {
            switch section {
            case .weather: return "Weather"
            case .websiteLink: return "Estate Website"
            case .polls: return "Polls & Votes"
            case .requestHelp: return "Request Help"
            case .stats: return "Community Stats"
            case .reminders: return "Reminders"
            case .events: return "Events"
            case .newsletters: return "Newsletters"
            case .localListings: return "Local Listings"
            }
        }

        private func sectionIcon(_ section: HomeSection) -> String {
            switch section {
            case .weather: return "cloud.sun.fill"
            case .websiteLink: return "globe"
            case .polls: return "chart.bar.fill"
            case .requestHelp: return "person.2.wave.2.fill"
            case .stats: return "chart.pie.fill"
            case .reminders: return "bell.fill"
            case .events: return "calendar"
            case .newsletters: return "newspaper.fill"
            case .localListings: return "storefront.fill"
            }
        }
    }

    // MARK: - Missing View Structs
    struct RequestHelpSheet: View {
        // Include EmergencyContactsCard and supporting views locally to fix scope issues
        struct EmergencyContactsCard: View {
            @StateObject private var contactManager = CommunityEmergencyContactManager()
            @State private var showingContactsList = false
            
            var body: some View {
                Button(action: {
                    showingContactsList = true
                }) {
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "phone.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Emergency Contacts")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Admin/Committee badge
                        if contactManager.canEdit {
                            HStack(spacing: 4) {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Admin")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(contactManager.contacts.count) contacts available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Show critical contacts preview
                            if !contactManager.criticalContacts().isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(contactManager.criticalContacts().prefix(3), id: \.id) { contact in
                                        Text(contact.category.displayName)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showingContactsList) {
                    // For now, show a simple list - full implementation would go here
                    NavigationView {
                        List(contactManager.contacts, id: \.id) { contact in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.name)
                                        .font(.headline)
                                    Text(contact.phoneNumber)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    if let org = contact.organization {
                                        Text(org)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Contact actions menu
                                Menu {
                                    Button(action: {
                                        if let url = URL(string: "tel:\(contact.phoneNumber)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label("Call", systemImage: "phone.fill")
                                    }
                                    
                                    Button(action: {
                                        var phoneNumber = contact.phoneNumber.replacingOccurrences(of: " ", with: "")
                                        phoneNumber = phoneNumber.filter { $0.isNumber }
                                        
                                        // Convert local South African number to international format
                                        if phoneNumber.hasPrefix("0") && phoneNumber.count == 10 {
                                            phoneNumber = "27" + phoneNumber.dropFirst()
                                        }
                                        
                                        // Pre-fill WhatsApp message with inquiry about business
                                        let userName = UserDefaults.standard.string(forKey: "userName") ?? "User"
                                        var message = "Hi, I found your business *\\(contact.businessName)* on NeighborHub.%0A%0A"
                                        message += "I'm interested in learning more about your services.%0A%0A"
                                        message += "Best regards,%0A\\(userName)"
                                        
                                        if let url = URL(string: "https://wa.me/\\(phoneNumber)?text=\\(message)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label("WhatsApp Inquiry", systemImage: "message.circle.fill")
                                    }
                                    
                                    Divider()
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = contact.phoneNumber
                                    }) {
                                        Label("Copy Number", systemImage: "doc.on.doc")
                                    }
                                } label: {
                                    Image(systemName: "phone.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                        .navigationTitle("Emergency Contacts")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showingContactsList = false
                                }
                            }
                        }
                    }
                }
            }
        }
        
        @Binding var isPresented: Bool
        let locationDescription: String
        let weatherService: OpenWeatherMapService
        let onSendHelp: (HelpType, String, Data?, FireReportData?) -> Void

        @State private var selectedHelpType: HelpType? = nil
        @State private var helpMessage: String = ""
        @State private var isLoading: Bool = false
        @State private var showingFireDetails: Bool = false
        @State private var isChoiceSectionMinimized: Bool = false
        
        // Emergency settings - separate numbers for each type
        @Binding var fireNumber: String
        @Binding var emergencyNumber: String
        @Binding var medicalNumber: String
        @State private var showEditEmergencyNumber: Bool = false
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false

        // Fire-specific fields (simplified for quick access)
        @State private var fireDateTime: Date = Date()
        @State private var fireBuildingType: String = "House"

        @State private var fireUseDeviceLocation: Bool = true
        @State private var fireLocationInput: String = ""
        @State private var fireContactName: String = ""
        @State private var fireContactPhone: String = ""
        @State private var fireUseProfileContact: Bool = true
        @State private var firePhotoItem: PhotosPickerItem? = nil
        @State private var firePhotoData: Data? = nil
        @State private var showingCameraPicker: Bool = false

        // Shared location fields for all help types
        @State private var useDeviceLocation: Bool = true
        @State private var manualLocationInput: String = ""
        @State private var detailedCurrentLocation: String = "Fetching location..."
        @State private var isLoadingLocation: Bool = false
        
        // MARK: - Computed Views
        private var helpTypeSelectionHeader: some View {
            HStack {
                Text(
                    isChoiceSectionMinimized
                        ? "Help Type Selected" : "What help do you need?"
                )
                .font(isChoiceSectionMinimized ? .headline : .title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

                if isChoiceSectionMinimized {
                    Spacer()
                    Button("Change") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isChoiceSectionMinimized = false
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        
        private func helpTypeRow(for helpType: HelpType) -> some View {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(helpType.color)
                        .frame(width: 50, height: 50)

                    Image(systemName: helpType.iconName)
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(helpType.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(helpType.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if selectedHelpType == helpType {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(helpType.color)
                } else {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        selectedHelpType == helpType
                            ? helpType.color.opacity(0.1)
                            : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selectedHelpType == helpType
                            ? helpType.color : Color.clear, lineWidth: 2
                    )
            )
        }

        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Quick Help Type Selection (Top Priority)
                    VStack(spacing: 16) {
                        helpTypeSelectionHeader

                        if isChoiceSectionMinimized {
                            // Minimized view - show only selected type
                            if let selectedType = selectedHelpType {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(selectedType.color)
                                            .frame(width: 40, height: 40)

                                        Image(systemName: selectedType.iconName)
                                            .font(.title3)
                                            .foregroundColor(.white)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedType.rawValue)
                                            .font(.headline)
                                            .fontWeight(.semibold)

                                        Text(selectedType.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(selectedType.color)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedType.color.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedType.color, lineWidth: 1)
                                )
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // Full selection view
                            VStack(spacing: 12) {
                                ForEach(HelpType.allCases, id: \.self) { helpType in
                                    Button(action: {
                                        selectedHelpType = helpType
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()

                                        // Auto-minimize choice section after selection
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            isChoiceSectionMinimized = true
                                        }

                                        // Auto-expand fire details if fire is selected
                                        if helpType == .fire {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    showingFireDetails = true
                                                }
                                            }
                                        }
                                    }) {
                                        helpTypeRow(for: helpType)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Emergency Contacts Card - Always visible on main selection screen
                            VStack(alignment: .leading, spacing: 12) {
                                Text("📞 Emergency Contacts")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                
                                EmergencyContactsCardView()
                                    .padding(.horizontal, 20)
                            }
                            .padding(.top, 16)
                        }
                    }

                    if selectedHelpType != nil {
                        ScrollView {
                            VStack(spacing: 20) {
                                // Location Section
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("📍 Location")
                                        .font(.headline)
                                        .padding(.horizontal, 20)

                                    VStack(spacing: 12) {
                                        Toggle("Use my current location", isOn: $useDeviceLocation)
                                            .font(.subheadline)
                                            .padding(.horizontal, 20)

                                        if useDeviceLocation {
                                            // Show current location
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Current Location:")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 20)

                                                HStack {
                                                    if isLoadingLocation {
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                        Text("Getting precise location...")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    } else {
                                                        Text(detailedCurrentLocation)
                                                            .font(.subheadline)
                                                            .foregroundColor(.primary)
                                                    }
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(8)
                                                .padding(.horizontal, 20)
                                            }
                                        } else {
                                            // Manual location input
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Enter Location:")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 20)

                                                TextField(
                                                    "Street address, building, or landmark",
                                                    text: $manualLocationInput
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                .padding(.horizontal, 20)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 20)
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }

                                // Quick Message Input
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Brief Description (Optional)")
                                        .font(.headline)
                                        .padding(.horizontal, 20)

                                    TextField(
                                        "What's happening?", text: $helpMessage, axis: .vertical
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                                    .padding(.horizontal, 20)
                                }

                                // Fire-Specific Quick Options (Expandable)
                                if selectedHelpType == .fire {
                                    VStack(spacing: 16) {
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                showingFireDetails.toggle()
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "flame.fill")
                                                    .foregroundColor(.orange)
                                                Text("Fire Details")
                                                    .font(.headline)
                                                Spacer()
                                                Image(
                                                    systemName: showingFireDetails
                                                        ? "chevron.up" : "chevron.down"
                                                )
                                                .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .padding(.horizontal, 20)

                                        if showingFireDetails {
                                            VStack(spacing: 16) {

                                                // Building Type Quick Picker
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Building Type")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .padding(.horizontal, 20)

                                                    ScrollView(.horizontal, showsIndicators: false)
                                                    {
                                                        HStack(spacing: 12) {
                                                            ForEach(
                                                                [
                                                                    "House", "Office", "Veld",
                                                                ], id: \.self
                                                            ) { type in
                                                                Button(type) {
                                                                    fireBuildingType = type
                                                                }
                                                                .padding(.horizontal, 16)
                                                                .padding(.vertical, 8)
                                                                .background(
                                                                    RoundedRectangle(
                                                                        cornerRadius: 20
                                                                    )
                                                                    .fill(
                                                                        fireBuildingType == type
                                                                            ? Color.orange
                                                                            : Color(.systemGray6))
                                                                )
                                                                .foregroundColor(
                                                                    fireBuildingType == type
                                                                        ? .white : .primary
                                                                )
                                                                .font(.subheadline)
                                                            }
                                                        }
                                                        .padding(.horizontal, 20)
                                                    }
                                                }

                                                // Quick Photo Options
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Photo Evidence (Optional)")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .padding(.horizontal, 20)

                                                    if let photoData = firePhotoData,
                                                        let uiImage = UIImage(data: photoData)
                                                    {
                                                        VStack {
                                                            Image(uiImage: uiImage)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .frame(maxHeight: 120)
                                                                .cornerRadius(8)
                                                                .padding(.horizontal, 20)

                                                            Button("Remove Photo") {
                                                                firePhotoItem = nil
                                                                firePhotoData = nil
                                                            }
                                                            .font(.caption)
                                                            .foregroundColor(.red)
                                                        }
                                                    } else {
                                                        HStack(spacing: 12) {
                                                            Button(action: {
                                                                showingCameraPicker = true
                                                            }) {
                                                                HStack {
                                                                    Image(systemName: "camera.fill")
                                                                    Text("Camera")
                                                                }
                                                                .font(.subheadline)
                                                                .padding(.vertical, 10)
                                                                .padding(.horizontal, 16)
                                                                .background(Color.blue)
                                                                .foregroundColor(.white)
                                                                .cornerRadius(8)
                                                            }

                                                            PhotosPicker(
                                                                selection: $firePhotoItem,
                                                                matching: .images
                                                            ) {
                                                                HStack {
                                                                    Image(systemName: "photo.fill")
                                                                    Text("Gallery")
                                                                }
                                                                .font(.subheadline)
                                                                .padding(.vertical, 10)
                                                                .padding(.horizontal, 16)
                                                                .background(Color.blue)
                                                                .foregroundColor(.white)
                                                                .cornerRadius(8)
                                                            }

                                                            Spacer()
                                                        }
                                                        .padding(.horizontal, 20)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 12)
                                            .background(Color(.systemBackground))
                                            .cornerRadius(12)
                                            .padding(.horizontal, 20)
                                            .shadow(
                                                color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                        }
                                    }
                                }

                                // Emergency Services Quick Access
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("⚠️ For life-threatening emergencies")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                        
                                        if userIsAdmin || userIsCommittee {
                                            Button(action: { showEditEmergencyNumber = true }) {
                                                Image(systemName: "pencil.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.title3)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)

                                    HStack(spacing: 16) {
                                        // Show button for current selected type
                                        if let selectedType = selectedHelpType {
                                            let numberToCall: String = {
                                                switch selectedType {
                                                case .fire:
                                                    return fireNumber
                                                case .emergency:
                                                    return emergencyNumber
                                                case .medical:
                                                    return medicalNumber
                                                }
                                            }()
                                            
                                            Button(action: {
                                                // Track emergency call
                                                let contactType = switch selectedType {
                                                case .fire: "fire"
                                                case .emergency: "emergency"
                                                case .medical: "medical"
                                                }
                                                AnalyticsService.shared.trackEmergencyContact(
                                                    contactType: contactType,
                                                    action: "call"
                                                )
                                                
                                                if let url = URL(string: "tel://\(numberToCall)") {
                                                    UIApplication.shared.open(url)
                                                }
                                            }) {
                                                HStack {
                                                    Image(systemName: "phone.fill")
                                                    Text("Call \(numberToCall)")
                                                }
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 12)
                                                .background(selectedType.color)
                                                .cornerRadius(25)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .padding(.vertical, 16)
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)

                                Spacer(minLength: 100)
                            }
                        }
                    }

                    // Bottom Action Bar
                    if selectedHelpType != nil {
                        VStack(spacing: 12) {
                            Divider()

                            HStack(spacing: 16) {
                                Button("Cancel") {
                                    isPresented = false
                                }
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Color(.systemGray6))
                                .cornerRadius(25)

                                Button(action: sendHelpRequest) {
                                    HStack {
                                        if isLoading {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .foregroundColor(.white)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                        }
                                        Text("Send Request")
                                    }
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(selectedHelpType?.color ?? .gray)
                                    .cornerRadius(25)
                                }
                                .disabled(isLoading)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(Color(.systemBackground))
                    }
                }
                .navigationTitle("Request Help")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(true)
            }
            .sheet(isPresented: $showingCameraPicker) {
                CameraPickerView(onImageSelected: { imageData in
                    firePhotoData = imageData
                    showingCameraPicker = false
                })
            }
            .sheet(isPresented: $showEditEmergencyNumber) {
                EditEmergencyNumbersView(
                    fireNumber: $fireNumber,
                    emergencyNumber: $emergencyNumber,
                    medicalNumber: $medicalNumber,
                    onSave: { type, newNumber in
                        // Update the binding immediately for instant UI feedback
                        switch type {
                        case "fire":
                            fireNumber = newNumber
                        case "emergency":
                            emergencyNumber = newNumber
                        case "medical":
                            medicalNumber = newNumber
                        default:
                            break
                        }
                        // Also update Firestore for persistence and sync
                        FirebaseManager.shared.updateEmergencyNumber(newNumber, forType: type) { error in
                            if let error = error {
                                print("Error updating \(type) number: \(error)")
                            }
                        }
                    }
                )
            }
            .onAppear {
                Task {
                    await fetchDetailedLocation()
                }
                
                // Watch emergency settings
                print("🎬 RequestHelpSheet: Setting up emergency settings watcher")
                FirebaseManager.shared.watchEmergencySettings { settings in
                    print("📞 RequestHelpSheet: Received emergency settings update")
                    DispatchQueue.main.async {
                        self.fireNumber = settings.fireNumber
                        self.emergencyNumber = settings.emergencyNumber
                        self.medicalNumber = settings.medicalNumber
                    }
                }
            }
            .onChange(of: useDeviceLocation) { _, newValue in
                if newValue {
                    Task {
                        await fetchDetailedLocation()
                    }
                }
            }
            .onChange(of: firePhotoItem) { _, newItem in
                Task {
                    if let newItem = newItem {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                firePhotoData = data
                            }
                        }
                    }
                }
            }
        }

        private func fetchDetailedLocation() async {
            guard let location = weatherService.locationManager.currentLocation else {
                await MainActor.run {
                    detailedCurrentLocation = "Location not available"
                    isLoadingLocation = false
                }
                return
            }

            await MainActor.run {
                isLoadingLocation = true
            }

            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    var addressComponents: [String] = []

                    // Add street number and name
                    if let streetNumber = placemark.subThoroughfare,
                        let streetName = placemark.thoroughfare
                    {
                        addressComponents.append("\(streetNumber) \(streetName)")
                    } else if let streetName = placemark.thoroughfare {
                        addressComponents.append(streetName)
                    }

                    // Add suburb/locality
                    if let suburb = placemark.locality {
                        addressComponents.append(suburb)
                    }

                    // Add state/administrative area
                    if let state = placemark.administrativeArea {
                        addressComponents.append(state)
                    }

                    // Add postal code
                    if let postalCode = placemark.postalCode {
                        addressComponents.append(postalCode)
                    }

                    let detailedAddress = addressComponents.joined(separator: ", ")

                    await MainActor.run {
                        detailedCurrentLocation =
                            detailedAddress.isEmpty
                            ? String(
                                format: "Lat: %.5f, Lon: %.5f", location.coordinate.latitude,
                                location.coordinate.longitude) : detailedAddress
                        isLoadingLocation = false
                    }
                } else {
                    await MainActor.run {
                        detailedCurrentLocation = String(
                            format: "Lat: %.5f, Lon: %.5f", location.coordinate.latitude,
                            location.coordinate.longitude)
                        isLoadingLocation = false
                    }
                }
            } catch {
                await MainActor.run {
                    detailedCurrentLocation = String(
                        format: "Lat: %.5f, Lon: %.5f", location.coordinate.latitude,
                        location.coordinate.longitude)
                }
            }
        }

        private func sendHelpRequest() {
            guard let helpType = selectedHelpType else { return }

            isLoading = true

            // Call the parent's help request function
            let fireData = FireReportData(
                dateTime: fireDateTime,
                buildingType: selectedHelpType == .fire ? fireBuildingType : "",
                useDeviceLocation: useDeviceLocation,
                locationInput: manualLocationInput,
                detailedLocationDescription: useDeviceLocation
                    ? detailedCurrentLocation : manualLocationInput,
                useProfileContact: selectedHelpType == .fire ? fireUseProfileContact : true,
                contactName: selectedHelpType == .fire ? fireContactName : "",
                contactPhone: selectedHelpType == .fire ? fireContactPhone : ""
            )

            onSendHelp(helpType, helpMessage, firePhotoData, fireData)

            // Add delay for user feedback then close
            Task {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                } catch {
                    // If sleep is cancelled or fails, just continue
                }

                await MainActor.run {
                    isLoading = false
                    isPresented = false

                    // Show success feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }
    }

    // MARK: - Emergency Contacts Card
    struct EmergencyContactsCardView: View {
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
        @State private var showingContactsList = false
        @State private var userContactsCount = 0
        @State private var fireNumber: String = "911"
        @State private var emergencyNumber: String = "911"
        @State private var medicalNumber: String = "911"
        @State private var showEditEmergencyNumber: Bool = false
        
        private let defaultContacts: [(name: String, phone: String, category: String)] = [
            ("Emergency Services", "911", "Emergency"),
            ("Police Non-Emergency", "(555) 123-4567", "Police"),
            ("Hospital Emergency", "(555) 234-5678", "Medical"),
            ("Power Company", "(555) 345-6789", "Utility"),
            ("Water Department", "(555) 456-7890", "Utility")
        ]
        
        var canEdit: Bool {
            return userIsAdmin || userIsCommittee
        }
        
        var body: some View {
            Button(action: {
                showingContactsList = true
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "phone.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Emergency Contacts")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Admin/Committee badge
                            if canEdit {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(defaultContacts.count + userContactsCount) contacts available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Show critical contacts preview
                        HStack(spacing: 8) {
                            Text("Emergency")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                            
                            Text("Medical")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 2)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingContactsList) {
                EmergencyContactsListView()
            }
            .sheet(isPresented: $showEditEmergencyNumber) {
                EditEmergencyNumbersView(
                    fireNumber: $fireNumber,
                    emergencyNumber: $emergencyNumber,
                    medicalNumber: $medicalNumber,
                    onSave: { type, newNumber in
                        // Update the binding immediately for instant UI feedback
                        switch type {
                        case "fire":
                            fireNumber = newNumber
                        case "emergency":
                            emergencyNumber = newNumber
                        case "medical":
                            medicalNumber = newNumber
                        default:
                            break
                        }
                        // Also update Firestore for persistence and sync
                        FirebaseManager.shared.updateEmergencyNumber(newNumber, forType: type) { error in
                            if let error = error {
                                print("Error updating \(type) number: \(error)")
                            }
                        }
                    }
                )
            }
            .onAppear {
                updateUserContactsCount()
                
                // Watch emergency settings
                print("🎬 EmergencyContactsCardView: Setting up emergency settings watcher")
                FirebaseManager.shared.watchEmergencySettings { settings in
                    print("📞 EmergencyContactsCardView: Received emergency settings update")
                    DispatchQueue.main.async {
                        self.fireNumber = settings.fireNumber
                        self.emergencyNumber = settings.emergencyNumber
                        self.medicalNumber = settings.medicalNumber
                    }
                }
            }

        }
        
        private func updateUserContactsCount() {
            #if canImport(FirebaseFirestore)
            FirebaseManager.shared.watchEmergencyContacts { contacts in
                DispatchQueue.main.async {
                    self.userContactsCount = contacts.count
                }
            }
            #else
            userContactsCount = 0
            #endif
        }
    }
    
    // MARK: - Emergency Contact Row Component
    struct EmergencyContactRow: View {
        let contact: (name: String, phone: String, email: String, organization: String, category: String, priority: String, availability: String, notes: String)
        let isUserContact: Bool
        let index: Int
        let onDelete: () -> Void
        
        init(contact: (name: String, phone: String, category: String, priority: String), isUserContact: Bool = false, index: Int = 0, onDelete: @escaping () -> Void = {}) {
            // Convert default contact format to full format
            self.contact = (name: contact.name, phone: contact.phone, email: "", organization: "", category: contact.category, priority: contact.priority, availability: "", notes: "")
            self.isUserContact = isUserContact
            self.index = index
            self.onDelete = onDelete
        }
        
        init(contact: (name: String, phone: String, email: String, organization: String, category: String, priority: String, availability: String, notes: String), isUserContact: Bool, index: Int, onDelete: @escaping () -> Void) {
            self.contact = contact
            self.isUserContact = isUserContact
            self.index = index
            self.onDelete = onDelete
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(categoryColor(contact.category).opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon(contact.category))
                        .font(.system(size: 16))
                        .foregroundColor(categoryColor(contact.category))
                }
                
                // Contact info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(contact.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if isUserContact {
                            Text("Custom")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(contact.phone)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    if !contact.organization.isEmpty {
                        Text(contact.organization)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !contact.availability.isEmpty {
                        Text(contact.availability)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Contact actions menu
                Menu {
                    Button(action: {
                        callContact(contact.phone)
                    }) {
                        Label("Call", systemImage: "phone.fill")
                    }
                    
                    Button(action: {
                        openWhatsApp(contact.phone)
                    }) {
                        Label("WhatsApp", systemImage: "message.circle.fill")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        UIPasteboard.general.string = contact.phone
                    }) {
                        Label("Copy Number", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)
        }
        
        private func categoryColor(_ category: String) -> Color {
            switch category {
            case "Emergency": return .red
            case "Medical": return .blue
            case "Police": return .orange
            case "Utility": return .yellow
            case "Community": return .purple
            case "Government": return .gray
            default: return .gray
            }
        }
        
        private func categoryIcon(_ category: String) -> String {
            switch category {
            case "Emergency": return "exclamationmark.triangle.fill"
            case "Medical": return "cross.case.fill"
            case "Police": return "shield.fill"
            case "Utility": return "lightbulb.fill"
            case "Community": return "person.3.fill"
            case "Government": return "building.columns.fill"
            default: return "phone.fill"
            }
        }
        
        private func callContact(_ phoneNumber: String) {
            guard let url = URL(string: "tel:\(phoneNumber)") else { return }
            
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
        
        private func openWhatsApp(_ phoneNumber: String) {
            var waNumber = phoneNumber.filter { $0.isNumber }
            
            // Convert local South African number to international format
            if waNumber.hasPrefix("0") && waNumber.count == 10 {
                waNumber = "27" + waNumber.dropFirst()
            }
            
            // Pre-fill WhatsApp message with user details for emergency contact
            let userName = UserDefaults.standard.string(forKey: "userName") ?? "User"
            let userSurname = UserDefaults.standard.string(forKey: "userSurname") ?? ""
            let userAddress = UserDefaults.standard.string(forKey: "userStreet") ?? ""
            let userCell = UserDefaults.standard.string(forKey: "userCellNumber") ?? ""
            
            var message = "Hi, I need assistance.%0A%0A"
            message += "*Contact Details:*%0A"
            message += "Name: \\(userName) \\(userSurname)%0A"
            if !userAddress.isEmpty {
                message += "Address: \\(userAddress)%0A"
            }
            if !userCell.isEmpty {
                message += "Phone: \\(userCell)%0A"
            }
            message += "%0AThank you."
            
            if let url = URL(string: "https://wa.me/\\(waNumber)?text=\\(message)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - Emergency Contacts List View
    struct EmergencyContactsListView: View {
        @Environment(\.dismiss) private var dismiss
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
        @AppStorage("userName") private var userName: String = ""
        @AppStorage("userSurname") private var userSurname: String = ""
        @State private var showingAddContact = false
        @State private var showingActionSheet = false
        @State private var showingEditContact = false
        @State private var showingDeleteAlert = false
        @State private var selectedContactIndex: Int? = nil
        @State private var editingContact: EmergencyContactData? = nil
        @State private var userContacts: [EmergencyContactData] = []
        
        var canEdit: Bool {
            return userIsAdmin || userIsCommittee
        }
        
        var body: some View {
            NavigationView {
                List {
                    ForEach(Array(userContacts.enumerated()), id: \.element.id) { index, contact in
                        EmergencyContactRow(
                            contact: (name: contact.name, phone: contact.phone, email: contact.email, organization: contact.organization, category: contact.category, priority: contact.priority, availability: contact.availability, notes: contact.notes),
                            isUserContact: true,
                            index: index,
                            onDelete: { deleteUserContact(at: index) }
                        )
                        .onTapGesture {
                            selectedContactIndex = index
                            showingActionSheet = true
                        }
                    }
                }
                .navigationTitle("Emergency Contacts")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    
                    if canEdit {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
                                Text("Admin")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Button {
                                    showingAddContact = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddEmergencyContactSheet()
            }
            .confirmationDialog(
                selectedContactIndex != nil && selectedContactIndex! < userContacts.count ? userContacts[selectedContactIndex!].name : "Contact",
                isPresented: $showingActionSheet,
                titleVisibility: .visible
            ) {
                if let selectedIndex = selectedContactIndex, selectedIndex < userContacts.count {
                    let contact = userContacts[selectedIndex]
                    
                    Button("Call \(contact.phone)") {
                        callContact(contact.phone)
                    }
                    
                    Button("Copy Number") {
                        UIPasteboard.general.string = contact.phone
                    }
                    
                    if canEdit {
                        Divider()
                        
                        Button("✏️ Edit Contact") {
                            editingContact = contact
                            showingEditContact = true
                            selectedContactIndex = nil
                        }
                        
                        Button("🗑️ Delete Contact", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    }
                    
                    Button("Cancel", role: .cancel) {
                        selectedContactIndex = nil
                    }
                }
            }
            .onAppear {
                loadUserContacts()
            }
            .alert("Delete Contact", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let selectedIndex = selectedContactIndex {
                        deleteUserContact(at: selectedIndex)
                    }
                    selectedContactIndex = nil
                }
                Button("Cancel", role: .cancel) {
                    selectedContactIndex = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingEditContact) {
                if let editingContact = editingContact {
                    EditEmergencyContactSheet(
                        contact: editingContact,
                        onSave: updateUserContact
                    )
                } else {
                    Text("Error loading contact")
                        .onAppear {
                            showingEditContact = false
                        }
                }
            }
        }
        
        private func loadUserContacts() {
            #if canImport(FirebaseFirestore)
            print("🔄 Loading emergency contacts from Firebase...")
            FirebaseManager.shared.watchEmergencyContacts { contacts in
                DispatchQueue.main.async {
                    print("✅ Received \(contacts.count) emergency contacts from Firebase")
                    self.userContacts = contacts
                }
            }
            #else
            print("⚠️ FirebaseFirestore not available - contacts not loaded")
            #endif
        }
        
        private func addUserContact(name: String, phone: String, email: String, organization: String, category: String, priority: String, availability: String, notes: String) {
            let currentUserName = "\(userName) \(userSurname)".trimmingCharacters(in: .whitespacesAndNewlines)
            let newContact = EmergencyContactData(
                name: name,
                phone: phone,
                email: email,
                organization: organization,
                category: category,
                priority: priority,
                availability: availability,
                notes: notes,
                createdBy: currentUserName.isEmpty ? "Admin" : currentUserName
            )
            
            #if canImport(FirebaseFirestore)
            print("🔄 Creating emergency contact: \(newContact.name)")
            FirebaseManager.shared.createOrUpdateEmergencyContact(newContact) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let id):
                        print("✅ Emergency contact created with ID: \(id)")
                    case .failure(let error):
                        print("❌ Error creating emergency contact: \(error.localizedDescription)")
                    }
                }
            }
            #else
            print("⚠️ FirebaseFirestore not available - contact not saved")
            #endif
        }
        
        private func deleteUserContact(at index: Int) {
            guard index < userContacts.count else { return }
            let contact = userContacts[index]
            
            #if canImport(FirebaseFirestore)
            print("🗑️ Deleting emergency contact: \(contact.name) (ID: \(contact.id))")
            FirebaseManager.shared.deleteEmergencyContact(id: contact.id) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success():
                        print("✅ Emergency contact deleted successfully")
                    case .failure(let error):
                        print("❌ Error deleting emergency contact: \(error.localizedDescription)")
                    }
                }
            }
            #else
            print("⚠️ FirebaseFirestore not available - contact not deleted")
            #endif
        }
        
        private func updateUserContact(_ updatedContact: (name: String, phone: String, email: String, organization: String, category: String, priority: String, availability: String, notes: String)) {
            guard let editingContact = editingContact,
                  let existingContact = userContacts.first(where: { $0.name == editingContact.name && $0.phone == editingContact.phone }) else {
                return
            }
            
            let updated = EmergencyContactData(
                id: existingContact.id,
                name: updatedContact.name,
                phone: updatedContact.phone,
                email: updatedContact.email,
                organization: updatedContact.organization,
                category: updatedContact.category,
                priority: updatedContact.priority,
                availability: updatedContact.availability,
                notes: updatedContact.notes,
                createdBy: existingContact.createdBy,
                createdAt: existingContact.createdAt,
                updatedAt: Date()
            )
            
            #if canImport(FirebaseFirestore)
            print("🔄 Updating emergency contact: \(updated.name) (ID: \(updated.id))")
            FirebaseManager.shared.createOrUpdateEmergencyContact(updated) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let id):
                        print("✅ Emergency contact updated with ID: \(id)")
                    case .failure(let error):
                        print("❌ Error updating emergency contact: \(error.localizedDescription)")
                    }
                }
            }
            #else
            print("⚠️ FirebaseFirestore not available - contact not updated")
            #endif
        }
        
        private func categoryColor(_ category: String) -> Color {
            switch category {
            case "Emergency": return .red
            case "Medical": return .blue
            case "Police": return .orange
            case "Utility": return .yellow
            default: return .gray
            }
        }
        
        private func categoryIcon(_ category: String) -> String {
            switch category {
            case "Emergency": return "exclamationmark.triangle.fill"
            case "Medical": return "cross.case.fill"
            case "Police": return "shield.fill"
            case "Utility": return "lightbulb.fill"
            default: return "phone.fill"
            }
        }
        
        private func callContact(_ phoneNumber: String) {
            guard let url = URL(string: "tel:\(phoneNumber)") else { return }
            
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - Add Emergency Contact Sheet
    struct AddEmergencyContactSheet: View {
        @Environment(\.dismiss) private var dismiss
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
        @AppStorage("userName") private var userName: String = ""
        @AppStorage("userSurname") private var userSurname: String = ""
        
        @State private var contactName = ""
        @State private var phoneNumber = ""
        @State private var email = ""
        @State private var organization = ""
        @State private var selectedCategory = "Emergency"
        @State private var availability = ""
        @State private var notes = ""
        @State private var showingSuccessAlert = false
        
        private let categories = ["Emergency", "Medical", "Police", "Utility", "Community", "Government"]
        
        var canEdit: Bool {
            return userIsAdmin || userIsCommittee
        }
        
        var isValid: Bool {
            !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        var body: some View {
            NavigationView {
                Form {
                    Section("Contact Information") {
                        TextField("Name *", text: $contactName)
                        TextField("Phone Number *", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                    
                    Section("Classification") {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                HStack {
                                    Image(systemName: categoryIcon(category))
                                        .foregroundColor(categoryColor(category))
                                    Text(category)
                                }
                                .tag(category)
                            }
                        }
                    }
                    
                    if !canEdit {
                        Section {
                            Text("You need admin or committee privileges to add emergency contacts")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .navigationTitle("Add Emergency Contact")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveContact()
                        }
                        .disabled(!isValid || !canEdit)
                    }
                }
            }
            .alert("Contact Added", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Emergency contact has been added successfully.")
            }
        }
        
        private func saveContact() {
            let currentUserName = "\(userName) \(userSurname)".trimmingCharacters(in: .whitespacesAndNewlines)
            let newContact = EmergencyContactData(
                name: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                email: "",
                organization: "",
                category: selectedCategory,
                priority: "Normal",
                availability: "",
                notes: "",
                createdBy: currentUserName.isEmpty ? "Admin" : currentUserName
            )
            
            #if canImport(FirebaseFirestore)
            FirebaseManager.shared.createOrUpdateEmergencyContact(newContact) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let id):
                        print("✅ Emergency contact created with ID: \(id)")
                        showingSuccessAlert = true
                    case .failure(let error):
                        print("❌ Error creating emergency contact: \(error.localizedDescription)")
                    }
                }
            }
            #else
            showingSuccessAlert = true
            #endif
        }
        
        private func categoryColor(_ category: String) -> Color {
            switch category {
            case "Emergency": return .red
            case "Medical": return .blue
            case "Police": return .orange
            case "Utility": return .yellow
            case "Community": return .purple
            case "Government": return .gray
            default: return .gray
            }
        }
        
        private func categoryIcon(_ category: String) -> String {
            switch category {
            case "Emergency": return "exclamationmark.triangle.fill"
            case "Medical": return "cross.case.fill"
            case "Police": return "shield.fill"
            case "Utility": return "lightbulb.fill"
            case "Community": return "person.3.fill"
            case "Government": return "building.columns.fill"
            default: return "phone.fill"
            }
        }
    }
    
    // MARK: - Edit Emergency Contact Sheet
    struct EditEmergencyContactSheet: View {
        @Environment(\.dismiss) private var dismiss
        let contact: EmergencyContactData
        let onSave: ((name: String, phone: String, email: String, organization: String, category: String, priority: String, availability: String, notes: String)) -> Void
        
        @State private var contactName = ""
        @State private var phoneNumber = ""
        @State private var email = ""
        @State private var organization = ""
        @State private var selectedCategory = "Emergency"
        @State private var availability = ""
        @State private var notes = ""
        @State private var showingSuccessAlert = false
        
        private let categories = ["Emergency", "Medical", "Police", "Utility", "Community", "Government"]
        
        var isValid: Bool {
            !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        var body: some View {
            NavigationView {
                Form {
                    Section("Contact Information") {
                        TextField("Name *", text: $contactName)
                        TextField("Phone Number *", text: $phoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Email (Optional)", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        TextField("Organization (Optional)", text: $organization)
                    }
                    
                    Section("Classification") {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                HStack {
                                    Image(systemName: categoryIcon(category))
                                        .foregroundColor(categoryColor(category))
                                    Text(category)
                                }
                                .tag(category)
                            }
                        }
                    }
                    
                    Section("Additional Details") {
                        TextField("Availability (Optional)", text: $availability)
                            .placeholder(when: availability.isEmpty) {
                                Text("e.g., 24/7, Business Hours")
                                    .foregroundColor(.gray)
                            }
                        
                        TextField("Notes (Optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Edit Emergency Contact")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveChanges()
                        }
                        .disabled(!isValid)
                    }
                }
                .onAppear {
                    loadContactData()
                }
            }
            .alert("Contact Updated", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Emergency contact has been updated successfully.")
            }
        }
        
        private func loadContactData() {
            contactName = contact.name
            phoneNumber = contact.phone
            email = contact.email
            organization = contact.organization
            selectedCategory = contact.category
            availability = contact.availability
            notes = contact.notes
        }
        
        private func saveChanges() {
            let updatedContact = (
                name: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
                category: selectedCategory,
                priority: "Normal",
                availability: availability.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            onSave(updatedContact)
            showingSuccessAlert = true
        }
        
        private func categoryColor(_ category: String) -> Color {
            switch category {
            case "Emergency": return .red
            case "Medical": return .blue
            case "Police": return .orange
            case "Utility": return .yellow
            case "Community": return .purple
            case "Government": return .gray
            default: return .gray
            }
        }
        
        private func categoryIcon(_ category: String) -> String {
            switch category {
            case "Emergency": return "exclamationmark.triangle.fill"
            case "Medical": return "cross.case.fill"
            case "Police": return "shield.fill"
            case "Utility": return "lightbulb.fill"
            case "Community": return "person.3.fill"
            case "Government": return "building.columns.fill"
            default: return "phone.fill"
            }
        }
    }

    // MARK: - Edit Default Contact Sheet
    struct EditDefaultContactSheet: View {
        @Environment(\.dismiss) private var dismiss
        let contact: (name: String, phone: String, category: String, priority: String)
        let onSave: ((name: String, phone: String, category: String, priority: String)) -> Void
        
        @State private var contactName = ""
        @State private var phoneNumber = ""
        @State private var selectedCategory = "Emergency"
        @State private var showingSuccessAlert = false
        
        private let categories = ["Emergency", "Medical", "Police", "Utility", "Community", "Government"]
        
        var isValid: Bool {
            !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Contact Information")) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            TextField("Contact Name", text: $contactName)
                        }
                        
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.green)
                                .frame(width: 20)
                            TextField("Phone Number", text: $phoneNumber)
                                .keyboardType(.phonePad)
                        }
                    }
                    
                    Section(header: Text("Category")) {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .navigationTitle("Edit Default Contact")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveChanges()
                        }
                        .disabled(!isValid)
                    }
                }
                .onAppear {
                    loadContactData()
                }
            }
            .alert("Contact Updated", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Default emergency contact has been updated successfully.")
            }
        }
        
        private func loadContactData() {
            contactName = contact.name
            phoneNumber = contact.phone
            selectedCategory = contact.category
        }
        
        private func saveChanges() {
            let updatedContact = (
                name: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                category: selectedCategory,
                priority: "Normal"
            )
            
            onSave(updatedContact)
            showingSuccessAlert = true
        }
    }

    struct CameraPickerView: UIViewControllerRepresentable {
        let onImageSelected: (Data) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.allowsEditing = true
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate
        {
            let parent: CameraPickerView

            init(_ parent: CameraPickerView) {
                self.parent = parent
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let editedImage = info[.editedImage] as? UIImage,
                    let imageData = editedImage.jpegData(compressionQuality: 0.8)
                {
                    parent.onImageSelected(imageData)
                } else if let originalImage = info[.originalImage] as? UIImage,
                    let imageData = originalImage.jpegData(compressionQuality: 0.8)
                {
                    parent.onImageSelected(imageData)
                }
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                picker.dismiss(animated: true)
            }
        }
    }

    struct ScheduleReminderSheet: View {
        @Binding var isPresented: Bool
        @Binding var scheduledReminders: [HomeView.ReminderInfo]
        let saveReminders: () -> Void

        @State private var reminderTitle = ""
        @State private var reminderBody = ""
        @State private var reminderDate = Date()

        var body: some View {
            NavigationView {
                Form {
                    Section("Reminder Details") {
                        TextField("Title", text: $reminderTitle)
                        TextField("Description", text: $reminderBody)
                        DatePicker(
                            "Date", selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute])
                    }

                    Section {
                        Button("Add Reminder") {
                            let newReminder = HomeView.ReminderInfo(
                                id: UUID().uuidString,
                                title: reminderTitle,
                                body: reminderBody,
                                date: reminderDate
                            )
                            scheduledReminders.append(newReminder)
                            saveReminders()
                            isPresented = false
                        }
                        .disabled(reminderTitle.isEmpty)
                    }
                }
                .navigationTitle("Schedule Reminder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    struct PollCreationSheet: View {
        @Binding var isPresented: Bool
        let createPoll: (String, [String]) -> Void

        @State private var question = ""
        @State private var options = ["", ""]

        var body: some View {
            NavigationView {
                Form {
                    Section("Poll Question") {
                        TextField("Enter your question", text: $question)
                    }

                    Section("Options") {
                        ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                            let index = offset
                            TextField(
                                "Option \(index + 1)",
                                text: Binding(
                                    get: { index < options.count ? options[index] : "" },
                                    set: {
                                        if index < options.count {
                                            options[index] = $0
                                        }
                                    }
                                ))
                        }

                        Button("Add Option") {
                            options.append("")
                        }
                    }

                    Section {
                        Button("Create Poll") {
                            let validOptions = options.filter {
                                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                            createPoll(question, validOptions)
                        }
                        .disabled(
                            question.isEmpty
                                || options.filter {
                                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                }.count < 2)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .navigationTitle("Create Poll")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}

// Helper extension for placeholder text in TextFields
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// Add Notification.Name extension for quick actions
extension Notification.Name {
    static let homeQuickAction = Notification.Name("homeQuickAction")
}

// MARK: - Edit Emergency Numbers View
struct EditEmergencyNumbersView: View {
    @Binding var fireNumber: String
    @Binding var emergencyNumber: String
    @Binding var medicalNumber: String
    let onSave: (String, String) -> Void // type, number
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempFireNumber: String = ""
    @State private var tempEmergencyNumber: String = ""
    @State private var tempMedicalNumber: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .frame(width: 30)
                        TextField("Fire Emergency", text: $tempFireNumber)
                            .keyboardType(.phonePad)
                            .font(.title3)
                    }
                } header: {
                    Text("🔥 Fire Services")
                } footer: {
                    Text("Number for fire-related emergencies")
                }
                
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 30)
                        TextField("General Emergency", text: $tempEmergencyNumber)
                            .keyboardType(.phonePad)
                            .font(.title3)
                    }
                } header: {
                    Text("🚨 Emergency Services")
                } footer: {
                    Text("Number for general emergencies")
                }
                
                Section {
                    HStack {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.blue)
                            .frame(width: 30)
                        TextField("Medical Emergency", text: $tempMedicalNumber)
                            .keyboardType(.phonePad)
                            .font(.title3)
                    }
                } header: {
                    Text("🏥 Medical Services")
                } footer: {
                    Text("Number for medical emergencies")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.orange)
                            Text("Fire: Call \(tempFireNumber)")
                                .font(.subheadline)
                        }
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.red)
                            Text("Emergency: Call \(tempEmergencyNumber)")
                                .font(.subheadline)
                        }
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.blue)
                            Text("Medical: Call \(tempMedicalNumber)")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Edit Emergency Numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save All") {
                        print("💾 Saving all emergency numbers")
                        onSave("fire", tempFireNumber)
                        onSave("emergency", tempEmergencyNumber)
                        onSave("medical", tempMedicalNumber)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempFireNumber = fireNumber
                tempEmergencyNumber = emergencyNumber
                tempMedicalNumber = medicalNumber
            }
        }
    }
}

// MARK: - Legacy Edit Emergency Number View (kept for compatibility)
struct EditEmergencyNumberView: View {
    @Binding var emergencyNumber: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempNumber: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Emergency Number", text: $tempNumber)
                        .keyboardType(.phonePad)
                        .font(.title2)
                } header: {
                    Text("Emergency Number")
                } footer: {
                    Text("This number will be displayed to all users for life-threatening emergencies")
                }
                
                Section {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.red)
                        Text("Preview: Call \(tempNumber)")
                            .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                }
            }
            .navigationTitle("Edit Emergency Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        print("💾 EditEmergencyNumberView: Saving emergency number: \(tempNumber)")
                        onSave(tempNumber)
                        dismiss()
                    }
                    .disabled(tempNumber.isEmpty)
                }
            }
            .onAppear {
                tempNumber = emergencyNumber
            }
        }
    }
}
