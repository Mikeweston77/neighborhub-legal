import SwiftUI
import PhotosUI

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

// MARK: - Onboarding Data Model
struct OnboardingData {
    var firstName: String = ""
    var surname: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var phoneNumber: String = ""
    var street: String = ""
    var suburb: String = ""
    var city: String = ""
    var postalCode: String = ""
    var emergencyContactName: String = ""
    var emergencyContactPhone: String = ""
    var emergencyContactRelationship: String = ""
    var profileImage: UIImage?
    var shareWithCommunity: Bool = true
    var shareWithCommittee: Bool = true
    var receiveNotifications: Bool = true
    var wellnessOptIn: Bool = true
}

// MARK: - Main Onboarding View
struct OnboardingView: View {
    @Binding var showingOnboarding: Bool
    var registerUser: (OnboardingData, @escaping (Bool) -> Void) -> Void
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var onboardingData = OnboardingData()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Bar
                if currentStep != .welcome {
                    OnboardingProgressBar(currentStep: currentStep)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Content
                TabView(selection: $currentStep) {
                    WelcomeStepView(data: $onboardingData, nextAction: { currentStep = .personalInfo })
                        .tag(OnboardingStep.welcome)
                    
                    PersonalInfoStepView(data: $onboardingData, nextAction: { currentStep = .password }, backAction: { currentStep = .welcome })
                        .tag(OnboardingStep.personalInfo)
                    
                    PasswordStepView(data: $onboardingData, nextAction: { currentStep = .location }, backAction: { currentStep = .personalInfo })
                        .tag(OnboardingStep.password)
                    
                    LocationStepView(data: $onboardingData, nextAction: { currentStep = .emergencyContact }, backAction: { currentStep = .password })
                        .tag(OnboardingStep.location)
                    
                    EmergencyContactStepView(data: $onboardingData, nextAction: { currentStep = .profilePhoto }, backAction: { currentStep = .location })
                        .tag(OnboardingStep.emergencyContact)
                    
                    ProfilePhotoStepView(data: $onboardingData, nextAction: { currentStep = .privacy }, backAction: { currentStep = .emergencyContact })
                        .tag(OnboardingStep.profilePhoto)
                    
                    PrivacyConsentStepView(
                        data: $onboardingData,
                        isSubmitting: $isSubmitting,
                        errorMessage: $errorMessage,
                        finishAction: {
                            submitRegistration()
                        },
                        backAction: { currentStep = .profilePhoto }
                    )
                    .tag(OnboardingStep.privacy)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
            }
            
            // Loading overlay
            if isSubmitting {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Creating your account...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
    }
    
    private func submitRegistration() {
        guard !isSubmitting else { return }
        
        // Validate required fields
        guard !onboardingData.firstName.isEmpty,
              !onboardingData.surname.isEmpty,
              !onboardingData.email.isEmpty,
              !onboardingData.password.isEmpty else {
            errorMessage = "Please complete all required fields"
            return
        }
        
        // Validate email format
        guard isValidEmail(onboardingData.email) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        
        // Validate password requirements
        guard onboardingData.password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            return
        }
        
        guard onboardingData.password == onboardingData.confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        
        // Create Firebase Auth account first
        FirebaseManager.shared.createUser(email: onboardingData.email, password: onboardingData.password) { result in
            switch result {
            case .success(let user):
                print("✅ Firebase Auth account created with UID: \(user.uid)")
                // Store UID and initial verification status in UserDefaults
                UserDefaults.standard.set(user.uid, forKey: "userUID")
                UserDefaults.standard.set(self.onboardingData.email, forKey: "userEmail")
                UserDefaults.standard.set(self.onboardingData.firstName, forKey: "userName")
                UserDefaults.standard.set(false, forKey: "userIsVerified") // New users are unverified
                
                // Save all data to AppStorage immediately
                UserDefaults.standard.set(self.onboardingData.firstName, forKey: "userName")
                UserDefaults.standard.set(self.onboardingData.surname, forKey: "userSurname")
                UserDefaults.standard.set(self.onboardingData.phoneNumber, forKey: "userCell")
                UserDefaults.standard.set(self.onboardingData.street, forKey: "userStreet")
                UserDefaults.standard.set(self.onboardingData.suburb, forKey: "userSuburb")
                UserDefaults.standard.set(self.onboardingData.city, forKey: "userCity")
                UserDefaults.standard.set(self.onboardingData.postalCode, forKey: "userPostalCode")
                UserDefaults.standard.set(self.onboardingData.emergencyContactName, forKey: "emergencyContactName")
                UserDefaults.standard.set(self.onboardingData.emergencyContactPhone, forKey: "emergencyContactPhone")
                UserDefaults.standard.set(self.onboardingData.emergencyContactRelationship, forKey: "emergencyContactRelationship")
                
                // Create Firestore document directly
                self.createFirestoreDocument(uid: user.uid) { firestoreSuccess in
                    // Also call the parent's registerUser callback (for HomeView compatibility)
                    self.registerUser(self.onboardingData) { _ in
                        DispatchQueue.main.async {
                            self.isSubmitting = false
                            if firestoreSuccess {
                                print("✅ Registration complete - dismissing onboarding")
                                self.showingOnboarding = false
                            } else {
                                print("⚠️ Registration partially failed - showing error")
                                self.errorMessage = "Profile creation failed. Please check your network connection and try again."
                            }
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // Create Firestore document with all onboarding data
    private func createFirestoreDocument(uid: String, completion: @escaping (Bool) -> Void) {
        print("🔍 OnboardingView: Creating Firestore document for UID: \(uid)")
        print("   Name: \(onboardingData.firstName) \(onboardingData.surname)")
        print("   Email: \(onboardingData.email)")
        print("   Phone: \(onboardingData.phoneNumber)")
        print("   Address: \(onboardingData.street), \(onboardingData.suburb)")
        
        // Upload profile image first if provided
        if let profileImage = onboardingData.profileImage {
            uploadProfileImage(profileImage, uid: uid) { imageURL in
                self.createFirestoreUser(uid: uid, profileImageURL: imageURL, completion: completion)
            }
        } else {
            createFirestoreUser(uid: uid, profileImageURL: nil, completion: completion)
        }
    }
    
    // Upload profile image to Firebase Storage
    private func uploadProfileImage(_ image: UIImage, uid: String, completion: @escaping (String?) -> Void) {
        #if canImport(FirebaseStorage)
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("❌ Failed to convert image to JPEG")
            completion(nil)
            return
        }
        
        let storageRef = Storage.storage().reference()
        let profileRef = storageRef.child("users/\(uid)/profile/avatar.jpg")
        
        profileRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                print("❌ Failed to upload profile image: \(error)")
                completion(nil)
                return
            }
            
            profileRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Failed to get download URL: \(error)")
                    completion(nil)
                } else if let downloadURL = url?.absoluteString {
                    print("✅ Profile image uploaded: \(downloadURL)")
                    
                    // Cache the profile image locally using ImageCacheManager
                    if let imageData = image.jpegData(compressionQuality: 0.7) {
                        if let localPath = try? ImageCacheManager.shared.saveData(imageData, forMessage: UUID()) {
                            print("✅ Profile image cached locally: \(localPath)")
                        }
                    }
                    
                    // Store profile image URL in UserDefaults
                    UserDefaults.standard.set(downloadURL, forKey: "profileImageURL")
                    
                    completion(downloadURL)
                } else {
                    completion(nil)
                }
            }
        }
        #else
        completion(nil)
        #endif
    }
    
    // Create Firestore user document
    private func createFirestoreUser(uid: String, profileImageURL: String?, completion: @escaping (Bool) -> Void) {
        FirebaseManager.shared.createOrUpdateUserWithAuth(
            firstName: onboardingData.firstName,
            lastName: onboardingData.surname,
            email: onboardingData.email,
            phoneNumber: onboardingData.phoneNumber.isEmpty ? nil : onboardingData.phoneNumber,
            street: onboardingData.street.isEmpty ? nil : onboardingData.street,
            suburb: onboardingData.suburb.isEmpty ? nil : onboardingData.suburb,
            city: onboardingData.city.isEmpty ? nil : onboardingData.city,
            postalCode: onboardingData.postalCode.isEmpty ? nil : onboardingData.postalCode,
            emergencyContactName: onboardingData.emergencyContactName.isEmpty ? nil : onboardingData.emergencyContactName,
            emergencyContactPhone: onboardingData.emergencyContactPhone.isEmpty ? nil : onboardingData.emergencyContactPhone,
            emergencyContactRelationship: onboardingData.emergencyContactRelationship.isEmpty ? nil : onboardingData.emergencyContactRelationship,
            profileImageURL: profileImageURL,
            shareWithCommunity: onboardingData.shareWithCommunity,
            shareWithCommittee: onboardingData.shareWithCommittee
        ) { result in
            switch result {
            case .success(let uid):
                print("✅ Firestore document created successfully: users/\(uid)")
                completion(true)
            case .failure(let error):
                print("❌ Failed to create Firestore document: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
}

// MARK: - Onboarding Steps
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case personalInfo = 1
    case password = 2
    case location = 3
    case emergencyContact = 4
    case profilePhoto = 5
    case privacy = 6
    
    var progress: Double {
        Double(rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
}

// MARK: - Progress Bar
struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * currentStep.progress, height: 4)
                        .cornerRadius(2)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .frame(height: 4)
            
            Text("Step \(currentStep.rawValue) of \(OnboardingStep.allCases.count - 1)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Welcome Step
struct WelcomeStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "house.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 8) {
                Text("Welcome to NeighborHub!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Your community connection platform")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureHighlight(
                    icon: "exclamationmark.triangle.fill",
                    title: "Emergency Alerts",
                    description: "Instantly notify neighbors of urgent situations"
                )
                
                FeatureHighlight(
                    icon: "message.circle.fill",
                    title: "Community Chat",
                    description: "Connect and communicate with your community in real-time"
                )
                
                FeatureHighlight(
                    icon: "bag.circle.fill",
                    title: "Marketplace",
                    description: "Buy, sell, and share resources within your neighborhood"
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: nextAction) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
    }
}

// MARK: - Personal Info Step
struct PersonalInfoStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    let backAction: () -> Void
    @FocusState private var focusedField: Field?
    
    enum Field {
        case firstName, surname, email, phone
    }
    
    var isValid: Bool {
        !data.firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !data.surname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !data.email.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Personal Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Let's start with your basic details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Name *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter your first name", text: $data.firstName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.givenName)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .surname }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Surname *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter your surname", text: $data.surname)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.familyName)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .surname)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email Address *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("you@example.com", text: $data.email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .phone }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phone Number (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("072 123 4567", text: $data.phoneNumber)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focusedField, equals: .phone)
                            .onChange(of: data.phoneNumber) { _, newValue in
                                data.phoneNumber = formatPhoneNumber(newValue)
                            }
                    }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $data.wellnessOptIn) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Opt-in to Daily Wellness Check-ins")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    Text("You’ll receive a daily prompt to confirm your wellbeing. If you don’t respond or request help, your emergency contact or committee may be notified. You can change this setting later in your profile.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                }
                .padding(.horizontal)
                
                Text("* Required fields")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: backAction) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        focusedField = nil
                        nextAction()
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!isValid)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func formatPhoneNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        let limited = String(digits.prefix(10))
        
        if limited.count <= 3 {
            return limited
        } else if limited.count <= 6 {
            let prefix = limited.prefix(3)
            let middle = limited.dropFirst(3)
            return "\(prefix) \(middle)"
        } else {
            let prefix = limited.prefix(3)
            let middle = limited.dropFirst(3).prefix(3)
            let suffix = limited.dropFirst(6)
            return "\(prefix) \(middle) \(suffix)"
        }
    }
}

