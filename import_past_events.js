/*
  One-off script to import past events into Firestore.
  Usage: node import_past_events.js
*/

const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin with service account
const serviceAccountPath = path.resolve(__dirname, 'functions', 'service-account-key.json');
// eslint-disable-next-line @typescript-eslint/no-var-requires
const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
}

const db = admin.firestore();

function toIsoDate(dateStr) {
  // Accepts M/D/YYYY or MM/DD/YYYY and returns YYYY-MM-DD
  if (!dateStr) return '';
  const parts = String(dateStr).trim().split('/');
  if (parts.length !== 3) return '';
  const [m, d, y] = parts.map((p) => p.trim());
  const month = String(parseInt(m, 10)).padStart(2, '0');
  const day = String(parseInt(d, 10)).padStart(2, '0');
  const year = String(parseInt(y, 10));
  if (!year || !month || !day) return '';
  return `${year}-${month}-${day}`;
}

function parseDates(startStr, endStr) {
  const startIso = toIsoDate(startStr);
  let endIso = toIsoDate(endStr);
  try {
    const start = startIso ? new Date(`${startIso}T00:00:00Z`) : null;
    let end = endIso ? new Date(`${endIso}T00:00:00Z`) : null;
    if (start && end && end < start) {
      // If end appears to be in an incorrect year (e.g., 2024 vs 2025), bump year to start year
      const sYear = startIso.slice(0, 4);
      const eMD = endIso.slice(5); // MM-DD
      endIso = `${sYear}-${eMD}`;
      end = new Date(`${endIso}T00:00:00Z`);
    }
  } catch (_) {}
  return { startIso, endIso };
}

function slugify(input) {
  return String(input)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 48);
}

async function upsertEvent(row) {
  const { name, startDate, endDate, location } = row;
  const { startIso, endIso } = parseDates(startDate, endDate);
  if (!startIso || !endIso) {
    throw new Error(`Invalid dates for event "${name}": start=${startDate} end=${endDate}`);
  }
  const id = `${startIso.replace(/-/g, '')}-${slugify(name)}`;

  const data = {
    startDate: startIso,
    endDate: endIso,
    locationId: null,
    locationName: location,
    locationAddress: '',
    typeId: null,
    typeName: name, // Use the actual event title for display
    registrationActivated: false,
    registrationDetails: { eventName: name },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection('events').doc(id).set(data, { merge: true });
  return id;
}

async function run() {
  const rows = [
    { name: 'Welcome to the Academy', startDate: '9/15/2023', endDate: '9/17/2023', location: "Gryphon's Nest Campground" },
    { name: 'Festival of the Lost - First Moon', startDate: '10/13/2023', endDate: '10/13/2023', location: "Gryphon's Nest Campground" },
    { name: 'Academy Visitors - Second Moon', startDate: '11/10/2023', endDate: '11/12/2023', location: "Gryphon's Nest Campground" },
    { name: 'The Open Door - Third Moon', startDate: '12/28/2023', endDate: '12/30/2023', location: "Gryphon's Nest Campground" },
    { name: 'New Beginnings - Chaper 4', startDate: '2/2/2024', endDate: '2/4/2024', location: 'Camp Niwana' },
    { name: 'A Challenge Offered - Third Moon', startDate: '2/16/2024', endDate: '2/18/2024', location: "Gryphon's Nest Campground" },
    { name: 'Academy Rivals - Fifth Moon', startDate: '3/15/2024', endDate: '3/17/2024', location: "Gryphon's Nest Campground" },
    { name: 'The First Tow Challenges', startDate: '4/12/2024', endDate: '4/12/2024', location: "Gryphon's Nest Campground" },
    { name: 'SSLA War Comes Season Closer', startDate: '5/24/2024', endDate: '5/27/2024', location: "Gryphon's Nest Campground" },
    { name: 'Sanguine Struggles SSLA', startDate: '9/13/2024', endDate: '9/15/2024', location: "Gryphon's Nest Campground" },
    { name: 'A Sanctuary Threatened', startDate: '10/11/2024', endDate: '10/13/2024', location: "Gryphon's Nest Campground" },
    { name: 'An Enemy Revealed', startDate: '12/27/2024', endDate: '12/30/2024', location: "Gryphon's Nest Campground" },
    { name: 'The Blood Chalice', startDate: '1/17/2025', endDate: '1/19/2025', location: "Gryphon's Nest Campground" },
    { name: 'War is here', startDate: '2/28/2025', endDate: '3/2/2025', location: "Gryphon's Nest Campground" },
    { name: 'The End of the Goblin Threat...hopefully', startDate: '3/28/2025', endDate: '3/30/2025', location: "Gryphon's Nest Campground" },
  ];

  let success = 0;
  const ids = [];
  for (const row of rows) {
    try {
      const id = await upsertEvent(row);
      ids.push(id);
      success += 1;
      console.log(`✔ Imported: ${row.name} (${id})`);
    } catch (err) {
      console.error(`✖ Failed: ${row.name} -> ${err.message}`);
    }
  }

  console.log('\nSummary');
  console.log(`Inserted/updated: ${success}/${rows.length}`);
  console.log('IDs:', ids.join(', '));
}

run().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });


