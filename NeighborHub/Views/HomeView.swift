import Combine
import CoreData
import CoreLocation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

#if canImport(WidgetKit)
    import WidgetKit
#endif

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
    import FirebaseAuth
#endif
#if canImport(FirebaseStorage)
    import FirebaseStorage
#endif
#if canImport(FirebaseFunctions)
    import FirebaseFunctions
#endif

extension Color {
    static var appBackground: Color {
        Color(.systemBackground)
    }
}

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

private struct ConciergeRecommendation {
    enum Action {
        case openWellnessCheckin
        case openChats
        case openEvents
        case openReminders
        case openPolls
        case openWeather
    }

    let badge: String
    let title: String
    let message: String
    let buttonTitle: String
    let iconName: String
    let tint: Color
    let action: Action
}

private struct AssistantContextSnapshot {
    let hasPendingWellnessCheckin: Bool
    let unreadMessagesCount: Int
    let activeReminderCount: Int
    let upcomingEventsCount: Int
    let precipitationChancePercent: Int
    let hasActivePollWithoutVote: Bool
    let weatherSummary: String
}

private struct NeighborhoodCopilotTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let iconName: String
    let tint: Color
    let action: ConciergeRecommendation.Action
}

private enum HomeAssistantContextService {
    static func makeSnapshot(
        hasPendingWellnessCheckin: Bool,
        unreadMessagesCount: Int,
        activeReminderCount: Int,
        upcomingEventsCount: Int,
        precipitationChancePercent: Int,
        hasActivePollWithoutVote: Bool,
        weatherSummary: String
    ) -> AssistantContextSnapshot {
        AssistantContextSnapshot(
            hasPendingWellnessCheckin: hasPendingWellnessCheckin,
            unreadMessagesCount: unreadMessagesCount,
            activeReminderCount: activeReminderCount,
            upcomingEventsCount: upcomingEventsCount,
            precipitationChancePercent: precipitationChancePercent,
            hasActivePollWithoutVote: hasActivePollWithoutVote,
            weatherSummary: weatherSummary
        )
    }
}

private enum HomeAssistantService {
    static func recommendation(for snapshot: AssistantContextSnapshot) -> ConciergeRecommendation {
        if snapshot.hasPendingWellnessCheckin {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "Complete today’s wellness check-in",
                message: "You still have a pending check-in. Reply now so your day starts with a cleared status.",
                buttonTitle: "Check In",
                iconName: "heart.text.square.fill",
                tint: .pink,
                action: .openWellnessCheckin
            )
        }

        if snapshot.unreadMessagesCount > 0 {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "Catch up on neighborhood messages",
                message: "You have \(snapshot.unreadMessagesCount) unread chat\(snapshot.unreadMessagesCount == 1 ? "" : "s"). Open chats to stay current without missing community context.",
                buttonTitle: "Open Chats",
                iconName: "message.badge.fill",
                tint: .blue,
                action: .openChats
            )
        }

        if snapshot.hasActivePollWithoutVote {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "There’s an open poll waiting for your vote",
                message: "A neighborhood decision is active and you have not voted yet. Add your input while the poll is still open.",
                buttonTitle: "Open Poll",
                iconName: "checklist.checked",
                tint: .indigo,
                action: .openPolls
            )
        }

        if snapshot.activeReminderCount > 0 {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "Review your active reminders",
                message: "You have \(snapshot.activeReminderCount) reminder\(snapshot.activeReminderCount == 1 ? "" : "s") still active. A quick check keeps your local schedule under control.",
                buttonTitle: "View Reminders",
                iconName: "bell.badge.fill",
                tint: .orange,
                action: .openReminders
            )
        }

        if snapshot.upcomingEventsCount > 0 {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "See what’s happening nearby",
                message: "There \(snapshot.upcomingEventsCount == 1 ? "is 1 upcoming event" : "are \(snapshot.upcomingEventsCount) upcoming events") in your neighborhood. Check the calendar before you miss one.",
                buttonTitle: "Open Events",
                iconName: "calendar.badge.clock",
                tint: .green,
                action: .openEvents
            )
        }

        if snapshot.precipitationChancePercent >= 50 {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "Keep an umbrella handy",
                message: snapshot.weatherSummary.isEmpty
                    ? "Rain looks possible later, so it may be worth keeping plans flexible."
                    : snapshot.weatherSummary,
                buttonTitle: "Check Weather",
                iconName: "cloud.rain.fill",
                tint: .teal,
                action: .openWeather
            )
        }

        let digestSignals = [
            snapshot.unreadMessagesCount > 0,
            snapshot.hasActivePollWithoutVote,
            snapshot.activeReminderCount > 0,
            snapshot.upcomingEventsCount > 0,
            snapshot.precipitationChancePercent >= 50,
        ].filter { $0 }.count

        if digestSignals >= 2 {
            return ConciergeRecommendation(
                badge: "AI Concierge",
                title: "Your Daily Digest is ready",
                message: dailyDigestSummary(for: snapshot),
                buttonTitle: "Open Daily Digest",
                iconName: "doc.text.magnifyingglass",
                tint: .indigo,
                action: .openWeather
            )
        }

        return ConciergeRecommendation(
            badge: "AI Concierge",
            title: "You’re caught up for now",
            message: "No urgent tasks are waiting. Check weather and neighborhood activity to plan the rest of your day.",
            buttonTitle: "View Forecast",
            iconName: "sparkles",
            tint: .purple,
            action: .openWeather
        )
    }

    static func briefItems(for snapshot: AssistantContextSnapshot) -> [String] {
        var items: [String] = []

        if snapshot.hasPendingWellnessCheckin {
            items.append("You still have a wellness check-in to finish")
        }

        if snapshot.unreadMessagesCount > 0 {
            items.append("\(snapshot.unreadMessagesCount) neighborhood chat\(snapshot.unreadMessagesCount == 1 ? "" : "s") waiting for you")
        }

        if snapshot.hasActivePollWithoutVote {
            items.append("There’s an open poll if you want to weigh in")
        }

        if snapshot.upcomingEventsCount > 0 {
            items.append("\(snapshot.upcomingEventsCount) upcoming event\(snapshot.upcomingEventsCount == 1 ? "" : "s") on the calendar")
        }

        if snapshot.activeReminderCount > 0 {
            items.append("\(snapshot.activeReminderCount) reminder\(snapshot.activeReminderCount == 1 ? "" : "s") still active")
        }

        if snapshot.precipitationChancePercent >= 50 {
            items.append("Rain looks possible later, so an umbrella might be worth keeping close")
        }

        if items.isEmpty {
            items.append("Nothing urgent is waiting on you right now")
        }

        return Array(items.prefix(3))
    }

    static func dailyDigestSummary(for snapshot: AssistantContextSnapshot) -> String {
        // Friendly greeting with user's first name (fallback to 'Neighbor')
        let rawName = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstName = rawName.split(separator: " ").first.map(String.init) ?? "Neighbor"

        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        case 17..<22: greeting = "Good evening"
        default: greeting = "Hello"
        }

        let weatherSummary = snapshot.weatherSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let weatherText: String
        if weatherSummary.isEmpty {
            let weatherPhrase = weatherPlanPhrase(
                precipitationChancePercent: snapshot.precipitationChancePercent,
                conditionDescription: nil
            )
            weatherText = "Weather today looks fairly calm, with about a \(snapshot.precipitationChancePercent)% chance of rain. \(weatherPhrase)"
        } else if weatherSummary.lowercased().contains("rain") || weatherSummary.lowercased().contains("shower") || weatherSummary.lowercased().contains("storm") {
            weatherText = "Weather today looks a bit wet: \(weatherSummary) \(weatherPlanPhrase(precipitationChancePercent: snapshot.precipitationChancePercent, conditionDescription: weatherSummary))"
        } else {
            weatherText = "Weather today looks pleasant: \(weatherSummary) \(weatherPlanPhrase(precipitationChancePercent: snapshot.precipitationChancePercent, conditionDescription: weatherSummary))"
        }

        var parts: [String] = []
        if snapshot.upcomingEventsCount > 0 {
            parts.append("\(snapshot.upcomingEventsCount) event\(snapshot.upcomingEventsCount == 1 ? "" : "s") coming up")
        }
        if snapshot.unreadMessagesCount > 0 {
            parts.append("\(snapshot.unreadMessagesCount) message\(snapshot.unreadMessagesCount == 1 ? "" : "s") waiting in chat")
        }
        if snapshot.hasActivePollWithoutVote {
            parts.append("an open poll if you want to weigh in")
        }
        if snapshot.activeReminderCount > 0 {
            parts.append("\(snapshot.activeReminderCount) reminder\(snapshot.activeReminderCount == 1 ? "" : "s") still active")
        }

        let activitySummary = parts.isEmpty
            ? "Things are pretty calm right now."
            : "On the neighborhood side, " + parts.joined(separator: ", ") + "."

        return "\(greeting), \(firstName) — quick update: \(weatherText) \(activitySummary) If you want, I can turn any part of this into a post, reminder, or message."
    }

    private static func weatherPlanPhrase(precipitationChancePercent: Int, conditionDescription: String?) -> String {
        let condition = conditionDescription?.lowercased() ?? ""

        if precipitationChancePercent >= 70 || condition.contains("rain") || condition.contains("shower") || condition.contains("storm") {
            return "Better to keep plans flexible today."
        }

        if precipitationChancePercent >= 40 {
            return "Good day for errands, but it’s smart to keep an umbrella nearby."
        }

        if condition.contains("clear") || condition.contains("sun") || condition.contains("bright") {
            return "Looks like a good day to get outside or tick off a few errands."
        }

        return "Seems like a decent day to get things done."
    }

    static func neighborhoodCopilotTasks(for snapshot: AssistantContextSnapshot) -> [NeighborhoodCopilotTask] {
        var tasks: [NeighborhoodCopilotTask] = []

        if snapshot.unreadMessagesCount > 0 {
            tasks.append(
                NeighborhoodCopilotTask(
                    id: "messages",
                    title: "Review neighborhood messages",
                    detail: "You have \(snapshot.unreadMessagesCount) unread chat\(snapshot.unreadMessagesCount == 1 ? "" : "s").",
                    iconName: "message.badge.fill",
                    tint: .blue,
                    action: .openChats
                )
            )
        }

        if snapshot.activeReminderCount > 0 {
            tasks.append(
                NeighborhoodCopilotTask(
                    id: "reminders",
                    title: "Clear active reminders",
                    detail: "\(snapshot.activeReminderCount) reminder\(snapshot.activeReminderCount == 1 ? "" : "s") still active.",
                    iconName: "bell.badge.fill",
                    tint: .orange,
                    action: .openReminders
                )
            )
        }

        if snapshot.upcomingEventsCount > 0 {
            tasks.append(
                NeighborhoodCopilotTask(
                    id: "events",
                    title: "Plan around upcoming events",
                    detail: "\(snapshot.upcomingEventsCount) event\(snapshot.upcomingEventsCount == 1 ? "" : "s") coming up in your area.",
                    iconName: "calendar.badge.clock",
                    tint: .green,
                    action: .openEvents
                )
            )
        }

        if tasks.isEmpty {
            tasks.append(
                NeighborhoodCopilotTask(
                    id: "weather",
                    title: "Start with weather planning",
                    detail: "No pending reminder, event, or message pressure right now.",
                    iconName: "cloud.sun.fill",
                    tint: .teal,
                    action: .openWeather
                )
            )
        }

        return Array(tasks.prefix(3))
    }

    static func descriptionSuggestion(title: String, category: String, eventType: String = "event") -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCategory = trimmedCategory.lowercased()
        let lowerTitle = trimmedTitle.lowercased()

        if eventType == "report" {
            switch lowerCategory {
            case "electricity":
                return "Please report the power outage or electrical issue to the relevant authorities. Include details such as affected areas, duration, and any safety concerns."
            case "water":
                return "Report water-related issues including outages, leaks, or quality concerns. Please provide location details and impact assessment for affected residents."
            case "infrastructure":
                return "Report issues with roads, pavements, drainage, or other infrastructure. Include location, photos if available, and impact on residents or safety."
            case "safety":
                return "Report security concerns or suspicious activities. Provide time, location, description of the incident, and any individuals involved. Safety is our priority."
            case "waste":
                return "Report waste management issues including missed collections, dumping, or improper disposal. Include location and nature of the problem."
            case "lighting":
                return "Report non-functioning street lights or lighting issues. Include specific location and how this impacts neighborhood safety."
            case "environment":
                return "Report environmental concerns such as pollution, illegal dumping, or damaged green spaces. Help protect our neighborhood's environment."
            case "community":
                return "Report community-related issues such as noise disturbances, anti-social behavior, or maintenance problems affecting shared spaces."
            default:
                return "Please provide details about the issue you're reporting. Include location, time of occurrence, and any relevant information that would help address this matter."
            }
        }

        if lowerTitle.contains("meeting") || lowerTitle.contains("gathering") || lowerTitle.contains("assembly") {
            return "Join us for this important neighborhood meeting. All residents are welcome to attend and participate in community discussions."
        } else if lowerTitle.contains("party") || lowerTitle.contains("celebration") || lowerTitle.contains("social") {
            return "Come celebrate with your neighbors! This is a great opportunity to connect with the community and build lasting friendships."
        } else if lowerTitle.contains("cleaning") || lowerTitle.contains("cleanup") || lowerTitle.contains("maintenance") {
            return "Help keep our neighborhood beautiful and well-maintained. Volunteers of all ages are welcome to participate in this community effort."
        } else if lowerTitle.contains("sports") || lowerTitle.contains("game") || lowerTitle.contains("match") || lowerTitle.contains("tournament") {
            return "Bring your competitive spirit and join fellow neighbors for a fun sporting event. Whether you're experienced or just looking for fun, you're welcome!"
        } else if lowerTitle.contains("market") || lowerTitle.contains("bazaar") || lowerTitle.contains("sale") {
            return "Visit our neighborhood market to discover local goods, crafts, and services. Support your neighbors while finding great deals."
        } else if lowerTitle.contains("workshop") || lowerTitle.contains("training") || lowerTitle.contains("class") {
            return "Learn new skills and share knowledge with your community. This workshop offers valuable insights for all participants."
        } else if lowerTitle.contains("walk") || lowerTitle.contains("hike") || lowerTitle.contains("nature") {
            return "Enjoy the outdoors with your neighbors on this scenic walk. Great exercise and an opportunity to appreciate our local environment."
        } else if lowerTitle.contains("kids") || lowerTitle.contains("children") || lowerTitle.contains("family") {
            return "A family-friendly event perfect for children and parents. Come enjoy quality time together in a safe, welcoming neighborhood setting."
        } else if lowerTitle.contains("dinner") || lowerTitle.contains("lunch") || lowerTitle.contains("meal") || lowerTitle.contains("food") {
            return "Join your neighbors for a delicious meal and great conversation. This is a wonderful way to build community bonds."
        } else if lowerTitle.contains("seminar") {
            return "An educational event designed to share expertise and help residents learn about important neighborhood topics."
        } else {
            return "We're excited to host this community event! Join your neighbors for a memorable experience. More details will be shared closer to the date."
        }
    }

}

struct HomeView: View {

