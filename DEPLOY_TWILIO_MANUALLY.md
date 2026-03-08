# Manual Twilio Deployment Guide

## The Issue
VS Code's integrated terminal is experiencing hanging processes during deployment. This is a common issue with Firebase CLI in VS Code.

## 🚀 Solution: Use Terminal.app

### Step 1: Open Terminal.app

1. Press `Cmd + Space` (Spotlight)
2. Type "Terminal"
3. Press Enter

### Step 2: Navigate to Project

```bash
cd "/Users/mikeweston/Desktop/Waterfall 3 V1.07"
```

### Step 3: Kill Any Hanging Processes

```bash
killall node
killall npm
killall firebase
```

### Step 4: Verify Firebase Login

```bash
firebase login:list
```

If not logged in, run:
```bash
firebase login
```

### Step 5: Deploy Twilio Functions

**Option A: Deploy Only New Functions (Faster)**
```bash
firebase deploy --only functions:testTwilioWhatsApp,functions:sendEmergencyWhatsApp
```

**Option B: Deploy All Functions (Safer)**
```bash
firebase deploy --only functions
```

### Step 6: Verify Deployment

```bash
firebase functions:list | grep -iE "twilio|emergency"
```

You should see:
```
│ testTwilioWhatsApp      │ v1 │ callable │ us-central1 │ 256 │ nodejs20 │
│ sendEmergencyWhatsApp   │ v1 │ callable │ us-central1 │ 256 │ nodejs20 │
```

### Step 7: Test the  Functions

**Test in Terminal:**
```bash
firebase functions:log --only sendEmergencyWhatsApp
```

**Test in iOS App:**

Add this test button to any view:

```swift
Button("🧪 Test Twilio") {
    EmergencyRequestManager().testTwilioWhatsApp(
        toPhone: "+27793867472", // Your number that joined sandbox
        message: "Test from NeighborHub - Twilio working! 🎉"
    ) { success, message in
        if success {
            print("✅ Test passed!")
            // Show success alert to user
        } else {
            print("❌ Test failed: \(message ?? "Unknown error")")
            // Show error alert to user
        }
    }
}
```

---

## 🔧 If Deployment Still Fails

### Check Node.js Path

```bash
which node
node --version
```

Should show `/usr/local/bin/node` or similar and version 16+

### Reinstall Firebase CLI

```bash
sudo npm uninstall -g firebase-tools
sudo npm install -g firebase-tools
firebase login
```

### Check functions/node_modules

```bash
cd functions
ls -la node_modules/twilio
ls -la node_modules/firebase-functions
```

Both should exist. If not:
```bash
npm install
```

### Use Firebase Console (Alternative)

If command line continues to fail, you can deploy via Firebase Console:

1. Go to: https://console.firebase.google.com/project/neighborhub-cd47d/functions
2. Click "Deploy"
3. Select your functions directory
4. Upload and deploy

---

## ✅ What Should Happen

When deployment succeeds, you'll see:

```
✔  functions[testTwilioWhatsApp(us-central1)] Successful create operation.
✔  functions[sendEmergencyWhatsApp(us-central1)] Successful create operation.
✔  Deploy complete!
```

Then your iOS app can send automatic WhatsApp messages without opening the WhatsApp app!

---

## 📋 Summary of What's Been Set Up

✅ Twilio credentials configured in Firebase  
✅ `functions/index.js` has Twilio functions implemented  
✅ `functions/package.json` has Twilio SDK dependency  
✅ `EmergencyRequestManager.swift` has iOS integration  
✅ npm packages installed (including Twilio)  

**All that's left is deploying the functions!**

---

## 💡 Quick Test Without Deployment

While debugging deployment, you can test WhatsApp functionality using the fallback URL scheme:

```swift
// This will open WhatsApp (manual send required)
let manager = EmergencyRequestManager()
manager.sendEmergencyViaTwilio(
    type: .fire,
    name: "Test User",
    address: "123 Test St",
    cell: "+27123456789",
    emergencyContact: EmergencyRequestManager.RecipientInfo(
        phone: "+27793867472"
    ),
    description: "Test",
    metadata: nil,
    reportedDate: Date()
) { success, error in
    // Will use fallback if Cloud Functions not deployed
    print(success ? "✅" : "❌ \(error ?? "")")
}
```

This confirms the iOS integration works while you're deploying the Cloud Functions.
