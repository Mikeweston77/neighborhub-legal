# Twilio WhatsApp API Setup Guide for NeighborHub

## 🚀 Complete Step-by-Step Twilio Setup

This guide will walk you through setting up Twilio's WhatsApp API for automated emergency messages in NeighborHub.

---

## 📋 Prerequisites

- [ ] Valid email address
- [ ] Phone number for verification
- [ ] Credit/debit card for account verification (no charges for testing)
- [ ] Business details (for production WhatsApp access)

---

## Step 1: Create Twilio Account

### 1.1 Sign Up
1. Go to https://www.twilio.com/try-twilio
2. Click **Sign up**
3. Fill in your details:
   ```
   First Name: [Your name]
   Last Name: [Your surname]
   Email: [Your email]
   Password: [Strong password]
   ```
4. Click **Start your free trial**

### 1.2 Verify Your Account
1. Check your email for verification link
2. Click the verification link
3. You'll be taken to the Twilio Console

### 1.3 Verify Your Phone Number
1. Enter your phone number (format: +27793867472)
2. Receive verification code via SMS
3. Enter the code

**🎉 You now have a Twilio account with $15 trial credit!**

---

## Step 2: WhatsApp Sandbox Setup (Testing)

The WhatsApp Sandbox lets you test WhatsApp messaging **immediately** without business verification.

### 2.1 Access WhatsApp Sandbox

1. In Twilio Console, click **Messaging** in left sidebar
2. Click **Try it out** → **Send a WhatsApp message**
3. You'll see the **WhatsApp Sandbox** page

### 2.2 Join the Sandbox

You'll see instructions like:
```
To connect to the sandbox:
1. Send "join [code]" to whatsapp:+1-415-523-8886
2. Your unique code: example-word
```

**On Your Phone:**
1. Open WhatsApp
2. Create a new message to: **+1 415 523 8886**
3. Send the message: `join [your-code]` (e.g., "join example-word")
4. You'll receive a confirmation: "You are all set!"

**✅ Your phone is now connected to Twilio's WhatsApp Sandbox**

### 2.3 Test Sending a Message

**In Twilio Console:**
1. Still on the WhatsApp Sandbox page
2. You'll see your phone number listed as "Joined"
3. Enter a test message: "Hello from Twilio!"
4. Click **Send message**

**📱 You should receive the WhatsApp message immediately!**

### 2.4 Get Your Sandbox Credentials

1. Click **Settings** in left sidebar
2. Click **General**
3. Scroll down to find:

```
Account SID: ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Auth Token: [Click to reveal] xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**🔐 Save these credentials securely - you'll need them!**

---

## Step 3: Test with Firebase Cloud Functions (Development)

### 3.1 Install Twilio Package

In your Firebase functions directory:

```bash
cd functions
npm install twilio
```

### 3.2 Create Test Function

Create `functions/testTwilioWhatsApp.js`:

```javascript
const functions = require('firebase-functions');
const twilio = require('twilio');

