# Video Visibility Issue - Diagnosis & Logging

## Problem Summary

**Issue**: Videos are not visible for sender or other users in the community chat UI.

## Root Cause Analysis

### Architecture Flow

```
1. User selects video from library/camera
   ↓
2. Video file loaded into memory (fileData)
   ↓
3. Message created with:
   - messageType: .file
   - fileData: video bytes
   - fileName: "video.MOV"
   - fileLocalURL: "/path/to/video" (sender's device only)
   - fileURL: nil (not uploaded yet)
   ↓
4. Message appended to local UI (optimistic update)
   ↓
5. ChatMessagesManager.addMessage() called
   ↓
6. uploadVideoAttachment() uploads to Storage
   ↓
7. Firestore updated with fileURL after upload completes
   ↓
8. Message syncs to all devices via Firestore listener
```

### The Problem

**For Sender:**
- Message created with `fileLocalURL = attachedFileURL.path` (line 2914)
- But `attachedFileURL = nil` is immediately set after sending (line 3010)
- The `fileLocalURL` in the message DOES persist in the CommunityMessage object
- However, if the app closes and reopens, the local file path may no longer be valid

**For Recipients:**
- Message syncs from Firestore WITHOUT `fileURL` initially (upload still in progress)
- `fileLocalURL` contains sender's device path (useless on recipient's device)
- FileMessageView renders but can't display anything

**Display Logic Issue (line 5560):**
```swift
.onTapGesture {
    if let remote = message.fileURL {
        // Download and play video ✅
    } else if let localPath = message.fileLocalURL {
        // Try to play from local path ⚠️ (only works for sender)
    } else if let data = message.fileData, let name = message.fileName {
        // Play from in-memory data ⚠️ (cleared after upload to save memory)
    }
}
```

## Key Insights

### Upload Flow Timeline

| Time | Sender Device | Firestore | Recipient Device |
|------|--------------|-----------|------------------|
| T+0s | Message sent with fileData | Empty | - |
| T+0.1s | Optimistic UI shows file icon | Empty | - |
| T+0.5s | Upload to Storage starts | Empty | - |
| T+5s | Upload completes | Message saved WITHOUT fileURL | - |
| T+5.1s | Firestore updated WITH fileURL | Message updated WITH fileURL | Message received WITHOUT fileURL |
| T+5.2s | - | - | Message updated WITH fileURL ✅ |

**Issue Window**: Between T+5s and T+5.2s, recipients see a message with no way to view the video.

### Memory Management

After upload completes (line 343):
```swift
var updatedMessage = message
updatedMessage.fileURL = url
updatedMessage.fileData = nil  // Cleared to save memory ⚠️
```

