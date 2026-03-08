import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct AdminPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: AdminTab = .users
    @State private var users: [UserProfile] = []
    @State private var isLoading: Bool = true
    @State private var searchText: String = ""
    @State private var selectedUser: UserProfile?
    @State private var showUserDetail: Bool = false
    @State private var filterRole: UserRole = .all
    
    enum AdminTab: String, CaseIterable, Identifiable {
        case users = "Users"
        case subscriptions = "Subscriptions"
        case monthlySubscriptions = "Monthly Subs"
        case wellness = "Wellness"
        var id: String { rawValue }
    }
    
    enum UserRole: String, CaseIterable {
        case all = "All Users"
        case admin = "Admins"
        case committee = "Committee"
        case regular = "Regular"
    }
    
    struct UserProfile: Identifiable {
        let id: String
        let email: String
        let firstName: String
        let lastName: String
        let phone: String
        let address: String
        var isAdmin: Bool
        var isCommittee: Bool
        var verified: Bool
        let createdAt: Date
        let lastLogin: Date?
        
        var fullName: String {
            "\(firstName) \(lastName)"
        }
        
        var initials: String {
            let first = firstName.prefix(1)
            let last = lastName.prefix(1)
            return "\(first)\(last)".uppercased()
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(AdminTab.allCases) { tab in
                            Button(action: { selectedTab = tab }) {
                                VStack(spacing: 4) {
                                    Text(tab.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 10)
                                    Rectangle()
                                        .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color(.systemGray6))
                Divider()
                
                // Tab Content
                if selectedTab == .users {
                    usersTabContent
                } else if selectedTab == .subscriptions {
                    SubscriptionTrackerView(skipAuthCheck: true)
                } else if selectedTab == .monthlySubscriptions {
                    MonthlySubscriptionTrackerView(skipAuthCheck: true)
                } else if selectedTab == .wellness {
                    WellnessAdminDashboardView()
                }
            }
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showUserDetail) {
                if let user = selectedUser {
                    UserDetailView(user: $selectedUser, onSave: { updatedUser in
                        if let index = users.firstIndex(where: { $0.id == updatedUser.id }) {
                            users[index] = updatedUser
                        }
                    })
                }
            }
            .task {
                await loadUsers()
            }
        }
    }
    
    private var usersTabContent: some View {
        VStack(spacing: 0) {
                // Filter & Search Bar
                VStack(spacing: 12) {
                    // Role filter
                    Picker("Filter", selection: $filterRole) {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search by name, email, phone, or address...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // User List
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading users...")
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                    Spacer()
                } else if filteredUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No users found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredUsers) { user in
                            Button(action: {
                                selectedUser = user
                                showUserDetail = true
                            }) {
                                UserRowView(user: user)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadUsers()
                    }
                }
            }
    }
    
    private var filteredUsers: [UserProfile] {
        var result = users
        
        // Apply role filter
        switch filterRole {
        case .all:
            break
        case .admin:
            result = result.filter { $0.isAdmin }
        case .committee:
            result = result.filter { $0.isCommittee }
        case .regular:
            result = result.filter { !$0.isAdmin && !$0.isCommittee }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.phone.localizedCaseInsensitiveContains(searchText) ||
                $0.address.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result.sorted { $0.fullName < $1.fullName }
    }
    
    private func loadUsers() async {
        await MainActor.run { isLoading = true }
        
        let db = Firestore.firestore()
        
        do {
            let snapshot = try await db.collection("users").getDocuments()
            var loadedUsers: [UserProfile] = []
            
            for document in snapshot.documents {
                let data = document.data()
                
                guard let email = data["email"] as? String,
                      let firstName = data["firstName"] as? String,
                      let lastName = data["lastName"] as? String else {
                    continue
                }
                
                let phone = data["phone"] as? String ?? ""
                let street = data["street"] as? String ?? ""
                let suburb = data["suburb"] as? String ?? ""
                let city = data["city"] as? String ?? ""
                let postalCode = data["postalCode"] as? String ?? ""
                let address = "\(street), \(suburb), \(city) \(postalCode)"
                
                let isAdmin = data["isAdmin"] as? Bool ?? false
                let isCommittee = data["isCommittee"] as? Bool ?? false
                let verified = data["verified"] as? Bool ?? false
                
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let lastLogin = (data["lastLogin"] as? Timestamp)?.dateValue()
                
                let user = UserProfile(
                    id: document.documentID,
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone,
                    address: address,
                    isAdmin: isAdmin,
                    isCommittee: isCommittee,
                    verified: verified,
                    createdAt: createdAt,
                    lastLogin: lastLogin
                )
                
                loadedUsers.append(user)
            }
            
            await MainActor.run {
                users = loadedUsers
                isLoading = false
            }
        } catch {
            print("Error loading users: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

struct UserRowView: View {
    let user: AdminPanelView.UserProfile
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                
                Text(user.initials)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.headline)
                
                Text(user.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    if user.isAdmin {
                        Label("Admin", systemImage: "shield.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if user.isCommittee {
                        Label("Committee", systemImage: "person.2.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if user.verified {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

struct UserDetailView: View {
    @Binding var user: AdminPanelView.UserProfile?
    var onSave: (AdminPanelView.UserProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editedUser: AdminPanelView.UserProfile?
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showDeleteConfirmation: Bool = false
    
    var body: some View {
        NavigationView {
            if let editedUser = editedUser {
                Form {
                    Section("Profile") {
                        HStack {
                            Text("Name")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(editedUser.fullName)
                        }
                        
                        HStack {
                            Text("Email")
                                .foregroundColor(.secondary)
                            Spacer()
                            if let emailURL = urlForEmail(editedUser.email) {
                                Button {
                                    openURL(emailURL)
                                } label: {
                                    Text(editedUser.email)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(editedUser.email)
                                    .font(.caption)
                            }
                        }
                        
                        HStack {
                            Text("Phone")
                                .foregroundColor(.secondary)
                            Spacer()
                            if let phoneURL = urlForPhone(editedUser.phone) {
                                Button {
                                    openURL(phoneURL)
                                } label: {
                                    Text(editedUser.phone)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(editedUser.phone)
                            }
                        }
                        
                        HStack {
                            Text("Address")
                                .foregroundColor(.secondary)
                            Spacer()
                            if let mapsURL = urlForAddress(editedUser.address) {
                                Button {
                                    openURL(mapsURL)
                                } label: {
                                    Text(editedUser.address)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .multilineTextAlignment(.trailing)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(editedUser.address)
                                    .font(.caption)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    
                    Section("Account Info") {
                        HStack {
                            Text("Joined")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(editedUser.createdAt, style: .date)
                        }
                        
                        HStack {
                            Text("Last Login")
                                .foregroundColor(.secondary)
                            Spacer()
                            if let lastLogin = editedUser.lastLogin {
                                Text(lastLogin, style: .relative)
                            } else {
                                Text("Never")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section("Permissions") {
                        Toggle("Administrator", isOn: Binding(
                            get: { self.editedUser?.isAdmin ?? false },
                            set: { self.editedUser?.isAdmin = $0 }
                        ))
                        .tint(.orange)
                        
                        Toggle("Committee Member", isOn: Binding(
                            get: { self.editedUser?.isCommittee ?? false },
                            set: { self.editedUser?.isCommittee = $0 }
                        ))
                        .tint(.blue)
                        
                        Toggle("Verified", isOn: Binding(
                            get: { self.editedUser?.verified ?? false },
                            set: { self.editedUser?.verified = $0 }
                        ))
                        .tint(.green)
                    }
                    
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            HStack {
                                Spacer()
                                Text("Delete User")
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle("User Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: saveChanges) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isLoading)
                    }
                }
                .alert("Error", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
                .confirmationDialog("Delete User", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: deleteUser)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete this user? This action cannot be undone.")
                }
            }
        }
        .onAppear {
            editedUser = user
        }
    }
    
    private func saveChanges() {
        guard let editedUser = editedUser else { return }
        
        isLoading = true
        
        let db = Firestore.firestore()
        let updates: [String: Any] = [
            "isAdmin": editedUser.isAdmin,
            "isCommittee": editedUser.isCommittee,
            "verified": editedUser.verified
        ]
        
        db.collection("users").document(editedUser.id).updateData(updates) { error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                showError = true
            } else {
                user = editedUser
                onSave(editedUser)
                dismiss()
            }
        }
    }
    
    private func deleteUser() {
        guard let editedUser = editedUser else { return }
        
        isLoading = true
        
        let db = Firestore.firestore()
        db.collection("users").document(editedUser.id).delete { error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                showError = true
            } else {
                user = nil
                dismiss()
            }
        }
    }

    private func urlForEmail(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    private func urlForPhone(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func urlForAddress(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }
}

// Preview
struct AdminPanelView_Previews: PreviewProvider {
    static var previews: some View {
        AdminPanelView()
    }
}