    enum HelpType: String, CaseIterable, Codable {
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
    @State private var showEmergencyContactsSheet = false
    @State private var showScheduleSheet = false
    @State private var showPollCreationSheet = false
    @State private var showWellnessCheckinSheet = false
    @State private var wellnessHelpRequestDetails: WellnessHelpRequestDetails? = nil
    @State private var showNeighborhoodCopilotSheet = false
    @State private var showAIChatSheet = false
    @State private var helpRequestText = ""
    @State private var lastAssistantDigestSyncSignature: String = ""
    @State private var wellnessOptIn: Bool = true
    @AppStorage("assistantDigestPushOptIn") private var assistantDigestPushOptIn: Bool = false

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
    @AppStorage("pendingWellnessCheckinPrompt") private var pendingWellnessCheckinPrompt: Bool = false
    @AppStorage("pendingEmergencyContactsPrompt") private var pendingEmergencyContactsPrompt: Bool = false

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
    @StateObject private var weatherService = WeatherKitService()
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
    @State private var newsletters: [Newsletter] = []
    @State private var reportItIncidents: [FirebaseManager.Incident] = []
    @State private var archivedReportItIncidents: [FirebaseManager.Incident] = []
    @State private var patrolSchedules: [FirebaseManager.PatrolSchedule] = []
    @State private var patrolArchives: [FirebaseManager.PatrolArchiveReport] = []
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
                    creatorUid: Auth.auth().currentUser?.uid,
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
                initialHelpType: selectedHelpType,
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
        .sheet(isPresented: $showEmergencyContactsSheet) {
            NavigationStack {
                EmergencyContactsListView()
                    .navigationTitle("Emergency Contacts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showEmergencyContactsSheet = false }
                        }
                    }
            }
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
        .sheet(isPresented: $showWellnessCheckinSheet) {
            NavigationStack {
                ScrollView {
                    WellnessCheckPromptView(isModal: true)
                        .padding()
                }
                .navigationTitle("Wellness Check-in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showWellnessCheckinSheet = false }
                    }
                }
            }
        }
        .sheet(item: $wellnessHelpRequestDetails) { details in
            WellnessHelpRequestSheet(details: details)
        }
        .sheet(isPresented: $showNeighborhoodCopilotSheet) {
            NavigationStack {
                NeighborhoodCopilotSheet(
                    tasks: neighborhoodCopilotTasks,
                    onTaskAction: { action in
                        showNeighborhoodCopilotSheet = false
                        performConciergeAction(action)
                    }
                )
            }
        }
        .sheet(isPresented: $showAIChatSheet) {
            NavigationStack {
                AICommunityAssistantView(
                    contextMessages: messages,
                    contextEvents: events,
                    contextReminders: scheduledReminders,
                    contextPoll: activePoll,
                    contextNewsletters: newsletters,
                    contextIncidents: reportItIncidents,
                    contextArchivedIncidents: archivedReportItIncidents,
                    contextPatrolSchedules: patrolSchedules,
                    contextPatrolArchives: patrolArchives,
                    contextWeatherSummary: aiWeatherSummary
                )
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .homeQuickAction)) { notification in
            let typeString = (notification.object as? String) ?? ""
            if typeString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "contacts" {
                showEmergencyContactsSheet = true
                return
            }
            selectedHelpType = helpType(from: typeString)
            showRequestHelpSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWellnessCheckinPrompt)) { _ in
            if wellnessOptIn {
                showWellnessCheckinSheet = true
            }
            pendingWellnessCheckinPrompt = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWellnessHelpRequest)) { notification in
            if let details = WellnessHelpRequestDetails(from: notification.userInfo) {
                wellnessHelpRequestDetails = details
            }
        }
        .onReceive(weatherService.locationManager.$currentLocation) { _ in
            syncEmergencyWidgetSharedDefaults()
        }
        .onReceive(weatherService.$locationName) { _ in
            syncEmergencyWidgetSharedDefaults()
        }
        .onReceive(weatherService.$currentWeather) { _ in
            syncAssistantDigestContextIfNeeded()
            Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot) }
        }
        .onAppear {
            if pendingEmergencyContactsPrompt {
                showEmergencyContactsSheet = true
                pendingEmergencyContactsPrompt = false
            }

            if pendingWellnessCheckinPrompt && wellnessOptIn {
                showWellnessCheckinSheet = true
                pendingWellnessCheckinPrompt = false
            }

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

            syncAssistantDigestContextIfNeeded(force: true)
        }
    }

    private func helpType(from rawValue: String) -> HelpType? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "fire": return .fire
        case "medical": return .medical
        case "emergency", "help", "sos": return .emergency
        default: return nil
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        aiChatButton
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        settingsButton
                    }
                }
                .onAppear(perform: handleOnAppear)
                .onDisappear(perform: handleOnDisappear)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WellnessOptInChanged"))) { note in
                    if let info = note.userInfo, let opt = info["optIn"] as? Bool {
                        DispatchQueue.main.async { self.wellnessOptIn = opt }
                    }
                }
                .onChange(of: eventsData) { _, _ in
                    Task { @MainActor in
                        loadEvents()
                        await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot)
                        fetchScheduledReminders()
                        syncAssistantDigestContextIfNeeded()
                    }
                }
                .onChange(of: communityMessagesData) { _, _ in
                    Task { @MainActor in
                        loadMessages()
                        await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot)
                        syncAssistantDigestContextIfNeeded()
                    }
                }
                .onChange(of: activePollData) { _, _ in
                    Task { @MainActor in
                        loadActivePoll()
                        await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot)
                        syncAssistantDigestContextIfNeeded()
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
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                Text(initials)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
        }
        .accessibilityLabel("Settings")
    }

    private var aiChatButton: some View {
        Button(action: {
            AnalyticsService.shared.trackAIAssistantAction(
                action: "Open AI Chat",
                source: "home_toolbar",
                accepted: true
            )
            showAIChatSheet = true
        }) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                Image(systemName: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .accessibilityLabel("AI Assistant")
    }

    private func handleOnAppear() {
        // Note: ContentView now handles showing onboarding for unauthenticated users
        // This check is only for authenticated users who haven't completed their profile
        // (edge case where auth exists but profile incomplete)
        checkAndShowOnboarding()

        loadSettings()  // Load user settings from AppStorage
        loadEvents()  // Always reload events to get latest data
        loadMessages()
        startHomeNewslettersListener()
        startHomeIncidentListeners()
        startHomePatrolListeners()
        Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot) }
        startHomeCommunityMessagesListener()
        loadWellnessOptInSetting()
        fetchScheduledReminders()
        loadActivePoll()
        watchArchivedPolls()

        // Keep widget identity/profile data in App Group defaults so widget requests
        // include a stable userId even if the user never opens Settings.
        syncEmergencyWidgetSharedDefaults()

        // Request location and weather data
        setupWeatherService()

        syncAssistantDigestContextIfNeeded(force: true)
    }

    private func loadWellnessOptInSetting() {
        guard let userUID = UserDefaults.standard.string(forKey: "userUID")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userUID.isEmpty else {
            return
        }
        Firestore.firestore().collection("users").document(userUID).getDocument { snap, error in
            guard error == nil, let data = snap?.data() else { return }
            let optedIn = data["wellnessOptIn"] as? Bool ?? true
            DispatchQueue.main.async {
                self.wellnessOptIn = optedIn
            }
        }
    }

    private func syncEmergencyWidgetSharedDefaults() {
        let appGroupID = "group.com.ml5ar66rq7.neighborhubwf3"
        let sharedDefaults = UserDefaults(suiteName: appGroupID) ?? .standard
        let localDefaults = UserDefaults.standard

        let resolvedUID = String(localDefaults.string(forKey: "userUID") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let values: [String: String] = [
            "userUID": resolvedUID,
            "userName": userName.trimmingCharacters(in: .whitespacesAndNewlines),
            "userSurname": userSurname.trimmingCharacters(in: .whitespacesAndNewlines),
            "userCell": userCell.trimmingCharacters(in: .whitespacesAndNewlines),
            "userStreet": userStreet.trimmingCharacters(in: .whitespacesAndNewlines),
            "userSuburb": userSuburb.trimmingCharacters(in: .whitespacesAndNewlines),
            "userCity": userCity.trimmingCharacters(in: .whitespacesAndNewlines),
            "userPostalCode": userPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        for (key, value) in values {
            if value.isEmpty {
                sharedDefaults.removeObject(forKey: key)
            } else {
                sharedDefaults.set(value, forKey: key)
            }
        }

        // Persist latest weather/device location for widget emergency payloads.
        if let current = weatherService.locationManager.currentLocation {
            sharedDefaults.set(current.coordinate.latitude, forKey: "widgetCurrentLatitude")
            sharedDefaults.set(current.coordinate.longitude, forKey: "widgetCurrentLongitude")
            sharedDefaults.set(current.timestamp.timeIntervalSince1970, forKey: "widgetCurrentLocationTimestamp")

            let resolvedName = weatherService.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedName.isEmpty && resolvedName != "Your Location" {
                sharedDefaults.set(resolvedName, forKey: "widgetCurrentLocationName")
            }
        }
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

        // Map local HelpType to manager type and incidentType string
        let (mgrType, incidentTypeStr): (EmergencyRequestManager.EmergencyType, String) = {
            switch type {
            case .fire: return (.fire, "fire")
            case .emergency: return (.emergency, "emergency")
            case .medical: return (.medical, "medical")
            }
        }()

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
            let alertId = UUID().uuidString
            let alert = FirebaseManager.ActiveAlert(
                id: alertId,
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

            // Also create emergencyAlerts document to trigger notification
            let pushMessage = emergencyRequestManager.buildMessageBody(
                type: mgrType,
                name: name,
                address: locationDesc.isEmpty ? nil : locationDesc,
                cell: cell.isEmpty ? nil : cell,
                emergencyContact: contactInfo,
                description: message.isEmpty ? nil : message,
                metadata: fireMeta.isEmpty ? nil : fireMeta,
                reportedDate: eventDate,
                photoAttached: firePhotoData != nil
            )
            let emergencyAlert = EmergencyAlert(
                id: UUID(uuidString: alertId) ?? UUID(),
                title: event.title,
                message: pushMessage,
                severity: .emergency,
                timestamp: Date(),
                isActive: true,
                incidentType: mgrType.rawValue,
                createdBy: Auth.auth().currentUser?.uid ?? (UserDefaults.standard.string(forKey: "fallbackUserId") ?? UUID().uuidString)
            )
            FirebaseManager.shared.createEmergencyAlert(emergencyAlert) { err in
                #if DEBUG
                    if let err = err { print("Failed to create emergency alert: \(err)") }
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
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let validOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedQuestion.isEmpty, validOptions.count >= 2 else {
            return
        }

        let newPoll = Poll(
            id: UUID(),
            question: trimmedQuestion,
            options: validOptions,
            votes: Array(repeating: 0, count: validOptions.count),
            userVote: nil,
            expiresAt: nil
        )

        activePoll = newPoll
        saveActivePoll()

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
            if wellnessOptIn {
                WellnessCheckPromptView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(homeSectionOrder, id: \.self) { section in
                if homeSectionVisibility[section, default: true] {
                    sectionView(for: section)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aiConciergeRecommendation: ConciergeRecommendation {
        HomeAssistantService.recommendation(for: aiConciergeSnapshot)
    }

    private var aiConciergeSnapshot: AssistantContextSnapshot {
        HomeAssistantContextService.makeSnapshot(
            hasPendingWellnessCheckin: pendingWellnessCheckinPrompt,
            unreadMessagesCount: unreadMessagesCount,
            activeReminderCount: scheduledReminders.filter { reminder in
                reminder.date >= Date().addingTimeInterval(-2 * 60 * 60)
            }.count,
            upcomingEventsCount: events.filter { $0.eventType == .event && $0.date >= Date() }.count,
            precipitationChancePercent: Int(((weatherService.currentWeather?.precipitationChance ?? 0) * 100).rounded()),
            hasActivePollWithoutVote: activePoll?.userVote == nil && activePoll != nil,
            weatherSummary: aiWeatherSummary
        )
    }

    private var aiLocalContextSnapshot: HomeAIContextSnapshot {
        HomeAIContextSnapshot(
            messages: messages,
            events: events,
            reminders: scheduledReminders,
            activePoll: activePoll,
            newsletters: newsletters,
            incidents: reportItIncidents,
            archivedIncidents: archivedReportItIncidents,
            patrolSchedules: patrolSchedules,
            patrolArchives: patrolArchives,
            weatherSummary: aiWeatherSummary
        )
    }

    private var aiDailyDigestSummary: String {
        HomeAssistantService.dailyDigestSummary(for: aiConciergeSnapshot)
    }

    private var neighborhoodCopilotTasks: [NeighborhoodCopilotTask] {
        HomeAssistantService.neighborhoodCopilotTasks(for: aiConciergeSnapshot)
    }

    private var aiConciergeCard: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                Button(action: {
                    AnalyticsService.shared.trackAIAssistantAction(
                        action: "Open AI Chat",
                        source: "home_concierge",
                        accepted: true
                    )
                    showAIChatSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)

                        Text("AI Concierge")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.blue.opacity(0.18), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open AI concierge chat")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Chat with your AI assistant")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Tap AI Concierge to open chat instantly for community updates, planning, listings, and safety communication help.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                    assistantDigestPushOptIn.toggle()
                    syncAssistantDigestContextIfNeeded(force: true)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: assistantDigestPushOptIn ? "bell.fill" : "bell.slash")
                        Text(assistantDigestPushOptIn ? "Daily Digest Push: On" : "Daily Digest Push: Off")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.blue.opacity(0.08), radius: 8, x: 0, y: 3)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Concierge. Opens AI chat directly.")
    }

    private func performConciergeAction(_ recommendation: ConciergeRecommendation) {
        AnalyticsService.shared.trackAIAssistantAction(
            action: recommendation.buttonTitle,
            source: "home_concierge",
            accepted: true
        )

        performConciergeAction(recommendation.action)
    }

    private func performConciergeAction(_ action: ConciergeRecommendation.Action) {
        switch action {
        case .openWellnessCheckin:
            showWellnessCheckinSheet = true
            pendingWellnessCheckinPrompt = false
        case .openChats:
            selectedTab = 3
            lastChatReadTimestamp = Date().timeIntervalSince1970
        case .openEvents:
            selectedTab = 1
        case .openReminders:
            showScheduleSheet = true
        case .openPolls:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                pollsExpanded = true
            }
        case .openWeather:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                weatherExpanded = true
            }
        }
    }

    private func syncAssistantDigestContextIfNeeded(force: Bool = false) {
        Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: aiLocalContextSnapshot) }

        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
            guard let uid = Auth.auth().currentUser?.uid else { return }

            let snapshot = aiConciergeSnapshot
            let recommendation = aiConciergeRecommendation
            let briefItems = HomeAssistantService.briefItems(for: snapshot)
            let digestSummary = HomeAssistantService.dailyDigestSummary(for: snapshot)

            let signature = [
                recommendation.title,
                digestSummary,
                briefItems.joined(separator: "|"),
                String(snapshot.unreadMessagesCount),
                String(snapshot.activeReminderCount),
                String(snapshot.upcomingEventsCount),
                String(snapshot.precipitationChancePercent),
                snapshot.hasActivePollWithoutVote ? "1" : "0",
                snapshot.hasPendingWellnessCheckin ? "1" : "0",
                assistantDigestPushOptIn ? "1" : "0",
            ].joined(separator: "::")

            if !force && signature == lastAssistantDigestSyncSignature {
                return
            }

            lastAssistantDigestSyncSignature = signature

            let db = Firestore.firestore()
            let now = FieldValue.serverTimestamp()

            db.collection("users").document(uid).setData([
                "assistantDigestOptIn": assistantDigestPushOptIn,
                "assistantDigestTimezone": TimeZone.current.identifier,
                "assistantDigestUpdatedAt": now,
            ], merge: true)

            db.collection("users").document(uid)
                .collection("assistantDigest")
                .document("current")
                .setData([
                    "summary": digestSummary,
                    "watchItems": briefItems,
                    "recommendedTitle": recommendation.title,
                    "recommendedButton": recommendation.buttonTitle,
                    "recommendedIcon": recommendation.iconName,
                    "recommendedTint": recommendation.tint.description,
                    "unreadMessagesCount": snapshot.unreadMessagesCount,
                    "activeReminderCount": snapshot.activeReminderCount,
                    "upcomingEventsCount": snapshot.upcomingEventsCount,
                    "precipitationChancePercent": snapshot.precipitationChancePercent,
                    "hasActivePollWithoutVote": snapshot.hasActivePollWithoutVote,
                    "hasPendingWellnessCheckin": snapshot.hasPendingWellnessCheckin,
                    "weatherSummary": aiWeatherSummary,
                    "timezone": TimeZone.current.identifier,
                    "pushOptIn": assistantDigestPushOptIn,
                    "updatedAt": now,
                ], merge: true)
        #endif
    }

    private var aiWeatherSummary: String {
        guard let weather = weatherService.currentWeather else {
            return "Weather update is unavailable right now."
        }

        let description = weather.description?.capitalized ?? "Current conditions"
        let currentTemperature = weather.temperature.map { roundedCelsius($0) } ?? "N/A"
        let feelsLike = weather.apparentTemperature.map { roundedCelsius($0) } ?? "N/A"
        let rainChance = weather.precipitationChanceString
        let wind = weather.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "N/A"

        let todayForecast = weatherService.dailyForecast.first
        let tomorrowForecast = weatherService.dailyForecast.dropFirst().first

        var parts: [String] = [
            "Right now: \(description.lowercased()) at \(currentTemperature)",
            "Feels like \(feelsLike)",
            "Wind \(wind)",
            "Rain chance \(rainChance)"
        ]

        if let todayForecast {
            parts.append("Today: high \(roundedCelsius(todayForecast.highC)), low \(roundedCelsius(todayForecast.lowC)), \(todayForecast.conditionDescription.lowercased())")
        }

        if let tomorrowForecast {
            parts.append("Tomorrow: high \(roundedCelsius(tomorrowForecast.highC)), low \(roundedCelsius(tomorrowForecast.lowC)), \(tomorrowForecast.conditionDescription.lowercased())")
        }

        return parts.joined(separator: " • ")
    }

    private func roundedCelsius(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
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

private struct AIDailyBriefSheet: View {
    let recommendation: ConciergeRecommendation
    let briefItems: [String]
    let digestSummary: String
    let weatherSummary: String
    let onPrimaryAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Daily Brief")
                        .font(.title2.bold())
                    Text("A quick summary of what matters in NeighborHub right now, with one recommended next step.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Recommended next action", systemImage: recommendation.iconName)
                        .font(.headline)
                        .foregroundColor(recommendation.tint)
                    Text(recommendation.title)
                        .font(.title3.weight(.semibold))
                    Text(recommendation.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily Digest")
                        .font(.headline)
                    Text(digestSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Today’s Watchlist")
                        .font(.headline)

                    ForEach(briefItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(recommendation.tint)
                            Text(item)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Weather Context")
                        .font(.headline)
                    Text(weatherSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button(action: onPrimaryAction) {
                    Text(recommendation.buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(recommendation.tint)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationTitle("Daily Brief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

private struct NeighborhoodCopilotSheet: View {
    let tasks: [NeighborhoodCopilotTask]
    let onTaskAction: (ConciergeRecommendation.Action) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Neighborhood Copilot")
                    .font(.title2.bold())

                Text("Action-ready recommendations for reminders, events, and messages.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: task.iconName)
                                .foregroundColor(task.tint)
                            Text(task.title)
                                .font(.headline)
                            Spacer()
                        }

                        Text(task.detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button("Do This") {
                            onTaskAction(task.action)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(task.tint)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(20)
        }
        .navigationTitle("Copilot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

private enum HomeAIChatRole: String {
    case user
    case assistant
}

private struct HomeAIChatMessage: Identifiable {
    let id = UUID()
    let role: HomeAIChatRole
    let text: String
    let timestamp: Date
}

private enum HomeAIProviderConfig {
    static let providerName = "Local Assistant"
    static let modelName = "offline"
}

private struct HomeAIContextSnapshot {
    let messages: [CommunityMessage]
    let events: [LocalEvent]
    let reminders: [HomeView.ReminderInfo]
    let activePoll: HomeView.Poll?
    let newsletters: [Newsletter]
    let incidents: [FirebaseManager.Incident]
    let archivedIncidents: [FirebaseManager.Incident]
    let patrolSchedules: [FirebaseManager.PatrolSchedule]
    let patrolArchives: [FirebaseManager.PatrolArchiveReport]
    let weatherSummary: String
}

private struct HomeAIChatService {
    static let shared = HomeAIChatService()
    private let hostedFallbackFlagKey = "enableHostedAIFallback"
    private let aiProvider: any AIContentProviding = AIContentService.shared

    func refreshLocalContext(snapshot: HomeAIContextSnapshot) async {
        await HomeAILocalIndexBuilder.refresh(snapshot: snapshot)
    }

    func sendMessage(input: String, history: [HomeAIChatMessage], snapshot: HomeAIContextSnapshot) async -> String {
        await refreshLocalContext(snapshot: snapshot)

        let retriever = LocalRetriever.shared
        let recentContext = await retriever.retrieve(query: input, since: Calendar.current.date(byAdding: .day, value: -30, to: Date()), maxItems: 20)
        let historyContext = history.suffix(12).filter { $0.role == .user }.map { message in
            IndexSnippet(
                kind: "home_chat_history",
                timestamp: message.timestamp,
                priority: message.role == .user ? 3 : 2,
                text: "\(message.role.rawValue.capitalized): \(message.text)"
            )
        }

        let engine = RuleBasedSummarizer()
        let localResponse = await engine.answer(query: input, context: historyContext + recentContext).text
        let humanLocalResponse = makeLocalReplyFeelLessRobotic(localResponse, query: input)

        if shouldUseHostedFallback(for: input, localReply: humanLocalResponse), let hostedResponse = await hostedReply(input: input, history: history, snapshot: snapshot) {
            AnalyticsService.shared.trackAIFeatureOutcome(
                feature: "ai_chat",
                action: "send_message",
                outcome: "hosted",
                metadata: ["chars": input.count]
            )
            return hostedResponse
        }

        AnalyticsService.shared.trackAIFeatureOutcome(
            feature: "ai_chat",
            action: "send_message",
            outcome: "local",
            metadata: ["chars": input.count]
        )
        return humanLocalResponse
    }

    func generateDailyBrief(snapshot: HomeAIContextSnapshot) async -> String {
        await refreshLocalContext(snapshot: snapshot)
        let retriever = LocalRetriever.shared
        let context = await retriever.retrieve(query: nil, since: Calendar.current.date(byAdding: .day, value: -7, to: Date()), maxItems: 30)
        let engine = RuleBasedSummarizer()
        let response = await engine.generateDailyBrief(context: context)
        return response.text
    }

    private func shouldUseHostedFallback(for input: String, localReply: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: hostedFallbackFlagKey) else { return false }

        let lowered = input.lowercased()
        let rewriteKeywords = [
            "rewrite", "polish", "improve", "reword", "compose", "draft", "write this",
            "make this", "summarize", "summary", "shorten", "expand"
        ]

        if rewriteKeywords.contains(where: { lowered.contains($0) }) {
            return true
        }

        let genericLocalReply = localReply.count < 110 || localReply.contains("I couldn't find a local match") || localReply.contains("I couldn't find an exact match") || localReply.contains("I am ready to help")
        return genericLocalReply
    }

    private func makeLocalReplyFeelLessRobotic(_ reply: String, query: String) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallbackReply(for: query)
        }

        if trimmed.contains("I couldn't find a local match") || trimmed.contains("I couldn't find an exact match") {
            return trimmed + " If you want, I can narrow it down with a related message, event, or listing."
        }

        if trimmed.contains("I am ready to help") || trimmed.contains("I can help you") {
            return fallbackReply(for: query)
        }

        return trimmed
    }

    private func hostedReply(input: String, history: [HomeAIChatMessage], snapshot: HomeAIContextSnapshot) async -> String? {
        let historyPayload: [[String: Any]] = history.suffix(12).map { message in
            [
                "role": message.role.rawValue,
                "text": message.text,
                "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
            ]
        }

        return await aiProvider.generateHomeChatReply(
            message: input,
            history: historyPayload,
            contextLimits: [
                "listings": 20,
                "events": 20,
                "incidents": 20,
                "communityMessages": 20,
                "newsletters": 20
            ]
        )
    }

    private func fallbackReply(for input: String) -> String {
        let query = input.lowercased()

        if query.contains("event") {
            return "I can help you plan this event. Share the title, audience, and date, and I will draft a clear description and checklist."
        }

        if query.contains("newsletter") {
            return "I can help with a newsletter draft. Tell me the topic, audience, and tone, and I’ll shape it into something natural."
        }

        if query.contains("listing") || query.contains("advert") {
            return "I can write a strong local listing. Share what you are offering, price, and contact preference, and I will structure it for you."
        }

        if query.contains("weather") || query.contains("forecast") {
            return "I can summarize the current weather and what it means for today. Ask me for a quick read or a planning note."
        }

        if query.contains("incident") || query.contains("patrol") || query.contains("report it") {
            return "I can help summarize recent incidents or patrol activity and turn it into a clear neighborhood update."
        }

        if query.contains("safety") || query.contains("alert") {
            return "For safety updates, include what happened, where, who is affected, and what action residents should take. I can draft that now if you share details."
        }

        return "I’m ready to help with community updates, newsletters, events, weather, listings, safety notices, incidents, patrols, and reminders. Tell me what you want to write and I’ll draft it in a more natural way."
    }
}

private enum HomeAILocalIndexBuilder {
    static func refresh(snapshot: HomeAIContextSnapshot) async {
        let retriever = LocalRetriever.shared
        await retriever.clear()

        await retriever.addSnippet(
            IndexSnippet(
                kind: "home_summary",
                priority: 10,
                text: buildSummary(snapshot: snapshot)
            )
        )

        for message in snapshot.messages.prefix(20) {
            await retriever.addSnippet(
                IndexSnippet(
                    id: message.id.uuidString,
                    kind: "community_message",
                    timestamp: message.timestamp,
                    priority: message.isRead ? 2 : 5,
                    text: "\(message.user): \(message.text)"
                )
            )
        }

        for event in snapshot.events.prefix(20) {
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = event.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = event.isResolved ? "resolved" : "active"
            let text = [event.title, description, location].compactMap { $0 }.joined(separator: " | ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: event.id.uuidString,
                    kind: event.eventType.rawValue.lowercased(),
                    timestamp: event.date,
                    priority: event.isResolved ? 2 : 7,
                    text: "\(text) [\(status)]"
                )
            )
        }

        for newsletter in snapshot.newsletters.prefix(20) {
            let category = newsletter.category.rawValue
            let subcategory = newsletter.businessSubcategory?.rawValue ?? newsletter.advertSubcategory?.rawValue ?? ""
            let subtype = subcategory.isEmpty ? "" : " (\(subcategory))"
            let summary = [newsletter.title, newsletter.summary].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " | ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: newsletter.id.uuidString,
                    kind: "newsletter_\(category.lowercased())",
                    timestamp: newsletter.date,
                    priority: newsletter.isPinned ? 9 : 5,
                    text: "\(summary)\(subtype) by \(newsletter.author)"
                )
            )
        }

        for incident in snapshot.incidents.prefix(20) {
            let type = incident.incidentType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = incident.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = incident.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let pieces = [incident.title, type, location, description].compactMap { part -> String? in
                guard let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
                return trimmed
            }
            await retriever.addSnippet(
                IndexSnippet(
                    id: incident.id.uuidString,
                    kind: "report_it_incident",
                    timestamp: incident.date,
                    priority: incident.showOnHome ? 8 : 4,
                    text: pieces.joined(separator: " | ")
                )
            )
        }

        for incident in snapshot.archivedIncidents.prefix(20) {
            let type = incident.incidentType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = incident.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = [incident.title, type, location].compactMap { $0 }.joined(separator: " | ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: incident.id.uuidString,
                    kind: "archived_report_it_incident",
                    timestamp: incident.archivedAt ?? incident.date,
                    priority: 3,
                    text: summary
                )
            )
        }

        for schedule in snapshot.patrolSchedules.prefix(20) {
            let scheduleSummary = [schedule.title, schedule.route, schedule.meetingPoint, schedule.notes].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " | ")
            let volunteers = schedule.volunteerNames.isEmpty ? "No volunteers yet" : schedule.volunteerNames.joined(separator: ", ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: schedule.id.uuidString,
                    kind: "patrol_schedule",
                    timestamp: schedule.updatedAt ?? schedule.createdAt ?? schedule.startTime,
                    priority: schedule.isActive ? 9 : 5,
                    text: "\(scheduleSummary) [\(schedule.status.displayName)] Volunteers: \(volunteers)"
                )
            )
        }

        for archive in snapshot.patrolArchives.prefix(20) {
            let summary = [archive.displayTitle, archive.summary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " | ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: archive.id,
                    kind: "patrol_archive",
                    timestamp: archive.archivedAt ?? Date(),
                    priority: 4,
                    text: summary
                )
            )
        }

        let weatherSummary = snapshot.weatherSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !weatherSummary.isEmpty {
            await retriever.addSnippet(
                IndexSnippet(
                    kind: "weather_summary",
                    timestamp: Date(),
                    priority: 6,
                    text: weatherSummary
                )
            )
        }

        for reminder in snapshot.reminders.prefix(20) {
            let due = Self.relativeDateString(for: reminder.date)
            await retriever.addSnippet(
                IndexSnippet(
                    id: reminder.id,
                    kind: "reminder",
                    timestamp: reminder.date,
                    priority: reminder.date < Date() ? 8 : 4,
                    text: "\(reminder.title): \(reminder.body) — due \(due)"
                )
            )
        }

        if let poll = snapshot.activePoll {
            let optionPairs = zip(poll.options, poll.votes + Array(repeating: 0, count: max(0, poll.options.count - poll.votes.count)))
            let optionSummary = optionPairs.map { option, voteCount in "\(option) (\(voteCount) votes)" }.joined(separator: "; ")
            await retriever.addSnippet(
                IndexSnippet(
                    id: poll.id.uuidString,
                    kind: "active_poll",
                    timestamp: Date(),
                    priority: 9,
                    text: "\(poll.question) Options: \(optionSummary)"
                )
            )
        }

        if snapshot.messages.isEmpty, snapshot.events.isEmpty, snapshot.reminders.isEmpty, snapshot.activePoll == nil {
            await addExampleSnippets(into: retriever)
        }
    }

    private static func buildSummary(snapshot: HomeAIContextSnapshot) -> String {
        let counts = [
            "\(snapshot.messages.count) messages",
            "\(snapshot.events.count) events",
            "\(snapshot.reminders.count) reminders",
            "\(snapshot.newsletters.count) newsletters",
            "\(snapshot.incidents.count) incidents",
            "\(snapshot.patrolSchedules.count) patrol schedules",
            snapshot.activePoll == nil ? nil : "1 active poll",
        ].compactMap { $0 }

        if counts.isEmpty {
            return "No local home data is currently cached."
        }

        return "Home context includes: " + counts.joined(separator: ", ") + "."
    }

    private static func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func addExampleSnippets(into retriever: LocalRetriever) async {
        let examples: [IndexSnippet] = [
            IndexSnippet(kind: "example_message", priority: 1, text: "Example: a neighbor reported a lost package near the front gate."),
            IndexSnippet(kind: "example_event", priority: 1, text: "Example: community meeting scheduled for Thursday at 7 PM in the clubhouse."),
            IndexSnippet(kind: "example_reminder", priority: 1, text: "Example: pay HOA fee before the 15th and confirm gate access code."),
            IndexSnippet(kind: "example_poll", priority: 1, text: "Example: active poll asks whether the neighborhood should add more motion lights."),
        ]

        for snippet in examples {
            await retriever.addSnippet(snippet)
        }
    }
}

private struct AICommunityAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @AppStorage("userName") private var userName: String = ""
    let contextMessages: [CommunityMessage]
    let contextEvents: [LocalEvent]
    let contextReminders: [HomeView.ReminderInfo]
    let contextPoll: HomeView.Poll?
    let contextNewsletters: [Newsletter]
    let contextIncidents: [FirebaseManager.Incident]
    let contextArchivedIncidents: [FirebaseManager.Incident]
    let contextPatrolSchedules: [FirebaseManager.PatrolSchedule]
    let contextPatrolArchives: [FirebaseManager.PatrolArchiveReport]
    let contextWeatherSummary: String

    private var currentContext: HomeAIContextSnapshot {
        HomeAIContextSnapshot(
            messages: contextMessages,
            events: contextEvents,
            reminders: contextReminders,
            activePoll: contextPoll,
            newsletters: contextNewsletters,
            incidents: contextIncidents,
            archivedIncidents: contextArchivedIncidents,
            patrolSchedules: contextPatrolSchedules,
            patrolArchives: contextPatrolArchives,
            weatherSummary: contextWeatherSummary
        )
    }

    init(
        contextMessages: [CommunityMessage],
        contextEvents: [LocalEvent],
        contextReminders: [HomeView.ReminderInfo],
        contextPoll: HomeView.Poll?,
        contextNewsletters: [Newsletter],
        contextIncidents: [FirebaseManager.Incident],
        contextArchivedIncidents: [FirebaseManager.Incident],
        contextPatrolSchedules: [FirebaseManager.PatrolSchedule],
        contextPatrolArchives: [FirebaseManager.PatrolArchiveReport],
        contextWeatherSummary: String
    ) {
        self.contextMessages = contextMessages
        self.contextEvents = contextEvents
        self.contextReminders = contextReminders
        self.contextPoll = contextPoll
        self.contextNewsletters = contextNewsletters
        self.contextIncidents = contextIncidents
        self.contextArchivedIncidents = contextArchivedIncidents
        self.contextPatrolSchedules = contextPatrolSchedules
        self.contextPatrolArchives = contextPatrolArchives
        self.contextWeatherSummary = contextWeatherSummary
    }

    private var seededAssistantMessage: String {
        let firstName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if firstName.isEmpty {
            return "Hi, I'm your neighborhood assistant. Ask me about messages, newsletters, weather, incidents, patrols, or something you want to draft."
        }
        return "Hi \(firstName), I'm your neighborhood assistant. Ask me about messages, newsletters, weather, incidents, patrols, or something you want to draft."
    }

    @State private var messages: [HomeAIChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false

    @AppStorage("aiFeatureChatEnabled") private var aiFeatureChatEnabled: Bool = true
    @AppStorage("aiFeatureDailyBriefEnabled") private var aiFeatureDailyBriefEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            messageBubble(for: message)
                                .id(message.id)
                        }

                        if isSending {
                            HStack {
                                ProgressView()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composer
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: currentContext) }
            if messages.isEmpty {
                messages = [
                    HomeAIChatMessage(
                        role: .assistant,
                        text: seededAssistantMessage,
                        timestamp: Date()
                    )
                ]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundColor(.blue)
                Text("\(HomeAIProviderConfig.providerName) · \(HomeAIProviderConfig.modelName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Text("Ask for summaries, planning support, emergency guidance, or daily brief help. This assistant uses only local app data.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button("Clear chat") {
                    clearConversation()
                }
                .font(.caption.weight(.semibold))
                .disabled(isSending || messages.count <= 1)

                Button("Regenerate") {
                    regenerateLastReply()
                }
                .font(.caption.weight(.semibold))
                .disabled(!canRegenerate)

                if aiFeatureDailyBriefEnabled {
                    Button("Daily Brief") {
                        requestDailyBrief()
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isSending)
                }
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var composer: some View {
        VStack(spacing: 10) {
            Divider()
            if !aiFeatureChatEnabled {
                Text("AI chat is currently disabled for this rollout.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask the AI assistant...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .focused($isComposerFocused)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(canSendMessage ? .blue : .gray)
                }
                .disabled(!canSendMessage)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
    }

    private var canSendMessage: Bool {
        aiFeatureChatEnabled && !isSending && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canRegenerate: Bool {
        !isSending && messages.contains(where: { $0.role == .user })
    }

    private var messagesForModel: [HomeAIChatMessage] {
        messages.filter { message in
            !(message.role == .assistant && message.text == seededAssistantMessage)
        }
    }

    private func messageBubble(for message: HomeAIChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack {
            if isUser {
                Spacer(minLength: 32)
            }

            Text(message.text)
                .font(.body)
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contextMenu {
                    Button("Copy") {
                        UIPasteboard.general.string = message.text
                    }
                    if message.role == .assistant {
                        Button("Use as Prompt") {
                            inputText = message.text
                            isComposerFocused = true
                        }
                    }
                }

            if !isUser {
                Spacer(minLength: 32)
            }
        }
    }

    private func clearConversation() {
        guard !isSending else { return }
        AnalyticsService.shared.trackAIFeatureOutcome(
            feature: "ai_chat",
            action: "clear_conversation",
            outcome: "success"
        )
        messages = [
            HomeAIChatMessage(
                role: .assistant,
                text: seededAssistantMessage,
                timestamp: Date()
            )
        ]
        inputText = ""
    }

    private func regenerateLastReply() {
        guard !isSending,
              let lastUserIndex = messages.lastIndex(where: { $0.role == .user })
        else { return }

        AnalyticsService.shared.trackAIFeatureOutcome(
            feature: "ai_chat",
            action: "regenerate",
            outcome: "requested"
        )

        let prompt = messages[lastUserIndex].text
        let historyBeforePrompt = Array(messages.prefix(lastUserIndex)).filter { message in
            !(message.role == .assistant && message.text == seededAssistantMessage)
        }

        if let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }

        isSending = true
        Task {
            let reply = await HomeAIChatService.shared.sendMessage(input: prompt, history: historyBeforePrompt, snapshot: currentContext)
            await MainActor.run {
                messages.append(HomeAIChatMessage(role: .assistant, text: reply, timestamp: Date()))
                AnalyticsService.shared.trackAIFeatureOutcome(
                    feature: "ai_chat",
                    action: "regenerate",
                    outcome: "received"
                )
                isSending = false
            }
        }
    }

    private func requestDailyBrief() {
        guard !isSending else { return }

        isComposerFocused = false
        isSending = true

        AnalyticsService.shared.trackAIFeatureOutcome(
            feature: "ai_daily_brief",
            action: "generate",
            outcome: "requested"
        )

        Task {
            let reply = await HomeAIChatService.shared.generateDailyBrief(snapshot: currentContext)
            await MainActor.run {
                messages.append(
                    HomeAIChatMessage(
                        role: .assistant,
                        text: reply,
                        timestamp: Date()
                    )
                )
                AnalyticsService.shared.trackAIFeatureOutcome(
                    feature: "ai_daily_brief",
                    action: "generate",
                    outcome: "received"
                )
                isSending = false
            }
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard aiFeatureChatEnabled, !trimmed.isEmpty, !isSending else { return }

        isComposerFocused = false
        let historySnapshot = messagesForModel
        messages.append(HomeAIChatMessage(role: .user, text: trimmed, timestamp: Date()))
        inputText = ""
        isSending = true

        AnalyticsService.shared.trackAIFeatureOutcome(
            feature: "ai_chat",
            action: "send_message",
            outcome: "requested",
            metadata: ["chars": trimmed.count]
        )

        Task {
            let reply = await HomeAIChatService.shared.sendMessage(input: trimmed, history: historySnapshot, snapshot: currentContext)
            await MainActor.run {
                messages.append(HomeAIChatMessage(role: .assistant, text: reply, timestamp: Date()))
                AnalyticsService.shared.trackAIFeatureOutcome(
                    feature: "ai_chat",
                    action: "send_message",
                    outcome: "received"
                )
                isSending = false
            }
        }
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
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
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
        .frame(maxWidth: .infinity)
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

    #if canImport(FirebaseFirestore)
    private func startHomeNewslettersListener() {
        FirebaseManager.shared.watchNewsletters { items in
            DispatchQueue.main.async {
                self.newsletters = items
                Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: self.aiLocalContextSnapshot) }
            }
        }
    }

    private func startHomeIncidentListeners() {
        FirebaseManager.shared.watchIncidents { items in
            DispatchQueue.main.async {
                self.reportItIncidents = items.filter { $0.showOnHome }
                Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: self.aiLocalContextSnapshot) }
            }
        }

        FirebaseManager.shared.watchArchivedIncidents { items in
            DispatchQueue.main.async {
                self.archivedReportItIncidents = items
                Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: self.aiLocalContextSnapshot) }
            }
        }
    }

    private func startHomePatrolListeners() {
        FirebaseManager.shared.watchPatrolSchedules { items in
            DispatchQueue.main.async {
                self.patrolSchedules = items
                Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: self.aiLocalContextSnapshot) }
            }
        }

        FirebaseManager.shared.watchPatrolArchives { items in
            DispatchQueue.main.async {
                self.patrolArchives = items
                Task { await HomeAIChatService.shared.refreshLocalContext(snapshot: self.aiLocalContextSnapshot) }
            }
        }
    }
    #endif

    // MARK: - Weather Details View (Expanded)
    struct WeatherDetailsView: View {
        @ObservedObject var weatherService: WeatherKitService
        @State private var forecastExpanded: Bool = false

        private var weatherValueColor: Color { .white }
        private var weatherLabelColor: Color { Color.white.opacity(0.94) }

        private static let hourFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "ha"
            return f
        }()

        private static let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "E"
            return f
        }()

        var body: some View {
            ZStack {
                LiveWeatherUnderlayView(weather: weatherService.currentWeather)
                    .clipped()
                    .cornerRadius(12)

                // Contrast scrim keeps text readable across bright and dark weather scenes.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.38),
                                Color.black.opacity(0.22),
                                Color.black.opacity(0.40),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )

                Group {
                    if let weather = weatherService.currentWeather {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Precipitation", systemImage: "drop.fill")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text(weather.precipitationChanceString)
                                    .foregroundColor(weatherValueColor)
                            }
                            HStack {
                                Label("Humidity", systemImage: "humidity")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text(weather.humidityString)
                                    .foregroundColor(weatherValueColor)
                            }
                            HStack {
                                Label("Feels Like", systemImage: "thermometer.medium")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text(weather.apparentTemperatureString)
                                    .foregroundColor(weatherValueColor)
                            }
                            HStack {
                                Label("Wind", systemImage: "wind")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text(weather.windSpeedString + (weather.windDirection.map { "  \($0)" } ?? ""))
                                    .foregroundColor(weatherValueColor)
                            }
                            HStack {
                                Label("Visibility", systemImage: "eye")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text(weather.visibilityString)
                                    .foregroundColor(weatherValueColor)
                            }
                            HStack {
                                Label("Cloud Cover", systemImage: "cloud.fill")
                                    .foregroundColor(weatherLabelColor)
                                Spacer()
                                Text("\(weather.cloudCover ?? 0)%")
                                    .foregroundColor(weatherValueColor)
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.24))

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    forecastExpanded.toggle()
                                }
                            }) {
                                HStack {
                                    Label("Forecast", systemImage: "calendar.badge.clock")
                                        .foregroundColor(weatherLabelColor)
                                    Spacer()
                                    Image(systemName: forecastExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(weatherLabelColor)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .buttonStyle(PlainButtonStyle())

                            if forecastExpanded {
                                VStack(alignment: .leading, spacing: 8) {
                                    if weatherService.hourlyForecast.isEmpty && weatherService.dailyForecast.isEmpty {
                                        Text("Forecast unavailable right now.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.88))
                                    } else {
                                        if !weatherService.hourlyForecast.isEmpty {
                                            Text("Next Hours")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white.opacity(0.92))
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 12) {
                                                    ForEach(Array(weatherService.hourlyForecast.prefix(12))) { hour in
                                                        VStack(spacing: 5) {
                                                            Text(Self.hourFormatter.string(from: hour.date))
                                                                .font(.caption2)
                                                                .foregroundColor(.white.opacity(0.88))
                                                            Image(systemName: forecastIcon(for: hour.conditionDescription, isDaylight: hour.isDaylight))
                                                                .font(.caption)
                                                                .foregroundStyle(.white.opacity(0.96))
                                                            Text("\(Int(round(hour.temperatureC)))°")
                                                                .font(.caption)
                                                                .fontWeight(.semibold)
                                                                .foregroundColor(.white)
                                                        }
                                                        .frame(width: 52)
                                                        .padding(.vertical, 2)
                                                    }
                                                }
                                            }
                                        }

                                        if !weatherService.dailyForecast.isEmpty {
                                            Text("Next Days")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white.opacity(0.92))
                                                .padding(.top, 2)
                                            VStack(spacing: 8) {
                                                ForEach(Array(weatherService.dailyForecast.prefix(7))) { day in
                                                    HStack {
                                                        Text(Self.dayFormatter.string(from: day.date))
                                                            .font(.footnote)
                                                            .frame(width: 34, alignment: .leading)
                                                            .foregroundColor(.white.opacity(0.9))
                                                        Image(systemName: forecastIcon(for: day.conditionDescription, isDaylight: true))
                                                            .font(.footnote)
                                                            .frame(width: 16)
                                                            .foregroundStyle(.white.opacity(0.96))
                                                        Spacer()
                                                        Text("\(Int(round(day.lowC)))° / \(Int(round(day.highC)))°")
                                                            .font(.footnote)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.white)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .fontWeight(.semibold)
                        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                        .padding()
                    } else if weatherService.isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading details...")
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding()
                    } else {
                        Text("Weather details unavailable.")
                            .foregroundColor(.white.opacity(0.9))
                            .padding()
                    }
                }
            }
        }

        private func forecastIcon(for description: String, isDaylight: Bool) -> String {
            let desc = description.lowercased()
            if desc.contains("thunder") || desc.contains("storm") { return "cloud.bolt.rain.fill" }
            if desc.contains("snow") || desc.contains("blizzard") || desc.contains("sleet") { return "cloud.snow.fill" }
            if desc.contains("rain") || desc.contains("drizzle") { return "cloud.rain.fill" }
            if desc.contains("fog") || desc.contains("haze") || desc.contains("smok") { return "cloud.fog.fill" }
            if desc.contains("clear") { return isDaylight ? "sun.max.fill" : "moon.stars.fill" }
            if desc.contains("partly") || desc.contains("mostly") { return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill" }
            return "cloud.fill"
        }
    }

    // MARK: - Apple-Style Weather Background
    struct LiveWeatherUnderlayView: View {
        let weather: WeatherData?
        private var desc: String { weather?.description?.lowercased() ?? "" }
        private var isDaylight: Bool { weather?.isDaylight ?? true }

        private var isStorm:  Bool { desc.contains("thunder") || desc.contains("storm") || desc.contains("tropical") || desc.contains("hurricane") }
        private var isSnow:   Bool { !isStorm && (desc.contains("snow") || desc.contains("sleet") || desc.contains("blizzard") || desc.contains("hail") || desc.contains("flurr")) }
        private var isRain:   Bool { !isStorm && (desc.contains("rain") || desc.contains("drizzle")) }
        private var isFog:    Bool { desc.contains("fog") || desc.contains("haze") || desc.contains("smoky") }
        private var isWindy:  Bool { !isStorm && !isSnow && !isRain && (desc.contains("windy") || desc.contains("breezy") || desc.contains("gust")) }
        private var isHot:    Bool { !isStorm && desc.contains("hot") }
        private var isFrigid: Bool { !isStorm && !isSnow && desc.contains("frigid") }
        private var isPartlyCloudy: Bool {
            !isStorm && !isSnow && !isRain && !isFog && !isWindy
            && (desc.contains("partly") || desc.contains("mostly clear") || desc.contains("mostly sunny"))
        }
        private var isCloudy: Bool {
            !isStorm && !isSnow && !isRain && !isFog && !isWindy && !isPartlyCloudy
            && (desc.contains("cloud") || desc.contains("overcast") || desc.contains("mostly"))
        }

        private func skyColors() -> [Color] {
            if isStorm  { return [Color(red: 0.03, green: 0.03, blue: 0.10), Color(red: 0.10, green: 0.10, blue: 0.22)] }
            if isSnow   { return [Color(red: 0.42, green: 0.52, blue: 0.72), Color(red: 0.70, green: 0.80, blue: 0.92)] }
            if isRain   { return [Color(red: 0.10, green: 0.16, blue: 0.28), Color(red: 0.22, green: 0.32, blue: 0.46)] }
            if isFog    { return isDaylight
                            ? [Color(red: 0.55, green: 0.60, blue: 0.70), Color(red: 0.74, green: 0.78, blue: 0.86)]
                            : [Color(red: 0.06, green: 0.07, blue: 0.16), Color(red: 0.12, green: 0.14, blue: 0.22)] }
            if isWindy  { return isDaylight
                            ? [Color(red: 0.28, green: 0.46, blue: 0.74), Color(red: 0.70, green: 0.82, blue: 0.92)]
                            : [Color(red: 0.05, green: 0.09, blue: 0.18), Color(red: 0.14, green: 0.18, blue: 0.28)] }
            if isPartlyCloudy { return isDaylight
                            ? [Color(red: 0.18, green: 0.50, blue: 0.92), Color(red: 0.76, green: 0.88, blue: 1.00)]
                            : [Color(red: 0.03, green: 0.06, blue: 0.16), Color(red: 0.18, green: 0.22, blue: 0.32)] }
            if isCloudy { return isDaylight
                            ? [Color(red: 0.40, green: 0.44, blue: 0.54), Color(red: 0.62, green: 0.66, blue: 0.74)]
                            : [Color(red: 0.07, green: 0.07, blue: 0.14), Color(red: 0.14, green: 0.16, blue: 0.22)] }
            if isHot    { return [Color(red: 0.86, green: 0.48, blue: 0.12), Color(red: 1.00, green: 0.77, blue: 0.34)] }
            if isFrigid { return [Color(red: 0.16, green: 0.28, blue: 0.46), Color(red: 0.72, green: 0.86, blue: 0.98)] }
            // Clear sky — time-of-day gradient transitions
            let c = Calendar.current; let now = Date()
            let h = Double(c.component(.hour, from: now)); let m = Double(c.component(.minute, from: now))
            let t = (h * 60 + m) / 1440.0
            switch t {
            case 0..<0.208:    return [Color(red: 0.01, green: 0.02, blue: 0.14), Color(red: 0.04, green: 0.06, blue: 0.24)]
            case 0.208..<0.27: return [Color(red: 0.08, green: 0.06, blue: 0.24), Color(red: 0.88, green: 0.42, blue: 0.18)]
            case 0.27..<0.34:  return [Color(red: 0.28, green: 0.44, blue: 0.88), Color(red: 1.00, green: 0.70, blue: 0.34)]
            case 0.34..<0.68:  return [Color(red: 0.06, green: 0.36, blue: 0.88), Color(red: 0.44, green: 0.76, blue: 1.00)]
            case 0.68..<0.76:  return [Color(red: 0.30, green: 0.48, blue: 0.86), Color(red: 1.00, green: 0.58, blue: 0.20)]
            case 0.76..<0.83:  return [Color(red: 0.14, green: 0.09, blue: 0.32), Color(red: 0.88, green: 0.34, blue: 0.14)]
            default:            return [Color(red: 0.01, green: 0.02, blue: 0.14), Color(red: 0.04, green: 0.06, blue: 0.24)]
            }
        }

        var body: some View {
            ZStack {
                LinearGradient(colors: skyColors(), startPoint: .top, endPoint: .bottom)
                if isStorm        { AWStormLayer() }
                else if isSnow    { AWSnowLayer() }
                else if isRain    { AWRainLayer() }
                else if isFog     { AWFogLayer(isDaylight: isDaylight) }
                else if isWindy   { AWWindLayer(isDaylight: isDaylight) }
                else if isPartlyCloudy { AWPartlyCloudyLayer(isDaylight: isDaylight) }
                else if isCloudy  { AWCloudyLayer(isDaylight: isDaylight) }
                else if isHot     { AWHeatLayer() }
                else if isFrigid  { AWFrigidLayer() }
                else if isDaylight { AWSunnyLayer() }
                else              { AWNightLayer() }
            }
        }
    }

    private struct AWPartlyCloudyLayer: View {
        let isDaylight: Bool
        private struct Cloud { let x, y, size, speed, phase, darkness: Double }
        private static let clouds: [Cloud] = {
            struct S { static var v: UInt64 = 0xABCDEF2299 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<6).map { _ in
                Cloud(
                    x: r(),
                    y: 0.10 + r() * 0.30,
                    size: 38 + r() * 44,
                    speed: 0.006 + r() * 0.007,
                    phase: r(),
                    darkness: 0.10 + r() * 0.18
                )
            }
        }()

        var body: some View {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isDaylight
                                    ? Color(red: 1.0, green: 0.93, blue: 0.60)
                                    : Color(red: 0.78, green: 0.84, blue: 1.0)
                                ).opacity(isDaylight ? 0.42 : 0.16),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 84
                        )
                    )
                    .frame(width: 168, height: 168)
                    .offset(x: 52, y: -40)
                    .blur(radius: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isDaylight ? Color(red: 1.0, green: 0.88, blue: 0.44) : Color.white).opacity(isDaylight ? 0.95 : 0.30),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 34
                        )
                    )
                    .frame(width: 68, height: 68)
                    .offset(x: 54, y: -42)

                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for cloud in Self.clouds {
                            let travel = CGFloat(((t * cloud.speed + cloud.phase).truncatingRemainder(dividingBy: 1))) * (size.width + 280)
                            let baseX = CGFloat(cloud.x) * size.width - 140 - travel
                            let baseY = CGFloat(cloud.y) * size.height
                            let r = CGFloat(cloud.size)
                            for dx: CGFloat in [0, size.width + 280, -(size.width + 280)] {
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 20))
                                    lc.fill(
                                        Path(ellipseIn: CGRect(x: baseX + dx - r * 1.20, y: baseY - r * 0.18, width: r * 2.40, height: r * 0.98)),
                                        with: .color(Color.black.opacity(isDaylight ? cloud.darkness * 0.55 : cloud.darkness * 0.90))
                                    )
                                }
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 9))
                                    lc.fill(
                                        Path(ellipseIn: CGRect(x: baseX + dx - r, y: baseY - r * 0.78, width: r * 2.02, height: r * 1.36)),
                                        with: .color((isDaylight ? Color.white : Color(red: 0.62, green: 0.66, blue: 0.74)).opacity(0.86))
                                    )
                                }
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 2))
                                    let sr = r * 0.52
                                    lc.fill(
                                        Path(ellipseIn: CGRect(x: baseX + dx - sr * 0.78, y: baseY - sr * 1.20, width: sr * 1.56, height: sr * 0.72)),
                                        with: .color(.white.opacity(isDaylight ? 0.66 : 0.30))
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct AWWindLayer: View {
        let isDaylight: Bool
        private struct Stream { let y, length, speed, phase, amp, thickness: Double }
        private static let streams: [Stream] = {
            struct S { static var v: UInt64 = 0xD00DBAAD11 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<18).map { _ in
                Stream(y: 0.08 + r() * 0.78, length: 46 + r() * 110, speed: 0.10 + r() * 0.16, phase: r(), amp: 4 + r() * 12, thickness: 0.8 + r() * 2.0)
            }
        }()

        var body: some View {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for stream in Self.streams {
                        let baseY = CGFloat(stream.y) * size.height
                        let travel = CGFloat(((t * stream.speed + stream.phase).truncatingRemainder(dividingBy: 1))) * (size.width + CGFloat(stream.length) + 120)
                        let startX = -CGFloat(stream.length) + travel - 60
                        var path = Path()
                        path.move(to: CGPoint(x: startX, y: baseY))
                        let segments = 14
                        for idx in 1...segments {
                            let progress = CGFloat(idx) / CGFloat(segments)
                            let x = startX + CGFloat(stream.length) * progress
                            let y = baseY + CGFloat(sin(t * 2.4 + Double(progress) * 4.6 + stream.phase * 6.28) * stream.amp)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        ctx.stroke(path, with: .color((isDaylight ? Color.white : Color(red: 0.78, green: 0.86, blue: 1.0)).opacity(0.20)),
                                   style: StrokeStyle(lineWidth: stream.thickness * 2.4, lineCap: .round, lineJoin: .round))
                        ctx.stroke(path, with: .linearGradient(
                            Gradient(colors: [.clear, (isDaylight ? Color.white : Color(red: 0.80, green: 0.88, blue: 1.0)).opacity(0.78), .clear]),
                            startPoint: CGPoint(x: startX, y: baseY),
                            endPoint: CGPoint(x: startX + CGFloat(stream.length), y: baseY)
                        ), style: StrokeStyle(lineWidth: stream.thickness, lineCap: .round, lineJoin: .round))
                    }

                    for idx in 0..<16 {
                        let p = (t * (0.06 + Double(idx) * 0.004) + Double(idx) * 0.13).truncatingRemainder(dividingBy: 1)
                        let x = p * (Double(size.width) + 60) - 30
                        let y = Double(size.height) * (0.12 + Double(idx % 8) * 0.10) + sin(t * 2.1 + Double(idx)) * 12
                        let w = 8 + Double(idx % 4) * 2
                        let h = 1.4 + Double(idx % 3) * 0.4
                        let rect = CGRect(x: x, y: y, width: w, height: h)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: h), with: .color(Color.white.opacity(isDaylight ? 0.18 : 0.14)))
                    }
                }
            }
        }
    }

    private struct AWHeatLayer: View {
        @State private var pulse = false

        var body: some View {
            ZStack {
                AWSunnyLayer()
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for idx in 0..<13 {
                            let x = CGFloat(idx) / 12 * size.width
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: size.height + 10))
                            let segments = 10
                            for step in 0...segments {
                                let progress = CGFloat(step) / CGFloat(segments)
                                let y = size.height - progress * size.height * 0.72
                                let offset = CGFloat(sin(t * 1.8 + Double(idx) * 0.8 + Double(step) * 0.6) * 6.5)
                                path.addLine(to: CGPoint(x: x + offset, y: y))
                            }
                            ctx.stroke(path, with: .color(Color.white.opacity(0.10)),
                                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        }
                    }
                }
                Circle()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.18).opacity(pulse ? 0.16 : 0.08))
                    .frame(width: pulse ? 280 : 220, height: pulse ? 280 : 220)
                    .blur(radius: 24)
                    .offset(x: 56, y: -46)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private struct AWFrigidLayer: View {
        private struct Crystal { let x, y, size, speed, phase: Double }
        private static let crystals: [Crystal] = {
            struct S { static var v: UInt64 = 0xF11E9E0C }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<28).map { _ in Crystal(x: r(), y: r() * 0.76, size: 5 + r() * 9, speed: 0.2 + r() * 0.3, phase: r()) }
        }()

        var body: some View {
            ZStack {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for crystal in Self.crystals {
                            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * crystal.speed + crystal.phase * 6.28))
                            let cx = CGFloat(crystal.x) * size.width
                            let cy = CGFloat(crystal.y) * size.height
                            let r = CGFloat(crystal.size)
                            var path = Path()
                            for arm in 0..<6 {
                                let angle = CGFloat(arm) * (.pi / 3)
                                let tip = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
                                path.move(to: CGPoint(x: cx, y: cy))
                                path.addLine(to: tip)
                            }
                            ctx.stroke(path, with: .color(Color.white.opacity(twinkle * 0.44)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                            ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.2, y: cy - 1.2, width: 2.4, height: 2.4)), with: .color(Color.white.opacity(twinkle * 0.8)))
                        }
                    }
                }

                LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                AWFogLayer(isDaylight: true)
                    .opacity(0.30)
            }
        }
    }

    // MARK: Sunny — time-tracking sun arc + drifting fluffy clouds
    private struct AWSunnyLayer: View {
        @State private var haloPulse = false

        private static var sunProgress: Double {
            let c = Calendar.current; let now = Date()
            let h = Double(c.component(.hour, from: now)); let m = Double(c.component(.minute, from: now))
            return max(0, min(1, (h * 60 + m - 360) / 720))
        }
        private var sunOffset: CGSize {
            let p = Self.sunProgress
            return CGSize(width: (p - 0.5) * 200, height: -(1 - pow(2 * p - 1, 2)) * 50 - 10)
        }
        private var sunTint: Color {
            let p = Self.sunProgress
            return (p < 0.22 || p > 0.78) ? Color(red: 1.0, green: 0.60, blue: 0.20)
                                           : Color(red: 1.0, green: 0.95, blue: 0.55)
        }

        private struct CloudBlob { let nx, ny, br, spd, phase: Double }
        private static let clouds: [CloudBlob] = {
            struct S { static var v: UInt64 = 0xFEEDC0FE01 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<4).map { _ in CloudBlob(nx: r(), ny: 0.06 + r() * 0.16, br: 26 + r() * 32, spd: 0.012 + r() * 0.010, phase: r()) }
        }()

        var body: some View {
            ZStack {
                LinearGradient(colors: [.clear, Color(red: 1.0, green: 0.88, blue: 0.64).opacity(0.14)],
                               startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for idx in 0..<6 {
                            let progress = (t * (0.008 + Double(idx) * 0.002) + Double(idx) * 0.14).truncatingRemainder(dividingBy: 1)
                            let x = progress * (Double(size.width) + 180) - 90
                            let y = Double(size.height) * (0.18 + Double(idx) * 0.08)
                            let w = 84 + Double(idx % 3) * 40
                            let h = 20 + Double(idx % 2) * 8
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                                     with: .color(Color.white.opacity(0.028)))
                        }
                    }
                    .blur(radius: 18)
                }
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for c in Self.clouds {
                            let scroll = CGFloat(((t * c.spd + c.phase).truncatingRemainder(dividingBy: 1))) * (size.width + 200)
                            let cx = CGFloat(c.nx) * size.width - scroll
                            let cy = CGFloat(c.ny) * size.height
                            let r  = CGFloat(c.br)
                            for dx: CGFloat in [0, size.width + 200, -(size.width + 200)] {
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 14))
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-r*0.9, y: cy-r*0.18, width: r*1.8, height: r*0.96)),
                                            with: .color(Color(red: 0.68, green: 0.78, blue: 0.92).opacity(0.52)))
                                }
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 7))
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-r, y: cy-r*0.72, width: r*2, height: r*1.44)),
                                            with: .color(.white.opacity(0.82)))
                                }
                                ctx.drawLayer { lc in
                                    lc.addFilter(.blur(radius: 2))
                                    let sr = r * 0.52
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-sr*0.80, y: cy-sr*1.22, width: sr*1.60, height: sr*0.72)),
                                            with: .color(.white.opacity(0.95)))
                                }
                            }
                        }
                    }
                }
                ZStack {
                    Circle().fill(sunTint.opacity(haloPulse ? 0.12 : 0.08)).frame(width: haloPulse ? 168 : 146).blur(radius: 34)
                    Circle().fill(sunTint.opacity(haloPulse ? 0.28 : 0.22)).frame(width: haloPulse ? 86 : 78).blur(radius: 18)
                    Circle().fill(
                        RadialGradient(
                            colors: [sunTint, sunTint.opacity(0.46), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 28
                        )
                    ).frame(width: 54)
                }
                .offset(sunOffset)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) { haloPulse = true }
            }
        }
    }

    // MARK: Night — twinkling stars + moon
    private struct AWNightLayer: View {
        private static let stars: [(x: Double, y: Double, r: Double, hue: Double, spd: Double)] = {
            struct S { static var v: UInt64 = 0xDEADBEEF44 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<55).map { _ in (r(), r() * 0.80, 1.0 + r() * 2.5, r(), 0.7 + r() * 2.4) }
        }()

        var body: some View {
            ZStack {
                LinearGradient(colors: [.clear, Color(red: 0.50, green: 0.26, blue: 0.04).opacity(0.20)],
                               startPoint: UnitPoint(x: 0.5, y: 0.62), endPoint: .bottom)
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        ctx.drawLayer { lc in
                            lc.addFilter(.blur(radius: 2.4))
                            for s in Self.stars {
                                let a = 0.5 + 0.45 * sin(t * s.spd + s.x * 6.28)
                                let cx = CGFloat(s.x) * size.width; let cy = CGFloat(s.y) * size.height
                                let rv = CGFloat(s.r) * 1.7
                                lc.fill(Path(ellipseIn: CGRect(x: cx-rv, y: cy-rv, width: rv*2, height: rv*2)),
                                        with: .color(.white.opacity(a * 0.5)))
                            }
                        }
                        for s in Self.stars {
                            let a = 0.5 + 0.45 * sin(t * s.spd + s.x * 6.28)
                            let cx = CGFloat(s.x) * size.width; let cy = CGFloat(s.y) * size.height
                            let rv = CGFloat(s.r * 0.50)
                            let col: Color = s.hue < 0.33 ? Color(red: 0.80, green: 0.90, blue: 1.00)
                                           : s.hue < 0.66 ? .white
                                           : Color(red: 1.00, green: 0.96, blue: 0.76)
                            ctx.fill(Path(ellipseIn: CGRect(x: cx-rv, y: cy-rv, width: rv*2, height: rv*2)),
                                     with: .color(col.opacity(a)))
                        }

                    }
                }
                ZStack {
                    Circle().fill(Color(red: 0.88, green: 0.92, blue: 1.00).opacity(0.09)).frame(width: 110).blur(radius: 22)
                    Circle().fill(Color.white.opacity(0.14)).frame(width: 66).blur(radius: 10)
                    Circle().fill(RadialGradient(
                        colors: [Color(red: 0.97, green: 0.97, blue: 1.00), Color(red: 0.80, green: 0.84, blue: 0.95)],
                        center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0, endRadius: 23)).frame(width: 46)
                        .shadow(color: .white.opacity(0.20), radius: 11)
                }
                .offset(x: 42, y: -34)
                LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 46, height: 170).offset(x: 42, y: 58)
            }
        }
    }

    // MARK: Rain — dark clouds + animated streaks + splash ripples
    private struct AWRainLayer: View {
        private struct Drop { let nx, spd, len, opa, phase, slant: Double }
        private static let drops: [Drop] = (0..<80).map { i in
            var s = UInt64(i &* 7919 &+ 1)
            func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 48) / 65536.0 }
            return Drop(nx: r(), spd: 0.38+r()*0.32, len: 16+r()*20, opa: 0.26+r()*0.34, phase: r(), slant: 2.0+r()*3.5)
        }
        private static let blobs: [(Double, Double, Double)] = {
            struct S { static var v: UInt64 = 0xC10DD4A7C }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<10).map { _ in (r(), r()*0.14, 44+r()*52) }
        }()

        var body: some View {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let scroll = CGFloat((t * 0.013).truncatingRemainder(dividingBy: 1)) * size.width
                    let gust = CGFloat(sin(t * 0.9) * 2.4)
                    ctx.drawLayer { lc in
                        lc.addFilter(.blur(radius: 20))
                        for b in Self.blobs {
                            let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)
                            for dx: CGFloat in [0, size.width, -size.width] {
                                lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.88, y: cy-rv*0.08, width: rv*1.76, height: rv*0.90)),
                                        with: .color(Color(red: 0.05, green: 0.07, blue: 0.14).opacity(0.92)))
                            }
                        }
                    }
                    ctx.drawLayer { lc in
                        lc.addFilter(.blur(radius: 10))
                        for b in Self.blobs {
                            let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)
                            for dx: CGFloat in [0, size.width, -size.width] {
                                lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv, y: cy-rv*0.62, width: rv*2, height: rv*1.24)),
                                        with: .color(Color(red: 0.16, green: 0.20, blue: 0.32).opacity(0.90)))
                            }
                        }
                    }
                    ctx.drawLayer { lc in
                        lc.addFilter(.blur(radius: 3))
                        for b in Self.blobs {
                            let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)*0.52
                            for dx: CGFloat in [0, size.width, -size.width] {
                                lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.84, y: cy-rv*1.16, width: rv*1.68, height: rv*0.68)),
                                        with: .color(Color(red: 0.30, green: 0.36, blue: 0.50).opacity(0.50)))
                            }
                        }
                    }
                    let dropCol = Color(red: 0.72, green: 0.84, blue: 1.00)
                    for d in Self.drops {
                        let p = (t * d.spd + d.phase).truncatingRemainder(dividingBy: 1)
                        let x = CGFloat(d.nx) * size.width + gust
                        let y = p * (size.height + CGFloat(d.len)) - CGFloat(d.len)
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - CGFloat(d.slant) - gust, y: y + CGFloat(d.len)))
                        ctx.stroke(path, with: .color(dropCol.opacity(d.opa)),
                                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

                        if d.opa > 0.46 {
                            var nearPath = Path()
                            nearPath.move(to: CGPoint(x: x + 2, y: y - 2))
                            nearPath.addLine(to: CGPoint(x: x - CGFloat(d.slant * 1.2) - gust * 1.2, y: y + CGFloat(d.len * 1.18)))
                            ctx.stroke(nearPath, with: .color(dropCol.opacity(d.opa * 0.34)),
                                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        }
                    }

                    let mistRect = CGRect(x: 0, y: size.height * 0.70, width: size.width, height: size.height * 0.30)
                    ctx.fill(Path(mistRect), with: .linearGradient(
                        Gradient(colors: [.clear, Color.white.opacity(0.05), Color.white.opacity(0.12)]),
                        startPoint: CGPoint(x: 0, y: size.height * 0.70),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))

                    for ri in 0..<8 {
                        let rxN = (Double(ri)/8.0 + t*0.10).truncatingRemainder(dividingBy: 1)
                        let rx  = rxN * Double(size.width)
                        let rT  = (t*0.80 + Double(ri)*0.16).truncatingRemainder(dividingBy: 1)
                        let rr  = rT * 12 + 2; let alpha = (1 - rT) * 0.25
                        ctx.stroke(Path(ellipseIn: CGRect(x: rx-rr, y: Double(size.height)-5-rr*0.38,
                                                          width: rr*2, height: rr*0.76)),
                                   with: .color(.white.opacity(alpha)), lineWidth: 0.8)
                    }
                }
            }
        }
    }

    // MARK: Storm — deep dark clouds + heavy rain + lightning flashes
    private struct AWStormLayer: View {
        private struct Drop { let nx, spd, len, opa, phase: Double }
        private static let drops: [Drop] = (0..<96).map { i in
            var s = UInt64(i &* 4523 &+ 17)
            func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 48) / 65536.0 }
            return Drop(nx: r(), spd: 0.55+r()*0.50, len: 18+r()*26, opa: 0.34+r()*0.40, phase: r())
        }
        private static let blobs: [(Double, Double, Double)] = {
            struct S { static var v: UInt64 = 0xD4A705E12 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<12).map { _ in (r(), r()*0.20, 52+r()*62) }
        }()

        private func flashEnvelope(t: Double, period: Double, phase: Double, width: Double) -> Double {
            let local = (t / period + phase).truncatingRemainder(dividingBy: 1)
            let dist = abs(local - 0.5)
            return max(0.0, 1.0 - dist / max(width, 0.0001))
        }

        private func boltPath(in size: CGSize, originX: CGFloat, fork: Bool) -> Path {
            var path = Path()
            let start = CGPoint(x: originX, y: size.height * 0.18)
            path.move(to: start)
            path.addLine(to: CGPoint(x: originX - 10, y: size.height * 0.34))
            path.addLine(to: CGPoint(x: originX + 8, y: size.height * 0.34))
            path.addLine(to: CGPoint(x: originX - 18, y: size.height * 0.56))
            path.addLine(to: CGPoint(x: originX - 4, y: size.height * 0.56))
            path.addLine(to: CGPoint(x: originX - 26, y: size.height * 0.82))
            if fork {
                path.move(to: CGPoint(x: originX + 2, y: size.height * 0.42))
                path.addLine(to: CGPoint(x: originX + 24, y: size.height * 0.56))
                path.addLine(to: CGPoint(x: originX + 8, y: size.height * 0.70))
            }
            return path
        }

        var body: some View {
            TimelineView(.animation) { tl in
                ZStack {
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let gust = CGFloat(2.2 + sin(t * 1.4) * 2.8)
                        for layer in 0..<3 {
                            let spd = 0.009 + Double(layer) * 0.006
                            let yOff = Double(layer) * 0.09
                            let blurR = CGFloat(14 - layer * 3)
                            let alph = 0.92 - Double(layer) * 0.12
                            ctx.drawLayer { lc in
                                lc.addFilter(.blur(radius: blurR))
                                let scroll = CGFloat((t * spd + Double(layer) * 0.33).truncatingRemainder(dividingBy: 1)) * size.width
                                let scl = CGFloat(1.0 - Double(layer) * 0.11)
                                for b in Self.blobs {
                                    let cx = CGFloat(b.0)*size.width-scroll
                                    let cy = (CGFloat(b.1)+CGFloat(yOff))*size.height
                                    let rv = CGFloat(b.2)*scl
                                    for dx: CGFloat in [0, size.width, -size.width] {
                                        lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.88, y: cy-rv*0.12, width: rv*1.76, height: rv*0.86)),
                                                with: .color(Color(red: 0.02, green: 0.02, blue: 0.06).opacity(alph)))
                                        lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv, y: cy-rv*0.62, width: rv*2, height: rv*1.24)),
                                                with: .color(Color(red: 0.09, green: 0.09, blue: 0.20).opacity(alph * 0.88)))
                                    }
                                }
                            }
                        }
                        let rainCol = Color(red: 0.70, green: 0.82, blue: 1.00)
                        for d in Self.drops {
                            let p = (t * d.spd + d.phase).truncatingRemainder(dividingBy: 1)
                            let x = CGFloat(d.nx) * size.width + gust
                            let y = p * (size.height + CGFloat(d.len)) - CGFloat(d.len)
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: y))
                            path.addLine(to: CGPoint(x: x - 6 - gust, y: y + CGFloat(d.len)))
                            ctx.stroke(path, with: .color(rainCol.opacity(d.opa)),
                                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                        }

                        let flashA = flashEnvelope(t: t, period: 8.9, phase: 0.19, width: 0.025)
                        let flashB = flashEnvelope(t: t, period: 13.4, phase: 0.63, width: 0.018)
                        let flashC = flashEnvelope(t: t, period: 17.8, phase: 0.41, width: 0.015)

                        if flashA > 0.02 {
                            let bolt = boltPath(in: size, originX: size.width * 0.70, fork: true)
                            ctx.stroke(bolt, with: .color(Color.white.opacity(flashA * 0.22)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                            ctx.stroke(bolt, with: .color(Color(red: 0.82, green: 0.92, blue: 1.0).opacity(flashA * 0.92)), style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                        }
                        if flashB > 0.02 {
                            let bolt = boltPath(in: size, originX: size.width * 0.34, fork: false)
                            ctx.stroke(bolt, with: .color(Color.white.opacity(flashB * 0.20)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                            ctx.stroke(bolt, with: .color(Color(red: 0.82, green: 0.94, blue: 1.0).opacity(flashB * 0.86)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        }
                        if flashC > 0.02 {
                            let bolt = boltPath(in: size, originX: size.width * 0.54, fork: true)
                            ctx.stroke(bolt, with: .color(Color.white.opacity(flashC * 0.16)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            ctx.stroke(bolt, with: .color(Color(red: 0.78, green: 0.90, blue: 1.0).opacity(flashC * 0.70)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                        }
                    }
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let f1 = flashEnvelope(t: t, period: 8.9, phase: 0.19, width: 0.028)
                    let f2 = flashEnvelope(t: t, period: 13.4, phase: 0.63, width: 0.020)
                    let f3 = flashEnvelope(t: t, period: 17.8, phase: 0.41, width: 0.017)
                    Color.white.opacity(min(1, (f1 * 0.45 + f2 * 0.40 + f3 * 0.32))).blendMode(.screen).allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Snow — grey clouds + drifting ice crystals + accumulation
    private struct AWSnowLayer: View {
        private struct Flake { let nx, spd, sz, drift, dspd, opa, phase, rot: Double }
        private static let flakes: [Flake] = (0..<55).map { i in
            var s = UInt64(i &* 3571 &+ 5)
            func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 48) / 65536.0 }
            return Flake(nx: r(), spd: 0.022+r()*0.020, sz: 3.5+r()*8.0,
                         drift: (r()>0.5 ? 1.0:-1.0)*(4+r()*14), dspd: 0.15+r()*0.25,
                         opa: 0.50+r()*0.42, phase: r(), rot: r()*Double.pi*2)
        }
        private static let blobs: [(Double, Double, Double)] = {
            struct S { static var v: UInt64 = 0xC10DD4A7F }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<10).map { _ in (r(), r()*0.14, 42+r()*48) }
        }()

        var body: some View {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let scroll = CGFloat((t*0.007).truncatingRemainder(dividingBy: 1)) * size.width
                    ctx.drawLayer { lc in
                        lc.addFilter(.blur(radius: 16))
                        for b in Self.blobs {
                            let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)
                            for dx: CGFloat in [0, size.width, -size.width] {
                                lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.90, y: cy-rv*0.10, width: rv*1.80, height: rv*0.88)),
                                        with: .color(Color(red: 0.28, green: 0.34, blue: 0.44).opacity(0.88)))
                                lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv, y: cy-rv*0.64, width: rv*2, height: rv*1.28)),
                                        with: .color(Color(red: 0.44, green: 0.50, blue: 0.62).opacity(0.80)))
                            }
                        }
                    }
                    let gustBias = sin(t * 0.11) * 20.0
                    for f in Self.flakes {
                        let p = (t*f.spd + f.phase).truncatingRemainder(dividingBy: 1)
                        let wobble = sin(t*f.dspd + f.nx*Double.pi*2) * f.drift
                        let cx = f.nx * Double(size.width) + wobble + gustBias
                        let cy = p * (Double(size.height) + f.sz) - f.sz
                        let rv = f.sz / 2; let rot = f.rot + t * 0.10
                        let alpha = f.opa * (0.85 + 0.15 * sin(t*2.2 + f.nx*8.0))
                        var crystal = Path()
                        for arm in 0..<6 {
                            let angle = Double(arm) * (Double.pi/3) + rot
                            let tipX = cx + cos(angle)*rv; let tipY = cy + sin(angle)*rv
                            crystal.move(to: CGPoint(x: cx - cos(angle)*rv*0.10, y: cy - sin(angle)*rv*0.10))
                            crystal.addLine(to: CGPoint(x: tipX, y: tipY))
                            let bl = rv*0.36; let bx = cx + cos(angle)*rv*0.52; let by = cy + sin(angle)*rv*0.52
                            for side in [-1.0, 1.0] {
                                let ba = angle + side * (Double.pi/4)
                                crystal.move(to: CGPoint(x: bx, y: by))
                                crystal.addLine(to: CGPoint(x: bx + cos(ba)*bl, y: by + sin(ba)*bl))
                            }
                        }
                        let dotR = rv * 0.20
                        ctx.fill(Path(ellipseIn: CGRect(x: cx-dotR, y: cy-dotR, width: dotR*2, height: dotR*2)),
                                 with: .color(.white.opacity(alpha)))
                        ctx.stroke(crystal, with: .color(.white.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: max(0.8, rv*0.20), lineCap: .round))
                    }
                    var mound = Path()
                    mound.move(to: CGPoint(x: 0, y: Double(size.height)))
                    for step in 0...60 {
                        let xi = Double(step)/60.0*Double(size.width)
                        mound.addLine(to: CGPoint(x: xi, y: Double(size.height)-(8+sin(xi*0.26)*5+sin(xi*0.10+1.8)*3.5)))
                    }
                    mound.addLine(to: CGPoint(x: Double(size.width), y: Double(size.height)))
                    mound.closeSubpath()
                    ctx.fill(mound, with: .color(.white.opacity(0.92)))
                }
            }
        }
    }

    // MARK: Fog — drifting mist bands
    private struct AWFogLayer: View {
        let isDaylight: Bool
        private struct Band { let yFrac, spd, w, h, opa: Double }
        private let bands: [Band] = [
            Band(yFrac: 0.07, spd: 0.018, w: 1.85, h: 88, opa: 0.28),
            Band(yFrac: 0.23, spd: 0.028, w: 1.65, h: 66, opa: 0.22),
            Band(yFrac: 0.41, spd: 0.014, w: 1.90, h: 78, opa: 0.26),
            Band(yFrac: 0.57, spd: 0.024, w: 1.70, h: 60, opa: 0.20),
            Band(yFrac: 0.72, spd: 0.020, w: 1.86, h: 70, opa: 0.24),
            Band(yFrac: 0.86, spd: 0.030, w: 1.60, h: 54, opa: 0.17),
        ]
        var body: some View {
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [isDaylight ? Color(red: 1.0, green: 0.88, blue: 0.50).opacity(0.42) : Color.white.opacity(0.05), .clear],
                    center: .center, startRadius: 0, endRadius: 46))
                    .frame(width: 92).blur(radius: 28).offset(x: 30, y: -22)
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let pulse = 1.0 + sin(t * 0.06) * 0.18
                        for b in bands {
                            let off = CGFloat((t * b.spd).truncatingRemainder(dividingBy: 1)) * size.width
                            let w = size.width * CGFloat(b.w); let h = CGFloat(b.h)
                            let y = CGFloat(b.yFrac) * size.height - h / 2 + CGFloat(sin(t * b.spd * 8) * 6)
                            let alpha = min(b.opa * pulse, 0.50)
                            for rawX in [-off, size.width - off] {
                                ctx.fill(Path(ellipseIn: CGRect(x: rawX-(w-size.width)/2, y: y, width: w, height: h)),
                                         with: .color(.white.opacity(alpha)))
                            }
                        }
                    }
                    .blur(radius: 22)
                }
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for (i, b) in bands.enumerated() {
                            let off = CGFloat((t*b.spd*1.6 + Double(i)*0.24).truncatingRemainder(dividingBy: 1)) * size.width
                            let w = size.width * CGFloat(b.w*0.76); let h = CGFloat(b.h*0.50)
                            let y = CGFloat(b.yFrac + 0.05)*size.height - h/2 + CGFloat(cos(t * b.spd * 10 + Double(i)) * 4)
                            ctx.fill(Path(ellipseIn: CGRect(x: -off, y: y, width: w, height: h)),
                                     with: .color(.white.opacity(b.opa*0.48)))
                        }
                    }
                    .blur(radius: 8)
                }
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                        Gradient(colors: [.clear, Color.black.opacity(0.24)]),
                        center: CGPoint(x: size.width/2, y: size.height/2),
                        startRadius: min(size.width, size.height)*0.25,
                        endRadius: max(size.width, size.height)*0.70))
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Cloudy — heavy overcast layered cloud mass
    private struct AWCloudyLayer: View {
        let isDaylight: Bool
        private static let blobs: [(Double, Double, Double, Double)] = {
            struct S { static var v: UInt64 = 0xC10FFEE234 }
            func r() -> Double { S.v = S.v &* 6364136223846793005 &+ 1442695040888963407; return Double(S.v >> 48) / 65536.0 }
            return (0..<14).map { _ in (r(), 0.04+r()*0.56, 38+r()*58, 0.007+r()*0.013) }
        }()
        var body: some View {
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [isDaylight ? Color(red: 1.0, green: 0.95, blue: 0.78).opacity(0.18) : Color.white.opacity(0.05), .clear],
                    center: .center, startRadius: 0, endRadius: 52))
                    .frame(width: 110).blur(radius: 34).offset(x: 20, y: -20)
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        ctx.drawLayer { lc in
                            lc.addFilter(.blur(radius: 22))
                            for b in Self.blobs {
                                let scroll = CGFloat((t*b.3).truncatingRemainder(dividingBy: 1)) * size.width
                                let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)
                                for dx: CGFloat in [0, size.width, -size.width] {
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.90, y: cy-rv*0.08, width: rv*1.80, height: rv*0.90)),
                                            with: .color((isDaylight ? Color(red:0.32,green:0.34,blue:0.40) : Color(red:0.06,green:0.06,blue:0.10)).opacity(0.90)))
                                }
                            }
                        }
                        ctx.drawLayer { lc in
                            lc.addFilter(.blur(radius: 13))
                            for b in Self.blobs {
                                let scroll = CGFloat((t*b.3).truncatingRemainder(dividingBy: 1)) * size.width
                                let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2)
                                for dx: CGFloat in [0, size.width, -size.width] {
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv, y: cy-rv*0.68, width: rv*2, height: rv*1.36)),
                                            with: .color((isDaylight ? Color(red:0.58,green:0.60,blue:0.66) : Color(red:0.16,green:0.17,blue:0.24)).opacity(0.90)))
                                }
                            }
                        }
                        ctx.drawLayer { lc in
                            lc.addFilter(.blur(radius: 6))
                            for b in Self.blobs {
                                let scroll = CGFloat((t*b.3).truncatingRemainder(dividingBy: 1)) * size.width
                                let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2*0.76)
                                for dx: CGFloat in [0, size.width, -size.width] {
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv, y: cy-rv*0.94, width: rv*2, height: rv*1.30)),
                                            with: .color((isDaylight ? Color(red:0.68,green:0.70,blue:0.75) : Color(red:0.22,green:0.23,blue:0.30)).opacity(0.70)))
                                }
                            }
                        }
                        ctx.drawLayer { lc in
                            lc.addFilter(.blur(radius: 2))
                            for b in Self.blobs.prefix(10) {
                                let scroll = CGFloat((t*b.3).truncatingRemainder(dividingBy: 1)) * size.width
                                let cx = CGFloat(b.0)*size.width-scroll; let cy = CGFloat(b.1)*size.height; let rv = CGFloat(b.2*0.50)
                                for dx: CGFloat in [0, size.width, -size.width] {
                                    lc.fill(Path(ellipseIn: CGRect(x: cx+dx-rv*0.82, y: cy-rv*1.26, width: rv*1.64, height: rv*0.68)),
                                            with: .color((isDaylight ? Color(red:0.80,green:0.82,blue:0.86) : Color(red:0.28,green:0.30,blue:0.38)).opacity(0.60)))
                                }
                            }
                        }

                        let opening = CGRect(x: size.width * 0.58, y: size.height * 0.14, width: size.width * 0.30, height: size.height * 0.18)
                        ctx.addFilter(.blur(radius: 22))
                        ctx.fill(Path(ellipseIn: opening), with: .color((isDaylight ? Color.white : Color(red: 0.76, green: 0.84, blue: 1.0)).opacity(isDaylight ? 0.05 : 0.03)))
                    }
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
        @ObservedObject var weatherService: WeatherKitService

        var body: some View {
            HStack(spacing: 8) {
                if let weather = weatherService.currentWeather {
                    // Weather icon based on condition and day/night
                    Image(systemName: weatherIcon(for: weather.description, isDaylight: weather.isDaylight))
                        .foregroundStyle(weather.isDaylight ? .orange : .indigo)
                        .font(.title3)
                        .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 2) {
                        if let temp = weather.temperature {
                            Text(String(format: "%.1f°C", temp))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
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

        private func weatherIcon(for description: String?, isDaylight: Bool) -> String {
            guard let desc = description?.lowercased() else {
                return isDaylight ? "sun.max.fill" : "moon.fill"
            }
            if desc.contains("clear") || desc.contains("mostly clear") {
                return isDaylight ? "sun.max.fill" : "moon.stars.fill"
            } else if desc.contains("partly cloudy") || desc.contains("mostly cloudy") {
                return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
            } else if desc.contains("cloud") {
                return "cloud.fill"
            } else if desc.contains("thunder") || desc.contains("storm") {
                return "cloud.bolt.fill"
            } else if desc.contains("snow") || desc.contains("blizzard") || desc.contains("sleet") {
                return "cloud.snow.fill"
            } else if desc.contains("rain") || desc.contains("drizzle") {
                return "cloud.rain.fill"
            } else if desc.contains("fog") || desc.contains("haze") || desc.contains("smoky") {
                return "cloud.fog.fill"
            } else if desc.contains("windy") || desc.contains("breezy") {
                return "wind"
            } else {
                return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
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

        // Emergency Widget Configuration (shared via App Group)
        @State private var emergencyWidgetEndpoint: String = ""
        @State private var widgetAuthToken: String = ""
        @State private var widgetConfigStatusMessage: String? = nil

        // Committee Member Settings
        @AppStorage("committeeMembers") private var committeeMembers: String = ""
        
        // Cached admin/committee status from Firestore
        @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
        @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false

        // Push Notification Toggle
        @AppStorage("allowPushNotifications") private var allowPushNotifications: Bool = true

        @State private var selectedPosition = 1  // 0=left, 1=right, 2=center
        @State private var cameraAccessRequestSubmitted = false
        @State private var showCameraRequestAlert = false
        @State private var cameraRequestMessage = ""
        
        // Profile picture state
        @AppStorage("profileImageURL") private var profileImageURL: String = ""
        @AppStorage("userUID") private var userUID: String = ""
        @AppStorage("userEmail") private var userEmail: String = ""
        @State private var profilePhotoItem: PhotosPickerItem? = nil
        @State private var isUploadingPhoto = false
        @State private var profilePreviewImage: UIImage? = nil
        @State private var profileImageCacheBuster: String = ""
        
        // Track previous watch username to detect changes
        @State private var previousWatchUsername = ""
        
        // Sign out state
        @State private var showSignOutConfirmation = false

        // Delete account state
        @State private var showDeleteAccountConfirmation = false
        @State private var showDeleteAccountFinalConfirmation = false
        @State private var isDeletingAccount = false
        @State private var deleteAccountError: String? = nil
        @State private var showDeleteAccountError = false

        // Subscription
        @State private var showSubscriptionView = false

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

        private var settingsInitialsAvatar: some View {
            let initials = "\(userName.prefix(1))\(userSurname.prefix(1))".uppercased()
            return ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }

        private var cacheBustedProfileImageURL: URL? {
            guard !profileImageURL.isEmpty, var components = URLComponents(string: profileImageURL)
            else {
                return nil
            }

            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "nhcb" }
            if !profileImageCacheBuster.isEmpty {
                queryItems.append(URLQueryItem(name: "nhcb", value: profileImageCacheBuster))
            }
            components.queryItems = queryItems
            return components.url
        }

        @ViewBuilder
        private var userProfileSection: some View {
            Section("User Profile") {
                // Profile picture row
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomTrailing) {
                        if let profilePreviewImage {
                            Image(uiImage: profilePreviewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else if let url = cacheBustedProfileImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                default:
                                    settingsInitialsAvatar
                                }
                            }
                            .frame(width: 80, height: 80)
                        } else {
                            settingsInitialsAvatar
                        }

                        PhotosPicker(selection: $profilePhotoItem, matching: .images) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Circle().fill(Color(.systemBackground)).padding(1))
                        }
                        .onChange(of: profilePhotoItem) { _, item in
                            handleSelectedProfilePhotoItem(item)
                        }
                    }
                    .overlay(alignment: .center) {
                        if isUploadingPhoto {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 80, height: 80)
                                .background(Circle().fill(Color.black.opacity(0.4)))
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

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

                Button {
                    showSubscriptionView = true
                } label: {
                    HStack {
                        Label("Manage Subscription", systemImage: "star.circle.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)

            }
        }

        private func handleSelectedProfilePhotoItem(_ item: PhotosPickerItem?) {
            guard let item else { return }

            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    profilePreviewImage = image
                    isUploadingPhoto = true
                }
                #if canImport(FirebaseStorage)
                let completion: (Result<String, Error>) -> Void = { result in
                    DispatchQueue.main.async {
                        isUploadingPhoto = false
                        profilePhotoItem = nil
                        if case .success(let urlStr) = result {
                            profileImageURL = urlStr
                            UserDefaults.standard.set(urlStr, forKey: "profileImageURL")
                            profileImageCacheBuster = "\(Int(Date().timeIntervalSince1970))"
                            profilePreviewImage = nil
                        }
                    }
                }

                let effectiveUID: String = {
                    let storedUID = userUID.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !storedUID.isEmpty { return storedUID }
                    #if canImport(FirebaseAuth)
                    if let authUID = Auth.auth().currentUser?.uid, !authUID.isEmpty {
                        return authUID
                    }
                    #endif
                    return ""
                }()

                if !effectiveUID.isEmpty {
                    FirebaseManager.shared.uploadProfileImage(
                        image,
                        forUserUID: effectiveUID
                    ) { result in
                        switch result {
                        case .success:
                            completion(result)
                        case .failure:
                            // Fallback to legacy email-based path for older accounts.
                            if !userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                FirebaseManager.shared.uploadProfileImage(
                                    image,
                                    forUserEmail: userEmail,
                                    completion: completion
                                )
                            } else {
                                completion(result)
                            }
                        }
                    }
                } else {
                    FirebaseManager.shared.uploadProfileImage(
                        image,
                        forUserEmail: userEmail,
                        completion: completion
                    )
                }
                #else
                await MainActor.run {
                    isUploadingPhoto = false
                    profilePhotoItem = nil
                }
                #endif
            }
        }

        var body: some View {
            settingsNavigationView
        }

        private var settingsNavigationView: some View {
            NavigationView {
                settingsDecoratedList
            }
        }

        private var settingsDecoratedList: some View {
            settingsList
                .confirmationDialog(
                    "Sign Out",
                    isPresented: $showSignOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Sign Out", role: .destructive) {
                        performSignOut()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to sign out?")
                }
                .confirmationDialog(
                    "Delete Account",
                    isPresented: $showDeleteAccountConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Continue to Delete", role: .destructive) {
                        showDeleteAccountFinalConfirmation = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete your account and all your data. This action cannot be undone.")
                }
                .confirmationDialog(
                    "Are You Sure?",
                    isPresented: $showDeleteAccountFinalConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete My Account Permanently", role: .destructive) {
                        Task { await performDeleteAccount() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your account and all associated data will be permanently deleted and cannot be recovered.")
                }
                .alert("Account Deletion Failed", isPresented: $showDeleteAccountError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deleteAccountError ?? "An unexpected error occurred. Please try again.")
                }
                .sheet(isPresented: $showSubscriptionView) {
                    SubscriptionPurchaseView()
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

                    loadWidgetConfiguration()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            saveWidgetConfiguration()
                            onSave()
                            isPresented = false
                        }
                    }
                }
        }

        private var settingsList: some View {
            List {
                userProfileSection

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Use Sign Out to leave the app on this device, or Delete Account to permanently remove your account and data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    Text("NeighbourHUB Watch Camera Login Details")
                } footer: {
                    Text("Enter your watch credentials to request camera access. An admin will approve your request.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // App Permissions
                Section("App Permissions") {
                    if isCommitteeMember {
                        Toggle(
                            "Allow everyone to create polls", isOn: $allowEveryoneToCreatePolls
                        )
                        .toggleStyle(SwitchToggleStyle())
                    }

                    Toggle(
                        "Allow Push Notifications",
                        isOn: $allowPushNotifications
                    )
                    .toggleStyle(SwitchToggleStyle())
                    .padding(.vertical, 4)
                    .onChange(of: allowPushNotifications) { _, enabled in
                        if enabled {
                            // Re-request permission and register for remote notifications
                            UNUserNotificationCenter.current().requestAuthorization(
                                options: [.alert, .sound, .badge]
                            ) { granted, _ in
                                guard granted else { return }
                                DispatchQueue.main.async {
                                    #if targetEnvironment(simulator)
                                    print("ℹ️ Skipping APNs registration on simulator (APNs requires a physical device)")
                                    #else
                                    UIApplication.shared.registerForRemoteNotifications()
                                    #endif
                                }
                            }
                        }
                    }

                    if isCommitteeMember {
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

            }
        }

        private func moveSection(from source: IndexSet, to destination: Int) {
            homeSectionOrder.move(fromOffsets: source, toOffset: destination)
        }

        private func loadWidgetConfiguration() {
            let appGroupID = "group.com.ml5ar66rq7.neighborhubwf3"
            let sharedDefaults = UserDefaults(suiteName: appGroupID) ?? .standard
            syncWidgetReporterDetailsToSharedDefaults(sharedDefaults)
            let legacyEndpoint = "https://neighborhub.app/api/emergency/widget-send"
            let defaultEndpoint = "https://us-central1-neighborhub-cd47d.cloudfunctions.net/widgetEmergencySend"

            let storedEndpoint = sharedDefaults.string(forKey: "emergencyWidgetEndpoint") ?? ""
            if storedEndpoint == legacyEndpoint {
                emergencyWidgetEndpoint = defaultEndpoint
                sharedDefaults.set(defaultEndpoint, forKey: "emergencyWidgetEndpoint")
            } else {
                emergencyWidgetEndpoint = storedEndpoint
            }
            widgetAuthToken = sharedDefaults.string(forKey: "widgetAuthToken") ?? ""
            widgetConfigStatusMessage = nil
        }

        private func saveWidgetConfiguration() {
            let appGroupID = "group.com.ml5ar66rq7.neighborhubwf3"
            let sharedDefaults = UserDefaults(suiteName: appGroupID) ?? .standard
            syncWidgetReporterDetailsToSharedDefaults(sharedDefaults)

            let endpoint = emergencyWidgetEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = widgetAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)

            if endpoint.isEmpty {
                sharedDefaults.removeObject(forKey: "emergencyWidgetEndpoint")
            } else {
                sharedDefaults.set(endpoint, forKey: "emergencyWidgetEndpoint")
            }

            if token.isEmpty {
                sharedDefaults.removeObject(forKey: "widgetAuthToken")
            } else {
                sharedDefaults.set(token, forKey: "widgetAuthToken")
            }

            widgetConfigStatusMessage = "Widget configuration saved."

            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "EmergencyActionWidget")
            #endif
        }

        private func syncWidgetReporterDetailsToSharedDefaults(_ sharedDefaults: UserDefaults) {
            let values: [String: String] = [
                "userUID": userUID.trimmingCharacters(in: .whitespacesAndNewlines),
                "userName": userName.trimmingCharacters(in: .whitespacesAndNewlines),
                "userSurname": userSurname.trimmingCharacters(in: .whitespacesAndNewlines),
                "userCell": userCell.trimmingCharacters(in: .whitespacesAndNewlines),
                "userStreet": userStreet.trimmingCharacters(in: .whitespacesAndNewlines),
                "userSuburb": userSuburb.trimmingCharacters(in: .whitespacesAndNewlines),
                "userCity": userCity.trimmingCharacters(in: .whitespacesAndNewlines),
                "userPostalCode": userPostalCode.trimmingCharacters(in: .whitespacesAndNewlines),
                "userNeighborhood": userNeighborhood.trimmingCharacters(in: .whitespacesAndNewlines)
            ]

            for (key, value) in values {
                if value.isEmpty {
                    sharedDefaults.removeObject(forKey: key)
                } else {
                    sharedDefaults.set(value, forKey: key)
                }
            }
        }
        
        private func performSignOut() {
            #if canImport(FirebaseAuth)
            do {
                try Auth.auth().signOut()
                clearLocalAccountState()
                isPresented = false
                print("✅ User signed out successfully")
            } catch {
                print("❌ Error signing out: \(error.localizedDescription)")
            }
            #endif
        }

        @MainActor
        private func performDeleteAccount() async {
            #if canImport(FirebaseAuth)
            guard let user = Auth.auth().currentUser else {
                deleteAccountError = "No authenticated user found. Please sign in again and try."
                showDeleteAccountError = true
                return
            }
            let uid = user.uid
            isDeletingAccount = true

            do {
                // 1. Delete Firestore user document
                let db = Firestore.firestore()
                try await db.collection("users").document(uid).delete()

                // 2. Delete Firebase Auth account
                try await user.delete()

                // 3. Clear local state and push identity
                clearLocalAccountState()

                isDeletingAccount = false
                isPresented = false
                print("✅ Account deleted successfully for uid: \(uid)")
            } catch {
                isDeletingAccount = false
                deleteAccountError = error.localizedDescription
                showDeleteAccountError = true
                print("❌ Error deleting account: \(error.localizedDescription)")
            }
            #endif
        }

        private func clearLocalAccountState() {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "userUID")
            defaults.removeObject(forKey: "userName")
            defaults.removeObject(forKey: "userSurname")
            defaults.removeObject(forKey: "userEmail")
            defaults.removeObject(forKey: "userIsVerified")
            defaults.removeObject(forKey: "userIsAdmin")
            defaults.removeObject(forKey: "userIsCommittee")
            defaults.removeObject(forKey: "userHasCameraAccess")
            defaults.removeObject(forKey: "watchUsername")
            defaults.removeObject(forKey: "watchPassword")
            defaults.removeObject(forKey: "profileImageURL")
            defaults.removeObject(forKey: "oneSignalSubscriptionId")

            #if canImport(OneSignalFramework)
            OneSignalManager.shared.logout()
            #endif
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
                                        let _ = UserDefaults.standard.string(forKey: "userName") ?? "User"
                                        var message = "Hi, I found your business *\\(contact.businessName)* on NeighborHub.%0A%0A"
                                        message += "I'm interested in learning more about your services.%0A%0A"
                                        message += "Best regards,%0A"
                                        
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
        let weatherService: WeatherKitService
        let initialHelpType: HelpType?
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

        private var aiDraftHelpMessage: String {
            let helpTypeName = selectedHelpType?.rawValue.lowercased() ?? "help"
            let locationText = (useDeviceLocation ? detailedCurrentLocation : manualLocationInput)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedLocation = locationText.isEmpty || locationText == "Fetching location..."
                ? "my location"
                : locationText

            switch helpTypeName {
            case "fire":
                return "Fire reported at \(resolvedLocation). Smoke or flames may be present. Please dispatch assistance urgently."
            case "medical":
                return "Medical assistance needed at \(resolvedLocation). Please respond as soon as possible."
            default:
                return "I need urgent help at \(resolvedLocation). Please check in as soon as you can."
            }
        }
        
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

                                    Button(action: {
                                        helpMessage = aiDraftHelpMessage
                                        AnalyticsService.shared.trackAIAssistantAction(
                                            action: "Draft Help Message",
                                            source: "request_help_sheet",
                                            accepted: true
                                        )
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "sparkles")
                                            Text("Draft with AI")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.purple.opacity(0.1))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
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
                if selectedHelpType == nil, let initialHelpType {
                    selectedHelpType = initialHelpType
                    isChoiceSectionMinimized = true
                    showingFireDetails = (initialHelpType == .fire)
                }

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
            let _ = UserDefaults.standard.string(forKey: "userName") ?? "User"
            let _ = UserDefaults.standard.string(forKey: "userSurname") ?? ""
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
    static let showWellnessCheckinPrompt = Notification.Name("showWellnessCheckinPrompt")
    static let showWellnessHelpRequest = Notification.Name("showWellnessHelpRequest")
}

struct WellnessHelpRequestDetails: Identifiable {
    let id = UUID()
    let uid: String
    let displayName: String
    let address: String?
    let phone: String?
    let emergencyContactName: String?
    let emergencyContactPhone: String?
    let visibility: String?

    init(uid: String,
         displayName: String,
         address: String? = nil,
         phone: String? = nil,
         emergencyContactName: String? = nil,
         emergencyContactPhone: String? = nil,
         visibility: String? = nil)
    {
        self.uid = uid
        self.displayName = displayName
        self.address = address
        self.phone = phone
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.visibility = visibility
    }

    init?(from userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo else { return nil }
        guard let uid = extractString(from: userInfo, matching: ["uid", "user_id", "userId", "senderUid"]) else { return nil }
        let displayName = extractString(from: userInfo, matching: ["displayName", "senderName", "name", "fullName", "userName"]) ?? "Unknown User"
        let address = extractString(from: userInfo, matching: ["address", "location", "userAddress"])
        let phone = extractString(from: userInfo, matching: ["phone", "phoneNumber", "userPhone"])
        let emergencyContactName = extractString(from: userInfo, matching: ["emergencyContactName", "emergency_name", "emergencyName"])
        let emergencyContactPhone = extractString(from: userInfo, matching: ["emergencyContactPhone", "emergencyPhone"])
        let visibility = extractString(from: userInfo, matching: ["visibility", "wellnessVisibility"])
        self.init(uid: uid,
                  displayName: displayName,
                  address: address,
                  phone: phone,
                  emergencyContactName: emergencyContactName,
                  emergencyContactPhone: emergencyContactPhone,
                  visibility: visibility)
    }
}

