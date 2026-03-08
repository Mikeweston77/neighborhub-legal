// MARK: - Local Event Model (shared for Home & Events)
enum EventType: String, CaseIterable, Identifiable, Codable {
    case event = "Event"
    case report = "Report Issue"
    case request = "Request Assistance"
    var id: String { self.rawValue }
}

struct LocalEvent: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var location: String?
    var date: Date
    var eventType: EventType
    var thumbsUp: Int = 0
    var heart: Int = 0
    var party: Int = 0
    var comments: [EventComment] = []
    var imageData: Data? = nil
    var fileURL: URL? = nil
    // Event creator tracking
    var creatorName: String?
    var creatorSurname: String?
    var creatorUID: String? // Firebase Auth UID
    // Contact details
    var contactName: String?
    var contactCell: String?
    // Optional structured metadata for events (e.g., buildingType, peopleAtRisk, visibleFlamesOrSmoke)
    var metadata: [String: String]? = nil
    // Messages/chat for incident reports
    var messages: [IncidentMessage] = []
    // Admin status tracking
    var isResolved: Bool = false
    var resolvedAt: Date?
    var resolvedBy: String? // Admin UID who marked as resolved
}

struct IncidentMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderUID: String // Firebase Auth UID
    let senderName: String
    let message: String
    let timestamp: Date
    let isAdmin: Bool
    
    init(id: UUID = UUID(), senderUID: String, senderName: String, message: String, timestamp: Date = Date(), isAdmin: Bool = false) {
        self.id = id
        self.senderUID = senderUID
        self.senderName = senderName
        self.message = message
        self.timestamp = timestamp
        self.isAdmin = isAdmin
    }
}

// MARK: - Category Contact Model (for Report It department contacts)
struct CategoryContact: Identifiable, Codable, Equatable {
    let id: String // category name (e.g., "Electricity", "Water", etc.)
    var name: String // Department/Organization name
    var number: String // Contact phone number
    var updatedAt: Date
    var updatedBy: String // UID of user who last updated
    
    init(id: String, name: String, number: String, updatedAt: Date = Date(), updatedBy: String = "") {
        self.id = id
        self.name = name
        self.number = number
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

struct EventComment: Identifiable, Codable, Equatable {
    let id: UUID
    let author: String
    let content: String
    let timestamp: Date
}

// MARK: - Newsletter Models
enum BusinessSubcategory: String, CaseIterable, Identifiable, Codable {
    case restaurant = "Restaurant & Dining"
    case cafe = "Cafe & Coffee Shop"
    case retail = "Retail & Shopping"
    case grocery = "Grocery & Food Store"
    case services = "Services & Professionals"
    case health = "Health & Wellness"
    case fitness = "Fitness & Gym"
    case beauty = "Beauty & Salon"
    case education = "Education & Training"
    case entertainment = "Entertainment & Recreation"
    case automotive = "Automotive"
    case homeImprovement = "Home Improvement"
    case petServices = "Pet Services"
    case realEstate = "Real Estate"
    case financial = "Financial Services"
    case technology = "Technology & IT"
    case legal = "Legal Services"
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .retail: return "cart.fill"
        case .grocery: return "basket.fill"
        case .services: return "briefcase.fill"
        case .health: return "heart.text.square.fill"
        case .fitness: return "figure.run"
        case .beauty: return "comb.fill"
        case .education: return "book.fill"
        case .entertainment: return "ticket.fill"
        case .automotive: return "car.fill"
        case .homeImprovement: return "hammer.fill"
        case .petServices: return "pawprint.fill"
        case .realEstate: return "house.fill"
        case .financial: return "dollarsign.circle.fill"
        case .technology: return "desktopcomputer"
        case .legal: return "scale.3d"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum AdvertSubcategory: String, CaseIterable, Identifiable, Codable {
    case forSale = "For Sale"
    case wanted = "Wanted"
    case services = "Services Offered"
    case jobOpportunity = "Job Opportunity"
    case rental = "Rental"
    case free = "Free Items"
    case swap = "Swap/Trade"
    case lostFound = "Lost & Found"
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .forSale: return "tag.fill"
        case .wanted: return "magnifyingglass"
        case .services: return "wrench.and.screwdriver.fill"
        case .jobOpportunity: return "briefcase.fill"
        case .rental: return "house.fill"
        case .free: return "gift.fill"
        case .swap: return "arrow.left.arrow.right"
        case .lostFound: return "questionmark.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum NewsletterCategory: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case safety = "Safety & Security"
    case events = "Community Events"
    case maintenance = "Property & Maintenance"
    case social = "Social News"
    case business = "Local Business"
    case localAdverts = "Local Adverts"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "doc.text.fill"
        case .safety: return "shield.fill"
        case .events: return "calendar.circle.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .social: return "person.2.fill"
        case .business: return "building.2.fill"
        case .localAdverts: return "megaphone.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .general: return .blue
        case .safety: return .red
        case .events: return .green
        case .maintenance: return .orange
        case .social: return .purple
        case .business: return .cyan
        case .localAdverts: return .pink
        }
    }
}

struct Newsletter: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var content: String
    var date: Date
    var author: String
    var authorEmail: String
    var category: NewsletterCategory
    var businessSubcategory: BusinessSubcategory? = nil
    var advertSubcategory: AdvertSubcategory? = nil
    var isPinned: Bool = false
    var readCount: Int = 0
    var tags: [String] = []
    var isPublished: Bool = true
    var requiresApproval: Bool = false
    // Attachments
    var imageData: Data? = nil
    var fileURL: URL? = nil
    var fileData: Data? = nil  // File data stored directly in Firestore
    var fileName: String? = nil  // Original filename
    // Fillable form fields (optional)
    var formFields: [NewsletterFormField] = []
    var isFormEnabled: Bool = false
    var allowPublicSubmissionView: Bool = false // Allow all users to view submissions

