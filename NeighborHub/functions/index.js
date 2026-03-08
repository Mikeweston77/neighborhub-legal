const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');
const sharp = require('sharp');
const os = require('os');
const path = require('path');
const fs = require('fs');

admin.initializeApp();
const storage = new Storage();

exports.processAdvertUpload = functions.storage.object().onFinalize(async (object) => {
  try {
    const bucketName = object.bucket;
    const contentType = object.contentType;
    const filePath = object.name; // e.g. uploads/<uid>/<advertId>/image.jpg
    if (!filePath) return null;

    // Skip if this is already a derived file (we'll put thumbs under thumbs/ or final/)
    if (filePath.startsWith('final/') || filePath.startsWith('thumbs/')) {
      console.log('Skipping already-processed file:', filePath);
      return null;
    }

    // Parse path to get collection, advertId and filename. Support both
    // uploads/{uid}/{advertId}/file and uploads/{uid}/{collection}/{id}/file formats.
    const parts = filePath.split('/');
    if (parts.length < 4 || parts[0] !== 'uploads') {
      console.log('Unexpected path format, skipping', filePath);
      return null;
    }
    const userId = parts[1];
    let collection = 'adverts';
    let advertId = '';
    let filename = '';
    if (parts.length >= 5) {
      // Common client uploads use uploads/{uid}/{collection}/{id}/{filename}
      collection = parts[2];
      advertId = parts[3];
      filename = parts.slice(4).join('/');
    } else {
      // Fallback: uploads/{uid}/{id}/{filename}
      advertId = parts[2];
      filename = parts.slice(3).join('/');
    }

    const bucket = storage.bucket(bucketName);
    const tempLocalFile = path.join(os.tmpdir(), path.basename(filePath));
    await bucket.file(filePath).download({ destination: tempLocalFile });

    // Basic validation
    if (!contentType || !contentType.startsWith('image/')) {
      console.log('Not an image, deleting temp and skipping');
      fs.unlinkSync(tempLocalFile);
      return null;
    }

    // Create medium and thumbnail
    const thumbLocalPath = path.join(os.tmpdir(), 'thumb-' + path.basename(filePath));
    const mediumLocalPath = path.join(os.tmpdir(), 'medium-' + path.basename(filePath));

    await sharp(tempLocalFile).resize({ width: 200 }).jpeg({ quality: 70 }).toFile(thumbLocalPath);
    await sharp(tempLocalFile).resize({ width: 1024 }).jpeg({ quality: 80 }).toFile(mediumLocalPath);

    // Upload processed files to final/ and thumbs/
  const finalPrefix = `final/${collection}/${advertId}/`;
  const thumbPrefix = `thumbs/${collection}/${advertId}/`;

    const finalName = finalPrefix + filename; // keep same filename
    const thumbName = thumbPrefix + filename;

    await bucket.upload(mediumLocalPath, { destination: finalName, metadata: { contentType: 'image/jpeg' } });
    await bucket.upload(thumbLocalPath, { destination: thumbName, metadata: { contentType: 'image/jpeg' } });

    // Generate signed URLs (short lived) or store path to construct public URLs later
    const finalFile = bucket.file(finalName);
    const thumbFile = bucket.file(thumbName);

    const [finalUrl] = await finalFile.getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });
    const [thumbUrl] = await thumbFile.getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });

    // Update Firestore advert document
    // Write processed URLs into the localAdverts collection so clients watching
    // `localAdverts` receive the update.
    const advertRef = admin.firestore().doc(`localAdverts/${advertId}`);
    await advertRef.set({
      // Clients watch `imageDatasURLs` and `imageURL`/`imageDatasURLs` fields. Add to
      // `imageDatasURLs` so the app will fetch processed images. We also include
      // thumbnailURLs for potential UI use.
      imageDatasURLs: admin.firestore.FieldValue.arrayUnion(finalUrl),
      thumbnailURLs: admin.firestore.FieldValue.arrayUnion(thumbUrl),
      processedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    // Clean up temp files
    fs.unlinkSync(tempLocalFile);
    fs.unlinkSync(thumbLocalPath);
    fs.unlinkSync(mediumLocalPath);

    console.log('Processed', filePath, 'for advert', advertId);
    return null;
  } catch (err) {
    console.error('Error processing upload:', err);
    return null;
  }
});

