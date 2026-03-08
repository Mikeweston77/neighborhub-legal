import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    @Binding var isAuthenticated: Bool
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var showSignUpRequired: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.accentColor.opacity(0.1), Color.accentColor.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "house.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.accentColor)
                            
                            Text("Welcome Back")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Sign in to continue to NeighborHub")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                        
                        // Login Form
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("your@email.com", text: $email)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .textContentType(.password)
                            }
                            
                            Button(action: { showForgotPassword = true }) {
                                Text("Forgot Password?")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            
                            Button(action: login) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Sign In")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canLogin ? Color.accentColor : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(!canLogin || isLoading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Login Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Account Not Found", isPresented: $showSignUpRequired) {
                Button("Sign Up", role: .none) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("No account exists for this email. Please create a new account to join NeighborHub.")
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
    }
    
    private var canLogin: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
    
    private func login() {
        guard canLogin else { return }
        
        isLoading = true
        errorMessage = ""
        
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
                return
            }
            
            guard let user = result?.user else {
                isLoading = false
                errorMessage = "Login failed"
                showError = true
                return
            }
            
            // Fetch user profile from Firestore
            let db = Firestore.firestore()
            db.collection("users").document(user.uid).getDocument { document, error in
                isLoading = false
                
                if let error = error {
                    errorMessage = "Failed to load profile: \(error.localizedDescription)"
                    showError = true
                    return
                }
                
                guard let data = document?.data() else {
                    print("⚠️ No Firestore document found for user: \(user.uid)")
                    print("🔓 User authenticated but no profile exists - signing out")
                    
                    // Sign out the user since they don't have a profile
                    try? Auth.auth().signOut()
                    
                    showSignUpRequired = true
                    return
                }
                
                // Store UID and verification status first (critical for auth flow)
                UserDefaults.standard.set(user.uid, forKey: "userUID")
                
                let verified = data["verified"] as? Bool ?? false
                UserDefaults.standard.set(verified, forKey: "userIsVerified")
                
                // Cache admin/committee roles for UI access control
                let isAdmin = data["isAdmin"] as? Bool ?? false
                let isCommittee = data["isCommittee"] as? Bool ?? false
                UserDefaults.standard.set(isAdmin, forKey: "userIsAdmin")
                UserDefaults.standard.set(isCommittee, forKey: "userIsCommittee")
                
                print("ℹ️ Login roles cached - Admin: \(isAdmin), Committee: \(isCommittee)")
                
                // Update local UserDefaults with user profile data
                if let firstName = data["firstName"] as? String {
                    UserDefaults.standard.set(firstName, forKey: "userName")
                }
                if let lastName = data["lastName"] as? String {
                    UserDefaults.standard.set(lastName, forKey: "userSurname")
                }
                if let email = data["email"] as? String {
                    UserDefaults.standard.set(email, forKey: "userEmail")
                }
                if let phone = data["phone"] as? String {
                    UserDefaults.standard.set(phone, forKey: "userCell")
                }
                if let street = data["street"] as? String {
                    UserDefaults.standard.set(street, forKey: "userStreet")
                }
                if let suburb = data["suburb"] as? String {
                    UserDefaults.standard.set(suburb, forKey: "userSuburb")
                }
                if let city = data["city"] as? String {
                    UserDefaults.standard.set(city, forKey: "userCity")
                }
                if let postalCode = data["postalCode"] as? String {
                    UserDefaults.standard.set(postalCode, forKey: "userPostalCode")
                }
                
                // Update last login timestamp in Firestore
                db.collection("users").document(user.uid).updateData([
                    "lastLogin": Timestamp(date: Date())
                ])
                
                // Mark authenticated (ContentView will handle showing PendingApprovalView if needed)
                isAuthenticated = true
                dismiss()
            }
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String = ""
    @State private var showMessage: Bool = false
    @State private var isSuccess: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding(.top, 60)
                
                Text("Reset Password")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your email address and we'll send you instructions to reset your password.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("your@email.com", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                .padding(.horizontal)
                
                Button(action: resetPassword) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Send Reset Link")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(email.isEmpty ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(email.isEmpty || isLoading)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isSuccess ? "Email Sent" : "Error", isPresented: $showMessage) {
                Button("OK") {
                    if isSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(message)
            }
        }
    }
    
    private func resetPassword() {
        guard !email.isEmpty else { return }
        
        isLoading = true
        
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            isLoading = false
            
            if let error = error {
                message = error.localizedDescription
                isSuccess = false
            } else {
                message = "Password reset instructions have been sent to \(email)"
                isSuccess = true
            }
            
            showMessage = true
        }
    }
}

// Preview
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(isAuthenticated: .constant(false))
    }
}
