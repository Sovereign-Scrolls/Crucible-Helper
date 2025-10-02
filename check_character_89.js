// Quick check and fix for Character 89's free affinity issue
// This can be run as a Cloud Function or adapted for local testing

const https = require('https');

// Function to call the calculateCharacter Cloud Function
async function runCalculateCharacter(playerUid, characterNumber, authToken) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      playerUid: playerUid,
      characterNumber: characterNumber
    });

    const options = {
      hostname: 'us-central1-crucible-helper.cloudfunctions.net',
      path: '/calculateCharacter',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          const result = JSON.parse(data);
          resolve({ statusCode: res.statusCode, data: result });
        } catch (e) {
          resolve({ statusCode: res.statusCode, data: data });
        }
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.write(postData);
    req.end();
  });
}

// Function to check character data via getCharacters API
async function getCharacterData(playerUid, authToken) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'us-central1-crucible-helper.cloudfunctions.net',
      path: `/getCharacters?impersonateUid=${playerUid}`,
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${authToken}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          const result = JSON.parse(data);
          resolve({ statusCode: res.statusCode, data: result });
        } catch (e) {
          resolve({ statusCode: res.statusCode, data: data });
        }
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.end();
  });
}

async function checkAndFixCharacter89(authToken) {
  const playerUid = 'IBDXgIT2D8QYebxU20NOsiBpKw63';
  const characterNumber = '89';
  
  console.log('🔍 Checking Character 89 Data...');
  
  try {
    // 1. Get current character data
    console.log('📋 Fetching character data...');
    const charResult = await getCharacterData(playerUid, authToken);
    
    if (charResult.statusCode !== 200) {
      console.log('❌ Failed to fetch character data:', charResult.statusCode, charResult.data);
      return;
    }
    
    const characters = charResult.data.characters || [];
    if (characters.length === 0) {
      console.log('❌ No characters found for this user');
      return;
    }
    
    const character = characters[0];
    console.log('✅ Character found:');
    console.log(`  - Name: ${character.characterName || 'Unknown'}`);
    console.log(`  - Cultivation Tier: ${character.cultivationTier || 'Unknown'}`);
    console.log(`  - Free Affinity: ${character.free_affinity || character.freeAffinity || 'NOT SET'}`);
    
    // 2. Check current affinities
    console.log('\n🎯 Current Affinities:');
    const affinities = character.affinities || {};
    Object.keys(affinities).forEach(affinityName => {
      const affinity = affinities[affinityName];
      const total = affinity.Total || {};
      console.log(`  - ${affinityName}: Level ${total.Level || 0}, Cost ${total.Cost || 0}`);
    });
    
    // 3. Run calculateCharacter to refresh calculations
    console.log('\n🔄 Running calculateCharacter function...');
    const calcResult = await runCalculateCharacter(playerUid, characterNumber, authToken);
    
    if (calcResult.statusCode === 200) {
      console.log('✅ Calculate character completed successfully');
      console.log('📊 Results:', calcResult.data);
    } else {
      console.log('❌ Calculate character failed:', calcResult.statusCode, calcResult.data);
    }
    
    // 4. Check affinities again after calculation
    console.log('\n🔄 Fetching updated character data...');
    const updatedResult = await getCharacterData(playerUid, authToken);
    
    if (updatedResult.statusCode === 200) {
      const updatedCharacter = updatedResult.data.characters[0];
      const updatedAffinities = updatedCharacter.affinities || {};
      
      console.log('\n🎯 Updated Affinities:');
      Object.keys(updatedAffinities).forEach(affinityName => {
        const affinity = updatedAffinities[affinityName];
        const total = affinity.Total || {};
        const isFreeAffinity = affinityName.toLowerCase() === (updatedCharacter.free_affinity || '').toLowerCase();
        console.log(`  - ${affinityName}: Level ${total.Level || 0}, Cost ${total.Cost || 0} ${isFreeAffinity ? '(FREE AFFINITY)' : ''}`);
      });
      
      // 5. Analysis
      console.log('\n💡 Analysis:');
      const freeAffinityName = updatedCharacter.free_affinity || updatedCharacter.freeAffinity;
      if (!freeAffinityName) {
        console.log('❌ Character has no free_affinity field set');
        console.log('   → Need to add Character Initialization entry to Master Logs');
      } else {
        console.log(`✅ Free affinity is set to: ${freeAffinityName}`);
        
        const freeAffinity = updatedAffinities[freeAffinityName];
        if (!freeAffinity) {
          console.log(`❌ Free affinity "${freeAffinityName}" not found in calculated affinities`);
          console.log('   → Character may not have purchased any levels in their free affinity');
        } else {
          const cultivationTier = updatedCharacter.cultivationTier || 'Iron';
          const tierIndex = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'].indexOf(cultivationTier);
          const expectedFreeLevels = tierIndex + 1; // +1 per tier from Iron
          
          console.log(`✅ Free affinity "${freeAffinityName}" found`);
          console.log(`   → Current tier: ${cultivationTier} (should get ${expectedFreeLevels} free levels)`);
          console.log(`   → Total levels: ${freeAffinity.Total?.Level || 0}`);
          console.log(`   → Total cost: ${freeAffinity.Total?.Cost || 0}`);
          
          // Check if cost calculation looks correct for free affinity
          if (freeAffinity.Total?.Cost === 0 && freeAffinity.Total?.Level > 0) {
            console.log('⚠️  Cost is 0 but levels > 0 - this might indicate an issue');
          }
        }
      }
    }
    
  } catch (error) {
    console.error('❌ Error during check:', error);
  }
}

// Usage: checkAndFixCharacter89('YOUR_AUTH_TOKEN_HERE');
module.exports = { checkAndFixCharacter89 };
