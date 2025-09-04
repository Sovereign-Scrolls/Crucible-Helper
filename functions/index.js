const { onRequest } = require("firebase-functions/v2/https");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const axios = require("axios");
const QRCode = require("qrcode");
const crypto = require("crypto");
const { google } = require("googleapis");

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();
const admin = require("firebase-admin");
const { google: googleapis } = require('googleapis');
const moment = require('moment-timezone');

// Load configuration
const config = require("./config.json");

// Declare secrets
const DISCORD_TOKEN = defineSecret("DISCORD_TOKEN");
const GAME_SECRET = defineSecret("GAME_SECRET");


// Advancement Intake Function - Proxy to Google Apps Script
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

  // Forward the request to Google Apps Script (proxy approach)
  const googleAppsScriptUrl = config.google_sheets.apps_script_url;
  
  // Forward the request directly to the Google Apps Script
  const scriptResponse = await axios.post(googleAppsScriptUrl, {
    idToken,
    affinityChanges,
    skillChanges,
    essenceChanges
  }, {
    headers: {
      'Content-Type': 'text/plain'
    }
  });

  // Return the response from Google Apps Script
  res.status(scriptResponse.status).json(scriptResponse.data);

  } catch (error) {
    console.error('Error proxying to Google Apps Script:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

exports.createDiscordChannel = onRequest(
  { secrets: [DISCORD_TOKEN] },
  async (req, res) => {
    const { guildId, channelName, categoryId } = req.body;

    if (!guildId || !channelName || !categoryId) {
      return res.status(400).send("Missing required parameters.");
    }

    try {
      const response = await axios.post(
        `https://discord.com/api/v10/guilds/${guildId}/channels`,
        {
          name: channelName,
          type: 0,
          parent_id: categoryId,
        },
        {
          headers: {
            Authorization: `Bot ${DISCORD_TOKEN.value()}`,
            "Content-Type": "application/json",
          },
        }
      );

      return res.status(200).send({
        message: `✅ Created channel: ${response.data.name}`,
        channelId: response.data.id,
      });
    } catch (error) {
      const message = error.response?.data || error.message;
      console.error("❌ Discord API error:", message);
      return res.status(500).json({ error: message });
    }
  }
);

exports.createDiscordEvent = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  const {
    guildId,
    name,
    description,
    scheduledStartTime,
    scheduledEndTime,
    entityType,           // 1=Stage, 2=Voice, 3=External
    privacyLevel,         // usually 2
    channelId,            // For non-external
    entityMetadata        // { location: ... }
  } = req.body;

  // Basic required checks (don't require channelId unless it's a channel event)
  if (!guildId || !name || !scheduledStartTime) {
    return res.status(400).json({ error: "Missing required parameters: guildId, name, or scheduledStartTime." });
  }

  // Discord API payload
  const payload = {
    name,
    description: description || "",
    scheduled_start_time: new Date(scheduledStartTime).toISOString(),
    privacy_level: privacyLevel || 2,   // default to GUILD_ONLY
    entity_type: entityType || 3        // default to EXTERNAL
  };

  // Add channel_id and metadata as needed
  if (payload.entity_type === 3) { // EXTERNAL
    if (!scheduledEndTime || !entityMetadata?.location) {
      return res.status(400).json({ error: "Missing scheduledEndTime or entityMetadata.location for external event." });
    }
    payload.scheduled_end_time = new Date(scheduledEndTime).toISOString();
    payload.entity_metadata = entityMetadata;
  } else {
    if (!channelId) {
      return res.status(400).json({ error: "Missing channelId for channel event." });
    }
    payload.channel_id = channelId;
  }

  try {
    const response = await axios.post(
      `https://discord.com/api/v10/guilds/${guildId}/scheduled-events`,
      payload,
      {
        headers: {
          Authorization: `Bot ${DISCORD_TOKEN.value()}`,
          "Content-Type": "application/json"
        }
      }
    );

    return res.status(200).send({
      message: `✅ Created event: ${response.data.name}`,
      eventId: response.data.id
    });
  } catch (error) {
    const message = error.response?.data || error.message;
    console.error("❌ Discord API error:", message);
    return res.status(500).json({ error: message });
  }
});

  
exports.updateDiscordEvent = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  const { guildId, eventId, ...updateFields } = req.body;
  if (!guildId || !eventId) {
    return res.status(400).send("Missing guildId or eventId.");
  }
  try {
    const response = await axios.patch(
      `https://discord.com/api/v10/guilds/${guildId}/scheduled-events/${eventId}`,
      updateFields,
      {
        headers: {
          Authorization: `Bot ${DISCORD_TOKEN.value()}`,
          "Content-Type": "application/json"
        }
      }
    );
    return res.status(200).send({
      message: `✅ Updated event: ${response.data.name}`,
      eventId: response.data.id
    });
  } catch (error) {
    const message = error.response?.data || error.message;
    return res.status(500).json({ error: message });
  }
});

// QR Code Generation Function - Triggered when pc.json is updated
exports.generateQRCode = onObjectFinalized({ secrets: [GAME_SECRET] }, async (event) => {
  const filePath = event.data.name;
  const bucketName = event.data.bucket;
  
  // Only process pc.json files
  if (!filePath.endsWith('/pc.json')) {
    console.log(`Skipping non-pc.json file: ${filePath}`);
    return;
  }
  
  console.log(`🔄 Processing pc.json update: ${filePath}`);
  
  try {
    // Extract user email from file path (users/email/pc.json)
    const pathParts = filePath.split('/');
    if (pathParts.length !== 3 || pathParts[0] !== 'users') {
      console.log(`❌ Invalid file path format: ${filePath}`);
      return;
    }
    
    const userEmail = pathParts[1];
    console.log(`📧 Processing QR code for user: ${userEmail}`);
    
    // Get the storage bucket
    const bucket = getStorage().bucket(bucketName);
    
    // Download and parse the pc.json file
    const file = bucket.file(filePath);
    const [fileContent] = await file.download();
    const characterData = JSON.parse(fileContent.toString('utf8'));
    
    // Try to get the user's Firebase UID from their email
    let playerUid = characterData.playerUid || null;
    
    // If playerUid is not in the character data, try to get it from Firebase Auth
    if (!playerUid) {
      try {
        const userRecord = await getAuth().getUserByEmail(userEmail);
        playerUid = userRecord.uid;
        console.log(`🔍 Found Firebase UID for ${userEmail}: ${playerUid}`);
      } catch (error) {
        console.log(`⚠️ Could not find Firebase UID for ${userEmail}: ${error.message}`);
        // Continue without UID - it's not critical for QR code functionality
      }
    }
    
    // Extract required data for QR code
    const qrData = {
      game: "Crucible",
      playerNumber: characterData.playerNumber || 0,
      playerName: characterData.playerName || "Unknown",
      playerEmail: userEmail,
      playerUid: playerUid,
      timestamp: Date.now(),
      verificationHash: null // Will be calculated below
    };
    
    // Generate verification hash using Firebase Secret
    const secretKey = GAME_SECRET.value();
    const hashData = `${qrData.game}|${qrData.playerNumber}|${qrData.playerName}|${qrData.playerEmail}|${qrData.playerUid}|${qrData.timestamp}|${secretKey}`;
    const hash = crypto.createHash('sha256').update(hashData).digest('hex');
    qrData.verificationHash = hash.substring(0, 8); // Use first 8 characters for shorter QR codes
    
    console.log(`🔐 Generated verification hash: ${qrData.verificationHash}`);
    
    // Generate QR code as PNG
    const qrCodeBuffer = await QRCode.toBuffer(JSON.stringify(qrData), {
      type: 'image/png',
      width: 300,
      margin: 2,
      color: {
        dark: '#000000',
        light: '#FFFFFF'
      }
    });
    
    console.log(`📱 Generated QR code image (${qrCodeBuffer.length} bytes)`);
    
    // Upload QR code to the same user folder
    const qrFilePath = filePath.replace('/pc.json', '/qr.png');
    const qrFile = bucket.file(qrFilePath);
    
    await qrFile.save(qrCodeBuffer, {
      metadata: {
        contentType: 'image/png',
        cacheControl: 'public, max-age=3600' // Cache for 1 hour
      }
    });
    
    console.log(`✅ QR code uploaded to: ${qrFilePath}`);
    
    // Log the QR data for debugging (without the secret)
    console.log(`📊 QR Code Data:`, {
      game: qrData.game,
      playerNumber: qrData.playerNumber,
      playerName: qrData.playerName,
      playerEmail: qrData.playerEmail,
      timestamp: new Date(qrData.timestamp).toISOString(),
      verificationHash: qrData.verificationHash
    });
    
  } catch (error) {
    console.error(`❌ Error generating QR code for ${filePath}:`, error);
    
    // Don't throw the error to prevent the function from retrying indefinitely
    // The QR code generation failure shouldn't break the character update process
  }
});

// Check if user is super admin
async function isSuperAdmin(uid) {
  try {
    const superAdminDoc = await db.collection('roles').doc('superadmin').collection('members').doc(uid).get();
    return superAdminDoc.exists;
  } catch (error) {
    console.error('Error checking super admin status:', error);
    return false;
  }
}

// Create a new event
exports.createEvent = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { startDate, endDate, locationId, typeId } = req.body;

    // Validate required fields
    if (!startDate || !endDate || !locationId || !typeId) {
      return res.status(400).json({ ok: false, error: 'All fields are required' });
    }

    // Get location and type details
    const locationDoc = await db.collection('locations').doc(locationId).get();
    const typeDoc = await db.collection('event_types').doc(typeId).get();

    if (!locationDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Location not found' });
    }

    if (!typeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event type not found' });
    }

    const location = locationDoc.data();
    const type = typeDoc.data();

    // Create event document
    const eventData = {
      startDate: startDate,
      endDate: endDate,
      locationId: locationId,
      locationName: location.name,
      locationAddress: location.address,
      typeId: typeId,
      typeName: type.name,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const eventRef = await db.collection('events').add(eventData);

    return res.status(200).json({
      ok: true,
      eventId: eventRef.id,
      event: eventData
    });

  } catch (error) {
    console.error('Error creating event:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Update an existing event
exports.updateEvent = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventId, startDate, endDate, locationId, typeId } = req.body;

    // Validate required fields
    if (!eventId || !startDate || !endDate || !locationId || !typeId) {
      return res.status(400).json({ ok: false, error: 'All fields are required' });
    }

    // Check if event exists
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    // Get location and type details
    const locationDoc = await db.collection('locations').doc(locationId).get();
    const typeDoc = await db.collection('event_types').doc(typeId).get();

    if (!locationDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Location not found' });
    }

    if (!typeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event type not found' });
    }

    const location = locationDoc.data();
    const type = typeDoc.data();

    // Update event document
    const updateData = {
      startDate: startDate,
      endDate: endDate,
      locationId: locationId,
      locationName: location.name,
      locationAddress: location.address,
      typeId: typeId,
      typeName: type.name,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    };

    await db.collection('events').doc(eventId).update(updateData);

    return res.status(200).json({
      ok: true,
      message: 'Event updated successfully',
      eventId: eventId
    });

  } catch (error) {
    console.error('Error updating event:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Create a new location
exports.createLocation = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { name, address, timezone } = req.body;

    // Validate required fields
    if (!name || !address) {
      return res.status(400).json({ ok: false, error: 'Name and address are required' });
    }

    // Validate timezone if provided
    if (timezone && !moment.tz.zone(timezone)) {
      return res.status(400).json({ ok: false, error: 'Invalid timezone provided' });
    }

    // Check if location already exists
    const existingLocation = await db.collection('locations')
      .where('name', '==', name)
      .where('address', '==', address)
      .get();

    if (!existingLocation.empty) {
      return res.status(409).json({ ok: false, error: 'Location already exists' });
    }

    // Create location document
    const locationData = {
      name: name,
      address: address,
      timezone: timezone || 'America/New_York', // Default timezone if not provided
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
    };

    const locationRef = await db.collection('locations').add(locationData);

    return res.status(200).json({
      ok: true,
      locationId: locationRef.id,
      location: locationData
    });

  } catch (error) {
    console.error('Error creating location:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Create a new event type
exports.createEventType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { 
      name, 
      defaultCost, 
      defaultPreregCost,
      numberOfNpcShifts,
      npcShifts,
      numberOfCleanupShifts,
      cleanupShifts,
      payOptions
    } = req.body;

    // Validate required fields
    if (!name) {
      return res.status(400).json({ ok: false, error: 'Name is required' });
    }

    // Check if type already exists
    const existingType = await db.collection('event_types')
      .where('name', '==', name)
      .get();

    if (!existingType.empty) {
      return res.status(409).json({ ok: false, error: 'Event type already exists' });
    }

    // Create type document
    const typeData = {
      name: name,
      defaultCost: defaultCost || 0,
      defaultPreregCost: defaultPreregCost || 0,
      numberOfNpcShifts: numberOfNpcShifts || 0,
      npcShifts: npcShifts || [],
      numberOfCleanupShifts: numberOfCleanupShifts || 0,
      cleanupShifts: cleanupShifts || [],
      payOptions: payOptions || [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
    };

    const typeRef = await db.collection('event_types').add(typeData);

    return res.status(200).json({
      ok: true,
      typeId: typeRef.id,
      type: typeData
    });

  } catch (error) {
    console.error('Error creating event type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Update event type
exports.updateEventType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { 
      eventTypeId,
      name, 
      defaultCost, 
      defaultPreregCost,
      numberOfNpcShifts,
      npcShifts,
      numberOfCleanupShifts,
      cleanupShifts,
      payOptions
    } = req.body;

    // Validate required fields
    if (!eventTypeId || !name) {
      return res.status(400).json({ ok: false, error: 'Event Type ID and Name are required' });
    }

    // Check if event type exists
    const eventTypeDoc = await db.collection('event_types').doc(eventTypeId).get();
    if (!eventTypeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event type not found' });
    }

    // Check if name is being changed and if it conflicts with existing types
    const existingType = eventTypeDoc.data();
    if (existingType.name !== name) {
      const nameConflictQuery = await db.collection('event_types')
        .where('name', '==', name)
        .get();

      if (!nameConflictQuery.empty) {
        return res.status(409).json({ ok: false, error: 'Event type with this name already exists' });
      }
    }

    // Update event type document
    const updateData = {
      name: name,
      defaultCost: defaultCost || 0,
      defaultPreregCost: defaultPreregCost || 0,
      numberOfNpcShifts: numberOfNpcShifts || 0,
      npcShifts: npcShifts || [],
      numberOfCleanupShifts: numberOfCleanupShifts || 0,
      cleanupShifts: cleanupShifts || [],
      payOptions: payOptions || [],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    };

    await db.collection('event_types').doc(eventTypeId).update(updateData);

    return res.status(200).json({
      ok: true,
      message: 'Event type updated successfully',
      eventTypeId: eventTypeId
    });

  } catch (error) {
    console.error('Error updating event type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Update location
exports.updateLocation = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { locationId, name, address, timezone } = req.body;

    // Validate required fields
    if (!locationId || !name || !address) {
      return res.status(400).json({ ok: false, error: 'Location ID, Name, and Address are required' });
    }

    // Validate timezone if provided
    if (timezone && !moment.tz.zone(timezone)) {
      return res.status(400).json({ ok: false, error: 'Invalid timezone provided' });
    }

    // Check if location exists
    const locationDoc = await db.collection('locations').doc(locationId).get();
    if (!locationDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Location not found' });
    }

    // Check if name is being changed and if it conflicts with existing locations
    const existingLocation = locationDoc.data();
    if (existingLocation.name !== name) {
      const nameConflictQuery = await db.collection('locations')
        .where('name', '==', name)
        .get();

      if (!nameConflictQuery.empty) {
        return res.status(409).json({ ok: false, error: 'Location with this name already exists' });
      }
    }

    // Update location document
    const updateData = {
      name: name,
      address: address,
      timezone: timezone || existingLocation.timezone || 'America/New_York', // Keep existing timezone if not provided
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    };

    await db.collection('locations').doc(locationId).update(updateData);

    return res.status(200).json({
      ok: true,
      message: 'Location updated successfully',
      locationId: locationId
    });

  } catch (error) {
    console.error('Error updating location:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Delete event type
exports.deleteEventType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventTypeId } = req.body;

    if (!eventTypeId) {
      return res.status(400).json({ ok: false, error: 'Event Type ID is required' });
    }

    // Check if event type exists
    const eventTypeDoc = await db.collection('event_types').doc(eventTypeId).get();
    if (!eventTypeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event type not found' });
    }

    // Check if event type is being used by any events
    const eventsUsingType = await db.collection('events')
      .where('typeId', '==', eventTypeId)
      .get();

    if (!eventsUsingType.empty) {
      return res.status(409).json({ 
        ok: false, 
        error: 'Cannot delete event type that is being used by existing events' 
      });
    }

    // Delete event type
    await db.collection('event_types').doc(eventTypeId).delete();

    return res.status(200).json({
      ok: true,
      message: 'Event type deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting event type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Delete location
exports.deleteLocation = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { locationId } = req.body;

    if (!locationId) {
      return res.status(400).json({ ok: false, error: 'Location ID is required' });
    }

    // Check if location exists
    const locationDoc = await db.collection('locations').doc(locationId).get();
    if (!locationDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Location not found' });
    }

    // Check if location is being used by any events
    const eventsUsingLocation = await db.collection('events')
      .where('locationId', '==', locationId)
      .get();

    if (!eventsUsingLocation.empty) {
      return res.status(409).json({ 
        ok: false, 
        error: 'Cannot delete location that is being used by existing events' 
      });
    }

    // Delete location
    await db.collection('locations').doc(locationId).delete();

    return res.status(200).json({
      ok: true,
      message: 'Location deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting location:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Delete event
exports.deleteEvent = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventId } = req.body;

    // Validate required fields
    if (!eventId) {
      return res.status(400).json({ ok: false, error: 'Event ID is required' });
    }

    // Check if event exists
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    // Delete the event
    await db.collection('events').doc(eventId).delete();

    return res.status(200).json({
      ok: true,
      message: 'Event deleted successfully',
      eventId: eventId
    });

  } catch (error) {
    console.error('Error deleting event:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get all events
exports.getEvents = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // All authenticated users can view events
    const eventsSnapshot = await db.collection('events')
      .orderBy('startDate', 'asc')
      .get();

    const events = [];
    eventsSnapshot.forEach(doc => {
      events.push({
        id: doc.id,
        ...doc.data()
      });
    });

    return res.status(200).json({
      ok: true,
      events: events
    });

  } catch (error) {
    console.error('Error getting events:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get all locations
exports.getLocations = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // All authenticated users can view locations
    const locationsSnapshot = await db.collection('locations')
      .orderBy('name', 'asc')
      .get();

    const locations = [];
    locationsSnapshot.forEach(doc => {
      locations.push({
        id: doc.id,
        ...doc.data()
      });
    });

    return res.status(200).json({
      ok: true,
      locations: locations
    });

  } catch (error) {
    console.error('Error getting locations:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get all event types
exports.getEventTypes = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // All authenticated users can view event types
    const typesSnapshot = await db.collection('event_types')
      .orderBy('name', 'asc')
      .get();

    const types = [];
    typesSnapshot.forEach(doc => {
      const data = doc.data();
      console.log(`📋 Event Type: ${data.name} (ID: ${doc.id})`);
      console.log(`   - Fields: ${Object.keys(data)}`);
      
      // Ensure all required fields exist with defaults
      const typeWithDefaults = {
        id: doc.id,
        name: data.name || '',
        defaultCost: data.defaultCost || 0,
        defaultPreregCost: data.defaultPreregCost || 0,
        npcShifts: data.npcShifts || [],
        numberOfNpcShifts: data.numberOfNpcShifts || 0,
        numberOfCleanupShifts: data.numberOfCleanupShifts || 0,
        cleanupShifts: data.cleanupShifts || [],
        payOptions: data.payOptions || [],
        ...data // Include any other existing fields
      };
      
      types.push(typeWithDefaults);
    });

    console.log(`✅ Returning ${types.length} event types`);

    return res.status(200).json({
      ok: true,
      types: types
    });

  } catch (error) {
    console.error('Error getting event types:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Activate event registration
exports.activateEventRegistration = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const {
      eventId,
      eventName,
      shortName,
      eventImage,
      cost,
      preregCost,
      preregDateEnd,
      extraInfo
    } = req.body;

    // Validate required fields
    if (!eventId || !eventName || !shortName) {
      return res.status(400).json({ ok: false, error: 'Event ID, Event Name, and Short Name are required' });
    }

    // Validate short name for Discord compatibility
    const discordNameRegex = /^[a-z0-9-]+$/;
    if (!discordNameRegex.test(shortName)) {
      return res.status(400).json({ ok: false, error: 'Short name must contain only lowercase letters, numbers, and hyphens' });
    }

    if (shortName.length > 32) {
      return res.status(400).json({ ok: false, error: 'Short name must be 32 characters or less' });
    }

    // Check if event exists
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    // Check if registration is already activated
    const eventData = eventDoc.data();
    if (eventData.registrationActivated) {
      return res.status(409).json({ ok: false, error: 'Registration is already activated for this event' });
    }

    // Update event with registration details
    const registrationData = {
      registrationActivated: true,
      registrationDetails: {
        eventName: eventName,
        shortName: shortName,
        eventImage: eventImage || '',
        cost: cost || 0,
        preregCost: preregCost || 0,
        preregDateEnd: preregDateEnd || null,
        extraInfo: extraInfo || '',
        activatedAt: admin.firestore.FieldValue.serverTimestamp(),
        activatedBy: uid,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('events').doc(eventId).update(registrationData);

    return res.status(200).json({
      ok: true,
      message: 'Event registration activated successfully',
      eventId: eventId
    });

  } catch (error) {
    console.error('Error activating event registration:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Update event registration details
exports.updateEventRegistration = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { 
      eventId,
      eventName,
      shortName,
      eventImage,
      cost,
      preregCost,
      preregDateEnd,
      extraInfo
    } = req.body;

    // Validate required fields
    if (!eventId || !eventName || !shortName) {
      return res.status(400).json({ ok: false, error: 'Event ID, Event Name, and Short Name are required' });
    }

    // Validate short name for Discord compatibility
    const discordNameRegex = /^[a-z0-9-]+$/;
    if (!discordNameRegex.test(shortName)) {
      return res.status(400).json({ ok: false, error: 'Short name must contain only lowercase letters, numbers, and hyphens' });
    }

    if (shortName.length > 32) {
      return res.status(400).json({ ok: false, error: 'Short name must be 32 characters or less' });
    }

    // Check if event exists and registration is activated
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    const eventData = eventDoc.data();
    if (!eventData.registrationActivated) {
      return res.status(400).json({ ok: false, error: 'Registration is not activated for this event' });
    }

    // Update event registration details
    const registrationData = {
      'registrationDetails.eventName': eventName,
      'registrationDetails.shortName': shortName,
      'registrationDetails.eventImage': eventImage || '',
      'registrationDetails.cost': cost || 0,
      'registrationDetails.preregCost': preregCost || 0,
      'registrationDetails.preregDateEnd': preregDateEnd || null,
      'registrationDetails.extraInfo': extraInfo || '',
      'registrationDetails.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
      'registrationDetails.updatedBy': uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('events').doc(eventId).update(registrationData);

    return res.status(200).json({
      ok: true,
      message: 'Event registration updated successfully',
      eventId: eventId
    });

  } catch (error) {
    console.error('Error updating event registration:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Create event attendee type
exports.createEventAttendeeType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { name, buildForEvent, affinityPointsForEvent, maxConsumeForEvent } = req.body;

    // Validate required fields
    if (!name) {
      return res.status(400).json({ ok: false, error: 'Name is required' });
    }

    // Check if attendee type already exists
    const existingType = await db.collection('event_attendee_types')
      .where('name', '==', name)
      .get();

    if (!existingType.empty) {
      return res.status(409).json({ ok: false, error: 'Event attendee type already exists' });
    }

    // Create attendee type document
    const attendeeTypeData = {
      name: name,
      buildForEvent: buildForEvent || 0,
      affinityPointsForEvent: affinityPointsForEvent || 0,
      maxConsumeForEvent: maxConsumeForEvent || 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
    };

    const attendeeTypeRef = await db.collection('event_attendee_types').add(attendeeTypeData);

    return res.status(200).json({
      ok: true,
      attendeeTypeId: attendeeTypeRef.id,
      attendeeType: attendeeTypeData
    });

  } catch (error) {
    console.error('Error creating event attendee type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get all event attendee types
exports.getEventAttendeeTypes = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // All authenticated users can view event attendee types
    const attendeeTypesSnapshot = await db.collection('event_attendee_types')
      .orderBy('name', 'asc')
      .get();

    const attendeeTypes = [];
    attendeeTypesSnapshot.forEach(doc => {
      attendeeTypes.push({
        id: doc.id,
        ...doc.data()
      });
    });

    return res.status(200).json({
      ok: true,
      attendeeTypes: attendeeTypes
    });

  } catch (error) {
    console.error('Error getting event attendee types:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Update event attendee type
exports.updateEventAttendeeType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { attendeeTypeId, name, buildForEvent, affinityPointsForEvent, maxConsumeForEvent } = req.body;

    // Validate required fields
    if (!attendeeTypeId || !name) {
      return res.status(400).json({ ok: false, error: 'Attendee Type ID and Name are required' });
    }

    // Check if attendee type exists
    const attendeeTypeDoc = await db.collection('event_attendee_types').doc(attendeeTypeId).get();
    if (!attendeeTypeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Attendee type not found' });
    }

    // Check if name is being changed and if it conflicts with existing types
    const existingType = attendeeTypeDoc.data();
    if (existingType.name !== name) {
      const nameConflictQuery = await db.collection('event_attendee_types')
        .where('name', '==', name)
        .get();

      if (!nameConflictQuery.empty) {
        return res.status(409).json({ ok: false, error: 'Attendee type with this name already exists' });
      }
    }

    // Update attendee type document
    const updateData = {
      name: name,
      buildForEvent: buildForEvent || 0,
      affinityPointsForEvent: affinityPointsForEvent || 0,
      maxConsumeForEvent: maxConsumeForEvent || 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    };

    await db.collection('event_attendee_types').doc(attendeeTypeId).update(updateData);

    return res.status(200).json({
      ok: true,
      message: 'Attendee type updated successfully',
      attendeeTypeId: attendeeTypeId
    });

  } catch (error) {
    console.error('Error updating attendee type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Delete event attendee type
exports.deleteEventAttendeeType = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { attendeeTypeId } = req.body;

    if (!attendeeTypeId) {
      return res.status(400).json({ ok: false, error: 'Attendee Type ID is required' });
    }

    // Check if attendee type exists
    const attendeeTypeDoc = await db.collection('event_attendee_types').doc(attendeeTypeId).get();
    if (!attendeeTypeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Attendee type not found' });
    }

    // Check if attendee type is being used by any registrations
    try {
      const registrationsUsingType = await db.collectionGroup('registrations')
        .where('attendeeTypeId', '==', attendeeTypeId)
        .get();

      if (!registrationsUsingType.empty) {
        return res.status(409).json({ 
          ok: false, 
          error: 'Cannot delete attendee type that is being used by existing registrations' 
        });
      }
    } catch (queryError) {
      console.warn('Could not check registrations using attendee type:', queryError.message);
      // Continue with deletion if we can't check usage (security rules might prevent collectionGroup queries)
    }

    // Delete attendee type
    await db.collection('event_attendee_types').doc(attendeeTypeId).delete();

    return res.status(200).json({
      ok: true,
      message: 'Attendee type deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting attendee type:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Register user for an event
exports.registerForEvent = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { eventId, attendeeTypeId, selectedNpcShifts, selectedCleanupShifts, selectedPayOption } = req.body;

    // Validate required fields
    if (!eventId || !attendeeTypeId) {
      return res.status(400).json({ ok: false, error: 'Event ID and Attendee Type ID are required' });
    }

    // Check if event exists and has active registration
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    const eventData = eventDoc.data();
    if (!eventData.registrationActivated) {
      return res.status(400).json({ ok: false, error: 'Event registration is not active' });
    }

    // Check if user is already registered
    const existingRegistration = await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .doc(uid)
      .get();

    if (existingRegistration.exists) {
      return res.status(409).json({ ok: false, error: 'User is already registered for this event' });
    }

    // Get attendee type details
    const attendeeTypeDoc = await db.collection('event_attendee_types').doc(attendeeTypeId).get();
    if (!attendeeTypeDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Attendee type not found' });
    }

    const attendeeTypeData = attendeeTypeDoc.data();

    // Create registration
    const registrationData = {
      userId: uid,
      attendeeTypeId: attendeeTypeId,
      attendeeTypeName: attendeeTypeData.name,
      buildForEvent: attendeeTypeData.buildForEvent,
      affinityPointsForEvent: attendeeTypeData.affinityPointsForEvent,
      maxConsumeForEvent: attendeeTypeData.maxConsumeForEvent,
      selectedNpcShifts: selectedNpcShifts || [],
      selectedCleanupShifts: selectedCleanupShifts || [],
      selectedPayOption: selectedPayOption,
      registeredAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .doc(uid)
      .set(registrationData);

    return res.status(200).json({
      ok: true,
      message: 'Successfully registered for event',
      registration: registrationData
    });

  } catch (error) {
    console.error('Error registering for event:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get user's event registration
exports.getUserEventRegistration = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { eventId } = req.query;

    if (!eventId) {
      return res.status(400).json({ ok: false, error: 'Event ID is required' });
    }

    // Get user's registration for this event
    const registrationDoc = await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .doc(uid)
      .get();

    if (!registrationDoc.exists) {
      return res.status(200).json({
        ok: true,
        registered: false,
        registration: null
      });
    }

    return res.status(200).json({
      ok: true,
      registered: true,
      registration: {
        id: registrationDoc.id,
        ...registrationDoc.data()
      }
    });

  } catch (error) {
    console.error('Error getting user event registration:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Check player registration for an event
exports.checkPlayerRegistration = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventId, playerUid, qrData } = req.body;

    // Validate required fields
    if (!eventId || !playerUid) {
      return res.status(400).json({ ok: false, error: 'Event ID and Player UID are required' });
    }

    // Check if event exists
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    // Check if player is registered for this event
    const registrationDoc = await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .doc(playerUid)
      .get();

    const isRegistered = registrationDoc.exists;

    // Check if player is already checked in
    const checkInDoc = await db.collection('events')
      .doc(eventId)
      .collection('checkins')
      .doc(playerUid)
      .get();

    const isCheckedIn = checkInDoc.exists;

    // Get player name from QR code data first, then fallback to other sources
    let playerName = 'Unknown Player';
    
    // Try to get player name from QR code data first
    if (qrData && qrData.playerName && qrData.playerName !== 'Unknown') {
      playerName = qrData.playerName;
    } else if (isRegistered) {
      // Fallback to registration data
      const registrationData = registrationDoc.data();
      playerName = registrationData.attendeeTypeName || 'Unknown Player';
    } else {
      // Try to get player name from user document
      try {
        const userDoc = await db.collection('users').doc(playerUid).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          playerName = userData.displayName || userData.email || 'Unknown Player';
        }
      } catch (error) {
        console.log('Could not fetch user data for player name');
      }
    }

    return res.status(200).json({
      ok: true,
      isRegistered: isRegistered,
      isCheckedIn: isCheckedIn,
      playerName: playerName
    });

  } catch (error) {
    console.error('Error checking player registration:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Check in a player for an event
exports.checkInPlayer = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventId, playerUid, attendeeTypeId, attendeeTypeName, buildForEvent, affinityPointsForEvent, qrData } = req.body;

    // Validate required fields
    if (!eventId || !playerUid) {
      return res.status(400).json({ ok: false, error: 'Event ID and Player UID are required' });
    }

    // Check if event exists
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }

    const eventData = eventDoc.data();
    
    // Get event name
    let eventName = eventData.type || 'Unknown Event';
    if (eventData.registrationActivated && eventData.registrationDetails && eventData.registrationDetails.eventName) {
      eventName = eventData.registrationDetails.eventName;
    }

    // Check if player is already checked in
    const existingCheckIn = await db.collection('events')
      .doc(eventId)
      .collection('checkins')
      .doc(playerUid)
      .get();

    if (existingCheckIn.exists) {
      return res.status(409).json({ ok: false, error: 'Player is already checked in for this event' });
    }

    // Get player registration details
    const registrationDoc = await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .doc(playerUid)
      .get();

    let attendingAs = 'Unknown';
    let buildAdjustment = 0;
    let apAdjustment = 0;

    if (registrationDoc.exists) {
      const registrationData = registrationDoc.data();
      attendingAs = registrationData.attendeeTypeName || 'Unknown';
      buildAdjustment = registrationData.buildForEvent || 0;
      apAdjustment = registrationData.affinityPointsForEvent || 0;
    } else if (attendeeTypeName && buildForEvent && affinityPointsForEvent) {
      // Use provided attendee type info for unregistered players
      attendingAs = attendeeTypeName;
      buildAdjustment = parseInt(buildForEvent) || 0;
      apAdjustment = parseInt(affinityPointsForEvent) || 0;
    }

    // Get player email and character number
    let playerEmail = 'Unknown';
    let characterNumber = 'Unknown';
    
    // Try to get character number from QR code data first
    if (qrData && qrData.playerNumber) {
      characterNumber = qrData.playerNumber.toString();
    }
    
    // Get player email from Firebase Auth
    try {
      const userRecord = await getAuth().getUser(playerUid);
      playerEmail = userRecord.email || 'Unknown';
    } catch (error) {
      console.log(`⚠️ Could not get email for user ${playerUid}: ${error.message}`);
      // Fallback to Firestore user document
      const playerUserDoc = await db.collection('users').doc(playerUid).get();
      if (playerUserDoc.exists) {
        const userData = playerUserDoc.data();
        playerEmail = userData.email || 'Unknown';
        // Also try to get character number from user data if not in QR code
        if (characterNumber === 'Unknown' && userData.characterNumber) {
          characterNumber = userData.characterNumber.toString();
        }
      }
    }

    // Create check-in record in Firebase
    const checkInData = {
      playerUid: playerUid,
      checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
      checkedInBy: uid,
    };

    await db.collection('events')
      .doc(eventId)
      .collection('checkins')
      .doc(playerUid)
      .set(checkInData);

    // Write to Google Sheets
    try {
      // Initialize Google Sheets API
      const auth = new googleapis.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
        keyFile: './service-account-key.json'
      });

      const sheets = googleapis.sheets({ version: 'v4', auth });

      // Prepare the row data for Google Sheets
      const rowData = [
        decodedToken.email,                                              // checkInUserEmail (scanner/admin email)
        new Date().toISOString(),                                        // Timestamp
        playerEmail,                                                     // characterNumber (player being scanned email)
        eventName,                                                       // Event Name
        attendingAs,                                                     // attendingAs
        buildAdjustment,                                                 // Build Adj
        apAdjustment                                                     // AP Adj
      ];

      // Append the row to the Google Sheet
      const sheetsResponse = await sheets.spreadsheets.values.append({
        spreadsheetId: config.google_sheets.checkin_spreadsheet_id,
        range: `${config.google_sheets.checkin_sheet_name}!A:G`,
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
        resource: {
          values: [rowData]
        }
      });

      console.log('Check-in data written to Google Sheets:', sheetsResponse.data);

    } catch (sheetsError) {
      console.error('Error writing to Google Sheets:', sheetsError);
      // Don't fail the check-in if Google Sheets fails, but log the error
    }

    return res.status(200).json({
      ok: true,
      message: 'Player checked in successfully',
      checkIn: checkInData,
      sheetsData: {
        attendingAs,
        buildAdjustment,
        apAdjustment,
        characterNumber
      }
    });

  } catch (error) {
    console.error('Error checking in player:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Check if user is super admin
exports.checkSuperAdmin = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);

    return res.status(200).json({
      ok: true,
      isSuperAdmin: isAdmin
    });

  } catch (error) {
    console.error('Error checking super admin status:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Generate Monster Core printout
exports.generateMonsterCorePrintout = onRequest({ secrets: [GAME_SECRET] }, async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { numberOfPages, tier } = req.body;

    // Validate required fields
    if (!numberOfPages || !tier) {
      return res.status(400).json({ ok: false, error: 'Number of pages and tier are required' });
    }

    if (numberOfPages < 1 || numberOfPages > 100) {
      return res.status(400).json({ ok: false, error: 'Number of pages must be between 1 and 100' });
    }

    // Validate tier is one of the allowed values
    const allowedTiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    if (!allowedTiers.includes(tier)) {
      return res.status(400).json({ ok: false, error: 'Tier must be one of: Iron, Silver, Gold, Jade, Saint, Sovereign' });
    }

    const coresPerPage = 10; // Avery 28371 format, 10 cards per page (5 rows x 2 columns)
    const totalCores = numberOfPages * coresPerPage;
    const cores = [];

    // Generate cores
    for (let i = 0; i < totalCores; i++) {
      const timestamp = Date.now() + i; // Ensure unique timestamps
      const uniqueNumber = Math.floor(Math.random() * 1000000) + 1;
      
      // Generate verification hash using Firebase Secret
      const secret = GAME_SECRET.value();
      const hashData = `Crucible:MonsterCore:${tier}:${uniqueNumber}:${timestamp}`;
      const verificationHash = crypto.createHash('sha256')
        .update(hashData + secret)
        .digest('hex')
        .substring(0, 8);

      // Full core data for database
      const fullCoreData = {
        game: 'Crucible',
        timestamp: timestamp,
        verificationHash: verificationHash,
        label: 'Monster Core',
        tier: tier,
        uniqueNumber: uniqueNumber,
        isActive: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Use uniqueNumber as the document ID for efficient lookup
      const coreRef = db.collection('monster_cores').doc(uniqueNumber.toString());
      await coreRef.set(fullCoreData);
      fullCoreData.id = uniqueNumber.toString();
      cores.push(fullCoreData);

      // Minimal QR data (only what's needed for identification)
      const qrData = {
        game: 'Crucible',
        label: 'Monster Core',
        tier: tier,
        id: uniqueNumber.toString(), // Use uniqueNumber as ID for direct lookup
        verificationHash: verificationHash,
      };

      // Generate QR code for this core
      const qrCodeBuffer = await QRCode.toBuffer(JSON.stringify(qrData), {
        errorCorrectionLevel: 'M',
        type: 'image/png',
        quality: 0.92,
        margin: 1,
        color: {
          dark: '#000000',
          light: '#FFFFFF'
        },
        width: 200
      });

      // Upload QR code to Firebase Storage
      const qrFileName = `monster_cores/${uniqueNumber}_qr.png`;
      const qrFile = getStorage().bucket().file(qrFileName);
      await qrFile.save(qrCodeBuffer, {
        metadata: {
          contentType: 'image/png',
        }
      });
    }

    // Generate PDF with Avery 28371 business card template
    const PDFDocument = require('pdfkit');
    const doc = new PDFDocument({
      size: 'A4',
      margin: 0
    });

    // Set response headers for PDF download
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="monster_cores_tier_${tier}.pdf"`);

    // Pipe PDF to response
    doc.pipe(res);

    // Avery 28371 specifications:
    // - 10 cards per sheet (5 rows x 2 columns)
    // - Card size: 3.5" x 2" (252 x 144 points)
    // - Sheet size: 8.5" x 11" (612 x 792 points)
    // - Spacing between cards: 0.125" (9 points)
    
    const cardWidth = 252; // 3.5 inches
    const cardHeight = 144; // 2 inches
    const cardsPerRow = 2;
    const cardsPerCol = 5;
    const cardSpacing = 9; // 0.125 inches
    
    // Calculate margins to center the cards on the page
    const pageWidth = 612; // 8.5 inches
    const pageHeight = 792; // 11 inches
    
    // Calculate total width and height of all cards including spacing
    const totalCardsWidth = cardsPerRow * cardWidth + (cardsPerRow - 1) * cardSpacing;
    const totalCardsHeight = cardsPerCol * cardHeight + (cardsPerCol - 1) * cardSpacing;
    
    // Calculate margins to center the cards, with slight left adjustment
    const leftMargin = (pageWidth - totalCardsWidth) / 2 - 5; // Move 5 points (about 2mm) to the left
    const topMargin = (pageHeight - totalCardsHeight) / 2;

    // Generate pages
    for (let page = 0; page < numberOfPages; page++) {
      if (page > 0) {
        doc.addPage();
      }

      // Generate cards for this page
      for (let row = 0; row < cardsPerCol; row++) {
        for (let col = 0; col < cardsPerRow; col++) {
          const cardIndex = page * coresPerPage + row * cardsPerRow + col;
          if (cardIndex >= cores.length) break;

          const core = cores[cardIndex];
          const x = leftMargin + col * (cardWidth + cardSpacing);
          const y = topMargin + row * (cardHeight + cardSpacing);

          // Draw card border
          doc.rect(x, y, cardWidth, cardHeight)
             .stroke();

          // Add tier title (left side of card, vertically centered, without rotation)
          try {
            const tierText = core.tier || 'Unknown';
            doc.fontSize(20) // Doubled from 10
               .font('Helvetica-Bold')
               .text(tierText, x + 10, y + cardHeight / 2 - 10, {
                 align: 'left',
                 width: 60
               });
          } catch (error) {
            console.error(`Error rendering tier text for core ${core.id}:`, error);
            // Fallback: draw a simple rectangle to indicate text position
            doc.rect(x + 20, y + 10, 10, 20).stroke();
          }

          // Add "Core" text below tier title
          try {
            doc.fontSize(20) // Doubled font size
               .font('Helvetica-Bold')
               .text('Core', x + 10, y + cardHeight / 2 + 10, {
                 align: 'left',
                 width: 60
               });
          } catch (error) {
            console.error(`Error rendering "Core" text for core ${core.id}:`, error);
            // Fallback: draw a simple rectangle to indicate text position
            doc.rect(x + 45, y + 10, 10, 20).stroke();
          }

          // Add QR code image (right side of card, vertically centered)
          // Calculate QR code size to fit in the card, leaving space for text on left
          const textWidth = 80; // Space needed for tier + "Core" text (increased for better spacing)
          const qrMargin = 10; // Margin from edges
          const availableHeight = cardHeight - 2 * qrMargin;
          const availableWidth = cardWidth - textWidth - 2 * qrMargin; // Leave space for text
          const qrSize = Math.min(availableWidth, availableHeight);
          const qrX = x + cardWidth - qrSize - qrMargin; // Right-justified
          const qrY = y + (cardHeight - qrSize) / 2; // Vertically centered
          
          // Embed the actual QR code image
          try {
            const qrFileName = `monster_cores/${core.uniqueNumber}_qr.png`;
            const qrFile = getStorage().bucket().file(qrFileName);
            const [qrBuffer] = await qrFile.download();
            
            // Embed the QR code image in the PDF
            doc.image(qrBuffer, qrX, qrY, {
              width: qrSize,
              height: qrSize
            });
          } catch (error) {
            console.error(`Error embedding QR code for core ${core.id}:`, error);
            // Fallback: draw a placeholder rectangle if QR code can't be loaded
            doc.rect(qrX, qrY, qrSize, qrSize)
               .stroke();
            doc.fontSize(16) // Doubled from 8
               .font('Helvetica')
               .text('QR Error', qrX + qrSize/2, qrY + qrSize/2 - 4, {
                 align: 'center',
                 width: qrSize
               });
          }
        }
      }
    }

    doc.end();

  } catch (error) {
    console.error('Error generating monster core printout:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get Monster Cores
exports.getMonsterCores = onRequest(async (req, res) => {
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
    const coresSnapshot = await db.collection('monster_cores').get();
    const cores = [];

    coresSnapshot.forEach((doc) => {
      cores.push({
        id: doc.id,
        ...doc.data()
      });
    });

    return res.status(200).json({
      ok: true,
      cores: cores
    });

  } catch (error) {
    console.error('Error getting monster cores:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Track Monster Core scan
exports.trackMonsterCoreScan = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { coreId, scanResult, characterData } = req.body;

    // Validate required fields
    if (!coreId || !scanResult) {
      return res.status(400).json({ ok: false, error: 'Core ID and scan result are required' });
    }

    // Record the scan
    const scanData = {
      playerUid: uid,
      coreId: coreId,
      scanResult: scanResult,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('monster_core_scans').add(scanData);

    return res.status(200).json({
      ok: true,
      message: 'Scan recorded successfully'
    });

  } catch (error) {
    console.error('Error tracking monster core scan:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Consume Monster Core
exports.consumeMonsterCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { coreId, consumptionType, characterData } = req.body;

    // Validate required fields
    if (!coreId || !consumptionType) {
      return res.status(400).json({ ok: false, error: 'Core ID and consumption type are required' });
    }

    // Check if core exists and is active
    const coreDoc = await db.collection('monster_cores').doc(coreId).get();
    if (!coreDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Monster core not found' });
    }

    const coreData = coreDoc.data();
    if (!coreData.isActive) {
      return res.status(400).json({ ok: false, error: 'Monster core is not active' });
    }

    // Record the consumption
    const consumptionData = {
      playerUid: uid,
      coreId: coreId,
      consumptionType: consumptionType, // 'build', 'affinity', 'reset'
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('monster_core_consumptions').add(consumptionData);

    // Deactivate the core
    await db.collection('monster_cores').doc(coreId).update({
      isActive: false,
      consumedBy: uid,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
      consumptionType: consumptionType
    });

    // If this is a build consumption, write to Google Sheets
    if (consumptionType === 'build') {
      try {
        // Get user email
        let userEmail = 'Unknown';
        try {
          const userRecord = await getAuth().getUser(uid);
          userEmail = userRecord.email || 'Unknown';
        } catch (error) {
          console.log(`⚠️ Could not get email for user ${uid}: ${error.message}`);
          const userDoc = await db.collection('users').doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            userEmail = userData.email || 'Unknown';
          }
        }

        // Write to Google Sheets
        const auth = new googleapis.auth.GoogleAuth({
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
          keyFile: './service-account-key.json'
        });
        const sheets = googleapis.sheets({ version: 'v4', auth });

        const rowData = [
          userEmail,                                                      // Email
          new Date().toISOString(),                                       // Timestamp
          coreData.tier,                                                  // Core Tier
          'TBD'                                                           // Event (placeholder for now)
        ];

        const sheetsResponse = await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.consume_cores_spreadsheet_id,
          range: `${config.google_sheets.consume_cores_sheet_name}!A:D`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: {
            values: [rowData]
          }
        });
        console.log('Core consumption data written to Google Sheets:', sheetsResponse.data);
      } catch (sheetsError) {
        console.error('Error writing to Google Sheets:', sheetsError);
        // Don't fail the entire operation if Google Sheets write fails
      }
    }

    // If this is an affinity consumption, write to Google Sheets
    if (consumptionType === 'affinity') {
      try {
        // Get user email
        let userEmail = 'Unknown';
        try {
          const userRecord = await getAuth().getUser(uid);
          userEmail = userRecord.email || 'Unknown';
        } catch (error) {
          console.log(`⚠️ Could not get email for user ${uid}: ${error.message}`);
          const userDoc = await db.collection('users').doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            userEmail = userData.email || 'Unknown';
          }
        }

        // Calculate perfect cultivation points
        // Perfect cultivation occurs when core tier is higher than character tier
        let perfectCultivationPoints = 0;
        if (characterData && characterData.cultivationTier && coreData.tier) {
          const tierOrder = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
          const characterTierIndex = tierOrder.indexOf(characterData.cultivationTier);
          const coreTierIndex = tierOrder.indexOf(coreData.tier);
          
          if (characterTierIndex !== -1 && coreTierIndex !== -1 && coreTierIndex > characterTierIndex) {
            perfectCultivationPoints = coreTierIndex - characterTierIndex;
          }
        }

        // Write to Google Sheets
        const auth = new googleapis.auth.GoogleAuth({
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
          keyFile: './service-account-key.json'
        });
        const sheets = googleapis.sheets({ version: 'v4', auth });

        const rowData = [
          userEmail,                                                      // Email
          new Date().toISOString(),                                       // Timestamp
          coreData.tier,                                                  // Core Tier
          perfectCultivationPoints,                                       // Perfect Cultivation Points
          'TBD'                                                           // Event (placeholder for now)
        ];

        const sheetsResponse = await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.slot_cores_spreadsheet_id,
          range: `${config.google_sheets.slot_cores_sheet_name}!A:E`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: {
            values: [rowData]
          }
        });
        console.log('Core slotting data written to Google Sheets:', sheetsResponse.data);
      } catch (sheetsError) {
        console.error('Error writing to Google Sheets:', sheetsError);
        // Don't fail the entire operation if Google Sheets write fails
      }
    }

    return res.status(200).json({
      ok: true,
      message: 'Core consumed successfully'
    });

  } catch (error) {
    console.error('Error consuming monster core:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get Monster Core consumption stats
exports.getMonsterCoreStats = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Get user's consumption stats
    const consumptionsSnapshot = await db.collection('monster_core_consumptions')
      .where('playerUid', '==', uid)
      .get();

    const stats = {
      totalConsumed: 0,
      buildConsumed: 0,
      affinityConsumed: 0,
      resetConsumed: 0,
      byTier: {}
    };

    consumptionsSnapshot.forEach((doc) => {
      const data = doc.data();
      stats.totalConsumed++;
      
      if (data.consumptionType === 'build') stats.buildConsumed++;
      else if (data.consumptionType === 'affinity') stats.affinityConsumed++;
      else if (data.consumptionType === 'reset') stats.resetConsumed++;
      
      // TODO: Add tier-based stats
    });

    return res.status(200).json({
      ok: true,
      stats: stats
    });

  } catch (error) {
    console.error('Error getting monster core stats:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Check-in Function - Direct Google Sheets API
exports.checkIn = onRequest(async (req, res) => {
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
    const { idToken, characterNumber, attendingAs, buildAdjustment, apAdjustment, timestamp } = req.body;

    if (!idToken) {
      return res.status(401).json({ ok: false, error: 'Missing idToken' });
    }

    // Verify Firebase token
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const email = decodedToken.email;

    if (!email) {
      return res.status(401).json({ ok: false, error: 'Email not verified' });
    }

    // Validate required fields
    if (!characterNumber) {
      return res.status(400).json({ ok: false, error: 'Missing characterNumber' });
    }
    if (!attendingAs) {
      return res.status(400).json({ ok: false, error: 'Missing attendingAs' });
    }
    if (typeof buildAdjustment !== 'number') {
      return res.status(400).json({ ok: false, error: 'Missing or invalid buildAdjustment' });
    }
    if (typeof apAdjustment !== 'number') {
      return res.status(400).json({ ok: false, error: 'Missing or invalid apAdjustment' });
    }

    // Initialize Google Sheets API
    const auth = new googleapis.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      keyFile: './service-account-key.json' // You'll need to add this file
    });

    const sheets = googleapis.sheets({ version: 'v4', auth });
    const client = await auth.getClient();

    // Prepare the row data
    const rowData = [
      email,                                    // checkInUserEmail
      timestamp || new Date().toISOString(),    // Timestamp
      characterNumber,                          // characterNumber
      attendingAs,                              // attendingAs
      buildAdjustment,                          // Build Adj
      apAdjustment                              // AP Adj
    ];

    // Append the row to the Google Sheet
    const response = await sheets.spreadsheets.values.append({
      spreadsheetId: config.google_sheets.checkin_spreadsheet_id,
      range: `${config.google_sheets.checkin_sheet_name}!A:F`,
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
      resource: {
        values: [rowData]
      }
    });

    console.log('Check-in data written to Google Sheets:', response.data);

    res.status(200).json({
      ok: true,
      email,
      checkInData: {
        characterNumber,
        attendingAs,
        buildAdjustment,
        apAdjustment
      },
      sheetsResponse: response.data
    });

  } catch (error) {
    console.error('Error writing to Google Sheets:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Add Entry to Google Sheet
exports.addToGoogleSheet = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { spreadsheetId, sheetName, data } = req.body;

    // Validate required fields
    if (!spreadsheetId || !sheetName || !data) {
      return res.status(400).json({ ok: false, error: 'Spreadsheet ID, sheet name, and data are required' });
    }

    // For this example, we'll use a simpler approach with Google Apps Script
    // You can also set up Google Sheets API with service account credentials
    
    // Example: Call a Google Apps Script web app
    const scriptUrl = config.google_sheets.apps_script_url;
    
    const scriptResponse = await axios.post(scriptUrl, {
      action: 'appendRow',
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      data: data,
      timestamp: new Date().toISOString(),
      userId: uid
    });

    return res.status(200).json({
      ok: true,
      message: 'Data added successfully',
      data: scriptResponse.data
    });

  } catch (error) {
    console.error('Error adding to Google Sheet:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get Monster Core by ID
exports.getMonsterCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { coreId } = req.query;

    // Validate required fields
    if (!coreId) {
      return res.status(400).json({ ok: false, error: 'Core ID is required' });
    }

    // Get the monster core from Firestore
    const coreDoc = await db.collection('monster_cores').doc(coreId).get();

    if (!coreDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Monster core not found' });
    }

    const coreData = coreDoc.data();

    return res.status(200).json({
      ok: true,
      core: {
        id: coreDoc.id,
        ...coreData
      }
    });

  } catch (error) {
    console.error('Error getting monster core:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Clear all monster cores
exports.clearMonsterCores = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    console.log('🗑️ Clearing all monster cores from database...');
    
    const snapshot = await db.collection('monster_cores').get();
    
    if (snapshot.empty) {
      console.log('✅ No monster cores found in database');
      return res.status(200).json({
        ok: true,
        message: 'No monster cores found in database',
        deletedCount: 0
      });
    }
    
    const batch = db.batch();
    let count = 0;
    
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
      count++;
    });
    
    await batch.commit();
    console.log(`✅ Deleted ${count} monster cores from database`);

    return res.status(200).json({
      ok: true,
      message: `Successfully deleted ${count} monster cores from database`,
      deletedCount: count
    });

  } catch (error) {
    console.error('Error clearing monster cores:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Reactivate Monster Core
exports.reactivateMonsterCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { coreId } = req.body;

    // Validate required fields
    if (!coreId) {
      return res.status(400).json({ ok: false, error: 'Core ID is required' });
    }

    console.log(`🔄 Reactivating monster core: ${coreId}`);

    // Check if core exists in database
    const coreDoc = await db.collection('monster_cores').doc(coreId).get();
    
    if (!coreDoc.exists) {
      // Core doesn't exist, create it from scratch with defaults
      console.log(`➕ Core ${coreId} not found, creating new entry`);
      
      const currentTimestamp = Date.now();
      const defaultCoreData = {
        game: 'Crucible',
        timestamp: currentTimestamp,
        verificationHash: 'reactivated', // Mark as reactivated
        label: 'Monster Core',
        tier: 1, // Default tier
        uniqueNumber: parseInt(coreId),
        isActive: true,
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reactivatedBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection('monster_cores').doc(coreId).set(defaultCoreData);
      
      // Record the reactivation in audit trail
      const reactivationRecord = {
        coreId: coreId,
        reactivatedBy: uid,
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'created_and_activated',
        previousState: 'not_found',
        userEmail: decodedToken.email || 'unknown',
        timestamp: Date.now()
      };
      
      await db.collection('monster_core_reactivations').add(reactivationRecord);
      
      console.log(`✅ Created and activated new monster core: ${coreId}`);
      
      return res.status(200).json({
        ok: true,
        message: 'Monster core created and activated successfully',
        core: {
          id: coreId,
          ...defaultCoreData,
          reactivatedAt: new Date().toISOString(),
          createdAt: new Date().toISOString()
        }
      });
    } else {
      // Core exists, check current status
      const coreData = coreDoc.data();
      
      if (coreData.isActive) {
        console.log(`⚠️ Core ${coreId} is already active`);
        
        // Record the attempted reactivation in audit trail
        const attemptRecord = {
          coreId: coreId,
          attemptedBy: uid,
          attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
          action: 'attempted_reactivation',
          previousState: 'already_active',
          userEmail: decodedToken.email || 'unknown',
          timestamp: Date.now(),
          result: 'failed_already_active'
        };
        
        await db.collection('monster_core_reactivations').add(attemptRecord);
        
        return res.status(400).json({ 
          ok: false, 
          error: 'Core is already active',
          core: {
            id: coreId,
            ...coreData
          }
        });
      }

      // Reactivate the core by resetting it to defaults
      const updateData = {
        isActive: true,
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reactivatedBy: uid,
        // Clear consumption data
        consumedBy: admin.firestore.FieldValue.delete(),
        consumedAt: admin.firestore.FieldValue.delete(),
        consumptionType: admin.firestore.FieldValue.delete(),
      };

      await db.collection('monster_cores').doc(coreId).update(updateData);
      
      // Record the reactivation in audit trail
      const reactivationRecord = {
        coreId: coreId,
        reactivatedBy: uid,
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'reactivated',
        previousState: 'inactive',
        userEmail: decodedToken.email || 'unknown',
        timestamp: Date.now(),
        previousConsumptionData: {
          consumedBy: coreData.consumedBy || null,
          consumedAt: coreData.consumedAt || null,
          consumptionType: coreData.consumptionType || null
        }
      };
      
      await db.collection('monster_core_reactivations').add(reactivationRecord);
      
      console.log(`✅ Reactivated monster core: ${coreId}`);

      return res.status(200).json({
        ok: true,
        message: 'Monster core reactivated successfully',
        core: {
          id: coreId,
          ...coreData,
          ...updateData,
          reactivatedAt: new Date().toISOString()
        }
      });
    }

  } catch (error) {
    console.error('Error reactivating monster core:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get Monster Core Reactivation History
exports.getMonsterCoreReactivationHistory = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { coreId, limit = 50, offset = 0 } = req.query;

    console.log(`📋 Getting reactivation history. CoreId: ${coreId || 'all'}, Limit: ${limit}, Offset: ${offset}`);

    let query = db.collection('monster_core_reactivations')
      .orderBy('timestamp', 'desc');

    // Filter by specific core if requested
    if (coreId) {
      query = query.where('coreId', '==', coreId);
    }

    // Apply pagination
    query = query.limit(parseInt(limit)).offset(parseInt(offset));

    const snapshot = await query.get();
    
    const reactivations = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      reactivations.push({
        id: doc.id,
        ...data,
        reactivatedAt: data.reactivatedAt?.toDate()?.toISOString() || null,
        attemptedAt: data.attemptedAt?.toDate()?.toISOString() || null,
      });
    });

    console.log(`✅ Retrieved ${reactivations.length} reactivation records`);

    return res.status(200).json({
      ok: true,
      reactivations: reactivations,
      count: reactivations.length,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset)
      }
    });

  } catch (error) {
    console.error('Error getting reactivation history:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Function to trade a monster core between players (tier-based)
exports.tradeMonsterCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const fromUid = decodedToken.uid;
    const { tier, fromCharacterNumber, toPlayerUid, toCharacterNumber } = req.body;

    if (!tier || !fromCharacterNumber || !toPlayerUid || !toCharacterNumber) {
      return res.status(400).json({ ok: false, error: 'Tier, from character, to player, and to character are required' });
    }

    // Prevent trading with yourself
    if (fromUid === toPlayerUid) {
      return res.status(400).json({ ok: false, error: 'You cannot trade cores with yourself' });
    }

    console.log(`🔄 Trading ${tier} core from ${fromUid}:${fromCharacterNumber} to ${toPlayerUid}:${toCharacterNumber}`);

    // Generate a unique trade ID for tracking
    const tradeId = `${fromUid}_${toPlayerUid}_${Date.now()}`;

    // TRACKING: Record the trade attempt BEFORE actually trading
    const tradeTrackingRef = db.collection('monster_core_trading').doc(tradeId);
    await tradeTrackingRef.set({
      tradeId: tradeId,
      tier: tier,
      fromUid: fromUid,
      fromCharacterNumber: fromCharacterNumber,
      toPlayerUid: toPlayerUid,
      toCharacterNumber: toCharacterNumber,
      tradeAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'attempting'
    });

    // Get the core tier for collection naming
    const collectionName = `core${tier}`;

    // Remove core from source character
    const sourceItemRef = db.collection('players').doc(fromUid).collection('characters').doc(fromCharacterNumber).collection('items').doc(collectionName);
    const sourceItemDoc = await sourceItemRef.get();

    if (!sourceItemDoc.exists) {
      // TRACKING: Update trade tracking to failed
      await tradeTrackingRef.update({
        status: 'failed',
        error: 'Source character does not have this core type',
        failedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return res.status(404).json({ ok: false, error: 'Source character does not have this core type' });
    }

    const sourceItemData = sourceItemDoc.data();
    const newSourceCount = (sourceItemData.count || 1) - 1;

    if (newSourceCount < 0) {
      // TRACKING: Update trade tracking to failed
      await tradeTrackingRef.update({
        status: 'failed',
        error: 'Source character does not have enough cores',
        failedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return res.status(400).json({ ok: false, error: 'Source character does not have enough cores' });
    }

    // Update source character inventory
    if (newSourceCount === 0) {
      await sourceItemRef.delete();
    } else {
      await sourceItemRef.update({
        count: newSourceCount,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    // Add core to target character
    const targetItemRef = db.collection('players').doc(toPlayerUid).collection('characters').doc(toCharacterNumber).collection('items').doc(collectionName);
    const targetItemDoc = await targetItemRef.get();

    let newTargetCount;
    if (targetItemDoc.exists) {
      // Target has this core type, increment count
      const targetItemData = targetItemDoc.data();
      newTargetCount = (targetItemData.count || 0) + 1;
      
      await targetItemRef.update({
        count: newTargetCount,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
    } else {
      // Target doesn't have this core type, create it
      newTargetCount = 1;
      await targetItemRef.set({
        count: newTargetCount,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    // TRACKING: Update trade tracking to success
    await tradeTrackingRef.update({
      status: 'success',
      tradedAt: admin.firestore.FieldValue.serverTimestamp(),
      sourceCountAfter: newSourceCount,
      targetCountAfter: newTargetCount
    });

    console.log(`✅ ${tier} core traded successfully from ${fromUid}:${fromCharacterNumber} to ${toPlayerUid}:${toCharacterNumber}`);

    return res.status(200).json({
      ok: true,
      message: 'Core traded successfully',
      tier: tier,
      fromCharacter: fromCharacterNumber,
      toPlayer: toPlayerUid,
      toCharacter: toCharacterNumber,
      sourceCountAfter: newSourceCount,
      targetCountAfter: newTargetCount
    });

  } catch (error) {
    console.error('Error trading monster core:', error);
    
    // TRACKING: Update trade tracking to failed if we have a tracking ref
    if (typeof tradeTrackingRef !== 'undefined') {
      try {
        await tradeTrackingRef.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (trackingError) {
        console.error('Error updating trade tracking:', trackingError);
      }
    }
    
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Store Monster Core in Character Inventory
exports.storeMonsterCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const { coreId, characterNumber } = req.body;

    if (!coreId || !characterNumber) {
      return res.status(400).json({ ok: false, error: 'Core ID and character number are required' });
    }

    console.log(`💎 Storing monster core ${coreId} for user ${uid} in character ${characterNumber}`);

    // First, check if the core exists and is active
    const coreRef = db.collection('monster_cores').doc(coreId.toString());
    const coreDoc = await coreRef.get();

    if (!coreDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Core not found' });
    }

    const coreData = coreDoc.data();
    if (!coreData.isActive) {
      return res.status(400).json({ ok: false, error: 'Core is already inactive' });
    }

    // Deactivate the core
    await coreRef.update({
      isActive: false,
      storedAt: admin.firestore.FieldValue.serverTimestamp(),
      storedBy: uid,
      storedInCharacter: characterNumber
    });

    console.log(`✅ Core ${coreId} deactivated`);

    // Get the core tier for collection naming
    const coreTier = coreData.tier || 'Iron';
    const collectionName = `core${coreTier}`;
    
    // TRACKING: Record the storage attempt BEFORE actually storing
    const storageTrackingRef = db.collection('monster_core_storing').doc(coreId.toString());
    await storageTrackingRef.set({
      coreId: coreId,
      tier: coreTier,
      storedBy: uid,
      storedInCharacter: characterNumber,
      storageAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'attempting',
      originalCoreData: {
        game: coreData.game,
        timestamp: coreData.timestamp,
        verificationHash: coreData.verificationHash,
        label: coreData.label,
        uniqueNumber: coreData.uniqueNumber
      }
    });
    
    // Check if the item already exists in the user's inventory
    const itemRef = db.collection('players').doc(uid).collection('characters').doc(characterNumber).collection('items').doc(collectionName);
    const itemDoc = await itemRef.get();

    if (itemDoc.exists) {
      // Item exists, increment the count
      const currentData = itemDoc.data();
      const newCount = (currentData.count || 0) + 1;
      
      await itemRef.update({
        count: newCount,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`📦 Updated existing ${collectionName} item, new count: ${newCount}`);

      // TRACKING: Update storage tracking to success
      await storageTrackingRef.update({
        status: 'success',
        storedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'updated',
        newCount: newCount
      });

      // Track the storage in the root collection
      await db.collection('monster_core_storage').doc(coreId.toString()).set({
        coreId: coreId,
        tier: coreTier,
        storedBy: uid,
        storedInCharacter: characterNumber,
        storedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'updated',
        newCount: newCount
      });

      return res.status(200).json({
        ok: true,
        message: 'Core stored successfully',
        action: 'updated',
        newCount: newCount,
        coreId: coreId,
        characterNumber: characterNumber,
        tier: coreTier
      });

    } else {
      // Item doesn't exist, create it
      const newItemData = {
        count: 1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      };

      await itemRef.set(newItemData);

      console.log(`🆕 Created new ${collectionName} item with count: 1`);

      // TRACKING: Update storage tracking to success
      await storageTrackingRef.update({
        status: 'success',
        storedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'created',
        newCount: 1
      });

      // Track the storage in the root collection
      await db.collection('monster_core_storage').doc(coreId.toString()).set({
        coreId: coreId,
        tier: coreTier,
        storedBy: uid,
        storedInCharacter: characterNumber,
        storedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: 'created',
        newCount: 1
      });

      return res.status(200).json({
        ok: true,
        message: 'Core stored successfully',
        action: 'created',
        newCount: 1,
        coreId: coreId,
        characterNumber: characterNumber,
        tier: coreTier
      });
    }

  } catch (error) {
    console.error('Error storing monster core:', error);
    
    // TRACKING: Update storage tracking to failed if we have a tracking ref
    if (typeof storageTrackingRef !== 'undefined') {
      try {
        await storageTrackingRef.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (trackingError) {
        console.error('Error updating storage tracking:', trackingError);
      }
    }
    
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Get Stored Cores for Character
exports.getStoredCores = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { characterId } = req.query;

    // Validate required fields
    if (!characterId) {
      return res.status(400).json({ ok: false, error: 'Character ID is required' });
    }

    console.log(`📋 Getting stored cores for character ${characterId}`);

    // Extract character number from characterId (format: "uid_characterNumber")
    const characterNumber = characterId.split('_')[1] || 'main';
    
    // Check if character exists and belongs to user
    console.log(`🔍 Checking character exists...`);

    // Check if character exists and belongs to user using new structure
    const characterDoc = await db.collection('players').doc(uid).collection('characters').doc(characterNumber).get();
    if (!characterDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Character not found' });
    }

    const characterData = characterDoc.data();
    if (characterData.playerUid !== uid) {
      return res.status(403).json({ ok: false, error: 'Character does not belong to user' });
    }

    // Get all stored cores for this character from the new tier-based collections
    const storedCores = [];
    const tierCollections = ['coreIron', 'coreSilver', 'coreGold', 'coreJade', 'coreSaint', 'coreSovereign'];
    
    for (const collectionName of tierCollections) {
      try {
        const itemDoc = await db.collection('players')
          .doc(uid)
          .collection('characters')
          .doc(characterNumber)
          .collection('items')
          .doc(collectionName)
          .get();
        
        if (itemDoc.exists) {
          const data = itemDoc.data();
          const count = data.count || 0;
          
          if (count > 0) {
            // Extract tier name from collection name (e.g., "coreIron" -> "Iron")
            const tierName = collectionName.replace('core', '');
            
            // Create virtual core entries for display
            for (let i = 0; i < count; i++) {
              storedCores.push({
                id: `${collectionName}_${i}`,
                tier: tierName,
                count: count,
                storedAt: data.lastUpdated?.toDate()?.toISOString() || null
              });
            }
          }
        }
      } catch (error) {
        console.log(`⚠️ Error reading ${collectionName}: ${error.message}`);
      }
    }

    // Group cores by tier for the frontend
    const coresByTier = {};
    storedCores.forEach(core => {
      const tier = core.tier || 'Unknown';
      if (!coresByTier[tier]) {
        coresByTier[tier] = [];
      }
      coresByTier[tier].push(core);
    });

    console.log(`✅ Retrieved ${storedCores.length} stored cores for character ${characterId}`);

    return res.status(200).json({
      ok: true,
      storedCores: storedCores,
      coresByTier: coresByTier,
      totalCount: storedCores.length
    });

  } catch (error) {
    console.error('Error getting stored cores:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Use Stored Core (Consume or Slot) - Updated for Tier-Based System
exports.useStoredCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { characterNumber, tier, usageType } = req.body;

    // Validate required fields
    if (!characterNumber || !tier || !usageType) {
      return res.status(400).json({ ok: false, error: 'Character number, tier, and usage type are required' });
    }

    if (!['build', 'affinity'].includes(usageType)) {
      return res.status(400).json({ ok: false, error: 'Usage type must be "build" or "affinity"' });
    }

    console.log(`🎯 Using ${tier} core for ${usageType} on character ${characterNumber}`);

    // Check if character exists and belongs to user
    const characterDoc = await db.collection('players').doc(uid).collection('characters').doc(characterNumber).get();
    if (!characterDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Character not found' });
    }

    const characterData = characterDoc.data();
    if (characterData.playerUid !== uid) {
      return res.status(403).json({ ok: false, error: 'Character does not belong to user' });
    }

    // Check if character has cores of this tier
    const collectionName = `core${tier}`;
    const itemRef = db.collection('players').doc(uid).collection('characters').doc(characterNumber).collection('items').doc(collectionName);
    const itemDoc = await itemRef.get();

    if (!itemDoc.exists) {
      return res.status(404).json({ ok: false, error: `No ${tier} cores found in inventory` });
    }

    const itemData = itemDoc.data();
    const currentCount = itemData.count || 0;

    if (currentCount <= 0) {
      return res.status(400).json({ ok: false, error: `No ${tier} cores available` });
    }

    // TIER VALIDATION: Check if character can use this tier core
    const characterCultivationTier = characterData.cultivationTier || 'Iron';
    const tierOrder = ['Iron', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
    const coreTierIndex = tierOrder.indexOf(tier);
    const characterTierIndex = tierOrder.indexOf(characterCultivationTier);
    
    if (coreTierIndex < characterTierIndex) {
      // Character is higher tier than the core - cannot consume directly
      const requiredCount = Math.pow(10, characterTierIndex - coreTierIndex);
      return res.status(400).json({ 
        ok: false, 
        error: `Cannot consume ${tier} core directly. You need ${requiredCount} ${tier} cores to equal 1 ${characterCultivationTier} core, or use a ${characterCultivationTier} core instead.` 
      });
    }

    // TRACKING: Record the usage attempt BEFORE actually using
    const usageTrackingRef = db.collection('monster_core_usage').doc(`${uid}_${characterNumber}_${tier}_${Date.now()}`);
    await usageTrackingRef.set({
      playerUid: uid,
      characterNumber: characterNumber,
      tier: tier,
      usageType: usageType,
      usageAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'attempting',
      coresAvailableBefore: currentCount
    });

    // Decrease the core count
    const newCount = currentCount - 1;
    
    if (newCount === 0) {
      // Remove the item if count reaches 0
      await itemRef.delete();
    } else {
      // Update the count
      await itemRef.update({
        count: newCount,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    // Record the usage
    const usageData = {
      playerUid: uid,
      characterNumber: characterNumber,
      tier: tier,
      usageType: usageType,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      coresAvailableAfter: newCount
    };

    await db.collection('monster_core_usage').add(usageData);

    // TRACKING: Update usage tracking to success
    await usageTrackingRef.update({
      status: 'success',
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      coresAvailableAfter: newCount
    });

    // If this is a build consumption, write to Google Sheets
    if (usageType === 'build') {
      try {
        // Get user email
        let userEmail = 'Unknown';
        try {
          const userRecord = await getAuth().getUser(uid);
          userEmail = userRecord.email || 'Unknown';
        } catch (error) {
          console.log(`⚠️ Could not get email for user ${uid}: ${error.message}`);
          const userDoc = await db.collection('users').doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            userEmail = userData.email || 'Unknown';
          }
        }

        // Write to Google Sheets
        const auth = new googleapis.auth.GoogleAuth({
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
          keyFile: './service-account-key.json'
        });
        const sheets = googleapis.sheets({ version: 'v4', auth });

        const rowData = [
          userEmail,                                                      // Email
          new Date().toISOString(),                                       // Timestamp
          tier,                                                           // Core Tier
          'TBD'                                                           // Event (placeholder for now)
        ];

        const sheetsResponse = await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.consume_cores_spreadsheet_id,
          range: `${config.google_sheets.consume_cores_sheet_name}!A:D`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: {
            values: [rowData]
          }
        });
        console.log('Core consumption data written to Google Sheets:', sheetsResponse.data);
      } catch (sheetsError) {
        console.error('❌ Error writing to Google Sheets:', sheetsError);
        // Don't fail the request if Google Sheets write fails
      }
    }

    // If this is an affinity slotting, write to Google Sheets
    if (usageType === 'affinity') {
      try {
        // Get user email
        let userEmail = 'Unknown';
        try {
          const userRecord = await getAuth().getUser(uid);
          userEmail = userRecord.email || 'Unknown';
        } catch (error) {
          console.log(`⚠️ Could not get email for user ${uid}: ${error.message}`);
          const userDoc = await db.collection('users').doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            userEmail = userData.email || 'Unknown';
          }
        }

        // Calculate tier conversion for Google Sheets
        // The sheet should show the effective tier value, not the raw core tier
        let effectiveTier = tier;
        let perfectCultivation = 0;
        
        // Get character's cultivation tier for conversion calculation
        const characterCultivationTier = characterData.cultivationTier || 'Iron';
        
        // If character is higher tier than the core, calculate conversion
        if (characterCultivationTier !== tier) {
          const tierOrder = ['Iron', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
          const coreTierIndex = tierOrder.indexOf(tier);
          const characterTierIndex = tierOrder.indexOf(characterCultivationTier);
          
          if (characterTierIndex > coreTierIndex) {
            // Character is higher tier, so core counts as fraction
            const tierDifference = characterTierIndex - coreTierIndex;
            const conversionRate = Math.pow(10, tierDifference);
            perfectCultivation = 1 / conversionRate; // This will be 0.1 for Iron->Silver, 0.01 for Iron->Gold, etc.
            
            // For Google Sheets, we'll show the character's tier as the effective tier
            effectiveTier = characterCultivationTier;
          }
        }

        // Write to Google Sheets
        const auth = new googleapis.auth.GoogleAuth({
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
          keyFile: './service-account-key.json'
        });
        const sheets = googleapis.sheets({ version: 'v4', auth });

        const rowData = [
          userEmail,                                                      // Email
          new Date().toISOString(),                                       // Timestamp
          effectiveTier,                                                  // Effective Tier (character's tier for conversion)
          perfectCultivation,                                             // Perfect Cultivation (fractional value)
          'TBD'                                                           // Event (placeholder)
        ];

        const sheetsResponse = await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.slot_cores_spreadsheet_id,
          range: `${config.google_sheets.slot_cores_sheet_name}!A:E`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: {
            values: [rowData]
          }
        });
        console.log('Core slotting data written to Google Sheets:', sheetsResponse.data);
      } catch (sheetsError) {
        console.error('❌ Error writing to Google Sheets:', sheetsError);
        // Don't fail the request if Google Sheets write fails
      }
    }

    console.log(`✅ Successfully used ${tier} core for ${usageType} on character ${characterNumber}`);

    return res.status(200).json({
      ok: true,
      message: `${tier} core used successfully for ${usageType}`,
      tier: tier,
      usageType: usageType,
      characterNumber: characterNumber,
      coresAvailableAfter: newCount
    });

  } catch (error) {
    console.error('Error using stored core:', error);
    
    // TRACKING: Update usage tracking to failed if we have a tracking ref
    if (typeof usageTrackingRef !== 'undefined') {
      try {
        await usageTrackingRef.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (trackingError) {
        console.error('Error updating usage tracking:', trackingError);
      }
    }
    
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Trade Stored Core to Another User
exports.tradeStoredCore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { fromCharacterId, toPlayerUid, toCharacterId, coreId } = req.body;

    // Validate required fields
    if (!fromCharacterId || !toPlayerUid || !toCharacterId || !coreId) {
      return res.status(400).json({ ok: false, error: 'From Character ID, To Player UID, To Character ID, and Core ID are required' });
    }

    console.log(`🔄 Trading core ${coreId} from character ${fromCharacterId} to character ${toCharacterId}`);

    // Extract character numbers from characterIds (format: "uid_characterNumber")
    const fromCharacterNumber = fromCharacterId.split('_')[1] || 'main';
    const toCharacterNumber = toCharacterId.split('_')[1] || 'main';
    
    // Ensure character structure exists for both characters before trading
    console.log(`🔧 Ensuring character structure exists...`);
    try {
      await ensureCharacterStructure(uid, fromCharacterNumber);
      await ensureCharacterStructure(toPlayerUid, toCharacterNumber);
      console.log(`✅ Character structure ensured for both characters`);
    } catch (structureError) {
      console.error('❌ Failed to ensure character structure:', structureError);
      return res.status(500).json({ 
        ok: false, 
        error: 'Failed to set up character storage structure' 
      });
    }

    // Check if source character exists and belongs to user using new structure
    const fromCharacterDoc = await db.collection('players').doc(uid).collection('characters').doc(fromCharacterNumber).get();
    if (!fromCharacterDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Source character not found' });
    }

    const fromCharacterData = fromCharacterDoc.data();
    if (fromCharacterData.playerUid !== uid) {
      return res.status(403).json({ ok: false, error: 'Source character does not belong to user' });
    }

    // Check if target character exists using new structure
    const toCharacterDoc = await db.collection('players').doc(toPlayerUid).collection('characters').doc(toCharacterNumber).get();
    if (!toCharacterDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Target character not found' });
    }

    const toCharacterData = toCharacterDoc.data();
    if (toCharacterData.playerUid !== toPlayerUid) {
      return res.status(400).json({ ok: false, error: 'Target character does not belong to specified player' });
    }

    // Check if core is stored for source character (search all tier collections)
    let storedCoreDoc = null;
    let storedCoreData = null;
    const tiers = ['Iron', 'Copper', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
    
    for (const tier of tiers) {
      const doc = await db.collection('players')
        .doc(uid)
        .collection('characters')
        .doc(fromCharacterNumber)
        .collection('items')
        .collection('cores')
        .collection(tier)
        .doc(coreId)
        .get();
      
      if (doc.exists) {
        storedCoreDoc = doc;
        storedCoreData = doc.data();
        break;
      }
    }

    if (!storedCoreDoc) {
      return res.status(404).json({ ok: false, error: 'Stored core not found' });
    }

    // Use batch to ensure atomic transaction
    const batch = db.batch();

    // Remove core from source character (find which tier it's in)
    let fromCoreRef = null;
    for (const tier of tiers) {
      const ref = db.collection('players')
        .doc(uid)
        .collection('characters')
        .doc(fromCharacterNumber)
        .collection('items')
        .collection('cores')
        .collection(tier)
        .doc(coreId);
      
      const doc = await ref.get();
      if (doc.exists) {
        fromCoreRef = ref;
        break;
      }
    }
    
    if (!fromCoreRef) {
      return res.status(404).json({ ok: false, error: 'Source core not found for deletion' });
    }
    
    batch.delete(fromCoreRef);

    // Add core to target character under the appropriate tier
    const tier = storedCoreData.tier || 'Iron';
    const toCoreRef = db.collection('players')
      .doc(toPlayerUid)
      .collection('characters')
      .doc(toCharacterNumber)
      .collection('items')
      .collection('cores')
      .collection(tier)
      .doc(coreId);
    
    const tradedCoreData = {
      ...storedCoreData,
      tradedAt: admin.firestore.FieldValue.serverTimestamp(),
      tradedFrom: fromCharacterId,
      tradedTo: toCharacterId,
      tradedFromPlayer: uid,
      tradedToPlayer: toPlayerUid
    };
    
    batch.set(toCoreRef, tradedCoreData);

    // Record the trade
    const tradeRecordRef = db.collection('core_trades').doc();
    const tradeRecord = {
      coreId: coreId,
      fromCharacterId: fromCharacterId,
      toCharacterId: toCharacterId,
      fromPlayerUid: uid,
      toPlayerUid: toPlayerUid,
      tradedAt: admin.firestore.FieldValue.serverTimestamp(),
      coreData: storedCoreData
    };
    batch.set(tradeRecordRef, tradeRecord);

    // Commit the batch
    await batch.commit();

    console.log(`✅ Traded core ${coreId} from character ${fromCharacterId} to character ${toCharacterId}`);

    return res.status(200).json({
      ok: true,
      message: 'Core traded successfully',
      trade: {
        ...tradeRecord,
        tradedAt: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error('Error trading stored core:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Function to get current user's characters
exports.getCharacters = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Get user's characters from new structure: players/{uid}/characters
    console.log(`🔍 Looking for characters for user ${uid} in new structure...`);
    
    const playerRef = db.collection('players').doc(uid);
    const playerDoc = await playerRef.get();
    
    if (!playerDoc.exists) {
      console.log(`❌ Player document not found for user ${uid}`);
      return res.status(200).json({
        ok: true,
        characters: [],
        debug: {
          searchedForUid: uid,
          playerExists: false,
          message: 'Player document not found'
        }
      });
    }
    
    const charactersRef = playerRef.collection('characters');
    const charactersSnapshot = await charactersRef.get();
    
    if (charactersSnapshot.empty) {
      console.log(`❌ No characters found for user ${uid}`);
      return res.status(200).json({
        ok: true,
        characters: [],
        debug: {
          searchedForUid: uid,
          playerExists: true,
          charactersCount: 0,
          message: 'No characters found in player document'
        }
      });
    }

    const characters = [];
    charactersSnapshot.forEach(doc => {
      const data = doc.data();
      // Create character ID in the format expected by the frontend: {uid}_{characterNumber}
      const characterId = `${uid}_${doc.id}`;
      characters.push({
        id: characterId, // This is the format the frontend expects
        characterNumber: doc.id, // The actual character number from the document ID
        playerName: data.playerName || 'Unknown',
        characterName: data.characterName || 'Unknown',
        race: data.race || 'Unknown',
        cultivationTier: data.cultivationTier || 'Unknown'
      });
    });

    console.log(`📋 Found ${characters.length} characters for user ${uid}`);

    return res.status(200).json({
      ok: true,
      characters: characters,
      debug: {
        searchedForUid: uid,
        playerExists: true,
        charactersCount: characters.length,
        message: 'Characters retrieved successfully'
      }
    });

  } catch (error) {
    console.error('Error in getCharacters:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Function to get a player's characters for trading
exports.getPlayerCharacters = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const currentUserUid = decodedToken.uid;

    // Parse request body
    const { targetPlayerEmail, targetPlayerUid } = req.body;

    if (!targetPlayerEmail && !targetPlayerUid) {
      return res.status(400).json({ ok: false, error: 'Either targetPlayerEmail or targetPlayerUid must be provided' });
    }

    let targetUid = targetPlayerUid;

    // If email is provided, find the user by email
    if (targetPlayerEmail && !targetUid) {
      try {
        const userRecord = await getAuth().getUser(targetPlayerEmail);
        targetUid = userRecord.uid;
      } catch (error) {
        console.log('User not found by email:', targetPlayerEmail);
        
        // Try to find by email field instead of auth record
        const usersQuery = await db.collection('users')
          .where('email', '==', targetPlayerEmail)
          .limit(1)
          .get();
        
        if (usersQuery.empty) {
          return res.status(404).json({ ok: false, error: 'Player not found' });
        }
        
        targetUid = usersQuery.docs[0].id;
      }
    }

    // Prevent trading with yourself
    if (targetUid === currentUserUid) {
      return res.status(400).json({ ok: false, error: 'Cannot trade with yourself' });
    }

    // Get target player's characters
    const charactersQuery = await db.collection('characters')
      .where('playerUid', '==', targetUid)
      .get();

    if (charactersQuery.empty) {
      return res.status(404).json({ ok: false, error: 'Target player has no characters' });
    }

    const characters = [];
    charactersQuery.forEach(doc => {
      const data = doc.data();
      characters.push({
        id: doc.id,
        playerName: data.playerName,
        playerNumber: data.playerNumber,
        race: data.race
      });
    });

    console.log(`📋 Found ${characters.length} characters for player ${targetUid}`);

    return res.status(200).json({
      ok: true,
      characters: characters,
      playerUid: targetUid
    });

  } catch (error) {
    console.error('Error in getPlayerCharacters:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Function to ensure character structure exists in Firestore
async function ensureCharacterStructure(uid, characterNumber = 'main') {
  const playerRef = db.collection('players').doc(uid);
  const charactersRef = playerRef.collection('characters');
  const characterRef = charactersRef.doc(characterNumber);
  
  try {
    // Check if player document exists, create if missing
    const playerDoc = await playerRef.get();
    if (!playerDoc.exists) {
      console.log(`👤 Creating player document for user ${uid}`);
      await playerRef.set({
        uid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
    }
    
    // Check if character document exists
    const characterDoc = await characterRef.get();
    
    if (!characterDoc.exists) {
      console.log(`📋 Creating character document ${characterNumber} for player ${uid}`);
      
      // Try to get character data from Firebase Storage first
      console.log(`🔍 Attempting to read character data from Firebase Storage...`);
      try {
        // Get user email from Firestore auth
        console.log(`🔍 Getting user email from auth...`);
        const userRecord = await getAuth().getUser(uid);
        const userEmail = userRecord.email;
        console.log(`🔍 User email: ${userEmail}`);
        
        if (userEmail) {
          console.log(`🔍 Attempting to read from Storage: users/${userEmail}/pc.json`);
          const bucket = getStorage().bucket();
          const file = bucket.file(`users/${userEmail}/pc.json`);
          
          const [exists] = await file.exists();
          console.log(`🔍 File exists in Storage: ${exists}`);
          
          if (exists) {
            console.log(`🔍 Downloading file content...`);
            const [fileContent] = await file.download();
            const characterData = JSON.parse(fileContent.toString());
            console.log(`🔍 Parsed character data: ${JSON.stringify(characterData).substring(0, 200)}...`);
            
            // Add metadata
            characterData.playerUid = uid;
            characterData.characterNumber = characterNumber;
            characterData.syncedAt = admin.firestore.FieldValue.serverTimestamp();
            
            // Create character document
            console.log(`🔍 Creating character document with Storage data...`);
            await characterRef.set(characterData);
            console.log(`✅ Created character from Storage data: ${characterNumber}`);
          } else {
            console.log(`🔍 No Storage file found, creating minimal character...`);
            // Create minimal character document if no Storage data
            await characterRef.set({
              playerUid: uid,
              characterNumber: characterNumber,
              playerName: `Character ${characterNumber}`,
              playerNumber: '1', // Default player number
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              syncedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`✅ Created minimal character document: ${characterNumber}`);
          }
        } else {
          console.log(`🔍 No user email found, creating minimal character...`);
          // Create minimal character document if no email found
          await characterRef.set({
            playerUid: uid,
            characterNumber: characterNumber,
            playerName: `Character ${characterNumber}`,
            playerNumber: '1', // Default player number
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            syncedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        console.log(`✅ Created minimal character document: ${characterNumber}`);
      }
    } catch (storageError) {
        console.log(`⚠️ Could not read from Storage, creating minimal character: ${storageError.message}`);
        console.log(`⚠️ Storage error details:`, storageError);
        // Create minimal character document
        await characterRef.set({
          playerUid: uid,
          characterNumber: characterNumber,
          playerName: `Character ${characterNumber}`,
          playerNumber: '1', // Default player number
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          syncedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`✅ Created minimal character document: ${characterNumber}`);
      }
    }
    
    // If character exists, ensure it has the latest profile data
    if (characterDoc.exists) {
      console.log(`📋 Character ${characterNumber} already exists, ensuring profile data is up to date...`);
      const existingData = characterDoc.data();
      
      // Update with current profile information if missing
      const updates = {};
      if (!existingData.playerUid || existingData.playerUid !== uid) {
        updates.playerUid = uid;
      }
      if (!existingData.playerNumber) {
        updates.playerNumber = '1'; // Default player number
      }
      if (!existingData.lastUpdated) {
        updates.lastUpdated = admin.firestore.FieldValue.serverTimestamp();
      }
      
      if (Object.keys(updates).length > 0) {
        console.log(`📝 Updating character ${characterNumber} with profile data:`, updates);
        await characterRef.update(updates);
        console.log(`✅ Character ${characterNumber} updated with profile data`);
      } else {
        console.log(`✅ Character ${characterNumber} already has up-to-date profile data`);
      }
    }
    
    // Ensure items subcollection exists
    console.log(`📦 Ensuring items subcollection exists...`);
    
    // Create itemsRef at function scope so it can be used in cores section
    const itemsRef = charactersRef.doc(characterNumber).collection('items');
    
    try {
      console.log(`🔍 Debug: About to create itemsRef...`);
      console.log(`🔍 Debug: characterRef type: ${typeof characterRef}`);
      console.log(`🔍 Debug: characterRef has collection method: ${typeof characterRef.collection}`);
      console.log(`🔍 Debug: characterRef has doc method: ${typeof characterRef.doc}`);
      console.log(`🔍 Debug: characterRef constructor: ${characterRef.constructor.name}`);
      console.log(`🔍 Debug: characterRef path: ${characterRef.path || 'no path'}`);
      console.log(`🔍 Debug: charactersRef type: ${typeof charactersRef}`);
      console.log(`🔍 Debug: charactersRef has collection method: ${typeof charactersRef.collection}`);
      console.log(`🔍 Debug: charactersRef has doc method: ${typeof charactersRef.doc}`);
      
      console.log(`🔍 Debug: itemsRef created successfully: ${typeof itemsRef}`);
      console.log(`🔍 Debug: itemsRef has collection method: ${typeof itemsRef.collection}`);
      console.log(`🔍 Debug: itemsRef has doc method: ${typeof itemsRef.doc}`);
      console.log(`🔍 Debug: itemsRef constructor: ${itemsRef.constructor.name}`);
      console.log(`🔍 Debug: itemsRef path: ${itemsRef.path || 'no path'}`);
      console.log(`🔍 Debug: About to query items metadata document...`);
      const itemsDoc = await itemsRef.doc('metadata').get();
      console.log(`🔍 Debug: items metadata document queried successfully`);
      
      if (!itemsDoc.exists) {
        console.log(`📦 Creating items subcollection for character ${characterNumber}`);
        await itemsRef.doc('metadata').set({
          created: admin.firestore.FieldValue.serverTimestamp(),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`✅ Items subcollection created successfully`);
      } else {
        console.log(`✅ Items subcollection already exists`);
      }
    } catch (itemsError) {
      console.error(`❌ Error creating items subcollection:`, itemsError);
      throw itemsError;
    }
    
    // Ensure cores subcollection exists
    console.log(`💎 Ensuring cores subcollection exists for character ${characterNumber} (v4 - STEP BY STEP)...`);
    try {
      // Use the itemsRef that's now available at function scope
      console.log(`🔍 Debug: Using itemsRef from function scope: ${typeof itemsRef}`);
      console.log(`🔍 Debug: itemsRef has collection method: ${typeof itemsRef.collection}`);
      
      // Use the working itemsRef but ensure it's a proper collection reference
      console.log(`🔍 Debug: Using itemsRef from function scope: ${typeof itemsRef}`);
      console.log(`🔍 Debug: itemsRef has collection method: ${typeof itemsRef.collection}`);
      
      // Try to get the collection method from the prototype
      console.log(`🔍 Debug: itemsRef prototype methods:`, Object.getOwnPropertyNames(Object.getPrototypeOf(itemsRef)));
      
      // Create cores subcollection using the working itemsRef
      const coresRef = itemsRef.collection('cores');
      console.log(`🔍 Debug: coresRef created: ${typeof coresRef}`);
      console.log(`🔍 Debug: About to query cores metadata document...`);
      
      const coresDoc = await coresRef.doc('metadata').get();
      console.log(`🔍 Debug: cores metadata document queried successfully`);
      
      if (!coresDoc.exists) {
        console.log(`💎 Creating cores subcollection for character ${characterNumber}`);
        await coresRef.doc('metadata').set({
          created: admin.firestore.FieldValue.serverTimestamp(),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          totalCores: 0
        });
        console.log(`✅ Cores subcollection created successfully`);
      } else {
        console.log(`✅ Cores subcollection already exists`);
      }
    } catch (coresError) {
      console.error(`❌ Error creating cores subcollection:`, coresError);
      throw coresError;
    }
    
    // Ensure tier-based subcollections exist
    console.log(`🏆 Ensuring tier subcollections exist...`);
    try {
      const tiers = ['Iron', 'Copper', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
      for (const tier of tiers) {
        console.log(`🏆 Checking ${tier} tier subcollection...`);
        const tierRef = coresRef.collection(tier);
        const tierDoc = await tierRef.doc('metadata').get();
        
        if (!tierDoc.exists) {
          console.log(`🏆 Creating ${tier} tier subcollection for character ${characterNumber}`);
          await tierRef.doc('metadata').set({
            created: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            totalCores: 0
          });
          console.log(`✅ ${tier} tier subcollection created successfully`);
        } else {
          console.log(`✅ ${tier} tier subcollection already exists`);
        }
      }
    } catch (tierError) {
      console.error(`❌ Error creating tier subcollections:`, tierError);
      throw tierError;
    }
    
    console.log(`✅ Character structure ensured for player ${uid}, character ${characterNumber}`);
    console.log(`🎯 Final verification - checking all components exist...`);
    
    // Final verification
    const finalPlayerDoc = await playerRef.get();
    const finalCharacterDoc = await characterRef.get();
    const finalItemsDoc = await charactersRef.doc(characterNumber).collection('items').doc('metadata').get();
    const finalCoresDoc = await itemsRef.collection('cores').doc('metadata').get();
    const finalIronDoc = await coresRef.collection('Iron').doc('metadata').get();
    
    console.log(`🎯 Final verification results:`);
    console.log(`  - Player exists: ${finalPlayerDoc.exists}`);
    console.log(`  - Character exists: ${finalCharacterDoc.exists}`);
    console.log(`  - Items exists: ${finalItemsDoc.exists}`);
    console.log(`  - Cores exists: ${finalCoresDoc.exists}`);
    console.log(`  - Iron tier exists: ${finalIronDoc.exists}`);
    
    return characterNumber;
    
  } catch (error) {
    console.error(`❌ Error ensuring character structure for player ${uid}, character ${characterNumber}:`, error);
    throw error;
  }
}

// Function to sync character from Firebase Storage to Firestore
exports.syncCharacterToFirestore = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const userEmail = decodedToken.email;

    console.log(`📋 Syncing character from Storage to Firestore for user ${uid} (${userEmail})`);

    // Get character data from Firebase Storage
    const bucket = getStorage().bucket();
    const file = bucket.file(`users/${userEmail}/pc.json`);
    
    try {
      const [exists] = await file.exists();
      if (!exists) {
        return res.status(404).json({ 
          ok: false, 
          error: 'Character file not found in Firebase Storage' 
        });
      }

      const [fileContent] = await file.download();
      const characterData = JSON.parse(fileContent.toString());
      
      // Add the playerUid to link it to the user
      characterData.playerUid = uid;
      characterData.syncedAt = admin.firestore.FieldValue.serverTimestamp();
      
      // Create a character document in Firestore
      // Use a predictable ID based on user email or character number
      const characterId = `${uid}_${characterData.characterNumber || 'main'}`;
      
      await db.collection('characters').doc(characterId).set(characterData);
      
      console.log(`✅ Synced character ${characterId} to Firestore for user ${uid}`);

      return res.status(200).json({
        ok: true,
        message: 'Character synced to Firestore successfully',
        characterId: characterId,
        characterName: characterData.playerName || 'Unknown'
      });

    } catch (storageError) {
      console.error('Error reading from Firebase Storage:', storageError);
      return res.status(500).json({ 
        ok: false, 
        error: 'Failed to read character data from storage' 
      });
    }

  } catch (error) {
    console.error('Error in syncCharacterToFirestore:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Test function to verify character structure creation
exports.testCharacterStructure = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    console.log(`🧪 Testing character structure creation for user ${uid}`);

    // Test the ensureCharacterStructure function
    const characterNumber = 'main';
    const result = await ensureCharacterStructure(uid, characterNumber);

    // Verify the structure was created
    const playerRef = db.collection('players').doc(uid);
    const playerDoc = await playerRef.get();
    
    const characterRef = playerRef.collection('characters').doc(characterNumber);
    const characterDoc = await characterRef.get();

    const itemsRef = characterRef.collection('items');
    const itemsDoc = await itemsRef.doc('metadata').get();

    const coresRef = itemsRef.collection('cores');
    const coresDoc = await coresRef.doc('metadata').get();

    const ironRef = coresRef.collection('Iron');
    const ironDoc = await ironRef.doc('metadata').get();

    return res.status(200).json({
      ok: true,
      message: 'Character structure test completed',
      result: result,
      verification: {
        playerExists: playerDoc.exists,
        characterExists: characterDoc.exists,
        itemsExists: itemsDoc.exists,
        coresExists: coresDoc.exists,
        ironTierExists: ironDoc.exists
      },
      paths: {
        player: `players/${uid}`,
        character: `players/${uid}/characters/${characterNumber}`,
        items: `players/${uid}/characters/${characterNumber}/items`,
        cores: `players/${uid}/characters/${characterNumber}/items/cores`,
        ironTier: `players/${uid}/characters/${characterNumber}/items/cores/Iron`
      }
    });

  } catch (error) {
    console.error('Error in testCharacterStructure:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error: ' + error.message });
  }
});

// Function to check if a character number exists in the database
exports.checkCharacterExists = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const { characterNumber } = req.body;

    if (!characterNumber) {
      return res.status(400).json({ ok: false, error: 'Character number is required' });
    }

    console.log(`🔍 Checking if character ${characterNumber} exists for user ${uid}`);
    console.log(`🔍 Path being checked: players/${uid}/characters/${characterNumber}`);
    
    try {
      const characterDoc = await db.collection('players').doc(uid).collection('characters').doc(characterNumber).get();
      const characterExists = characterDoc.exists;
      const path = `players/${uid}/characters/${characterNumber}`;
      
      console.log(`🔍 Character ${characterNumber} exists: ${characterExists}`);
      if (characterExists) {
        console.log(`🔍 Document data:`, characterDoc.data());
      }
      
      return res.status(200).json({
        ok: true,
        exists: characterExists,
        path: path,
        message: characterExists ? 'Character found' : 'Character not found'
      });
      
    } catch (checkError) {
      console.error('Error checking character existence:', checkError);
      return res.status(500).json({ 
        ok: false, 
        error: checkError.message,
        exists: false,
        path: `players/${uid}/characters/${characterNumber}`
      });
    }

  } catch (error) {
    console.error('Error in checkCharacterExists:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Function to initialize user structure after login
exports.initializeUserStructure = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const userEmail = decodedToken.email;

    console.log(`🚀 Initializing user structure for ${uid} (${userEmail})`);

    // Check if player document exists
    const playerRef = db.collection('players').doc(uid);
    const playerDoc = await playerRef.get();
    
    let playerCreated = false;
    if (!playerDoc.exists) {
      console.log(`📝 Creating player document for ${uid}`);
      await playerRef.set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        email: userEmail
      });
      playerCreated = true;
      console.log(`✅ Player document created`);
    } else {
      console.log(`✅ Player document already exists`);
    }

    // Try to get character data from Firebase Storage to determine character number
    let characterNumber = 'main'; // Default fallback
    let characterData = null;
    
    if (userEmail) {
      try {
        const storageRef = admin.storage().bucket().file(`users/${userEmail}/pc.json`);
        const [exists] = await storageRef.exists();
        if (exists) {
          const [data] = await storageRef.download();
          const jsonString = data.toString('utf8');
          characterData = JSON.parse(jsonString);
          characterNumber = characterData.characterNumber?.toString() || 'main';
          console.log(`📁 Found character data in Firebase Storage with characterNumber: ${characterNumber}`);
        }
      } catch (storageError) {
        console.log(`⚠️ Could not fetch character data from Firebase Storage: ${storageError.message}`);
      }
    }

    // Check if character document exists
    const characterRef = playerRef.collection('characters').doc(characterNumber);
    const characterDoc = await characterRef.get();
    
    let characterCreated = false;
    if (!characterDoc.exists) {
      console.log(`📝 Creating character document for ${characterNumber}`);
      
      // Create character document with data from Firebase Storage if available
      const characterDocData = {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        playerUid: uid,
        playerName: characterData?.playerName || 'Unknown',
        characterName: characterData?.characterName || 'Unknown',
        characterNumber: characterNumber,
        race: characterData?.race || 'Unknown',
        cultivationTier: characterData?.cultivationTier || 'Unknown'
      };
      
      await characterRef.set(characterDocData);
      characterCreated = true;
      console.log(`✅ Character document created with data:`, characterDocData);
    } else {
      console.log(`✅ Character document already exists`);
    }

    // Create basic items subcollection if it doesn't exist
    const itemsRef = characterRef.collection('items');
    const itemsDoc = await itemsRef.doc('metadata').get();
    
    let itemsCreated = false;
    if (!itemsDoc.exists) {
      console.log(`📦 Creating items subcollection for character ${characterNumber}`);
      await itemsRef.doc('metadata').set({
        created: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
      itemsCreated = true;
      console.log(`✅ Items subcollection created`);
    } else {
      console.log(`✅ Items subcollection already exists`);
    }

    // Create basic cores subcollection if it doesn't exist
    const coresRef = itemsRef.collection('cores');
    const coresDoc = await coresRef.doc('metadata').get();
    
    let coresCreated = false;
    if (!coresDoc.exists) {
      console.log(`💎 Creating cores subcollection for character ${characterNumber}`);
      await coresRef.doc('metadata').set({
        created: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        totalCores: 0
      });
      coresCreated = true;
      console.log(`✅ Cores subcollection created`);
    } else {
      console.log(`✅ Cores subcollection already exists`);
    }

    console.log(`🎯 User structure initialization completed for ${uid}`);

    return res.status(200).json({
      ok: true,
      message: 'User structure initialized successfully',
      playerCreated: playerCreated,
      characterCreated: characterCreated,
      itemsCreated: itemsCreated,
      coresCreated: coresCreated,
      characterNumber: characterNumber,
      path: `players/${uid}/characters/${characterNumber}`,
      summary: {
        player: playerCreated ? 'created' : 'already existed',
        character: characterCreated ? 'created' : 'already existed',
        items: itemsCreated ? 'created' : 'already existed',
        cores: coresCreated ? 'created' : 'already existed'
      }
    });

  } catch (error) {
    console.error('Error in initializeUserStructure:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Temporary function to fix character playerUid field
exports.fixCharacterPlayerUid = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const userEmail = decodedToken.email;

    console.log(`🔧 Fixing character playerUid for user ${uid} (${userEmail})`);

    // Get all characters and find ones that might belong to this user
    const allCharactersQuery = await db.collection('characters').get();
    const updatedCharacters = [];

    for (const doc of allCharactersQuery.docs) {
      const data = doc.data();
      
      // If character doesn't have playerUid or has null/empty playerUid
      if (!data.playerUid) {
        // Update the character to have the current user's UID
        await db.collection('characters').doc(doc.id).update({
          playerUid: uid
        });
        
        updatedCharacters.push({
          id: doc.id,
          playerName: data.playerName,
          characterName: data.characterName
        });
        
        console.log(`✅ Updated character ${doc.id} (${data.playerName}) with playerUid: ${uid}`);
      }
    }

    return res.status(200).json({
      ok: true,
      message: `Updated ${updatedCharacters.length} characters`,
      updatedCharacters: updatedCharacters
    });

  } catch (error) {
    console.error('Error in fixCharacterPlayerUid:', error);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

// Update Monster Core status
exports.updateMonsterCoreStatus = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { coreId, isActive } = req.body;

    // Validate required fields
    if (!coreId || typeof isActive !== 'boolean') {
      return res.status(400).json({ ok: false, error: 'Core ID and active status are required' });
    }

    // Update the core status
    await db.collection('monster_cores').doc(coreId).update({
      isActive: isActive
    });

    return res.status(200).json({
      ok: true,
      message: 'Monster core status updated successfully'
    });

  } catch (error) {
    console.error('Error updating monster core status:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get locations with timezone status
exports.getLocationsWithTimezone = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    // Get all locations
    const locationsSnapshot = await db.collection('locations').get();
    const locations = [];

    for (const doc of locationsSnapshot.docs) {
      const locationData = doc.data();
      locations.push({
        id: doc.id,
        name: locationData.name,
        address: locationData.address,
        timezone: locationData.timezone || null,
        hasTimezone: !!locationData.timezone,
        timezoneUpdatedAt: locationData.timezoneUpdatedAt || null
      });
    }

    // Sort by name
    locations.sort((a, b) => a.name.localeCompare(b.name));

    return res.status(200).json({
      ok: true,
      locations: locations,
      summary: {
        total: locations.length,
        withTimezone: locations.filter(l => l.hasTimezone).length,
        withoutTimezone: locations.filter(l => !l.hasTimezone).length
      }
    });

  } catch (error) {
    console.error('Error getting locations with timezone:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Set timezone for a location
exports.setLocationTimezone = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { locationName, timezone } = req.body;

    // Validate required fields
    if (!locationName || !timezone) {
      return res.status(400).json({ ok: false, error: 'Location name and timezone are required' });
    }

    // Validate timezone
    if (!moment.tz.zone(timezone)) {
      return res.status(400).json({ ok: false, error: `Invalid timezone: ${timezone}` });
    }

    // Find the location by name
    const locationQuery = await db.collection('locations')
      .where('name', '==', locationName)
      .limit(1)
      .get();

    if (locationQuery.empty) {
      return res.status(404).json({ ok: false, error: `Location not found: ${locationName}` });
    }

    const locationDoc = locationQuery.docs[0];
    
    // Update the location with timezone
    await locationDoc.ref.update({
      timezone: timezone,
      timezoneUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).json({
      ok: true,
      message: `Timezone updated for location: ${locationName}`,
      locationId: locationDoc.id,
      timezone: timezone
    });

  } catch (error) {
    console.error('Error setting location timezone:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Check Discord Rate Limit Status
exports.checkDiscordRateLimit = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
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
    // Make a simple API call to check rate limit status
    const response = await axios.get(
      `https://discord.com/api/v10/guilds/1102958641503547394/scheduled-events`,
      {
        headers: {
          Authorization: `Bot ${DISCORD_TOKEN.value()}`,
          "Content-Type": "application/json"
        }
      }
    );

    // Extract rate limit headers
    const rateLimitInfo = {
      remaining: response.headers['x-ratelimit-remaining'],
      limit: response.headers['x-ratelimit-limit'],
      reset: response.headers['x-ratelimit-reset'],
      resetAfter: response.headers['x-ratelimit-reset-after'],
      bucket: response.headers['x-ratelimit-bucket'],
      global: response.headers['x-ratelimit-global'] === 'true'
    };

    // Calculate time until reset
    let resetTime = null;
    if (rateLimitInfo.reset) {
      const resetTimestamp = parseInt(rateLimitInfo.reset) * 1000; // Convert to milliseconds
      resetTime = new Date(resetTimestamp);
    }

    return res.status(200).json({
      ok: true,
      rateLimitInfo: {
        ...rateLimitInfo,
        resetTime: resetTime,
        timeUntilReset: resetTime ? Math.max(0, resetTime.getTime() - Date.now()) : null
      },
      message: `Rate limit status: ${rateLimitInfo.remaining}/${rateLimitInfo.limit} requests remaining`
    });

  } catch (error) {
    if (error.response?.status === 429) {
      // Rate limited
      const retryAfter = error.response.headers['retry-after'];
      const resetAfter = error.response.headers['x-ratelimit-reset-after'];
      
      return res.status(429).json({
        ok: false,
        error: 'rate_limited',
        message: 'Discord API rate limit exceeded',
        retryAfter: retryAfter ? parseInt(retryAfter) : null,
        resetAfter: resetAfter ? parseFloat(resetAfter) : null,
        estimatedWaitTime: retryAfter ? `${retryAfter} seconds` : 'Unknown'
      });
    }

    return res.status(500).json({
      ok: false,
      error: 'api_error',
      message: error.response?.data?.message || error.message
    });
  }
});

// Sync Events to Discord
exports.syncEventsToDiscord = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    // Get all events from Firestore
    const eventsSnapshot = await db.collection('events').get();
    const events = [];
    const results = [];

    console.log(`📊 Found ${eventsSnapshot.docs.length} events in Firestore`);

    for (const doc of eventsSnapshot.docs) {
      const eventData = doc.data();
      events.push({
        id: doc.id,
        ...eventData
      });
    }

    console.log(`📋 Processing ${events.length} events for Discord sync`);

    // Add initial delay to avoid rate limiting
    console.log(`⏳ Adding initial 1 second delay to avoid rate limiting...`);
    await new Promise(resolve => setTimeout(resolve, 1000));
    console.log(`✅ Initial delay completed`);

    // Process each event
    for (let i = 0; i < events.length; i++) {
      const event = events[i];
      console.log(`🔄 Processing event ${i + 1}/${events.length}: ${event.id} - ${event.typeName}`);
      
      // Add a delay between events to avoid rate limiting
      if (i > 0) {
        console.log(`⏳ Adding 3 second delay between events to avoid rate limiting...`);
        await new Promise(resolve => setTimeout(resolve, 3000));
        console.log(`✅ Delay completed, continuing with next event`);
      }
      
      try {
        // Use event data with fallbacks for events without registration
        let eventName = event.typeName;
        let eventDescription = `Location: ${event.locationName}`;
        let coverImage = null;
        
        // If registration is activated, use registration details and update name/description
        if (event.registrationActivated && event.registrationDetails) {
          const details = event.registrationDetails;
          
          // Update event name to include event type in parentheses
          eventName = `${details.eventName || event.typeName} (${event.typeName})`;
          
          // Build comprehensive description with registration details
          let descriptionParts = [`Register in Crucible Helper App.`, `Location: ${event.locationName}`];
          
          if (event.locationAddress) {
            descriptionParts.push(`Address: ${event.locationAddress}`);
          }
          
          if (details.cost !== undefined && details.cost !== null) {
            descriptionParts.push(`Event Cost: $${details.cost}`);
          }
          
          if (details.preregCost !== undefined && details.preregCost !== null && details.preregCost > 0) {
            descriptionParts.push(`Prereg Cost: $${details.preregCost}`);
          }
          
          if (details.preregDateEnd) {
            const preregEndDate = new Date(details.preregDateEnd);
            const formattedDate = preregEndDate.toLocaleDateString('en-US', {
              year: 'numeric',
              month: 'short',
              day: 'numeric'
            });
            descriptionParts.push(`Prereg End Date: ${formattedDate}`);
          }
          
          if (details.extraInfo && details.extraInfo.trim()) {
            descriptionParts.push(`Extra Information: ${details.extraInfo}`);
          }
          
          eventDescription = descriptionParts.join('\n');
          
          // Get cover image from event type if available
          try {
            const eventTypeDoc = await db.collection('event_types').doc(event.typeId).get();
            if (eventTypeDoc.exists) {
              const eventTypeData = eventTypeDoc.data();
              if (eventTypeData.imageUrl) {
                coverImage = eventTypeData.imageUrl;
              }
            }
          } catch (imageError) {
            console.log(`⚠️ Could not get event type image for ${event.id}:`, imageError.message);
          }
        }

        const {
          startDate,
          endDate,
          locationName,
          locationAddress
        } = event;

        // Validate required fields
        if (!startDate || !endDate || !locationName) {
          console.log(`❌ Event ${event.id} missing required fields: startDate=${startDate}, endDate=${endDate}, locationName=${locationName}`);
          results.push({
            eventId: event.id,
            eventName: eventName,
            status: 'error',
            message: 'Missing required fields: startDate, endDate, or locationName'
          });
          continue;
        }

        // Parse dates and times with proper timezone handling
        // Get location timezone from the event's location
        let timezone = 'America/New_York'; // Default fallback
        
        try {
          // Get the location document to get its timezone
          const locationDoc = await db.collection('locations')
            .where('name', '==', locationName)
            .limit(1)
            .get();
          
          if (!locationDoc.empty) {
            const locationData = locationDoc.docs[0].data();
            if (locationData.timezone) {
              timezone = locationData.timezone;
              console.log(`📍 Using timezone ${timezone} for location: ${locationName}`);
            }
          }
        } catch (timezoneError) {
          console.log(`⚠️ Could not get timezone for location ${locationName}, using default: ${timezone}`);
        }
        
        // Parse the date strings and treat them as local time in the specified timezone
        const startDateTime = moment.tz(startDate + ' 00:00:00', timezone);
        const endDateTime = moment.tz(endDate + ' 23:59:59', timezone);

        // Validate dates
        if (startDateTime.isBefore(moment())) {
          console.log(`❌ Event ${event.id} start time is in the past: ${startDateTime.format()}`);
          results.push({
            eventId: event.id,
            eventName: eventName,
            status: 'error',
            message: 'Event start time must be in the future'
          });
          continue;
        }

        if (endDateTime.isBefore(startDateTime)) {
          results.push({
            eventId: event.id,
            eventName: eventName,
            status: 'error',
            message: 'Event end time must be later than start time'
          });
          continue;
        }

        // Format dates for Discord API with proper timezone handling
        const formattedStart = startDateTime.toISOString();
        const formattedEnd = endDateTime.toISOString();

        // Check if event already has a Discord event ID and verify it still exists
        if (event.discordEventId) {
          console.log(`🔍 Checking existing Discord event ${event.discordEventId} for event ${event.id}`);
          
          try {
            // Try to fetch the existing Discord event with retry logic
            let existingDiscordEvent = null;
            let retryCount = 0;
            const maxRetries = 3;
            
            while (retryCount < maxRetries) {
              try {
                existingDiscordEvent = await axios.get(
                  `https://discord.com/api/v10/guilds/1102958641503547394/scheduled-events/${event.discordEventId}`,
                  {
                    headers: {
                      Authorization: `Bot ${DISCORD_TOKEN.value()}`,
                      "Content-Type": "application/json"
                    },
                    timeout: 10000 // 10 second timeout
                  }
                );
                break; // Success, exit retry loop
              } catch (retryError) {
                retryCount++;
                console.log(`⚠️ Discord API retry ${retryCount}/${maxRetries} for event ${event.discordEventId}: ${retryError.response?.status || retryError.message}`);
                
                if (retryCount >= maxRetries) {
                  throw retryError; // Re-throw the last error
                }
                
                // Wait before retrying (exponential backoff)
                await new Promise(resolve => setTimeout(resolve, 1000 * retryCount));
              }
            }
            
            console.log(`✅ Discord event ${event.discordEventId} still exists`);
            
            // Check if the event data has changed and needs updating
            const discordEvent = existingDiscordEvent.data;
            
            // Normalize the data for comparison
            const normalizedDiscordName = discordEvent.name || '';
            const normalizedDiscordDescription = discordEvent.description || '';
            const normalizedDiscordStart = discordEvent.scheduled_start_time || '';
            const normalizedDiscordEnd = discordEvent.scheduled_end_time || '';
            const normalizedDiscordLocation = discordEvent.entity_metadata?.location || '';
            
            const needsUpdate = 
              normalizedDiscordName !== eventName ||
              normalizedDiscordDescription !== eventDescription ||
              normalizedDiscordStart !== formattedStart ||
              normalizedDiscordEnd !== formattedEnd ||
              normalizedDiscordLocation !== locationName;
            
            if (needsUpdate) {
              console.log(`🔄 Updating Discord event ${event.discordEventId} with new data`);
              console.log(`   Name: "${normalizedDiscordName}" -> "${eventName}"`);
              console.log(`   Description: "${normalizedDiscordDescription}" -> "${eventDescription}"`);
              console.log(`   Start: "${normalizedDiscordStart}" -> "${formattedStart}"`);
              console.log(`   End: "${normalizedDiscordEnd}" -> "${formattedEnd}"`);
              console.log(`   Location: "${normalizedDiscordLocation}" -> "${locationName}"`);
              
              // Update the Discord event with retry logic
              let updateResponse = null;
              retryCount = 0;
              
              while (retryCount < maxRetries) {
                try {
                  const updatePayload = {
                    name: eventName,
                    description: eventDescription,
                    scheduled_start_time: formattedStart,
                    scheduled_end_time: formattedEnd,
                    entity_metadata: {
                      location: locationName
                    }
                  };
                  
                  // Add image if available
                  if (coverImage) {
                    updatePayload.image = coverImage;
                  }
                  
                  updateResponse = await axios.patch(
                    `https://discord.com/api/v10/guilds/1102958641503547394/scheduled-events/${event.discordEventId}`,
                    updatePayload,
                    {
                      headers: {
                        Authorization: `Bot ${DISCORD_TOKEN.value()}`,
                        "Content-Type": "application/json"
                      },
                      timeout: 10000
                    }
                  );
                  break; // Success, exit retry loop
                } catch (retryError) {
                  retryCount++;
                  console.log(`⚠️ Discord update retry ${retryCount}/${maxRetries} for event ${event.discordEventId}: ${retryError.response?.status || retryError.message}`);
                  
                  if (retryCount >= maxRetries) {
                    throw retryError; // Re-throw the last error
                  }
                  
                  // Wait before retrying (exponential backoff)
                  await new Promise(resolve => setTimeout(resolve, 1000 * retryCount));
                }
              }
              
              console.log(`✅ Discord event ${event.discordEventId} updated successfully`);
              
              results.push({
                eventId: event.id,
                eventName: eventName,
                status: 'updated',
                message: `Discord event updated: ${updateResponse.data.name}`,
                discordEventId: event.discordEventId
              });
              
              // Continue to next event since we've handled this one
              continue;
            } else {
              console.log(`⏭️ Discord event ${event.discordEventId} is up to date`);
              results.push({
                eventId: event.id,
                eventName: eventName,
                status: 'skipped',
                message: 'Discord event is up to date'
              });
              
              // Continue to next event since we've handled this one
              continue;
            }
            
          } catch (discordError) {
            const errorStatus = discordError.response?.status;
            const errorMessage = discordError.response?.data?.message || discordError.message;
            
            console.log(`❌ Discord event ${event.discordEventId} check failed:`);
            console.log(`   Status: ${errorStatus}`);
            console.log(`   Message: ${errorMessage}`);
            
            // Only clear the Discord event ID if it's a 404 (not found) error
            // For other errors (rate limiting, network issues, etc.), keep the ID and skip
            if (errorStatus === 404) {
              console.log(`🗑️ Discord event ${event.discordEventId} not found (404), clearing ID and will recreate`);
              
              // Discord event doesn't exist, clear the ID and recreate
              await db.collection('events').doc(event.id).update({
                discordEventId: null,
                discordEventCreated: false,
                discordEventCreatedAt: null
              });
              
              console.log(`🔄 Will recreate Discord event for ${event.id}`);
              // Continue to create new Discord event below
            } else {
              console.log(`⚠️ Discord API error (${errorStatus}), skipping event ${event.id} to avoid duplicates`);
              
              results.push({
                eventId: event.id,
                eventName: eventName,
                status: 'error',
                message: `Discord API error: ${errorStatus} - ${errorMessage}`,
                discordEventId: event.discordEventId
              });
              
              // Skip this event to avoid creating duplicates
              continue;
            }
          }
        }

        // Create Discord event payload
        const payload = {
          guildId: "1102958641503547394",
          name: eventName,
          description: eventDescription,
          scheduledStartTime: formattedStart,
          scheduledEndTime: formattedEnd,
          entityType: 3,                        // 3 = External event
          privacyLevel: 2,                      // 2 = Guild only
          entityMetadata: {
            location: locationName
          }
        };
        
        // Add cover image if available
        if (coverImage) {
          payload.image = coverImage;
        }

        console.log(`📤 Creating Discord event for: ${eventName} (${startDateTime.format()} - ${endDateTime.format()})`);
        
        // Create Discord event with retry logic
        let discordResponse = null;
        let retryCount = 0;
        const maxRetries = 3;
        
        while (retryCount < maxRetries) {
          try {
            const eventPayload = {
              name: payload.name,
              description: payload.description,
              scheduled_start_time: payload.scheduledStartTime,
              scheduled_end_time: payload.scheduledEndTime,
              privacy_level: payload.privacyLevel,
              entity_type: payload.entityType,
              entity_metadata: payload.entityMetadata
            };
            
            // Add image if available
            if (payload.image) {
              eventPayload.image = payload.image;
            }
            
            discordResponse = await axios.post(
              `https://discord.com/api/v10/guilds/${payload.guildId}/scheduled-events`,
              eventPayload,
              {
                headers: {
                  Authorization: `Bot ${DISCORD_TOKEN.value()}`,
                  "Content-Type": "application/json"
                },
                timeout: 10000
              }
            );
            break; // Success, exit retry loop
          } catch (retryError) {
            retryCount++;
            console.log(`⚠️ Discord create retry ${retryCount}/${maxRetries} for event ${eventName}: ${retryError.response?.status || retryError.message}`);
            
            if (retryCount >= maxRetries) {
              throw retryError; // Re-throw the last error
            }
            
            // Wait before retrying (exponential backoff)
            await new Promise(resolve => setTimeout(resolve, 1000 * retryCount));
          }
        }

        // Update event in Firestore to mark Discord sync
        await db.collection('events').doc(event.id).update({
          discordEventId: discordResponse.data.id,
          discordEventCreated: true,
          discordEventCreatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // Add delay after Discord API call to avoid rate limiting
        await new Promise(resolve => setTimeout(resolve, 1000));

        results.push({
          eventId: event.id,
          eventName: eventName,
          status: 'success',
          message: `Discord event created: ${discordResponse.data.name}`,
          discordEventId: discordResponse.data.id
        });

              } catch (error) {
          console.error(`❌ Error syncing event ${event.id}:`, error);
          console.error(`   Error details:`, {
            status: error.response?.status,
            statusText: error.response?.statusText,
            data: error.response?.data,
            message: error.message,
            stack: error.stack
          });
          
          // Log rate limit specific information
          if (error.response?.status === 429) {
            console.error(`🚨 RATE LIMIT HIT for event ${event.id}:`);
            console.error(`   Rate limit headers:`, error.response.headers);
            console.error(`   Retry after:`, error.response.headers['retry-after']);
            console.error(`   X-RateLimit-Limit:`, error.response.headers['x-ratelimit-limit']);
            console.error(`   X-RateLimit-Remaining:`, error.response.headers['x-ratelimit-remaining']);
            console.error(`   X-RateLimit-Reset:`, error.response.headers['x-ratelimit-reset']);
          }
          
          results.push({
            eventId: event.id,
            eventName: event.typeName || 'Unknown',
            status: 'error',
            message: error.response?.data?.message || error.message,
            errorDetails: {
              status: error.response?.status,
              statusText: error.response?.statusText,
              rateLimitInfo: error.response?.status === 429 ? {
                retryAfter: error.response.headers['retry-after'],
                limit: error.response.headers['x-ratelimit-limit'],
                remaining: error.response.headers['x-ratelimit-remaining'],
                reset: error.response.headers['x-ratelimit-reset']
              } : null
            }
          });
        }
    }

    return res.status(200).json({
      ok: true,
      message: 'Events sync completed',
      results: results,
      summary: {
        total: events.length,
        successful: results.filter(r => r.status === 'success').length,
        updated: results.filter(r => r.status === 'updated').length,
        errors: results.filter(r => r.status === 'error').length,
        skipped: results.filter(r => r.status === 'skipped').length
      }
    });

  } catch (error) {
    console.error('Error syncing events to Discord:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Get all registrations for an event
exports.getEventRegistrations = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { eventId } = req.query;

    if (!eventId) {
      return res.status(400).json({ ok: false, error: 'Event ID is required' });
    }

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    // Get all registrations for this event
    const registrationsSnapshot = await db.collection('events')
      .doc(eventId)
      .collection('registrations')
      .get();

    // Get the event to access the event type
    const eventDoc = await db.collection('events').doc(eventId).get();
    const eventData = eventDoc.data();
    
    // Get the event type to access NPC shifts and cleanup tasks
    const eventTypeDoc = await db.collection('event_types').doc(eventData.typeId).get();
    const eventTypeData = eventTypeDoc.data();
    
    const registrations = [];
    const npcShifts = {};
    const cleanupTasks = {};

    // Process each registration
    for (const doc of registrationsSnapshot.docs) {
      const registration = {
        id: doc.id,
        ...doc.data()
      };
      console.log('Processing registration:', registration);
      
      // Get user details for the main registration
      let playerName = 'Unknown Player';
      let characterName = '';
      try {
        const userRecord = await getAuth().getUser(doc.id);
        playerName = userRecord.displayName || userRecord.email || 'Unknown Player';
        
        // Try to get character data from user's document
        try {
          const userDoc = await db.collection('users').doc(doc.id).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            if (userData.characterName) {
              characterName = userData.characterName;
            }
          }
        } catch (charError) {
          console.log(`Could not get character data for ${doc.id}:`, charError.message);
        }
      } catch (error) {
        console.log(`Could not get user details for ${doc.id}:`, error.message);
      }
      
      // Add player name and character name to the registration
      registration.playerName = playerName;
      registration.characterName = characterName;
      
      registrations.push(registration);

      // Count by attendee type
      const attendeeType = registration.attendeeTypeName || 'Unknown';

      // Process NPC shifts
      if (registration.selectedNpcShifts && Array.isArray(registration.selectedNpcShifts)) {
        for (const shiftIndex of registration.selectedNpcShifts) {
          // Get the actual shift name from the event type
          const shiftName = eventTypeData.npcShifts && eventTypeData.npcShifts[shiftIndex] 
            ? eventTypeData.npcShifts[shiftIndex].name || `Shift ${shiftIndex + 1}`
            : `Shift ${shiftIndex + 1}`;
          
          if (!npcShifts[shiftIndex]) {
            npcShifts[shiftIndex] = {
              name: shiftName,
              registrations: []
            };
          }
          // Get user details
          let playerName = 'Unknown Player';
          let characterName = '';
          try {
            const userRecord = await getAuth().getUser(doc.id);
            playerName = userRecord.displayName || userRecord.email || 'Unknown Player';
            
            // Try to get character data from user's document
            try {
              const userDoc = await db.collection('users').doc(doc.id).get();
              if (userDoc.exists) {
                const userData = userDoc.data();
                if (userData.characterName) {
                  characterName = userData.characterName;
                }
              }
            } catch (charError) {
              console.log(`Could not get character data for ${doc.id}:`, charError.message);
            }
          } catch (error) {
            console.log(`Could not get user details for ${doc.id}:`, error.message);
          }
          
          npcShifts[shiftIndex].registrations.push({
            playerName: playerName,
            characterName: characterName,
            uid: doc.id
          });
        }
      }

      // Process cleanup tasks
      if (registration.selectedCleanupShifts && Array.isArray(registration.selectedCleanupShifts)) {
        for (const taskIndex of registration.selectedCleanupShifts) {
          // Get the actual task name from the event type
          const taskName = eventTypeData.cleanupShifts && eventTypeData.cleanupShifts[taskIndex]
            ? eventTypeData.cleanupShifts[taskIndex]
            : `Cleanup Task ${taskIndex + 1}`;
          
          if (!cleanupTasks[taskIndex]) {
            cleanupTasks[taskIndex] = {
              name: taskName,
              registrations: []
            };
          }
          // Get user details
          let playerName = 'Unknown Player';
          let characterName = '';
          try {
            const userRecord = await getAuth().getUser(doc.id);
            playerName = userRecord.displayName || userRecord.email || 'Unknown Player';
            
            // Try to get character data from user's document
            try {
              const userDoc = await db.collection('users').doc(doc.id).get();
              if (userDoc.exists) {
                const userData = userDoc.data();
                if (userData.characterName) {
                  characterName = userData.characterName;
                }
              }
            } catch (charError) {
              console.log(`Could not get character data for ${doc.id}:`, charError.message);
            }
          } catch (error) {
            console.log(`Could not get user details for ${doc.id}:`, error.message);
          }
          
          cleanupTasks[taskIndex].registrations.push({
            playerName: playerName,
            characterName: characterName,
            uid: doc.id
          });
        }
      }
    }

    // Count registrations by type
    const playerCount = registrations.filter((r) => r.attendeeTypeName === 'Player').length;
    const staffCount = registrations.filter((r) => r.attendeeTypeName === 'Staff').length;
    const sliceOfLifeCount = registrations.filter((r) => r.attendeeTypeName === 'Slice of Life').length;

    return res.status(200).json({
      ok: true,
      registrations: {
        total: registrations.length,
        players: playerCount,
        staff: staffCount,
        sliceOfLife: sliceOfLifeCount,
        registrations: registrations
      },
      npcShifts: npcShifts,
      cleanupTasks: cleanupTasks
    });

  } catch (error) {
    console.error('Error getting event registrations:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});

// Manual QR Code Regeneration for all users
exports.regenerateAllQRCodes = onRequest({ secrets: [GAME_SECRET] }, async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Check if user is authenticated
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Check if user is super admin
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    console.log('🔄 Starting QR code regeneration for all users...');

    // Get all users from Firestore
    const usersSnapshot = await db.collection('users').get();
    const results = [];

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userEmail = userData.email;
      
      if (!userEmail) {
        console.log(`⚠️ Skipping user ${userDoc.id} - no email found`);
        continue;
      }

      try {
        console.log(`🔄 Regenerating QR code for user: ${userEmail}`);
        
        // Get the user's pc.json file from Firebase Storage
        const bucket = getStorage().bucket();
        const pcFilePath = `users/${userEmail}/pc.json`;
        const pcFile = bucket.file(pcFilePath);
        
        // Check if pc.json exists
        const [exists] = await pcFile.exists();
        if (!exists) {
          console.log(`⚠️ No pc.json found for ${userEmail}`);
          results.push({
            email: userEmail,
            status: 'skipped',
            reason: 'No pc.json file found'
          });
          continue;
        }

        // Download the current pc.json
        const [fileContent] = await pcFile.download();
        const characterData = JSON.parse(fileContent.toString('utf8'));
        
        // Add a small modification to trigger the function
        characterData.lastQRRegeneration = new Date().toISOString();
        
        // Upload the modified pc.json back to trigger QR generation
        await pcFile.save(JSON.stringify(characterData, null, 2), {
          metadata: {
            contentType: 'application/json'
          }
        });
        
        console.log(`✅ Triggered QR regeneration for ${userEmail}`);
        results.push({
          email: userEmail,
          status: 'success',
          message: 'QR regeneration triggered'
        });
        
        // Add a small delay to avoid overwhelming the system
        await new Promise(resolve => setTimeout(resolve, 1000));
        
      } catch (error) {
        console.error(`❌ Error regenerating QR for ${userEmail}:`, error);
        results.push({
          email: userEmail,
          status: 'error',
          error: error.message
        });
      }
    }

    const successCount = results.filter(r => r.status === 'success').length;
    const errorCount = results.filter(r => r.status === 'error').length;
    const skippedCount = results.filter(r => r.status === 'skipped').length;

    console.log(`✅ QR regeneration completed: ${successCount} successful, ${errorCount} errors, ${skippedCount} skipped`);

    return res.status(200).json({
      ok: true,
      message: `QR regeneration completed for ${usersSnapshot.docs.length} users`,
      summary: {
        total: usersSnapshot.docs.length,
        successful: successCount,
        errors: errorCount,
        skipped: skippedCount
      },
      results: results
    });

  } catch (error) {
    console.error('Error regenerating QR codes:', error);
    res.status(500).json({
      ok: false,
      error: 'server_error',
      message: error.message
    });
  }
});
