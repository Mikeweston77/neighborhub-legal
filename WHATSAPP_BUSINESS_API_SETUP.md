# WhatsApp Business API Setup Guide for NeighborHub Emergency System

## 🚨 Current Limitations

**Important:** The current implementation uses **WhatsApp URL schemes** which:
- ❌ Opens WhatsApp with pre-filled message
- ❌ **Requires user to manually press "Send"**
- ❌ Cannot send messages automatically
- ✅ Works without any API setup
- ✅ Simple implementation

**To send WhatsApp messages automatically without user interaction**, you need the **WhatsApp Business API**.

---

## 📱 WhatsApp Business API Overview

### What It Enables:
- ✅ **Automated message sending** without user interaction
- ✅ Send messages programmatically from your server
- ✅ Message templates for emergencies
- ✅ Delivery receipts and read status
- ✅ 24/7 automated notifications

### Requirements:
1. **Facebook Business Account**
2. **WhatsApp Business API Access** (paid service)
3. **Backend server** to handle API requests
4. **Business verification** from Meta
5. **Message templates** pre-approved by WhatsApp

### Costs:
- **Setup:** Free (but requires business verification)
- **Per message:** Varies by country (South Africa: ~R0.50-1.50 per message)
- **API provider:** Cloud API (Meta) or BSP (Business Solution Provider) - some charge monthly fees

---

## 🎯 Recommended Architecture for NeighborHub

```
[iOS App] → [Firebase Cloud Function] → [WhatsApp Business API] → [Emergency Contacts]
    ↓
[Firebase Cloud Messaging] → [Push Notification to User's Device]
```

### Flow:
1. User presses emergency button in app
2. App sends emergency data to Firebase Cloud Function
3. Cloud Function:
   - Sends WhatsApp message via WhatsApp Business API
   - Sends push notification to user's device
   - Logs emergency to Firestore
4. Emergency contacts receive WhatsApp message automatically

---

## 📋 Step 1: WhatsApp Business API Setup

### Option A: Meta Cloud API (Recommended for Small-Medium Apps)

#### 1. Create Facebook Business Account
- Go to https://business.facebook.com
- Click **Create Account**
- Fill in business details
- Verify your business (requires business documents)

#### 2. Set Up WhatsApp Business API
- Go to https://developers.facebook.com
- Create a new app
- Select **Business** as app type
- Add **WhatsApp** product to your app

#### 3. Get API Credentials
```
Business Account ID: [From Meta Business Suite]
Phone Number ID: [From WhatsApp API Setup]
Access Token: [From App Dashboard]
```

#### 4. Verify Phone Number
- You need a business phone number (cannot be personal WhatsApp)
- Meta will send a verification code
- Complete two-factor authentication

#### 5. Create Message Templates
WhatsApp requires **pre-approved templates** for automated messages.

**Emergency Template Example:**
```
Template Name: emergency_alert
Language: English
Category: ALERT_UPDATE

Body:
🚨 EMERGENCY ALERT 🚨

Type: {{1}}
Name: {{2}}
Location: {{3}}
Description: {{4}}

Emergency Contact: {{5}}
Time: {{6}}

This is an automated emergency notification from NeighborHub.
```

**Approval Process:**
1. Submit template in Meta Business Manager
2. Wait 24-48 hours for approval
3. Once approved, can be used for sending

---

### Option B: WhatsApp Business Solution Provider (BSP)

**Recommended BSPs for South Africa:**
1. **Twilio** (twilio.com/whatsapp)
   - Easy integration
   - Pay-as-you-go
   - Good documentation
   - ~$0.10-0.30 per message

2. **MessageBird** (messagebird.com)
   - Great for African markets
   - Competitive pricing

3. **360Dialog** (360dialog.com)
   - WhatsApp official partner
   - Monthly subscription + per-message cost

**Twilio Setup (Easiest):**
```bash
# 1. Sign up at twilio.com
# 2. Verify your account
# 3. Request WhatsApp Sender (requires business verification)
# 4. Get credentials:

TWILIO_ACCOUNT_SID: "Your SID"
TWILIO_AUTH_TOKEN: "Your Token"
WHATSAPP_FROM: "whatsapp:+14155238886" # Twilio sandbox for testing
```