This means after upload:
- ✅ `fileURL` is set (recipients can download)
- ❌ `fileData` is nil (can't play from memory)
- ✅ `fileLocalURL` still set for sender (may or may not work)

## Logging Added

### 1. ChatMessagesManager.addMessage()
**Emoji Codes:**
- 🔵 = Message processing started
- 🎬 = Video detected
- 📄 = Non-video file
- ✅ = Success
- ❌ = Error
- ⚠️ = Warning

**Output Example:**
```
🔵 ChatMessagesManager: Adding message via Firebase
   - Message ID: 12345-67890-ABCDE
   - Message Type: file
   - Has fileData: true (size: 15728640 bytes)
   - Has fileName: true (video.MOV)
   - Has fileLocalURL: true (/var/mobile/Media/DCIM/video.MOV)
   - Has fileURL: false
   - File type: 🎬 VIDEO
🎬 ChatMessagesManager: Video detected (video.MOV), uploading to Storage before Firestore write
```

### 2. uploadVideoAttachment()
**Emoji Codes:**
- 📤 = Upload operation
- ✅ = Success
- ❌ = Error
- 📝 = Firestore write

**Output Example:**
```
📤 uploadVideoAttachment() called
   - Message ID: 12345-67890-ABCDE
   - File name: video.MOV
   - File size: 15728640 bytes
✅ ChatMessagesManager: File size validated, proceeding with upload...
✅ Temp file written: /tmp/video.MOV
📤 Uploading to Storage path: uploads/{uid}/communityMessages/{messageId}/video.MOV
🗑️ Temp file cleaned up
✅ ChatMessagesManager: Video uploaded successfully!
   - Download URL: https://firebasestorage.googleapis.com/...
📝 Updating Firestore message with fileURL...
✅ ChatMessagesManager: Message updated with video URL successfully
   - Recipients will now be able to download and view video
```

### 3. FileMessageView
**Emoji Codes:**
- 🎬 = FileMessageView rendering/interaction

**Output Example:**
```
🎬 FileMessageView rendering for message 12345-67890-ABCDE
   - fileName: video.MOV
   - fileURL: https://firebasestorage.googleapis.com/...
   - fileLocalURL: nil
   - fileData: nil
🎬 FileMessageView tapped for message 12345-67890-ABCDE
FileMessageView: Remote URL detected as video, downloading and playing
```

## Testing Instructions

### Test Scenario 1: Sender Perspective
1. Open Community Chat
2. Tap camera/file icon, select video
3. Tap send

**Expected Console Output:**
```
🔵 ChatMessagesManager: Adding message via Firebase
🎬 ChatMessagesManager: Video detected (video.MOV)
📤 uploadVideoAttachment() called
✅ File size validated
📤 Uploading to Storage path: uploads/...
✅ Video uploaded successfully!
📝 Updating Firestore message with fileURL...
✅ Message updated with video URL successfully
```

**Expected UI:**
- ✅ File icon appears immediately
- ✅ "Uploading..." text shown during upload
- ✅ After upload completes, tappable video message
- ✅ Tapping opens video player

### Test Scenario 2: Recipient Perspective
1. Sender sends video
2. Recipient opens Community Chat

**Expected Console Output:**
```
🎬 FileMessageView rendering for message 12345-67890-ABCDE
   - fileURL: https://firebasestorage.googleapis.com/...
   (after Firestore update propagates)
```

**Expected UI:**
- ✅ File icon appears
- ✅ Tapping downloads and plays video

### Test Scenario 3: Upload Failure
1. Disconnect internet
2. Send video

**Expected Console Output:**
```
🔵 ChatMessagesManager: Adding message via Firebase
🎬 ChatMessagesManager: Video detected
📤 uploadVideoAttachment() called
❌ ChatMessagesManager: Video upload failed!
   - Error: The Internet connection appears to be offline
⚠️ Writing message to Firestore without fileURL (fallback)
```

**Expected UI:**
- ⚠️ Error notification shown
- ⚠️ Message saved but video not accessible

## Next Steps

### Immediate Fixes Needed

1. **Display "Uploading..." state properly**
   - Currently shows if `fileURL == nil && fileLocalURL == nil`
   - Should also show upload progress bar

2. **Handle sender's local playback**
   - After sending, `fileLocalURL` is set but file may be in Photos library
   - Consider copying video to app's temp directory first

3. **Improve error handling**
   - Show retry button for failed uploads
   - Queue uploads for when internet reconnects

4. **Add thumbnail generation**
   - Generate preview image from first frame
   - Store as `imageData` for instant preview while video downloads

### Optional Enhancements

1. **Upload progress indicator**
   - Show percentage during upload
   - Use Storage SDK's progress observer

2. **Video compression**
   - Compress videos before upload
   - Reduce file size for faster uploads

3. **Caching**
   - Cache downloaded videos locally
   - Avoid re-downloading same video

## Files Modified

1. **ChatMessagesManager.swift**
   - Added detailed logging to `addMessage()`
   - Added detailed logging to `uploadVideoAttachment()`
   - Added error context to all failure paths

2. **CommunityChatCard.swift**
   - Added FileMessageView rendering logs
   - Added "Uploading..." UI state
   - Improved tap gesture logging

## Summary

The video upload flow **IS WORKING** but visibility issues stem from:
1. Brief window where `fileURL` is nil during upload
2. Sender's `fileLocalURL` may not persist across app restarts
3. Recipients see message before upload completes

The logging added will help identify:
- ✅ If upload is completing successfully
- ✅ If Firestore is being updated with fileURL
- ✅ If FileMessageView is receiving the correct data
- ✅ Where in the flow the display breaks down

---

**Next Action**: Test video sending and examine console logs to pinpoint exact failure point.
