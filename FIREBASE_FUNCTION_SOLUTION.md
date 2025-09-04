# Firebase Function Alternative Solution

If the Google Apps Script CORS issue persists, here's how to use Firebase Functions instead.

## Step 1: Create Firebase Function

Create a new file `functions/advancement_intake.js`:

```javascript
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
```

## Step 2: Update Flutter App

Update the `_submitToGoogleAppScript` method in `lib/main.dart`:

```dart
Future<Map<String, dynamic>> _submitToGoogleAppScript(Map<String, dynamic> payload) async {
  // Use Firebase Function instead of Google Apps Script
  final String functionUrl = 'https://us-central1-crucible-helper.cloudfunctions.net/advancementIntake';
  
  try {
    print('Submitting payload to: $functionUrl');
    print('Payload: ${json.encode(payload)}');
    
    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode(payload),
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return responseData;
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('Error details: $e');
    throw Exception('Failed to submit advancement: $e');
  }
}
```

## Step 3: Deploy Firebase Function

```bash
cd functions
npm install
firebase deploy --only functions
```

## Benefits of Firebase Functions

1. **Better CORS support** - Native CORS handling
2. **Better error handling** - More detailed error messages
3. **Scalability** - Automatic scaling
4. **Monitoring** - Built-in logging and monitoring
5. **Security** - Automatic Firebase Auth integration

## Data Storage

The Firebase Function stores data in Firestore, which you can then sync to Google Sheets if needed.