    // Custom Codable for fileURL and fileData
    enum CodingKeys: String, CodingKey {
        case id, title, summary, content, date, author, authorEmail, category, businessSubcategory, advertSubcategory, isPinned, readCount, tags, isPublished, requiresApproval, imageData, fileURL, fileData, fileName, formFields, isFormEnabled, allowPublicSubmissionView
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        content = try container.decode(String.self, forKey: .content)
        date = try container.decode(Date.self, forKey: .date)
        author = try container.decode(String.self, forKey: .author)
        authorEmail = try container.decode(String.self, forKey: .authorEmail)
        category = try container.decode(NewsletterCategory.self, forKey: .category)
        businessSubcategory = try container.decodeIfPresent(BusinessSubcategory.self, forKey: .businessSubcategory)
        advertSubcategory = try container.decodeIfPresent(AdvertSubcategory.self, forKey: .advertSubcategory)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        readCount = try container.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPublished = try container.decodeIfPresent(Bool.self, forKey: .isPublished) ?? true
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        if let fileURLString = try container.decodeIfPresent(String.self, forKey: .fileURL) {
            fileURL = URL(string: fileURLString)
        } else {
            fileURL = nil
        }
        fileData = try container.decodeIfPresent(Data.self, forKey: .fileData)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        formFields = try container.decodeIfPresent([NewsletterFormField].self, forKey: .formFields) ?? []
        isFormEnabled = try container.decodeIfPresent(Bool.self, forKey: .isFormEnabled) ?? false
        allowPublicSubmissionView = try container.decodeIfPresent(Bool.self, forKey: .allowPublicSubmissionView) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(content, forKey: .content)
        try container.encode(date, forKey: .date)
        try container.encode(author, forKey: .author)
        try container.encode(authorEmail, forKey: .authorEmail)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(businessSubcategory, forKey: .businessSubcategory)
        try container.encodeIfPresent(advertSubcategory, forKey: .advertSubcategory)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(readCount, forKey: .readCount)
        try container.encode(tags, forKey: .tags)
        try container.encode(isPublished, forKey: .isPublished)
        try container.encode(requiresApproval, forKey: .requiresApproval)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(fileURL?.absoluteString, forKey: .fileURL)
        try container.encodeIfPresent(fileData, forKey: .fileData)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(formFields, forKey: .formFields)
        try container.encode(isFormEnabled, forKey: .isFormEnabled)
        try container.encode(allowPublicSubmissionView, forKey: .allowPublicSubmissionView)
    }
    
