# App Store Screenshot Guide - NeighborHub

## 📱 Required Device Sizes

Apple requires screenshots for at least ONE of these sizes:

### Priority 1 (REQUIRED):
- **6.7" Display** - iPhone 15 Pro Max, 14 Pro Max, 15 Plus, 14 Plus
  - Resolution: 1290 x 2796 pixels

### Priority 2 (Recommended):
- **6.5" Display** - iPhone 11 Pro Max, XS Max, 11, XR
  - Resolution: 1242 x 2688 pixels

### Priority 3 (Optional):
- **5.5" Display** - iPhone 8 Plus, 7 Plus, 6s Plus
  - Resolution: 1242 x 2208 pixels

**iPad (if supporting iPad):**
- **12.9" iPad Pro** - Resolution: 2048 x 2732 pixels

## 🎯 Recommended Screenshots (5-10 images)

Capture these screens in order:

### 1. **Home Screen / Main Dashboard** ⭐ FIRST IMPRESSION
   - Shows emergency features
   - Weather widget
   - Quick access buttons
   - Community updates preview

### 2. **ReportIt - Safety Incidents** 🚨
   - Incident cards with photos
   - Filter options visible
   - Shows community safety in action

### 3. **Community Chat** 💬
   - Active conversation
   - Shows neighbor engagement
   - Reply/reaction features visible

### 4. **Events Calendar** 📅
   - Upcoming neighborhood events
   - RSVP functionality
   - Shows community connection

### 5. **Marketplace** 🛍️
   - Active listings with photos
   - Shows local commerce features
   - Categories visible

### 6. **Emergency Features** 🆘 (UNIQUE SELLING POINT)
   - Emergency contact tree
   - Quick dial buttons
   - Shows safety-first approach

### 7. **Business Directory** 🏪 (Optional)
   - Local businesses
   - Search functionality
   - Shows neighborhood support

### 8. **Polls/Voting** 🗳️ (Optional)
   - Community decision making
   - Shows democratic features

## 📸 Screenshot Tips

### Do's:
✅ Use light mode (better visibility)
✅ Show real content (not empty states)
✅ Hide status bar (Settings → Simulator → Hide Status Bar)
✅ Capture at actual device size
✅ Show the app in action (messages, events, listings)
✅ Highlight unique features (emergency system)

### Don'ts:
❌ Don't show personal information
❌ Don't use lorem ipsum or fake data
❌ Don't show error states
❌ Don't capture with low quality
❌ Don't show empty screens

## 🚀 Quick Capture Steps

### Step 1: Open Simulator
```bash
# Open iPhone 15 Pro Max (6.7" - REQUIRED)
open -a Simulator

# In Simulator menu: File → Open Simulator → iPhone 15 Pro Max
```

### Step 2: Build and Run
1. Open NeighborHub.xcodeproj in Xcode
2. Select "iPhone 15 Pro Max" as target
3. Press Cmd+R to run

### Step 3: Prepare the Screen
1. Register/login if needed
2. Navigate to the screen you want to capture
3. Make sure content looks good
4. Hide keyboard if visible (Cmd+K in simulator)

### Step 4: Capture Screenshot
- Press **Cmd+S** in Simulator
- Screenshot saves to Desktop automatically
- File name format: `Simulator Screenshot - iPhone 15 Pro Max - 2025-12-26 at 14.30.15.png`

### Step 5: Organize Screenshots
Move to organized folders:
```bash
mkdir -p ~/Desktop/NeighborHub-Screenshots/6.7-inch
mv ~/Desktop/Simulator\ Screenshot*.png ~/Desktop/NeighborHub-Screenshots/6.7-inch/
```

## 📁 File Organization

Create this structure:
```
NeighborHub-Screenshots/
├── 6.7-inch/           (iPhone 15 Pro Max) - REQUIRED
│   ├── 01-home.png
│   ├── 02-reportit.png
│   ├── 03-chat.png
│   ├── 04-events.png
│   └── 05-marketplace.png
├── 6.5-inch/           (iPhone 11 Pro Max) - Optional
└── iPad-12.9/          (iPad Pro) - If supporting iPad
```

## 🎨 Making Screenshots Pop

### Add Marketing Polish (Optional):
You can add text overlays and highlights using:
- **Figma** (free): https://figma.com
- **Canva** (free): https://canva.com
- **Screenshot Maker**: https://screenshots.pro

### Example Marketing Text:
1. "Connect with Your Neighbors" (Home)
2. "Stay Safe Together" (ReportIt)
3. "Chat & Share" (Community)
4. "Local Events" (Events)
5. "Buy & Sell Locally" (Marketplace)

## ✅ Final Checklist

Before uploading to App Store Connect:

- [ ] At least 5 screenshots for 6.7" display
- [ ] Screenshots are 1290 x 2796 pixels
- [ ] Files are PNG or JPEG format
- [ ] File size under 500KB each
- [ ] No personal information visible
- [ ] Content looks professional
- [ ] Screenshots showcase key features
- [ ] Emergency features highlighted

## 🎯 Pro Tips

1. **First screenshot is CRITICAL** - This is what users see first
2. **Show the app in use** - People with messages, events, etc.
3. **Highlight unique features** - Emergency system is your differentiator
4. **Keep it simple** - Don't overwhelm with too much info
5. **Test on real device** - If colors/layout look off in simulator

## 📤 Uploading to App Store Connect

1. Go to App Store Connect
2. Select your app → App Store tab
3. Scroll to Screenshots section
4. Drag and drop images
5. Arrange in best order (first = most important)

---

**Need help?** Run the automated screenshot script (coming next) or manually follow these steps.