---

## 📋 Step 2: Backend Implementation (Firebase Cloud Functions)

### Install Dependencies
```bash
cd functions
npm install axios
npm install firebase-admin
npm install @google-cloud/firestore
```

### Create Cloud Function for Emergency WhatsApp
```javascript
// functions/sendEmergencyWhatsApp.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

exports.sendEmergencyWhatsApp = functions.https.onCall(async (data, context) => {
    // Verify user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const {
        emergencyType, // 'fire', 'medical', 'emergency'
        userName,
        userAddress,
        userPhone,
        description,
        emergencyContactPhone,
        timestamp
    } = data;

    // Validate required fields
    if (!emergencyType || !userName) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    try {
        // WhatsApp Business API Configuration
        const WHATSAPP_API_TOKEN = functions.config().whatsapp.token; // Set via Firebase config
        const WHATSAPP_PHONE_ID = functions.config().whatsapp.phone_id;
        const WHATSAPP_API_URL = `https://graph.facebook.com/v18.0/${WHATSAPP_PHONE_ID}/messages`;

        // Format emergency message
        const emergencyEmoji = {
            fire: '🔥',
            medical: '🏥',
            emergency: '⚠️'
        };

        // Send WhatsApp message using approved template
        const whatsappPayload = {
            messaging_product: 'whatsapp',
            to: emergencyContactPhone, // Must be in E.164 format: +27793867472
            type: 'template',
            template: {
                name: 'emergency_alert', // Your approved template name
                language: {
                    code: 'en'
                },
                components: [
                    {
                        type: 'body',
                        parameters: [
                            { type: 'text', text: emergencyType },
                            { type: 'text', text: userName },
                            { type: 'text', text: userAddress || 'Not provided' },
                            { type: 'text', text: description || 'No description' },
                            { type: 'text', text: userPhone || 'Not provided' },
                            { type: 'text', text: new Date(timestamp).toLocaleString() }
                        ]
                    }
                ]
            }
        };

        // Send WhatsApp message
        const whatsappResponse = await axios.post(
            WHATSAPP_API_URL,
            whatsappPayload,
            {
                headers: {
                    'Authorization': `Bearer ${WHATSAPP_API_TOKEN}`,
                    'Content-Type': 'application/json'
                }
            }
        );

        console.log('WhatsApp message sent:', whatsappResponse.data);

        // Log emergency to Firestore
        await admin.firestore().collection('emergencies').add({
            type: emergencyType,
            userName: userName,
            userAddress: userAddress,
            userPhone: userPhone,
            description: description,
            emergencyContactPhone: emergencyContactPhone,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            userId: context.auth.uid,
            whatsappMessageId: whatsappResponse.data.messages[0].id,
            status: 'sent'
        });

        return {
            success: true,
            messageId: whatsappResponse.data.messages[0].id,
            message: 'Emergency WhatsApp sent successfully'
        };

    } catch (error) {
        console.error('Error sending WhatsApp:', error.response?.data || error.message);
        
        // Log failed emergency
        await admin.firestore().collection('emergencies').add({
            type: emergencyType,
            userName: userName,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            userId: context.auth.uid,
            status: 'failed',
            error: error.message
        });

        throw new functions.https.HttpsError('internal', 'Failed to send WhatsApp message');
    }
});
```

### Set Firebase Configuration
```bash
# Set WhatsApp credentials in Firebase
firebase functions:config:set whatsapp.token="YOUR_WHATSAPP_ACCESS_TOKEN"
firebase functions:config:set whatsapp.phone_id="YOUR_PHONE_NUMBER_ID"

# Deploy function
firebase deploy --only functions:sendEmergencyWhatsApp
```

---

## 📋 Step 3: iOS App Integration

### Update EmergencyRequestManager.swift

Add this method to call the Cloud Function:

```swift
import FirebaseFunctions

extension EmergencyRequestManager {
    
