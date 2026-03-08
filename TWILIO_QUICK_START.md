# Twilio Emergency WhatsApp - Quick Start Guide

## ⚡ Fast Setup (5 minutes)

### Step 1: Install Dependencies (1 min)

```bash
# Install Node.js (if not installed)
brew install node

# Install npm packages
cd "/Users/mikeweston/Desktop/Waterfall 3 V1.07/functions"
npm install
```

### Step 2: Create Twilio Account (2 min)

1. Go to https://www.twilio.com/try-twilio
2. Sign up (you get $15 credit free)
3. Go to WhatsApp Sandbox: https://console.twilio.com/us1/develop/sms/try-it-out/whatsapp-learn
4. Join sandbox with your phone:
   - Open WhatsApp
   - Send code to sandbox number (shown on screen)
   - Wait for "Connected!" message

### Step 3: Configure Firebase (1 min)

Get your credentials from Twilio Dashboard:
- **Account SID**: Starts with `AC` (on main dashboard)
- **Auth Token**: Click "Show" on dashboard
- **Sandbox Number**: `whatsapp:+14155238886`

```bash
cd "/Users/mikeweston/Desktop/Waterfall 3 V1.07"

firebase functions:config:set \
  twilio.account_sid="ACxxxxx" \
  twilio.auth_token="your_token" \
  twilio.whatsapp_number="whatsapp:+14155238886"
```

### Step 4: Deploy Functions (1 min)

```bash
firebase deploy --only functions:testTwilioWhatsApp,sendEmergencyWhatsApp
```

### Step 5: Test It! (30 seconds)

Add this button to any SwiftUI view:

```swift
Button("Test Emergency") {
    EmergencyRequestManager().testTwilioWhatsApp(
        toPhone: "+27793867472", // Replace with YOUR number that joined sandbox
        message: "🧪 Test - Twilio is working!"
    ) { success, message in
        print(success ? "✅ Sent!" : "❌ Failed: \(message ?? "")")
    }
}
```

Press button → WhatsApp message arrives in 2-5 seconds! 🎉

---

## 📱 Use in Your Emergency Flow

Replace your old WhatsApp code with:

```swift
// OLD (opens WhatsApp, manual send)
emergencyManager.openWhatsAppFallback(...)

// NEW (automatic sending, no manual action)
emergencyManager.sendEmergencyViaTwilio(
    type: .fire, // or .medical, .emergency
    name: userName,
    address: userAddress,
    cell: userPhone,
    emergencyContact: EmergencyRequestManager.RecipientInfo(
        name: "Emergency Control",
        phone: "+27793867472", // Your emergency number in E.164 format
        relationship: "Emergency Coordinator"
    ),
    description: description,
    metadata: ["buildingType": "Residential"],
    reportedDate: Date(),
    imageData: photoData
) { success, error in
    if success {
        // Show success alert
        showAlert(title: "✅ Emergency Sent", 
                  message: "WhatsApp alert sent automatically")
    } else {
        // Show error
        showAlert(title: "❌ Failed", message: error ?? "Unknown error")
    }
}
```

---

## 🧪 Common Test Scenarios

### Test 1: Basic Message

```swift
EmergencyRequestManager().testTwilioWhatsApp(
    toPhone: "+27793867472",
    message: "Test message"
) { success, _ in print(success ? "✅" : "❌") }
```

### Test 2: Fire Emergency

```swift
EmergencyRequestManager().sendEmergencyViaTwilio(
    type: .fire,
    name: "Test User",
    address: "123 Test St",
    cell: "+27123456789",
    emergencyContact: EmergencyRequestManager.RecipientInfo(
        phone: "+27793867472"
    ),
    description: "Test fire alert",
    metadata: ["buildingType": "Residential"],
    reportedDate: Date()
) { success, _ in print(success ? "✅" : "❌") }
```

### Test 3: Rate Limiting

Press emergency button twice within 60 seconds → Second press should fail with wait message.

---

## 🔧 Useful Commands

### View Logs
```bash
# Real-time function logs
firebase functions:log

# Specific function logs
firebase functions:log --only sendEmergencyWhatsApp
```

### Check Config
```bash
firebase functions:config:get
```

### Update Config
```bash
firebase functions:config:set twilio.account_sid="NEW_VALUE"
firebase deploy --only functions
```

### Redeploy Functions
```bash
# Specific functions
firebase deploy --only functions:sendEmergencyWhatsApp

# All functions
firebase deploy --only functions
```

---

## ⚠️ Troubleshooting

| Error | Solution |
|-------|----------|
| "npm not found" | Install Node.js: `brew install node` |
| "Twilio credentials not configured" | Run `firebase functions:config:set ...` |
| "Phone number must be E.164" | Use `+27793867472` format, not `0793867472` |
| "Cannot send to this number" | Recipient must join sandbox first |
| "Wait X seconds" | Rate limit active (wait or see code to adjust) |
| Functions deploy fails | Run `npm install` in `functions/` folder |

---

## 📊 Monitor Usage

### Twilio Console
- Messages sent: https://console.twilio.com/us1/monitor/logs/whatsapp
- Credit balance: Main dashboard
- Message status: Click message SID in logs

### Firebase Console
- Function invocations: https://console.firebase.google.com/project/_/functions
- Emergency logs: Firestore → `emergencies` collection
- Rate limits: Firestore → `emergencyRateLimit` collection

---

## 🚀 Go to Production

When ready for real WhatsApp Business:

1. **Request Access**: Twilio Console → WhatsApp → Request Access
2. **Verify Business**: Submit business documents, wait 1-2 days
3. **Create Templates**: Required for first message to new contacts
4. **Update Config**:
   ```bash
   firebase functions:config:set \
     twilio.whatsapp_number="whatsapp:+27XXXXXXXXXX"
   firebase deploy --only functions
   ```

---

## 📋 Checklist

- [ ] Node.js installed (`node --version`)
- [ ] npm packages installed (`cd functions && npm install`)
- [ ] Twilio account created
- [ ] WhatsApp sandbox joined
- [ ] Firebase config set (`firebase functions:config:get`)
- [ ] Functions deployed (`firebase deploy --only functions`)
- [ ] Test button added to app
- [ ] Test message received on phone
- [ ] Emergency flow updated to use `sendEmergencyViaTwilio()`
- [ ] Firestore rules deployed (`firebase deploy --only firestore:rules`)

---

## ✨ What You Get

✅ **Automatic WhatsApp sending** - No manual button press required  
✅ **Rate limiting** - Prevents spam (1 per 60 seconds)  
✅ **Push notifications** - Sender gets confirmation  
✅ **Firestore logging** - All emergencies tracked  
✅ **Photo support** - Auto-saves to photo library  
✅ **Error handling** - User-friendly error messages  
✅ **Fallback support** - Uses manual WhatsApp if Cloud Functions unavailable  

---

**Need more details?** See [TWILIO_EMERGENCY_SETUP_COMPLETE.md](TWILIO_EMERGENCY_SETUP_COMPLETE.md)
