import Foundation
import CoreLocation
import MapKit

// MARK: - Neighborhood Verification Manager
class NeighborhoodVerificationManager: ObservableObject {
    @Published var isVerified = false
    @Published var neighborhoodName = ""
    @Published var verificationStatus = ""
    
    func verifyAddress(_ address: String, completion: @escaping (Bool) -> Void) {
        // Simulate address verification
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // In a real app, this would call a verification service
            self.isVerified = true
            self.neighborhoodName = "Maple Street Neighborhood"
            self.verificationStatus = "Verified"
            completion(true)
        }
    }
    
    func calculateDistance(from location1: CLLocation, to location2: CLLocation) -> Double {
        return location1.distance(from: location2)
    }
}

// MARK: - Push Notification Manager
class PushNotificationManager: ObservableObject {
    @Published var isAuthorized = false
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
        }
    }
    
    func scheduleEmergencyNotification(title: String, body: String, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "emergency"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleCommunityNotification(title: String, body: String, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "community"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleChatNotification(from user: String, message: String, messageId: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Community Chat Message"
        content.body = "\(user): \(message.prefix(100))"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "chat"
        
        let request = UNNotificationRequest(identifier: "chat-\(messageId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Safety Manager
class SafetyManager: ObservableObject {
    @Published var currentSafetyLevel: SafetyLevel = .safe
    @Published var recentIncidents: [SecurityIncident] = []
    @Published var emergencyContacts: [EmergencyContact] = []
    
    enum SafetyLevel: String, CaseIterable {
        case safe = "Safe"
        case caution = "Caution"
        case warning = "Warning"
        case danger = "Danger"
        
        var color: Color {
            switch self {
            case .safe: return .green
            case .caution: return .yellow
            case .warning: return .orange
            case .danger: return .red
            }
        }
    }
    
    func calculateSafetyScore() -> Double {
        // Implement safety score calculation based on recent incidents
        return 8.7 // Placeholder
    }
    
    func reportIncident(title: String, description: String, severity: String, location: CLLocation?) {
        // Create and save security incident
        let incident = SecurityIncident(context: PersistenceController.shared.container.viewContext)
        incident.id = UUID()
        incident.title = title
        incident.incidentDescription = description
        incident.severity = severity
        incident.reportedDate = Date()
        incident.status = "Reported"
        
        if let location = location {
            let locationData = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude]
            if let jsonData = try? JSONSerialization.data(withJSONObject: locationData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                incident.location = jsonString
            }
        }
        
        PersistenceController.shared.save()
        
        // Send push notification to neighbors
        PushNotificationManager().scheduleEmergencyNotification(
            title: "Safety Alert",
            body: title
        )
    }
}

// MARK: - Content Moderation Manager
class ContentModerationManager: ObservableObject {
    private let inappropriateWords = ["spam", "scam", "fake"] // Simplified list
    
    func moderateContent(_ content: String) -> ContentModerationResult {
        let lowercaseContent = content.lowercased()
        
        // Check for inappropriate content
        for word in inappropriateWords {
            if lowercaseContent.contains(word) {
                return ContentModerationResult(
                    isAppropriate: false,
                    reason: "Contains inappropriate language",
                    suggestedAction: .flagForReview
                )
            }
        }
        
        // Check content length
        if content.count > 5000 {
            return ContentModerationResult(
                isAppropriate: false,
                reason: "Content too long",
                suggestedAction: .requestEdit
            )
        }
        
        return ContentModerationResult(
            isAppropriate: true,
            reason: "Content approved",
            suggestedAction: .approve
        )
    }
}

struct ContentModerationResult {
    let isAppropriate: Bool
    let reason: String
    let suggestedAction: ModerationAction
}

enum ModerationAction {
    case approve
    case flagForReview
    case requestEdit
    case block
}

// MARK: - Reputation Manager
class ReputationManager: ObservableObject {
    func calculateReputation(for user: User) -> Double {
        // Implement reputation calculation based on:
        // - Posts liked by community
        // - Helpful contributions
        // - Event participation
        // - Verification status
        // - Report history
        
        var score = 3.0 // Base score
        
        if user.isVerified {
            score += 1.0
        }
        
        // Add points for community engagement
        if let posts = user.posts as? Set<Post> {
            let totalLikes = posts.reduce(0) { $0 + Int($1.likes) }
            score += min(Double(totalLikes) * 0.1, 2.0)
        }
        
        return min(score, 5.0)
    }
    
    func updateUserReputation(_ user: User) {
        let newScore = calculateReputation(for: user)
        user.reputationScore = newScore
        PersistenceController.shared.save()
    }
}

// MARK: - Emergency Contact Manager
class EmergencyContactManager: ObservableObject {
    @Published var contacts: [EmergencyContact] = []
    
    func addEmergencyContact(name: String, phone: String, relationship: String, user: User) {
        let contact = EmergencyContact(context: PersistenceController.shared.container.viewContext)
        contact.id = UUID()
        contact.name = name
        contact.phoneNumber = phone
        contact.relationship = relationship
        contact.user = user
        contact.isActive = true
        contact.priority = Int32(contacts.count)
        
        PersistenceController.shared.save()
        loadContacts(for: user)
    }
    
    func loadContacts(for user: User) {
        if let userContacts = user.emergencyContacts as? Set<EmergencyContact> {
            self.contacts = Array(userContacts).sorted { $0.priority < $1.priority }
        }
    }
    
    func callEmergencyContact(_ contact: EmergencyContact) {
        guard let phone = contact.phoneNumber,
              let url = URL(string: "tel:\(phone)") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

import SwiftUI
import UserNotifications
import UIKit
