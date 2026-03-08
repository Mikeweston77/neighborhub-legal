import CoreData
import CoreLocation
import Foundation
import SwiftUI
import UserNotifications

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif

/// Manager that handles all community-related features including posts, incidents, issues, and petitions
class CommunityManager: ObservableObject {
    @Published var posts: [CommunityPost] = []
    @Published var incidents: [IncidentReport] = []
    @Published var issues: [CommunityIssueReport] = []
    @Published var petitions: [CommunityPetition] = []
    @Published var emergencyAlerts: [EmergencyAlert] = []

    // App Storage for settings
    @AppStorage("showEmergencyAlerts") var showEmergencyAlerts: Bool = true
    @AppStorage("allowAnonymousPosting") var allowAnonymousPosting: Bool = true
    @AppStorage("enablePostModeration") var enablePostModeration: Bool = true
    @AppStorage("communityNotificationsEnabled") var communityNotificationsEnabled: Bool = true
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""

    private let firebaseManager = FirebaseManager.shared

    init() {
        loadSampleData()
        setupNotifications()
    }

    // MARK: - Community Posts
    func createPost(title: String, content: String, category: String, isAnonymous: Bool = false) {
        let post = CommunityPost(
            id: UUID(),
            author: isAnonymous ? "Anonymous" : "\(userName) \(userSurname)",
            authorInitials: isAnonymous ? "A" : "\(userName.prefix(1))\(userSurname.prefix(1))",
            timeAgo: "now",
            category: category,
            title: title,
            content: content,
            likes: 0,
            comments: 0,
            isLiked: false,
            hasImage: false
        )

        posts.insert(post, at: 0)
        saveCommunityData()

        if communityNotificationsEnabled {
            sendLocalNotification(
                title: "New Community Post", body: title, category: "community_post")
        }
    }

    func likePost(_ postId: UUID) {
        if let index = posts.firstIndex(where: { $0.id == postId }) {
            posts[index].toggleLike()
            saveCommunityData()
        }
    }

    // MARK: - Security Incidents
    func reportIncident(
        title: String, description: String, severity: String, location: String?,
        isAnonymous: Bool = false
    ) {
        let incident = IncidentReport(
            id: UUID(),
            title: title,
            description: description,
            severity: severity,
            location: location ?? "Unknown",
            reportedDate: Date(),
            status: "Open",
            reporter: isAnonymous ? "Anonymous" : "\(userName) \(userSurname)",
            isAnonymous: isAnonymous
        )

        incidents.insert(incident, at: 0)
        saveCommunityData()

        if communityNotificationsEnabled {
            sendLocalNotification(
                title: "New Security Incident", body: title, category: "security_incident")
        }

        // Send emergency alert for high/critical incidents
        if severity == "High" || severity == "Critical" {
            createEmergencyAlert(title: "Security Alert", message: title, severity: .critical)
        }
    }

    // MARK: - Community Issues
    func reportIssue(
        title: String, description: String, category: String, priority: String, location: String?
    ) {
        let issue = CommunityIssueReport(
            id: UUID(),
            title: title,
            description: description,
            category: category,
            priority: priority,
            location: location ?? "Unknown",
            reportedDate: Date(),
            status: "Open",
            votes: 0,
            reporter: "\(userName) \(userSurname)"
        )

        issues.insert(issue, at: 0)
        saveCommunityData()

        if communityNotificationsEnabled {
            sendLocalNotification(
                title: "New Community Issue", body: title, category: "community_issue")
        }
    }

    func voteOnIssue(_ issueId: UUID) {
        if let index = issues.firstIndex(where: { $0.id == issueId }) {
            issues[index].votes += 1
            saveCommunityData()
        }
    }

    // MARK: - Petitions
    func createPetition(
        title: String, description: String, category: String, targetSignatures: Int, deadline: Date?
    ) {
        let petition = CommunityPetition(
            id: UUID(),
            title: title,
            description: description,
            category: category,
            targetSignatures: targetSignatures,
            currentSignatures: 1,  // Creator automatically signs
            createdDate: Date(),
            deadline: deadline,
            creator: "\(userName) \(userSurname)",
            isActive: true
        )

        petitions.insert(petition, at: 0)
        saveCommunityData()

        if communityNotificationsEnabled {
            sendLocalNotification(
                title: "New Community Petition", body: title, category: "petition")
        }
    }

