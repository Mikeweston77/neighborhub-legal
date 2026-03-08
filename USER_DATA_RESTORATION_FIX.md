# User Data Restoration Fix

## Problem
When users sign back into the app, their emergency contact details and NeighborHub Watch credentials were not being restored to the user settings.

## Root Cause
The `fetchVerificationStatus()` function in `ContentView.swift` only fetched and restored three fields from Firestore:
- `verified` (bool)
- `isAdmin` (bool)
- `isCommittee` (bool)

It was **not** fetching:
- Emergency contact name, phone, relationship
- Watch username
- User profile data (firstName, lastName, email)
- Camera access status

## Solution Implemented

### Modified File: `NeighborHub/ContentView.swift`

Enhanced the `fetchVerificationStatus(uid:)` function to fetch and restore **ALL** user data from Firestore on sign-in:

```swift
// Now fetches and restores:
✅ Roles: verified, isAdmin, isCommittee, hasCameraAccess
✅ Profile: firstName, lastName, email, phone
✅ Address: street, suburb, city, postalCode
✅ Emergency contacts: emergencyContactName, emergencyContactPhone, emergencyContactRelationship
✅ Watch credential: watchCredential (watch username)
✅ Privacy settings: privacyShareWithCommunity, privacyShareWithCommittee
⚠️ Watch password: NOT restored (see "Watch Password Limitation" below)
```

All these fields are now:
1. **Fetched from Firestore** when user signs in
2. **Restored to UserDefaults** (which backs @AppStorage)
3. **Immediately available** in user settings UI

### Code Changes

**Before:**
```swift
let verified = data["verified"] as? Bool ?? false
let isAdmin = data["isAdmin"] as? Bool ?? false
let isCommittee = data["isCommittee"] as? Bool ?? false

DispatchQueue.main.async {
    self.isVerified = verified
    UserDefaults.standard.set(verified, forKey: "userIsVerified")
    UserDefaults.standard.set(isAdmin, forKey: "userIsAdmin")
    UserDefaults.standard.set(isCommittee, forKey: "userIsCommittee")
}
```

**After:**
```swift
// Fetch all user data from Firestore
let verified = data["verified"] as? Bool ?? false
let isAdmin = data["isAdmin"] as? Bool ?? false
let isCommittee = data["isCommittee"] as? Bool ?? false
let hasCameraAccess = data["cameraAccess"] as? Bool ?? false
let firstName = data["firstName"] as? String ?? ""
let lastName = data["lastName"] as? String ?? ""
let email = data["email"] as? String ?? ""
let phone = data["phone"] as? String ?? ""
let street = data["street"] as? String ?? ""
let suburb = data["suburb"] as? String ?? ""
let city = data["city"] as? String ?? ""
let postalCode = data["postalCode"] as? String ?? ""
let emName = data["emergencyContactName"] as? String ?? ""
let emPhone = data["emergencyContactPhone"] as? String ?? ""
let emRel = data["emergencyContactRelationship"] as? String ?? ""
let watchCred = data["watchCredential"] as? String ?? ""
let shareWithCommunity = data["privacyShareWithCommunity"] as? Bool ?? true
let shareWithCommittee = data["privacyShareWithCommittee"] as? Bool ?? true

// Restore ALL user data to local storage
DispatchQueue.main.async {
    self.isVerified = verified
    
    // Roles
    UserDefaults.standard.set(verified, forKey: "userIsVerified")
    UserDefaults.standard.set(isAdmin, forKey: "userIsAdmin")
    UserDefaults.standard.set(isCommittee, forKey: "userIsCommittee")
    UserDefaults.standard.set(hasCameraAccess, forKey: "userHasCameraAccess")
    
    // Profile
    if !firstName.isEmpty { UserDefaults.standard.set(firstName, forKey: "userName") }
    if !lastName.isEmpty { UserDefaults.standard.set(lastName, forKey: "userSurname") }
    if !email.isEmpty { UserDefaults.standard.set(email, forKey: "userEmail") }
    if !phone.isEmpty { UserDefaults.standard.set(phone, forKey: "userCell") }
    
    // Address
    if !street.isEmpty { UserDefaults.standard.set(street, forKey: "userStreet") }
    if !suburb.isEmpty { UserDefaults.standard.set(suburb, forKey: "userSuburb") }
    if !city.isEmpty { UserDefaults.standard.set(city, forKey: "userCity") }
    if !postalCode.isEmpty { UserDefaults.standard.set(postalCode, forKey: "userPostalCode") }
    
    // Emergency contacts
    if !emName.isEmpty { UserDefaults.standard.set(emName, forKey: "emergencyContactName") }
    if !emPhone.isEmpty { UserDefaults.standard.set(emPhone, forKey: "emergencyContactPhone") }
    if !emRel.isEmpty { UserDefaults.standard.set(emRel, forKey: "emergencyContactRelationship") }
    
    // Watch username
    if !watchCred.isEmpty { UserDefaults.standard.set(watchCred, forKey: "watchUsername") }
    
    // Privacy settings
    UserDefaults.standard.set(shareWithCommunity, forKey: "userPrivacyShareWithCommunity")
    UserDefaults.standard.set(shareWithCommittee, forKey: "userPrivacyShareWithCommittee")
    
    print("✅ User profile data restored to local storage")
}
```