    init(id: UUID = UUID(), title: String, summary: String, content: String = "", 
         author: String, authorEmail: String, category: NewsletterCategory = .general) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.date = Date()
        self.author = author
        self.authorEmail = authorEmail
        self.category = category
    }
}
import Foundation
import SwiftUI

// MARK: - Community Post Model
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

// MARK: - Newsletter Form Models
enum NewsletterFormFieldType: String, Codable, CaseIterable {
    case shortText = "Short Text"
    case longText = "Long Text"
    case multipleChoice = "Multiple Choice"
    case date = "Date"
    case email = "Email"
    case phone = "Phone"
    case number = "Number"
    
    var icon: String {
        switch self {
        case .shortText: return "textformat"
        case .longText: return "text.alignleft"
        case .multipleChoice: return "list.bullet.circle"
        case .date: return "calendar"
        case .email: return "envelope"
        case .phone: return "phone"
        case .number: return "number"
        }
    }
}

struct NewsletterFormField: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var fieldType: NewsletterFormFieldType
    var isRequired: Bool
    var placeholder: String
    var options: [String] // For multiple choice
    var helpText: String
    
    init(id: UUID = UUID(), label: String, fieldType: NewsletterFormFieldType, 
         isRequired: Bool = false, placeholder: String = "", 
         options: [String] = [], helpText: String = "") {
        self.id = id
        self.label = label
        self.fieldType = fieldType
        self.isRequired = isRequired
        self.placeholder = placeholder
        self.options = options
        self.helpText = helpText
    }
}

struct NewsletterFormSubmission: Identifiable, Codable {
    let id: UUID
    let newsletterId: UUID
    let submitterId: String // Firebase Auth UID
    let submitterName: String
    let submitterEmail: String // Keep for display purposes
    var submissionDate: Date
    var responses: [UUID: String] // fieldId -> response
    var status: SubmissionStatus
    var allowPublicSubmissionView: Bool = false // For security rules
    
    enum SubmissionStatus: String, Codable {
        case pending = "Pending Review"
        case approved = "Approved"
        case rejected = "Rejected"
    }
    
    init(id: UUID = UUID(), newsletterId: UUID, submitterId: String, submitterName: String, 
         submitterEmail: String, responses: [UUID: String], allowPublicSubmissionView: Bool = false) {
        self.id = id
        self.newsletterId = newsletterId
        self.submitterId = submitterId
        self.submitterName = submitterName
        self.submitterEmail = submitterEmail
        self.submissionDate = Date()
        self.responses = responses
        self.status = .pending
        self.allowPublicSubmissionView = allowPublicSubmissionView
    }
}

// MARK: - Quick Action Model
enum QuickAction: String, CaseIterable {
    case reportIssue = "Report Issue"
    case requestHelp = "Request Help"
    case shareUpdate = "Share Update"
    case emergencyCall = "Emergency Call"
    case checkSafety = "Check Safety"
    case findNeighbors = "Find Neighbors"
    
    var icon: String {
        switch self {
        case .reportIssue: return "exclamationmark.triangle.fill"
        case .requestHelp: return "hand.raised.fill"
        case .shareUpdate: return "square.and.pencil"
        case .emergencyCall: return "phone.fill"
        case .checkSafety: return "shield.fill"
        case .findNeighbors: return "person.3.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .reportIssue: return .orange
        case .requestHelp: return .blue
        case .shareUpdate: return .green
        case .emergencyCall: return .red
        case .checkSafety: return .purple
        case .findNeighbors: return .teal
        }
    }
}

// MARK: - Emergency Alert Model
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

