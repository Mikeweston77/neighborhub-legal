# Subscription Tracker Integration Guide

## Overview
The subscription tracker allows admin/committee members to track annual subscription payments for all community members year-on-year.

## Files Created
1. **SubscriptionModels.swift** - Data models for subscriptions and payments
2. **SubscriptionTrackerView.swift** - Main tracking interface
3. **SubscriptionDetailViews.swift** - Detail views for recording payments and viewing history

## Features Implemented

### Main View (`SubscriptionTrackerView`)
- ✅ Admin/committee-only access control
- ✅ Statistics dashboard (Total, Paid, Unpaid, Overdue 2+ years)
- ✅ Filter pills (All, Paid This Year, Unpaid, Overdue)
- ✅ Search by name or address
- ✅ Member cards showing payment status
- ✅ Quick actions (tap to view details, context menu for payment)

### Payment Recording (`AddPaymentView`)
- ✅ Record payment for specific year
- ✅ Enter amount, date, payment method (Cash/EFT/Card/Other)
- ✅ Optional receipt number and notes
- ✅ Auto-tracks who recorded the payment
- ✅ Validates amount before saving

### Member Details (`MemberDetailView`)
- ✅ View full member information
- ✅ Payment status summary
- ✅ Complete payment history
- ✅ Quick access to record new payment

## Integration Steps

### Step 1: Add Navigation Link to WatchView

Add this button in the admin section of `WatchView.swift` (around line 1329 where `if isAdmin {` starts):

```swift
if isAdmin {
    VStack(spacing: 14) {
        HStack(spacing: 14) {
            // Existing buttons...
            WatchGlassCard(
                gradient: Gradient(colors: [
                    Color.orange.opacity(0.18), Color.red.opacity(0.10),
                ]),
                borderGradient: Gradient(colors: [
                    Color.white.opacity(0.7), Color.orange.opacity(0.2),
                ]),
                shadowColor1: Color.orange.opacity(0.18),
                shadowColor2: Color.red.opacity(0.10),
                text: "Add Incident",
                textColor: .primary,
                action: { showIncidentSheet = true },
                height: 48
            )
            
            // NEW: Add this button
            WatchGlassCard(
                gradient: Gradient(colors: [
                    Color.green.opacity(0.18), Color.blue.opacity(0.10),
                ]),
                borderGradient: Gradient(colors: [
                    Color.white.opacity(0.7), Color.green.opacity(0.2),
                ]),
                shadowColor1: Color.green.opacity(0.18),
                shadowColor2: Color.blue.opacity(0.10),
                text: "Subscriptions",
                textColor: .primary,
                action: { showSubscriptionTracker = true },
                height: 48
            )
            
            // Rest of existing buttons...
        }
    }
}
```

### Step 2: Add State Variable

Add this near the other `@State` variables in `WatchView` (around line 415):

```swift
@State private var showWatchSettings = false
@State private var showSubscriptionTracker = false  // ADD THIS
```

### Step 3: Add Full Screen Cover

Add this after the other `.fullScreenCover` modifiers (around line 1200):

```swift
.fullScreenCover(isPresented: $showWatchSettings) {
    WatchSettingsView()
}
.fullScreenCover(isPresented: $showSubscriptionTracker) {
    NavigationView {
        SubscriptionTrackerView()
    }
}
```

## Data Storage

### Current Implementation
- Uses `UserDefaults` for local storage with key: `"subscriptionsData"`
- Data persists across app launches
- Stored as JSON-encoded array of `MemberSubscription` objects

### Firebase Integration (TODO)
The code includes placeholders for Firebase integration. To implement:

1. Add Firestore collection: `subscriptions`
2. Document structure:
```json
{
  "id": "UUID",
  "memberUID": "Firebase Auth UID",
  "memberName": "John",
  "memberSurname": "Doe",
  "address": "123 Main St",
  "email": "john@example.com",
  "phone": "+27123456789",
  "paymentHistory": [
    {
      "id": "UUID",
      "year": 2024,
      "amount": 500.00,
      "paymentDate": "2024-01-15T10:00:00Z",
      "paymentMethod": "EFT",
      "receiptNumber": "REC-001",
      "notes": "Paid via bank transfer",
      "recordedBy": "admin_uid",
      "recordedByName": "Admin User"
    }
  ],
  "currentYear": 2024,
  "isPaidCurrentYear": true
}
```

3. Update `loadSubscriptions()` in `SubscriptionTrackerView.swift`:
```swift
private func loadSubscriptions() {
    isLoading = true
    
    let db = Firestore.firestore()
    db.collection("subscriptions").addSnapshotListener { snapshot, error in
        guard let documents = snapshot?.documents else {
            print("Error fetching subscriptions: \\(error?.localizedDescription ?? "Unknown")")
            isLoading = false
            return
        }
        
        var loadedSubscriptions: [MemberSubscription] = []
        for doc in documents {
            if let subscription = try? doc.data(as: MemberSubscription.self) {
                loadedSubscriptions.append(subscription)
            }
        }
        
        DispatchQueue.main.async {
            self.subscriptions = loadedSubscriptions
            self.isLoading = false
        }
    }
}
```

4. Update `saveSubscriptions()` to save to Firestore:
```swift
private func saveSubscriptions(_ subscription: MemberSubscription) {
    let db = Firestore.firestore()
    do {
        try db.collection("subscriptions")
            .document(subscription.id.uuidString)
            .setData(from: subscription, merge: true)
    } catch {
        print("Error saving subscription: \\(error)")
    }
}
```

## Usage Workflow

1. **Admin logs in** → Sees "Subscriptions" button in Watch tab
2. **Clicks Subscriptions** → Opens tracker with all members
3. **Views statistics** → Quick overview of payment status
4. **Filters members** → Can filter by Paid/Unpaid/Overdue
5. **Searches** → Type name or address to find specific member
6. **Records payment**:
   - Tap member card → View details
   - Click "+" or long-press → "Record Payment"
   - Enter payment details
   - Save
7. **Views history** → Tap any member to see complete payment history

## Security

- Only users with `userIsAdmin` or `userIsCommittee` can access
- Non-admin users see "Admin Access Only" message
- All payment records include audit trail (who recorded it)

## Future Enhancements

### Short Term
- [ ] Export to CSV/PDF for reporting
- [ ] Email reminders for unpaid subscriptions
- [ ] Bulk import members from CSV
- [ ] Payment receipt generation

### Long Term
- [ ] Integration with payment gateways
- [ ] Automatic payment confirmation via bank feeds
- [ ] Annual subscription amount configuration
- [ ] Multi-year payment discounts
- [ ] Payment statistics and trends

## Testing Checklist

- [ ] Non-admin users cannot access feature
- [ ] Admin can view subscription list
- [ ] Can record payment for member
- [ ] Payment appears in member history
- [ ] Filters work correctly
- [ ] Search finds members by name/address
- [ ] Statistics update when payments are recorded
- [ ] Data persists after app restart
- [ ] Can view member details
- [ ] Payment validation prevents invalid amounts

## Support

For questions or issues, contact the development team or refer to:
- `SubscriptionModels.swift` for data structure
- `SubscriptionTrackerView.swift` for main UI logic
- `SubscriptionDetailViews.swift` for payment recording

