# Admin Bootstrap Code - First Admin Setup

## Overview

To solve the "first admin problem" (who creates the first admin?), NeighborHub includes a **bootstrap admin code** feature. This allows the first community admin to grant themselves admin privileges during registration without needing Firebase Console access.

## Security Design

### The Bootstrap Code

**Default Code**: `NEIGHBORHUB_ADMIN_2025`

**Security Features**:
- Only works when **NO admins exist** in the system
- Automatically disabled after first admin is created
- Can be customized per deployment
- Should be shared only with trusted first admin
- Logged in Firestore for audit trail

### How It Works

1. **New Community Setup**: No admins exist yet
2. **First User Registers**: Completes onboarding normally
3. **Privacy Step**: Sees optional "Admin Setup" disclosure group
4. **Enters Code**: Inputs bootstrap admin code
5. **Validation**: System checks:
   - Is code correct?
   - Are there zero existing admins?
6. **Grant Access**: If valid, user document gets `isAdmin: true`
7. **Auto-Disable**: Future registrations won't accept the code

## Implementation Status

### ✅ Completed
- FirebaseManager method to check if admins exist
- Security rules allow user creation with isAdmin field
- Documentation created

### ⏳ Optional Enhancement (Not Critical)
- UI in OnboardingView privacy step
- Code validation logic
- Audit logging

### Current Workaround

**Manual Firebase Console Setup** (Recommended):
Since this feature is optional UI sugar, use the manual method documented in `ADMIN_SETUP_GUIDE.md`:

1. First user completes registration normally
2. Admin opens Firebase Console
3. Navigates to Firestore → users → {user's UID}
4. Adds field: `isAdmin: true`
5. Done - user becomes first admin

## Future Implementation (If Needed)

### Add to PrivacyConsentStepView

```swift
// Add to OnboardingData
var adminSetupCode: String = ""

// Add to PrivacyConsentStepView
DisclosureGroup("🔐 Admin Setup (First Admin Only)") {
    VStack(alignment: .leading, spacing: 8) {
        Text("If you're setting up a new community...")
            .font(.caption)
            .foregroundColor(.secondary)
        
        SecureField("Admin Bootstrap Code", text: $data.adminSetupCode)
            .textFieldStyle(.roundedBorder)
            .autocapitalization(.allCharacters)
        
        Text("Leave blank if you're not the first admin.")
            .font(.caption2)
            .foregroundColor(.orange)
    }
}
```

### Add to FirebaseManager

```swift
/// Check if any admins exist in the system
func adminExists(completion: @escaping (Bool) -> Void) {
    db.collection("users")
        .whereField("isAdmin", isEqualTo: true)
        .limit(to: 1)
        .getDocuments { snapshot, error in
            completion(snapshot?.documents.isEmpty == false)
        }
}

/// Validate bootstrap code and grant admin if valid
func validateBootstrapCode(
    _ code: String,
    forUser uid: String,
    completion: @escaping (Result<Bool, Error>) -> Void
) {
    let correctCode = "NEIGHBORHUB_ADMIN_2025"
    
    guard code.uppercased() == correctCode else {
        completion(.success(false))
        return
    }
    
    // Check if admins already exist
    adminExists { exists in
        if exists {
            // Code disabled - admins already exist
            print("⚠️ Bootstrap code rejected: admins already exist")
            completion(.success(false))
        } else {
            // Grant admin access
            self.db.collection("users").document(uid).updateData([
                "isAdmin": true,
                "isCommittee": true,
                "adminGrantedVia": "bootstrap_code",
                "adminGrantedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Bootstrap admin created: \(uid)")
                    completion(.success(true))
                }
            }
        }
    }
}
```

### Add to submitRegistration()

```swift
// After user profile is created...
if !data.adminSetupCode.isEmpty {
    FirebaseManager.shared.validateBootstrapCode(
        data.adminSetupCode,
        forUser: user.uid
    ) { result in
        switch result {
        case .success(let granted):
            if granted {
                print("✅ Admin access granted via bootstrap code")
                UserDefaults.standard.set(true, forKey: "userIsAdmin")
            } else {
                print("⚠️ Invalid or expired bootstrap code")
            }
        case .failure(let error):
            print("❌ Bootstrap code validation error: \(error)")
        }
    }
}
```

## Alternative: Environment Variable

For production deployments, consider storing the bootstrap code in Firebase Remote Config or app environment:

```swift
// Config.swift
struct BootstrapConfig {
    static var adminCode: String {
        // Read from Firebase Remote Config or Info.plist
        return Bundle.main.object(forInfoDictionaryKey: "ADMIN_BOOTSTRAP_CODE") as? String
            ?? "NEIGHBORHUB_ADMIN_2025"
    }
}
```

## Security Considerations

### ✅ Safe Practices
- Change default code for production
- Share code only via secure channel (Signal, in-person)
- Use code only once (first admin)
- Delete/rotate code after use
- Monitor Firestore for unauthorized admin creations

### ⚠️ Risks
- If code leaks, anyone can become first admin
- No rate limiting on validation attempts
- Code stored in app binary (can be extracted)

### Mitigations
- Auto-disable after first admin created (primary defense)
- Use temporary code valid for limited time
- Require email verification before admin grant
- Send alert email when admin created
- Audit log all admin creations

## Recommendation

**For Now**: Use manual Firebase Console method (documented in `ADMIN_SETUP_GUIDE.md`)

**For Future**: Implement bootstrap code UI if:
- Community admins don't have Firebase Console access
- Multiple communities deployed (can't manually configure each)
- Want simpler onboarding for non-technical admins

## Testing

If implementing bootstrap code feature:

1. **Test Valid Code**:
   - Register with code
   - Verify `isAdmin: true` in Firestore
   - Confirm admin panel appears

2. **Test Code Disabled**:
   - Create first admin
   - Register new user with code
   - Verify code rejected
   - Verify `isAdmin: false`

3. **Test Invalid Code**:
   - Register with wrong code
   - Verify `isAdmin: false`
   - Verify no error shown (security)

4. **Test Security**:
   - Attempt brute force
   - Check rate limiting
   - Verify logging

---

**Status**: Documentation only - feature not implemented in UI  
**Priority**: Low (manual method works well)  
**Complexity**: Low (2 hours to implement)
