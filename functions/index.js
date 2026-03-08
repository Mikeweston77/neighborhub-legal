const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');
const sharp = require('sharp');
const os = require('os');
const path = require('path');
const fs = require('fs');
const nodemailer = require('nodemailer');
// const twilio = require('twilio'); // Lazy load in functions to avoid deployment timeout

admin.initializeApp();
const storage = new Storage();

// Email configuration - using Gmail SMTP (can be changed to other providers)
// Configure these environment variables in Firebase Functions:
// firebase functions:config:set gmail.email="your-email@gmail.com" gmail.password="your-app-password"
const emailConfig = {
  service: 'gmail',
  auth: {
    user: functions.config().gmail?.email || 'noreply@neighborhub.com',
    pass: functions.config().gmail?.password || 'default-password'
  }
};

const transporter = nodemailer.createTransport(emailConfig);

// Email templates
function getApprovalEmailHTML(userName) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4CAF50; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #4CAF50; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
        .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>🎉 Welcome to NeighborHub!</h1>
        </div>
        <div class="content">
          <h2>Hi ${userName},</h2>
          <p>Great news! Your NeighborHub account has been <strong>approved</strong> by our community administrators.</p>
          <p>You now have access to all community features including:</p>
          <ul>
            <li>Community messaging and discussions</li>
            <li>Local events and announcements</li>
            <li>Neighborhood marketplace</li>
            <li>Emergency and safety features</li>
            <li>Resource sharing with neighbors</li>
          </ul>
          <p>Open the NeighborHub app on your device to get started connecting with your neighbors!</p>
          <div class="footer">
            <p>This is an automated message from NeighborHub. Please do not reply to this email.</p>
            <p>If you have questions, contact our support team.</p>
          </div>
        </div>
      </div>
    </body>
    </html>
  `;
}

function getRejectionEmailHTML(userName) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f44336; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 8px 8px; }
        .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>NeighborHub Account Update</h1>
        </div>
        <div class="content">
          <h2>Hi ${userName},</h2>
          <p>We regret to inform you that your NeighborHub application was not approved at this time.</p>
          <p>This could be due to various reasons such as:</p>
          <ul>
            <li>Incomplete registration information</li>
            <li>Unable to verify neighborhood residence</li>
            <li>Community guidelines concerns</li>
          </ul>
          <p>If you believe this was an error or would like to appeal this decision, please contact our support team with your registration details.</p>
          <p>Thank you for your interest in NeighborHub.</p>
          <div class="footer">
            <p>This is an automated message from NeighborHub. Please do not reply to this email.</p>
            <p>For support, please contact our community administrators.</p>
          </div>
        </div>
      </div>
    </body>
    </html>
  `;
}

