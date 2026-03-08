import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
// ...existing code...

class SubscriptionTrackerViewModel: ObservableObject {
        func updateMember(_ updatedMember: MemberSubscription) {
            do {
                try db.collection("subscriptions")
                    .document(updatedMember.id.uuidString)
                    .setData(from: updatedMember, merge: false)
            } catch {
                print("Error saving subscription: \(error)")
            }
            if let index = subscriptions.firstIndex(where: { $0.id == updatedMember.id }) {
                subscriptions[index] = updatedMember
            } else {
                subscriptions.append(updatedMember)
            }
        }
        
        func deleteMember(_ member: MemberSubscription) {
            // Remove from local array immediately for responsive UI
            subscriptions.removeAll { $0.id == member.id }
            
            // Delete from Firestore to persist the change for all users
            db.collection("subscriptions")
                .document(member.id.uuidString)
                .delete { error in
                    if let error = error {
                        print("Error deleting subscription from Firestore: \(error.localizedDescription)")
                        // Optionally: reload subscriptions to restore deleted item if Firestore delete failed
                        // self.reloadSubscriptions()
                    } else {
                        print("Successfully deleted subscription from Firestore: \(member.fullName)")
                    }
                }
        }
    @Published var subscriptions: [MemberSubscription] = []
    @Published var userRole: String = ""
    @Published var currentUserUID: String = ""
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()


    init() {
        fetchCurrentUser()
        reloadSubscriptions()
    }

    func fetchCurrentUser() {
        if let user = Auth.auth().currentUser {
            currentUserUID = user.uid
            db.collection("users").document(user.uid).getDocument { doc, error in
                if let data = doc?.data() {
                    if data["isAdmin"] as? Bool == true {
                        self.userRole = "admin"
                    } else if data["isCommittee"] as? Bool == true {
                        self.userRole = "committee"
                    } else {
                        self.userRole = "user"
                    }
                }
            }
        }
    }

    /// Loads all subscriptions from Firestore (used for both initial load and manual refresh)
    func reloadSubscriptions(completion: (() -> Void)? = nil) {
        db.collection("subscriptions").getDocuments { snapshot, error in
            if let error = error {
                print("Error loading subscriptions: \(error.localizedDescription)")
                completion?()
                return
            }

            if let docs = snapshot?.documents {
                self.subscriptions = docs.compactMap { doc in
                    try? doc.data(as: MemberSubscription.self)
                }
            }

            // Keep tracker in sync with newly verified users that do not yet
            // have a corresponding subscriptions record.
            self.seedMissingSubscriptionsFromUsers {
                completion?()
            }
        }
    }

    private func seedMissingSubscriptionsFromUsers(completion: @escaping () -> Void) {
        db.collection("users")
            .whereField("verified", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading users for subscription seeding: \(error.localizedDescription)")
                    completion()
                    return
                }

                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    completion()
                    return
                }

                let existingUIDs = Set(self.subscriptions.map { $0.memberUID })
                let missingMembers = docs.compactMap { doc -> MemberSubscription? in
                    let data = doc.data()
                    let uid = (data["uid"] as? String) ?? doc.documentID
                    guard !uid.isEmpty, !existingUIDs.contains(uid) else { return nil }

                    let firstName = (data["firstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lastName = (data["lastName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallbackName = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    let parsedFallback = self.splitFullName(fallbackName)
                    let memberName = (firstName?.isEmpty == false ? firstName! : parsedFallback.firstName)
                    let memberSurname = (lastName?.isEmpty == false ? lastName! : parsedFallback.lastName)

                    return MemberSubscription(
                        memberUID: uid,
                        memberName: memberName.isEmpty ? "Unknown" : memberName,
                        memberSurname: memberSurname,
                        address: self.composeAddress(from: data),
                        email: data["email"] as? String,
                        phone: data["phone"] as? String
                    )
                }

                guard !missingMembers.isEmpty else {
                    completion()
                    return
                }

                let batch = self.db.batch()
                for member in missingMembers {
                    let ref = self.db.collection("subscriptions").document(member.id.uuidString)
                    do {
                        try batch.setData(from: member, forDocument: ref, merge: false)
                    } catch {
                        print("Error encoding seeded subscription for \(member.memberUID): \(error)")
                    }
                }

                batch.commit { error in
                    if let error = error {
                        print("Error seeding missing subscriptions: \(error.localizedDescription)")
                    } else {
                        print("Seeded \(missingMembers.count) missing subscriptions from verified users")
                        self.subscriptions.append(contentsOf: missingMembers)
                        self.subscriptions.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
                    }
                    completion()
                }
            }
    }

    private func composeAddress(from data: [String: Any]) -> String? {
        let parts = [
            data["street"] as? String,
            data["suburb"] as? String,
            data["city"] as? String,
            data["postalCode"] as? String
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private func splitFullName(_ fullName: String) -> (firstName: String, lastName: String) {
        let components = fullName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return ("", "") }
        guard components.count > 1 else { return (components[0], "") }

        let firstName = components[0]
        let lastName = components.dropFirst().joined(separator: " ")
        return (firstName, lastName)
    }

    func canListSubscriptions() -> Bool {
        return userRole == "admin" || userRole == "committee"
    }

    func canGetSubscription(_ subscription: MemberSubscription) -> Bool {
        return userRole == "admin" || userRole == "committee" || subscription.memberUID == currentUserUID
    }

    func canCreateOrUpdate() -> Bool {
        return userRole == "admin" || userRole == "committee"
    }

    func canDelete() -> Bool {
        return userRole == "admin"
    }

    // Add methods for bulk reminders, payment capture, etc.
}