// MARK: - Community Emergency Contacts

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
    let createdBy: String // Firebase Auth UID of admin/committee member who created this
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
            case .neighborhood: return "cyan"
            }
        }
    }
    
    enum ContactPriority: String, CaseIterable, Codable {
        case critical = "critical"      // Life-threatening emergencies
        case high = "high"             // Urgent but not life-threatening
        case normal = "normal"         // Standard community services
        case low = "low"              // Non-urgent convenience services
        
        var displayName: String {
            switch self {
            case .critical: return "Critical"
            case .high: return "High Priority"
            case .normal: return "Normal"
            case .low: return "Low Priority"
            }
        }
        
        var color: String {
            switch self {
            case .critical: return "red"
            case .high: return "orange"
            case .normal: return "blue"
            case .low: return "gray"
            }
        }
    }
    
    // Default emergency contacts for South African neighborhoods
    static let defaultContacts: [CommunityEmergencyContact] = [
        CommunityEmergencyContact(
            id: "default-police",
            name: "South African Police Service",
            phoneNumber: "10111",
            email: nil,
            organization: "SAPS",
            category: .emergency,
            priority: .critical,
            availability: "24/7",
            notes: "General police emergency number",
            createdBy: "system",
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        ),
        CommunityEmergencyContact(
            id: "default-fire",
            name: "Fire & Rescue Services",
            phoneNumber: "10177",
            email: nil,
            organization: "Municipal Fire Services",
            category: .emergency,
            priority: .critical,
            availability: "24/7",
            notes: "Fire emergencies and rescue operations",
            createdBy: "system",
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        ),
        CommunityEmergencyContact(
            id: "default-ambulance",
            name: "Emergency Medical Services",
            phoneNumber: "10177",
            email: nil,
            organization: "EMS",
            category: .medical,
            priority: .critical,
            availability: "24/7",
            notes: "Medical emergencies and ambulance services",
            createdBy: "system",
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        ),
        CommunityEmergencyContact(
            id: "default-municipal",
            name: "Municipal Services",
            phoneNumber: "0800 111 300",
            email: "services@municipality.gov.za",
            organization: "Local Municipality",
            category: .government,
            priority: .normal,
            availability: "Office hours",
            notes: "Water, electricity, and municipal service issues",
            createdBy: "system",
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        )
    ]
    
    init(id: String = UUID().uuidString, name: String, phoneNumber: String, email: String? = nil, organization: String? = nil, category: ContactCategory, priority: ContactPriority, availability: String? = nil, notes: String? = nil, createdBy: String, createdAt: Date = Date(), updatedAt: Date = Date(), isActive: Bool = true) {
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
}

// MARK: - Community Emergency Contact Manager

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif

/// Manager for community-wide emergency contacts that admins/committee members can edit
class CommunityEmergencyContactManager: ObservableObject {
    @Published var contacts: [CommunityEmergencyContact] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let userDefaults = UserDefaults.standard
    private let contactsKey = "communityEmergencyContactsData"
    
    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    #endif
    
    init() {
        loadContactsFromDefaults()
        loadDefaultContactsIfNeeded()
        loadContactsFromFirebase()
    }
    
    deinit {
        #if canImport(FirebaseFirestore)
        listener?.remove()
        #endif
    }
    
    // MARK: - Local Persistence
    
    private func saveContactsToDefaults() {
        do {
            let data = try JSONEncoder().encode(contacts)
            userDefaults.set(data, forKey: contactsKey)
        } catch {
            errorMessage = "Failed to save contacts locally: \(error.localizedDescription)"
        }
    }
    