// ======================================================================
// Chat attachments: process uploads for chat messages
// uploads/{uid}/{chatId}/{messageId}/{filename}
// Writes final files to final/{chatId}/{messageId}/ and thumbs/{chatId}/{messageId}/
// Updates Firestore at chats/{chatId}/messages/{messageId}
// ======================================================================
exports.onChatAttachmentFinalize = functions.storage.object().onFinalize(async (object) => {
  try {
    const bucketName = object.bucket;
    const contentType = object.contentType;
    const filePath = object.name; // e.g. uploads/<uid>/<chatId>/<messageId>/image.jpg
    if (!filePath) return null;

    // Skip already processed
    if (filePath.startsWith('final/') || filePath.startsWith('thumbs/') || filePath.startsWith('quarantine/')) {
      console.log('Skipping already-processed file:', filePath);
      return null;
    }

    const parts = filePath.split('/');
    if (parts.length < 4 || parts[0] !== 'uploads') {
      console.log('Unexpected chat upload path format, skipping', filePath);
      return null;
    }
    const userId = parts[1];
    
    // Detect GIF files in separate storage path
    // Path formats:
    // - Regular: uploads/{uid}/communityMessages/{messageId}/{filename}
    // - GIF: uploads/{uid}/communityMessages/gifs/{messageId}/{filename}
    // - Private chats: uploads/{uid}/{chatId}/{messageId}/{filename}
    let chatId, messageId, filename, isGif = false;
    
    if (parts[2] === 'communityMessages' && parts[3] === 'gifs') {
      // GIF path: uploads/{uid}/communityMessages/gifs/{messageId}/{filename}
      chatId = 'communityMessages';
      messageId = parts[4];
      filename = parts.slice(5).join('/');
      isGif = true;
      console.log('🎭 Cloud Function: Detected GIF upload', { messageId, filename });
    } else if (parts[2] === 'communityMessages') {
      // Video/image path: uploads/{uid}/communityMessages/{messageId}/{filename}
      chatId = 'communityMessages';
      messageId = parts[3];
      filename = parts.slice(4).join('/');
    } else {
      // Private chat: uploads/{uid}/{chatId}/{messageId}/{filename}
      chatId = parts[2];
      messageId = parts[3];
      filename = parts.slice(4).join('/');
    }

    const bucket = storage.bucket(bucketName);
    const tempLocalFile = path.join(os.tmpdir(), path.basename(filePath));
    await bucket.file(filePath).download({ destination: tempLocalFile });

    // Basic validation
    if (!contentType) {
      console.log('Unknown contentType, quarantining', filePath);
      const qName = `quarantine/${chatId}/${messageId}/${filename}`;
      await bucket.upload(tempLocalFile, { destination: qName });
      await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({ status: 'quarantined', moderation: { flagged: true } }, { merge: true });
      fs.unlinkSync(tempLocalFile);
      return null;
    }

    // Placeholder moderation: integrate Vision API or other models here
    const moderationPassed = true; // TODO: replace with real check
    if (!moderationPassed) {
      const qName = `quarantine/${chatId}/${messageId}/${filename}`;
      await bucket.upload(tempLocalFile, { destination: qName });
      await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({ status: 'quarantined', moderation: { flagged: true } }, { merge: true });
      fs.unlinkSync(tempLocalFile);
      return null;
    }

    // Image handling
    // Preserve GIF directory structure: final/communityMessages/gifs/{messageId}/
    // Regular files: final/{chatId}/{messageId}/
    let finalPrefix, thumbPrefix;
    
    if (isGif) {
      finalPrefix = `final/communityMessages/gifs/${messageId}/`;
      thumbPrefix = `thumbs/communityMessages/gifs/${messageId}/`;
      console.log('🎭 Cloud Function: Using GIF-specific storage paths', { finalPrefix, thumbPrefix });
    } else {
      finalPrefix = `final/${chatId}/${messageId}/`;
      thumbPrefix = `thumbs/${chatId}/${messageId}/`;
    }

    const finalName = finalPrefix + filename;
    const thumbName = thumbPrefix + filename;

    // If image, create a thumbnail
    if (contentType.startsWith('image/')) {
      // GIFs need special handling - preserve animation, don't convert to JPEG
      if (isGif || contentType === 'image/gif') {
        console.log('🎭 Cloud Function: Processing GIF - preserving animation');
        // Upload original GIF without conversion (to preserve animation)
        await bucket.upload(tempLocalFile, { destination: finalName, metadata: { contentType: 'image/gif' } });
        
        // For GIF thumbnail, extract first frame using sharp
        const thumbLocalPath = path.join(os.tmpdir(), 'thumb-' + path.basename(filePath).replace('.gif', '.jpg'));
        try {
          await sharp(tempLocalFile, { animated: false }) // Take only first frame
            .resize({ width: 300 })
            .jpeg({ quality: 72 })
            .toFile(thumbLocalPath);
          await bucket.upload(thumbLocalPath, { destination: thumbName, metadata: { contentType: 'image/jpeg' } });
        } catch (gifErr) {
          console.warn('Failed to create GIF thumbnail, using original:', gifErr);
          // Fallback: use original GIF as thumbnail
          await bucket.upload(tempLocalFile, { destination: thumbName, metadata: { contentType: 'image/gif' } });
        }
        
        const finalFile = bucket.file(finalName);
        const thumbFile = bucket.file(thumbName);
        const [finalUrl] = await finalFile.getSignedUrl({ action: 'read', expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });
        const [thumbUrl] = await thumbFile.getSignedUrl({ action: 'read', expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });
        
        // Get GIF dimensions and size
        let width = null;
        let height = null;
        try {
          const meta = await sharp(tempLocalFile, { animated: false }).metadata();
          width = meta.width || null;
          height = meta.height || null;
        } catch (merr) {
          console.warn('Failed to read GIF metadata:', merr);
        }
        let sizeBytes = null;
        try { sizeBytes = fs.statSync(tempLocalFile).size; } catch (e) { /* ignore */ }
        
        // Update Firestore for community messages
        if (chatId === 'communityMessages' || chatId === 'community') {
          const msgRef = admin.firestore().doc(`communityMessages/${messageId}`);
          await msgRef.set({
            status: 'ok',
            fileURL: finalUrl, // GIFs use fileURL (like videos) not imageURL
            thumbnailURL: thumbUrl,
            'attachmentMeta.contentType': 'image/gif',
            'attachmentMeta.size': sizeBytes,
            'attachmentMeta.width': width,
            'attachmentMeta.height': height,
            'attachmentMeta.isGif': true, // Flag for client-side handling
            processedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
          console.log('🎭 Cloud Function: Updated Firestore with GIF URLs', { messageId, finalUrl });
        } else {
          // Chat-scoped GIF
          await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
            status: 'ok',
            'attachmentPaths.finalUrls': admin.firestore.FieldValue.arrayUnion(finalUrl),
            'attachmentPaths.thumbUrls': admin.firestore.FieldValue.arrayUnion(thumbUrl),
            'attachmentMeta.contentType': 'image/gif',
            'attachmentMeta.size': sizeBytes,
            'attachmentMeta.width': width,
            'attachmentMeta.height': height,
            'attachmentMeta.isGif': true,
            processedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
        }
        
        // Cleanup
        try { fs.unlinkSync(thumbLocalPath); } catch (e) {}
        try { fs.unlinkSync(tempLocalFile); } catch (e) {}
        console.log('🎭 Cloud Function: GIF processing complete', filePath);
        return null;
      }
      
      // Regular image processing (non-GIF)
      const thumbLocalPath = path.join(os.tmpdir(), 'thumb-' + path.basename(filePath));
      await sharp(tempLocalFile).resize({ width: 300 }).jpeg({ quality: 72 }).toFile(thumbLocalPath);
      await bucket.upload(tempLocalFile, { destination: finalName, metadata: { contentType } });
      await bucket.upload(thumbLocalPath, { destination: thumbName, metadata: { contentType: 'image/jpeg' } });

      const finalFile = bucket.file(finalName);
      const thumbFile = bucket.file(thumbName);
      const [finalUrl] = await finalFile.getSignedUrl({ action: 'read', expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });
      const [thumbUrl] = await thumbFile.getSignedUrl({ action: 'read', expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });

      // Get image dimensions and size
      let width = null;
      let height = null;
      try {
        const meta = await sharp(tempLocalFile).metadata();
        width = meta.width || null;
        height = meta.height || null;
      } catch (merr) {
        console.warn('Failed to read image metadata:', merr);
      }
      let sizeBytes = null;
      try { sizeBytes = fs.statSync(tempLocalFile).size; } catch (e) { /* ignore */ }

      // If this upload was for the community timeline (uploads/.../communityMessages/<messageId>)
      // write the canonical fields into the `communityMessages` collection which the client watches.
      if (chatId === 'communityMessages' || chatId === 'community') {
        const msgRef = admin.firestore().doc(`communityMessages/${messageId}`);
        await msgRef.set({
          status: 'ok',
          imageURL: finalUrl,
          thumbnailURL: thumbUrl,
          'attachmentMeta.contentType': contentType,
          'attachmentMeta.size': sizeBytes,
          'attachmentMeta.width': width,
          'attachmentMeta.height': height,
          processedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      } else {
        // Chat-scoped message: write into chats/{chatId}/messages/{messageId}
        await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
          status: 'ok',
          'attachmentPaths.finalUrls': admin.firestore.FieldValue.arrayUnion(finalUrl),
          'attachmentPaths.thumbUrls': admin.firestore.FieldValue.arrayUnion(thumbUrl),
          'attachmentMeta.contentType': contentType,
          'attachmentMeta.size': sizeBytes,
          'attachmentMeta.width': width,
          'attachmentMeta.height': height,
          processedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      }

      // cleanup
      try { fs.unlinkSync(thumbLocalPath); } catch (e) {}
      try { fs.unlinkSync(tempLocalFile); } catch (e) {}
      console.log('Processed chat image', filePath);
      return null;
    }

    // Video/audio or other file types: for heavy processing, consider Cloud Run + ffmpeg
    // For now, just move to final/ and set status to 'processing' so another job can transcode
    await bucket.upload(tempLocalFile, { destination: finalName, metadata: { contentType } });
    const finalFile = bucket.file(finalName);
    const [finalUrl] = await finalFile.getSignedUrl({ action: 'read', expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });
    // Attempt to get duration for video/audio via ffprobe if available. Fallback to null.
    let duration = null;
    try {
      // This project does not include ffprobe by default; keep placeholder for integration.
      // If using fluent-ffmpeg or ffprobe, populate duration here.
    } catch (derr) {
      // ignore
    }
    let sizeBytes = null;
    try { sizeBytes = fs.statSync(tempLocalFile).size; } catch (e) { /* ignore */ }

    if (chatId === 'communityMessages' || chatId === 'community') {
      const msgRef = admin.firestore().doc(`communityMessages/${messageId}`);
      await msgRef.set({
        status: 'processing',
        fileURL: finalUrl,
        'attachmentMeta.contentType': contentType,
        'attachmentMeta.size': sizeBytes,
        'attachmentMeta.duration': duration,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    } else {
      await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
        status: 'processing',
        'attachmentPaths.finalUrls': admin.firestore.FieldValue.arrayUnion(finalUrl),
        'attachmentMeta.contentType': contentType,
        'attachmentMeta.size': sizeBytes,
        'attachmentMeta.duration': duration,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }

    try { fs.unlinkSync(tempLocalFile); } catch (e) {}
    console.log('Processed chat non-image file', filePath);
    return null;
  } catch (err) {
    console.error('Error processing chat upload:', err);
    // best-effort mark message failed
    try { 
      const parts = (object.name || '').split('/');
      if (parts.length >= 4) {
        const chatId = parts[2];
        const messageId = parts[3];
        await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({ status: 'failed', error: String(err) }, { merge: true });
      }
    } catch (uerr) { console.error('Error updating message status:', uerr); }
    return null;
  }
});

// Callable for pinning messages atomically and enforcing permissions server-side
exports.pinMessage = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const { chatId, messageId } = data;
  if (!chatId || !messageId) throw new functions.https.HttpsError('invalid-argument', 'chatId and messageId required');

  const chatRef = admin.firestore().doc(`chats/${chatId}`);
  const msgRef = chatRef.collection('messages').doc(messageId);

  try {
    await admin.firestore().runTransaction(async (tx) => {
      const chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) throw new functions.https.HttpsError('not-found', 'Chat not found');
      const prevPinnedId = chatSnap.get('pinnedMessageId');
      if (prevPinnedId) {
        const prevMsgRef = chatRef.collection('messages').doc(prevPinnedId);
        tx.update(prevMsgRef, { pinned: false, pinnedBy: admin.firestore.FieldValue.delete(), pinnedAt: admin.firestore.FieldValue.delete() });
      }
      tx.update(msgRef, { pinned: true, pinnedBy: context.auth.uid, pinnedAt: admin.firestore.FieldValue.serverTimestamp() });
      tx.update(chatRef, { pinnedMessageId: messageId });
    });
    return { success: true };
  } catch (err) {
    console.error('pinMessage error', err);
    throw new functions.https.HttpsError('internal', 'Unable to pin message');
  }
});

// Callable function to delete a message and its storage artifacts (delete-for-everyone)
exports.deleteMessage = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const { chatId, messageId } = data;
  if (!chatId || !messageId) throw new functions.https.HttpsError('invalid-argument', 'chatId and messageId required');

  // Permission check: allow if owner or admin. For now, require the caller to be authenticated and rely on client-side checks.
  try {
    const bucket = storage.bucket();
    const finalPrefix = `final/${chatId}/${messageId}/`;
    const thumbPrefix = `thumbs/${chatId}/${messageId}/`;

    // Delete all files under the prefixes
    const deletePrefix = async (prefix) => {
      const [files] = await bucket.getFiles({ prefix });
      if (!files || files.length === 0) return;
      const deletions = files.map(f => f.delete().catch(e => { console.warn('deleteFile failed', f.name, e); }));
      await Promise.all(deletions);
    };

    await deletePrefix(finalPrefix);
    await deletePrefix(thumbPrefix);

    // Mark message as deleted in Firestore so clients can show "message deleted"
    const msgRef = admin.firestore().doc(`chats/${chatId}/messages/${messageId}`);
    await msgRef.set({ deleted: true, deletedBy: context.auth.uid, deletedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    return { success: true };
  } catch (err) {
    console.error('deleteMessage error', err);
    throw new functions.https.HttpsError('internal', 'Failed to delete message');
  }
});
