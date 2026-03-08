import SwiftUI
import FirebaseAuth

/// Welcome screen shown to unauthenticated users with options to sign in or sign up
struct AuthWelcomeView: View {
    @Binding var isAuthenticated: Bool
    @State private var showLogin = false
    @State private var showOnboarding = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.accentColor.opacity(0.3),
                    Color.accentColor.opacity(0.1),
                    Color(.systemBackground)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App Icon and Branding
                VStack(spacing: 20) {
                    Image(systemName: "house.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.accentColor)
                    
                    Text("NeighborHub")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    
                    Text("Connect with your community")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Features List
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "message.fill", text: "Chat with neighbors")
                    FeatureRow(icon: "calendar", text: "Discover local events")
                    FeatureRow(icon: "cart.fill", text: "Buy & sell locally")
                    FeatureRow(icon: "shield.fill", text: "Neighborhood watch")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: { showOnboarding = true }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Sign Up")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { showLogin = true }) {
                        HStack {
                            Image(systemName: "person.fill")
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView(isAuthenticated: $isAuthenticated)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingViewWrapper(
                showingOnboarding: $showOnboarding,
                isAuthenticated: $isAuthenticated
            )
        }
    }
}

// Helper view for feature rows
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            Text(text)
                .font(.body)
        }
    }
}

// Wrapper to bridge OnboardingView with ContentView's auth flow
struct OnboardingViewWrapper: View {
    @Binding var showingOnboarding: Bool
    @Binding var isAuthenticated: Bool
    
    var body: some View {
        OnboardingView(
            showingOnboarding: $showingOnboarding,
            registerUser: { data, completion in
                // NOTE: This wrapper doesn't actually handle registration
                // The OnboardingView itself creates the Firebase Auth account
                // and the HomeView instance handles the Firestore document creation
                // This is just a pass-through to satisfy the closure signature
                
                // The auth state listener in ContentView will detect the sign-in
                // and automatically update isAuthenticated
                
                // Call completion to allow onboarding to proceed
                completion(true)
            }
        )
        .onChange(of: showingOnboarding) { newValue in
            // When onboarding dismisses, check if user is now authenticated
            if !newValue {
                // Give Firebase Auth a moment to register the sign-in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    #if canImport(FirebaseAuth)
                    if Auth.auth().currentUser != nil {
                        isAuthenticated = true
                    }
                    #endif
                }
            }
        }
    }
}

// Preview
struct AuthWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        AuthWelcomeView(isAuthenticated: .constant(false))
    }
}
