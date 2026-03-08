#!/bin/bash

# ============================================================================
# Firebase Security Rules Deployment Script
# ============================================================================
# This script deploys updated Firestore and Storage security rules to Firebase
# Run this after updating firestore.rules or firebase-storage.rules files

set -e  # Exit on error

echo "🚀 Firebase Rules Deployment"
echo "=================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "📦 Install it with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Check if user is logged in
if ! firebase projects:list &> /dev/null; then
    echo "🔐 Not logged in to Firebase. Running login..."
    firebase login
fi

echo "✅ Authenticated with Firebase"
echo ""

# Show current project
echo "📋 Current Firebase project:"
firebase use
echo ""

# Deploy Firestore rules (validation happens automatically during deployment)
echo "📤 Deploying Firestore security rules..."
if firebase deploy --only firestore; then
    echo "✅ Firestore rules deployed successfully"
else
    echo "❌ Firestore rules deployment failed!"
    exit 1
fi
echo ""

# Deploy Storage rules
echo "📤 Deploying Storage security rules..."
if firebase deploy --only storage; then
    echo "✅ Storage rules deployed successfully"
else
    echo "❌ Storage rules deployment failed!"
    exit 1
fi
echo ""

echo "=================================="
echo "🎉 All rules deployed successfully!"
echo "=================================="
echo ""
echo "⚠️  Important Next Steps:"
echo "1. Enable Firebase Authentication in Firebase Console"
echo "2. Enable Email/Password provider"
echo "3. Test authentication with a new user account"
echo "4. Verify security rules are working as expected"
echo ""