// MARK: - Password Step
struct PasswordStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    let backAction: () -> Void
    @FocusState private var focusedField: Field?
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    
    enum Field {
        case password, confirmPassword
    }
    
    var passwordStrength: PasswordStrength {
        let password = data.password
        if password.isEmpty { return .none }
        if password.count < 8 { return .weak }
        
        var strength = 0
        if password.count >= 8 { strength += 1 }
        if password.count >= 12 { strength += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { strength += 1 }
        if password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil { strength += 1 }
        
        if strength <= 2 { return .weak }
        if strength <= 4 { return .medium }
        return .strong
    }
    
    enum PasswordStrength {
        case none, weak, medium, strong
        
        var color: Color {
            switch self {
            case .none: return .gray
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }
        
        var text: String {
            switch self {
            case .none: return ""
            case .weak: return "Weak"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }
    }
    
    var isValid: Bool {
        !data.password.isEmpty &&
        data.password.count >= 8 &&
        data.password == data.confirmPassword
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Create Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Choose a strong password to secure your account")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if showPassword {
                                TextField("Enter password", text: $data.password)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .password)
                            } else {
                                SecureField("Enter password", text: $data.password)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .password)
                            }
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmPassword }
                        
                        // Password strength indicator
                        if !data.password.isEmpty {
                            HStack {
                                ForEach(0..<3) { index in
                                    Rectangle()
                                        .fill(index < strengthBars ? passwordStrength.color : Color.gray.opacity(0.3))
                                        .frame(height: 4)
                                        .cornerRadius(2)
                                }
                            }
                            .padding(.top, 4)
                            
                            Text("Strength: \(passwordStrength.text)")
                                .font(.caption)
                                .foregroundColor(passwordStrength.color)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm Password *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if showConfirmPassword {
                                TextField("Confirm password", text: $data.confirmPassword)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .confirmPassword)
                            } else {
                                SecureField("Confirm password", text: $data.confirmPassword)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .confirmPassword)
                            }
                            
                            Button(action: { showConfirmPassword.toggle() }) {
                                Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .submitLabel(.done)
                        
                        // Password match indicator
                        if !data.confirmPassword.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: data.password == data.confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(data.password == data.confirmPassword ? .green : .red)
                                Text(data.password == data.confirmPassword ? "Passwords match" : "Passwords do not match")
                                    .font(.caption)
                                    .foregroundColor(data.password == data.confirmPassword ? .green : .red)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password Requirements:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        PasswordRequirement(met: data.password.count >= 8, text: "At least 8 characters")
                        PasswordRequirement(met: data.password.rangeOfCharacter(from: .uppercaseLetters) != nil, text: "One uppercase letter")
                        PasswordRequirement(met: data.password.rangeOfCharacter(from: .lowercaseLetters) != nil, text: "One lowercase letter")
                        PasswordRequirement(met: data.password.rangeOfCharacter(from: .decimalDigits) != nil, text: "One number")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: backAction) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        focusedField = nil
                        nextAction()
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!isValid)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var strengthBars: Int {
        switch passwordStrength {
        case .none: return 0
        case .weak: return 1
        case .medium: return 2
        case .strong: return 3
        }
    }
}