    /// Send emergency via WhatsApp Business API (automatic, no user interaction)
    func sendEmergencyWhatsAppAutomatic(
        type: EmergencyType,
        userName: String,
        userAddress: String?,
        userPhone: String?,
        description: String?,
        emergencyContactPhone: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let functions = Functions.functions()
        
        let data: [String: Any] = [
            "emergencyType": type.rawValue.lowercased(),
            "userName": userName,
            "userAddress": userAddress ?? "",
            "userPhone": userPhone ?? "",
            "description": description ?? "",
            "emergencyContactPhone": emergencyContactPhone,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        functions.httpsCallable("sendEmergencyWhatsApp").call(data) { result, error in
            if let error = error {
                print("❌ Error sending emergency WhatsApp: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            if let data = result?.data as? [String: Any],
               let success = data["success"] as? Bool,
               success == true {
                let messageId = data["messageId"] as? String ?? "unknown"
                print("✅ Emergency WhatsApp sent successfully. Message ID: \(messageId)")
                completion(.success(messageId))
            } else {
                let error = NSError(domain: "EmergencyManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to send emergency WhatsApp"
                ])
                completion(.failure(error))
            }
        }
    }
}
```

### Update Emergency Button Handler

```swift
// In your emergency button view/handler
func handleEmergencyButtonPress() {
    // Show loading indicator
    isLoading = true
    
    let manager = EmergencyRequestManager()
    
    // Send automatic WhatsApp (no user interaction needed)
    manager.sendEmergencyWhatsAppAutomatic(
        type: .emergency,
        userName: currentUser.fullName,
        userAddress: currentUser.address,
        userPhone: currentUser.phone,
        description: "Emergency button pressed",
        emergencyContactPhone: "+27793867472" // Your emergency number in E.164 format
    ) { result in
        DispatchQueue.main.async {
            isLoading = false
            
            switch result {
            case .success(let messageId):
                print("✅ Emergency WhatsApp sent: \(messageId)")
                
                // Send push notification to user's device
                self.sendEmergencyNotification()
                
                // Show success alert
                self.showAlert(title: "Emergency Sent", message: "Emergency WhatsApp sent successfully!")
                
            case .failure(let error):
                print("❌ Failed to send emergency: \(error.localizedDescription)")
                
                // Fallback to traditional WhatsApp URL scheme
                self.openWhatsAppFallback()
            }
        }
    }
}
```

---

## 📋 Step 4: Push Notifications Setup

### Configure Firebase Cloud Messaging (FCM)

#### 1. iOS App Configuration

```swift
// AppDelegate.swift
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            }
        }
        
        application.registerForRemoteNotifications()
        
        // Set messaging delegate
        Messaging.messaging().delegate = self
        
        return true
    }
    
    // Get FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM Token: \(fcmToken ?? "")")
        
        // Save FCM token to Firestore for user
        if let token = fcmToken, let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore().collection("users").document(uid).setData([
                "fcmToken": token
            ], merge: true)
        }
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
```

#### 2. Cloud Function to Send Push Notification

```javascript
// functions/sendEmergencyNotification.js

exports.sendEmergencyNotification = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = context.auth.uid;
    
    // Get user's FCM token
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;
    
    if (!fcmToken) {
        throw new functions.https.HttpsError('not-found', 'User FCM token not found');
    }

    const { emergencyType } = data;
    
    // Create notification payload
    const message = {
        notification: {
            title: '🚨 Emergency Sent',
            body: `Your ${emergencyType} emergency has been sent to emergency contacts via WhatsApp.`
        },
        data: {
            type: 'emergency_confirmation',
            emergencyType: emergencyType,
            timestamp: Date.now().toString()
        },
        token: fcmToken
    };

    // Send notification
    try {
        const response = await admin.messaging().send(message);
        console.log('✅ Notification sent:', response);
        return { success: true, messageId: response };
    } catch (error) {
        console.error('❌ Error sending notification:', error);
        throw new functions.https.HttpsError('internal', 'Failed to send notification');
    }
});
```

#### 3. Call from iOS App

```swift
func sendEmergencyNotification() {
    let functions = Functions.functions()
    
    functions.httpsCallable("sendEmergencyNotification").call([
        "emergencyType": "emergency"
    ]) { result, error in
        if let error = error {
            print("❌ Error sending notification: \(error.localizedDescription)")
        } else {
            print("✅ Push notification sent")
        }
    }
}
```

---

## 🔐 Security Considerations

1. **Rate Limiting:** Prevent abuse of emergency button
```swift
private var lastEmergencyTime: Date?
private let minimumEmergencyInterval: TimeInterval = 60 // 60 seconds

