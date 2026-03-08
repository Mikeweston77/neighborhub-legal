import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// User-facing household management for regular users to manage their own household memberships
struct UserHouseholdManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserHouseholdViewModel()
    @State private var showAddMember = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle("My Household")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    #endif
                }
        }
        .sheet(isPresented: $showAddMember) {
            addMemberSheet
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .task {
            await viewModel.loadMySubscription()
        }
        .onChange(of: viewModel.errorMessage) {
            if let error = viewModel.errorMessage {
                errorMessage = error
                showError = true
            }
        }
        .onChange(of: viewModel.successMessage) {
            if let success = viewModel.successMessage {
                successMessage = success
                showSuccess = true
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading household information...")
                .padding()
        } else if let subscription = viewModel.mySubscription {
            householdContent(subscription: subscription)
        } else {
            noSubscriptionView
        }
    }
    
    @ViewBuilder
    private var addMemberSheet: some View {
        if let subscription = viewModel.mySubscription {
            AddHouseholdMemberView(
                currentSubscription: subscription,
                onAdd: { userUID in
                    Task {
                        await viewModel.addHouseholdMember(userUID)
                    }
                }
            )
        }
    }
    
    // MARK: - Household Content
    
    private func householdContent(subscription: MemberSubscription) -> some View {
        // Get all household members including primary user
        let allHouseholdMembers: [String] = {
            var allMembers = Set<String>()
            
            // Always include the primary user (owner)
            allMembers.insert(subscription.memberUID)
            
            // Add all household members
            if let members = subscription.householdMembers {
                allMembers.formUnion(members)
            }
            
            // Return as sorted array (primary user first, then others)
            return Array(allMembers).sorted { uid1, uid2 in
                if uid1 == subscription.memberUID { return true }
                if uid2 == subscription.memberUID { return false }
                return uid1 < uid2
            }
        }()
        
        return List {
            // Status Section
            Section {
                HStack {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundColor(subscription.isHousehold ? .purple : .blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscription.effectiveSubscriptionType.displayRate)
                            .font(.headline)
                        Text(subscription.isHousehold
                            ? "\(subscription.householdSize) of \(MemberSubscription.maxHouseholdMembers) members"
                            : "Single user subscription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                
                // Monthly Payment Status
                HStack {
                    Text("Current Month")
                    Spacer()
                    if subscription.isPaidCurrentMonth ?? false {
                        Label("Paid", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Unpaid", systemImage: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.subheadline)
                
                if subscription.monthsUnpaid > 0 {
                    HStack {
                        Text("Amount Due")
                        Spacer()
                        Text("R\(Int(subscription.totalOutstanding))")
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Subscription Status")
            } footer: {
                Text("Your subscription covers all members in your household.")
                    .font(.caption)
            }
            
            // Household Members Section
            Section {
                // Show all household members including primary user
                ForEach(Array(allHouseholdMembers.enumerated()), id: \.offset) { index, userUID in
                    HouseholdMemberRowWithDetails(
                        userUID: userUID,
                        isPrimary: userUID == subscription.memberUID,
                        canRemove: allHouseholdMembers.count > 1 && userUID != subscription.memberUID,
                        subscriptionAddress: subscription.address,
                        onRemove: {
                            Task {
                                await viewModel.removeHouseholdMember(userUID)
                            }
                        }
                    )
                }
                
                // Add Member Button
                if subscription.canAddHouseholdMember && !viewModel.isInAnotherHousehold {
                    Button(action: { showAddMember = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add Household Member")
                            Spacer()
                            Text("\(subscription.remainingHouseholdSlots) slots")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Household Members (\(allHouseholdMembers.count))")
            } footer: {
                if viewModel.isInAnotherHousehold {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("You are already a member of another household. You cannot manage your own household while being a dependent member.")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                } else if !subscription.canAddHouseholdMember {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Maximum household size reached (5 members)")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                } else if !subscription.isHousehold {
                    Text("Add members to upgrade to household rate (R99/month for up to 5 people)")
                        .font(.caption)
                }
            }
            
            // Pricing Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    PricingInfoRow(
                        icon: "person.fill",
                        title: "Single User",
                        price: "R50/month",
                        description: "For individual members",
                        isActive: !subscription.isHousehold
                    )
                    
                    Divider()
                    
                    PricingInfoRow(
                        icon: "person.2.fill",
                        title: "Household",
                        price: "R99/month",
                        description: "Up to 5 people",
                        isActive: subscription.isHousehold
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("Subscription Plans")
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - No Subscription View
    
    private var noSubscriptionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Subscription Found")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Contact your admin to set up a subscription for your household.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

struct HouseholdMemberRowWithDetails: View {
    let userUID: String
    let isPrimary: Bool
    let canRemove: Bool
    let subscriptionAddress: String?
    let onRemove: () -> Void
    
    @State private var userName: String = ""
    
    private var displayAddress: String {
        subscriptionAddress ?? "No address"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isPrimary ? Color.purple : Color.blue)
                    .frame(width: 40, height: 40)
                
                Text(userName.isEmpty ? "?" : userName.prefix(1))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(userName.isEmpty ? "Loading..." : userName)
                    .font(.body)
                    .fontWeight(isPrimary ? .semibold : .regular)
                
                Text(displayAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isPrimary {
                    Text("Primary Member")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
            
            Spacer()
            
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .task {
            await loadUserDetails()
        }
    }
    
    private func loadUserDetails() async {
        #if canImport(FirebaseFirestore)
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(userUID)
                .getDocument()
            
            if let data = snapshot.data(),
               let firstName = data["firstName"] as? String,
               let lastName = data["lastName"] as? String {
                userName = "\(firstName) \(lastName)"
            } else {
                userName = userUID
            }
        } catch {
            print("Error loading user details: \(error)")
            userName = userUID
        }
        #endif
    }
}

struct PricingInfoRow: View {
    let icon: String
    let title: String
    let price: String
    let description: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive ? .blue : .secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    if isActive {
                        Text("(Current)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(price)
                .font(.headline)
                .foregroundColor(isActive ? .blue : .secondary)
        }
    }
}

// MARK: - Add Household Member View

struct AddHouseholdMemberView: View {
    let currentSubscription: MemberSubscription?
    let onAdd: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var availableUsers: [UserSearchResult] = []
    @State private var isLoading = false
    
    struct UserSearchResult: Identifiable {
        let id: String // UID
        let name: String
        let email: String
        let address: String?
        let isAlreadyAdded: Bool
    }
    
    private var filteredUsers: [UserSearchResult] {
        if searchText.isEmpty {
            return availableUsers
        }
        return availableUsers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by name or email", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .systemGray6))
                
                if isLoading {
                    ProgressView("Loading users...")
                        .padding()
                } else {
                    VStack(spacing: 0) {
                        // Current Household Members Header
                        currentHouseholdSection
                        
                        Divider()
                        
                        // Available Users to Add
                        if filteredUsers.isEmpty {
                            emptyStateView
                        } else {
                            availableUsersSection
                        }
                    }
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadAvailableUsers()
            }
        }
    }
    
    private var currentHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Household")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(currentHouseholdMembers.count) of \(MemberSubscription.maxHouseholdMembers) members")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            if let subscription = currentSubscription {
                VStack(spacing: 0) {
                    ForEach(Array(currentHouseholdMembers.enumerated()), id: \.offset) { index, userUID in
                        HouseholdMemberSummaryRow(
                            userUID: userUID,
                            isPrimary: userUID == subscription.memberUID,
                            subscriptionAddress: subscription.address
                        )
                        if index < currentHouseholdMembers.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Text("Available at Your Address")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 4)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    // Get all household members including the primary user
    private var currentHouseholdMembers: [String] {
        guard let subscription = currentSubscription else { return [] }
        
        var allMembers = Set<String>()
        
        // Always include the primary user (owner)
        allMembers.insert(subscription.memberUID)
        
        // Add all household members
        if let members = subscription.householdMembers {
            allMembers.formUnion(members)
        }
        
        // Return as sorted array (primary user first, then others)
        return Array(allMembers).sorted { uid1, uid2 in
            if uid1 == subscription.memberUID { return true }
            if uid2 == subscription.memberUID { return false }
            return uid1 < uid2
        }
    }
    
    private var availableUsersSection: some View {
        List(filteredUsers) { user in
            Button(action: {
                onAdd(user.id)
                dismiss()
            }) {
                HStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 40, height: 40)
                        
                        Text(user.name.prefix(1))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let address = user.address {
                            Text(address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if user.isAlreadyAdded {
                        Text("Added")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(user.isAlreadyAdded)
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(searchText.isEmpty ? "No Users Available" : "No Results Found")
                .font(.headline)
            
            if searchText.isEmpty {
                VStack(spacing: 8) {
                    Text("Verified users at your address will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Users already in other households are not available to add")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                    
                    if let address = currentSubscription?.address {
                        Text("Looking for users at: \(address)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text("Try adjusting your search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Household Member Summary Row

struct HouseholdMemberSummaryRow: View {
    let userUID: String
    let isPrimary: Bool
    let subscriptionAddress: String?
    @State private var userName: String = ""
    
    private var displayAddress: String {
        subscriptionAddress ?? "No address"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isPrimary ? Color.purple : Color.blue)
                    .frame(width: 40, height: 40)
                
                Text(userName.prefix(1))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(userName.isEmpty ? "Loading..." : userName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if isPrimary {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .fontWeight(.semibold)
                    }
                }
                
                Text(displayAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .task {
            await loadUserInfo()
        }
    }
    
    private func loadUserInfo() async {
        #if canImport(FirebaseFirestore)
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(userUID)
                .getDocument()
            
            if let data = doc.data(),
               let firstName = data["firstName"] as? String,
               let lastName = data["lastName"] as? String {
                userName = "\(firstName) \(lastName)"
            } else {
                userName = userUID
            }
        } catch {
            userName = userUID
        }
        #else
        userName = userUID
        #endif
    }
}

// MARK: - Add Household Member Extension

extension AddHouseholdMemberView {
    private func loadAvailableUsers() async {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        isLoading = true
        defer { isLoading = false }
        
        guard let currentUserUID = Auth.auth().currentUser?.uid else { return }
        
        // Build set of all members in current household (primary + household members)
        var existingMembers = Set<String>()
        if let subscription = currentSubscription {
            existingMembers.insert(subscription.memberUID) // Add primary
            if let members = subscription.householdMembers {
                existingMembers.formUnion(members) // Add all household members
            }
        }
        
        // Get current user's address for filtering
        guard let currentUserAddress = currentSubscription?.address,
              !currentUserAddress.isEmpty else {
            // No address set - can't filter by address
            availableUsers = []
            return
        }
        
        // Normalize the full address for comparison
        let normalizedCurrentAddress = currentUserAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        guard !normalizedCurrentAddress.isEmpty else {
            availableUsers = []
            return
        }
        
        do {
            // Step 1: Find all subscriptions with matching address (full address)
            let subscriptionsSnapshot = try await Firestore.firestore()
                .collection("subscriptions")
                .getDocuments()
            
            // Filter subscriptions by matching full address
            let matchingUIDs = subscriptionsSnapshot.documents.compactMap { doc -> String? in
                let data = doc.data()
                guard let memberUID = data["memberUID"] as? String,
                      memberUID != currentUserUID, // Skip current user
                      let subAddress = data["address"] as? String,
                      !subAddress.isEmpty else {
                    return nil
                }
                
                // Normalize the subscription address
                let normalizedSubAddress = subAddress
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                
                return normalizedSubAddress == normalizedCurrentAddress ? memberUID : nil
            }
            
            // Step 2: Get all household members across all subscriptions
            // to exclude users who are already in other households
            let allSubscriptions = try await Firestore.firestore()
                .collection("subscriptions")
                .getDocuments()
            
            var usersInOtherHouseholds = Set<String>()
            for doc in allSubscriptions.documents {
                if let members = doc.data()["householdMembers"] as? [String] {
                    usersInOtherHouseholds.formUnion(members)
                }
            }
            
            // Step 3: Load user details for matching UIDs
            if matchingUIDs.isEmpty {
                availableUsers = []
                return
            }
            
            // Load users in batches (Firestore 'in' query has a 10 item limit)
            var allUsers: [UserSearchResult] = []
            for uids in matchingUIDs.chunked(into: 10) {
                let usersSnapshot = try await Firestore.firestore()
                    .collection("users")
                    .whereField("verified", isEqualTo: true)
                    .whereField("uid", in: Array(uids))
                    .getDocuments()
                
                let batchUsers = usersSnapshot.documents.compactMap { doc -> UserSearchResult? in
                    let data = doc.data()
                    let uid = doc.documentID
                    
                    guard let firstName = data["firstName"] as? String,
                          let lastName = data["lastName"] as? String,
                          let email = data["email"] as? String else {
                        return nil
                    }
                    
                    // Skip if already in current household OR already in another household
                    let isAlreadyAdded = existingMembers.contains(uid) || usersInOtherHouseholds.contains(uid)
                    
                    return UserSearchResult(
                        id: uid,
                        name: "\(firstName) \(lastName)",
                        email: email,
                        address: currentUserAddress, // Use subscription address
                        isAlreadyAdded: isAlreadyAdded
                    )
                }
                
                allUsers.append(contentsOf: batchUsers)
            }
            
            // Filter out already-added members from the list
            availableUsers = allUsers.filter { !$0.isAlreadyAdded }.sorted { $0.name < $1.name }
        } catch {
            print("Error loading users: \(error)")
        }
        #endif
    }
}

// Helper extension to chunk arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - ViewModel

@MainActor
class UserHouseholdViewModel: ObservableObject {
    @Published var mySubscription: MemberSubscription?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isInAnotherHousehold: Bool = false
    
    #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
    private let db = Firestore.firestore()
    #endif
    
    func loadMySubscription() async {
        #if canImport(FirebaseAuth)
        guard let currentUserUID = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        #if canImport(FirebaseFirestore)
        do {
            let snapshot = try await db.collection("subscriptions")
                .whereField("memberUID", isEqualTo: currentUserUID)
                .limit(to: 1)
                .getDocuments()
            
            if let doc = snapshot.documents.first {
                mySubscription = try doc.data(as: MemberSubscription.self)
            }
            
            // Check if user is in another household
            await checkIfInAnotherHousehold()
        } catch {
            errorMessage = "Failed to load subscription: \(error.localizedDescription)"
        }
        #endif
        #endif
    }
    
    func checkIfInAnotherHousehold() async {
        #if canImport(FirebaseAuth)
        guard let currentUserUID = Auth.auth().currentUser?.uid else { return }
        
        #if canImport(FirebaseFirestore)
        do {
            // Check if current user appears in any subscription's householdMembers array
            let snapshot = try await db.collection("subscriptions")
                .whereField("householdMembers", arrayContains: currentUserUID)
                .getDocuments()
            
            // If we find any subscription where the user is a household member
            // (not the primary owner), set the flag
            isInAnotherHousehold = !snapshot.documents.isEmpty
        } catch {
            print("Error checking household membership: \(error.localizedDescription)")
            isInAnotherHousehold = false
        }
        #endif
        #endif
    }
    
    func addHouseholdMember(_ userUID: String) async {
        guard var subscription = mySubscription else {
            errorMessage = "No subscription found"
            return
        }
        
        let result = subscription.addHouseholdMember(userUID)
        
        switch result {
        case .success:
            #if canImport(FirebaseFirestore)
            do {
                try db.collection("subscriptions")
                    .document(subscription.id.uuidString)
                    .setData(from: subscription, merge: true)
                
                mySubscription = subscription
                successMessage = "Household member added successfully!"
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
            #endif
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
    
    func removeHouseholdMember(_ userUID: String) async {
        guard var subscription = mySubscription else {
            errorMessage = "No subscription found"
            return
        }
        
        subscription.removeHouseholdMember(userUID)
        
        #if canImport(FirebaseFirestore)
        do {
            try db.collection("subscriptions")
                .document(subscription.id.uuidString)
                .setData(from: subscription, merge: true)
            
            mySubscription = subscription
            successMessage = "Member removed from household"
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
        #endif
    }
}
