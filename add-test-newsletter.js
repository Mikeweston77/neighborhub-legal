// Test script to add sample newsletter to Firestore
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json'); // You'll need to add this
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function addTestNewsletter() {
  const testNewsletter = {
    id: 'test-newsletter-' + Date.now(),
    title: 'Welcome to NeighborHub!',
    summary: 'This is a test newsletter to verify the Android app is working correctly.',
    content: 'Welcome to our community newsletter system! This test newsletter confirms that:\n\n• Firebase integration is working\n• Newsletter collection is accessible\n• Real-time updates are functioning\n\nYou should be able to see this newsletter in your Android app.',
    date: Date.now(),
    author: 'NeighborHub Team',
    authorEmail: 'admin@neighborhub.com',
    authorId: 'test-user',
    category: 'GENERAL',
    isPinned: true,
    isPublished: true,
    readCount: 0,
    tags: ['welcome', 'test', 'android'],
    attachments: [],
    formFields: [],
    submissions: [],
    imageData: null,
    fileURL: null,
    createdAt: Date.now(),
    updatedAt: Date.now()
  };

  try {
    await db.collection('newsletters').doc(testNewsletter.id).set(testNewsletter);
    console.log('✅ Test newsletter added successfully!');
    console.log('Newsletter ID:', testNewsletter.id);
    console.log('Title:', testNewsletter.title);
  } catch (error) {
    console.error('❌ Error adding test newsletter:', error);
  }
}

addTestNewsletter().then(() => {
  process.exit(0);
});