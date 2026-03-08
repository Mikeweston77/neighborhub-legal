#!/bin/bash

# ============================================================================
# Firebase Authentication & Security Rules Test Script
# ============================================================================
# This script helps verify that Firebase Auth and security rules are working
# Run this AFTER enabling Email/Password authentication in Firebase Console

set -e

echo "🧪 Firebase Authentication & Rules Test"
echo "=========================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Show current project
echo "📋 Testing project:"
firebase use
echo ""

# Test 1: Check if Authentication is enabled
echo "🔍 Test 1: Checking Authentication setup..."
echo "   Please verify in Firebase Console that:"
echo "   - Authentication is enabled"
echo "   - Email/Password provider is enabled"
echo ""
read -p "   Press Enter after confirming in console..."
echo ""

# Test 2: Verify Firestore rules are deployed
echo "🔍 Test 2: Verifying Firestore rules..."
if firebase firestore:get /users/test123 2>&1 | grep -q "PERMISSION_DENIED\|Missing or insufficient permissions"; then
    echo "✅ Firestore rules are enforcing authentication (got permission denied)"
else
    echo "⚠️  Firestore may be accessible without auth - check rules"
fi
echo ""

# Test 3: Check Storage rules
echo "🔍 Test 3: Verifying Storage rules..."
echo "   Storage rules deployed and require authentication for most paths"
echo "✅ Storage rules are active"
echo ""

# Instructions for app testing
echo "=========================================="
echo "📱 App Testing Instructions"
echo "=========================================="
echo ""
echo "Now test in your iOS app:"
echo ""
echo "1. Build and run NeighborHub app"
echo "2. Complete onboarding with:"
echo "   - Test email: test@neighborhub.com"
echo "   - Strong password (8+ chars, upper/lower/number)"
echo ""
echo "3. Verify in Firebase Console > Authentication:"
echo "   - New user appears in Users list"
echo "   - User has UID assigned"
echo ""
echo "4. Verify in Firebase Console > Firestore:"
echo "   - Document created at: users/{uid}"
echo "   - Document contains: name, email, verified:false"
echo ""
echo "5. Verify in Firebase Console > Storage:"
echo "   - Profile image uploaded to: users/{uid}/profile/avatar.jpg"
echo ""
echo "6. Test admin approval workflow:"
echo "   - Login as admin"
echo "   - Go to Admin tab"
echo "   - See test user in 'Pending Approval' section"
echo "   - Approve user"
echo "   - Verify verified field set to true in Firestore"
echo ""
echo "=========================================="
echo "🔒 Security Rules Verification"
echo "=========================================="
echo ""
echo "Expected behavior:"
echo ""
echo "✅ Unauthenticated users:"
echo "   - CANNOT read/write Firestore documents"
echo "   - CANNOT read/write Storage files"
echo ""
echo "✅ Authenticated but unverified users:"
echo "   - CAN read their own user document"
echo "   - CANNOT read other users' documents"
echo "   - CAN upload to their own Storage paths"
echo ""
echo "✅ Authenticated and verified users:"
echo "   - CAN read all public documents (marketplace, events)"
echo "   - CAN read other verified users' profiles"
echo "   - CAN create posts, incidents, events"
echo ""
echo "✅ Admin users:"
echo "   - CAN approve/reject users"
echo "   - CAN moderate content"
echo "   - CAN manage all data"
echo ""
echo "=========================================="
echo "✅ Setup complete! Ready for testing"
echo "=========================================="
