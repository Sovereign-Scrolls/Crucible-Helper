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

// Function to set timezone for a specific location
async function setLocationTimezone(locationName, timezone) {
  try {
    // Validate timezone
    if (!moment.tz.zone(timezone)) {
      throw new Error(`Invalid timezone: ${timezone}`);
    }
    
    // Find the location by name
    const locationQuery = await db.collection('locations')
      .where('name', '==', locationName)
      .limit(1)
      .get();

    if (locationQuery.empty) {
      throw new Error(`Location not found: ${locationName}`);
    }

    const locationDoc = locationQuery.docs[0];
    
    // Update the location with timezone
    await locationDoc.ref.update({
      timezone: timezone,
      timezoneUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`✅ Set timezone for location "${locationName}" to: ${timezone}`);
    return locationDoc.id;
  } catch (error) {
    console.error(`❌ Error setting timezone for location "${locationName}":`, error.message);
    throw error;
  }
}

// Function to auto-detect and set timezones for all locations
async function autoSetTimezones() {
  try {
    console.log('🔄 Starting automatic timezone detection for locations...');
    
    const locationsSnapshot = await db.collection('locations').get();
    console.log(`📊 Found ${locationsSnapshot.docs.length} locations to process`);
    
    let updatedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    for (const doc of locationsSnapshot.docs) {
      const locationData = doc.data();
      
      // Skip if already has timezone
      if (locationData.timezone) {
        console.log(`⏭️  Skipping "${locationData.name}" - already has timezone: ${locationData.timezone}`);
        skippedCount++;
        continue;
      }
      
      try {
        // Detect timezone from address
        const detectedTimezone = detectTimezoneFromAddress(locationData.address);
        
        // Update the location with timezone
        await db.collection('locations').doc(doc.id).update({
          timezone: detectedTimezone,
          timezoneMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        console.log(`✅ Updated "${locationData.name}" with timezone: ${detectedTimezone}`);
        updatedCount++;
      } catch (error) {
        console.error(`❌ Error updating "${locationData.name}":`, error.message);
        errorCount++;
      }
    }
    
    console.log(`\n🎉 Auto-detection completed!`);
    console.log(`📈 Updated: ${updatedCount} locations`);
    console.log(`⏭️  Skipped: ${skippedCount} locations (already had timezone)`);
    console.log(`❌ Errors: ${errorCount} locations`);
    console.log(`📊 Total processed: ${locationsSnapshot.docs.length} locations`);
    
  } catch (error) {
    console.error('❌ Error during auto-detection:', error);
    throw error;
  }
}

// Function to list all locations with their timezone status
async function listLocationsWithTimezone() {
  try {
    console.log('📋 Listing all locations with timezone status...');
    
    const locationsSnapshot = await db.collection('locations').get();
    const locations = [];

    for (const doc of locationsSnapshot.docs) {
      const locationData = doc.data();
      locations.push({
        id: doc.id,
        name: locationData.name,
        address: locationData.address,
        timezone: locationData.timezone || 'NOT SET',
        hasTimezone: !!locationData.timezone
      });
    }

    // Sort by name
    locations.sort((a, b) => a.name.localeCompare(b.name));

    console.log(`\n📊 Found ${locations.length} locations:`);
    console.log('─'.repeat(80));
    
    for (const location of locations) {
      const status = location.hasTimezone ? '✅' : '❌';
      console.log(`${status} ${location.name}`);
      console.log(`   Address: ${location.address || 'No address'}`);
      console.log(`   Timezone: ${location.timezone}`);
      console.log('');
    }

    const withTimezone = locations.filter(l => l.hasTimezone).length;
    const withoutTimezone = locations.filter(l => !l.hasTimezone).length;
    
    console.log('─'.repeat(80));
    console.log(`📈 Summary: ${withTimezone} with timezone, ${withoutTimezone} without timezone`);
    
  } catch (error) {
    console.error('❌ Error listing locations:', error);
    throw error;
  }
}

// Export functions for use
module.exports = {
  setLocationTimezone,
  autoSetTimezones,
  listLocationsWithTimezone,
  detectTimezoneFromAddress,
  timezoneMappings,
};

// Run auto-detection if this file is executed directly
if (require.main === module) {
  const command = process.argv[2];
  
  switch (command) {
    case 'auto':
      autoSetTimezones()
        .then(() => {
          console.log('Auto-detection completed successfully');
          process.exit(0);
        })
        .catch((error) => {
          console.error('Auto-detection failed:', error);
          process.exit(1);
        });
      break;
      
    case 'list':
      listLocationsWithTimezone()
        .then(() => {
          console.log('Listing completed successfully');
          process.exit(0);
        })
        .catch((error) => {
          console.error('Listing failed:', error);
          process.exit(1);
        });
      break;
      
    case 'set':
      const locationName = process.argv[3];
      const timezone = process.argv[4];
      
      if (!locationName || !timezone) {
        console.error('Usage: node set_timezones.js set <location_name> <timezone>');
        console.error('Example: node set_timezones.js set "My Location" "America/New_York"');
        process.exit(1);
      }
      
      setLocationTimezone(locationName, timezone)
        .then(() => {
          console.log('Timezone set successfully');
          process.exit(0);
        })
        .catch((error) => {
          console.error('Failed to set timezone:', error);
          process.exit(1);
        });
      break;
      
    default:
      console.log('Usage:');
      console.log('  node set_timezones.js auto                    - Auto-detect timezones for all locations');
      console.log('  node set_timezones.js list                    - List all locations with timezone status');
      console.log('  node set_timezones.js set <name> <timezone>   - Set timezone for specific location');
      console.log('');
      console.log('Examples:');
      console.log('  node set_timezones.js auto');
      console.log('  node set_timezones.js list');
      console.log('  node set_timezones.js set "My Location" "America/New_York"');
      process.exit(1);
  }
}
