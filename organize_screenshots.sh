#!/bin/bash
# NeighborHub Screenshot Organizer
# Helps organize screenshots captured from iOS Simulator

set -e

echo "📸 NeighborHub Screenshot Organizer"
echo "===================================="
echo ""

# Create directory structure
SCREENSHOT_DIR="$HOME/Desktop/NeighborHub-Screenshots"
mkdir -p "$SCREENSHOT_DIR/6.7-inch"
mkdir -p "$SCREENSHOT_DIR/6.5-inch"
mkdir -p "$SCREENSHOT_DIR/5.5-inch"
mkdir -p "$SCREENSHOT_DIR/iPad-12.9"

echo "✅ Created screenshot directories at:"
echo "   $SCREENSHOT_DIR"
echo ""

# Function to move and rename screenshots
organize_screenshots() {
    local device_size=$1
    local device_name=$2
    local target_dir="$SCREENSHOT_DIR/$device_size"
    
    echo "Looking for $device_name screenshots..."
    
    # Find simulator screenshots on Desktop
    count=0
    for file in "$HOME/Desktop/Simulator Screenshot - $device_name"*.png; do
        if [ -f "$file" ]; then
            count=$((count + 1))
            new_name="screenshot-$(printf %02d $count).png"
            mv "$file" "$target_dir/$new_name"
            echo "  ✓ Moved: $new_name"
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "  ℹ️  No screenshots found for $device_name"
    else
        echo "  📁 Organized $count screenshot(s) in $device_size/"
    fi
    echo ""
}

# Organize by device
organize_screenshots "6.7-inch" "iPhone 15 Pro Max"
organize_screenshots "6.7-inch" "iPhone 15 Plus"
organize_screenshots "6.7-inch" "iPhone 14 Pro Max"
organize_screenshots "6.5-inch" "iPhone 11 Pro Max"
organize_screenshots "6.5-inch" "iPhone XS Max"
organize_screenshots "5.5-inch" "iPhone 8 Plus"
organize_screenshots "iPad-12.9" "iPad Pro (12.9-inch)"

echo "===================================="
echo "✅ Screenshot organization complete!"
echo ""
echo "📁 Your screenshots are organized in:"
echo "   $SCREENSHOT_DIR"
echo ""
echo "📊 Screenshot counts:"
ls -1 "$SCREENSHOT_DIR/6.7-inch" 2>/dev/null | wc -l | xargs echo "   6.7-inch: "
ls -1 "$SCREENSHOT_DIR/6.5-inch" 2>/dev/null | wc -l | xargs echo "   6.5-inch: "
ls -1 "$SCREENSHOT_DIR/5.5-inch" 2>/dev/null | wc -l | xargs echo "   5.5-inch: "
ls -1 "$SCREENSHOT_DIR/iPad-12.9" 2>/dev/null | wc -l | xargs echo "   iPad 12.9: "
echo ""
echo "🎯 Next steps:"
echo "   1. Review screenshots in Finder"
echo "   2. Rename descriptively (01-home.png, 02-reportit.png, etc.)"
echo "   3. Upload to App Store Connect"
echo ""
echo "💡 Tip: You need at least 5 screenshots for 6.7-inch display"
