import SwiftUI
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

/// Temporary debug view for testing OneSignal external user ID setup
struct OneSignalDebugView: View {
    @State private var statusMessage = "Tap 'Force Login' to retry OneSignal authentication"
    @State private var lastCheckTime: Date?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("OneSignal Debug Panel")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Status:")
                    .font(.headline)
                
                Text(statusMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                if let checkTime = lastCheckTime {
                    Text("Last checked: \(checkTime, style: .time)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            VStack(spacing: 12) {
                Button(action: {
                    forceLogin()
                }) {
                    Label("Force Login with Firebase UID", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    checkStatus()
                }) {
                    Label("Check Current Status", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func forceLogin() {
        statusMessage = "🔄 Attempting to login with Firebase UID..."
        lastCheckTime = Date()
        
        #if canImport(FirebaseAuth)
        guard let currentUser = Auth.auth().currentUser else {
            statusMessage = "❌ No Firebase user logged in. Please sign in first."
            return
        }
        
        OneSignalManager.shared.forceLoginWithFirebaseUser()
        
        // Wait 2 seconds for the retry logic to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            checkStatus()
        }
        #else
        statusMessage = "❌ Firebase not available"
        #endif
    }
    
    private func checkStatus() {
        lastCheckTime = Date()
        
        #if canImport(OneSignalFramework)
        let externalId = OneSignal.User.externalId ?? "none"
        let pushId = OneSignal.User.pushSubscription.id ?? "none"
        let token = OneSignal.User.pushSubscription.token ?? "none"
        let optedIn = OneSignal.User.pushSubscription.optedIn
        
        if externalId != "none" {
            statusMessage = """
            ✅ SUCCESS!
            External ID: \(externalId)
            Push ID: \(pushId)
            Token: \(token.prefix(20))...
            Opted In: \(optedIn)
            """
        } else if pushId != "none" {
            statusMessage = """
            ⚠️ PARTIAL SETUP
            External ID: NOT SET ❌
            Push ID: \(pushId)
            Token: \(token.prefix(20))...
            Opted In: \(optedIn)
            
            Try 'Force Login' button
            """
        } else {
            statusMessage = """
            ❌ NOT CONFIGURED
            No push subscription found.
            Check network connection and APNs setup.
            """
        }
        #else
        statusMessage = "❌ OneSignal SDK not available"
        #endif
        
        // Also log to console
        OneSignalManager.shared.logSubscriptionStatus()
    }
}

#Preview {
    OneSignalDebugView()
}