// Test function for WhatsApp sandbox
exports.testTwilioWhatsApp = functions.https.onCall(async (data, context) => {
    // Verify user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
    }

    // Twilio credentials from Firebase config
    const accountSid = functions.config().twilio.account_sid;
    const authToken = functions.config().twilio.auth_token;
    const twilioWhatsAppNumber = functions.config().twilio.whatsapp_number; // e.g., 'whatsapp:+14155238886'

    const client = twilio(accountSid, authToken);

    const { toPhone, message } = data;

    try {
        // Send WhatsApp message via Twilio
        const messageResponse = await client.messages.create({
            from: twilioWhatsAppNumber,
            to: `whatsapp:${toPhone}`, // Must include 'whatsapp:' prefix
            body: message
        });

        console.log('✅ WhatsApp message sent:', messageResponse.sid);

        return {
            success: true,
            messageSid: messageResponse.sid,
            status: messageResponse.status
        };

    } catch (error) {
        console.error('❌ Twilio error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
```

### 3.3 Configure Firebase with Twilio Credentials

```bash
# Set Twilio credentials in Firebase config
firebase functions:config:set twilio.account_sid="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
firebase functions:config:set twilio.auth_token="your_auth_token"
firebase functions:config:set twilio.whatsapp_number="whatsapp:+14155238886"

# View configuration (to verify)
firebase functions:config:get

# Deploy function
firebase deploy --only functions:testTwilioWhatsApp
```

### 3.4 Test from iOS App

Add this test function to your iOS app:

```swift
import FirebaseFunctions

func testTwilioWhatsApp() {
    let functions = Functions.functions()
    
    let data: [String: Any] = [
        "toPhone": "+27793867472", // Your phone number (must be joined to sandbox)
        "message": """
        🚨 TEST EMERGENCY ALERT 🚨
        
        This is a test message from NeighborHub.
        If you receive this, Twilio WhatsApp integration is working!
        """
    ]
    
    functions.httpsCallable("testTwilioWhatsApp").call(data) { result, error in
        if let error = error {
            print("❌ Error: \(error.localizedDescription)")
            return
        }
        
        if let data = result?.data as? [String: Any],
           let success = data["success"] as? Bool,
           success {
            print("✅ Test message sent successfully!")
            print("Message SID:", data["messageSid"] ?? "unknown")
        }
    }
}
```

**Test it:**
1. Make sure your phone is joined to the Twilio Sandbox
2. Call `testTwilioWhatsApp()` from your app
3. You should receive a WhatsApp message within seconds!

---

## Step 4: Production WhatsApp API Setup

Once testing is successful, request production WhatsApp access.

### 4.1 Upgrade Twilio Account

1. In Twilio Console, click **Upgrade** in top right
2. Add credit card details
3. Add at least $20 credit (required for WhatsApp verification)

### 4.2 Request WhatsApp Sender

1. Go to **Messaging** → **Senders** → **WhatsApp senders**
2. Click **Request to add a WhatsApp sender**
3. You'll need:
   - **Business Name**: NeighborHub
   - **Business Website**: [Your website URL]
   - **Business Address**: [Your business address]
   - **Business Type**: Technology/Software
   - **Phone Number**: New business phone number (cannot be currently used on WhatsApp)

### 4.3 Phone Number Options

**Option A: Use Existing Number (Recommended)**
- Must be a business landline or mobile
- Cannot be currently registered on WhatsApp
- Number will be deactivated from regular WhatsApp

**Option B: Buy Twilio Phone Number**
```bash
# In Twilio Console:
1. Phone Numbers → Buy a number
2. Filter by Country: South Africa (+27)
3. Select a number with SMS capability
4. Purchase (~$1/month)
```

### 4.4 WhatsApp Business Profile Setup

After your sender is approved (1-3 business days):

1. **Set Business Profile:**
   ```
   Display Name: NeighborHub Emergency System
   Category: Technology
   Description: Automated emergency notification system for neighborhood safety
   Website: [Your website]
   Address: [Your business address]
   ```

2. **Upload Profile Picture:**
   - Upload your NeighborHub logo
   - 640x640px recommended

### 4.5 Create Message Templates

WhatsApp requires pre-approved templates for automated messages.

**Go to:** Messaging → Content Editor → Create Template

**Template 1: Emergency Alert**
```
Template Name: emergency_alert
Language: English
Category: ALERT_UPDATE

Body:
🚨 EMERGENCY ALERT 🚨

Type: {{1}}
Name: {{2}}
Location: {{3}}
Time: {{4}}

Contact: {{5}}

This is an automated emergency notification from NeighborHub.
```

**Template 2: Fire Alert**
```
Template Name: fire_alert
Language: English
Category: ALERT_UPDATE

Body:
🚨🔥 FIRE EMERGENCY 🔥🚨

Location: {{1}}
Building Type: {{2}}
Visible Flames: {{3}}
Time Reported: {{4}}

Reporter: {{5}}
Contact: {{6}}

URGENT: Fire reported in your neighborhood!
```

**Template 3: Medical Emergency**
```
Template Name: medical_alert
Language: English
Category: ALERT_UPDATE

Body:
🚨🏥 MEDICAL EMERGENCY 🏥🚨

Patient: {{1}}
Location: {{2}}
Description: {{3}}
Time: {{4}}

Emergency Contact: {{5}}

Immediate medical assistance requested via NeighborHub.
```

**Submit templates and wait 24-48 hours for WhatsApp approval**

---

## Step 5: Production Firebase Cloud Function

Replace the test function with production-ready code:

```javascript
// functions/sendEmergencyWhatsApp.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const twilio = require('twilio');

exports.sendEmergencyWhatsApp = functions.https.onCall(async (data, context) => {
    // Authentication check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    // Rate limiting check
    const userId = context.auth.uid;
    const lastEmergencyRef = admin.firestore()
        .collection('emergencyRateLimit')
        .doc(userId);
    
    const lastEmergencyDoc = await lastEmergencyRef.get();
    if (lastEmergencyDoc.exists) {
        const lastTime = lastEmergencyDoc.data().timestamp.toDate();
        const timeSince = Date.now() - lastTime.getTime();
        const minInterval = 60000; // 60 seconds
        
        if (timeSince < minInterval) {
            throw new functions.https.HttpsError(
                'resource-exhausted',
                'Please wait 60 seconds between emergency alerts'
            );
        }
    }

    // Extract data
    const {
        emergencyType, // 'fire', 'medical', 'emergency'
        userName,
        userAddress,
        userPhone,
        description,
        emergencyContactPhone,
        emergencyContactName,
        timestamp,
        metadata // Optional: building type, visible flames, etc.
    } = data;

    // Validation
    if (!emergencyType || !userName || !emergencyContactPhone) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Missing required fields'
        );
    }

    // Validate phone number format (E.164)
    const phoneRegex = /^\+[1-9]\d{1,14}$/;
    if (!phoneRegex.test(emergencyContactPhone)) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Emergency contact phone must be in E.164 format (e.g., +27793867472)'
        );
    }

    // Initialize Twilio client
    const accountSid = functions.config().twilio.account_sid;
    const authToken = functions.config().twilio.auth_token;
    const twilioWhatsAppNumber = functions.config().twilio.whatsapp_number;
    
    const client = twilio(accountSid, authToken);

    try {
        // Select appropriate template and parameters
        let templateName;
        let parameters;

        switch (emergencyType.toLowerCase()) {
            case 'fire':
                templateName = 'fire_alert';
                parameters = [
                    userAddress || 'Not provided',
                    metadata?.buildingType || 'Unknown',
                    metadata?.visibleFlames || 'Unknown',
                    new Date(timestamp).toLocaleString('en-ZA', { 
                        dateStyle: 'short', 
                        timeStyle: 'short' 
                    }),
                    userName,
                    userPhone || 'Not provided'
                ];
                break;

            case 'medical':
                templateName = 'medical_alert';
                parameters = [
                    userName,
                    userAddress || 'Not provided',
                    description || 'No description provided',
                    new Date(timestamp).toLocaleString('en-ZA', { 
                        dateStyle: 'short', 
                        timeStyle: 'short' 
                    }),
                    `${emergencyContactName || 'Emergency Contact'}: ${emergencyContactPhone}`
                ];
                break;

            default: // 'emergency'
                templateName = 'emergency_alert';
                parameters = [
                    emergencyType,
                    userName,
                    userAddress || 'Not provided',
                    new Date(timestamp).toLocaleString('en-ZA', { 
                        dateStyle: 'short', 
                        timeStyle: 'short' 
                    }),
                    userPhone || emergencyContactPhone
                ];
                break;
        }

        // Send WhatsApp message using template
        const messageResponse = await client.messages.create({
            from: twilioWhatsAppNumber,
            to: `whatsapp:${emergencyContactPhone}`,
            contentSid: templateName, // Template SID from Twilio
            contentVariables: JSON.stringify({
                1: parameters[0],
                2: parameters[1],
                3: parameters[2],
                4: parameters[3],
                5: parameters[4] || '',
                6: parameters[5] || ''
            })
        });

        console.log('✅ WhatsApp message sent:', messageResponse.sid);

        // Log to Firestore
        const emergencyRef = await admin.firestore().collection('emergencies').add({
            type: emergencyType,
            userName: userName,
            userAddress: userAddress,
            userPhone: userPhone,
            description: description,
            emergencyContactPhone: emergencyContactPhone,
            emergencyContactName: emergencyContactName,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            userId: userId,
            twilioMessageSid: messageResponse.sid,
            twilioStatus: messageResponse.status,
            metadata: metadata || {},
            status: 'sent'
        });

        // Update rate limiting
        await lastEmergencyRef.set({
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        // Send push notification to user
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const fcmToken = userDoc.data()?.fcmToken;
        
        if (fcmToken) {
            await admin.messaging().send({
                notification: {
                    title: '🚨 Emergency Sent',
                    body: `Your ${emergencyType} alert has been sent via WhatsApp.`
                },
                data: {
                    type: 'emergency_confirmation',
                    emergencyId: emergencyRef.id
                },
                token: fcmToken
            });
        }

        return {
            success: true,
            emergencyId: emergencyRef.id,
            messageSid: messageResponse.sid,
            status: messageResponse.status
        };

    } catch (error) {
        console.error('❌ Error sending emergency:', error);

        // Log failed emergency
        await admin.firestore().collection('emergencies').add({
            type: emergencyType,
            userName: userName,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            userId: userId,
            status: 'failed',
            error: error.message,
            errorCode: error.code
        });

        throw new functions.https.HttpsError(
            'internal',
            `Failed to send emergency: ${error.message}`
        );
    }
});
```

### Deploy Production Function

```bash
# Update Twilio config with production WhatsApp number
firebase functions:config:set twilio.whatsapp_number="whatsapp:+27XXXXXXXXXX"

# Deploy
firebase deploy --only functions:sendEmergencyWhatsApp
```

---

## Step 6: iOS App Integration

Update your EmergencyRequestManager.swift:

```swift
import FirebaseFunctions

extension EmergencyRequestManager {
    
    /// Send emergency via Twilio WhatsApp (production)
    func sendEmergencyViaTwilio(
        type: EmergencyType,
        userName: String,
        userAddress: String?,
        userPhone: String?,
        description: String?,
        emergencyContactPhone: String,
        emergencyContactName: String?,
        metadata: [String: String]? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        // Validate phone number format (E.164)
        guard emergencyContactPhone.hasPrefix("+") && emergencyContactPhone.count >= 10 else {
            let error = NSError(domain: "EmergencyManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Phone number must be in international format (e.g., +27793867472)"
            ])
            completion(.failure(error))
            return
        }
        
        let functions = Functions.functions()
        
        let data: [String: Any] = [
            "emergencyType": type.rawValue.lowercased(),
            "userName": userName,
            "userAddress": userAddress ?? "",
            "userPhone": userPhone ?? "",
            "description": description ?? "",
            "emergencyContactPhone": emergencyContactPhone,
            "emergencyContactName": emergencyContactName ?? "Emergency Contact",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "metadata": metadata ?? [:]
        ]
        
        functions.httpsCallable("sendEmergencyWhatsApp").call(data) { result, error in
            if let error = error as NSError? {
                print("❌ Error sending emergency: \(error.localizedDescription)")
                
                // Check for specific error codes
                if error.domain == FunctionsErrorDomain {
                    if error.code == FunctionsErrorCode.resourceExhausted.rawValue {
                        // Rate limited
                        let userError = NSError(domain: "EmergencyManager", code: 429, userInfo: [
                            NSLocalizedDescriptionKey: "Please wait 60 seconds between emergency alerts"
                        ])
                        completion(.failure(userError))
                        return
                    }
                }
                
                completion(.failure(error))
                return
            }
            
            if let data = result?.data as? [String: Any],
               let success = data["success"] as? Bool,
               success == true {
                let emergencyId = data["emergencyId"] as? String ?? "unknown"
                let messageSid = data["messageSid"] as? String ?? "unknown"
                
                print("✅ Emergency sent successfully!")
                print("Emergency ID: \(emergencyId)")
                print("Twilio Message SID: \(messageSid)")
                
                completion(.success(emergencyId))
            } else {
                let error = NSError(domain: "EmergencyManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to send emergency alert"
                ])
                completion(.failure(error))
            }
        }
    }
}
```

### Update Emergency Button Handler

```swift
// In your emergency button view
func handleEmergencyButtonPress() {
    // Check rate limiting
    if !canSendEmergency() {
        showAlert(title: "Please Wait", message: "You can only send an emergency alert once per minute.")
        return
    }
    
    isLoading = true
    
    let manager = EmergencyRequestManager()
    
    // Get user details from Firebase or UserDefaults
    let userName = currentUser.fullName
    let userAddress = currentUser.address
    let userPhone = currentUser.phone
    let emergencyContact = currentUser.emergencyContactPhone ?? "+27793867472"
    let emergencyContactName = currentUser.emergencyContactName
    
    // Send via Twilio
    manager.sendEmergencyViaTwilio(
        type: selectedEmergencyType, // .fire, .medical, or .emergency
        userName: userName,
        userAddress: userAddress,
        userPhone: userPhone,
        description: emergencyDescription,
        emergencyContactPhone: emergencyContact,
        emergencyContactName: emergencyContactName,
        metadata: additionalMetadata
    ) { result in
        DispatchQueue.main.async {
            self.isLoading = false
            
            switch result {
            case .success(let emergencyId):
                print("✅ Emergency sent! ID: \(emergencyId)")
                self.lastEmergencyTime = Date()
                self.showAlert(
                    title: "Emergency Sent",
                    message: "Your emergency alert has been sent via WhatsApp to your emergency contacts."
                )
                
            case .failure(let error):
                print("❌ Failed to send emergency: \(error.localizedDescription)")
                
                if (error as NSError).code == 429 {
                    self.showAlert(
                        title: "Too Many Requests",
                        message: "Please wait 60 seconds between emergency alerts."
                    )
                } else {
                    self.showAlert(
                        title: "Error",
                        message: "Failed to send emergency alert: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

// Rate limiting
private var lastEmergencyTime: Date?

func canSendEmergency() -> Bool {
    guard let lastTime = lastEmergencyTime else {
        return true
    }
    return Date().timeIntervalSince(lastTime) >= 60 // 60 seconds
}
```

---

## 💰 Pricing

### Twilio WhatsApp Pricing (South Africa)

**Conversation-Based Pricing:**
- **Service Conversations** (business-initiated): ~$0.05 (R0.95) per conversation
- **User-Initiated Conversations**: FREE for 24 hours after user message
- **Session Messages**: FREE within 24-hour window

**Monthly Estimates:**
- **100 emergencies/month**: ~R95
- **500 emergencies/month**: ~R475
- **1,000 emergencies/month**: ~R950

**Additional Costs:**
- **Phone Number**: $1-2/month (~R20-40)
- **SMS (fallback)**: $0.03/SMS (~R0.50)

---

## 🧪 Testing Checklist

### Sandbox Testing
- [ ] Account created and verified
- [ ] Phone joined to sandbox
- [ ] Test message received successfully
- [ ] Firebase function deployed
- [ ] Test from iOS app successful

### Production Testing
- [ ] WhatsApp sender approved
- [ ] Message templates approved
- [ ] Production phone number configured
- [ ] Test emergency sent successfully
- [ ] Push notification received
- [ ] Emergency logged in Firestore
- [ ] Rate limiting working
- [ ] Error handling tested

---

## 📊 Monitoring & Logs

### View Message Status in Twilio Console

1. Go to **Messaging** → **Logs** → **Messages**
2. Filter by:
   - Date range
   - Status (delivered, sent, failed)
   - Phone number
3. Click any message to see details:
   - Message SID
   - Status timeline
   - Error codes (if failed)
   - Delivery receipts

### Common Status Codes

- `queued`: Message accepted by Twilio
- `sending`: Being sent to WhatsApp
- `sent`: Delivered to WhatsApp servers
- `delivered`: Delivered to recipient (requires delivery receipts)
- `failed`: Send failed (check error code)
- `undelivered`: Could not deliver (recipient blocked, invalid number, etc.)

### View in Firebase Console

```javascript
// Query recent emergencies
admin.firestore()
    .collection('emergencies')
    .orderBy('timestamp', 'desc')
    .limit(20)
    .get()
    .then(snapshot => {
        snapshot.forEach(doc => {
            console.log(doc.id, doc.data());
        });
    });
```

---

## 🔧 Troubleshooting

### Error: "Invalid phone number"
**Solution:** Ensure phone is in E.164 format: `+27793867472` (no spaces, dashes, or parentheses)

### Error: "Sender not approved"
**Solution:** Wait for WhatsApp sender approval (1-3 business days). Use sandbox for testing.

### Error: "Template not found"
**Solution:** Ensure template is approved. Check template name matches exactly (case-sensitive).

### Error: "Message blocked"
**Solution:** 
- Recipient may have blocked your number
- Recipient phone may not be WhatsApp-enabled
- Check Twilio logs for specific error code

### Error: "Rate limit exceeded"
**Solution:** 
- Twilio limit: 1,000 messages/second (unlikely for emergencies)
- Your rate limit: 1 emergency per 60 seconds per user (by design)

### Messages not delivering
**Checklist:**
- [ ] Recipient has WhatsApp installed
- [ ] Phone number is correct and active
- [ ] Recipient hasn't blocked your sender
- [ ] Template is approved for use
- [ ] Account has sufficient credit

---

## 🔐 Security Best Practices

1. **Store Credentials Securely**
   ```bash
   # Use Firebase functions config (encrypted)
   firebase functions:config:set twilio.account_sid="ACxxx"
   
   # Never commit credentials to Git
   echo "functions/.runtimeconfig.json" >> .gitignore
   ```

2. **Validate All Inputs**
   ```javascript
   // Phone number validation
   const phoneRegex = /^\+[1-9]\d{1,14}$/;
   if (!phoneRegex.test(phone)) {
       throw new Error('Invalid phone number');
   }
   ```

3. **Rate Limiting**
   ```javascript
   // Implement in Firebase function (shown in Step 5)
   // Prevent spam/abuse - 1 emergency per 60 seconds
   ```

4. **Audit Logging**
   ```javascript
   // Log all emergency requests
   await admin.firestore().collection('emergencies').add({
       userId, type, timestamp, status, messageSid
   });
   ```

---

## 🆘 Support Resources

- **Twilio Support**: https://support.twilio.com
- **Twilio WhatsApp Docs**: https://www.twilio.com/docs/whatsapp
- **Firebase Support**: https://firebase.google.com/support
- **NeighborHub Emergency Guide**: See WHATSAPP_BUSINESS_API_SETUP.md

---

## ✅ Final Checklist

### Development (Sandbox)
- [ ] Twilio account created
- [ ] Phone verified
- [ ] Joined WhatsApp sandbox
- [ ] Test message sent successfully
- [ ] Firebase function deployed
- [ ] iOS app tested with sandbox

### Production
- [ ] Twilio account upgraded
- [ ] WhatsApp sender requested
- [ ] Business verified
- [ ] Phone number assigned
- [ ] Message templates created and approved
- [ ] Production function deployed
- [ ] iOS app updated with production code
- [ ] End-to-end testing completed
- [ ] Monitoring setup
- [ ] Rate limiting tested

---

**🎉 You're ready to send automated WhatsApp emergency alerts!**

*Last Updated: March 2026*
*For NeighborHub Emergency System*