// Helper function to send email
async function sendEmail(to, subject, html) {
  try {
    const mailOptions = {
      from: `"NeighborHub Community" <${emailConfig.auth.user}>`,
      to: to,
      subject: subject,
      html: html
    };
    
    await transporter.sendMail(mailOptions);
    console.log(`✅ Email sent successfully to ${to}`);
    return true;
  } catch (error) {
    console.error(`❌ Failed to send email to ${to}:`, error);
    return false;
  }
}

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

    // Parse path to get advertId and filename. Adjust based on your client upload path.
    const parts = filePath.split('/');
    // Expecting ['uploads', userId, advertId, filename]
    if (parts.length < 4 || parts[0] !== 'uploads') {
      console.log('Unexpected path format, skipping', filePath);
      return null;
    }
    const userId = parts[1];
    const advertId = parts[2];
    const filename = parts.slice(3).join('/');

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
    const finalPrefix = `final/${advertId}/`;
    const thumbPrefix = `thumbs/${advertId}/`;

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
    const advertRef = admin.firestore().doc(`adverts/${advertId}`);
    await advertRef.set({
      imageStorageURLs: admin.firestore.FieldValue.arrayUnion(finalUrl),
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
    
    // Detect file types in separate storage paths
    // Path formats:
    // - Regular: uploads/{uid}/communityMessages/{messageId}/{filename}
    // - GIF: uploads/{uid}/communityMessages/gifs/{messageId}/{filename}
    // - Audio: uploads/{uid}/communityMessages/audio/{messageId}/{filename}
    // - Private chats: uploads/{uid}/{chatId}/{messageId}/{filename}
    let chatId, messageId, filename, isGif = false, isAudio = false;
    
    if (parts[2] === 'communityMessages' && parts[3] === 'gifs') {
      // GIF path: uploads/{uid}/communityMessages/gifs/{messageId}/{filename}
      chatId = 'communityMessages';
      messageId = parts[4];
      filename = parts.slice(5).join('/');
      isGif = true;
      console.log('🎭 Cloud Function: Detected GIF upload', { messageId, filename });
    } else if (parts[2] === 'communityMessages' && parts[3] === 'audio') {
      // Audio path: uploads/{uid}/communityMessages/audio/{messageId}/{filename}
      chatId = 'communityMessages';
      messageId = parts[4];
      filename = parts.slice(5).join('/');
      isAudio = true;
      console.log('🎤 Cloud Function: Detected AUDIO upload', { messageId, filename });
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
    // Preserve directory structure for different file types:
    // - GIF: final/communityMessages/gifs/{messageId}/
    // - Audio: final/communityMessages/audio/{messageId}/
    // - Regular files: final/{chatId}/{messageId}/
    let finalPrefix, thumbPrefix;
    
    if (isAudio) {
      finalPrefix = `final/communityMessages/audio/${messageId}/`;
      thumbPrefix = null;  // Audio files don't need thumbnails
      console.log('🎤 Cloud Function: Using audio-specific storage path', { finalPrefix });
    } else if (isGif) {
      finalPrefix = `final/communityMessages/gifs/${messageId}/`;
      thumbPrefix = `thumbs/communityMessages/gifs/${messageId}/`;
      console.log('🎭 Cloud Function: Using GIF-specific storage paths', { finalPrefix, thumbPrefix });
    } else {
      finalPrefix = `final/${chatId}/${messageId}/`;
      thumbPrefix = `thumbs/${chatId}/${messageId}/`;
    }

    const finalName = finalPrefix + filename;
    const thumbName = thumbPrefix ? thumbPrefix + filename : null;

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
        
        // Update Firestore for community messages
        if (chatId === 'communityMessages' || chatId === 'community') {
          const msgRef = admin.firestore().doc(`communityMessages/${messageId}`);
          await msgRef.set({
            status: 'ok',
            fileURL: finalUrl, // GIFs use fileURL (like videos) not imageURL
            thumbnailURL: thumbUrl,
            'attachmentMeta.contentType': 'image/gif',
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
      
      // Audio file handling (voice messages, etc.)
      if (isAudio || contentType.startsWith('audio/')) {
        console.log('🎤 Cloud Function: Processing audio file');
        
        // Upload original audio file to final location
        await bucket.upload(tempLocalFile, { destination: finalName, metadata: { contentType } });
        const finalFile = bucket.file(finalName);
        const [finalUrl] = await finalFile.getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 60 * 60 * 1000 }); // 1 year
        
        console.log('🎤 Cloud Function: Audio uploaded to final location', finalName);
        
        // Get file size for metadata
        let sizeBytes = 0;
        try { sizeBytes = fs.statSync(tempLocalFile).size; } catch (e) { /* ignore */ }
        
        // Update Firestore with audio URL
        if (chatId === 'communityMessages' || chatId === 'community') {
          const msgRef = admin.firestore().doc(`communityMessages/${messageId}`);
          await msgRef.set({
            status: 'ok',
            audioURL: finalUrl,
            'attachmentMeta.contentType': contentType,
            'attachmentMeta.size': sizeBytes,
            'attachmentMeta.isAudio': true,
            processedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
          console.log('🎤 Cloud Function: Updated communityMessages document with audioURL');
        } else {
          // Private chat message
          await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
            status: 'ok',
            audioURL: finalUrl,
            'attachmentMeta.contentType': contentType,
            'attachmentMeta.size': sizeBytes,
            'attachmentMeta.isAudio': true,
            processedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
          console.log('🎤 Cloud Function: Updated chat message document with audioURL');
        }
        
        // Cleanup
        try { fs.unlinkSync(tempLocalFile); } catch (e) {}
        console.log('🎤 Cloud Function: Audio processing complete', filePath);
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

      await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
        status: 'ok',
        'attachmentPaths.finalUrls': admin.firestore.FieldValue.arrayUnion(finalUrl),
        'attachmentPaths.thumbUrls': admin.firestore.FieldValue.arrayUnion(thumbUrl),
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

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
    await admin.firestore().doc(`chats/${chatId}/messages/${messageId}`).set({
      status: 'processing',
      'attachmentPaths.finalUrls': admin.firestore.FieldValue.arrayUnion(finalUrl),
      processedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

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

// ======================================================================
// PUSH NOTIFICATIONS
// Send FCM notifications to all users except the sender
// ======================================================================

// Helper function to get all user tokens except sender
async function getUserTokensExceptSender(senderUid) {
  const tokensSnapshot = await admin.firestore().collectionGroup('tokens').get();
  const tokens = [];
  
  for (const doc of tokensSnapshot.docs) {
    const userUid = doc.ref.parent.parent.id;
    if (userUid !== senderUid) {
      tokens.push({
        token: doc.data().token,
        uid: userUid
      });
    }
  }
  
  console.log(`📱 Found ${tokens.length} tokens (excluding sender ${senderUid})`);
  return tokens;
}

// Helper function to send notifications to multiple tokens
async function sendNotifications(tokens, notification, data) {
  if (tokens.length === 0) {
    console.log('⚠️ No tokens to send notifications to');
    return;
  }
  
  const tokenStrings = tokens.map(t => t.token);
  const message = {
    notification: notification,
    data: data || {},
    tokens: tokenStrings
  };
  
  try {
    const response = await admin.messaging().sendMulticast(message);
    console.log(`✅ Successfully sent ${response.successCount} notifications`);
    if (response.failureCount > 0) {
      console.log(`⚠️ Failed to send ${response.failureCount} notifications`);
      // Clean up invalid tokens
      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          console.log(`   Error for token ${idx}: ${resp.error.code}`);
          // TODO: Remove invalid tokens from Firestore
        }
      });
    }
  } catch (error) {
    console.error('❌ Error sending notifications:', error);
  }
}

// Community Chat Message Notification
exports.onNewCommunityMessage = functions.firestore
  .document('communityMessages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      const messageData = snap.data();
      const senderUid = messageData.senderId || messageData.uid;
      const senderName = messageData.user || 'Someone';
      const messageText = messageData.text || '';
      
      console.log(`📨 New community message from ${senderName} (${senderUid})`);
      
      // Get all tokens except sender
      const tokens = await getUserTokensExceptSender(senderUid);
      
      // Send notification
      await sendNotifications(
        tokens,
        {
          title: '💬 New Community Message',
          body: `${senderName}: ${messageText.substring(0, 100)}${messageText.length > 100 ? '...' : ''}`
        },
        {
          type: 'communityMessage',
          messageId: context.params.messageId,
          senderId: senderUid
        }
      );
      
      return null;
    } catch (error) {
      console.error('Error sending community message notification:', error);
      return null;
    }
  });

// Incident Report Notification
exports.onNewIncident = functions.firestore
  .document('incidents/{incidentId}')
  .onCreate(async (snap, context) => {
    try {
      const incidentData = snap.data();
      const reporterUid = incidentData.reporterId || incidentData.uid;
      const title = incidentData.title || 'New Incident';
      const severity = incidentData.severity || 'Medium';
      
      console.log(`⚠️ New incident reported: ${title}`);
      
      // Get all tokens except reporter
      const tokens = await getUserTokensExceptSender(reporterUid);
      
      // Send notification with appropriate emoji based on severity
      let emoji = '⚠️';
      if (severity === 'Critical') emoji = '🚨';
      else if (severity === 'High') emoji = '⛔';
      
      await sendNotifications(
        tokens,
        {
          title: `${emoji} New Incident Report`,
          body: `${title} - Severity: ${severity}`
        },
        {
          type: 'incident',
          incidentId: context.params.incidentId,
          severity: severity
        }
      );
      
      return null;
    } catch (error) {
      console.error('Error sending incident notification:', error);
      return null;
    }
  });

// Event Notification
exports.onNewEvent = functions.firestore
  .document('events/{eventId}')
  .onCreate(async (snap, context) => {
    try {
      const eventData = snap.data();
      const creatorUid = eventData.creatorUid || eventData.uid;
      const title = eventData.title || 'New Event';
      const eventType = eventData.eventType || 'event';
      
      console.log(`📅 New event created: ${title}`);
      
      // Get all tokens except creator
      const tokens = await getUserTokensExceptSender(creatorUid);
      
      // Choose emoji based on event type
      let emoji = '📅';
      if (eventType === 'meeting') emoji = '🤝';
      else if (eventType === 'social') emoji = '🎉';
      else if (eventType === 'maintenance') emoji = '🔧';
      
      await sendNotifications(
        tokens,
        {
          title: `${emoji} New Event`,
          body: title
        },
        {
          type: 'event',
          eventId: context.params.eventId,
          eventType: eventType
        }
      );
      
      return null;
    } catch (error) {
      console.error('Error sending event notification:', error);
      return null;
    }
  });

// Marketplace Listing Notification
exports.onNewMarketplaceListing = functions.firestore
  .document('marketplace/{listingId}')
  .onCreate(async (snap, context) => {
    try {
      const listingData = snap.data();
      const sellerUid = listingData.sellerId || listingData.uid;
      const title = listingData.title || 'New Item';
      const category = listingData.category || 'item';
      
      console.log(`🛒 New marketplace listing: ${title}`);
      
      // Get all tokens except seller
      const tokens = await getUserTokensExceptSender(sellerUid);
      
      await sendNotifications(
        tokens,
        {
          title: '🛒 New Marketplace Listing',
          body: `${title} - ${category}`
        },
        {
          type: 'marketplace',
          listingId: context.params.listingId,
          category: category
        }
      );
      
      return null;
    } catch (error) {
      console.error('Error sending marketplace notification:', error);
      return null;
    }
  });

// Newsletter Notification
exports.onNewNewsletter = functions.firestore
  .document('newsletters/{newsletterId}')
  .onCreate(async (snap, context) => {
    try {
      const newsletterData = snap.data();
      const authorUid = newsletterData.authorId || newsletterData.uid;
      const title = newsletterData.title || 'New Newsletter';
      
      console.log(`📰 New newsletter published: ${title}`);
      
      // Get all tokens except author
      const tokens = await getUserTokensExceptSender(authorUid);
      
      await sendNotifications(
        tokens,
        {
          title: '📰 New Newsletter',
          body: title
        },
        {
          type: 'newsletter',
          newsletterId: context.params.newsletterId
        }
      );
      
      return null;
    } catch (error) {
      console.error('Error sending newsletter notification:', error);
      return null;
    }
  });

// Poll Notification
exports.onNewPoll = functions.firestore
  .document('polls/active')
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      // Check if a new poll was added (polls is an array)
      const beforePolls = beforeData.polls || [];
      const afterPolls = afterData.polls || [];
      
      if (afterPolls.length > beforePolls.length) {
        // New poll was added
        const newPoll = afterPolls[afterPolls.length - 1];
        const creatorUid = newPoll.creatorUid || newPoll.uid;
        const question = newPoll.question || 'New Poll';
        
        console.log(`📊 New poll created: ${question}`);
        
        // Get all tokens except poll creator
        const tokens = await getUserTokensExceptSender(creatorUid);
        
        await sendNotifications(
          tokens,
          {
            title: '📊 New Community Poll',
            body: question
          },
          {
            type: 'poll',
            pollId: newPoll.id,
            question: question
          }
        );
      }
      
      return null;
    } catch (error) {
      console.error('Error sending poll notification:', error);
      return null;
    }
  });

// Poll Vote Notification (notify poll creator when someone votes)
exports.onPollVote = functions.firestore
  .document('polls/active')
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      const beforePolls = beforeData.polls || [];
      const afterPolls = afterData.polls || [];
      
      // Check if any poll's vote count increased
      for (let i = 0; i < Math.min(beforePolls.length, afterPolls.length); i++) {
        const beforePoll = beforePolls[i];
        const afterPoll = afterPolls[i];
        
        // Calculate total votes
        const beforeVotes = (beforePoll.votes || []).reduce((sum, opt) => sum + (opt.count || 0), 0);
        const afterVotes = (afterPoll.votes || []).reduce((sum, opt) => sum + (opt.count || 0), 0);
        
        if (afterVotes > beforeVotes) {
          // New vote detected
          const creatorUid = afterPoll.creatorUid || afterPoll.uid;
          const question = afterPoll.question || 'Your poll';
          
          console.log(`🗳️ New vote on poll: ${question}`);
          
          // Get creator's tokens only
          const tokensSnapshot = await admin.firestore()
            .collection('users')
            .doc(creatorUid)
            .collection('tokens')
            .get();
          
          const tokens = tokensSnapshot.docs.map(doc => ({
            token: doc.data().token,
            uid: creatorUid
          }));
          
          if (tokens.length > 0) {
            await sendNotifications(
              tokens,
              {
                title: '🗳️ New Vote on Your Poll',
                body: `Someone voted on: ${question}`
              },
              {
                type: 'pollVote',
                pollId: afterPoll.id,
                totalVotes: afterVotes.toString()
              }
            );
          }
        }
      }
      
      return null;
    } catch (error) {
      console.error('Error sending poll vote notification:', error);
      return null;
    }
  });

