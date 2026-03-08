# Video Player Error -12785 - Diagnosis & Fix

## Issue Identified

Based on your console logs, the video system is **working correctly** through the upload phase:

```
✅ ChatMessagesManager: Message updated with video URL successfully
   - Recipients will now be able to download and view video
```

**BUT** when trying to play the video, AVPlayer throws error `-12785`:

```
<<<< Async >>>> signalled err=-12785 at <>:3919
<<<< PlayerRemoteXPC >>>> signalled err=-12785 at <>:1101
```

## What Error -12785 Means

**Error Code**: `-12785` = `kAudioConverterErr_FormatNotSupported`

**Possible Causes:**
1. ❌ Video codec not supported by AVPlayer
2. ❌ Audio codec not supported by AVPlayer
3. ❌ File corrupted during download
4. ❌ File URL passed to AVPlayer is incorrect
5. ⚠️ Firebase Storage URL requires authentication headers (AVPlayer can't handle)

## Current Flow Analysis

### What's Working ✅

1. **Upload to Storage**: Video uploads successfully
   ```
   📤 Uploading to Storage path: uploads/{uid}/communityMessages/{id}/video.MOV
   ✅ Video uploaded successfully!
   ```

2. **Firestore Update**: Message document updated with `fileURL`
   ```
   📝 Updating Firestore message with fileURL...
   ✅ Message updated with video URL successfully
   ```

3. **FileMessageView Detection**: Video is detected and displayed
   ```
   🎬 FileMessageView rendering for message 22F583B7-54E4-439F-9CAF-BCC33B879310
      - fileName: video.MOV
      - fileURL: https://firebasestorage.googleapis.com/...
      - fileLocalURL: nil
      - fileData: nil
   ```

4. **Download Logic**: Video download completes successfully
   ```
   FileMessageView: Video downloaded to: /tmp/...
   FileMessageView: Video moved to final destination: /tmp/NeighborHub/Videos/video.MOV
   FileMessageView: Calling onPreviewVideo with local file
   ```

### What's Failing ❌

**AVPlayer Setup**: When `PopupVideoPlayerView` tries to create an AVPlayer with the downloaded file, it fails with error -12785.

## Enhanced Logging Added

### 1. PopupVideoPlayerView.setupPlayer()

Now logs:
```swift
🎬 Setting up popup player for URL: {url}
   - Is file URL: true/false
   - Scheme: file/http/https
   - Path: /path/to/video
   - Absolute string: full URL
   - File exists check: true/false
   - File size: X bytes
📺 Creating AVPlayer with URL...
   - AVPlayerItem created: {item}
   - Initial status: {status}
```

### 2. checkPlayerStatus()

Now logs:
```swift
📊 Checking player item status: 0/1/2
✅ Popup player ready to play
   OR
❌ Popup player failed!
   - Error: {description}
   - Code: {code}
   - Domain: {domain}
   - Full error: {error object}
```

## Next Steps to Debug

### Test 1: Verify Downloaded File
When you send a video and tap to play, check the logs for:

```
🎬 Setting up popup player for URL: file:///tmp/NeighborHub/Videos/video.MOV
   - Is file URL: true
   - File exists check: true/false  ← Should be TRUE
   - File size: X bytes  ← Should be > 0
```

**If file exists but size is 0**: Download is failing silently.
**If file doesn't exist**: Download path is incorrect.

### Test 2: Check AVPlayer Error Details
Look for:

```
❌ Popup player failed!
   - Error: {exact error message}
   - Code: {error code}
   - Domain: {error domain}
```

This will tell us:
- If it's a codec issue (video format incompatible)
- If it's a file access issue (permissions)
- If it's a URL issue (wrong path)

### Test 3: Verify Video Format
The video filename shows:
```
28737B35-40C9-4B52-81D2-DF290A10E60C-78422417693__F9B24D3A-C174-4C0F-B5F6-96A389A6201C.MOV
```

**.MOV files from iPhone** should work fine with AVPlayer, but:
- ⚠️ HEVC (H.265) codec might not be supported on all simulators
- ⚠️ ProRAW/ProRes formats might fail
- ⚠️ Corrupted downloads might have 0 bytes

## Potential Fixes

### Fix 1: Force Re-encode Video (If Codec Issue)

If the error is codec-related, add video compression before upload:

```swift
func compressVideo(url: URL, completion: @escaping (URL?) -> Void) {
    let asset = AVAsset(url: url)
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
        completion(nil)
        return
    }
    
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("compressed-\(UUID().uuidString).mp4")
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    
    exportSession.exportAsynchronously {
        if exportSession.status == .completed {
            completion(outputURL)
        } else {
            print("Compression failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
            completion(nil)
        }
    }
}
```

### Fix 2: Validate Downloaded File

Add validation after download:

```swift
// After download completes
let asset = AVAsset(url: downloadedURL)
Task {
    do {
        let isPlayable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        
        guard isPlayable && duration.seconds > 0 else {
            print("❌ Downloaded file is not playable or has 0 duration")
            // Show error to user
            return
        }
        
        // Proceed with playback
        onPreviewVideo?(downloadedURL)
    } catch {
        print("❌ Failed to validate video: \(error)")
    }
}
```

### Fix 3: Use Different Video Player

If AVPlayer continues to fail, consider using a custom video player with AVPlayerLayer:

```swift
class VideoPlayerViewController: UIViewController {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = .resizeAspect
        
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }
        
        player?.play()
    }
}
```

## What to Test Now

1. **Send a video** in the community chat
2. **Tap the video** to open the player
3. **Check the console** for the new detailed logs:
   - File existence check
   - File size
   - AVPlayer creation
   - Error code and message

**Share the new console output** and we can pinpoint the exact failure point!

---

## Summary

✅ Upload working  
✅ Firestore sync working  
✅ Download working  
❌ AVPlayer playback failing with error -12785

**Root Cause**: Likely codec incompatibility or corrupted download  
**Solution**: Enhanced logging will reveal exact cause  
**Next**: Test video playback and check console output
