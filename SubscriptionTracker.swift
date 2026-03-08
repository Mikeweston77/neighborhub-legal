// SubscriptionTracker.swift
// iOS implementation for subscription tracker features
// Generated for parity with Android

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct Subscription: Identifiable, Codable {
    var id: String
    var memberUID: String
    var amount: Double?
    var status: String?
    // Add other fields as needed
}

class SubscriptionTrackerViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var userRole: String = ""
    @Published var currentUserUID: String = ""
    private let db = Firestore.firestore()

    init() {
        fetchCurrentUser()
        fetchSubscriptions()
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

    func fetchSubscriptions() {
        db.collection("subscriptions").getDocuments { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            self.subscriptions = docs.compactMap { doc in
                try? doc.data(as: Subscription.self)
            }
        }
    }

    func canListSubscriptions() -> Bool {
        return userRole == "admin" || userRole == "committee"
    }

    func canGetSubscription(_ subscription: Subscription) -> Bool {
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

struct SubscriptionTrackerView: View {
    @StateObject var viewModel = SubscriptionTrackerViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.subscriptions) { subscription in
                if viewModel.canGetSubscription(subscription) {
                    NavigationLink(destination: SubscriptionDetailView(subscription: subscription)) {
                        Text(subscription.id)
                    }
                }
            }
            .navigationTitle("Subscriptions")
        }
    }
}

struct SubscriptionDetailView: View {
    let subscription: Subscription
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription ID: \(subscription.id)")
            Text("Member UID: \(subscription.memberUID)")
            // Add more fields as needed
        }
        .padding()
    }
}

// For modal contact actions, use ActionSheet in SwiftUI
// For bulk actions, add batch Firestore operations in ViewModel
