#!/usr/bin/env python3
"""
iOS App Icon Generator
Generates all required iOS app icon sizes from a 1024x1024 source image
"""

import os
import json
from PIL import Image

# Define required iOS app icon sizes (iPhone + iPad)
# Format: (filename, size_in_pixels)
ICON_SIZES = [
    # iPhone
    ("icon-20@2x.png", 40),      # 20pt @2x (Notification)
    ("icon-20@3x.png", 60),      # 20pt @3x (Notification)
    ("icon-29@2x.png", 58),      # 29pt @2x (Settings)
    ("icon-29@3x.png", 87),      # 29pt @3x (Settings)
    ("icon-40@2x.png", 80),      # 40pt @2x (Spotlight)
    ("icon-40@3x.png", 120),     # 40pt @3x (Spotlight)
    ("icon-60@2x.png", 120),     # 60pt @2x (App Icon)
    ("icon-60@3x.png", 180),     # 60pt @3x (App Icon)
    
    # iPad
    ("icon-20@1x-ipad.png", 20),     # 20pt @1x (iPad Notification)
    ("icon-20@2x-ipad.png", 40),     # 20pt @2x (iPad Notification)
    ("icon-29@1x-ipad.png", 29),     # 29pt @1x (iPad Settings)
    ("icon-29@2x-ipad.png", 58),     # 29pt @2x (iPad Settings)
    ("icon-40@1x-ipad.png", 40),     # 40pt @1x (iPad Spotlight)
    ("icon-40@2x-ipad.png", 80),     # 40pt @2x (iPad Spotlight)
    ("icon-76@1x-ipad.png", 76),     # 76pt @1x (iPad App Icon)
    ("icon-76@2x-ipad.png", 152),    # 76pt @2x (iPad App Icon)
    ("icon-83.5@2x-ipad.png", 167),  # 83.5pt @2x (iPad Pro App Icon)
    
    # App Store
    ("icon-1024.png", 1024),     # App Store Marketing
]

# Contents.json structure for iOS app icons (iPhone + iPad)
CONTENTS_JSON = {
    "images": [
        # iPhone
        {
            "filename": "icon-20@2x.png",
            "idiom": "iphone",
            "scale": "2x",
            "size": "20x20"
        },
        {
            "filename": "icon-20@3x.png",
            "idiom": "iphone",
            "scale": "3x",
            "size": "20x20"
        },
        {
            "filename": "icon-29@2x.png",
            "idiom": "iphone",
            "scale": "2x",
            "size": "29x29"
        },
        {
            "filename": "icon-29@3x.png",
            "idiom": "iphone",
            "scale": "3x",
            "size": "29x29"
        },
        {
            "filename": "icon-40@2x.png",
            "idiom": "iphone",
            "scale": "2x",
            "size": "40x40"
        },
        {
            "filename": "icon-40@3x.png",
            "idiom": "iphone",
            "scale": "3x",
            "size": "40x40"
        },
        {
            "filename": "icon-60@2x.png",
            "idiom": "iphone",
            "scale": "2x",
            "size": "60x60"
        },
        {
            "filename": "icon-60@3x.png",
            "idiom": "iphone",
            "scale": "3x",
            "size": "60x60"
        },
        # iPad
        {
            "filename": "icon-20@1x-ipad.png",
            "idiom": "ipad",
            "scale": "1x",
            "size": "20x20"
        },
        {
            "filename": "icon-20@2x-ipad.png",
            "idiom": "ipad",
            "scale": "2x",
            "size": "20x20"
        },
        {
            "filename": "icon-29@1x-ipad.png",
            "idiom": "ipad",
            "scale": "1x",
            "size": "29x29"
        },
        {
            "filename": "icon-29@2x-ipad.png",
            "idiom": "ipad",
            "scale": "2x",
            "size": "29x29"
        },
        {
            "filename": "icon-40@1x-ipad.png",
            "idiom": "ipad",
            "scale": "1x",
            "size": "40x40"
        },
        {
            "filename": "icon-40@2x-ipad.png",
            "idiom": "ipad",
            "scale": "2x",
            "size": "40x40"
        },
        {
            "filename": "icon-76@1x-ipad.png",
            "idiom": "ipad",
            "scale": "1x",
            "size": "76x76"
        },
        {
            "filename": "icon-76@2x-ipad.png",
            "idiom": "ipad",
            "scale": "2x",
            "size": "76x76"
        },
        {
            "filename": "icon-83.5@2x-ipad.png",
            "idiom": "ipad",
            "scale": "2x",
            "size": "83.5x83.5"
        },
        # App Store
        {
            "filename": "icon-1024.png",
            "idiom": "ios-marketing",
            "scale": "1x",
            "size": "1024x1024"
        }
    ],
    "info": {
        "author": "xcode",
        "version": 1
    }
}


def generate_icons(source_image_path, output_dir):
    """
    Generate all required iOS app icon sizes from a source image
    
    Args:
        source_image_path: Path to the 1024x1024 source image
        output_dir: Directory where icons will be saved
    """
    
    # Verify source image exists
    if not os.path.exists(source_image_path):
        print(f"❌ Error: Source image not found at {source_image_path}")
        return False
    
    # Load source image
    try:
        source_img = Image.open(source_image_path)
        print(f"✅ Loaded source image: {source_img.size}")
        
        # Verify it's 1024x1024
        if source_img.size != (1024, 1024):
            print(f"⚠️  Warning: Source image is {source_img.size}, recommended 1024x1024")
    except Exception as e:
        print(f"❌ Error loading image: {e}")
        return False
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate each icon size
    print(f"\n📱 Generating {len(ICON_SIZES)} icon sizes (iPhone + iPad)...")
    for filename, size in ICON_SIZES:
        try:
            # Resize with high-quality resampling
            resized_img = source_img.resize((size, size), Image.Resampling.LANCZOS)
            
            # Save as PNG
            output_path = os.path.join(output_dir, filename)
            resized_img.save(output_path, "PNG", optimize=True)
            
            print(f"  ✓ {filename} ({size}x{size})")
        except Exception as e:
            print(f"  ✗ {filename}: {e}")
            return False
    
    # Generate Contents.json
    contents_path = os.path.join(output_dir, "Contents.json")
    try:
        with open(contents_path, 'w') as f:
            json.dump(CONTENTS_JSON, f, indent=2)
        print(f"\n✅ Generated Contents.json")
    except Exception as e:
        print(f"❌ Error creating Contents.json: {e}")
        return False
    
    print(f"\n🎉 Success! All {len(ICON_SIZES)} icons generated in: {output_dir}")
    print(f"\nNext steps:")
    print(f"1. Open Xcode")
    print(f"2. Navigate to Assets.xcassets → AppIcon")
    print(f"3. Verify all iPhone and iPad icon slots are filled")
    print(f"4. Build for both iPhone and iPad targets")
    
    return True


if __name__ == "__main__":
    import sys
    
    # Default paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_source = "/Users/mike/Downloads/IMG_0743.jpeg"
    default_output = os.path.join(
        script_dir,
        "NeighborHub/Assets.xcassets/AppIcon.appiconset"
    )
    
    # Allow custom paths from command line
    source_image = sys.argv[1] if len(sys.argv) > 1 else default_source
    output_directory = sys.argv[2] if len(sys.argv) > 2 else default_output
    
    print("🚀 iOS App Icon Generator")
    print("=" * 50)
    print(f"Source: {source_image}")
    print(f"Output: {output_directory}")
    print("=" * 50)
    
    success = generate_icons(source_image, output_directory)
    
    sys.exit(0 if success else 1)