    func signPetition(_ petitionId: UUID) {
        if let index = petitions.firstIndex(where: { $0.id == petitionId }) {
            petitions[index].currentSignatures += 1
            saveCommunityData()
        }
    }

    // MARK: - Emergency Alerts
    func createEmergencyAlert(
        title: String, message: String, severity: EmergencyAlert.AlertSeverity
    ) {
        let alert = EmergencyAlert(
            id: UUID(),
            title: title,
            message: message,
            severity: severity,
            timestamp: Date(),
            isActive: true
        )

        emergencyAlerts.insert(alert, at: 0)

        if showEmergencyAlerts {
            sendLocalNotification(title: title, body: message, category: "emergency_alert")
        }
    }

    // MARK: - Data Persistence
    private func saveCommunityData() {
        // Save posts
        if let postsData = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(postsData, forKey: "communityPostsData")
        }

        // Save incidents
        if let incidentsData = try? JSONEncoder().encode(incidents) {
            UserDefaults.standard.set(incidentsData, forKey: "communityIncidentsData")
        }

        // Save issues
        if let issuesData = try? JSONEncoder().encode(issues) {
            UserDefaults.standard.set(issuesData, forKey: "communityIssuesData")
        }

        // Save petitions
        if let petitionsData = try? JSONEncoder().encode(petitions) {
            UserDefaults.standard.set(petitionsData, forKey: "communityPetitionsData")
        }
    }

    private func loadCommunityData() {
        // Load posts
        if let postsData = UserDefaults.standard.data(forKey: "communityPostsData"),
            let decodedPosts = try? JSONDecoder().decode([CommunityPost].self, from: postsData)
        {
            posts = decodedPosts
        }

        // Load incidents
        if let incidentsData = UserDefaults.standard.data(forKey: "communityIncidentsData"),
            let decodedIncidents = try? JSONDecoder().decode(
                [IncidentReport].self, from: incidentsData)
        {
            incidents = decodedIncidents
        }

        // Load issues
        if let issuesData = UserDefaults.standard.data(forKey: "communityIssuesData"),
            let decodedIssues = try? JSONDecoder().decode(
                [CommunityIssueReport].self, from: issuesData)
        {
            issues = decodedIssues
        }

        // Load petitions
        if let petitionsData = UserDefaults.standard.data(forKey: "communityPetitionsData"),
            let decodedPetitions = try? JSONDecoder().decode(
                [CommunityPetition].self, from: petitionsData)
        {
            petitions = decodedPetitions
        }
    }

    // MARK: - Sample Data
    private func loadSampleData() {
        loadCommunityData()

        // Only add sample data if no existing data
        if posts.isEmpty {
            addSamplePosts()
        }

        if incidents.isEmpty {
            addSampleIncidents()
        }

        if issues.isEmpty {
            addSampleIssues()
        }

        if petitions.isEmpty {
            addSamplePetitions()
        }
    }

    private func addSamplePosts() {
        let samplePosts = [
            CommunityPost(
                id: UUID(), author: "Sarah Johnson", authorInitials: "SJ", timeAgo: "2h",
                category: "General", title: "Welcome New Neighbors!",
                content:
                    "Just wanted to welcome the Smith family who moved in at 123 Oak Street. Looking forward to meeting you at the next community BBQ!",
                likes: 12, comments: 5, isLiked: false, hasImage: false),
            CommunityPost(
                id: UUID(), author: "Mike Davis", authorInitials: "MD", timeAgo: "5h",
                category: "Events", title: "Community Garden Update",
                content:
                    "The community garden is looking great! Thanks to everyone who helped with the planting day. The tomatoes are already sprouting!",
                likes: 8, comments: 3, isLiked: false, hasImage: true),
            CommunityPost(
                id: UUID(), author: "Lisa Chen", authorInitials: "LC", timeAgo: "1d",
                category: "Safety", title: "Neighborhood Watch Reminder",
                content:
                    "Don't forget about our monthly neighborhood watch meeting this Thursday at 7 PM in the community center.",
                likes: 15, comments: 7, isLiked: true, hasImage: false),
        ]
        posts = samplePosts
    }

    private func addSampleIncidents() {
        let sampleIncidents = [
            IncidentReport(
                id: UUID(), title: "Suspicious Vehicle",
                description:
                    "Black sedan parked on Elm Street for 3 hours, occupant appeared to be watching houses",
                severity: "Medium", location: "Elm Street",
                reportedDate: Date().addingTimeInterval(-7200), status: "Under Investigation",
                reporter: "John Smith", isAnonymous: false),
            IncidentReport(
                id: UUID(), title: "Attempted Break-in",
                description:
                    "Someone tried to force open the back gate at 456 Pine Street around 2 AM",
                severity: "High", location: "456 Pine Street",
                reportedDate: Date().addingTimeInterval(-86400), status: "Resolved",
                reporter: "Anonymous", isAnonymous: true),
        ]
        incidents = sampleIncidents
    }

    private func addSampleIssues() {
        let sampleIssues = [
            CommunityIssueReport(
                id: UUID(), title: "Broken Street Light",
                description: "Street light on corner of Main and Oak has been out for a week",
                category: "Infrastructure", priority: "Medium", location: "Main & Oak Street",
                reportedDate: Date().addingTimeInterval(-172800), status: "Reported to City",
                votes: 23, reporter: "Community"),
            CommunityIssueReport(
                id: UUID(), title: "Potholes on Maple Avenue",
                description: "Several large potholes developing that could damage vehicles",
                category: "Roads", priority: "High", location: "Maple Avenue",
                reportedDate: Date().addingTimeInterval(-259200), status: "In Progress", votes: 45,
                reporter: "Multiple Residents"),
        ]
        issues = sampleIssues
    }

    private func addSamplePetitions() {
        let samplePetitions = [
            CommunityPetition(
                id: UUID(), title: "Install Speed Bumps on School Street",
                description:
                    "Cars regularly exceed 35mph on School Street creating safety hazards for children walking to school",
                category: "Safety", targetSignatures: 50, currentSignatures: 32,
                createdDate: Date().addingTimeInterval(-432000),
                deadline: Date().addingTimeInterval(1_209_600), creator: "Parents Association",
                isActive: true)
        ]
        petitions = samplePetitions
    }

    // MARK: - Notifications
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            _, _ in
        }
    }

    private func sendLocalNotification(title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Data Models
struct CommunityPost: Identifiable, Codable {
    let id: UUID
    let author: String
    let authorInitials: String
    let timeAgo: String
    let category: String
    let title: String
    let content: String
    var likes: Int
    var comments: Int
    var isLiked: Bool
    let hasImage: Bool

    mutating func toggleLike() {
        isLiked.toggle()
        likes += isLiked ? 1 : -1
    }
}

struct IncidentReport: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let severity: String  // Low, Medium, High, Critical
    let location: String
    let reportedDate: Date
    var status: String  // Open, Under Investigation, Resolved
    let reporter: String
    let isAnonymous: Bool
}

struct CommunityIssueReport: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let category: String
    let priority: String  // Low, Medium, High, Critical
    let location: String
    let reportedDate: Date
    var status: String  // Open, Reported to City, In Progress, Resolved
    var votes: Int
    let reporter: String
}

struct CommunityPetition: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let category: String
    let targetSignatures: Int
    var currentSignatures: Int
    let createdDate: Date
    let deadline: Date?
    let creator: String
    var isActive: Bool
}

struct EmergencyAlert: Identifiable, Codable {
    let id: UUID
    let title: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    let isActive: Bool

    enum AlertSeverity: String, Codable, CaseIterable {
        case info = "Info"
        case warning = "Warning"
        case critical = "Critical"
        case emergency = "Emergency"

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .critical: return .red
            case .emergency: return .purple
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            case .emergency: return "siren.fill"
            }
        }
    }
}
