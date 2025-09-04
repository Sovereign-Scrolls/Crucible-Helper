const admin = require('firebase-admin');
const moment = require('moment-timezone');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(require('./service-account-key.json')),
});

const db = admin.firestore();

// Common timezone mappings based on US states/regions
const timezoneMappings = {
  // Eastern Time
  'new york': 'America/New_York',
  'florida': 'America/New_York',
  'georgia': 'America/New_York',
  'north carolina': 'America/New_York',
  'south carolina': 'America/New_York',
  'virginia': 'America/New_York',
  'maryland': 'America/New_York',
  'delaware': 'America/New_York',
  'pennsylvania': 'America/New_York',
  'new jersey': 'America/New_York',
  'connecticut': 'America/New_York',
  'rhode island': 'America/New_York',
  'massachusetts': 'America/New_York',
  'vermont': 'America/New_York',
  'new hampshire': 'America/New_York',
  'maine': 'America/New_York',
  'ohio': 'America/New_York',
  'indiana': 'America/New_York',
  'kentucky': 'America/New_York',
  'tennessee': 'America/New_York',
  'michigan': 'America/New_York',
  
  // Central Time
  'illinois': 'America/Chicago',
  'wisconsin': 'America/Chicago',
  'minnesota': 'America/Chicago',
  'iowa': 'America/Chicago',
  'missouri': 'America/Chicago',
  'arkansas': 'America/Chicago',
  'louisiana': 'America/Chicago',
  'mississippi': 'America/Chicago',
  'alabama': 'America/Chicago',
  'oklahoma': 'America/Chicago',
  'kansas': 'America/Chicago',
  'nebraska': 'America/Chicago',
  'north dakota': 'America/Chicago',
  'south dakota': 'America/Chicago',
  
  // Mountain Time
  'colorado': 'America/Denver',
  'wyoming': 'America/Denver',
  'montana': 'America/Denver',
  'idaho': 'America/Denver',
  'utah': 'America/Denver',
  'new mexico': 'America/Denver',
  'arizona': 'America/Phoenix', // Arizona doesn't observe DST
  
  // Pacific Time
  'california': 'America/Los_Angeles',
  'oregon': 'America/Los_Angeles',
  'washington': 'America/Los_Angeles',
  'nevada': 'America/Los_Angeles',
  
  // Alaska
  'alaska': 'America/Anchorage',
  
  // Hawaii
  'hawaii': 'Pacific/Honolulu',
};

// Function to detect timezone from address
function detectTimezoneFromAddress(address) {
  if (!address) return 'America/New_York'; // Default fallback
  
  const addressLower = address.toLowerCase();
  
  // Check for state names
  for (const [state, timezone] of Object.entries(timezoneMappings)) {
    if (addressLower.includes(state)) {
      return timezone;
    }
  }
  
  // Check for common city patterns
  if (addressLower.includes('nyc') || addressLower.includes('new york city')) {
    return 'America/New_York';
  }
  if (addressLower.includes('la') || addressLower.includes('los angeles')) {
    return 'America/Los_Angeles';
  }
  if (addressLower.includes('chicago')) {
    return 'America/Chicago';
  }
  if (addressLower.includes('denver')) {
    return 'America/Denver';
  }
  if (addressLower.includes('phoenix')) {
    return 'America/Phoenix';
  }
  if (addressLower.includes('anchorage')) {
    return 'America/Anchorage';
  }
  if (addressLower.includes('honolulu')) {
    return 'Pacific/Honolulu';
  }
  
  // Default to Eastern Time if no match found
  return 'America/New_York';
}

// Migration function
async function migrateLocationTimezones() {
  try {
    console.log('🔄 Starting timezone migration for locations...');
    
    const locationsSnapshot = await db.collection('locations').get();
    console.log(`📊 Found ${locationsSnapshot.docs.length} locations to process`);
    
    let updatedCount = 0;
    let skippedCount = 0;
    
    for (const doc of locationsSnapshot.docs) {
      const locationData = doc.data();
      
      // Skip if already has timezone
      if (locationData.timezone) {
        console.log(`⏭️  Skipping ${locationData.name} - already has timezone: ${locationData.timezone}`);
        skippedCount++;
        continue;
      }
      
      // Detect timezone from address
      const detectedTimezone = detectTimezoneFromAddress(locationData.address);
      
      // Update the location with timezone
      await db.collection('locations').doc(doc.id).update({
        timezone: detectedTimezone,
        timezoneMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      console.log(`✅ Updated ${locationData.name} with timezone: ${detectedTimezone}`);
      updatedCount++;
    }
    
    console.log(`\n🎉 Migration completed!`);
    console.log(`📈 Updated: ${updatedCount} locations`);
    console.log(`⏭️  Skipped: ${skippedCount} locations (already had timezone)`);
    console.log(`📊 Total processed: ${locationsSnapshot.docs.length} locations`);
    
  } catch (error) {
    console.error('❌ Error during migration:', error);
    throw error;
  }
}

// Function to manually set timezone for a specific location
async function setLocationTimezone(locationId, timezone) {
  try {
    // Validate timezone
    if (!moment.tz.zone(timezone)) {
      throw new Error(`Invalid timezone: ${timezone}`);
    }
    
    await db.collection('locations').doc(locationId).update({
      timezone: timezone,
      timezoneUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`✅ Set timezone for location ${locationId} to: ${timezone}`);
  } catch (error) {
    console.error(`❌ Error setting timezone for location ${locationId}:`, error);
    throw error;
  }
}

// Export functions for use
module.exports = {
  migrateLocationTimezones,
  setLocationTimezone,
  detectTimezoneFromAddress,
  timezoneMappings,
};

// Run migration if this file is executed directly
if (require.main === module) {
  migrateLocationTimezones()
    .then(() => {
      console.log('Migration script completed successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Migration script failed:', error);
      process.exit(1);
    });
}