// User Approval Notification
exports.onUserApproval = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      // Check if user was just approved (verified changed from false to true)
      if (!beforeData.verified && afterData.verified) {
        const userId = context.params.userId;
        const userName = afterData.name || 'User';
        
        console.log(`✅ User approved: ${userName} (${userId})`);
        
        // Get user's FCM tokens
        const tokensSnapshot = await admin.firestore()
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .get();
        
        const tokens = tokensSnapshot.docs.map(doc => ({
          token: doc.data().token,
          uid: userId
        }));
        
        // Send approval notification (push notification)
        if (tokens.length > 0) {
          await sendNotifications(
            tokens,
            {
              title: '🎉 Welcome to NeighborHub!',
              body: 'Your account has been approved. You can now access all community features.'
            },
            {
              type: 'userApproved',
              userId: userId
            }
          );
        }
        
        // Send approval email
        const userEmail = afterData.email;
        if (userEmail) {
          await sendEmail(
            userEmail,
            '🎉 NeighborHub Account Approved - Welcome to the Community!',
            getApprovalEmailHTML(userName)
          );
        } else {
          console.log('⚠️ No email address found for approved user');
        }
      }
      
      // Check if user was rejected (verified changed from true to false or rejected flag added)
      else if ((beforeData.verified && !afterData.verified) || (!beforeData.rejected && afterData.rejected)) {
        const userId = context.params.userId;
        const userName = afterData.name || 'User';
        
        console.log(`❌ User rejected: ${userName} (${userId})`);
        
        // Get user's FCM tokens
        const tokensSnapshot = await admin.firestore()
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .get();
        
        const tokens = tokensSnapshot.docs.map(doc => ({
          token: doc.data().token,
          uid: userId
        }));
        
        // Send rejection notification (push notification)
        if (tokens.length > 0) {
          await sendNotifications(
            tokens,
            {
              title: '❌ Account Application',
              body: 'Your NeighborHub application was not approved. Please contact support if you have questions.'
            },
            {
              type: 'userRejected',
              userId: userId
            }
          );
        }
        
        // Send rejection email
        const userEmail = afterData.email;
        if (userEmail) {
          await sendEmail(
            userEmail,
            '❌ NeighborHub Account Application Update',
            getRejectionEmailHTML(userName)
          );
        } else {
          console.log('⚠️ No email address found for rejected user');
        }
      }
      
      return null;
    } catch (error) {
      console.error('Error sending user approval/rejection notification:', error);
      return null;
    }
  });

