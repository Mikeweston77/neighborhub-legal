import Foundation
import SwiftUI

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif

/// Manager for community-wide emergency contacts that admins/committee members can edit
class CommunityEmergencyContactManager: ObservableObject {
    @Published var contacts: [CommunityEmergencyContact] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    #if canImport(FirebaseFirestore)
    private var contactsListener: ListenerRegistration?
    #endif
    
    private let userDefaults = UserDefaults.standard
    private let contactsKey = "communityEmergencyContacts"
    
    // Admin/committee authentication
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    @AppStorage("userUID") private var userUID: String = ""
    
    var canEdit: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    var currentUserUID: String {
        return userUID
    }
    
    init() {
        loadLocalContacts()
        
        // Initialize with default contacts if empty
        if contacts.isEmpty {
            initializeDefaultContacts()
        }
        
        #if canImport(FirebaseFirestore)
        startRealtimeListener()
        #endif
    }
    
    deinit {
        #if canImport(FirebaseFirestore)
        stopRealtimeListener()
        #endif
    }
    
    // MARK: - Local Storage
    
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
    
    private func initializeDefaultContacts() {
        contacts = CommunityEmergencyContact.defaultContacts
        saveLocalContacts()
        
        #if canImport(FirebaseFirestore)
        // Upload default contacts to Firestore
        for contact in contacts {
            saveContactToFirestore(contact)
        }
        #endif
    }
    
    // MARK: - Firestore Real-time Sync
    