    private func loadContactsFromDefaults() {
        guard let data = userDefaults.data(forKey: contactsKey),
              let decodedContacts = try? JSONDecoder().decode([CommunityEmergencyContact].self, from: data) else {
            return
        }
        
        contacts = decodedContacts.sorted { contact1, contact2 in
            let priority1 = priorityOrder(contact1.priority)
            let priority2 = priorityOrder(contact2.priority)
            
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return contact1.name < contact2.name
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
    
    private func loadDefaultContactsIfNeeded() {
        if contacts.isEmpty {
            contacts = CommunityEmergencyContact.defaultContacts
            saveContactsToDefaults()
        }
    }
    
    // MARK: - Firebase Integration
    
    func loadContactsFromFirebase() {
        #if canImport(FirebaseFirestore)
        isLoading = true
        
        listener = db.collection("emergencyContacts")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = "Failed to load contacts: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else { return }
                    
                    var firebaseContacts: [CommunityEmergencyContact] = []
                    
                    for document in documents {
                        do {
                            let data = document.data()
                            
                            // Parse dates safely
                            let createdAt: Date
                            let updatedAt: Date
                            
                            if let createdTimestamp = data["createdAt"] as? Timestamp {
                                createdAt = createdTimestamp.dateValue()
                            } else {
                                createdAt = Date()
                            }
                            
                            if let updatedTimestamp = data["updatedAt"] as? Timestamp {
                                updatedAt = updatedTimestamp.dateValue()
                            } else {
                                updatedAt = Date()
                            }
                            
                            let contact = CommunityEmergencyContact(
                                id: document.documentID,
                                name: data["name"] as? String ?? "",
                                phoneNumber: data["phoneNumber"] as? String ?? "",
                                email: data["email"] as? String,
                                organization: data["organization"] as? String,
                                category: CommunityEmergencyContact.ContactCategory(rawValue: data["category"] as? String ?? "emergency") ?? .emergency,
                                priority: CommunityEmergencyContact.ContactPriority(rawValue: data["priority"] as? String ?? "normal") ?? .normal,
                                availability: data["availability"] as? String,
                                notes: data["notes"] as? String,
                                createdBy: data["createdBy"] as? String ?? "unknown",
                                createdAt: createdAt,
                                updatedAt: updatedAt,
                                isActive: data["isActive"] as? Bool ?? true
                            )
                            
                            firebaseContacts.append(contact)
                        } catch {
                            print("Error parsing contact from Firebase: \(error)")
                        }
                    }
                    
                    // Merge with default contacts
                    let allContacts = firebaseContacts + CommunityEmergencyContact.defaultContacts
                    
                    // Remove duplicates (Firebase contacts take precedence)
                    var uniqueContacts: [CommunityEmergencyContact] = []
                    var seenIds: Set<String> = []
                    
                    for contact in allContacts {
                        if !seenIds.contains(contact.id) {
                            uniqueContacts.append(contact)
                            seenIds.insert(contact.id)
                        }
                    }
                    
                    self?.contacts = uniqueContacts.sorted { contact1, contact2 in
                        let priority1 = self?.priorityOrder(contact1.priority) ?? 99
                        let priority2 = self?.priorityOrder(contact2.priority) ?? 99
                        
                        if priority1 != priority2 {
                            return priority1 < priority2
                        }
                        return contact1.name < contact2.name
                    }
                    
                    self?.saveContactsToDefaults()
                    
                    // Notify UI of updates
                    NotificationCenter.default.post(name: .emergencyContactsUpdated, object: self?.contacts)
                }
            }
        #endif
    }
    