// Helper view for password requirements
struct PasswordRequirement: View {
    let met: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? .green : .secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(met ? .primary : .secondary)
        }
    }
}

// MARK: - Location Step
struct LocationStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    let backAction: () -> Void
    @FocusState private var focusedField: Field?
    
    enum Field {
        case street, suburb, city, postal
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "map.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Your Location")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Help us connect you with your neighborhood")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Street Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("123 Main Street", text: $data.street)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.streetAddressLine1)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .street)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .suburb }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suburb")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Your Suburb", text: $data.suburb)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.addressCityAndState)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .suburb)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .city }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("City")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Your City", text: $data.city)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.addressCity)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .city)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .postal }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Postal Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1234", text: $data.postalCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .postal)
                            .onChange(of: data.postalCode) { _, newValue in
                                data.postalCode = String(newValue.filter { $0.isNumber }.prefix(4))
                            }
                    }
                }
                .padding(.horizontal)
                
                Text("This helps us show you relevant local content")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: backAction) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        focusedField = nil
                        nextAction()
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Emergency Contact Step
struct EmergencyContactStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    let backAction: () -> Void
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, phone, relationship
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Emergency Contact")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Someone we can reach in case of emergency")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contact Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("John Doe", text: $data.emergencyContactName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.name)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .phone }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contact Phone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("072 123 4567", text: $data.emergencyContactPhone)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focusedField, equals: .phone)
                            .onChange(of: data.emergencyContactPhone) { _, newValue in
                                data.emergencyContactPhone = formatPhoneNumber(newValue)
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Relationship")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Spouse, Parent, Sibling, etc.", text: $data.emergencyContactRelationship)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.words)
                            .focused($focusedField, equals: .relationship)
                            .submitLabel(.done)
                    }
                }
                .padding(.horizontal)
                
                Text("Optional but highly recommended for safety")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: backAction) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        focusedField = nil
                        nextAction()
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func formatPhoneNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        let limited = String(digits.prefix(10))
        
        if limited.count <= 3 {
            return limited
        } else if limited.count <= 6 {
            let prefix = limited.prefix(3)
            let middle = limited.dropFirst(3)
            return "\(prefix) \(middle)"
        } else {
            let prefix = limited.prefix(3)
            let middle = limited.dropFirst(3).prefix(3)
            let suffix = limited.dropFirst(6)
            return "\(prefix) \(middle) \(suffix)"
        }
    }
}