struct WellnessHelpRequestSheet: View {
    let details: WellnessHelpRequestDetails
    @Environment(\.dismiss) private var dismiss

    private var contactTitle: String {
        details.displayName.isEmpty ? "Wellness Help Request" : details.displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.red.opacity(0.16))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Wellness Help Requested")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Tap to contact the person who requested help and their emergency contact.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Group {
                        Text(contactTitle)
                            .font(.headline)
                        if let phone = details.phone, !phone.isEmpty {
                            HStack(spacing: 16) {
                                Button(action: {
                                    if let url = telURL(for: phone) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Call requester", systemImage: "phone.fill")
                                }
                                .font(.subheadline)

                                Button(action: {
                                    if let url = whatsappURL(for: phone, text: "Hi, I saw your wellness help request.") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("WhatsApp", systemImage: "message.fill")
                                }
                                .font(.subheadline)
                            }
                            .foregroundColor(.accentColor)
                        }
                        if let address = details.address, !address.isEmpty {
                            Label(address, systemImage: "map.fill")
                                .font(.subheadline).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Emergency Contact")
                            .font(.subheadline).fontWeight(.semibold)

                        if let emergencyContactName = details.emergencyContactName,
                           !emergencyContactName.isEmpty {
                            Text(emergencyContactName)
                                .font(.body)
                        }

                        if let emergencyContactPhone = details.emergencyContactPhone,
                           !emergencyContactPhone.isEmpty {
                            HStack(spacing: 16) {
                                Button(action: {
                                    if let url = telURL(for: emergencyContactPhone) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Call emergency contact", systemImage: "phone.fill")
                                }
                                .font(.subheadline)

                                Button(action: {
                                    if let url = whatsappURL(for: emergencyContactPhone, text: "I can help. Are you okay?") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("WhatsApp", systemImage: "message.fill")
                                }
                                .font(.subheadline)
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    if let visibility = details.visibility, !visibility.isEmpty {
                        Divider()
                        Text("Visibility: \(visibility)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Help Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private func extractString(from any: Any, matching keys: [String]) -> String? {
    if let dict = any as? [AnyHashable: Any] {
        for (rawKey, rawValue) in dict {
            let key = String(describing: rawKey)
            let normalized = key
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if keys.contains(where: { normalized == $0.lowercased() }) {
                if let stringValue = rawValue as? String,
                   !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        for value in dict.values {
            if let found = extractString(from: value, matching: keys) {
                return found
            }
        }
    } else if let array = any as? [Any] {
        for value in array {
            if let found = extractString(from: value, matching: keys) {
                return found
            }
        }
    }
    return nil
}

private func telURL(for rawPhone: String) -> URL? {
    let trimmed = rawPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    // Keep plus sign if present, otherwise strip non-digits
    let hasPlus = trimmed.hasPrefix("+")
    let digits = trimmed.filter { $0.isNumber }
    if digits.isEmpty { return nil }
    let phonePart = hasPlus ? "+\(digits)" : digits
    return URL(string: "tel:\(phonePart)")
}

private func whatsappURL(for rawPhone: String, text: String? = nil) -> URL? {
    let trimmed = rawPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.filter { $0.isNumber }
    guard !digits.isEmpty else { return nil }
    let waNumber = digits // wa.me expects country code + number without +
    let encodedText = (text ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    if let app = URL(string: "whatsapp://send?phone=\(waNumber)&text=\(encodedText)"), UIApplication.shared.canOpenURL(app) {
        return app
    }
    return URL(string: "https://wa.me/\(waNumber)?text=\(encodedText)")
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