    func saveContactToFirebase(_ contact: CommunityEmergencyContact) {
        #if canImport(FirebaseFirestore)
        let contactData: [String: Any] = [
            "name": contact.name,
            "phoneNumber": contact.phoneNumber,
            "email": contact.email as Any,
            "organization": contact.organization as Any,
            "category": contact.category.rawValue,
            "priority": contact.priority.rawValue,
            "availability": contact.availability as Any,
            "notes": contact.notes as Any,
            "createdBy": contact.createdBy,
            "createdAt": Timestamp(date: contact.createdAt),
            "updatedAt": Timestamp(date: Date()),
            "isActive": contact.isActive
        ]
        
        db.collection("emergencyContacts").document(contact.id).setData(contactData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to save contact: \(error.localizedDescription)"
                } else {
                    print("Contact saved to Firebase successfully")
                }
            }
        }
        #endif
    }
    
    func deleteContactFromFirebase(_ contact: CommunityEmergencyContact) {
        #if canImport(FirebaseFirestore)
        db.collection("emergencyContacts").document(contact.id).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to delete contact: \(error.localizedDescription)"
                } else {
                    print("Contact deleted from Firebase successfully")
                }
            }
        }
        #endif
    }
    
    // MARK: - Contact Management
    
    func addContact(name: String, phoneNumber: String, email: String? = nil, organization: String? = nil, category: CommunityEmergencyContact.ContactCategory, priority: CommunityEmergencyContact.ContactPriority, availability: String? = nil, notes: String? = nil, createdBy: String) {
        
        let newContact = CommunityEmergencyContact(
            name: name,
            phoneNumber: phoneNumber,
            email: email,
            organization: organization,
            category: category,
            priority: priority,
            availability: availability,
            notes: notes,
            createdBy: createdBy
        )
        
        contacts.append(newContact)
        contacts.sort { contact1, contact2 in
            let priority1 = priorityOrder(contact1.priority)
            let priority2 = priorityOrder(contact2.priority)
            
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return contact1.name < contact2.name
        }
        
        saveContactsToDefaults()
        saveContactToFirebase(newContact)
        
        // Notify UI of updates
        NotificationCenter.default.post(name: .emergencyContactsUpdated, object: contacts)
    }
    
    func updateContact(_ contact: CommunityEmergencyContact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        
        let updatedContact = CommunityEmergencyContact(
            id: contact.id,
            name: contact.name,
            phoneNumber: contact.phoneNumber,
            email: contact.email,
            organization: contact.organization,
            category: contact.category,
            priority: contact.priority,
            availability: contact.availability,
            notes: contact.notes,
            createdBy: contact.createdBy,
            createdAt: contact.createdAt,
            updatedAt: Date(),
            isActive: contact.isActive
        )
        
        contacts[index] = updatedContact
        contacts.sort { contact1, contact2 in
            let priority1 = priorityOrder(contact1.priority)
            let priority2 = priorityOrder(contact2.priority)
            
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return contact1.name < contact2.name
        }
        
        saveContactsToDefaults()
        saveContactToFirebase(updatedContact)
        
        // Notify UI of updates
        NotificationCenter.default.post(name: .emergencyContactsUpdated, object: contacts)
    }
    
    func deleteContact(_ contact: CommunityEmergencyContact) {
        // For default contacts, mark as inactive instead of deleting
        if contact.createdBy == "system" {
            let inactiveContact = CommunityEmergencyContact(
                id: contact.id,
                name: contact.name,
                phoneNumber: contact.phoneNumber,
                email: contact.email,
                organization: contact.organization,
                category: contact.category,
                priority: contact.priority,
                availability: contact.availability,
                notes: contact.notes,
                createdBy: contact.createdBy,
                createdAt: contact.createdAt,
                updatedAt: Date(),
                isActive: false
            )
            
            updateContact(inactiveContact)
            return
        }
        
        contacts.removeAll { $0.id == contact.id }
        saveContactsToDefaults()
        deleteContactFromFirebase(contact)
        
        // Notify UI of updates
        NotificationCenter.default.post(name: .emergencyContactsUpdated, object: contacts)
    }
    
    // MARK: - Contact Actions
    
    func callContact(_ contact: CommunityEmergencyContact) {
        guard let url = URL(string: "tel:\(contact.phoneNumber)") else {
            errorMessage = "Invalid phone number: \(contact.phoneNumber)"
            return
        }
        
        #if canImport(UIKit)
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            errorMessage = "Unable to make phone calls on this device"
        }
        #else
        errorMessage = "Phone calls not supported on this platform"
        #endif
    }
    
    func messageContact(_ contact: CommunityEmergencyContact) {
        // WhatsApp support with South African number formatting
        var waNumber = contact.phoneNumber.filter { $0.isNumber }
        if waNumber.hasPrefix("0") && waNumber.count == 10 {
            waNumber = "27" + waNumber.dropFirst()
        }
        
        #if canImport(UIKit)
        if let url = URL(string: "https://wa.me/\(waNumber)") {
            UIApplication.shared.open(url)
        }
        #endif
    }
    
    func copyContactNumber(_ contact: CommunityEmergencyContact) {
        #if canImport(UIKit)
        UIPasteboard.general.string = contact.phoneNumber
        #endif
    }
    
    // MARK: - Utility Methods
    
    func contacts(for category: CommunityEmergencyContact.ContactCategory) -> [CommunityEmergencyContact] {
        return contacts.filter { $0.category == category && $0.isActive }
    }
    
    func criticalContacts() -> [CommunityEmergencyContact] {
        return contacts.filter { $0.priority == .critical && $0.isActive }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let emergencyContactsUpdated = Notification.Name("emergencyContactsUpdated")
}
