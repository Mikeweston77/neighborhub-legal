#!/bin/bash

# Deploy GIF-enabled Cloud Functions to Firebase
# This script deploys the updated Cloud Functions with GIF storage separation support

set -e  # Exit on error

echo "🎭 NeighborHub - Deploying GIF Storage Separation Updates"
echo "========================================================"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if logged in to Firebase
echo "📋 Checking Firebase authentication..."
if ! firebase projects:list &> /dev/null; then
    echo "❌ Not logged in to Firebase!"
    echo "Run: firebase login"
    exit 1
fi

echo "✅ Firebase CLI ready"
echo ""

# Navigate to functions directory
cd "$(dirname "$0")/functions"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing Cloud Functions dependencies..."
    npm install
    echo "✅ Dependencies installed"
    echo ""
fi

# Show current project
echo "🎯 Current Firebase project:"
firebase use

echo ""
echo "⚠️  This will deploy Cloud Functions with the following updates:"
echo "   • GIF detection in upload paths"
echo "   • Separate storage: final/communityMessages/gifs/"
echo "   • Animation preservation for GIFs"
echo "   • First-frame thumbnail extraction"
echo ""

read -p "Continue with deployment? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo ""
echo "🚀 Deploying Cloud Functions..."
firebase deploy --only functions

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment successful!"
    echo ""
    echo "🎭 GIF storage separation is now active!"
    echo ""
    echo "Test the deployment:"
    echo "  1. Open NeighborHub app on iOS"
    echo "  2. Paste a GIF in community chat"
    echo "  3. Check Firebase Console → Storage"
    echo "     • Look for: uploads/.../communityMessages/gifs/"
    echo "  4. Check Firebase Console → Functions → Logs"
    echo "     • Look for: 🎭 Cloud Function: Detected GIF upload"
    echo ""
else
    echo ""
    echo "❌ Deployment failed!"
    echo "Check the error messages above"
    exit 1
fi