## Watch Password Limitation

### Current Behavior
**Watch password is NOT stored in Firestore** - it's only stored locally in `@AppStorage("watchPassword")` (UserDefaults).

### Implications
- ✅ **Sign out and back in on same device**: Password persists (UserDefaults retained)
- ❌ **New device / app reinstall**: Password is lost (UserDefaults cleared)
- ❌ **iCloud sync across devices**: Password does NOT sync

### Security Rationale
Passwords should not be stored in plain text in cloud databases. Current implementation follows this principle.

### Recommended Solutions

#### Option 1: Use iOS Keychain (Most Secure)
- Store watch password in iOS Keychain
- Syncs across user's devices via iCloud Keychain
- Encrypted and secure
- Requires keychain access implementation

#### Option 2: Encrypted Firestore Storage
- Encrypt password before storing in Firestore
- Decrypt when retrieving
- Allows cross-device access
- Less secure than Keychain

#### Option 3: User Re-entry (Current)
- Users must re-enter watch password after app reinstall
- Most secure option
- Minor inconvenience for users

## Testing Checklist

Test these scenarios to verify the fix:

### ✅ Same Device Sign-in/Sign-out
1. User enters emergency contact and watch credentials
2. User signs out
3. User signs back in
4. **Expected**: All data restored (including watch password)

### ✅ New Device / Reinstall
1. User registers and enters all data on Device A
2. User installs app on Device B (or reinstalls on Device A)
3. User signs in
4. **Expected**: 
   - Emergency contacts restored ✅
   - Watch username restored ✅
   - Watch password needs re-entry ⚠️

### ✅ Firestore Data Verification
1. Check Firestore console: `users/{uid}` document
2. **Should contain**:
   - `firstName`, `lastName`, `email`, `phone`
   - `street`, `suburb`, `city`, `postalCode`
   - `emergencyContactName`, `emergencyContactPhone`, `emergencyContactRelationship`
   - `watchCredential` (username)
   - `verified`, `isAdmin`, `isCommittee`, `cameraAccess`
   - `privacyShareWithCommunity`, `privacyShareWithCommittee`
3. **Should NOT contain**: `watchPassword` (security best practice)

## Files Modified
- `NeighborHub/ContentView.swift` - Enhanced `fetchVerificationStatus()` function

## Files Analyzed
- `NeighborHub/Views/HomeView.swift` - Verified @AppStorage usage
- `NeighborHub/Views/WatchView.swift` - Verified @AppStorage usage
- `NeighborHub/Managers/FirebaseManager.swift` - Verified Firestore storage

## Status
✅ **COMPLETE** - All user data except watch password now restores on sign-in.

## Next Steps (Optional)
Consider implementing Keychain storage for watch password if cross-device password sync is required.
