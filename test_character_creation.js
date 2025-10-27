// Test script to verify character creation and Google Sheets integration
const https = require('https');

// Test data
const testData = {
  characterName: 'Test Character',
  playerName: 'Test Player',
  race: 'Human',
  freeAffinity: 'Attack'
};

// Mock Firebase ID token (you'll need to get a real one from the app)
const idToken = 'YOUR_FIREBASE_ID_TOKEN_HERE';

const postData = JSON.stringify(testData);

const options = {
  hostname: 'createcharacter-gmxcgg5w6q-uc.a.run.app',
  port: 443,
  path: '/',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData),
    'Authorization': `Bearer ${idToken}`
  }
};

console.log('🧪 Testing character creation...');
console.log('📊 Test data:', testData);

const req = https.request(options, (res) => {
  console.log(`📡 Status: ${res.statusCode}`);
  console.log(`📋 Headers:`, res.headers);

  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    console.log('📄 Response:', data);
    try {
      const response = JSON.parse(data);
      if (response.ok) {
        console.log('✅ Character creation successful!');
        console.log('🆔 Character ID:', response.characterId);
        console.log('📊 Character Number:', response.characterNumber);
        console.log('💬 Message:', response.message);
      } else {
        console.log('❌ Character creation failed:', response.error);
      }
    } catch (e) {
      console.log('❌ Error parsing response:', e.message);
    }
  });
});

req.on('error', (e) => {
  console.error('❌ Request error:', e.message);
});

req.write(postData);
req.end();
