#!/bin/bash
# Twilio Emergency WhatsApp Deployment Script

set -e

echo "🚀 Deploying Emergency WhatsApp Functions..."
echo ""

# Kill any hanging npm processes
pkill -f npm || true

# Wait a moment
sleep 2

# Deploy functions
echo "📦 Deploying to Firebase..."
firebase deploy --only functions:testTwilioWhatsApp,functions:sendEmergencyWhatsApp --force

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Test your deployment with:"
echo "  firebase functions:log --only sendEmergencyWhatsApp"