    #if canImport(FirebaseFirestore)
    private func startRealtimeListener() {
        print("🚨 EmergencyContacts: Starting real-time Firestore listener")
        print("   Current user UID: \(userUID)")
        print("   Can edit: \(canEdit)")
        stopRealtimeListener()
        
        let db = Firestore.firestore()
        
        contactsListener = db.collection("emergencyContacts")
            .addSnapshotListener { [weak self] snapshot, error in
                
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ EmergencyContacts: Error in real-time listener: \(error.localizedDescription)")
                        print("   Error code: \((error as NSError).code)")
                        print("   Error domain: \((error as NSError).domain)")
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("⚠️ EmergencyContacts: No contacts found in Firestore")
                        self?.contacts = []
                        return
                    }
                    
                    print("🚨 EmergencyContacts: Received \(documents.count) contacts from Firestore")
                    print("   Document IDs: \(documents.map { $0.documentID }.joined(separator: ", "))")
                    
                    var firestoreContacts: [CommunityEmergencyContact] = []
                    
                    for document in documents {
                        if let contact = self?.parseFirestoreContact(document.data(), id: document.documentID) {
                            // Only include active contacts
                            if contact.isActive {
                                firestoreContacts.append(contact)
                            }
                        }
                    }
                    
                    print("   Active contacts after filtering: \(firestoreContacts.count)")
                    
                    // Update contacts immediately for all users (sort by priority then category)
// Update contacts immediately for all users (sort by priority then category)
                    self?.contacts = firestoreContacts.sorted { contact1, contact2 in
                        if contact1.priority.rawValue != contact2.priority.rawValue {
                            return self?.priorityOrder(contact1.priority) ?? 0 < self?.priorityOrder(contact2.priority) ?? 0
                        }
                        return contact1.category.rawValue < contact2.category.rawValue
                    }
                    self?.saveLocalContacts()
                    print("✅ EmergencyContacts: Synced \(firestoreContacts.count) contacts from Firestore")
                }
            }
    }
    
    private func stopRealtimeListener() {
        contactsListener?.remove()
        contactsListener = nil
        print("🚨 EmergencyContacts: Stopped real-time listener")
    }
    
    // MARK: - Firestore Integration
    
    #if canImport(FirebaseFirestore)
    private func loadFromFirestore() {
        guard !contacts.isEmpty else {
            // If no local contacts, load from Firestore first
            fetchFromFirestore()
            return
        }
        
        // Load in background and update if newer
        fetchFromFirestore()
    }
    
    private func fetchFromFirestore() {
        isLoading = true
        let db = Firestore.firestore()
        
        db.collection("emergencyContacts")
            .getDocuments { [weak self] snapshot, error in
                
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        print("❌ Error loading emergency contacts: \(error.localizedDescription)")
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("⚠️ No emergency contacts found in Firestore")
                        return
                    }
                    
                    var firestoreContacts: [CommunityEmergencyContact] = []
                    
                    for document in documents {
                        if let contact = self?.parseFirestoreContact(document.data(), id: document.documentID) {
                            // Only include active contacts
                            if contact.isActive {
                                firestoreContacts.append(contact)
                            }
                        }
                    }
                    
                    // Update local contacts if we got data from Firestore
                    if !firestoreContacts.isEmpty {
                        self?.contacts = firestoreContacts.sorted { contact1, contact2 in
                            if contact1.priority.rawValue != contact2.priority.rawValue {
                                return self?.priorityOrder(contact1.priority) ?? 0 < self?.priorityOrder(contact2.priority) ?? 0
                            }
                            return contact1.category.rawValue < contact2.category.rawValue
                        }
                        self?.saveLocalContacts()
                        print("✅ Loaded \(firestoreContacts.count) emergency contacts from Firestore")
                    }
                }
            }
    }
    
    private func parseFirestoreContact(_ data: [String: Any], id: String) -> CommunityEmergencyContact? {
        guard let name = data["name"] as? String,
              let phoneNumber = data["phoneNumber"] as? String,
              let categoryString = data["category"] as? String,
              let category = CommunityEmergencyContact.ContactCategory(rawValue: categoryString),
              let priorityString = data["priority"] as? String,
              let priority = CommunityEmergencyContact.ContactPriority(rawValue: priorityString),
              let createdBy = data["createdBy"] as? String else {
            return nil
        }
        
        let email = data["email"] as? String
        let organization = data["organization"] as? String
        let availability = data["availability"] as? String
        let notes = data["notes"] as? String
        let isActive = data["isActive"] as? Bool ?? true
        
        let createdAt: Date
        let updatedAt: Date
        
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date()
        }
        
        if let timestamp = data["updatedAt"] as? Timestamp {
            updatedAt = timestamp.dateValue()
        } else {
            updatedAt = Date()
        }
        
        return CommunityEmergencyContact(
            id: id,
            name: name,
            phoneNumber: phoneNumber,
            email: email,
            organization: organization,
            category: category,
            priority: priority,
            availability: availability,
            notes: notes,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive
        )
    }
    
    private func saveContactToFirestore(_ contact: CommunityEmergencyContact) {
        let db = Firestore.firestore()
        
        var data: [String: Any] = [
            "name": contact.name,
            "phoneNumber": contact.phoneNumber,
            "category": contact.category.rawValue,
            "priority": contact.priority.rawValue,
            "createdBy": contact.createdBy,
            "createdAt": Timestamp(date: contact.createdAt),
            "updatedAt": Timestamp(date: contact.updatedAt),
            "isActive": contact.isActive
        ]
        
        if let email = contact.email {
            data["email"] = email
        }
        if let organization = contact.organization {
            data["organization"] = organization
        }
        if let availability = contact.availability {
            data["availability"] = availability
        }
        if let notes = contact.notes {
            data["notes"] = notes
        }
        
        db.collection("emergencyContacts").document(contact.id).setData(data, merge: true) { error in
            if let error = error {
                print("❌ Error saving emergency contact to Firestore: \(error.localizedDescription)")
                print("   Contact ID: \(contact.id)")
                print("   Contact Name: \(contact.name)")
            } else {
                print("✅ Emergency contact saved to Firestore successfully")
                print("   ID: \(contact.id)")
                print("   Name: \(contact.name)")
                print("   Phone: \(contact.phoneNumber)")
                print("   Category: \(contact.category.rawValue)")
                print("   Priority: \(contact.priority.rawValue)")
                print("   Created By (UID): \(contact.createdBy)")
            }
        }
    }
    #endif
    
    // MARK: - CRUD Operations
    
    func addContact(name: String, phoneNumber: String, email: String? = nil, organization: String? = nil, category: CommunityEmergencyContact.ContactCategory, priority: CommunityEmergencyContact.ContactPriority = .normal, availability: String? = nil, notes: String? = nil) {
        
        guard canEdit else {
            errorMessage = "Only admins and committee members can add emergency contacts"
            return
        }
        
        let newContact = CommunityEmergencyContact(
            name: name,
            phoneNumber: phoneNumber,
            email: email,
            organization: organization,
            category: category,
            priority: priority,
            availability: availability,
            notes: notes,
            createdBy: currentUserUID
        )
        
        contacts.append(newContact)
        contacts.sort { contact1, contact2 in
            if contact1.priority.rawValue != contact2.priority.rawValue {
                return priorityOrder(contact1.priority) < priorityOrder(contact2.priority)
            }
            return contact1.category.rawValue < contact2.category.rawValue
        }
        
        saveLocalContacts()
        
        #if canImport(FirebaseFirestore)
        saveContactToFirestore(newContact)
        #endif
    }
    
    func updateContact(_ contact: CommunityEmergencyContact) {
        guard canEdit else {
            errorMessage = "Only admins and committee members can edit emergency contacts"
            return
        }
        
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            var updatedContact = contact
            updatedContact = CommunityEmergencyContact(
                id: updatedContact.id,
                name: updatedContact.name,
                phoneNumber: updatedContact.phoneNumber,
                email: updatedContact.email,
                organization: updatedContact.organization,
                category: updatedContact.category,
                priority: updatedContact.priority,
                availability: updatedContact.availability,
                notes: updatedContact.notes,
                createdBy: updatedContact.createdBy,
                createdAt: updatedContact.createdAt,
                updatedAt: Date(),
                isActive: updatedContact.isActive
            )
            
            contacts[index] = updatedContact
            contacts.sort { contact1, contact2 in
                if contact1.priority.rawValue != contact2.priority.rawValue {
                    return priorityOrder(contact1.priority) < priorityOrder(contact2.priority)
                }
                return contact1.category.rawValue < contact2.category.rawValue
            }
            
            saveLocalContacts()
            
            #if canImport(FirebaseFirestore)
            saveContactToFirestore(updatedContact)
            #endif
        }
    }
    
    func deleteContact(_ contact: CommunityEmergencyContact) {
        guard canEdit else {
            errorMessage = "Only admins and committee members can delete emergency contacts"
            return
        }
        
        // Remove from local array
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts.remove(at: index)
            saveLocalContacts()
            
            #if canImport(FirebaseFirestore)
            // Hard delete from Firestore
            let db = Firestore.firestore()
            db.collection("emergencyContacts").document(contact.id).delete { error in
                if let error = error {
                    print("❌ Error deleting emergency contact from Firestore: \(error.localizedDescription)")
                    print("   Contact ID: \(contact.id)")
                    print("   Contact Name: \(contact.name)")
                } else {
                    print("✅ Emergency contact deleted from Firestore successfully")
                    print("   ID: \(contact.id)")
                    print("   Name: \(contact.name)")
                }
            }
            #endif
        }
    }
    
    // MARK: - Contact Actions
    
    func callContact(_ contact: CommunityEmergencyContact) {
        guard let url = URL(string: "tel:\(contact.phoneNumber)") else {
            errorMessage = "Invalid phone number: \(contact.phoneNumber)"
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            errorMessage = "Unable to make phone calls on this device"
        }
    }
    
    func messageContact(_ contact: CommunityEmergencyContact) {
        // WhatsApp support with South African number formatting
        var waNumber = contact.phoneNumber.filter { $0.isNumber }
        if waNumber.hasPrefix("0") && waNumber.count == 10 {
            waNumber = "27" + waNumber.dropFirst()
        }
        
        if let url = URL(string: "https://wa.me/\(waNumber)") {
            UIApplication.shared.open(url)
        }
    }
    
    func copyContactNumber(_ contact: CommunityEmergencyContact) {
        UIPasteboard.general.string = contact.phoneNumber
    }
    
    // MARK: - Filtering
    
    func contacts(for category: CommunityEmergencyContact.ContactCategory) -> [CommunityEmergencyContact] {
        return contacts.filter { $0.category == category }
    }
    
    func criticalContacts() -> [CommunityEmergencyContact] {
        return contacts.filter { $0.priority == .critical }
    }
}