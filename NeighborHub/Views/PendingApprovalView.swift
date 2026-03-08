import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// View shown to users after registration while waiting for admin approval
struct PendingApprovalView: View {
    @Binding var isVerified: Bool
    @State private var userName: String = ""
    @State private var userEmail: String = ""
    @State private var isCheckingStatus: Bool = false
    @State private var lastChecked: Date = Date()
    
    // Firestore listener
    @State private var listener: ListenerRegistration?
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
            }
            
            // Title
            VStack(spacing: 8) {
                Text("Pending Approval")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Welcome, \(userName)!")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Message
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Created")
                            .font(.headline)
                        Text("Your account has been successfully created")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Awaiting Verification")
                            .font(.headline)
                        Text("A community admin will review your registration")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("We'll Notify You")
                            .font(.headline)
                        Text("You'll receive an email at \(userEmail) once approved")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Status check button
            VStack(spacing: 12) {
                Button(action: {
                    checkApprovalStatus()
                }) {
                    HStack {
                        if isCheckingStatus {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isCheckingStatus ? "Checking..." : "Check Status")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isCheckingStatus)
                
                Text("Last checked: \(lastChecked, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            
            // Sign out button
            Button(action: {
                signOut()
            }) {
                Text("Sign Out")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            loadUserInfo()
            startListeningForApproval()
        }
        .onDisappear {
            stopListening()
        }
    }
    
    // MARK: - Methods
    
    private func loadUserInfo() {
        // Get user info from UserDefaults
        userName = UserDefaults.standard.string(forKey: "userName") ?? "there"
        userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""
        
        #if canImport(FirebaseAuth)
        // If not in UserDefaults, try Firebase Auth
        if userEmail.isEmpty, let user = Auth.auth().currentUser {
            userEmail = user.email ?? ""
        }
        #endif
    }
    
    private func startListeningForApproval() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        listener = db.collection("users").document(uid).addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening for approval: \(error)")
                return
            }
            
            guard let data = snapshot?.data() else { return }
            
            if let verified = data["verified"] as? Bool, verified {
                print("✅ User has been approved!")
                DispatchQueue.main.async {
                    self.isVerified = true
                    // Update UserDefaults
                    UserDefaults.standard.set(true, forKey: "userIsVerified")
                }
            }
        }
        #endif
    }
    
    private func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    private func checkApprovalStatus() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        isCheckingStatus = true
        
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isCheckingStatus = false
                self.lastChecked = Date()
            }
            
            if let error = error {
                print("❌ Error checking status: \(error)")
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ No user document found")
                return
            }
            
            if let verified = data["verified"] as? Bool {
                if verified {
                    print("✅ User has been approved!")
                    DispatchQueue.main.async {
                        self.isVerified = true
                        // Update UserDefaults
                        UserDefaults.standard.set(true, forKey: "userIsVerified")
                    }
                } else {
                    print("⏳ Still pending approval")
                }
            }
        }
        #endif
    }
    
    private func signOut() {
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            
            // Clear UserDefaults
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "userUID")
            defaults.removeObject(forKey: "userName")
            defaults.removeObject(forKey: "userEmail")
            defaults.removeObject(forKey: "userIsVerified")
            
            print("✅ User signed out successfully")
        } catch {
            print("❌ Error signing out: \(error)")
        }
        #endif
    }
}

// MARK: - Preview
struct PendingApprovalView_Previews: PreviewProvider {
    static var previews: some View {
        PendingApprovalView(isVerified: .constant(false))
    }
}
