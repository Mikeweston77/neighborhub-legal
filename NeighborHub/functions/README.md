NeighborHub Cloud Functions

This folder contains example Cloud Functions to process user-uploaded advert images.

Quick start (requires Firebase CLI):

1) Install dependencies

```bash
cd functions
npm install
```

2) Run the emulator locally (Firestore + Storage + Functions)

```bash
firebase emulators:start --only functions,firestore,storage
```

3) Configure your iOS app to point to the emulators during development (see Firebase docs). Upload files to `uploads/<uid>/<advertId>/...` and the function will process them.

Production deploy

```bash
cd functions
npm run deploy
```

Notes

- The function uses `sharp` to resize images. Ensure native binaries can be built in your environment or use Cloud Run for heavier workloads.
- Adjust parsing of upload paths to match how the client uploads files.
