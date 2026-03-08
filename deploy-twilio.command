#!/bin/bash

# Twilio Emergency WhatsApp - Terminal.app Deployment Script
# Double-click this file or run: bash deploy-twilio.command

echo "🚀 Twilio Emergency WhatsApp Deployment"
echo "========================================"
echo ""

# Navigate to project directory
cd "/Users/mikeweston/Desktop/Waterfall 3 V1.07"

echo "📍 Current directory: $(pwd)"
echo ""

# Kill any hanging processes
echo "🧹 Cleaning up any hanging processes..."
killall node 2>/dev/null || true
killall npm 2>/dev/null || true  
killall firebase 2>/dev/null || true
sleep 2

echo "✅ Processes cleaned"
echo ""

# Check Firebase login
echo "🔐 Checking Firebase authentication..."
if firebase login:list | grep -q "miichael.weston77@gmail.com"; then
    echo "✅ Already logged in"
else
    echo "❌ Not logged in. Running firebase login..."
    firebase login
fi

echo ""
echo "📦 Deploying Twilio Emergency Functions..."
echo ""

# Deploy the functions
firebase deploy --only functions:testTwilioWhatsApp,functions:sendEmergencyWhatsApp

echo ""
if [ $? -eq 0 ]; then
    echo "✅ ✅ ✅ DEPLOYMENT SUCCESSFUL! ✅ ✅ ✅"
    echo ""
    echo "Deployed functions:"
    firebase functions:list | grep -iE "twilio|emergency"
    echo ""
    echo "📱 Next step: Test in your iOS app!"
    echo ""
    echo "Add this test button to any SwiftUI view:"
    echo ""
    echo 'Button("Test Twilio") {'
    echo '    EmergencyRequestManager().testTwilioWhatsApp('
    echo '        toPhone: "+27793867472",'
    echo '        message: "Test! 🎉"'
    echo '    ) { success, msg in'
    echo '        print(success ? "✅ \(msg ?? "")" : "❌ \(msg ?? "")")'
    echo '    }'
    echo '}'
else
    echo "❌ Deployment failed with error code: $?"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check that Node.js is installed: node --version"
    echo "2. Verify Firebase CLI: firebase --version"
    echo "3. Check functions/node_modules exists: ls functions/node_modules | head"
    echo "4. Try: cd functions && npm install && cd .."
    echo ""
    echo "See DEPLOY_TWILIO_MANUALLY.md for detailed troubleshooting"
fi

echo ""
echo "Press any key to exit..."
read -n 1
