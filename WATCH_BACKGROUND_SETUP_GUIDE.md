# Watch Background Images Setup Guide

## How to Add Custom Background Images

The NeighborHub Watch interface now supports multiple background images that users can choose from. Here's how to add your own custom images:

### 1. Image Requirements
- **Format**: JPG, PNG, or HEIC
- **Resolution**: 1170x2532 pixels (iPhone resolution) or higher
- **Aspect Ratio**: 9:19.5 (iPhone aspect ratio)
- **File Size**: Keep under 2MB for optimal performance

### 2. Adding Images to the Project

#### For each new background image:

1. **Create the image asset folder** in `NeighborHub/Assets.xcassets/`:
   ```
   watch-background-[NUMBER].imageset/
   ```

2. **Add the Contents.json file** with this structure:
   ```json
   {
     "images" : [
       {
         "filename" : "background-[NUMBER].jpg",
         "idiom" : "universal",
         "scale" : "1x"
       },
       {
         "idiom" : "universal",
         "scale" : "2x"
       },
       {
         "idiom" : "universal",
         "scale" : "3x"
       }
     ],
     "info" : {
       "author" : "xcode",
       "version" : 1
     }
   }
   ```

3. **Add your image file** to the same folder with the filename specified in Contents.json

### 3. Update the Background Options List

In `WatchView.swift`, update the `backgroundOptions` array in the `BackgroundPickerSheet`:

```swift
private let backgroundOptions: [BackgroundOption] = [
    BackgroundOption(name: "watch-background", displayName: "Original", category: "Standard"),
    BackgroundOption(name: "watch-background-1", displayName: "Urban Night", category: "City"),
    BackgroundOption(name: "watch-background-2", displayName: "Nature Trail", category: "Nature"),
    // Add your new background here:
    BackgroundOption(name: "watch-background-[NUMBER]", displayName: "Your Image Name", category: "Your Category"),
]
```

### 4. Categories Available
- **Standard**: Default/basic backgrounds
- **City**: Urban and cityscape images
- **Nature**: Natural landscapes and outdoor scenes
- **Neighborhood**: Suburban and residential areas
- **Tech**: Technology and security-themed backgrounds

### 5. Current Background Assets Created
The following background image sets have been created and are ready for your images:

- `watch-background` - Original (existing image)
- `watch-background-1` - Urban Night (City category)
- `watch-background-2` - Nature Trail (Nature category)  
- `watch-background-3` - Suburban Street (Neighborhood category)
- `watch-background-4` - Security Grid (Tech category)
- `watch-background-5` - Community Park (Nature category)
- `watch-background-6` - City Skyline (City category)
- `default-background` - Default (Standard category)

### 6. Adding Your Images

To add your custom images:

1. Copy your image files to the respective `.imageset` folders
2. Name them according to the `filename` in `Contents.json`
3. Build and run the app
4. Tap the photo icon in the top-left of the Watch view
5. Select your new background from the picker

### 7. Features

The background picker includes:
- **Live Preview**: See how text will look over your background
- **Category Filtering**: Filter backgrounds by type
- **Grid Layout**: Easy browsing of all available backgrounds
- **Persistent Selection**: Your choice is saved and remembered

### 8. Text Readability

All backgrounds automatically get:
- Reduced opacity (20-25%) for better text visibility
- Multi-layer gradient overlays
- Ultra-thin material effects
- Conditional styling for day/night modes

This ensures text remains readable regardless of the background image chosen.

## Usage

Once set up, users can:
1. Tap the photo icon (📷) in the Watch navigation bar
2. Browse backgrounds by category
3. See a live preview of how text will appear
4. Select their preferred background
5. Tap "Done" to apply the change

The selected background will be saved and used every time they view the Watch interface.
