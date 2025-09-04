const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();

exports.advancementIntake = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    const { idToken, affinityChanges = [], skillChanges = [], essenceChanges = [] } = req.body;

    if (!idToken) {
      return res.status(401).json({ ok: false, error: 'Missing idToken' });
    }

    // Verify Firebase token
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const email = decodedToken.email;

    if (!email) {
      return res.status(401).json({ ok: false, error: 'Email not verified' });
    }

    // Store data in Firestore
    const batch = db.batch();
    const timestamp = new Date();

    // Add affinity changes
    affinityChanges.forEach(change => {
      const docRef = db.collection('advancements').doc();
      batch.set(docRef, {
        email,
        type: 'affinity',
        ...change,
        timestamp
      });
    });

    // Add skill changes
    skillChanges.forEach(change => {
      const docRef = db.collection('advancements').doc();
      batch.set(docRef, {
        email,
        type: 'skill',
        ...change,
        timestamp
      });
    });

    // Add essence changes
    essenceChanges.forEach(change => {
      const docRef = db.collection('advancements').doc();
      batch.set(docRef, {
        email,
        type: 'essence',
        ...change,
        timestamp
      });
    });

    await batch.commit();

    res.json({
      ok: true,
      email,
      counts: {
        affinityChanges: affinityChanges.length,
        skillChanges: skillChanges.length,
        essenceChanges: essenceChanges.length
      }
    });

  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});