func canSendEmergency() -> Bool {
    guard let lastTime = lastEmergencyTime else {
        return true
    }
    return Date().timeIntervalSince(lastTime) >= minimumEmergencyInterval
}
```

2. **Firestore Security Rules:**
```javascript
// firestore.rules
match /emergencies/{emergencyId} {
  allow create: if request.auth != null;
  allow read: if request.auth != null && 
              (request.auth.uid == resource.data.userId || 
               get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
}
```

3. **Verify Emergency Contacts:**
```swift
func validatePhoneNumber(_ phone: String) -> Bool {
    // E.164 format: +[country code][number]
    let phoneRegex = "^\\+[1-9]\\d{1,14}$"
    let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
    return phonePredicate.evaluate(with: phone)
}
```

---

## 💰 Cost Estimation (South Africa)

### WhatsApp Business API:
- **Conversation-based pricing**
- **Service conversations:** ~R0.80 per conversation (first 1,000 free/month)
- **1,000 emergencies/month:** ~R800
- **5,000 emergencies/month:** ~R4,000

### Firebase Cloud Functions:
- **Free tier:** 2 million invocations/month
- **Beyond free tier:** $0.40 per million invocations

### Firebase Cloud Messaging (FCM):
- **Completely FREE** for push notifications

### Total Estimated Cost:
- **0-100 emergencies/month:** FREE
- **100-1,000 emergencies/month:** ~R100-800
- **1,000+ emergencies/month:** Contact Meta for volume pricing

---

## 🧪 Testing

### Test with WhatsApp Sandbox (Development)

#### Using Twilio Sandbox:
```javascript
// Test configuration
const TWILIO_ACCOUNT_SID = 'your_test_sid';
const TWILIO_AUTH_TOKEN = 'your_test_token';
const TWILIO_SANDBOX = 'whatsapp:+14155238886';

// Send test message
await axios.post(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
    new URLSearchParams({
        From: TWILIO_SANDBOX,
        To: 'whatsapp:+27793867472',
        Body: '🚨 TEST EMERGENCY ALERT'
    }),
    {
        auth: {
            username: TWILIO_ACCOUNT_SID,
            password: TWILIO_AUTH_TOKEN
        }
    }
);
```

### Test Push Notifications:
```bash
# Use Firebase Console: Cloud Messaging > Send test message
# Or use curl:
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "USER_FCM_TOKEN",
    "notification": {
      "title": "Test Emergency",
      "body": "This is a test emergency notification"
    }
  }'
```

---

## 📚 Additional Resources

- **WhatsApp Business API Docs:** https://developers.facebook.com/docs/whatsapp
- **Firebase Cloud Functions:** https://firebase.google.com/docs/functions
- **Firebase Cloud Messaging:** https://firebase.google.com/docs/cloud-messaging
- **Twilio WhatsApp:** https://www.twilio.com/docs/whatsapp
- **WhatsApp Message Templates:** https://developers.facebook.com/docs/whatsapp/message-templates

---

## ⚠️ Important Notes

1. **WhatsApp Business API is a paid service** - Budget accordingly
2. **Message templates must be pre-approved** - Plan ahead (24-48 hour approval)
3. **Cannot send promotional content** - Only transactional/alert messages
4. **Rate limits apply** - 1,000 messages/second (Meta Cloud API)
5. **Phone number verification required** - Need business documents
6. **Session messages are free** - But only within 24-hour window after user message

---

## 🚀 Quick Start Checklist

- [ ] Create Facebook Business Account
- [ ] Apply for WhatsApp Business API access
- [ ] Verify business phone number
- [ ] Create and get approval for emergency message template
- [ ] Set up Firebase Cloud Functions
- [ ] Configure WhatsApp API credentials in Firebase
- [ ] Update iOS app with automatic sending code
- [ ] Set up Firebase Cloud Messaging for push notifications
- [ ] Implement rate limiting and security rules
- [ ] Test in sandbox environment
- [ ] Deploy to production
- [ ] Monitor costs and usage

---

*Last Updated: March 2026*
*For NeighborHub Emergency System*