// MARK: - Profile Photo Step
struct ProfilePhotoStepView: View {
    @Binding var data: OnboardingData
    let nextAction: () -> Void
    let backAction: () -> Void
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                if let image = data.profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 120))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                Text("Profile Photo")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Add a photo so your neighbors can recognize you")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            
            VStack(spacing: 12) {
                Button(action: {
                    imagePickerSource = .camera
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    imagePickerSource = .photoLibrary
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                        Text("Choose from Library")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(10)
                }
                
                if data.profileImage != nil {
                    Button(action: {
                        data.profileImage = nil
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Remove Photo")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("Optional - you can add this later in settings")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: backAction) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
                
                Button(action: nextAction) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
        .sheet(isPresented: $showImagePicker) {
            ProfileImagePicker(image: $data.profileImage, sourceType: imagePickerSource)
        }
    }
}

// MARK: - Privacy Consent Step
struct PrivacyConsentStepView: View {
    @Binding var data: OnboardingData
    @Binding var isSubmitting: Bool
    @Binding var errorMessage: String?
    let finishAction: () -> Void
    let backAction: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Privacy & Permissions")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Control how your information is shared")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    Toggle(isOn: $data.shareWithCommunity) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(.accentColor)
                                Text("Share with Community")
                                    .font(.headline)
                            }
                            Text("Allow other verified neighbors to see your profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    Toggle(isOn: $data.shareWithCommittee) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.accentColor)
                                Text("Share with Committee")
                                    .font(.headline)
                            }
                            Text("Allow committee members to access your contact details")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    Toggle(isOn: $data.receiveNotifications) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.accentColor)
                                Text("Push Notifications")
                                    .font(.headline)
                            }
                            Text("Receive alerts for emergencies and community updates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                VStack(spacing: 8) {
                    Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: backAction) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                    
                    Button(action: finishAction) {
                        HStack {
                            Text("Complete Registration")
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Feature Highlight Component
struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
    }
}

// MARK: - Profile Image Picker (Onboarding-specific)
struct ProfileImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImagePicker
        
        init(_ parent: ProfileImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
