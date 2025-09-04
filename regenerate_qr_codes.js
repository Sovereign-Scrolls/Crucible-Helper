const admin = require('firebase-admin');
const { getStorage } = require('firebase-admin/storage');

// Initialize Firebase Admin
const serviceAccount = require('./functions/service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'crucible-helper.appspot.com'
});

const db = admin.firestore();
const storage = getStorage();
const bucket = storage.bucket();

async function regenerateQRCodes() {
  try {
    console.log('Starting QR code regeneration...');
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`Found ${usersSnapshot.size} users`);
    
    let successCount = 0;
    let errorCount = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      try {
        // Check if user has a pc.json file
        const pcFileName = `users/${userId}/pc.json`;
        const file = bucket.file(pcFileName);
        
        // Check if file exists
        const [exists] = await file.exists();
        if (!exists) {
          console.log(`No pc.json found for user ${userId}, skipping...`);
          continue;
        }
        
        // Get the current file content
        const [fileContent] = await file.download();
        const pcData = JSON.parse(fileContent.toString());
        
        // Add a timestamp to trigger the update
        pcData.lastQRUpdate = new Date().toISOString();
        
        // Upload the updated file - this will trigger the generateQRCode function
        await file.save(JSON.stringify(pcData, null, 2), {
          metadata: {
            contentType: 'application/json',
          }
        });
        
        console.log(`✅ Regenerated QR code for user: ${userData.displayName || userId}`);
        successCount++;
        
        // Small delay to avoid overwhelming the system
        await new Promise(resolve => setTimeout(resolve, 100));
        
      } catch (error) {
        console.error(`❌ Error regenerating QR for user ${userId}:`, error.message);
        errorCount++;
      }
    }
    
    console.log(`\n🎉 QR Code Regeneration Complete!`);
    console.log(`✅ Successfully regenerated: ${successCount} QR codes`);
    console.log(`❌ Errors: ${errorCount}`);
    
  } catch (error) {
    console.error('❌ Fatal error:', error);
  } finally {
    process.exit(0);
  }
}

// Run the regeneration
regenerateQRCodes();