// ======================================================================
// SCHEDULED EVENT CLEANUP
// Runs every hour to delete expired events from Firestore
// Events are deleted 2 hours after their scheduled date/time
// Report-type events are never deleted automatically
// ======================================================================
exports.cleanupExpiredEvents = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('America/Los_Angeles') // Adjust to your timezone
  .onRun(async (context) => {
    try {
      console.log('🧹 Starting scheduled cleanup of expired events...');
      
      const now = admin.firestore.Timestamp.now();
      const gracePeriodMs = 2 * 60 * 60 * 1000; // 2 hours in milliseconds
      const expiryThreshold = new Date(now.toMillis() - gracePeriodMs);
      const expiryTimestamp = admin.firestore.Timestamp.fromDate(expiryThreshold);
      
      // Query for events that are expired (date < now - 2 hours)
      // Note: We'll need to filter out 'report' type events after fetching
      const eventsSnapshot = await admin.firestore()
        .collection('events')
        .where('date', '<', expiryTimestamp)
        .get();
      
      if (eventsSnapshot.empty) {
        console.log('✅ No expired events to clean up');
        return null;
      }
      
      console.log(`📋 Found ${eventsSnapshot.size} potentially expired events`);
      
      let deletedCount = 0;
      let skippedCount = 0;
      const batch = admin.firestore().batch();
      const storageDeletionPromises = [];
      
      for (const doc of eventsSnapshot.docs) {
        const eventData = doc.data();
        const eventType = eventData.eventType || eventData.type;
        
        // Skip deletion for 'report' type events - they should be kept indefinitely
        if (eventType === 'report') {
          skippedCount++;
          console.log(`⏭️  Skipping report event: ${doc.id} - "${eventData.title}"`);
          continue;
        }
        
        // Delete the event document
        batch.delete(doc.ref);
        deletedCount++;
        
        console.log(`🗑️  Deleting expired event: ${doc.id} - "${eventData.title || 'Untitled'}" (${eventData.date?.toDate?.() || 'no date'})`);
        
        // Delete associated storage files if they exist
        if (eventData.imageURL) {
          const imagePromise = deleteStorageFileFromURL(eventData.imageURL)
            .catch(err => console.warn(`⚠️  Failed to delete image for event ${doc.id}:`, err.message));
          storageDeletionPromises.push(imagePromise);
        }
        
        if (eventData.fileURL) {
          const filePromise = deleteStorageFileFromURL(eventData.fileURL)
            .catch(err => console.warn(`⚠️  Failed to delete file for event ${doc.id}:`, err.message));
          storageDeletionPromises.push(filePromise);
        }
      }
      
      // Commit all deletions
      if (deletedCount > 0) {
        await batch.commit();
        console.log(`✅ Deleted ${deletedCount} expired events from Firestore`);
        
        // Wait for all storage deletions to complete
        await Promise.all(storageDeletionPromises);
        console.log(`✅ Cleaned up associated storage files`);
      }
      
      console.log(`📊 Cleanup summary: ${deletedCount} deleted, ${skippedCount} skipped (reports)`);
      return null;
      
    } catch (error) {
      console.error('❌ Error during event cleanup:', error);
      return null;
    }
  });

