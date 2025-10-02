// Diagnostic script to check free affinity issues
// Run this in the Firebase Functions environment or adapt for local testing

const admin = require('firebase-admin');

async function diagnoseFreeAffinity(playerUid, characterNumber) {
  const db = admin.firestore();
  
  console.log(`🔍 Diagnosing free affinity for player ${playerUid}, character ${characterNumber}`);
  
  try {
    // 1. Check character document
    const charRef = db.collection('players').doc(playerUid).collection('characters').doc(String(characterNumber));
    const charSnap = await charRef.get();
    
    if (!charSnap.exists) {
      console.log('❌ Character document does not exist');
      return;
    }
    
    const charData = charSnap.data();
    console.log('📋 Character data:');
    console.log(`  - Name: ${charData.characterName || 'Unknown'}`);
    console.log(`  - Cultivation Tier: ${charData.cultivationTier || 'Unknown'}`);
    console.log(`  - Free Affinity: ${charData.free_affinity || charData.freeAffinity || 'NOT SET'}`);
    
    // 2. Check advancement entries for Character Initialization
    const advancementRef = charRef.collection('advancement');
    const advancementSnap = await advancementRef.get();
    
    console.log(`\n📚 Advancement entries: ${advancementSnap.size}`);
    
    let hasCharacterInit = false;
    let initEntry = null;
    
    for (const doc of advancementSnap.docs) {
      const data = doc.data();
      const reason = String(data['Advancement Reason'] || '').toLowerCase().replace(/[^a-z]/g, '');
      
      if (reason === 'characterinitialization') {
        hasCharacterInit = true;
        initEntry = data;
        console.log('✅ Found Character Initialization entry:');
        console.log(`  - Affinity: ${data.Affinity || data.affinity || 'NOT SET'}`);
        console.log(`  - Build Adjustment: ${data['Build Adjustment'] || 'NOT SET'}`);
        console.log(`  - AP Adjustment: ${data['Affinity Point Adjustment'] || 'NOT SET'}`);
        break;
      }
    }
    
    if (!hasCharacterInit) {
      console.log('❌ No Character Initialization entry found in advancement');
    }
    
    // 3. Check calculated affinities
    const affinitiesRef = charRef.collection('affinities');
    const affinitiesSnap = await affinitiesRef.get();
    
    console.log(`\n🎯 Calculated affinities: ${affinitiesSnap.size}`);
    
    for (const affinityDoc of affinitiesSnap.docs) {
      const affinityName = affinityDoc.id;
      const tiersRef = affinityDoc.ref.collection('tiers');
      const tiersSnap = await tiersRef.get();
      
      console.log(`\n  ${affinityName}:`);
      
      for (const tierDoc of tiersSnap.docs) {
        const tierName = tierDoc.id;
        const tierData = tierDoc.data();
        console.log(`    ${tierName}: Level ${tierData.Level || 0}, Cost ${tierData.Cost || 0}`);
      }
    }
    
    // 4. Recommendations
    console.log('\n💡 Recommendations:');
    
    if (!hasCharacterInit) {
      console.log('1. Add a Character Initialization entry to the Master Logs with:');
      console.log('   - Advancement Reason: "Character Initialization"');
      console.log('   - Affinity: [desired free affinity name]');
      console.log('   - Build Adjustment: [initial build points]');
      console.log('   - Affinity Point Adjustment: [initial AP]');
    }
    
    if (!charData.free_affinity && !charData.freeAffinity) {
      console.log('2. The character document is missing the free_affinity field');
      console.log('   - This should be set automatically by syncMasterLogs');
      console.log('   - Run syncMasterLogs after adding Character Initialization');
    }
    
    if (affinitiesSnap.size === 0) {
      console.log('3. No calculated affinities found');
      console.log('   - Run calculateCharacter function after fixing the above');
    }
    
    console.log('\n✅ Diagnosis complete');
    
  } catch (error) {
    console.error('❌ Error during diagnosis:', error);
  }
}

// Specific diagnosis for character 89
async function diagnoseCharacter89() {
  const playerUid = 'IBDXgIT2D8QYebxU20NOsiBpKw63';
  const characterNumber = '89';
  
  console.log('🎯 Diagnosing Character 89 Free Affinity Issue');
  console.log('=' .repeat(50));
  
  await diagnoseFreeAffinity(playerUid, characterNumber);
}

// Example usage:
// diagnoseFreeAffinity('USER_UID_HERE', 'CHARACTER_NUMBER_HERE');
// diagnoseCharacter89();

module.exports = { diagnoseFreeAffinity, diagnoseCharacter89 };
