# CommunityChatCard Refactoring Plan

## Current State
- **File**: `NeighborHub/Views/CommunityChatCard.swift`
- **Size**: 8,632 lines
- **Problem**: Extremely large file causing:
  - Slow compilation times
  - Difficult code navigation
  - Increased memory usage during builds
  - Xcode indexing delays

## Refactoring Strategy

### Phase 1: Extract Video Components (Est. ~500 lines)
**New File**: `ChatVideoPlayer.swift`

**Components to Extract**:
- `EnhancedVideoPreviewView` (Lines 6109-6364)
- `FullScreenVideoPlayerView` (Lines 6365-6609)
- `PopupVideoPlayerView` (Lines 6610-6812)
- Video helper functions

**Dependencies**:
- AVKit framework
- AVFoundation

**Benefits**: ~500 lines removed

---

### Phase 2: Extract Business Card Components (Est. ~600 lines)
**New File**: `ChatBusinessCard.swift`

**Components to Extract**:
- `SharedBusinessCardInChatView` (Lines 7697-8022)
- `SharedBusinessListInChatView` (Lines 8024-8216)
- `CompactBusinessRowView` (Lines 8218-8590)
- `BusinessListData` struct
- Business-related helpers

**Dependencies**:
- LocalBusiness model
- MapKit

**Benefits**: ~600 lines removed

---

### Phase 3: Extract Message Bubble (Est. ~1000 lines)
**New File**: `ChatMessageBubble.swift`

**Components to Extract**:
- `MessageBubbleView` (Lines 4555-5615)
- `BubbleTransformModifier` (Lines 6084-6101)
- `BubbleAnimationModifier` (Lines 7466-7486)
- Content warning view
- Dynamic color effects
- File message views

**Dependencies**:
- CommunityMessage model
- SimpleContentModerator

**Benefits**: ~1000 lines removed

---

### Phase 4: Extract Audio Components (Est. ~400 lines)
**New File**: `ChatAudioPlayer.swift`

**Components to Extract**:
- `AudioPlayer` class (Lines 7059-7339)
- `AudioMessageView` (Lines 7340-7465)
- Voice recorder helper
- Audio file handling

**Dependencies**:
- AVFoundation
- Audio session configuration

**Benefits**: ~400 lines removed

---

### Phase 5: Extract GIF Components (Est. ~200 lines)
**New File**: `ChatGifViewer.swift`

**Components to Extract**:
- `PopupGifView` (Lines 6814-6911)
- `AnimatedGifView` (Lines 6912-6933)
- `AsyncGifView` (Lines 6934-7058)
- GIF loading helpers

**Dependencies**:
- UIKit for GIF animation
- Caching logic

**Benefits**: ~200 lines removed

---

### Phase 6: Extract Input Bar (Est. ~400 lines)
**New File**: `ChatInputBar.swift`

**Components to Extract**:
- Message input view (Lines 1331-1600)
- Context bars (reply/edit) (Lines 1601-1652)
- `ActionCircleButton` (Lines 1653-1734)
- Input helper properties (Lines 1735-1766)
- Attachment buttons and logic

**Dependencies**:
- CommunityMessage
- Image/File pickers

**Benefits**: ~400 lines removed

---

### Phase 7: Extract Utility Components (Est. ~300 lines)
**New File**: `ChatHelpers.swift`

**Components to Extract**:
- `CameraPickerDelegate` (Lines 7555-7571)
- Image picker wrappers (Lines 7580-7645)
- `ChatDocumentPicker` (Lines 7647-7695)
- `DateSeparatorView` (Lines 7494-7532)
- `RoundedCorner` shape (Lines 7540-7553)
- `TappableLinksText` (Lines 8593-8633)

**Dependencies**:
- UIKit
- PhotosUI
- UniformTypeIdentifiers

**Benefits**: ~300 lines removed

---

### Phase 8: Extract Models & Enums (Est. ~200 lines)
**New File**: `ChatModels.swift`

**Components to Extract**:
- `CommunityMessage` struct (Lines 4387-4489)
- `MessageType` enum (Lines 4490-4493)
- `SimpleContentModerator` struct (Lines 4282-4386)
- `MessageGroup` struct (Lines 4549-4553)
- `AnimationPhase` enum (Lines 126-129)

**Benefits**: ~200 lines removed

---

## Execution Plan

### Step-by-Step Process

1. **Create New Files** (in order):
   ```
   NeighborHub/Views/Chat/
   ├── ChatModels.swift          (Phase 8 - Do first for dependencies)
   ├── ChatHelpers.swift         (Phase 7)
   ├── ChatGifViewer.swift       (Phase 6)
   ├── ChatAudioPlayer.swift     (Phase 5)
   ├── ChatMessageBubble.swift   (Phase 3)
   ├── ChatInputBar.swift        (Phase 6)
   ├── ChatBusinessCard.swift    (Phase 2)
   └── ChatVideoPlayer.swift     (Phase 1)
   ```

2. **For Each File**:
   - Extract code from CommunityChatCard.swift
   - Add necessary imports
   - Keep `internal` or `public` access as needed
   - Add `// MARK:` comments for organization
   - Test compilation

3. **Update Main File**:
   - Add imports for new files
   - Remove extracted code
   - Update references if needed
   - Verify all functionality works

4. **Testing Checklist**:
   - [ ] Messages display correctly
   - [ ] Video playback works
   - [ ] Audio messages play
   - [ ] GIFs animate
   - [ ] Business cards display
   - [ ] Input bar functions
   - [ ] All gestures work (long press, swipe, etc.)
   - [ ] Dark mode still works
   - [ ] Animations smooth
   - [ ] No compilation errors

---

## Expected Results

### Before Refactoring
- Main file: 8,632 lines
- Build time: ~45-60 seconds (clean build)
- Xcode indexing: Slow

### After Refactoring
- Main file: ~4,000 lines (-52% reduction)
- 8 supporting files: ~600-1000 lines each
- Build time: ~25-35 seconds (est. 30-40% improvement)
- Xcode indexing: Much faster
- Better code navigation
- Easier maintenance

---

## Implementation Command

```bash
# Create Chat directory
mkdir -p "NeighborHub/Views/Chat"

# Phase by phase extraction (manual process)
# Each phase requires:
# 1. Create new file
# 2. Copy code sections
# 3. Add imports
# 4. Remove from main file
# 5. Test compilation
# 6. Verify functionality
```

---

## Risk Mitigation

1. **Backup Current File**:
   ```bash
   cp NeighborHub/Views/CommunityChatCard.swift NeighborHub/Views/CommunityChatCard.swift.backup
   ```

2. **Git Commit Before Each Phase**:
   ```bash
   git add .
   git commit -m "Refactor: Extract [component name] from CommunityChatCard"
   ```

3. **Test After Each Phase**:
   - Run app in simulator
   - Test extracted functionality
   - Verify no regressions

---

## Notes

- This refactoring is **HIGH PRIORITY** due to build performance impact
- Estimated total time: 6-8 hours for complete refactoring
- Can be done incrementally over multiple sessions
- Each phase is independent and can be tested separately
- Consider pairing with code review after each phase

---

## Current Status

✅ Backup files deleted (HomeView.swift.bak*, MarketplaceDetailView_old.swift)
⏳ Refactoring plan documented
🔲 Phase 1-8 execution pending

---

*Last Updated: November 18, 2025*