// Helper function to delete a storage file from its download URL
async function deleteStorageFileFromURL(downloadURL) {
  if (!downloadURL || typeof downloadURL !== 'string') {
    return;
  }
  
  try {
    // Extract the file path from the download URL
    // Format: https://storage.googleapis.com/BUCKET/PATH or https://firebasestorage.googleapis.com/...
    const urlPattern = /\/o\/(.+?)\?/;
    const match = downloadURL.match(urlPattern);
    
    if (match && match[1]) {
      const encodedPath = match[1];
      const filePath = decodeURIComponent(encodedPath);
      
      // Delete from default bucket
      const bucket = storage.bucket();
      const file = bucket.file(filePath);
      
      const [exists] = await file.exists();
      if (exists) {
        await file.delete();
        console.log(`   🗑️  Deleted storage file: ${filePath}`);
      }
    }
  } catch (error) {
    // Log but don't throw - we don't want storage deletion failures to break the cleanup
    console.warn(`   ⚠️  Could not delete storage file from URL: ${error.message}`);
  }
}

// ============================================================================
// TWILIO WHATSAPP EMERGENCY MESSAGING
// ============================================================================

/**
 * Test function for Twilio WhatsApp Sandbox (Development)
 * 
 * Configure Twilio credentials:
 * firebase functions:config:set twilio.account_sid="ACxxxxx" twilio.auth_token="xxxxx" twilio.whatsapp_number="whatsapp:+14155238886"
 * 
 * Use this for testing before production approval
 */
