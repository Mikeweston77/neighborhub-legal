import Foundation
import CoreData

// MARK: - User Entity
@objc(User)
public class User: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var email: String?
    @NSManaged public var address: String?
    @NSManaged public var profileImageURL: String?
    @NSManaged public var isVerified: Bool
    @NSManaged public var reputationScore: Double
    @NSManaged public var joinedDate: Date?
    @NSManaged public var lastActive: Date?
    @NSManaged public var privacySettings: String? // JSON string
    @NSManaged public var emergencyContact: String?
    @NSManaged public var skillsOffered: String? // JSON array
    @NSManaged public var interests: String? // JSON array
    
    // Relationships
    @NSManaged public var posts: NSSet?
    @NSManaged public var events: NSSet?
    @NSManaged public var listings: NSSet?
    @NSManaged public var emergencyContacts: NSSet?
    @NSManaged public var patrolSchedules: NSSet?
    @NSManaged public var eventAttendances: NSSet?
    @NSManaged public var interestedListings: NSSet?
    @NSManaged public var reportedIncidents: NSSet?
    @NSManaged public var assignedIncidents: NSSet?
    @NSManaged public var volunteerSchedules: NSSet?
    @NSManaged public var ownedResources: NSSet?
    @NSManaged public var borrowedResources: NSSet?
    @NSManaged public var resourceReservations: NSSet?
    @NSManaged public var reportedIssues: NSSet?
    @NSManaged public var assignedIssues: NSSet?
    @NSManaged public var supportedIssues: NSSet?
    @NSManaged public var createdPetitions: NSSet?
    @NSManaged public var signedPetitions: NSSet?
    @NSManaged public var comments: NSSet?
}

// MARK: - Post Entity
@objc(Post)
public class Post: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var content: String?
    @NSManaged public var category: String?
    @NSManaged public var priority: String? // Low, Medium, High, Emergency
    @NSManaged public var createdDate: Date?
    @NSManaged public var updatedDate: Date?
    @NSManaged public var likes: Int32
    @NSManaged public var isAnonymous: Bool
    @NSManaged public var location: String? // JSON location data
    @NSManaged public var images: String? // JSON array of image URLs
    @NSManaged public var tags: String? // JSON array of tags
    @NSManaged public var expirationDate: Date?
    
    // Relationships
    @NSManaged public var author: User?
    @NSManaged public var comments: NSSet?
}

// MARK: - Event Entity
@objc(Event)
public class Event: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var eventDescription: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var location: String?
    @NSManaged public var category: String?
    @NSManaged public var maxAttendees: Int32
    @NSManaged public var currentAttendees: Int32
    @NSManaged public var isPublic: Bool
    @NSManaged public var requiresRSVP: Bool
    @NSManaged public var createdDate: Date?
    @NSManaged public var cost: Double
    @NSManaged public var images: String? // JSON array
    @NSManaged public var requirements: String? // JSON array
    
    // Relationships
    @NSManaged public var organizer: User?
    @NSManaged public var attendees: NSSet?
}

// MARK: - Marketplace Listing Entity
@objc(MarketplaceListing)
public class MarketplaceListing: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var itemDescription: String?
    @NSManaged public var price: Double
    @NSManaged public var category: String?
    @NSManaged public var condition: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var createdDate: Date?
    @NSManaged public var updatedDate: Date?
    @NSManaged public var images: String? // JSON array
    @NSManaged public var pickupLocation: String?
    @NSManaged public var deliveryAvailable: Bool
    @NSManaged public var sustainabilityScore: Double
    @NSManaged public var tags: String? // JSON array
    @NSManaged public var type: String? // sale, wanted, free, barter
    
    // Relationships
    @NSManaged public var seller: User?
    @NSManaged public var interestedBuyers: NSSet?
}

// MARK: - Security Incident Entity
@objc(SecurityIncident)
public class SecurityIncident: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var incidentDescription: String?
    @NSManaged public var severity: String? // Low, Medium, High, Critical
    @NSManaged public var location: String? // JSON location data
    @NSManaged public var reportedDate: Date?
    @NSManaged public var resolvedDate: Date?
    @NSManaged public var status: String? // Reported, Investigating, Resolved
    @NSManaged public var isAnonymous: Bool
    @NSManaged public var images: String? // JSON array
    @NSManaged public var evidenceFiles: String? // JSON array
    @NSManaged public var involvedParties: String? // JSON array
    
    // Relationships
    @NSManaged public var reporter: User?
    @NSManaged public var assignedOfficers: NSSet?
}

// MARK: - Patrol Schedule Entity
@objc(PatrolSchedule)
public class PatrolSchedule: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var scheduleName: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var route: String? // JSON route data
    @NSManaged public var maxVolunteers: Int32
    @NSManaged public var currentVolunteers: Int32
    @NSManaged public var isActive: Bool
    @NSManaged public var createdDate: Date?
    @NSManaged public var notes: String?
    @NSManaged public var requiredSkills: String? // JSON array
    
    // Relationships
    @NSManaged public var coordinator: User?
    @NSManaged public var volunteers: NSSet?
}

