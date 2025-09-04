const admin = require('firebase-admin');

// Initialize Firebase Admin with application default credentials
admin.initializeApp({
  projectId: 'crucible-helper-2024'
});

const db = admin.firestore();

async function clearMonsterCores() {
  try {
    console.log('🗑️ Clearing all monster cores from database...');
    
    const snapshot = await db.collection('monster_cores').get();
    
    if (snapshot.empty) {
      console.log('✅ No monster cores found in database');
      return;
    }
    
    const batch = db.batch();
    let count = 0;
    
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
      count++;
    });
    
    await batch.commit();
    console.log(`✅ Successfully deleted ${count} monster cores from database`);
    
  } catch (error) {
    console.error('❌ Error clearing monster cores:', error);
  } finally {
    process.exit(0);
  }
}

clearMonsterCores();
