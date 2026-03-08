#!/bin/bash
# Android NeighborHub - iOS Parity Diagnostic Script

echo "🔍 NeighborHub Android - iOS Parity Diagnostic"
echo "=============================================="
echo ""

cd "/Users/mike/Desktop/Waterfall 3 V1.06/NeighborHub_Android"

echo "📱 Project Structure:"
echo "--------------------"
echo "Kotlin files: $(find app/src/main -name "*.kt" | wc -l | xargs)"
echo "Layout files: $(find app/src/main/res/layout -name "*.xml" 2>/dev/null | wc -l | xargs)"
echo "Drawable files: $(find app/src/main/res/drawable* -type f 2>/dev/null | wc -l | xargs)"
echo ""

echo "🔧 Key Managers Present:"
echo "------------------------"
for manager in "CommunityMessagesManager" "EmergencyRequestManager" "PollsManager" "NewsletterManager" "WeatherManager" "LocationManager"; do
    if find app/src/main -name "${manager}.kt" | grep -q .; then
        echo "✅ $manager"
    else
        echo "❌ $manager - MISSING"
    fi
done
echo ""

echo "📄 Key Activities Present:"
echo "--------------------------"
for activity in "MainActivity" "AuthWelcomeActivity" "CreateNewsletterActivity" "EmergencyRequestActivity"; do
    if find app/src/main -name "${activity}.kt" | grep -q .; then
        echo "✅ $activity"
    else
        echo "❌ $activity - MISSING"
    fi
done
echo ""

echo "🎨 Key Fragments Present:"
echo "-------------------------"
for fragment in "HomeFragment" "CommunityChatFragment" "EventsFragment" "MarketplaceFragment" "NewslettersFragment"; do
    if find app/src/main -name "${fragment}.kt" | grep -q .; then
        echo "✅ $fragment"
    else
        echo "❌ $fragment - MISSING"
    fi
done
echo ""

echo "🔥 Firebase Configuration:"
echo "--------------------------"
if [ -f "google-services.json" ]; then
    echo "✅ google-services.json present"
    echo "   Package: $(grep 'package_name' google-services.json | head -1 | cut -d'"' -f4)"
else
    echo "❌ google-services.json - MISSING"
fi
echo ""

echo "📦 Dependencies Check:"
echo "---------------------"
if grep -q "firebase-bom" app/build.gradle.kts 2>/dev/null; then
    echo "✅ Firebase BOM configured"
else
    echo "❌ Firebase BOM - check app/build.gradle.kts"
fi

if grep -q "material" app/build.gradle.kts 2>/dev/null; then
    echo "✅ Material Design library"
else
    echo "❌ Material Design - missing"
fi
echo ""

echo "🏗️ Build Status:"
echo "----------------"
if ./gradlew clean > /dev/null 2>&1; then
    echo "✅ Gradle clean successful"
else
    echo "⚠️  Gradle clean had issues"
fi
echo ""

echo "📊 Comparison with iOS:"
echo "----------------------"
IOS_VIEWS=$(find ../NeighborHub -name "*.swift" | wc -l | xargs)
ANDROID_VIEWS=$(find app/src/main -name "*.kt" | wc -l | xargs)
echo "iOS Swift files: $IOS_VIEWS"
echo "Android Kotlin files: $ANDROID_VIEWS"
echo ""

echo "🎯 Common Issues to Check:"
echo "--------------------------"
echo "1. Colors match? Check app/src/main/res/values/colors.xml"
echo "2. Bottom nav setup? Check MainActivity.kt"
echo "3. Firebase listeners? Check Manager files"
echo "4. LiveData observers? Check Fragment files"
echo "5. RecyclerView adapters? Check adapters/"
echo ""

echo "💡 Next Steps:"
echo "--------------"
echo "1. Open Android Studio"
echo "2. Build → Clean Project"
echo "3. Build → Rebuild Project"
echo "4. Run app and check logcat for errors"
echo "5. Compare specific screens with iOS version"
echo ""

echo "📖 For detailed fixes, see: ANDROID_TROUBLESHOOTING.md"