// MARK: - Resource Sharing Entity
@objc(SharedResource)
public class SharedResource: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var resourceDescription: String?
    @NSManaged public var category: String?
    @NSManaged public var isAvailable: Bool
    @NSManaged public var condition: String?
    @NSManaged public var value: Double
    @NSManaged public var maxBorrowDays: Int32
    @NSManaged public var depositRequired: Double
    @NSManaged public var createdDate: Date?
    @NSManaged public var images: String? // JSON array
    @NSManaged public var usageInstructions: String?
    @NSManaged public var maintenanceNotes: String?
    
    // Relationships
    @NSManaged public var owner: User?
    @NSManaged public var currentBorrower: User?
    @NSManaged public var reservations: NSSet?
}

// MARK: - Community Issue Entity
@objc(CommunityIssue)
public class CommunityIssue: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var issueDescription: String?
    @NSManaged public var category: String?
    @NSManaged public var priority: String?
    @NSManaged public var status: String? // Open, In Progress, Resolved, Closed
    @NSManaged public var location: String? // JSON location data
    @NSManaged public var reportedDate: Date?
    @NSManaged public var resolvedDate: Date?
    @NSManaged public var votes: Int32
    @NSManaged public var images: String? // JSON array
    @NSManaged public var updateHistory: String? // JSON array
    @NSManaged public var cityTicketNumber: String?
    
    // Relationships
    @NSManaged public var reporter: User?
    @NSManaged public var assignedTo: User?
    @NSManaged public var supporters: NSSet?
}

// MARK: - Petition Entity
@objc(Petition)
public class Petition: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var petitionDescription: String?
    @NSManaged public var targetSignatures: Int32
    @NSManaged public var currentSignatures: Int32
    @NSManaged public var createdDate: Date?
    @NSManaged public var deadline: Date?
    @NSManaged public var category: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var targetEntity: String? // City Council, HOA, etc.
    @NSManaged public var images: String? // JSON array
    @NSManaged public var updates: String? // JSON array
    
    // Relationships
    @NSManaged public var creator: User?
    @NSManaged public var signers: NSSet?
}

// MARK: - Comment Entity
@objc(Comment)
public class Comment: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var content: String?
    @NSManaged public var createdDate: Date?
    @NSManaged public var updatedDate: Date?
    @NSManaged public var likes: Int32
    @NSManaged public var isAnonymous: Bool
    @NSManaged public var parentCommentId: UUID?
    
    // Relationships
    @NSManaged public var author: User?
    @NSManaged public var post: Post?
}

// MARK: - Emergency Contact Entity
@objc(EmergencyContact)
public class EmergencyContact: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var phoneNumber: String?
    @NSManaged public var email: String?
    @NSManaged public var relationship: String?
    @NSManaged public var address: String?
    @NSManaged public var notes: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var priority: Int32
    
    // Relationships
    @NSManaged public var user: User?
}

// MARK: - Core Data Extensions
extension User {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<User> {
        return NSFetchRequest<User>(entityName: "User")
    }
    
    var skillsArray: [String] {
        guard let skillsString = skillsOffered,
              let data = skillsString.data(using: .utf8),
              let skills = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return skills
    }
    
    var interestsArray: [String] {
        guard let interestsString = interests,
              let data = interestsString.data(using: .utf8),
              let interests = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return interests
    }
}

extension Post {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Post> {
        return NSFetchRequest<Post>(entityName: "Post")
    }
    
    var imagesArray: [String] {
        guard let imagesString = images,
              let data = imagesString.data(using: .utf8),
              let images = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return images
    }
    
    var tagsArray: [String] {
        guard let tagsString = tags,
              let data = tagsString.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tags
    }
}

extension Event {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }
}

extension MarketplaceListing {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MarketplaceListing> {
        return NSFetchRequest<MarketplaceListing>(entityName: "MarketplaceListing")
    }
}

extension SecurityIncident {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SecurityIncident> {
        return NSFetchRequest<SecurityIncident>(entityName: "SecurityIncident")
    }
}

extension PatrolSchedule {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PatrolSchedule> {
        return NSFetchRequest<PatrolSchedule>(entityName: "PatrolSchedule")
    }
}

extension SharedResource {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedResource> {
        return NSFetchRequest<SharedResource>(entityName: "SharedResource")
    }
}

extension CommunityIssue {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CommunityIssue> {
        return NSFetchRequest<CommunityIssue>(entityName: "CommunityIssue")
    }
}

extension Petition {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Petition> {
        return NSFetchRequest<Petition>(entityName: "Petition")
    }
}

extension Comment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Comment> {
        return NSFetchRequest<Comment>(entityName: "Comment")
    }
}

extension EmergencyContact {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<EmergencyContact> {
        return NSFetchRequest<EmergencyContact>(entityName: "EmergencyContact")
    }
}