exports.testTwilioWhatsApp = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  // Get Twilio credentials from Firebase config
  const accountSid = functions.config().twilio?.account_sid;
  const authToken = functions.config().twilio?.auth_token;
  const twilioWhatsAppNumber = functions.config().twilio?.whatsapp_number || 'whatsapp:+14155238886';
  const emergencyTemplateSid = functions.config().twilio?.emergency_template_sid;

  if (!accountSid || !authToken) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Twilio credentials not configured. Run: firebase functions:config:set twilio.account_sid="..." twilio.auth_token="..."'
    );
  }

  if (!emergencyTemplateSid) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Twilio template SID not configured. Run: firebase functions:config:set twilio.emergency_template_sid="HX..."'
    );
  }

  const twilio = require('twilio');
  const client = twilio(accountSid, authToken);

  const { toPhone, message } = data;

  // Validate required fields
  if (!toPhone || !message) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: toPhone, message');
  }

  try {
    const normalizedTo = toPhone.startsWith('whatsapp:') ? toPhone : `whatsapp:${toPhone}`;
    const messageResponse = await client.messages.create({
      from: twilioWhatsAppNumber,
      to: normalizedTo,
      contentSid: emergencyTemplateSid,
      contentVariables: JSON.stringify({
        1: 'TEST',
        2: context.auth.uid,
        3: 'NeighborHub Test',
        4: new Date().toISOString(),
        5: 'N/A',
        6: message
      })
    });

    console.log('✅ Test WhatsApp message sent:', messageResponse.sid);

    return {
      success: true,
      messageSid: messageResponse.sid,
      status: messageResponse.status,
      dateCreated: messageResponse.dateCreated,
      usedTemplate: true
    };

  } catch (error) {
    console.error('❌ Twilio error:', error);
    if (Number(error.code) === 63016) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'WhatsApp freeform message blocked outside the 24-hour window. Template send failed or is misconfigured.'
      );
    }
    throw new functions.https.HttpsError('internal', `Twilio error: ${error.message}`);
  }
});

