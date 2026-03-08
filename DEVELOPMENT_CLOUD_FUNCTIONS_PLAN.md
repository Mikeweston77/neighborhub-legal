Purpose

This document outlines how to add server-side logic (Cloud Functions) and Cloud Storage flows for handling user-generated images for NeighborHub. It includes concrete code examples, Firebase Storage rules, emulator and deploy steps, and recommended best practices for thumbnails, moderation, signed upload URLs, and durability.

Goals

- Offload image processing (resizing, thumbnails) to a trustworthy server-side step.
- Keep Firestore documents small: store only metadata and Storage download URLs.
- Ensure uploads are authenticated and controlled (Storage rules / App Check / signed URLs).
- Provide an emulator-based dev workflow and production deployment path.

High-level options

1) Client uploads directly to Firebase Storage using the Firebase iOS SDK
   - Pros: simple, uses existing SDKs, resume/monitor progress on client
   - Cons: difficult to add server-side transformations without extra triggers

2) Client requests a short-lived signed upload URL from a callable HTTPS Function, then PUTs image bytes directly to GCS
   - Pros: server can control filename, path, and attach metadata (advertId, uploaderId). Allows clients without the full SDK.
   - Cons: client needs to use URL PUT and then confirm the upload path back to Firestore or call another function to finalize.

3) Client uploads to a "temp" path (uploads/{uid}/{advertId}/...), Cloud Function triggers on finalize to:
   - validate file type/size
   - create thumbnails (sharp)
   - move/copy to final path (final/{advertId}/...)
   - set metadata and create signed download URLs or set public download tokens
   - update Firestore advert doc with storage URLs and thumbnail URLs

Recommended flow (practical): Option 3
- Client uploads image(s) to `uploads/{uid}/{advertId}/{filename}` using Firebase Storage SDK (authenticated + App Check). Include `advertId` either in path or metadata.
- Cloud Function (storage.onFinalize) triggers; it:
  - ignores already-processed files (e.g. skip `final/` or `thumbs/` folder),
  - downloads the file into `/tmp`, runs `sharp` to create sizes (thumb 200px, medium 800px),
  - uploads derived files to `final/{advertId}/...` or `thumbs/{advertId}/...`,
  - deletes temp files, and
  - uses `admin.firestore()` to update the advert doc with download URLs (prefer signed URLs or `getDownloadURL()` semantics).

Security: Storage rules + App Check + Authentication
- Storage rules should allow writes only to authenticated users under their own `uploads/{uid}/...` path.
- Finalized files under `final/` or public files can be readable by all (if desired) or subject to auth.
- Require App Check for client SDK uploads in production.

Sample Storage rules (start, adapt to your policy)

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Allow authenticated users to upload to their own upload folder
    match /uploads/{userId}/{advertId}/{allPaths=**} {
      allow write: if request.auth != null && request.auth.uid == userId && request.resource.size < 20 * 1024 * 1024; // 20 MB limit
      // reads are allowed only if file has a valid download token or the final area
      allow read: if false;
    }

    // Finalized public assets
    match /final/{advertId}/{allPaths=**} {
      // If you want final images public, allow read true. Otherwise require auth.
      allow read: if true;
      // Writes only allowed by server (Cloud Functions) -- deny client writes by default
      allow write: if false;
    }

    // Thumbnails created server-side
    match /thumbs/{advertId}/{allPaths=**} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

Minimal Cloud Function: thumbnail + finalization (JavaScript example)

- This sample uses Node 18, `firebase-functions` and `firebase-admin`, `@google-cloud/storage`, and `sharp` for image processing.
- Key behaviors:
  - triggered on `onFinalize` for new uploaded images
  - creates two sizes (thumb / medium)
  - uploads results to `final/` and `thumbs/`
  - writes thumbnail and final URLs into Firestore under `adverts/{advertId}`

File: `functions/index.js`

```js
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

    // Optionally delete the upload from uploads/ if you want to move rather than copy
    // await bucket.file(filePath).delete();

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
```

Notes about the function
- Adjust `filePath` parsing to match how your client uploads. I used `uploads/<uid>/<advertId>/filename` as an example.
- `sharp` requires native binaries and can increase function bundle size; if deploying to Cloud Functions, provide prebuilt binaries or use a Docker-based build (Functions Framework or Cloud Run) if necessary.
- Signed URLs above are v2-style via `getSignedUrl`; you can also choose to make `final/` public and return stable URLs.

Alternative: Use a small HTTP function to issue signed upload URLs

If you prefer the client not to use the Firebase Storage SDK, create an HTTPS Callable function that returns a signed PUT URL to GCS. Client PUTs to that URL, then calls a finalize callable if needed. Example (JS):

```js
exports.getUploadUrl = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be signed in');
  const { advertId, filename, contentType } = data;
  const bucket = storage.bucket();
  const file = bucket.file(`uploads/${context.auth.uid}/${advertId}/${filename}`);
  const expires = Date.now() + 15 * 60 * 1000; // 15 min
  const [url] = await file.getSignedUrl({ action: 'write', expires, version: 'v4', contentType });
  return { uploadUrl: url, path: file.name };
});
```

Emulator & local testing

1) Install Firebase CLI & initialize functions
```bash
npm install -g firebase-tools
cd functions
npm init -y
npm i firebase-functions firebase-admin @google-cloud/storage sharp
firebase login
firebase init emulators functions firestore storage
```
2) Start emulators
```bash
firebase emulators:start --only functions,firestore,storage
```
3) From your iOS simulator, point Firebase config to emulator host if desired for testing (see Firebase docs). Use `Functions` emulator for callable functions.

Deployment

```bash
# in functions/ folder
npm run build # if using TypeScript
firebase deploy --only functions
```

Moderation & safety

- Use a content moderation step in the function (Google Vision SafeSearch or Cloud Vision/Image Moderation) to detect NSFW, violent content, or PII. If flagged, move to a quarantine prefix and set `imagesPendingModeration=true` on Firestore.
- Optionally do face-blurring or OCR detection to redact sensitive info.

Costs & scaling

- Generating thumbnails increases Storage & function execution costs. Use size limits and rate-limits.
- Consider using Cloud Run for heavy processing or GPU ML workloads.

Best-practice checklist

- Enforce auth and App Check on client uploads for production.
- Use structured paths: `uploads/<uid>/<advertId>/original.jpg`, `final/<advertId>/original.jpg`, `thumbs/<advertId>/original.jpg`.
- Attach `advertId` in metadata or path so functions can map files back to adverts.
- Update Firestore with final URLs once processed; UI should prefer `imageStorageURLs` if present, otherwise fall back to local paths.
- For sensitive files, do moderation and quarantine before making final images public.

Next actions I can take for you

- Scaffold a `functions/` folder in this repo with the example function plus `package.json` and `firebase.json` for emulator use, then run the emulator here and run a quick end-to-end local test (requires network and emulator support).
- Or just generate a ready-to-deploy `functions/` sample (TypeScript preferred) you can deploy.

Tell me which you prefer and I'll proceed.