/**
 * Production function for sending emergency WhatsApp alerts
 * 
 * Implements:
 * - Rate limiting (1 emergency per 60 seconds per user)
 * - Phone number validation (E.164 format)
 * - Emergency logging to Firestore
 * - Push notification confirmation to sender
 * - Support for Fire, Medical, and General emergencies
 */
exports.sendEmergencyWhatsApp = functions.https.onCall(async (data, context) => {
  // Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = context.auth.uid;

  // Rate limiting check (prevent spam)
  const lastEmergencyRef = admin.firestore()
    .collection('emergencyRateLimit')
    .doc(userId);
  
  const lastEmergencyDoc = await lastEmergencyRef.get();
  if (lastEmergencyDoc.exists) {
    const lastTime = lastEmergencyDoc.data().timestamp.toDate();
    const timeSince = Date.now() - lastTime.getTime();
    const minInterval = 60000; // 60 seconds
    
    if (timeSince < minInterval) {
      const waitTime = Math.ceil((minInterval - timeSince) / 1000);
      throw new functions.https.HttpsError(
        'resource-exhausted',
        `Please wait ${waitTime} seconds before sending another emergency alert`
      );
    }
  }

  // Extract and validate data
  const {
    emergencyType, // 'fire', 'medical', 'emergency'
    userName,
    userAddress,
    userPhone,
    description,
    emergencyContactPhone,
    emergencyContactName,
    timestamp,
    metadata // Optional: building type, visible flames, etc.
  } = data;

  // Validation
  if (!emergencyType || !userName || !emergencyContactPhone) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing required fields: emergencyType, userName, emergencyContactPhone'
    );
  }

  // Validate phone number format (E.164: +27793867472)
  const phoneRegex = /^\+[1-9]\d{1,14}$/;
  const cleanPhone = emergencyContactPhone.replace('whatsapp:', '').trim();
  
  if (!phoneRegex.test(cleanPhone)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Phone number must be in E.164 format (e.g., +27793867472)'
    );
  }

  // Get Twilio credentials
  const accountSid = functions.config().twilio?.account_sid;
  const authToken = functions.config().twilio?.auth_token;
  const twilioWhatsAppNumber = functions.config().twilio?.whatsapp_number;
  const emergencyTemplateSid = functions.config().twilio?.emergency_template_sid;

  if (!accountSid || !authToken || !twilioWhatsAppNumber) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Twilio not configured'
    );
  }

  const twilio = require('twilio');
  const client = twilio(accountSid, authToken);

  try {
    // Build emergency message based on type
    let messageBody;
    const emergencyEmoji = {
      fire: '🔥',
      medical: '🏥',
      emergency: '⚠️'
    };

    const emoji = emergencyEmoji[emergencyType.toLowerCase()] || '🚨';
    const typeUpper = emergencyType.toUpperCase();
    const timestampDate = new Date(timestamp || Date.now());
    const timeString = timestampDate.toLocaleString('en-ZA', { 
      dateStyle: 'short', 
      timeStyle: 'short' 
    });

    switch (emergencyType.toLowerCase()) {
      case 'fire':
        messageBody = `🚨${emoji} FIRE EMERGENCY ${emoji}🚨

Location: ${userAddress || 'Not provided'}
Building Type: ${metadata?.buildingType || 'Unknown'}
Visible Flames: ${metadata?.visibleFlames || 'Unknown'}
Time Reported: ${timeString}

Reporter: ${userName}
Contact: ${userPhone || 'Not provided'}

⚠️ URGENT: Fire reported in your neighborhood!

This is an automated emergency alert from NeighborHub.`;
        break;

      case 'medical':
        messageBody = `🚨${emoji} MEDICAL EMERGENCY ${emoji}🚨

Patient: ${userName}
Location: ${userAddress || 'Not provided'}
Description: ${description || 'No description provided'}
Time: ${timeString}

Emergency Contact: ${userPhone || cleanPhone}

⚠️ Immediate medical assistance requested.

This is an automated emergency alert from NeighborHub.`;
        break;

      default: // 'emergency'
        messageBody = `🚨${emoji} EMERGENCY ALERT ${emoji}🚨

Type: ${typeUpper}
Name: ${userName}
Location: ${userAddress || 'Not provided'}
Time: ${timeString}

${description ? `Description: ${description}\n\n` : ''}Contact: ${userPhone || cleanPhone}

This is an automated emergency alert from NeighborHub.`;
        break;
    }

    // Send WhatsApp message via Twilio.
    // If a template SID is configured, prefer template send first so emergency
    // alerts work outside the 24-hour customer care window.
    let messageResponse;
    let usedTemplate = false;
    if (emergencyTemplateSid) {
      const contentVariables = JSON.stringify({
        1: typeUpper,
        2: userName,
        3: userAddress || 'Not provided',
        4: timeString,
        5: userPhone || cleanPhone,
        6: description || 'No additional details'
      });

      messageResponse = await client.messages.create({
        from: twilioWhatsAppNumber,
        to: `whatsapp:${cleanPhone}`,
        contentSid: emergencyTemplateSid,
        contentVariables
      });
      usedTemplate = true;
    } else {
      try {
        messageResponse = await client.messages.create({
          from: twilioWhatsAppNumber,
          to: `whatsapp:${cleanPhone}`,
          body: messageBody
        });
      } catch (sendError) {
        const errText = String(sendError?.message || '').toLowerCase();
        const errCode = Number(sendError?.code || 0);
        const outsideWindow = errCode === 63016
          || errText.includes('outside the allowed window')
          || errText.includes('message template');

        if (outsideWindow) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'WhatsApp freeform message blocked outside the 24-hour window. Set twilio.emergency_template_sid.'
          );
        }
        throw sendError;
      }
    }

    console.log('✅ Emergency WhatsApp sent:', messageResponse.sid);

    // Log emergency to Firestore
    const emergencyRef = await admin.firestore().collection('emergencies').add({
      type: emergencyType,
      userName: userName,
      userAddress: userAddress || null,
      userPhone: userPhone || null,
      description: description || null,
      emergencyContactPhone: cleanPhone,
      emergencyContactName: emergencyContactName || 'Emergency Contact',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      timestampClient: new Date(timestamp || Date.now()),
      userId: userId,
      twilioMessageSid: messageResponse.sid,
      twilioStatus: messageResponse.status,
      twilioUsedTemplate: usedTemplate,
      twilioTemplateSid: usedTemplate ? emergencyTemplateSid : null,
      metadata: metadata || {},
      status: 'sent',
      messageBody: messageBody
    });

    console.log('📝 Emergency logged to Firestore:', emergencyRef.id);

    // Update rate limiting timestamp
    await lastEmergencyRef.set({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      lastEmergencyId: emergencyRef.id
    });

    // Send push notification confirmation to user
    try {
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      
      if (fcmToken) {
        await admin.messaging().send({
          notification: {
            title: '🚨 Emergency Sent',
            body: `Your ${emergencyType} alert has been sent via WhatsApp to ${emergencyContactName || 'emergency contact'}.`
          },
          data: {
            type: 'emergency_confirmation',
            emergencyId: emergencyRef.id,
            emergencyType: emergencyType
          },
          token: fcmToken
        });
        console.log('📱 Push notification sent to user');
      }
    } catch (notifError) {
      // Don't fail the request if notification fails
      console.warn('⚠️ Could not send push notification:', notifError.message);
    }

    return {
      success: true,
      emergencyId: emergencyRef.id,
      messageSid: messageResponse.sid,
      status: messageResponse.status,
      usedTemplate: usedTemplate,
      message: 'Emergency alert sent successfully'
    };

  } catch (error) {
    console.error('❌ Error sending emergency:', error);

    // Log failed emergency attempt
    await admin.firestore().collection('emergencies').add({
      type: emergencyType,
      userName: userName,
      userAddress: userAddress || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      userId: userId,
      status: 'failed',
      error: error.message,
      errorCode: error.code || 'unknown',
      emergencyContactPhone: cleanPhone
    });

    // Provide user-friendly error messages
    if (error.code === 21211) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid phone number. Please check the format (e.g., +27793867472)'
      );
    } else if (error.code === 21408) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Cannot send to this number. Recipient may have opted out or blocked messages.'
      );
    } else if (error.code === 21610) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'WhatsApp number not enabled. Please verify your Twilio WhatsApp sender.'
      );
    } else if (Number(error.code) === 63016) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'WhatsApp freeform message blocked outside the 24-hour window. Use an approved template and set twilio.emergency_template_sid.'
      );
    }

    throw new functions.https.HttpsError(
      'internal',
      `Failed to send emergency alert: ${error.message}`
    );
  }
});
