// Imports and initialization (moved to top to avoid 'onRequest' before initialization)
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
const admin = require("firebase-admin");
const moment = require('moment-timezone');
const { google: googleapis } = require('googleapis');
const config = require("./config.json");

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// Declare secrets
const DISCORD_TOKEN = defineSecret("DISCORD_TOKEN");
const GAME_SECRET = defineSecret("GAME_SECRET");

// Confirm/add/remove user from a shift
exports.updateShiftAssignment = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) return res.status(403).json({ ok: false, error: 'admin_only' });

    const { eventId, targetUid, action, shiftType, shiftIndexOrName } = req.body || {};
    if (!eventId || !targetUid || !action || !shiftType) {
      return res.status(400).json({ ok: false, error: 'missing_params' });
    }

    const regRef = db.collection('events').doc(String(eventId)).collection('registrations').doc(String(targetUid));
    const regDoc = await regRef.get();
    if (!regDoc.exists) return res.status(404).json({ ok: false, error: 'registration_not_found' });
    const data = regDoc.data() || {};

    if (shiftType === 'npc') {
      const idx = parseInt(shiftIndexOrName);
      const primary = Array.isArray(data.selectedNpcShifts) ? data.selectedNpcShifts : [];
      switch (action) {
        case 'confirm':
        case 'add_primary':
          if (!primary.includes(idx)) primary.push(idx);
          break;
        case 'remove':
          const i = primary.indexOf(idx);
          if (i >= 0) primary.splice(i, 1);
          if (data.secondaryNpcShift === idx) data.secondaryNpcShift = null;
          break;
        case 'set_secondary':
          data.secondaryNpcShift = idx;
          break;
      }
      data.selectedNpcShifts = primary;
    } else if (shiftType === 'cleanup') {
      const name = String(shiftIndexOrName);
      const primary = Array.isArray(data.selectedCleanupShifts) ? data.selectedCleanupShifts : [];
      switch (action) {
        case 'confirm':
        case 'add_primary':
          if (!primary.includes(name)) primary.push(name);
          break;
        case 'remove':
          const i = primary.indexOf(name);
          if (i >= 0) primary.splice(i, 1);
          if (data.secondaryCleanupShift === name) data.secondaryCleanupShift = null;
          break;
        case 'set_secondary':
          data.secondaryCleanupShift = name;
          break;
      }
      data.selectedCleanupShifts = primary;
    } else {
      return res.status(400).json({ ok: false, error: 'invalid_shift_type' });
    }

    await regRef.update(data);
    return res.status(200).json({ ok: true, message: 'updated', data });
  } catch (e) {
    console.error('updateShiftAssignment error', e);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});

// Grant check-in permission (super admin only)
exports.grantCheckInPermission = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const requesterUid = decoded.uid;
    if (!(await isSuperAdmin(requesterUid))) return res.status(403).json({ ok: false, error: 'Must be super admin' });
    const { targetUid, eventId, global } = req.body || {};
    if (!targetUid) return res.status(400).json({ ok: false, error: 'targetUid required' });
    if (global === true) {
      await db.collection('roles').doc('checkin').collection('global').doc(targetUid).set({ grantedAt: admin.firestore.FieldValue.serverTimestamp(), grantedBy: requesterUid });
    } else if (eventId) {
      await db.collection('roles').doc('checkin').collection('events').doc(eventId).collection('members').doc(targetUid).set({ grantedAt: admin.firestore.FieldValue.serverTimestamp(), grantedBy: requesterUid });
    } else {
      return res.status(400).json({ ok: false, error: 'Provide eventId or set global=true' });
    }
    return res.status(200).json({ ok: true });
  } catch (e) {
    console.error('grantCheckInPermission error:', e);
    return res.status(500).json({ ok: false, error: 'server_error', message: e.message });
  }
});

// Revoke check-in permission (super admin only)
exports.revokeCheckInPermission = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const requesterUid = decoded.uid;
    if (!(await isSuperAdmin(requesterUid))) return res.status(403).json({ ok: false, error: 'Must be super admin' });
    const { targetUid, eventId, global } = req.body || {};
    if (!targetUid) return res.status(400).json({ ok: false, error: 'targetUid required' });
    if (global === true) {
      await db.collection('roles').doc('checkin').collection('global').doc(targetUid).delete();
    } else if (eventId) {
      await db.collection('roles').doc('checkin').collection('events').doc(eventId).collection('members').doc(targetUid).delete();
    } else {
      return res.status(400).json({ ok: false, error: 'Provide eventId or set global=true' });
    }
    return res.status(200).json({ ok: true });
  } catch (e) {
    console.error('revokeCheckInPermission error:', e);
    return res.status(500).json({ ok: false, error: 'server_error', message: e.message });
  }
});

// List check-in permissions (super admin only)
exports.listCheckInPermissions = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const requesterUid = decoded.uid;
    if (!(await isSuperAdmin(requesterUid))) return res.status(403).json({ ok: false, error: 'Must be super admin' });
    const { eventId } = req.query;
    const globalSnap = await db.collection('roles').doc('checkin').collection('global').get();
    const global = globalSnap.docs.map(d => ({ uid: d.id, ...d.data() }));
    let eventMembers = [];
    if (eventId) {
      const evSnap = await db.collection('roles').doc('checkin').collection('events').doc(String(eventId)).collection('members').get();
      eventMembers = evSnap.docs.map(d => ({ uid: d.id, ...d.data() }));
    }
    return res.status(200).json({ ok: true, global, eventMembers });
  } catch (e) {
    console.error('listCheckInPermissions error:', e);
    return res.status(500).json({ ok: false, error: 'server_error', message: e.message });
  }
});

// List users (basic) for admin selection (super admin only)
exports.listUsersBasic = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const requesterUid = decoded.uid;
    if (!(await isSuperAdmin(requesterUid))) return res.status(403).json({ ok: false, error: 'Must be super admin' });

    const q = ((req.query.q || '').toString() || '').toLowerCase();
    const limitParam = parseInt((req.query.limit || '500').toString(), 10);
    const maxResults = Math.max(1, Math.min(1000, isNaN(limitParam) ? 500 : limitParam));

    const users = [];
    let nextPageToken = undefined;
    while (users.length < maxResults) {
      const page = await getAuth().listUsers(1000, nextPageToken);
      for (const u of page.users) {
        const email = (u.email || '').toLowerCase();
        const displayName = u.displayName || null;
        if (!q || email.includes(q)) {
          users.push({ uid: u.uid, email: u.email || null, displayName });
          if (users.length >= maxResults) break;
        }
      }
      nextPageToken = page.pageToken;
      if (!nextPageToken) break;
    }

    // Try to attach a primary character number per user (best effort)
    for (let i = 0; i < users.length; i++) {
      const { uid } = users[i];
      try {
        const charsSnap = await db.collection('players').doc(uid).collection('characters').get();
        let chosen = null;
        charsSnap.forEach((doc) => {
          const id = doc.id || '';
          // prefer numeric, pick smallest; fallback to 'main'; else any
          const asNum = parseInt(id, 10);
          if (!isNaN(asNum)) {
            if (chosen == null || (!isNaN(parseInt(chosen, 10)) && asNum < parseInt(chosen, 10))) chosen = id;
            if (isNaN(parseInt(chosen || '', 10))) chosen = id;
          } else if (!chosen) {
            chosen = id; // take first non-numeric if nothing else
          }
        });
        if (chosen) users[i].characterNumber = chosen;
      } catch (e) {
        // ignore; leave without characterNumber
      }
    }

    // Sort by character number ascending, then email
    users.sort((a, b) => {
      const aNum = parseInt(a.characterNumber || '', 10);
      const bNum = parseInt(b.characterNumber || '', 10);
      const aIsNum = !isNaN(aNum);
      const bIsNum = !isNaN(bNum);
      if (aIsNum && bIsNum) {
        if (aNum !== bNum) return aNum - bNum;
      } else if (aIsNum) {
        return -1;
      } else if (bIsNum) {
        return 1;
      }
      return (a.email || '').localeCompare(b.email || '');
    });

    return res.status(200).json({ ok: true, users });
  } catch (e) {
    console.error('listUsersBasic error:', e);
    return res.status(500).json({ ok: false, error: 'server_error', message: e.message });
  }
});
// (imports and initialization moved to top)
// Discord OAuth: Get authorization URL
exports.getDiscordAuthorizeUrl = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  try {
    const clientId = config.discord.client_id;
    const redirectUri = encodeURIComponent(config.discord.redirect_uri);
    const scope = encodeURIComponent('identify guilds.join');
    const responseType = 'code';
    const prompt = 'consent';

    const url = `https://discord.com/api/oauth2/authorize?client_id=${clientId}&redirect_uri=${redirectUri}&response_type=${responseType}&scope=${scope}&prompt=${prompt}`;
    return res.status(200).json({ ok: true, url });
  } catch (e) {
    console.error('getDiscordAuthorizeUrl error', e);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});

// Temporary: Import a fixed list of past events into Firestore
exports.importPastEventsTemp = onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  try {
    const key = (req.query.key || req.body?.key || '').toString();
    if (key !== 'import') {
      return res.status(403).json({ ok: false, error: 'forbidden' });
    }

    const toIsoDate = (dateStr) => {
      if (!dateStr) return '';
      const parts = String(dateStr).trim().split('/');
      if (parts.length !== 3) return '';
      const m = String(parseInt(parts[0], 10)).padStart(2, '0');
      const d = String(parseInt(parts[1], 10)).padStart(2, '0');
      const y = String(parseInt(parts[2], 10));
      if (!y || !m || !d) return '';
      return `${y}-${m}-${d}`;
    };

    const parseDates = (startStr, endStr) => {
      const startIso = toIsoDate(startStr);
      let endIso = toIsoDate(endStr);
      try {
        const start = startIso ? new Date(`${startIso}T00:00:00Z`) : null;
        let end = endIso ? new Date(`${endIso}T00:00:00Z`) : null;
        if (start && end && end < start) {
          const sYear = startIso.slice(0, 4);
          const eMD = endIso.slice(5);
          endIso = `${sYear}-${eMD}`;
          end = new Date(`${endIso}T00:00:00Z`);
        }
      } catch (_) {}
      return { startIso, endIso };
    };

    const slugify = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 48);

    const fallbackRows = [
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

    const rows = Array.isArray(req.body?.rows) ? req.body.rows : fallbackRows;

    let success = 0;
    const ids = [];
    for (const row of rows) {
      const name = String(row.name || '').trim();
      const locationName = String(row.location || '').trim();
      const { startIso, endIso } = parseDates(row.startDate, row.endDate);
      if (!name || !startIso || !endIso) continue;
      const id = `${startIso.replace(/-/g, '')}-${slugify(name)}`;

      const data = {
        startDate: startIso,
        endDate: endIso,
        locationId: null,
        locationName,
        locationAddress: '',
        typeId: null,
        typeName: name,
        registrationActivated: false,
        registrationDetails: { eventName: name },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection('events').doc(id).set(data, { merge: true });
      success += 1;
      ids.push(id);
    }

    return res.status(200).json({ ok: true, inserted: success, ids });
  } catch (error) {
    console.error('importPastEventsTemp error', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

// Backfill: For past events, scan event checkins and Master Logs for matching
// "Attending Event" entries by date; write rows to the check-in Google Sheet
exports.backfillAdvancementFromMasterLogs = onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  try {
    // Optional key-bypass for temporary usage
    const bypassKey = (req.query.key || req.body?.key || '').toString();
    const keyBypass = (bypassKey === 'backfill');

    let scannerEmail = 'backfill@system.local';
    if (!keyBypass) {
      // Auth: super admin only
      if (!req.headers.authorization) {
        return res.status(401).json({ ok: false, error: 'Missing authorization header' });
      }
      const idToken = req.headers.authorization.split(' ')[1];
      const decodedToken = await getAuth().verifyIdToken(idToken);
      const uid = decodedToken.uid;
      const isAdmin = await isSuperAdmin(uid);
      if (!isAdmin) {
        return res.status(403).json({ ok: false, error: 'User must be super admin' });
      }
      scannerEmail = decodedToken.email || scannerEmail;
    }

    // Inputs: upToDate (ISO), containerDocId (Master Logs root), dryRun
    const upToDateIso = (req.query.upToDate || req.body?.upToDate || '').toString();
    const containerDocId = (req.query.containerDocId || req.body?.containerDocId || 'root').toString();
    const dryRun = String(req.query.dryRun ?? req.body?.dryRun ?? 'false').toLowerCase() === 'true';

    let upToDate = null;
    if (upToDateIso) {
      const d = new Date(upToDateIso);
      if (!isNaN(d.getTime())) upToDate = d;
    }

    // Load events that ended before now (past events). If upToDate is given, use it; else now
    const now = new Date();
    const cutoff = upToDate || now;
    const eventsSnap = await db.collection('events')
      .where('endDate', '<', cutoff.toISOString().slice(0, 10))
      .orderBy('endDate', 'desc')
      .get();

    // Prepare Google Sheets API
    const auth = new googleapis.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      keyFile: './service-account-key.json'
    });
    const sheets = googleapis.sheets({ version: 'v4', auth });

    const results = [];
    let appended = 0;

    // Helper to normalize a date string from Master Logs to YYYY-MM-DD
    const normalizeDate = (value) => {
      if (!value) return '';
      // Try known formats: ISO, M/D/YYYY, MM/DD/YYYY
      const v = String(value).trim();
      // If already YYYY-MM-DD
      if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      // If ISO full
      const dt = new Date(v);
      if (!isNaN(dt.getTime())) return dt.toISOString().slice(0, 10);
      // If M/D/YYYY
      const m = v.split('/');
      if (m.length === 3) {
        const month = String(parseInt(m[0], 10)).padStart(2, '0');
        const day = String(parseInt(m[1], 10)).padStart(2, '0');
        const year = String(parseInt(m[2], 10));
        if (year && month && day) return `${year}-${month}-${day}`;
      }
      return '';
    };

    // Preload Master Logs rows indexed by date with reason
    const masterLogsRef = db.collection('Master Logs').doc(containerDocId).collection('All');
    const masterLogsSnap = await masterLogsRef.get();
    const byDate = new Map(); // dateStr (YYYY-MM-DD) -> array of rows
    masterLogsSnap.forEach((doc) => {
      const row = doc.data() || {};
      const reason = String(row['Advancement Reason'] || row['AdvancementReason'] || '').trim();
      if (reason.toLowerCase() !== 'attending event') return;
      const dateStr = normalizeDate(row['Date'] || row['date'] || row['_date']);
      if (!dateStr) return;
      if (!byDate.has(dateStr)) byDate.set(dateStr, []);
      byDate.get(dateStr).push(row);
    });

    for (const evDoc of eventsSnap.docs) {
      const ev = { id: evDoc.id, ...(evDoc.data() || {}) };
      const eventName = ev.registrationActivated && ev.registrationDetails?.eventName ? ev.registrationDetails.eventName : (ev.typeName || ev.type || ev.id);
      const eventStart = String(ev.startDate || '').slice(0, 10);
      const eventEnd = String(ev.endDate || '').slice(0, 10);

      // Load checkins
      const checkinsSnap = await db.collection('events').doc(ev.id).collection('checkins').get();
      if (checkinsSnap.empty) {
        results.push({ eventId: ev.id, eventName, status: 'no_checkins' });
        continue;
      }

      // Candidate master log dates: between start and end (inclusive)
      const candidateDates = new Set([eventStart, eventEnd]);
      // Also include each day in the range in case of multi-day events
      try {
        const s = new Date(`${eventStart}T00:00:00Z`);
        const e = new Date(`${eventEnd}T00:00:00Z`);
        if (!isNaN(s.getTime()) && !isNaN(e.getTime())) {
          for (let d = new Date(s); d <= e; d.setUTCDate(d.getUTCDate() + 1)) {
            candidateDates.add(d.toISOString().slice(0, 10));
          }
        }
      } catch (_) {}

      const rowsToAppend = [];
      for (const checkDoc of checkinsSnap.docs) {
        const checkin = checkDoc.data() || {};
        const playerUid = checkin.playerUid || checkDoc.id;

        // Get player email
        let playerEmail = 'Unknown';
        try {
          const userRecord = await getAuth().getUser(playerUid);
          playerEmail = userRecord.email || 'Unknown';
        } catch (e) {
          const userDoc = await db.collection('users').doc(playerUid).get();
          if (userDoc.exists) playerEmail = (userDoc.data() || {}).email || 'Unknown';
        }

        // Read registration for attendingAs and adjustments
        const regDoc = await db.collection('events').doc(ev.id).collection('registrations').doc(playerUid).get();
        const reg = regDoc.exists ? (regDoc.data() || {}) : {};
        const attendingAs = reg.attendeeTypeName || 'Unknown';
        const buildAdjustment = reg.buildForEvent || 0;
        const apAdjustment = reg.affinityPointsForEvent || 0;

        // Find a matching master log entry by date among candidate dates
        let matched = false;
        for (const dateStr of candidateDates) {
          const rows = byDate.get(dateStr) || [];
          if (rows.length > 0) { matched = true; break; }
        }
        if (!matched) continue; // skip if no matching attending event row by date

        // Build row like checkInPlayer: [scanner email, timestamp, player email, event name, attendingAs, Build, AP]
        const rowData = [
          scannerEmail,                       // scanner/admin
          new Date().toISOString(),           // timestamp now
          playerEmail,                        // player email
          eventName,                          // event name
          attendingAs,                        // attending as
          buildAdjustment,                     // build adj
          apAdjustment                         // ap adj
        ];
        rowsToAppend.push(rowData);
      }

      if (rowsToAppend.length > 0 && !dryRun) {
        await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.checkin_spreadsheet_id,
          range: `${config.google_sheets.checkin_sheet_name}!A:G`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: { values: rowsToAppend }
        });
        appended += rowsToAppend.length;
        results.push({ eventId: ev.id, eventName, appended: rowsToAppend.length });
      } else {
        results.push({ eventId: ev.id, eventName, appended: 0 });
      }
    }

    return res.status(200).json({ ok: true, appended, results, dryRun });
  } catch (error) {
    console.error('backfillAdvancementFromMasterLogs error', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

// Discord OAuth callback: exchange code, store user, and optionally join guild
exports.discordOAuthCallback = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  try {
    const code = req.query.code || req.body?.code;
    const state = req.query.state || req.body?.state; // optional: could include Firebase UID
    if (!code) return res.status(400).json({ ok: false, error: 'missing_code' });

    // Exchange code for tokens
    const params = new URLSearchParams();
    params.append('client_id', config.discord.client_id);
    params.append('client_secret', config.discord.client_secret);
    params.append('grant_type', 'authorization_code');
    params.append('code', code);
    params.append('redirect_uri', config.discord.redirect_uri);

    const tokenResp = await axios.post('https://discord.com/api/oauth2/token', params, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });

    const accessToken = tokenResp.data.access_token;
    const tokenType = tokenResp.data.token_type; // should be 'Bearer'

    // Fetch user identity
    const userResp = await axios.get('https://discord.com/api/users/@me', {
      headers: { Authorization: `${tokenType} ${accessToken}` },
    });
    const discordUser = userResp.data; // { id, username, discriminator, global_name, avatar, ... }

    // If state includes Firebase ID token, verify and get UID to associate
    let uid = null;
    if (state) {
      try {
        const decoded = await getAuth().verifyIdToken(String(state));
        uid = decoded.uid;
      } catch (e) {
        console.log('State not a valid Firebase ID token, skipping user association');
      }
    }

    // If not provided via state, allow Authorization header with Firebase ID token
    if (!uid && req.headers.authorization) {
      const idToken = req.headers.authorization.split(' ')[1];
      const decoded = await getAuth().verifyIdToken(idToken);
      uid = decoded.uid;
    }

    // Store mapping in Firestore under players/{uid}/discord
    if (uid) {
      const playerRef = db.collection('players').doc(uid);
      await playerRef.set({ lastUpdated: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      await playerRef.collection('integrations').doc('discord').set({
        discordId: discordUser.id,
        username: discordUser.username,
        discriminator: discordUser.discriminator,
        globalName: discordUser.global_name || null,
        avatar: discordUser.avatar || null,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Optionally join guild using bot token
      try {
        const guildId = config.discord.guild_id;
        if (guildId) {
          await axios.put(
            `https://discord.com/api/v10/guilds/${guildId}/members/${discordUser.id}`,
            { access_token: accessToken },
            { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` } }
          );
        }
      } catch (joinErr) {
        console.log('Guild join failed or skipped:', joinErr.response?.data || joinErr.message);
      }

      // After linking: if there is an active event and the user is registered,
      // add them to the event role and NPC shift private channels
      try {
        const activeEventsSnap = await db.collection('events')
          .where('registrationActivated', '==', true)
          .get();
        for (const evDoc of activeEventsSnap.docs) {
          const ev = { id: evDoc.id, ...evDoc.data() };
          // Check if user is registered
          const regDoc = await db.collection('events').doc(ev.id)
            .collection('registrations').doc(uid).get();
          if (!regDoc.exists) continue;

          // Ensure role and shift channels exist
          const roleId = await ensureDiscordRoleForEvent(ev);
          const shifts = await ensureNpcShiftPrivateChannelsForEvent(ev);

          // Get linked discord id
          const discordId = discordUser.id;
          if (roleId) await addRoleToDiscordMember(discordId, roleId);

          // Grant access to selected NPC shift channels
          const reg = regDoc.data();
          const selected = Array.isArray(reg.selectedNpcShifts) ? reg.selectedNpcShifts : [];
          const VIEW_CHANNEL = 1 << 10;
          const SEND_MESSAGES = 1 << 11;
          const READ_MESSAGE_HISTORY = 1 << 16;
          const normalAllow = (VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY);
          for (const idx of selected) {
            const chId = shifts[idx];
            if (chId) await ensureUserPermissionOnChannel(chId, discordId, normalAllow);
          }
        }
      } catch (postLinkErr) {
        console.log('⚠️ post-link discord membership update failed:', postLinkErr.response?.data || postLinkErr.message);
      }
    }

    // Respond with a minimal HTML page that can close the popup and pass result back
    const successHtml = `<!doctype html><html><body><script>try{window.opener && window.opener.postMessage({type:'discord_linked', ok:true}, '*');}catch(e){} window.close();</script>Linked. You can close this window.</body></html>`;
    res.set('Content-Type', 'text/html');
    return res.status(200).send(successHtml);
  } catch (e) {
    console.error('discordOAuthCallback error', e.response?.data || e.message);
    const errorHtml = `<!doctype html><html><body><script>try{window.opener && window.opener.postMessage({type:'discord_linked', ok:false, error:'${(e.response?.data?.error || e.message).toString().replace(/'/g, '')}'}, '*');}catch(err){} window.close();</script>Failed. You can close this window.</body></html>`;
    res.set('Content-Type', 'text/html');
    return res.status(500).send(errorHtml);
  }
});

// Get Discord link status for current user
exports.getDiscordLinkStatus = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const doc = await db.collection('players').doc(uid).collection('integrations').doc('discord').get();
    return res.status(200).json({ ok: true, linked: doc.exists, data: doc.exists ? doc.data() : null });
  } catch (e) {
    console.error('getDiscordLinkStatus error', e);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});

// Disconnect Discord link for current user
exports.disconnectDiscord = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const ref = db.collection('players').doc(uid).collection('integrations').doc('discord');
    await ref.delete();
    return res.status(200).json({ ok: true, disconnected: true });
  } catch (e) {
    console.error('disconnectDiscord error', e);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});

// Create a one-time link code for the current user
exports.createDiscordLinkCode = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const code = crypto.randomBytes(4).toString('hex');
    const ref = db.collection('discord_link_codes').doc(code);
    await ref.set({
      uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      used: false,
    });

    // Clean up the verification channel and post instruction message
    try {
      const channelId = config.discord.link_channel_id;
      if (channelId) {
        // Fetch recent messages
        const msgsResp = await axios.get(`https://discord.com/api/v10/channels/${channelId}/messages?limit=100`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }
        });
        const messages = msgsResp.data || [];

        // Check if a pinned instruction message already exists
        let hasPinnedInstruction = false;
        for (const m of messages) {
          if (m.pinned && typeof m.content === 'string' && m.content.includes('Crucible Helper app')) {
            hasPinnedInstruction = true;
            break;
          }
        }

        // Post concise instruction message and pin it only if missing
        const channelName = config.discord.link_channel_name || 'verification';
        const parts = [];
        parts.push(`# ${channelName}`);
        parts.push('This channel is reserved for the Crucible Helper app to link Discord users.');
        parts.push('Please do not chat here.');
        parts.push('To link: In the app, get your code and post it here. Messages are removed after verification.');
        const instructionContent = parts.join('\n');
        if (!hasPinnedInstruction) {
          try {
            const postResp = await axios.post(`https://discord.com/api/v10/channels/${channelId}/messages`, {
              content: instructionContent
            }, {
              headers: {
                Authorization: `Bot ${DISCORD_TOKEN.value()}`,
                'Content-Type': 'application/json'
              }
            });
            const posted = postResp.data;
            try {
              await axios.put(`https://discord.com/api/v10/channels/${channelId}/pins/${posted.id}`, null, {
                headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }
              });
            } catch (pinErr) {
              console.log('Pin failed (continuing):', pinErr.response?.status || pinErr.message);
            }
          } catch (postErr) {
            console.log('Instruction post failed (continuing):', postErr.response?.status || postErr.message);
          }
        }
      }
    } catch (channelErr) {
      console.log('Channel cleanup failed (continuing):', channelErr.response?.status || channelErr.message);
    }
    return res.status(200).json({ ok: true, code, channelId: config.discord.link_channel_id, channelName: config.discord.link_channel_name || null, inviteUrl: config.discord.invite_url || null });
  } catch (e) {
    console.error('createDiscordLinkCode error', e);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});

// Verify a code by scanning messages in a specific channel
exports.verifyDiscordLinkByChannel = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (!req.headers.authorization) return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    const decoded = await getAuth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const { code } = req.body || {};
    if (!code) return res.status(400).json({ ok: false, error: 'missing_code' });

    const codeDoc = await db.collection('discord_link_codes').doc(String(code)).get();
    if (!codeDoc.exists || codeDoc.data().used) {
      return res.status(400).json({ ok: false, error: 'invalid_or_used_code' });
    }
    if (codeDoc.data().uid !== uid) {
      return res.status(403).json({ ok: false, error: 'code_not_for_user' });
    }

    const channelId = config.discord.link_channel_id;
    if (!channelId) return res.status(500).json({ ok: false, error: 'link_channel_not_configured' });

    // Fetch recent messages and look for the code
    const resp = await axios.get(`https://discord.com/api/v10/channels/${channelId}/messages?limit=100`, {
      headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }
    });
    const messages = resp.data || [];
    const hit = messages.find((m) => typeof m.content === 'string' && m.content.includes(code));
    if (!hit) {
      return res.status(404).json({ ok: false, error: 'code_not_found_in_channel' });
    }

    const discordUser = hit.author; // { id, username, ... }

    // Store mapping under player integrations
    const playerRef = db.collection('players').doc(uid);
    await playerRef.set({ lastUpdated: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    await playerRef.collection('integrations').doc('discord').set({
      discordId: discordUser.id,
      username: discordUser.username,
      discriminator: discordUser.discriminator,
      globalName: discordUser.global_name || null,
      linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      linkMethod: 'channel_code'
    }, { merge: true });

    // Mark code used
    await db.collection('discord_link_codes').doc(String(code)).update({ used: true, usedAt: admin.firestore.FieldValue.serverTimestamp() });

    // Attempt to delete the user's verification message to keep channel clean
    try {
      await axios.delete(`https://discord.com/api/v10/channels/${channelId}/messages/${hit.id}`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }
      });
    } catch (cleanupErr) {
      console.log('Cleanup delete failed (continuing):', cleanupErr.response?.status || cleanupErr.message);
    }

    return res.status(200).json({ ok: true, linked: true, discordId: discordUser.id });
  } catch (e) {
    console.error('verifyDiscordLinkByChannel error', e.response?.data || e.message);
    return res.status(500).json({ ok: false, error: 'server_error' });
  }
});
// Sync Rules DB from Google Sheets to Firestore
exports.syncRulesDb = onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Optional auth: allow only signed-in users; super-admin check can be added if needed
    // Mirror syncMasterLogs behavior: no auth required, rely on project permissions/CORS

    // Inputs
    let spreadsheetId = (req.query.spreadsheetId || req.body?.spreadsheetId || config.google_sheets.rules_spreadsheet_id || config.google_sheets.pc_db_spreadsheet_id).toString();
    const sanitizeSpreadsheetId = (raw) => {
      if (!raw) return raw;
      const dIdx = raw.indexOf('/d/');
      if (dIdx >= 0) {
        const after = raw.substring(dIdx + 3);
        const endSlash = after.indexOf('/');
        return endSlash >= 0 ? after.substring(0, endSlash) : after;
      }
      const qIdx = raw.indexOf('?');
      if (qIdx >= 0) raw = raw.substring(0, qIdx);
      const slashIdx = raw.indexOf('/');
      if (slashIdx >= 0) raw = raw.substring(0, slashIdx);
      return raw;
    };
    spreadsheetId = sanitizeSpreadsheetId(spreadsheetId);
    const clearExisting = ((req.query.clear ?? req.body?.clear ?? 'true').toString().toLowerCase() !== 'false');

    // Google Sheets API
    const auth = new googleapis.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
      keyFile: './service-account-key.json',
    });
    const sheets = googleapis.sheets({ version: 'v4', auth });

    // Fetch sheet metadata for robust name resolution
    const meta = await sheets.spreadsheets.get({ spreadsheetId });
    const sheetTitles = (meta.data.sheets || [])
      .map(s => s.properties?.title)
      .filter(Boolean);
    const normalize = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
    const titleByNorm = new Map(sheetTitles.map(t => [normalize(t), t]));
    const resolveSheetTitle = (desired, variants = []) => {
      const candidates = [desired, ...variants];
      for (const c of candidates) {
        if (sheetTitles.includes(c)) return c;
        const norm = normalize(c);
        if (titleByNorm.has(norm)) return titleByNorm.get(norm);
      }
      return null;
    };
    const warnings = [];

    const readSheet = async (sheetName, rangeA1 = 'A:ZZ') => {
      // Always quote sheet names to handle spaces/special chars; escape single quotes by doubling
      const safeSheet = `'${String(sheetName).replace(/'/g, "''")}'`;
      const range = `${safeSheet}!${rangeA1}`;
      const resp = await sheets.spreadsheets.values.get({ spreadsheetId, range });
      const values = resp.data.values || [];
      if (values.length === 0) return { headers: [], rows: [] };
      return { headers: values[0], rows: values.slice(1) };
    };

    const toObject = (headers, row) => {
      const obj = {};
      for (let i = 0; i < headers.length; i++) {
        const key = headers[i] ?? `col_${i}`;
        obj[key] = (row[i] ?? '').toString().trim();
      }
      return obj;
    };

    const parseBool = (val) => {
      if (typeof val !== 'string') return false;
      const t = val.trim().toLowerCase();
      return t === 'true' || t === 'yes' || t === 'y' || t === '1';
    };

    const sanitizeDocId = (value, fallback) => {
      let id = String(value ?? '').trim();
      if (id === '' || id === '.' || id === '..') id = String(fallback ?? 'doc');
      // Firestore doc IDs cannot contain '/'
      id = id.replace(/\//g, ' - ');
      // Collapse whitespace
      id = id.replace(/\s+/g, ' ').trim();
      // Enforce max length (Firestore supports up to 1500)
      if (id.length > 1500) id = id.substring(0, 1500);
      return id;
    };

    const sanitizeCollectionId = (value, fallback) => {
      // Same restrictions as doc IDs for safety
      return sanitizeDocId(value, fallback);
    };

    const rulesRoot = db.collection('Rules');

    // Optional clearing of existing docs to mirror Master Logs behavior
    const clearAllDocs = async (collectionRef) => {
      let cleared = 0;
      const snapshot = await collectionRef.get();
      const docs = snapshot.docs;
      for (let i = 0; i < docs.length; i += 450) {
        const batch = db.batch();
        for (let j = i; j < Math.min(i + 450, docs.length); j++) {
          batch.delete(docs[j].ref);
        }
        await batch.commit();
        cleared += Math.min(450, docs.length - i);
      }
      return cleared;
    };

    // If clearing is requested, remove subcollections first
    let cleared = 0;
    if (clearExisting) {
      cleared += await clearAllDocs(rulesRoot.doc('Affinities').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Races').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Skills').collection('Common'));
      cleared += await clearAllDocs(rulesRoot.doc('Skills').collection('Races'));
      // Clear dynamic Skills subcollections: Common, Races, and any affinity-named collections
      const skillsDocRef = rulesRoot.doc('Skills');
      cleared += await clearAllDocs(skillsDocRef.collection('Common'));
      cleared += await clearAllDocs(skillsDocRef.collection('Races'));
      // Legacy subcollection name used previously
      cleared += await clearAllDocs(skillsDocRef.collection('Affinities'));
      // Delete any other subcollections under Skills (affinity-named)
      if (typeof skillsDocRef.listCollections === 'function') {
        const subcols = await skillsDocRef.listCollections();
        for (const col of subcols) {
          if (col.id === 'Common' || col.id === 'Races' || col.id === 'Affinities') continue;
          cleared += await clearAllDocs(col);
        }
      }
      cleared += await clearAllDocs(rulesRoot.doc('Body Essence - DR').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Cultivation Tiers').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Status Effects').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Frequency').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Duration').collection('All'));
      cleared += await clearAllDocs(rulesRoot.doc('Delivery').collection('All'));
    }

    // 1) Affinities
    const affinityTitle = resolveSheetTitle('Affinity', ['Affinities']);
    let affHeaders = [], affRows = [];
    if (affinityTitle) {
      const sheet = await readSheet(affinityTitle);
      affHeaders = sheet.headers; affRows = sheet.rows;
    } else {
      warnings.push("Missing sheet: Affinity");
    }
    if (affRows.length) {
      const batch = db.batch();
      for (let i = 0; i < affRows.length; i++) {
        const obj = toObject(affHeaders, affRows[i]);
        const name = obj.Name || obj.Affinity || obj.name || `Affinity_${i+1}`;
        const docId = sanitizeDocId(name, `Affinity_${i+1}`);
        const docRef = rulesRoot.doc('Affinities').collection('All').doc(docId);
        batch.set(docRef, {
          Multiplier: Number(obj.Multiplier ?? obj.multiplier ?? 0) || 0,
          Unique: parseBool(obj.Unique ?? obj.unique ?? 'false'),
          _sheetRow: i + 2,
        });
      }
      await batch.commit();
    }

    // 2) Races and Race-Affinity options
    const raceTitle = resolveSheetTitle('Race', ['Races']);
    const raceAffinityTitle = resolveSheetTitle('Race- Affinity', ['Race - Affinity', 'Race Affinity', 'Race Affinities']);
    const raceSheet = raceTitle ? await readSheet(raceTitle) : { headers: [], rows: [] };
    const raceAffinitySheet = raceAffinityTitle ? await readSheet(raceAffinityTitle) : { headers: [], rows: [] };
    if (!raceTitle) warnings.push("Missing sheet: Race");
    if (!raceAffinityTitle) warnings.push("Missing sheet: Race- Affinity");
    // Build map of race -> array of allowed affinities
    const raceToAffinities = new Map();
    if (raceAffinitySheet.rows.length) {
      for (let i = 0; i < raceAffinitySheet.rows.length; i++) {
        const obj = toObject(raceAffinitySheet.headers, raceAffinitySheet.rows[i]);
        const raceName = obj.Race || obj.race || obj.Name;
        const affinityOption = obj['Affinity Option'] || obj['Affinity'] || obj.affinity || '';
        if (!raceName) continue;
        const curr = raceToAffinities.get(raceName) || [];
        if (affinityOption) curr.push(affinityOption);
        raceToAffinities.set(raceName, curr);
      }
    }
    if (raceSheet.rows.length) {
      const batch = db.batch();
      for (let i = 0; i < raceSheet.rows.length; i++) {
        const obj = toObject(raceSheet.headers, raceSheet.rows[i]);
        const name = obj.Name || obj.Race || obj.name || `Race_${i+1}`;
        const docId = sanitizeDocId(name, `Race_${i+1}`);
        const docRef = rulesRoot.doc('Races').collection('All').doc(docId);
        batch.set(docRef, {
          Unique: parseBool(obj.Unique ?? obj.unique ?? 'false'),
          Description: obj.Description ?? obj.description ?? '',
          'Costume Requirements': obj['Costume Requirements'] ?? obj.costumeRequirements ?? '',
          Notes: obj.Notes ?? obj.notes ?? '',
          AffinityOptions: raceToAffinities.get(name) || [],
          _sheetRow: i + 2,
        });
      }
      await batch.commit();
    }

    // 3) Skills: Common, Race Skills, Affinity Skills
    const commonSkillsTitle = resolveSheetTitle('Common Skills', ['Common']);
    const raceSkillsTitle = resolveSheetTitle('Race Skill', ['Race Skills']);
    const affinitySkillsTitle = resolveSheetTitle('Affinity Skills', ['Affinity Skill']);
    const commonSkills = commonSkillsTitle ? await readSheet(commonSkillsTitle) : { headers: [], rows: [] };
    const raceSkills = raceSkillsTitle ? await readSheet(raceSkillsTitle) : { headers: [], rows: [] };
    const affinitySkills = affinitySkillsTitle ? await readSheet(affinitySkillsTitle) : { headers: [], rows: [] };
    if (!commonSkillsTitle) warnings.push("Missing sheet: Common Skills");
    if (!raceSkillsTitle) warnings.push("Missing sheet: Race Skill");
    if (!affinitySkillsTitle) warnings.push("Missing sheet: Affinity Skills");

    const writeSkills = async (categoryName, sheet) => {
      if (!sheet.rows.length) return 0;
      console.log(`📋 Processing ${categoryName} skills - headers:`, sheet.headers);
      const baseCol = rulesRoot.doc('Skills').collection(categoryName);
      let written = 0;
      for (let start = 0; start < sheet.rows.length; start += 400) {
        const batch = db.batch();
        const slice = sheet.rows.slice(start, start + 400);
        for (let i = 0; i < slice.length; i++) {
          const rowIndex = start + i;
          const obj = toObject(sheet.headers, slice[i]);
          const name = obj.Name || obj.name || `Skill_${categoryName}_${rowIndex+1}`;
          const docId = sanitizeDocId(name, `Skill_${categoryName}_${rowIndex+1}`);
          const prereqName = obj['Skill Prerequisite'] || obj.skillPrerequisite || '';
          const prereqCategory = obj['Prerequisite Category'] || obj['Skill Prerequisite Category'] || obj.prerequisiteCategory || '';
          
          // Get Build from correct column based on skill type
          let rawBuild = '';
          if (categoryName === 'Common') {
            // Common Skills: Column C = Build
            rawBuild = slice[i][2] || ''; // Column C (index 2)
          } else if (categoryName === 'Races') {
            // Race Skill: Column B = Build  
            rawBuild = slice[i][1] || ''; // Column B (index 1)
          } else {
            // Affinity Skills: Column D = Build
            rawBuild = slice[i][3] || ''; // Column D (index 3)
          }
          
          console.log(`🔍 ${categoryName} skill "${name}" - raw Build from column: "${rawBuild}" (type: ${typeof rawBuild})`);
          const numericBuild = Number(rawBuild);
          console.log(`🔢 Converted to number: ${numericBuild}`);
          
          const attributes = { ...obj };
          delete attributes.build;
          delete attributes['Base Build'];
          delete attributes['base build'];
          delete attributes.Build;
          const docRef = baseCol.doc(docId);
          batch.set(docRef, {
            ...attributes,
            ...(Number.isFinite(numericBuild) && numericBuild >= 0 ? { Build: numericBuild } : {}),
            SkillPrerequisite: prereqName,
            SkillPrerequisiteCategory: prereqCategory, // Affinity | Race | Common
            _sheetRow: rowIndex + 2,
          }, { merge: true });
          written++;
        }
        await batch.commit();
      }
      return written;
    };

    // Write Common and Race skills as before
    const commonWritten = await writeSkills('Common', commonSkills);
    const raceWritten = await writeSkills('Races', raceSkills);

    // Route Affinity skills into subcollections named after each Affinity
    let affinityWritten = 0;
    if (affinitySkills.rows.length) {
      const skillsDocRef = rulesRoot.doc('Skills');
      for (let start = 0; start < affinitySkills.rows.length; start += 400) {
        const batch = db.batch();
        const slice = affinitySkills.rows.slice(start, start + 400);
        for (let i = 0; i < slice.length; i++) {
          const rowIndex = start + i;
          const obj = toObject(affinitySkills.headers, slice[i]);
          const name = obj.Name || obj.name || `Skill_Affinity_${rowIndex+1}`;
          const docId = sanitizeDocId(name, `Skill_Affinity_${rowIndex+1}`);
          const prereqName = obj['Skill Prerequisite'] || obj.skillPrerequisite || '';
          const prereqCategory = obj['Prerequisite Category'] || obj['Skill Prerequisite Category'] || obj.prerequisiteCategory || '';
          // Determine target affinity subcollection
          const affinityNameRaw = obj.Affinity || obj['Affinity'] || obj['Affinity Name'] || 'Unknown';
          const subcollectionId = sanitizeCollectionId(affinityNameRaw, 'Unknown');
          // Get Build from Column D for Affinity Skills
          const rawBuild = slice[i][3] || ''; // Column D (index 3)
          console.log(`🔍 Affinity skill "${name}" - raw Build from column D: "${rawBuild}" (type: ${typeof rawBuild})`);
          const numericBuild = Number(rawBuild);
          console.log(`🔢 Converted to number: ${numericBuild}`);
          const attributes = { ...obj };
          delete attributes.build;
          delete attributes['Base Build'];
          delete attributes['base build'];
          delete attributes.Build;
          const docRef = skillsDocRef.collection(subcollectionId).doc(docId);
          batch.set(docRef, {
            ...attributes,
            ...(Number.isFinite(numericBuild) && numericBuild >= 0 ? { Build: numericBuild } : {}),
            SkillPrerequisite: prereqName,
            SkillPrerequisiteCategory: prereqCategory,
            _sheetRow: rowIndex + 2,
          }, { merge: true });
          affinityWritten++;
        }
        await batch.commit();
      }
    }

    const skillsWritten = commonWritten + raceWritten + affinityWritten;

    // 4) Body Essence - DR
    const bodyTitle = resolveSheetTitle('Body Essence-DR Chart', ['Body Essence - DR Chart', 'Body Essence DR Chart']);
    const bodySheet = bodyTitle ? await readSheet(bodyTitle) : { headers: [], rows: [] };
    if (!bodyTitle) warnings.push("Missing sheet: Body Essence-DR Chart");
    if (bodySheet.rows.length) {
      const batch = db.batch();
      for (let i = 0; i < bodySheet.rows.length; i++) {
        const obj = toObject(bodySheet.headers, bodySheet.rows[i]);
        const docRef = rulesRoot.doc('Body Essence - DR').collection('All').doc(`Body ${i + 1}`);
        batch.set(docRef, { ...obj, _sheetRow: i + 2 }, { merge: true });
      }
      await batch.commit();
    }

    // 5) Cultivation Tiers
    const tierTitle = resolveSheetTitle('Cultivation Tier', ['Cultivation Tiers']);
    const tierSheet = tierTitle ? await readSheet(tierTitle) : { headers: [], rows: [] };
    if (!tierTitle) warnings.push("Missing sheet: Cultivation Tier");
    if (tierSheet.rows.length) {
      const batch = db.batch();
      for (let i = 0; i < tierSheet.rows.length; i++) {
        const obj = toObject(tierSheet.headers, tierSheet.rows[i]);
        const name = obj.Name || obj.Tier || obj.name || `Tier_${i + 1}`;
        const docId = sanitizeDocId(name, `Tier_${i + 1}`);
        const docRef = rulesRoot.doc('Cultivation Tiers').collection('All').doc(docId);
        batch.set(docRef, { ...obj, _sheetRow: i + 2 }, { merge: true });
      }
      await batch.commit();
    }

    // 6) Status Effects
    const statusTitle = resolveSheetTitle('Status Effects', ['Status Effect']);
    const statusSheet = statusTitle ? await readSheet(statusTitle) : { headers: [], rows: [] };
    if (!statusTitle) warnings.push("Missing sheet: Status Effects");
    if (statusSheet.rows.length) {
      const batch = db.batch();
      for (let i = 0; i < statusSheet.rows.length; i++) {
        const obj = toObject(statusSheet.headers, statusSheet.rows[i]);
        const name = obj.Name || obj.name || `Status_${i + 1}`;
        const docId = sanitizeDocId(name, `Status_${i + 1}`);
        const docRef = rulesRoot.doc('Status Effects').collection('All').doc(docId);
        batch.set(docRef, { ...obj, _sheetRow: i + 2 }, { merge: true });
      }
      await batch.commit();
    }

    // 7) Frequency, Duration, Delivery enumerations
    const freqTitle = resolveSheetTitle('Frequency');
    const durTitle = resolveSheetTitle('Duration');
    const delTitle = resolveSheetTitle('Delivery');
    const freqSheet = freqTitle ? await readSheet(freqTitle) : { headers: [], rows: [] };
    const durSheet = durTitle ? await readSheet(durTitle) : { headers: [], rows: [] };
    const delSheet = delTitle ? await readSheet(delTitle) : { headers: [], rows: [] };
    if (!freqTitle) warnings.push("Missing sheet: Frequency");
    if (!durTitle) warnings.push("Missing sheet: Duration");
    if (!delTitle) warnings.push("Missing sheet: Delivery");
    const writeEnum = async (collectionName, sheet) => {
      if (!sheet.rows.length) return 0;
      const batch = db.batch();
      let count = 0;
      for (let i = 0; i < sheet.rows.length; i++) {
        const obj = toObject(sheet.headers, sheet.rows[i]);
        const name = obj.Name || obj.name || obj.Value || obj.value || `Item_${i + 1}`;
        const docId = sanitizeDocId(name, `Item_${i + 1}`);
        const docRef = rulesRoot.doc(collectionName).collection('All').doc(docId);
        batch.set(docRef, { ...obj, _sheetRow: i + 2 }, { merge: true });
        count++;
      }
      await batch.commit();
      return count;
    };
    const enumsWritten =
      (await writeEnum('Frequency', freqSheet)) +
      (await writeEnum('Duration', durSheet)) +
      (await writeEnum('Delivery', delSheet));

    // 8) README last updated (cell B1)
    const readmeTitle = resolveSheetTitle('README', ['Readme', 'ReadMe']);
    let lastUpdated = '';
    if (readmeTitle) {
      const cellRange = `'${String(readmeTitle).replace(/'/g, "''")}'!B1:B1`;
      const readmeResp = await sheets.spreadsheets.values.get({ spreadsheetId, range: cellRange });
      lastUpdated = (readmeResp.data.values?.[0]?.[0] || '').toString().trim();
    }
    await rulesRoot.doc('Last Updated').set({ date: lastUpdated, _syncedAt: new Date().toISOString() }, { merge: true });

    return res.status(200).json({
      ok: true,
      message: 'Rules DB synced',
      spreadsheetId,
      sheetTitles,
      warnings,
      counts: {
        affinities: affRows.length,
        races: raceSheet.rows.length,
        skills: skillsWritten,
        bodyEssenceDR: bodySheet.rows.length,
        tiers: tierSheet.rows.length,
        statusEffects: statusSheet.rows.length,
        enums: enumsWritten,
      },
      cleared,
    });
  } catch (error) {
    console.error('Error syncing Rules DB:', error);
    res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

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
// Helper: ensure an event-specific Discord text channel exists and has correct permissions
async function ensureDiscordChannelForEvent(event) {
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) {
      console.log('⚠️ Missing discord.guild_id in config; skipping channel ensure');
      return null;
    }

    // Only create channel for activated registrations with an event name
    if (!event.registrationActivated || !event.registrationDetails || !event.registrationDetails.eventName) {
      console.log(`ℹ️ Event ${event.id} has no active registration or shortName; skipping channel ensure`);
      return null;
    }

    // Channel name is fixed to 'notifications'
    const desiredName = 'notifications';

    console.log(`🔧 ensureDiscordChannelForEvent: event=${event.id}, activated=${!!event.registrationActivated}, eventName="${event.registrationDetails?.eventName}", shortName="${event.registrationDetails?.shortName}"`);

    // Desired permission overwrites: @everyone can view and read history, cannot send messages
    const VIEW_CHANNEL = 1 << 10;        // 1024
    const SEND_MESSAGES = 1 << 11;       // 2048
    const READ_MESSAGE_HISTORY = 1 << 16; // 65536
    const desiredAllow = String(VIEW_CHANNEL | READ_MESSAGE_HISTORY);
    const desiredDeny = String(SEND_MESSAGES);
    const everyoneRoleId = guildId; // @everyone role id equals guild id
    const adminRoleId = config.discord.admin_role_id || null; // optional explicit writer role

    // Helper to apply permission overwrite patch safely (preserving others)
    const ensureOverwrites = (existingOverwrites) => {
      const overwrites = Array.isArray(existingOverwrites) ? [...existingOverwrites] : [];
      const idx = overwrites.findIndex((ow) => ow && String(ow.id) === String(everyoneRoleId) && (ow.type === 0 || ow.type === 'role'));
      const target = { id: everyoneRoleId, type: 0, allow: desiredAllow, deny: desiredDeny };
      if (idx >= 0) {
        overwrites[idx] = { id: everyoneRoleId, type: overwrites[idx].type ?? 0, allow: desiredAllow, deny: desiredDeny };
      } else {
        overwrites.push(target);
      }
      // Ensure admin role can send messages explicitly if configured
      if (adminRoleId) {
        const adminIdx = overwrites.findIndex((ow) => ow && String(ow.id) === String(adminRoleId));
        const adminAllow = String((VIEW_CHANNEL | READ_MESSAGE_HISTORY | SEND_MESSAGES));
        const adminTarget = { id: adminRoleId, type: 0, allow: adminAllow, deny: '0' };
        if (adminIdx >= 0) {
          overwrites[adminIdx] = { id: adminRoleId, type: overwrites[adminIdx].type ?? 0, allow: adminAllow, deny: '0' };
        } else {
          overwrites.push(adminTarget);
        }
      }
      return overwrites;
    };

    // Attempt to ensure we have a category for this event (named after the event)
    const { categoryId: eventsCategoryId } = await ensureDiscordCategoryForEvent(event);
    console.log(`📂 ensureDiscordChannelForEvent: categoryId=${eventsCategoryId || 'null'}`);

    // Load latest nested discord data if present
    let latestDiscord = null;
    try {
      const snap = await db.collection('events').doc(event.id).get();
      if (snap.exists) {
        latestDiscord = (snap.data() || {}).discord || null;
      }
    } catch (_) {}
    const storedChannelId = latestDiscord?.notifications?.id || event.discordChannelId || null;

    // If we have a recorded channel id, validate existence and settings
    if (storedChannelId) {
      try {
        const getResp = await axios.get(`https://discord.com/api/v10/channels/${storedChannelId}`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` },
          timeout: 10000
        });
        const channel = getResp.data;
        console.log(`🔎 Found existing notifications channel ${storedChannelId} name="${channel?.name}" parent=${channel?.parent_id}`);

        // Determine if name or overwrites need update
        let needsPatch = false;
        const patchPayload = {};
        if (String(channel.name) !== desiredName) {
          patchPayload.name = desiredName;
          needsPatch = true;
        }

        // Compare @everyone overwrite
        const currentEveryone = Array.isArray(channel.permission_overwrites)
          ? channel.permission_overwrites.find((ow) => String(ow.id) === String(everyoneRoleId))
          : null;
        const allowOk = currentEveryone && String(currentEveryone.allow) === desiredAllow;
        const denyOk = currentEveryone && String(currentEveryone.deny) === desiredDeny;
        if (!allowOk || !denyOk) {
          patchPayload.permission_overwrites = ensureOverwrites(channel.permission_overwrites);
          needsPatch = true;
        }

        // Also ensure parent (category) is set
        if (eventsCategoryId && String(channel.parent_id || '') !== String(eventsCategoryId)) {
          patchPayload.parent_id = eventsCategoryId;
          needsPatch = true;
        }

        if (needsPatch) {
          await axios.patch(`https://discord.com/api/v10/channels/${storedChannelId}`, patchPayload, {
            headers: {
              Authorization: `Bot ${DISCORD_TOKEN.value()}`,
              'Content-Type': 'application/json'
            },
            timeout: 10000
          });
          console.log(`✅ Patched Discord channel ${storedChannelId} for event ${event.id}`);
        } else {
          console.log(`✅ Discord channel ${storedChannelId} already valid for event ${event.id}`);
        }

        // Ensure Firestore has the latest (already does) and return id
        await db.collection('events').doc(event.id).set({
          discordChannelId: storedChannelId,
          discordChannelName: desiredName,
          discord: {
            notifications: { id: storedChannelId, name: desiredName, verifiedAt: new Date().toISOString() }
          }
        }, { merge: true });
        return storedChannelId;
      } catch (e) {
        const status = e.response?.status;
        if (status === 404) {
          console.log(`⚠️ Recorded Discord channel ${storedChannelId} no longer exists; will recreate`);
          // fallthrough to create
        } else {
          console.log(`⚠️ Failed to validate Discord channel ${storedChannelId}:`, e.response?.data || e.message);
          // Continue to attempt creation
        }
      }
    }

    // Create a new channel (optionally under configured category)
    const payload = {
      name: desiredName,
      type: 0,
      permission_overwrites: ensureOverwrites([])
    };
    if (eventsCategoryId) payload.parent_id = eventsCategoryId;

    console.log(`➕ Creating notifications channel under category ${eventsCategoryId} (if provided)`);
    const createResp = await axios.post(
      `https://discord.com/api/v10/guilds/${guildId}/channels`,
      payload,
      { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 15000 }
    );
    const channelId = createResp.data?.id || null;
    if (!channelId) {
      console.log('❌ Failed to create Discord channel: no id returned');
      return null;
    }

    // Persist channel id/name on event
    await db.collection('events').doc(event.id).set({
      discordChannelId: channelId,
      discordChannelName: desiredName,
      discord: {
        notifications: { id: channelId, name: desiredName, createdAt: new Date().toISOString() }
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    console.log(`✅ Created Discord channel ${channelId} (${desiredName}) for event ${event.id}`);
    return channelId;
  } catch (err) {
    console.log('⚠️ ensureDiscordChannelForEvent error:', err.response?.data || err.message || err);
    return null;
  }
}

// Helper: ensure an event-specific Discord role exists (named after the event), return roleId
async function ensureDiscordRoleForEvent(event) {
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) return null;

    const roleName = String(event.registrationDetails?.eventName || event.typeName || `event-${event.id}`).trim().substring(0, 100);

    // Read nested discord data
    let latestDiscord = null;
    try {
      const snap = await db.collection('events').doc(event.id).get();
      if (snap.exists) latestDiscord = (snap.data() || {}).discord || null;
    } catch (_) {}

    const storedRoleId = latestDiscord?.role?.id || event.discordRoleId || null;

    // If we already have a recorded role, verify it
    if (storedRoleId) {
      try {
        const getResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/roles`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` },
          timeout: 10000
        });
        const roles = Array.isArray(getResp.data) ? getResp.data : [];
        const existing = roles.find((r) => String(r.id) === String(storedRoleId));
        if (existing) {
          if (String(existing.name) !== roleName) {
            await axios.patch(`https://discord.com/api/v10/guilds/${guildId}/roles/${storedRoleId}`,
              { name: roleName },
              { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000 }
            );
          }
          await db.collection('events').doc(event.id).set({
            discordRoleId: storedRoleId,
            discordRoleName: roleName,
            discord: { role: { id: storedRoleId, name: roleName, verifiedAt: new Date().toISOString() } },
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
          return storedRoleId;
        }
      } catch (e) {
        console.log('⚠️ verify discord role failed:', e.response?.data || e.message);
      }
    }

    // If we get here, find by name or create
    try {
      const listResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/roles`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` },
        timeout: 10000
      });
      const roles = Array.isArray(listResp.data) ? listResp.data : [];
      const byName = roles.find((r) => String(r.name) === roleName);
      if (byName && byName.id) {
        await db.collection('events').doc(event.id).set({
          discordRoleId: byName.id,
          discordRoleName: roleName,
          discord: { role: { id: byName.id, name: roleName, detectedAt: new Date().toISOString() } },
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        return byName.id;
      }
    } catch (e) {
      console.log('⚠️ list roles failed:', e.response?.data || e.message);
    }

    try {
      const createResp = await axios.post(`https://discord.com/api/v10/guilds/${guildId}/roles`,
        { name: roleName },
        { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000 }
      );
      const roleId = createResp.data?.id || null;
      if (roleId) {
        await db.collection('events').doc(event.id).set({
          discordRoleId: roleId,
          discordRoleName: roleName,
          discord: { role: { id: roleId, name: roleName, createdAt: new Date().toISOString() } },
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`✅ Created Discord role ${roleId} (${roleName}) for event ${event.id}`);
        return roleId;
      }
    } catch (e) {
      console.log('❌ create role failed:', e.response?.data || e.message);
    }

    return null;
  } catch (err) {
    console.log('⚠️ ensureDiscordRoleForEvent error:', err.response?.data || err.message || err);
    return null;
  }
}
// Helper: ensure NPC shift private channels exist, return mapping { [shiftKey]: channelId }
async function ensureNpcShiftPrivateChannelsForEvent(event) {
  const result = {};
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) return result;

    // Need category for this event
    const { categoryId } = await ensureDiscordCategoryForEvent(event);
    if (!categoryId) return result;

    // Load event type to know shifts with dayOfWeek and times
    let npcShifts = [];
    try {
      if (event.typeId) {
        const typeDoc = await db.collection('event_types').doc(event.typeId).get();
        if (typeDoc.exists) {
          const typeData = typeDoc.data();
          npcShifts = Array.isArray(typeData.npcShifts) ? typeData.npcShifts : [];
        }
      }
    } catch (e) {
      console.log('⚠️ failed to load event type npcShifts:', e.message);
    }

    const total = npcShifts.length || (event.numberOfNpcShifts || 0);
    if (!total) return result;

    // Merge with any existing mapping (refresh from DB to avoid stale data)
    let existingMap = event.discordNpcShiftChannels || {};
    try {
      const refreshed = await db.collection('events').doc(event.id).get();
      if (refreshed.exists) {
        existingMap = (refreshed.data() || {}).discordNpcShiftChannels || existingMap;
      }
    } catch (_) {}

    // Build a lookup of existing channels under this category to avoid duplicates
    let existingChildren = [];
    try {
      const listResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/channels`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 20000
      });
      const all = Array.isArray(listResp.data) ? listResp.data : [];
      existingChildren = all.filter((c) => String(c.parent_id || '') === String(categoryId));
    } catch (e) {
      console.log('⚠️ failed to list existing channels for category during ensure:', e.response?.data || e.message);
    }

    // Build the target NPC channel names set for this event
    const targetNames = new Set();
    for (let i = 0; i < total; i++) {
      const shift = npcShifts[i] || {};
      const day0 = String(shift.dayOfWeek || `shift-${i + 1}`).toLowerCase().replace(/\s+/g, '-');
      const start0 = String(shift.startTime || '').replace(/[^0-9:]/g, '');
      const normalizedStart0 = start0 || 'tbd';
      targetNames.add(`npc-${day0}-${normalizedStart0}`);
    }

    // Cleanup any NPC channels under this category that are not part of target names (prefix npc-)
    for (const ch of existingChildren) {
      const name = String(ch.name || '');
      if (/^npc-/i.test(name) && !targetNames.has(name)) {
        try {
          await axios.delete(`https://discord.com/api/v10/channels/${ch.id}`, {
            headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 15000
          });
          console.log(`🗑️ Deleted non-target NPC channel ${ch.id} (${name})`);
        } catch (e) {
          console.log(`⚠️ Failed deleting non-target NPC channel ${ch.id}:`, e.response?.status || e.message);
        }
      }
    }

    // Build name→channel index for quick lookups and track names we assign this run
    const nameToChannel = new Map();
    for (const ch of existingChildren) {
      if (ch && ch.name && targetNames.has(ch.name)) {
        if (!nameToChannel.has(ch.name)) nameToChannel.set(ch.name, ch);
      }
    }
    const usedNames = new Set();

    const MANAGE_CHANNELS = 1 << 5;
    const VIEW_CHANNEL = 1 << 10;
    const SEND_MESSAGES = 1 << 11;
    const READ_MESSAGE_HISTORY = 1 << 16;
    const everyoneRoleId = config.discord.guild_id; // @everyone role id equals guild id

    // Determine a role the bot owns to grant explicit access to private channels
    let botRoleId = null;
    try {
      // Get bot user
      const meResp = await axios.get('https://discord.com/api/v10/users/@me', {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
      });
      const botUser = meResp.data; // { id, username, ... }
      if (botUser?.id) {
        const memberResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/members/${botUser.id}`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
        });
        const roles = memberResp.data?.roles || [];
        if (roles.length > 0) botRoleId = String(roles[0]);
      }
    } catch (e) {
      console.log('⚠️ Could not determine bot role id; private channels may be inaccessible to bot:', e.response?.status || e.message);
    }
    const allowBotBits = String(VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY | MANAGE_CHANNELS);

    for (let i = 0; i < total; i++) {
      const shift = npcShifts[i] || {};
      const day = String(shift.dayOfWeek || `shift-${i + 1}`).toLowerCase().replace(/\s+/g, '-');
      const start = String(shift.startTime || '').replace(/[^0-9:]/g, '');
      const normalizedStart = start || 'tbd';
      const channelName = `npc-${day}-${normalizedStart}`;

      // Start from DB mapping (most authoritative), else from existing category by name
      let channelId = existingMap[i] || null;

      if (channelId) {
        try {
          const getResp = await axios.get(`https://discord.com/api/v10/channels/${channelId}`, {
            headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
          });
          const ch = getResp.data;
          nameToChannel.set(ch.name, ch);
          // Ensure correct name/parent/privacy
          let needPatch = (String(ch.name) !== channelName) || (String(ch.parent_id || '') !== String(categoryId));
          const curEveryone = Array.isArray(ch.permission_overwrites) ? ch.permission_overwrites.find((ow) => String(ow.id) === String(everyoneRoleId)) : null;
          const denyView = String(VIEW_CHANNEL);
          const needsPrivacy = !(curEveryone && String(curEveryone.deny) === denyView);
          if (needsPrivacy) needPatch = true;
          if (needPatch) {
            const overwrites = Array.isArray(ch.permission_overwrites) ? [...ch.permission_overwrites] : [];
            const idx = overwrites.findIndex((ow) => String(ow.id) === String(everyoneRoleId));
            if (idx >= 0) {
              overwrites[idx] = { id: everyoneRoleId, type: 0, allow: '0', deny: denyView };
            } else {
              overwrites.push({ id: everyoneRoleId, type: 0, allow: '0', deny: denyView });
            }
            if (botRoleId) {
              const bIdx = overwrites.findIndex((ow) => String(ow.id) === String(botRoleId));
              if (bIdx >= 0) {
                overwrites[bIdx] = { id: botRoleId, type: 0, allow: allowBotBits, deny: '0' };
              } else {
                overwrites.push({ id: botRoleId, type: 0, allow: allowBotBits, deny: '0' });
              }
            }
            await axios.patch(`https://discord.com/api/v10/channels/${channelId}`,
              { name: channelName, parent_id: categoryId, permission_overwrites: overwrites },
              { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000 }
            );
          }
          // Commit mapping immediately to prevent re-creation by concurrent ensures
          try {
            await db.collection('events').doc(event.id).set({
              [`discordNpcShiftChannels.${i}`]: channelId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
          } catch (_) {}
          nameToChannel.set(channelName, { id: channelId, name: channelName, parent_id: categoryId });
          usedNames.add(channelName);
          result[i] = channelId;
          continue;
        } catch (e) {
          if (e.response?.status === 404) {
            console.log(`ℹ️ Stored NPC channel ${channelId} not found; will recreate for idx ${i}`);
            channelId = null;
          } else if (e.response?.status === 403) {
            // Missing Access: assume the channel exists but the bot can't view/manage it. Avoid creating duplicates.
            console.log('⚠️ Missing access to stored NPC channel; assuming it exists and skipping creation. Please grant bot Manage/View Channels on the category.' );
            usedNames.add(channelName);
            result[i] = existingMap[i];
            // Do not create another channel for this shift
            continue;
          } else {
            console.log('⚠️ Failed to verify stored NPC channel:', e.response?.status || e.message);
          }
        }
      }

      // If after verification we still don't have a channel, try to reuse an existing by name
      if (!channelId) {
        const byName = nameToChannel.get(channelName);
        if (byName && !usedNames.has(channelName)) {
          channelId = byName.id;
        }
      }

      if (channelId) {
        try {
          const getResp = await axios.get(`https://discord.com/api/v10/channels/${channelId}`, {
            headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
          });
          const ch = getResp.data;
          // Ensure correct name and parent & baseline @everyone deny
          let needPatch = (String(ch.name) !== channelName) || (String(ch.parent_id || '') !== String(categoryId));
          const curEveryone = Array.isArray(ch.permission_overwrites) ? ch.permission_overwrites.find((ow) => String(ow.id) === String(everyoneRoleId)) : null;
          const denyView = String(VIEW_CHANNEL);
          const needsPrivacy = !(curEveryone && String(curEveryone.deny) === denyView);
          if (needsPrivacy) needPatch = true;
          if (needPatch) {
            const overwrites = Array.isArray(ch.permission_overwrites) ? [...ch.permission_overwrites] : [];
            const idx = overwrites.findIndex((ow) => String(ow.id) === String(everyoneRoleId));
            if (idx >= 0) {
              overwrites[idx] = { id: everyoneRoleId, type: 0, allow: '0', deny: denyView };
            } else {
              overwrites.push({ id: everyoneRoleId, type: 0, allow: '0', deny: denyView });
            }
            await axios.patch(`https://discord.com/api/v10/channels/${channelId}`,
              { name: channelName, parent_id: categoryId, permission_overwrites: overwrites },
              { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000 }
            );
          }
          // Update indexes
          // Commit mapping as soon as we successfully verified/created
          try {
            await db.collection('events').doc(event.id).set({
              [`discordNpcShiftChannels.${i}`]: channelId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
          } catch (_) {}
          nameToChannel.set(channelName, { id: channelId, name: channelName, parent_id: categoryId });
          usedNames.add(channelName);
        } catch (e) {
          if (e.response?.status !== 404) {
            console.log('⚠️ verify npc channel failed:', e.response?.data || e.message);
          }
          channelId = null; // will recreate
        }
      }

      if (!channelId) {
        try {
          const payload = {
            name: channelName,
            type: 0,
            parent_id: categoryId,
            permission_overwrites: [
              { id: everyoneRoleId, type: 0, allow: '0', deny: String(VIEW_CHANNEL) }
            ]
          };
          if (botRoleId) {
            payload.permission_overwrites.push({ id: botRoleId, type: 0, allow: allowBotBits, deny: '0' });
          }
          const createResp = await axios.post(`https://discord.com/api/v10/guilds/${guildId}/channels`, payload, {
            headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 15000
          });
          channelId = createResp.data?.id;
          console.log(`✅ Created NPC shift channel ${channelId} (${channelName}) in category ${categoryId}`);
          try {
            await db.collection('events').doc(event.id).set({
              [`discordNpcShiftChannels.${i}`]: channelId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
          } catch (_) {}
          nameToChannel.set(channelName, { id: channelId, name: channelName, parent_id: categoryId });
          usedNames.add(channelName);
        } catch (e) {
          if (e.response?.status === 403 || e.response?.data?.code === 50013) {
            console.log('⚠️ Missing Permissions creating NPC channel; ensuring category overwrites then retrying once...');
            try {
              await ensureDiscordCategoryForEvent(event);
              const retryPayload = {
                name: channelName,
                type: 0,
                parent_id: categoryId,
                permission_overwrites: [
                  { id: everyoneRoleId, type: 0, allow: '0', deny: String(VIEW_CHANNEL) }
                ]
              };
              if (botRoleId) {
                retryPayload.permission_overwrites.push({ id: botRoleId, type: 0, allow: allowBotBits, deny: '0' });
              }
              const retryResp = await axios.post(`https://discord.com/api/v10/guilds/${guildId}/channels`, retryPayload, {
                headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 15000
              });
              channelId = retryResp.data?.id || null;
              if (channelId) {
                console.log(`✅ Created NPC shift channel on retry ${channelId} (${channelName}) in category ${categoryId}`);
                try {
                  await db.collection('events').doc(event.id).set({
                    [`discordNpcShiftChannels.${i}`]: channelId,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                  }, { merge: true });
                } catch (_) {}
                nameToChannel.set(channelName, { id: channelId, name: channelName, parent_id: categoryId });
                usedNames.add(channelName);
              } else {
                console.log('❌ Retry create returned no id for NPC channel');
              }
            } catch (eRetry) {
              console.log('❌ failed creating NPC shift channel after retry:', eRetry.response?.data || eRetry.message);
            }
          } else {
            console.log('❌ failed creating NPC shift channel:', e.response?.data || e.message);
          }
        }
      }

      if (channelId) {
        result[i] = channelId;
      }
    }

    // Persist mapping
    await db.collection('events').doc(event.id).update({
      discordNpcShiftChannels: result,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (err) {
    console.log('⚠️ ensureNpcShiftPrivateChannelsForEvent error:', err.response?.data || err.message || err);
  }
  return result;
}

// Helper: archive/delete Discord assets for a past event (delete all child channels, then delete category)
async function archiveDiscordAssetsForEvent(event) {
  const actions = [];
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) return { archived: false, actions };

    if (!event.discordCategoryId) {
      actions.push('No discordCategoryId on event; nothing to archive');
      return { archived: false, actions };
    }

    // Fetch category
    let category = null;
    try {
      const getResp = await axios.get(`https://discord.com/api/v10/channels/${event.discordCategoryId}`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
      });
      category = getResp.data;
    } catch (e) {
      actions.push(`Category ${event.discordCategoryId} not found; skipping archive`);
      return { archived: false, actions };
    }

    // List all guild channels to find children (any type) under the category
    let channels = [];
    try {
      const listResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/channels`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 20000
      });
      channels = Array.isArray(listResp.data) ? listResp.data : [];
    } catch (e) {
      actions.push('Failed listing guild channels while archiving');
    }

    const children = channels.filter((c) => String(c.parent_id || '') === String(event.discordCategoryId));

    // Delete each child channel
    for (const ch of children) {
      try {
        await axios.delete(`https://discord.com/api/v10/channels/${ch.id}`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 15000
        });
        actions.push(`Deleted channel ${ch.id} (${ch.name})`);
      } catch (e) {
        actions.push(`Failed deleting channel ${ch.id}: ${e.response?.status || e.message}`);
      }
    }

    // Delete the category itself
    try {
      await axios.delete(`https://discord.com/api/v10/channels/${event.discordCategoryId}`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 15000
      });
      actions.push(`Deleted category ${event.discordCategoryId} (${category.name})`);
    } catch (e) {
      actions.push(`Failed deleting category ${event.discordCategoryId}: ${e.response?.status || e.message}`);
    }

    // Clear stored Discord fields on the event after deletion
    await db.collection('events').doc(event.id).update({
      discordArchivedAt: admin.firestore.FieldValue.serverTimestamp(),
      discordCategoryId: admin.firestore.FieldValue.delete(),
      discordCategoryName: admin.firestore.FieldValue.delete(),
      discordChannelId: admin.firestore.FieldValue.delete(),
      discordChannelName: admin.firestore.FieldValue.delete(),
      discordRoleId: admin.firestore.FieldValue.delete(),
      discordRoleName: admin.firestore.FieldValue.delete(),
      discordNpcShiftChannels: {},
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return { archived: true, actions };
  } catch (err) {
    return { archived: false, actions: [`Archive error: ${err.response?.data || err.message || err}`] };
  }
}

// Helper: add a Discord role to a guild member
async function addRoleToDiscordMember(discordUserId, roleId) {
  try {
    const guildId = config.discord.guild_id;
    if (!guildId || !discordUserId || !roleId) return;
    await axios.put(`https://discord.com/api/v10/guilds/${guildId}/members/${discordUserId}/roles/${roleId}`, null, {
      headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
    });
  } catch (e) {
    console.log('⚠️ addRoleToDiscordMember failed:', e.response?.data || e.message);
  }
}

// Helper: add user permission to a channel
async function ensureUserPermissionOnChannel(channelId, discordUserId, allowBits) {
  try {
    if (!channelId || !discordUserId) return;
    const getResp = await axios.get(`https://discord.com/api/v10/channels/${channelId}`, {
      headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
    });
    const channel = getResp.data;
    const overwrites = Array.isArray(channel.permission_overwrites) ? [...channel.permission_overwrites] : [];
    const allow = String(allowBits);
    const idx = overwrites.findIndex((ow) => String(ow.id) === String(discordUserId) && (ow.type === 1 || ow.type === '1' || ow.type === 'member'));
    const target = { id: discordUserId, type: 1, allow, deny: '0' };
    if (idx >= 0) {
      overwrites[idx] = { id: discordUserId, type: overwrites[idx].type ?? 1, allow, deny: '0' };
    } else {
      overwrites.push(target);
    }
    await axios.patch(`https://discord.com/api/v10/channels/${channelId}`, { permission_overwrites: overwrites }, {
      headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000
    });
  } catch (e) {
    console.log('⚠️ ensureUserPermissionOnChannel failed:', e.response?.data || e.message);
  }
}

// Update Discord memberships for all linked registrations of an event
async function updateEventDiscordMembershipsForAll(event, options = {}) {
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) return;

    // Ensure role and shift channels exist
    const roleId = await ensureDiscordRoleForEvent(event);
    const skipEnsureNpcChannels = !!options.skipEnsureNpcChannels;
    let shiftChannels = {};
    if (skipEnsureNpcChannels) {
      try {
        const refreshed = await db.collection('events').doc(event.id).get();
        if (refreshed.exists) {
          shiftChannels = (refreshed.data() || {}).discordNpcShiftChannels || (event.discordNpcShiftChannels || {});
        }
      } catch (_) {
        shiftChannels = event.discordNpcShiftChannels || {};
      }
    } else {
      shiftChannels = await ensureNpcShiftPrivateChannelsForEvent(event);
    }

    // Load all registrations
    const regsSnap = await db.collection('events').doc(String(event.id)).collection('registrations').get();
    if (regsSnap.empty) return;

    const VIEW_CHANNEL = 1 << 10;
    const SEND_MESSAGES = 1 << 11;
    const READ_MESSAGE_HISTORY = 1 << 16;
    const normalAllow = (VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY);

    for (const regDoc of regsSnap.docs) {
      const reg = regDoc.data();
      const uid = regDoc.id;
      // Get user's discord link
      const linkDoc = await db.collection('players').doc(uid).collection('integrations').doc('discord').get();
      if (!linkDoc.exists) continue;
      const discordId = linkDoc.data()?.discordId;
      if (!discordId) continue;

      if (roleId) await addRoleToDiscordMember(discordId, roleId);

      const selectedShifts = Array.isArray(reg.selectedNpcShifts) ? reg.selectedNpcShifts : [];
      for (const shiftIndex of selectedShifts) {
        const channelId = shiftChannels[shiftIndex];
        if (channelId) {
          await ensureUserPermissionOnChannel(channelId, discordId, normalAllow);
        }
      }
    }
  } catch (e) {
    console.log('⚠️ updateEventDiscordMembershipsForAll failed:', e.response?.data || e.message);
  }
}
// Helper: ensure a per-event category exists (named after the event), return { categoryId, categoryName }
async function ensureDiscordCategoryForEvent(event) {
  try {
    const guildId = config.discord.guild_id;
    if (!guildId) return { categoryId: null, categoryName: null };

    const categoryName = String(event.registrationDetails?.eventName || event.typeName || `event-${event.id}`).trim().substring(0, 100);
    console.log(`🔧 ensureDiscordCategoryForEvent: event=${event.id}, desiredName="${categoryName}"`);

    // Load latest event to see if nested discord data exists
    let latestDiscord = null;
    try {
      const snap = await db.collection('events').doc(event.id).get();
      if (snap.exists) {
        latestDiscord = (snap.data() || {}).discord || null;
      }
    } catch (_) {}

    const storedCategoryId = latestDiscord?.category?.id || event.discordCategoryId || null;

    // If event already has a recorded category id (either nested or legacy field), verify and update name if needed
    if (storedCategoryId) {
      try {
        const getResp = await axios.get(`https://discord.com/api/v10/channels/${storedCategoryId}`, {
          headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` },
          timeout: 10000
        });
        const category = getResp.data;
        if (category && (category.type === 4 || category.type === '4')) {
          if (String(category.name) !== categoryName) {
            await axios.patch(`https://discord.com/api/v10/channels/${storedCategoryId}`, {
              name: categoryName
            }, { headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000 });
            console.log(`✅ Renamed existing category ${event.discordCategoryId} to "${categoryName}"`);
          }
          // Persist on event: legacy fields and nested discord map
          await db.collection('events').doc(event.id).set({
            discordCategoryId: storedCategoryId,
            discordCategoryName: categoryName,
            discord: {
              category: { id: storedCategoryId, name: categoryName, updatedAt: new Date().toISOString() }
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
          return { categoryId: storedCategoryId, categoryName };
        }
      } catch (e) {
        const status = e.response?.status;
        if (status !== 404) {
          console.log('⚠️ Failed verifying existing event category:', e.response?.data || e.message);
        }
        // fall-through to find/create
      }
    }

    // Try to find an existing category by name
    try {
      const listResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/channels`, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` },
        timeout: 15000
      });
      const channels = Array.isArray(listResp.data) ? listResp.data : [];
      const existing = channels.find((c) => (c.type === 4 || c.type === '4') && String(c.name) === categoryName);
      if (existing && existing.id) {
        await db.collection('events').doc(event.id).set({
          discordCategoryId: existing.id,
          discordCategoryName: categoryName,
          discord: {
            category: { id: existing.id, name: categoryName, detectedAt: new Date().toISOString() }
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`✅ Found existing category ${existing.id} for "${categoryName}"`);
        // Ensure the bot role has explicit permissions on the category so it can create channels under it
        try {
          const MANAGE_CHANNELS = 1 << 5;
          const VIEW_CHANNEL = 1 << 10;
          const SEND_MESSAGES = 1 << 11;
          const READ_MESSAGE_HISTORY = 1 << 16;
          let botRoleId = null;
          try {
            const meResp = await axios.get('https://discord.com/api/v10/users/@me', {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
            });
            const botUser = meResp.data;
            if (botUser?.id) {
              const memberResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/members/${botUser.id}`, {
                headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
              });
              const roles = memberResp.data?.roles || [];
              if (roles.length > 0) botRoleId = String(roles[0]);
            }
          } catch (_) {}
          if (botRoleId) {
            const getCat = await axios.get(`https://discord.com/api/v10/channels/${existing.id}`, {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
            });
            const overwrites = Array.isArray(getCat.data?.permission_overwrites) ? [...getCat.data.permission_overwrites] : [];
            const allowBotBits = String(VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY | MANAGE_CHANNELS);
            const bIdx = overwrites.findIndex((ow) => String(ow.id) === String(botRoleId));
            if (bIdx >= 0) {
              overwrites[bIdx] = { id: botRoleId, type: overwrites[bIdx].type ?? 0, allow: allowBotBits, deny: '0' };
            } else {
              overwrites.push({ id: botRoleId, type: 0, allow: allowBotBits, deny: '0' });
            }
            await axios.patch(`https://discord.com/api/v10/channels/${existing.id}`, { permission_overwrites: overwrites }, {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000
            });
          }
        } catch (e2) {
          console.log('⚠️ Failed ensuring bot access on category:', e2.response?.status || e2.message);
        }
        return { categoryId: existing.id, categoryName };
      }
    } catch (e) {
      console.log('⚠️ Failed listing guild channels:', e.response?.data || e.message);
    }

    // Create the category
    try {
      const createResp = await axios.post(`https://discord.com/api/v10/guilds/${guildId}/channels`, {
        name: categoryName,
        type: 4
      }, {
        headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' },
        timeout: 15000
      });
      const newId = createResp.data?.id || null;
      if (newId) {
        await db.collection('events').doc(event.id).set({
          discordCategoryId: newId,
          discordCategoryName: categoryName,
          discord: {
            category: { id: newId, name: categoryName, createdAt: new Date().toISOString() }
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`✅ Created Discord category ${newId} (${categoryName}) for event ${event.id}`);
        // Ensure the bot role has explicit permissions on the category so it can create channels under it
        try {
          const MANAGE_CHANNELS = 1 << 5;
          const VIEW_CHANNEL = 1 << 10;
          const SEND_MESSAGES = 1 << 11;
          const READ_MESSAGE_HISTORY = 1 << 16;
          let botRoleId = null;
          try {
            const meResp = await axios.get('https://discord.com/api/v10/users/@me', {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
            });
            const botUser = meResp.data;
            if (botUser?.id) {
              const memberResp = await axios.get(`https://discord.com/api/v10/guilds/${guildId}/members/${botUser.id}`, {
                headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
              });
              const roles = memberResp.data?.roles || [];
              if (roles.length > 0) botRoleId = String(roles[0]);
            }
          } catch (_) {}
          if (botRoleId) {
            const getCat = await axios.get(`https://discord.com/api/v10/channels/${newId}`, {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}` }, timeout: 10000
            });
            const overwrites = Array.isArray(getCat.data?.permission_overwrites) ? [...getCat.data.permission_overwrites] : [];
            const allowBotBits = String(VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY | MANAGE_CHANNELS);
            const bIdx = overwrites.findIndex((ow) => String(ow.id) === String(botRoleId));
            if (bIdx >= 0) {
              overwrites[bIdx] = { id: botRoleId, type: overwrites[bIdx].type ?? 0, allow: allowBotBits, deny: '0' };
            } else {
              overwrites.push({ id: botRoleId, type: 0, allow: allowBotBits, deny: '0' });
            }
            await axios.patch(`https://discord.com/api/v10/channels/${newId}`, { permission_overwrites: overwrites }, {
              headers: { Authorization: `Bot ${DISCORD_TOKEN.value()}`, 'Content-Type': 'application/json' }, timeout: 10000
            });
          }
        } catch (e2) {
          console.log('⚠️ Failed ensuring bot access on category:', e2.response?.status || e2.message);
        }
        return { categoryId: newId, categoryName };
      }
    } catch (e) {
      console.log('❌ Failed creating per-event category:', e.response?.data || e.message);
    }

    return { categoryId: null, categoryName: null };
  } catch (err) {
    console.log('⚠️ ensureDiscordCategoryForEvent error:', err.response?.data || err.message || err);
    return { categoryId: null, categoryName: null };
  }
}
// Sync Master Logs from Google Sheets to Firestore
exports.syncMasterLogs = onRequest(async (req, res) => {
  // CORS for manual invocation from browser if needed
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Auth: super admin only
    if (!req.headers.authorization) {
      return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    }
    const idToken = req.headers.authorization.split(' ')[1];
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }
    const containerDocId = (req.query.containerDocId || req.body?.containerDocId || 'root').toString();
    const sheetName = (req.query.sheetName || req.body?.sheetName || config.google_sheets.pc_db_master_logs_sheet_name || 'Master Logs').toString();
    let spreadsheetId = (req.query.spreadsheetId || req.body?.spreadsheetId || config.google_sheets.pc_db_spreadsheet_id || config.google_sheets.checkin_spreadsheet_id).toString();
    // Sanitize spreadsheetId in case a full URL or "/edit?..." suffix was provided
    const sanitizeSpreadsheetId = (raw) => {
      if (!raw) return raw;
      // If URL format, try to extract between '/d/' and next '/'
      const dIdx = raw.indexOf('/d/');
      if (dIdx >= 0) {
        const after = raw.substring(dIdx + 3);
        const endSlash = after.indexOf('/');
        return endSlash >= 0 ? after.substring(0, endSlash) : after;
      }
      // Otherwise strip query or path suffixes
      const qIdx = raw.indexOf('?');
      if (qIdx >= 0) raw = raw.substring(0, qIdx);
      const slashIdx = raw.indexOf('/');
      if (slashIdx >= 0) raw = raw.substring(0, slashIdx);
      return raw;
    };
    spreadsheetId = sanitizeSpreadsheetId(spreadsheetId);
    const clearExisting = ((req.query.clear ?? req.body?.clear ?? 'true').toString().toLowerCase() !== 'false');

    // Initialize Google Sheets API client
    const auth = new googleapis.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      keyFile: './service-account-key.json'
    });
    const sheets = googleapis.sheets({ version: 'v4', auth });

    // Read all rows (21 columns A:U based on provided header)
    const range = `${sheetName}!A:U`;
    const valuesResp = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range
    });
    const values = valuesResp.data.values || [];

    if (!values.length) {
      return res.status(200).json({ ok: true, message: 'No rows found', written: 0, cleared: 0 });
    }

    const headers = values[0];
    const rows = values.slice(1);

    const targetCollection = db.collection('Master Logs').doc(containerDocId).collection('All');

    let cleared = 0;
    if (clearExisting) {
      // Delete existing docs in batches
      const snapshot = await targetCollection.get();
      const docs = snapshot.docs;
      for (let i = 0; i < docs.length; i += 450) {
        const batch = db.batch();
        for (let j = i; j < Math.min(i + 450, docs.length); j++) {
          batch.delete(docs[j].ref);
        }
        await batch.commit();
        cleared += Math.min(450, docs.length - i);
      }
    }

    // Helper to map a sheet row to an object using the header row
    const toObject = (headerArr, rowArr) => {
      const obj = {};
      for (let i = 0; i < headerArr.length; i++) {
        const key = headerArr[i] ?? `col_${i}`;
        obj[key] = rowArr[i] ?? '';
      }
      return obj;
    };

    // Write rows in batches
    let written = 0;
    for (let start = 0; start < rows.length; start += 400) {
      const batch = db.batch();
      const slice = rows.slice(start, start + 400);
      for (let idx = 0; idx < slice.length; idx++) {
        const globalRowIndex = start + idx + 2; // +2 to account for header row and 1-based indexing
        const data = toObject(headers, slice[idx]);
        data._rowNumber = globalRowIndex;
        data._sheet = sheetName;
        data._syncedAt = new Date().toISOString();
        // Use deterministic doc id by row number for idempotency
        const docRef = targetCollection.doc(`r${globalRowIndex}`);
        batch.set(docRef, data, { merge: true });
        written++;
      }
      await batch.commit();
    }

    // Load PC DB 'PCs' sheet to map characterNumber -> email
    const charNumToEmail = new Map();
    try {
      let pcDbSpreadsheetId = sanitizeSpreadsheetId(
        (config.google_sheets.pc_db_spreadsheet_id || '').toString()
      );
      if (pcDbSpreadsheetId) {
        const pcsRange = `PCs!A:Z`;
        const pcsResp = await sheets.spreadsheets.values.get({
          spreadsheetId: pcDbSpreadsheetId,
          range: pcsRange
        });
        const pcsValues = pcsResp.data.values || [];
        // Expect: Column B (index 1) = email, Column F (index 5) = character number
        for (let i = 1; i < pcsValues.length; i++) {
          const r = pcsValues[i] || [];
          const email = String(r[1] || '').trim();
          const charNum = String(r[5] || '').trim();
          if (email && charNum) charNumToEmail.set(charNum, email);
        }
      }
    } catch (e) {
      console.log('PCs lookup failed:', e.message);
    }

    // Mirror Master Logs to per-character advancement subcollections
    // Goal: For each row, identify player and character; write a simple mirror doc under
    // players/{uid}/characters/{characterNumber}/advancement/{masterLogDocId}.
    // Also, delete any existing per-character advancement docs not present in the Master Logs.

    const normalizeKey = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    const getFieldValue = (rowObj, candidates) => {
      for (const cand of candidates) {
        const target = normalizeKey(cand);
        for (const k of Object.keys(rowObj)) {
          if (normalizeKey(k) === target) return rowObj[k];
        }
      }
      return '';
    };

    const emailKeys = [
      'Player Email', 'Email', 'PlayerEmail',
      'Email Address', 'EmailAddress', 'Player E-mail', 'E-mail'
    ];
    const uidKeys = ['Player UID', 'UID', 'PlayerUid', 'playerUid'];
    const characterNumberKeys = [
      'Character Number', 'CharacterNumber', 'characterNumber', 'Character',
      'Character #', 'Character#', 'Char #', 'Char#',
      'PC Number', 'PCNumber',
      'Player Number', 'PlayerNumber',
      'Number', '#'
    ];

    const emailToUidCache = new Map();
    const characterMirrorMap = new Map(); // key: `${uid}_${characterNumber}` -> { uid, characterNumber, docs: Map(docId->docData) }

    // Helper to resolve UID from row (prefer explicit UID; else via email and Auth/users fallback)
    const resolveUid = async (row, characterNumberMaybe) => {
      let uid = String(getFieldValue(row, uidKeys) || '').trim();
      if (uid) return uid;
      let email = String(getFieldValue(row, emailKeys) || '').trim();
      if (!email && characterNumberMaybe) {
        const cKey = String(characterNumberMaybe).trim();
        if (cKey && charNumToEmail.has(cKey)) {
          email = charNumToEmail.get(cKey) || '';
        }
      }
      if (!email) return '';
      if (emailToUidCache.has(email)) return emailToUidCache.get(email);
      try {
        const userRecord = await getAuth().getUserByEmail(email);
        uid = userRecord.uid || '';
      } catch (e) {
        // Fallback to Firestore users collection by email
        try {
          const snap = await db.collection('users').where('email', '==', email).limit(1).get();
          if (!snap.empty) {
            uid = snap.docs[0].id;
          }
        } catch (_) {}
      }
      if (!uid && characterNumberMaybe) {
        try {
          // Try resolve by character number via collection group on 'characters'
          const cg = await db.collectionGroup('characters')
            .where('characterNumber', '==', String(characterNumberMaybe))
            .limit(2)
            .get();
          if (cg.size === 1) {
            const doc = cg.docs[0];
            const parentPlayer = doc.ref.parent.parent; // players/{uid}
            uid = parentPlayer ? parentPlayer.id : '';
          } else if (cg.size === 0) {
            // Try by document ID match (character doc id is usually the number)
            const FieldPath = admin.firestore.FieldPath;
            const cg2 = await db.collectionGroup('characters')
              .where(FieldPath.documentId(), '==', String(characterNumberMaybe))
              .limit(2)
              .get();
            if (cg2.size === 1) {
              const doc = cg2.docs[0];
              const parentPlayer = doc.ref.parent.parent;
              uid = parentPlayer ? parentPlayer.id : '';
            }
          }
        } catch (_) {}
      }
      if (uid && email) emailToUidCache.set(email, uid);
      return uid || '';
    };

    // Load all rows again to compute character mirroring (use values + headers to keep memory low)
    // We'll process sequentially with caching to avoid auth rate limits.
    let diagTotalRows = 0;
    let diagMissingCharacterNumber = 0;
    let diagMissingUid = 0;
    let diagResolvedViaPcDb = 0;
    for (let start = 0; start < rows.length; start += 400) {
      const slice = rows.slice(start, start + 400);
      for (let idx = 0; idx < slice.length; idx++) {
        const globalRowIndex = start + idx + 2;
        const rowArr = slice[idx];
        const rowObj = toObject(headers, rowArr);
        rowObj._rowNumber = globalRowIndex;
        rowObj._sheet = sheetName;
        diagTotalRows += 1;
        let characterNumberRaw = getFieldValue(rowObj, characterNumberKeys);
        if (characterNumberRaw === null || characterNumberRaw === undefined) characterNumberRaw = '';
        characterNumberRaw = String(characterNumberRaw).trim();
        if (!characterNumberRaw && Array.isArray(rowArr) && rowArr.length > 0) {
          // Fallback: column A (index 0) is the character number per sheet definition
          characterNumberRaw = String(rowArr[0] || '').trim();
        }
        if (!characterNumberRaw) { diagMissingCharacterNumber += 1; continue; }
        const beforeEmail = String(getFieldValue(rowObj, emailKeys) || '').trim();
        const uid = await resolveUid(rowObj, characterNumberRaw);
        if (!beforeEmail && uid) diagResolvedViaPcDb += 1;
        if (!uid) { diagMissingUid += 1; continue; }

        const characterKey = `${uid}_${characterNumberRaw}`;
        if (!characterMirrorMap.has(characterKey)) {
          characterMirrorMap.set(characterKey, { uid, characterNumber: characterNumberRaw, docs: new Map() });
        }
        const entry = characterMirrorMap.get(characterKey);
        const docId = `r${globalRowIndex}`;
        // Keep mirrored data simple: store selected normalized fields plus the raw row for reference
        const email = String(getFieldValue(rowObj, emailKeys) || '').trim();
        const reason = String(getFieldValue(rowObj, ['Advancement Reason', 'AdvancementReason']) || '').trim();
        const dateVal = getFieldValue(rowObj, ['Date', 'date', '_date']);
        const mirrored = {
          _masterLogId: docId,
          _sheet: sheetName,
          _rowNumber: globalRowIndex,
          _syncedAt: new Date().toISOString(),
          playerUid: uid,
          playerEmail: email || null,
          characterNumber: characterNumberRaw,
          advancementReason: reason || null,
          date: dateVal || null,
          data: rowObj
        };
        entry.docs.set(docId, mirrored);
      }
    }

    // For each character touched, delete docs not present and upsert the current ones
    let mirrored = 0;
    let deletedFromCharacters = 0;
    for (const [key, info] of characterMirrorMap.entries()) {
      const { uid, characterNumber, docs } = info;
      const advRef = db.collection('players').doc(uid).collection('characters').doc(String(characterNumber)).collection('advancement');

      // Ensure player and character documents exist (best-effort)
      try {
        const playerDocRef = db.collection('players').doc(uid);
        const playerDoc = await playerDocRef.get();
        if (!playerDoc.exists) {
          await playerDocRef.set({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            uid: uid
          }, { merge: true });
        }

        const charDoc = await playerDocRef.collection('characters').doc(String(characterNumber)).get();
        if (!charDoc.exists) {
          await playerDocRef.collection('characters').doc(String(characterNumber)).set({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            playerUid: uid,
            characterNumber: String(characterNumber)
          }, { merge: true });
        }
      } catch (_) {}

      // Fetch existing advancement doc IDs
      const existingSnap = await advRef.get();
      const existingIds = new Set(existingSnap.docs.map(d => d.id));
      const presentIds = new Set(docs.keys());

      // Delete obsolete
      const toDelete = [];
      for (const id of existingIds) {
        if (!presentIds.has(id)) toDelete.push(id);
      }
      for (let i = 0; i < toDelete.length; i += 450) {
        const batch = db.batch();
        for (let j = i; j < Math.min(i + 450, toDelete.length); j++) {
          batch.delete(advRef.doc(toDelete[j]));
        }
        await batch.commit();
        deletedFromCharacters += Math.min(450, toDelete.length - i);
      }

      // Upsert current docs to match Master Logs exactly
      const toWrite = Array.from(docs.entries());
      for (let i = 0; i < toWrite.length; i += 400) {
        const batch = db.batch();
        const slice = toWrite.slice(i, i + 400);
        for (const [docId, docData] of slice) {
          batch.set(advRef.doc(docId), docData); // overwrite to ensure exact match
          mirrored += 1;
        }
        await batch.commit();
      }
    }

    // Write last sync metadata at Master Logs level
    await db.collection('Master Logs').doc('last_sync').set({
      syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      spreadsheetId,
      sheetName,
      containerDocId,
      cleared,
      written,
      mirrored,
      deletedFromCharacters,
      diagnostics: {
        processedRows: diagTotalRows,
        missingCharacterNumber: diagMissingCharacterNumber,
        missingUid: diagMissingUid,
        resolvedViaPcDb: diagResolvedViaPcDb
      }
    }, { merge: true });

    return res.status(200).json({
      ok: true,
      message: 'Master Logs sync complete',
      spreadsheetId,
      sheetName,
      containerDocId,
      cleared,
      written,
      mirrored,
      deletedFromCharacters,
      diagnostics: {
        processedRows: diagTotalRows,
        missingCharacterNumber: diagMissingCharacterNumber,
        missingUid: diagMissingUid,
        resolvedViaPcDb: diagResolvedViaPcDb
      }
    });
  } catch (error) {
    console.error('Error syncing Master Logs:', error);
    return res.status(500).json({ ok: false, error: error.message });
  }
});
// Calculate per-character advancement summaries (Affinities first)
exports.calculateCharacter = onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  try {
    // Auth: user must be authenticated
    if (!req.headers.authorization) {
      return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    }
    const idToken = req.headers.authorization.split(' ')[1];
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const authenticatedUid = decodedToken.uid;

    // Inputs: playerUid + characterNumber, or characterId in format "{uid}_{characterNumber}"
    const playerUid = (req.query.playerUid || req.body?.playerUid || '').toString();
    const characterNumberInput = (req.query.characterNumber || req.body?.characterNumber || '').toString();
    const characterId = (req.query.characterId || req.body?.characterId || '').toString();
    const debug = String(req.query.debug ?? req.body?.debug ?? 'false').toLowerCase() === 'true';

    let uid = playerUid;
    let characterNumber = characterNumberInput;
    if ((!uid || !characterNumber) && characterId) {
      const parts = characterId.split('_');
      if (parts.length >= 2) {
        uid = parts[0];
        characterNumber = parts.slice(1).join('_');
      }
    }
    if (!uid || !characterNumber) {
      return res.status(400).json({ ok: false, error: 'missing_target', message: 'Provide playerUid and characterNumber or characterId' });
    }

    // Authorization: user can calculate their own characters OR super admin can calculate any character
    const isAdmin = await isSuperAdmin(authenticatedUid);
    const isOwner = (authenticatedUid === uid);
    if (!isOwner && !isAdmin) {
      return res.status(403).json({ ok: false, error: 'insufficient_permissions', message: 'You can only calculate your own characters unless you are a super admin' });
    }

    // Ensure character structure exists before trying to calculate
    console.log(`🏗️ Ensuring character structure exists for player ${uid}, character ${characterNumber}`);
    try {
      await ensureCharacterStructure(uid, String(characterNumber));
      console.log(`✅ Character structure verified/created for ${uid}/${characterNumber}`);
    } catch (structureError) {
      console.error(`❌ Failed to ensure character structure: ${structureError.message}`);
      return res.status(500).json({ 
        ok: false, 
        error: 'structure_initialization_failed', 
        message: `Failed to initialize character structure: ${structureError.message}` 
      });
    }

    // Fetch advancement rows for this character
    const advRef = db.collection('players').doc(uid).collection('characters').doc(String(characterNumber)).collection('advancement');
    const advSnap = await advRef.get();
    const advRowsCount = advSnap.size;
    if (advSnap.empty) {
      return res.status(200).json({ ok: true, message: 'No advancement rows found for character', uid, characterNumber, advRows: 0 });
    }

    // Initialize character calculation error log
    const advancementErrorLog = [];

    // Load Rules multipliers for affinities
    const rulesAffinitiesRef = db.collection('Rules').doc('Affinities').collection('All');
    const rulesSnap = await rulesAffinitiesRef.get();
    const affinityToMultiplier = new Map();
    const knownAffinityNames = [];
    rulesSnap.forEach((doc) => {
      const d = doc.data() || {};
      const name = doc.id;
      const m = Number(d.Multiplier ?? d.multiplier ?? d.Multipler ?? 0); // accept variants
      if (!isNaN(m) && m > 0) affinityToMultiplier.set(name.toLowerCase(), m);
      knownAffinityNames.push(name);
    });

    // Helpers to extract fields from a master log row
    const normalizeKey = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    const getFieldValue = (rowObj, candidates) => {
      for (const cand of candidates) {
        const target = normalizeKey(cand);
        for (const k of Object.keys(rowObj)) {
          if (normalizeKey(k) === target) return rowObj[k];
        }
      }
      return '';
    };

    const reasonKeys = ['Advancement Reason', 'AdvancementReason', 'Reason'];
    const affinityNameKeys = ['Affinty', 'Affinity', 'Affinity Name', 'affinityName', 'Name'];
    const tierKeys = ['Character Cultivation Tier', 'Tier', 'Affinity Tier', 'tier'];
    const levelChangeKeys = ['Affinity Level', 'Level Change', 'levelChange', 'Change', 'Delta', 'Adjustment', 'Adjust Hit Points', 'AdjustHitPoints', 'Hit Points', 'HitPoints'];
    const buildAdjustmentKeys = ['Build Adjustment', 'BuildAdjustment', 'Build Adj', 'BuildAdj', 'Build Change', 'BuildChange', 'Build'];
    const affinityPointAdjustmentKeys = ['Affinity Point Adjustment', 'AffinityPointAdjustment', 'AP Adjustment', 'APAdjustment', 'Affinity Points', 'AffinityPoints', 'AP'];
    const adjustCultivationTierKeys = [
      'Adjust Cultivation Tier',
      'Adjust Cultilation Tier',
      'Adjust Cultication Tier',
      'Adjust Cutlication Tier',
      'Character Cultivation Tier'
    ];

    // Prefer the first non-empty value among a set of candidate field names
    const getFirstNonEmptyFieldValue = (rowObj, candidates) => {
      for (const cand of candidates) {
        const target = normalizeKey(cand);
        for (const k of Object.keys(rowObj)) {
          if (normalizeKey(k) === target) {
            const val = rowObj[k];
            if (val !== null && val !== undefined && String(val).trim() !== '') {
              return val;
            }
          }
        }
      }
      return '';
    };

    const totals = new Map(); // affinityName(lower) -> { name, tiers: { [tier: string]: { Level:number, Cost:number } }, Total:{Level:number, Cost:number} }

    let detectedAffinityRows = 0;
    const skippedSamples = [];
    for (const doc of advSnap.docs) {
      const data = doc.data() || {};
      const row = data.data || data; // mirror rows keep raw under data

      const rawReason = String(getFieldValue(row, reasonKeys) || '').trim().toLowerCase();
      const reasonNorm = rawReason.replace(/[^a-z]/g, '');
      const isAffinityRaise = (reasonNorm === 'rasingaffintylevel' || reasonNorm === 'raisingaffinitylevel');
      if (!isAffinityRaise) { 
        if (debug && skippedSamples.length < 10) skippedSamples.push({ id: doc.id, reason: `reason=${rawReason || 'none'}` }); 
        // Log non-affinity entries for potential processing by other sections
        if (rawReason && reasonNorm !== 'buyinghitpoints' && reasonNorm !== 'buyingskill' && reasonNorm !== 'buyingskills') {
          // Special-case: reason "import" with positive Build Adjustment is handled in the Build section.
          if (reasonNorm === 'import') {
            const rawAdj = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const adj = Number(rawAdj);
            if (!isNaN(adj) && adj > 0) {
              // Considered processed by the Build writer; do not create an error entry
              continue;
            }
          }
          // Special-case: reason "attending event" with positive Build/AP Adjustment is handled in Build/AP section
          if (reasonNorm === 'attendingevent') {
            const rawBuild = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const rawAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
            const build = Number(rawBuild);
            const ap = Number(rawAp);
            if ((!isNaN(build) && build > 0) || (!isNaN(ap) && ap > 0)) {
              continue;
            }
          }
          // Special-case: Character Initialization handled earlier
          if (reasonNorm === 'characterinitialization') {
            const rawBuild = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const rawAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
            const build = Number(rawBuild);
            const ap = Number(rawAp);
            const freeAffinity = String(getFirstNonEmptyFieldValue(row, [...affinityNameKeys, 'Affinity']) || '').trim();
            const hasTier = String(getFirstNonEmptyFieldValue(row, adjustCultivationTierKeys) || '').trim();
            if ((!isNaN(build) && build > 0) || (!isNaN(ap) && ap > 0) || freeAffinity || hasTier) {
              continue;
            }
          }
          // Special-case: Ascend handled earlier
          if (reasonNorm === 'ascend') {
            const ascTier = String(getFirstNonEmptyFieldValue(row, adjustCultivationTierKeys) || '').trim();
            if (ascTier) {
              continue;
            }
          }
          // Special-case: reason "slotting cores" with positive AP is handled in AP section
          if (reasonNorm === 'slottingcores') {
            const rawApOnly = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
            const apOnly = Number(rawApOnly);
            if (!isNaN(apOnly) && apOnly > 0) {
              continue;
            }
          }
          // Special-case: reason "consuming cores" with positive Build Adjustment handled in Build section
          if (reasonNorm === 'consumingcores') {
            const rawBuildOnly = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const buildOnly = Number(rawBuildOnly);
            if (!isNaN(buildOnly) && buildOnly > 0) {
              continue;
            }
          }
          // Special-case: reason "donations" handled in Build/AP section if it has values; otherwise ignore
          if (reasonNorm === 'donations') {
            const rawBuild = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const rawAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
            const build = Number(rawBuild);
            const ap = Number(rawAp);
            if ((!isNaN(build) && build > 0) || (!isNaN(ap) && ap > 0)) {
              continue;
            }
          }
          // Special-case: reason "marshal override" handled in Build/AP section (allows +/-); ignore here
          if (reasonNorm === 'marshaloverride') {
            const rawBuild = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
            const rawAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
            const build = Number(rawBuild);
            const ap = Number(rawAp);
            if ((!isNaN(build) && build !== 0) || (!isNaN(ap) && ap !== 0)) {
              continue;
            }
          }
          // Special-case: reason "free affinity" is ignored entirely
          if (reasonNorm === 'freeaffinity' || reasonNorm === 'freeaffinty') {
            continue;
          }
          // Special-case: reason "Free Affinty after ascending" (and correct-spelling variant) is handled elsewhere; ignore without error
          if (reasonNorm === 'freeaffintyafterascending' || reasonNorm === 'freeaffinityafterascending') {
            continue;
          }
          console.log(`⚠️ Unrecognized reason in affinity section: Doc ${doc.id}: reason="${rawReason}" normalized="${reasonNorm}"`);
          advancementErrorLog.push({
            docId: doc.id,
            masterLogId: data._masterLogId || 'unknown',
            rowNumber: data._rowNumber || 'unknown',
            reason: rawReason,
            issue: 'unrecognized_advancement_reason',
            details: `Reason "${rawReason}" (normalized: "${reasonNorm}") is not recognized as affinity, skill, or hit point advancement`,
            timestamp: new Date().toISOString()
          });
        }
        continue; 
      }
      let affinityNameRaw = String(getFirstNonEmptyFieldValue(row, [...affinityNameKeys, 'Affinity Purchased', 'Affinity Purchased Name']) || '').trim();
      if (!affinityNameRaw) {
        // Heuristic: search for any known affinity name present in row values
        const joinedValues = Object.values(row).map(v => String(v || '')).join(' ').toLowerCase();
        const found = knownAffinityNames.find(n => joinedValues.includes(String(n).toLowerCase()));
        if (found) affinityNameRaw = found;
      }
      if (!affinityNameRaw) { 
        if (debug && skippedSamples.length < 10) skippedSamples.push({ id: doc.id, reason: 'no_affinity_name' }); 
        advancementErrorLog.push({
          docId: doc.id,
          masterLogId: data._masterLogId || 'unknown',
          rowNumber: data._rowNumber || 'unknown',
          reason: rawReason,
          issue: 'missing_affinity_name',
          details: `Affinity advancement missing affinity name. Looked for fields: ${affinityNameKeys.join(', ')}`,
          timestamp: new Date().toISOString()
        });
        continue; 
      }
      // Reason already filtered; no further type checks needed

      let tier = String(getFirstNonEmptyFieldValue(row, [...tierKeys, 'Character Tier', 'Cultivation Tier'])) .trim();
      if (!tier) {
        // Attempt to infer tier from other fields (very loose)
        const joined = JSON.stringify(row).toLowerCase();
        if (joined.includes('iron')) tier = 'Iron';
        else if (joined.includes('silver')) tier = 'Silver';
        else if (joined.includes('gold')) tier = 'Gold';
      }
      // Normalize tier to Title Case
      const tierNorm = tier ? (tier.charAt(0).toUpperCase() + tier.slice(1).toLowerCase()) : null;
      if (!tierNorm) { 
        if (debug && skippedSamples.length < 10) skippedSamples.push({ id: doc.id, reason: `no_tier` }); 
        advancementErrorLog.push({
          docId: doc.id,
          masterLogId: data._masterLogId || 'unknown',
          rowNumber: data._rowNumber || 'unknown',
          reason: rawReason,
          issue: 'missing_tier',
          details: `Affinity advancement for "${affinityNameRaw}" missing tier information. Looked for fields: ${tierKeys.join(', ')}`,
          timestamp: new Date().toISOString()
        });
        continue; 
      }

      let delta = Number(getFieldValue(row, levelChangeKeys));
      if (isNaN(delta)) delta = 1; // default to +1 per row if unspecified
      if (delta <= 0) {
        advancementErrorLog.push({
          docId: doc.id,
          masterLogId: data._masterLogId || 'unknown',
          rowNumber: data._rowNumber || 'unknown',
          reason: rawReason,
          issue: 'zero_or_negative_affinity_change',
          details: `Affinity advancement for "${affinityNameRaw}" (${tierNorm}) has zero or negative change: ${delta}. No data modified.`,
          timestamp: new Date().toISOString()
        });
        continue; // ignore reductions for now
      }

      const key = affinityNameRaw.toLowerCase();
      if (!totals.has(key)) {
        totals.set(key, {
          name: affinityNameRaw,
          tiers: {},
          Total: { Level: 0, Cost: 0 }
        });
      }
      const agg = totals.get(key);
      if (!agg.tiers[tierNorm]) agg.tiers[tierNorm] = { Level: 0, Cost: 0 };
      agg.tiers[tierNorm].Level += delta;
      agg.Total.Level += delta;
      detectedAffinityRows += 1;
    }

    // Load character free affinity for per-tier first-level-free rule
    const charRootRef = db.collection('players').doc(uid).collection('characters').doc(String(characterNumber));
    let freeAffinityName = '';
    let characterCultivationTier = '';
    try {
      const cSnap = await charRootRef.get();
      const cData = cSnap.exists ? (cSnap.data() || {}) : {};
      freeAffinityName = String(cData.free_affinity || cData.freeAffinity || '').trim();
      characterCultivationTier = String(cData.cultivationTier || '').trim();
    } catch (_) {}

    // Add free levels for the free affinity based on character's cultivation tier
    if (freeAffinityName && characterCultivationTier) {
      const tierOrder = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
      const currentTierIndex = tierOrder.findIndex(t => t.toLowerCase() === characterCultivationTier.toLowerCase());
      
      if (currentTierIndex >= 0) {
        const freeAffinityKey = freeAffinityName.toLowerCase();
        
        // Ensure free affinity entry exists in totals
        if (!totals.has(freeAffinityKey)) {
          totals.set(freeAffinityKey, {
            name: freeAffinityName,
            tiers: {},
            Total: { Level: 0, Cost: 0 }
          });
        }
        
        const freeAgg = totals.get(freeAffinityKey);
        
        // Add +1 free level for each tier from Iron up to current tier
        for (let i = 0; i <= currentTierIndex; i++) {
          const tierName = tierOrder[i];
          if (!freeAgg.tiers[tierName]) freeAgg.tiers[tierName] = { Level: 0, Cost: 0 };
          freeAgg.tiers[tierName].Level += 1; // Add 1 free level
          freeAgg.Total.Level += 1; // Add to total
        }
        
        console.log(`🎁 Added free ${freeAffinityName} levels: ${currentTierIndex + 1} levels (Iron to ${characterCultivationTier})`);
      }
    }

    // Compute costs using multiplier and triangular numbers per tier (minus free first level per tier if matches free_affinity)
    const triangular = (n) => (n <= 0 ? 0 : (n * (n + 1)) / 2);
    for (const [key, agg] of totals.entries()) {
      const m = affinityToMultiplier.get(key) || affinityToMultiplier.get(agg.name.toLowerCase()) || 1;
      let totalCost = 0;
      for (const t of Object.keys(agg.tiers)) {
        const n = Number(agg.tiers[t].Level || 0); // purchased levels in this tier
        let cost;
        if (freeAffinityName && String(agg.name || '').toLowerCase() === freeAffinityName.toLowerCase()) {
          // Free level is granted per tier, so cost is triangular(n + 1) - triangular(1) = triangular(n + 1) - 1
          cost = Math.round(m * (triangular(n + 1) - 1));
        } else {
          cost = Math.round(m * triangular(n));
        }
        agg.tiers[t].Cost = cost;
        totalCost += cost;
      }
      agg.Total.Cost = totalCost;
    }

    // Write results under character root: characters/{characterNumber}/affinities/{AffinityName}/tiers/{Tier}
    // First, clear existing calculated affinity docs for a clean slate
    const charDocRef = charRootRef;
    const affinitiesCol = charDocRef.collection('affinities');
    // Clear previous advancement error log for this character at start of calculation
    try {
      await charDocRef.collection('errors').doc('advancement').delete();
    } catch (_) {}
    try {
      const existingAffDocs = await affinitiesCol.get();
      for (const affDoc of existingAffDocs.docs) {
        const tiersSnap = await affDoc.ref.collection('tiers').get();
        for (let i = 0; i < tiersSnap.docs.length; i += 450) {
          const batch = db.batch();
          for (let j = i; j < Math.min(i + 450, tiersSnap.docs.length); j++) {
            batch.delete(tiersSnap.docs[j].ref);
          }
          await batch.commit();
        }
        await affDoc.ref.delete();
      }
    } catch (_) {}

    let written = 0;
    for (const [, agg] of totals.entries()) {
      const sanitizedAffinityName = sanitizeDocIdLocal(agg.name, agg.name);
      const affDocRef = affinitiesCol.doc(sanitizedAffinityName);
      await affDocRef.set({ name: agg.name, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      // Write encountered tiers only
      for (const t of Object.keys(agg.tiers)) {
        const docRef = affDocRef.collection('tiers').doc(t);
        const payload = { Level: agg.tiers[t].Level || 0, Cost: agg.tiers[t].Cost || 0, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
        await docRef.set(payload, { merge: true });
        written += 1;
      }
      // Write Total
      {
        const docRef = affDocRef.collection('tiers').doc('Total');
        const payload = { Level: agg.Total.Level || 0, Cost: agg.Total.Cost || 0, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
        await docRef.set(payload, { merge: true });
        written += 1;
      }
    }

    // ========== Skills Calculation ==========
    // Collect skill increments from advancement
    const skillReasonKeys = ['Advancement Reason', 'AdvancementReason', 'Reason'];
    const skillNameKeys = ['Skill'];
    const skillLevelAdjKeys = ['Skill Level Adj', 'SkillLevelAdj', 'Level Adj', 'Level Adjustment'];
    const skillTypeKeys = ['Skill Type', 'SkillType', 'Type'];

    const skillsTotals = new Map(); // type -> Map(name->levels)
    let detectedSkillRows = 0;
    for (const doc of advSnap.docs) {
      const data = doc.data() || {};
      const row = data.data || data;
      const rawReason = String(getFieldValue(row, skillReasonKeys) || '').trim().toLowerCase();
      const norm = rawReason.replace(/[^a-z]/g, '');
      if (!(norm === 'buyingskill' || norm === 'buyingskills' || norm === 'illuionaryrace' || norm === 'illusionaryrace')) continue;
      // Illuionary Race handling (typo accepted): must be a Race skill
      if (norm === 'illuionaryrace' || norm === 'illusionaryrace') {
        const skillTypeVal = String(getFieldValue(row, skillTypeKeys) || '').trim();
        if (skillTypeVal.toLowerCase() !== 'race') {
          advancementErrorLog.push({
            docId: doc.id,
            masterLogId: data._masterLogId || 'unknown',
            rowNumber: data._rowNumber || 'unknown',
            reason: rawReason,
            issue: 'illusionary_race_not_race_type',
            details: `Illusionary Race must have Skill Type 'Race'. Found: '${skillTypeVal}'`,
            timestamp: new Date().toISOString()
          });
          continue;
        }
      }
      const skillName = String(getFieldValue(row, skillNameKeys) || '').trim();
      if (!skillName) {
        advancementErrorLog.push({
          docId: doc.id,
          masterLogId: data._masterLogId || 'unknown',
          rowNumber: data._rowNumber || 'unknown',
          reason: rawReason,
          issue: 'missing_skill_name',
          details: `Skill advancement missing skill name. Looked for fields: ${skillNameKeys.join(', ')}`,
          timestamp: new Date().toISOString()
        });
        continue;
      }
      const skillType = String(getFieldValue(row, skillTypeKeys) || '').trim() || 'Unknown';
      let adj = Number(getFieldValue(row, skillLevelAdjKeys));
      if (isNaN(adj)) adj = 1;
      if (adj <= 0) {
        advancementErrorLog.push({
          docId: doc.id,
          masterLogId: data._masterLogId || 'unknown',
          rowNumber: data._rowNumber || 'unknown',
          reason: rawReason,
          issue: 'zero_or_negative_skill_change',
          details: `Skill advancement for "${skillName}" (${skillType}) has zero or negative change: ${adj}. No data modified.`,
          timestamp: new Date().toISOString()
        });
        continue;
      }
      if (!skillsTotals.has(skillType)) skillsTotals.set(skillType, new Map());
      const byName = skillsTotals.get(skillType);
      byName.set(skillName, (byName.get(skillName) || 0) + adj);
      detectedSkillRows += 1;
    }

    // Helper to sanitize doc ids similar to syncRulesDb
    const sanitizeDocIdLocal = (name, fallback) => {
      try {
        let id = String(name || '').trim();
        if (!id) return fallback;
        // Match syncRulesDb behavior: replace '/' and collapse whitespace
        id = id.replace(/\//g, ' - ');
        id = id.replace(/\s+/g, ' ').trim();
        if (id.length > 1500) id = id.substring(0, 1500);
        return id;
      } catch (_) { return fallback; }
    };

    // Load character for race
    const charDoc = await charDocRef.get();
    const characterRace = (charDoc.exists ? ((charDoc.data() || {}).race || (charDoc.data() || {}).Race) : '') || '';

    // For each skill, look up base Build cost and compute total cost
    const skillsRoot = charDocRef.collection('skills');
    // Clear existing skills tree
    try {
      const existingTypes = await skillsRoot.get();
      for (const typeDoc of existingTypes.docs) {
        const itemsSnap = await typeDoc.ref.listCollections();
        for (const sub of itemsSnap) {
          const docs = await sub.get();
          for (let i = 0; i < docs.docs.length; i += 450) {
            const batch = db.batch();
            for (let j = i; j < Math.min(i + 450, docs.docs.length); j++) batch.delete(docs.docs[j].ref);
            await batch.commit();
          }
        }
        await typeDoc.ref.delete();
      }
    } catch (_) {}

    let totalSkillsCost = 0;
    const rulesSkillsDoc = db.collection('Rules').doc('Skills');
    const skillsErrorLog = [];

    // Preload Common skills to build a case-insensitive index by Name and by doc id
    const commonIndexByName = new Map();
    const commonIndexById = new Map();
    try {
      const commonSnap = await rulesSkillsDoc.collection('Common').get();
      for (const d of commonSnap.docs) {
        const data = d.data() || {};
        const name = String(data.Name || d.id || '').trim();
        const build = Number(data.Build || 0) || 0;
        commonIndexById.set(d.id.toLowerCase(), build);
        if (name) commonIndexByName.set(name.toLowerCase(), build);
      }
    } catch (_) {}

    const computeSkillCost = (base, levels) => {
      if (!levels || levels <= 0 || !base || base <= 0) return 0;
      let total = base; // Level 1 costs full base
      for (let k = 1; k < levels; k++) {
        // Each subsequent level costs (base - k), but cannot drop below 1
        total += Math.max(1, base - k);
      }
      return total;
    };

    for (const [skillType, byName] of skillsTotals.entries()) {
      const sanitizedSkillType = sanitizeDocIdLocal(skillType, skillType);
      const typeDocRef = skillsRoot.doc(sanitizedSkillType);
      await typeDocRef.set({ type: skillType, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      const itemsCol = typeDocRef.collection('items');

      for (const [skillName, levels] of byName.entries()) {
        let baseBuild = 0;
        let resolvedFrom = null;
        const skillId = sanitizeDocIdLocal(skillName, skillName);
        if (debug) console.log(`🔍 Looking for skill "${skillName}" with sanitized ID "${skillId}"`);
        // Try Common first by doc id, then by Name (case-insensitive index)
        try {
          const docRef = rulesSkillsDoc.collection('Common').doc(skillId);
          const snap = await docRef.get();
          if (debug) console.log(`📋 Common doc "${skillId}" exists: ${snap.exists}`);
          if (snap.exists) {
            const data = snap.data() || {};
            if (debug) console.log(`📊 Common doc "${skillId}" data:`, data);
            const fromDoc = Number((snap.data() || {}).Build || 0);
            if (debug) console.log(`💰 Build value for "${skillId}": ${fromDoc}`);
            if (Number.isFinite(fromDoc) && fromDoc >= 0) { baseBuild = fromDoc; resolvedFrom = { category: 'Common', id: skillId }; }
            else {
              // record that doc exists but Build missing
              skillsErrorLog.push({ skillName, skillType, reason: 'build_missing_in_common_doc', docId: skillId });
            }
          }
        } catch (_) {}
        // Fallback: query by Name in Common
        if (!baseBuild && baseBuild !== 0) {
          const byIdLower = commonIndexById.get(skillId.toLowerCase());
          const byNameLower = commonIndexByName.get(String(skillName).toLowerCase());
          if (debug) console.log(`🔎 Index lookup for "${skillName}": byId=${byIdLower}, byName=${byNameLower}`);
          if (byIdLower !== undefined) { baseBuild = byIdLower; resolvedFrom = { category: 'CommonIndex', id: skillId }; }
          else if (byNameLower !== undefined) { baseBuild = byNameLower; resolvedFrom = { category: 'CommonIndex', name: skillName }; }
        }
        // If not found, try Affinity subcollection using known affinities or skillType
        if (!baseBuild) {
          const candidateAffinities = new Set([skillType, ...knownAffinityNames]);
          for (const aff of candidateAffinities) {
            try {
              const docRef = rulesSkillsDoc.collection(String(aff)).doc(skillId);
              const snap = await docRef.get();
              if (snap.exists) { baseBuild = Number((snap.data() || {}).Build || 0); if (baseBuild) { resolvedFrom = { category: 'Affinity', affinity: String(aff), id: skillId }; break; } }
            } catch (_) {}
            if (!baseBuild) {
              try {
                const q = await rulesSkillsDoc.collection(String(aff)).where('Name', '==', String(skillName)).limit(1).get();
                if (!q.empty) { baseBuild = Number((q.docs[0].data() || {}).Build || 0); if (baseBuild) { resolvedFrom = { category: 'Affinity', affinity: String(aff), name: skillName }; break; } }
              } catch (_) {}
            }
          }
        }
        // If still not found, try Races filtered by race and name
        if (!baseBuild) {
          try {
            const q = await rulesSkillsDoc.collection('Races')
              .where('Race', '==', String(characterRace))
              .where('Name', '==', String(skillName))
              .limit(1).get();
            if (!q.empty) { baseBuild = Number((q.docs[0].data() || {}).Build || 0); if (baseBuild) resolvedFrom = { category: 'Races', race: characterRace, name: skillName }; }
          } catch (_) {}
        }

        // If baseBuild still not found (undefined), record error details
        if (baseBuild === undefined || (baseBuild === 0 && resolvedFrom === null)) {
          const tried = [];
          tried.push({ category: 'Common', id: skillId });
          tried.push({ category: 'Affinity', candidates: [skillType, ...knownAffinityNames] });
          tried.push({ category: 'Races', race: characterRace, name: skillName });
          skillsErrorLog.push({ skillName, skillType, reason: 'base_build_not_found', tried });
        }

        const cost = computeSkillCost(baseBuild, Number(levels || 0));
        totalSkillsCost += cost;
        await itemsCol.doc(skillName).set({ Name: skillName, Level: Number(levels || 0), Cost: cost, BaseBuild: baseBuild, ResolvedFrom: resolvedFrom || null, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      }
    }

    await skillsRoot.doc('Total').set({ Cost: totalSkillsCost, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    
    // Write errors to centralized location: Errors > Character Calculation > {Character Number} > skills
    if (skillsErrorLog.length > 0) {
      const errorsRef = db.collection('Errors').doc('Character Calculation').collection(String(characterNumber)).doc('skills');
      await errorsRef.set({ entries: skillsErrorLog, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    } else {
      // Clear old error log if present
      try { 
        await db.collection('Errors').doc('Character Calculation').collection(String(characterNumber)).doc('skills').delete();
      } catch (_) {}
    }

    // === ESSENCE CALCULATION ===
    // 1. Base essence: 5 for all characters
    let baseEssence = 5;
    let hitPointsFromAdvancements = 0;
    let bodyEssenceByTier = {};
    let detectedHitPointRows = 0;
    let detectedBodyAffinityRows = 0;

    // 2.a Process Build/AP adjustments (Import, Attending Event) and Ascend
    let totalBuildAdjustment = 0;
    let totalAffinityPointAdjustment = 0;
    const buildColRef = charDocRef.collection('build');
    const affinityPointsColRef = charDocRef.collection('affinity_points');
    const ascendColRef = charDocRef.collection('ascend');
    try {
      // Clear previous non-total build docs (keep or overwrite total later)
      const existingBuild = await buildColRef.get();
      for (const d of existingBuild.docs) {
        if (d.id !== 'Total') {
          await d.ref.delete();
        }
      }
    } catch (_) {}
    try {
      // Clear previous non-total affinity point docs
      const existingAp = await affinityPointsColRef.get();
      for (const d of existingAp.docs) {
        if (d.id !== 'Total') {
          await d.ref.delete();
        }
      }
    } catch (_) {}
    try {
      // Clear previous ascend entries except 'current'
      const existingAsc = await ascendColRef.get();
      for (const d of existingAsc.docs) {
        if (d.id !== 'current') {
          await d.ref.delete();
        }
      }
    } catch (_) {}

    // Track highest ascended tier value from Adjust Cultivation Tier
    const tierOrder = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    const tierRank = (t) => { const idx = tierOrder.indexOf(String(t)); return idx >= 0 ? idx : -1; };
    let highestAscTier = null;

    for (const doc of advSnap.docs) {
      const data = doc.data() || {};
      const row = data.data || data;
      const rawReason = String(getFieldValue(row, reasonKeys) || '').trim().toLowerCase();
      const reasonNorm = rawReason.replace(/[^a-z]/g, '');
      // Character Initialization: seed free affinity, positive Build/AP, optional cultivation tier
      if (reasonNorm === 'characterinitialization') {
        // Free affinity: store on character doc
        const freeAffinity = String(getFirstNonEmptyFieldValue(row, [...affinityNameKeys, 'Affinity']) || '').trim();
        if (freeAffinity) {
          await charDocRef.set({ free_affinity: freeAffinity }, { merge: true });
        }
        // Positive Build
        const rawInitBuild = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
        const initBuild = Number(rawInitBuild);
        if (!isNaN(initBuild) && initBuild > 0) {
          totalBuildAdjustment += initBuild;
          await buildColRef.doc(data._masterLogId || doc.id).set({
            amount: initBuild,
            source: 'Character Initialization',
            rowNumber: data._rowNumber || null,
            masterLogId: data._masterLogId || doc.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        // Positive AP
        const rawInitAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
        const initAp = Number(rawInitAp);
        if (!isNaN(initAp) && initAp > 0) {
          totalAffinityPointAdjustment += initAp;
          await affinityPointsColRef.doc(data._masterLogId || doc.id).set({
            amount: initAp,
            source: 'Character Initialization',
            rowNumber: data._rowNumber || null,
            masterLogId: data._masterLogId || doc.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        // Optional cultivation tier
        const newTier = String(getFirstNonEmptyFieldValue(row, adjustCultivationTierKeys) || '').trim();
        if (newTier) {
          await charDocRef.set({ cultivationTier: newTier }, { merge: true });
        }
        continue;
      }
      // Slotting Cores: AP only
      if (reasonNorm === 'slottingcores') {
        const rawApOnly = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
        const apOnly = Number(rawApOnly);
        if (!isNaN(apOnly) && apOnly > 0) {
          totalAffinityPointAdjustment += apOnly;
          await affinityPointsColRef.doc(data._masterLogId || doc.id).set({
            amount: apOnly,
            source: 'Slotting Cores',
            rowNumber: data._rowNumber || null,
            masterLogId: data._masterLogId || doc.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        continue;
      }

      if (reasonNorm === 'import' || reasonNorm === 'attendingevent' || reasonNorm === 'consumingcores' || reasonNorm === 'donations' || reasonNorm === 'marshaloverride') {
        const rawAdj = getFirstNonEmptyFieldValue(row, buildAdjustmentKeys);
        const adj = Number(rawAdj);
        const isMarshal = reasonNorm === 'marshaloverride';
        const isDonations = reasonNorm === 'donations';
        const isImport = reasonNorm === 'import';
        const isAttend = reasonNorm === 'attendingevent';
        const isConsume = reasonNorm === 'consumingcores';

        // Build: marshaloverride allows positive or negative (non-zero). Others positive only. consumingcores is build-only.
        if (!isNaN(adj) && ((isMarshal && adj !== 0) || (!isMarshal && adj > 0)) && reasonNorm !== 'slottingcores') {
          totalBuildAdjustment += adj;
          await buildColRef.doc(data._masterLogId || doc.id).set({
            amount: adj,
            source: isMarshal ? 'Marshal Override' : (isDonations ? 'Donations' : (isImport ? 'Import' : (isAttend ? 'Attending Event' : 'Consuming Cores'))),
            rowNumber: data._rowNumber || null,
            masterLogId: data._masterLogId || doc.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        // Affinity Points: skip for consumingcores. marshaloverride allows non-zero; others positive only
        if (!isConsume) {
          const rawAp = getFirstNonEmptyFieldValue(row, affinityPointAdjustmentKeys);
          const ap = Number(rawAp);
          if (!isNaN(ap) && ((isMarshal && ap !== 0) || (!isMarshal && ap > 0))) {
            totalAffinityPointAdjustment += ap;
            await affinityPointsColRef.doc(data._masterLogId || doc.id).set({
              amount: ap,
              source: isMarshal ? 'Marshal Override' : (isDonations ? 'Donations' : (isImport ? 'Import' : 'Attending Event')),
              rowNumber: data._rowNumber || null,
              masterLogId: data._masterLogId || doc.id,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
        }
      }

      // Ascend: record entry, compute highest tier, optionally AP/Build ignored here
      if (reasonNorm === 'ascend') {
        // Explicitly prefer the Adjust* field over Character Cultivation Tier
        let ascendTierRaw = String(getFirstNonEmptyFieldValue(row, ['Adjust Cultivation Tier','Adjust Cultilation Tier','Adjust Cultication Tier','Adjust Cutlication Tier']) || '').trim();
        if (!ascendTierRaw) {
          // fallback only if no explicit Adjust* present
          ascendTierRaw = String(getFirstNonEmptyFieldValue(row, ['Character Cultivation Tier']) || '').trim();
        }
        const ascendTier = ascendTierRaw ? (ascendTierRaw.charAt(0).toUpperCase() + ascendTierRaw.slice(1).toLowerCase()) : '';
        if (ascendTier) {
          const rank = tierRank(ascendTier);
          // choose the highest tier encountered in this run
          if (highestAscTier === null || rank > tierRank(highestAscTier)) { highestAscTier = ascendTier; }
        }

        await ascendColRef.doc(data._masterLogId || doc.id).set({
          tier: ascendTier || null,
          rowNumber: data._rowNumber || null,
          masterLogId: data._masterLogId || doc.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        continue;
      }
    }

    // Write Build total
    await buildColRef.doc('Total').set({
      amount: totalBuildAdjustment,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Write Affinity Points total
    await affinityPointsColRef.doc('Total').set({
      amount: totalAffinityPointAdjustment,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Write Ascend current + apply effects
    if (highestAscTier) {
      await ascendColRef.doc('current').set({
        tier: highestAscTier,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Upgrade character cultivation tier if higher
      try {
        const charSnap = await charDocRef.get();
        const currentTier = (charSnap.exists ? (charSnap.data().cultivationTier || '') : '') || '';
        const currentRank = tierRank(currentTier);
        if (tierRank(highestAscTier) > currentRank) {
          await charDocRef.set({ cultivationTier: highestAscTier }, { merge: true });
        }
      } catch (_) {}

      // Free affinity +1 level on ascend
      try {
        const charSnap = await charDocRef.get();
        const freeAffinity = (charSnap.exists ? (charSnap.data().free_affinity || '') : '') || '';
        if (freeAffinity) {
          const sanitizedFreeAffinity = sanitizeDocIdLocal(freeAffinity, freeAffinity);
          const affDocRef = charDocRef.collection('affinities').doc(sanitizedFreeAffinity);
          // Increment Total level by 1 with cost 0
          const totalRef = affDocRef.collection('tiers').doc('Total');
          const totalSnap = await totalRef.get();
          const currentLevel = Number((totalSnap.data() || {}).Level || 0) || 0;
          await affDocRef.set({ name: freeAffinity, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
          await totalRef.set({ Level: currentLevel + 1, Cost: Number((totalSnap.data() || {}).Cost || 0), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        }
      } catch (_) {}
    }
    // 2.b Process "Buying Hit Points" advancements 
    console.log(`🔋 Starting essence/hit point processing loop with ${advSnap.docs.length} documents`);
    const allDocIds = advSnap.docs.map(doc => doc.id);
    console.log(`🔋 All document IDs: ${allDocIds.join(', ')}`);
    console.log(`🔋 Looking for r151 and r162: r151=${allDocIds.includes('r151')}, r162=${allDocIds.includes('r162')}`);
    for (const doc of advSnap.docs) {
      const data = doc.data() || {};
      const row = data.data || data;
      
      const rawReason = String(getFieldValue(row, reasonKeys) || '').trim().toLowerCase();
      const reasonNorm = rawReason.replace(/[^a-z]/g, '');
      
      // Debug logging for essence processing - show ALL docs
      console.log(`🔋 Essence loop - Processing doc ${doc.id}: reason="${rawReason}" normalized="${reasonNorm}"`);
      
      if (reasonNorm === 'buyinghitpoints') {
        console.log(`🎯 Hit point entry found! Doc ${doc.id}`);
        console.log(`🎯 Available fields: ${JSON.stringify(Object.keys(row))}`);
        console.log(`🎯 Row data: ${JSON.stringify(row)}`);
        console.log(`🎯 Looking for fields: ${levelChangeKeys.join(', ')}`);
        
        // Use first non-empty among all possible HP fields
        let hpGainRaw = getFirstNonEmptyFieldValue(row, ['Adjust Hit Points', 'Hit Points', 'Adjustment', 'Delta', 'Change', 'Level Change', 'levelChange']);
        if (hpGainRaw === '' || hpGainRaw === null || hpGainRaw === undefined) {
          // Fallback to generic getFieldValue just in case
          hpGainRaw = getFieldValue(row, levelChangeKeys);
        }
        console.log(`🎯 Found hit point value: "${hpGainRaw}"`);
        
        // Debug each field individually
        for (const field of levelChangeKeys) {
          const value = getFieldValue(row, [field]);
          console.log(`🎯 Field "${field}": "${value}"`);
        }
        
        const hpGain = Number(hpGainRaw);
        
        if (isNaN(hpGain) || hpGain === null || hpGain === undefined) {
          // Missing or invalid hit point field
          advancementErrorLog.push({
            docId: doc.id,
            masterLogId: data._masterLogId || 'unknown',
            rowNumber: data._rowNumber || 'unknown',
            reason: rawReason,
            issue: 'missing_hit_point_value',
            details: `Hit point advancement missing or invalid value: "${hpGainRaw}". Looked for fields: ${levelChangeKeys.join(', ')}`,
            timestamp: new Date().toISOString()
          });
        } else if (hpGain <= 0) {
          // Zero or negative hit point value
          advancementErrorLog.push({
            docId: doc.id,
            masterLogId: data._masterLogId || 'unknown',
            rowNumber: data._rowNumber || 'unknown',
            reason: rawReason,
            issue: 'zero_or_negative_hit_point_value',
            details: `Hit point advancement has zero or negative value: ${hpGain}. No data modified.`,
            timestamp: new Date().toISOString()
          });
        } else {
          // Valid hit point gain
          hitPointsFromAdvancements += hpGain;
          detectedHitPointRows += 1;
        }
      }
    }

    // 3. Calculate Body affinity essence contribution
    // Prefer freshly calculated totals; if absent, fall back to stored affinities under the character
    const bodyAffinityKey = 'body';
    let bodyLevelsByTier = {};
    if (totals.has(bodyAffinityKey)) {
      const bodyAgg = totals.get(bodyAffinityKey);
      for (const [tier, tierData] of Object.entries(bodyAgg.tiers)) {
        const bodyLevel = Number(tierData.Level || 0);
        if (bodyLevel > 0) bodyLevelsByTier[tier] = bodyLevel;
      }
    }
    // Fallback: read from Firestore if not present in this run
    if (Object.keys(bodyLevelsByTier).length === 0) {
      try {
        const sanitizedBodyName = sanitizeDocIdLocal('Body', 'Body');
        const bodyDoc = await charDocRef.collection('affinities').doc(sanitizedBodyName).get();
        if (bodyDoc.exists) {
          const tiersSnap = await bodyDoc.ref.collection('tiers').get();
          tiersSnap.forEach(d => {
            const data = d.data() || {};
            const level = Number((data.Level ?? data.level ?? 0)) || 0;
            if (level > 0) bodyLevelsByTier[d.id] = level; // d.id expected to be tier name (e.g., "Silver")
          });
        }
      } catch (_) {}
    }

    // Load Body Essence - DR values from Rules (supports multiple key names)
    const bodyEssenceRef = db.collection('Rules').doc('Body Essence - DR').collection('All');
    const bodyEssenceSnap = await bodyEssenceRef.get();
    const bodyEssenceData = new Map(); // level -> essence value

    bodyEssenceSnap.forEach((doc) => {
      const data = doc.data() || {};
      const docId = doc.id; // Should be like "Body 1", "Body 2", etc.
      const level = Number(String(docId).replace(/[^0-9]/g, '') || 0);
      const essenceValue = (
        data['Essence gain'] ??
        data['Essence gain:'] ??
        data['Essence Gain'] ??
        data['Essence Gain:'] ??
        data['Essence/Hit Points'] ??
        data['Essence / Hit Points'] ??
        data.Essence ??
        data.essence ??
        0
      );
      const essence = Number(essenceValue) || 0;
      if (level > 0 && essence >= 0) {
        bodyEssenceData.set(level, essence);
      }
    });

    // Calculate cumulative Body essence for each tier using gathered body levels
    for (const [tier, bodyLevelRaw] of Object.entries(bodyLevelsByTier)) {
      const bodyLevel = Number(bodyLevelRaw) || 0;
      if (bodyLevel <= 0) continue;
      let tierEssence = 0;
      for (let lvl = 1; lvl <= bodyLevel; lvl++) {
        tierEssence += Number(bodyEssenceData.get(lvl) || 0);
      }
      bodyEssenceByTier[tier] = {
        Level: bodyLevel,
        Essence: tierEssence
      };
      detectedBodyAffinityRows += bodyLevel;
    }

    // 4. Calculate total essence
    const totalBodyEssence = Object.values(bodyEssenceByTier).reduce((sum, tier) => sum + (tier.Essence || 0), 0);
    const totalEssence = baseEssence + hitPointsFromAdvancements + totalBodyEssence;

    // 5. Store essence data at character level
    const essenceData = {
      base: baseEssence,
      hitPointsFromAdvancements,
      bodyEssenceByTier,
      total: totalEssence,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    const essenceRef = charDocRef.collection('essence').doc('summary');
    await essenceRef.set(essenceData, { merge: true });

    // Record last_sync for advancement calculations
    try {
      await charDocRef.collection('advancement').doc('last_sync').set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    } catch (_) {}

    // Write advancement error log per character: players/{uid}/characters/{characterNumber}/errors
    if (advancementErrorLog.length > 0) {
      const errorsRef = charDocRef.collection('errors').doc('advancement');
      await errorsRef.set({ 
        entries: advancementErrorLog, 
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        totalErrors: advancementErrorLog.length,
        summary: {
          unrecognized_reasons: advancementErrorLog.filter(e => e.issue === 'unrecognized_advancement_reason').length,
          missing_affinity_names: advancementErrorLog.filter(e => e.issue === 'missing_affinity_name').length,
          missing_tiers: advancementErrorLog.filter(e => e.issue === 'missing_tier').length,
          missing_skill_names: advancementErrorLog.filter(e => e.issue === 'missing_skill_name').length,
          missing_hit_point_values: advancementErrorLog.filter(e => e.issue === 'missing_hit_point_value').length,
          zero_or_negative_affinity_changes: advancementErrorLog.filter(e => e.issue === 'zero_or_negative_affinity_change').length,
          zero_or_negative_skill_changes: advancementErrorLog.filter(e => e.issue === 'zero_or_negative_skill_change').length,
          zero_or_negative_hit_point_values: advancementErrorLog.filter(e => e.issue === 'zero_or_negative_hit_point_value').length
        }
      }, { merge: true });
    } else {
      // Clear old error log if present
      try { 
        await charDocRef.collection('errors').doc('advancement').delete();
      } catch (_) {}
    }

    return res.status(200).json({ 
      ok: true, 
      uid, 
      characterNumber, 
      advRows: advRowsCount, 
      detectedAffinityRows, 
      affinitiesCalculated: written, 
      affinityCount: totals.size, 
      detectedSkillRows, 
      detectedHitPointRows,
      detectedBodyAffinityRows,
      essenceCalculated: {
        base: baseEssence,
        hitPoints: hitPointsFromAdvancements,
        bodyEssence: totalBodyEssence,
        total: totalEssence
      },
      advancementErrors: advancementErrorLog.length,
      debug: debug ? { skippedSamples, advancementErrors: advancementErrorLog } : undefined 
    });
  } catch (error) {
    console.error('calculateCharacter error', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

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
      playerNumber: characterData.characterNumber || characterData.playerNumber || 0,
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

// Check per-event or global check-in permission
async function hasCheckInPermission(uid, eventId) {
  try {
    // Global permission
    const globalDoc = await db.collection('roles').doc('checkin').collection('global').doc(uid).get();
    if (globalDoc.exists) return true;
    if (eventId) {
      const evDoc = await db.collection('roles').doc('checkin').collection('events').doc(eventId).collection('members').doc(uid).get();
      if (evDoc.exists) return true;
    }
  } catch (error) {
    console.error('Error checking check-in permission:', error);
  }
  return false;
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

    // Check if user is super admin or has explicit check-in permission
    const isAdmin = await isSuperAdmin(uid);
    const { eventId } = req.body || {};
    const isPermitted = isAdmin || (await hasCheckInPermission(uid, eventId));
    if (!isPermitted) {
      return res.status(403).json({ ok: false, error: 'User must be super admin or have check-in permission' });
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

    // Best-effort trigger of Discord sync
    try {
      await axios.post(`https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/syncEventsToDiscord`);
    } catch (e) {
      console.log('syncEventsToDiscord trigger failed (continuing):', e.response?.status || e.message);
    }

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

    try {
      await axios.post(`https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/syncEventsToDiscord`);
    } catch (e) {
      console.log('syncEventsToDiscord trigger failed (continuing):', e.response?.status || e.message);
    }

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
exports.activateEventRegistration = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
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

    // Ensure a Discord text channel exists for this event after activation
    try {
      const refreshed = await db.collection('events').doc(eventId).get();
      const eventRecord = { id: eventId, ...refreshed.data() };
      await ensureDiscordChannelForEvent(eventRecord);
      await ensureDiscordRoleForEvent(eventRecord);
      await updateEventDiscordMembershipsForAll(eventRecord, { skipEnsureNpcChannels: true });
    } catch (ensureErr) {
      console.log('⚠️ ensureDiscordChannelForEvent failed (continuing):', ensureErr.response?.status || ensureErr.message || ensureErr);
    }

    // Best-effort trigger a full Discord sync
    try {
      await axios.post(`https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/syncEventsToDiscord`);
    } catch (e) {
      console.log('syncEventsToDiscord trigger failed (continuing):', e.response?.status || e.message);
    }

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

    // Ensure Discord text channel exists/renamed on updates
    try {
      const refreshed = await db.collection('events').doc(eventId).get();
      const eventRecord = { id: eventId, ...refreshed.data() };
      await ensureDiscordChannelForEvent(eventRecord);
      await ensureDiscordRoleForEvent(eventRecord);
      await updateEventDiscordMembershipsForAll(eventRecord, { skipEnsureNpcChannels: true });
    } catch (ensureErr) {
      console.log('⚠️ ensureDiscordChannelForEvent (update) failed (continuing):', ensureErr.response?.status || ensureErr.message || ensureErr);
    }

    try {
      await axios.post(`https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/syncEventsToDiscord`);
    } catch (e) {
      console.log('syncEventsToDiscord trigger failed (continuing):', e.response?.status || e.message);
    }

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
// Register user for an event (supports secondary backup shifts)
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

    const { 
      eventId, 
      attendeeTypeId, 
      selectedNpcShifts, 
      selectedCleanupShifts, 
      selectedPayOption,
      secondaryNpcShift, // optional backup shift name/id
      secondaryCleanupShift // optional backup shift name/id
    } = req.body;

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
      secondaryNpcShift: secondaryNpcShift || null,
      secondaryCleanupShift: secondaryCleanupShift || null,
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

// Get event shift summary: counts per NPC and Cleanup shift (primary selections)
exports.getEventShiftSummary = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    await getAuth().verifyIdToken(idToken);

    const eventId = req.query.eventId || req.body?.eventId;
    if (!eventId) return res.status(400).json({ ok: false, error: 'eventId_required' });

    const eventDoc = await db.collection('events').doc(String(eventId)).get();
    if (!eventDoc.exists) return res.status(404).json({ ok: false, error: 'event_not_found' });
    const eventData = eventDoc.data() || {};

    let npcShifts = Array.isArray(eventData.npcShifts) ? eventData.npcShifts : [];
    let cleanupShifts = Array.isArray(eventData.cleanupShifts) ? eventData.cleanupShifts : [];

    // If shifts are not present on the event, fall back to its event type definition
    if ((!npcShifts || npcShifts.length === 0) || (!cleanupShifts || cleanupShifts.length === 0)) {
      const typeId = eventData.typeId;
      if (typeId) {
        try {
          const typeDoc = await db.collection('event_types').doc(String(typeId)).get();
          if (typeDoc.exists) {
            const typeData = typeDoc.data() || {};
            if (!npcShifts || npcShifts.length === 0) npcShifts = Array.isArray(typeData.npcShifts) ? typeData.npcShifts : [];
            if (!cleanupShifts || cleanupShifts.length === 0) cleanupShifts = Array.isArray(typeData.cleanupShifts) ? typeData.cleanupShifts : [];
          }
        } catch (e) {
          console.log('Failed to load event type for shifts (continuing):', e.message);
        }
      }
    }

    // Initialize counts by index (string keys)
    const npcCounts = {};
    const cleanupCounts = {};
    for (let i = 0; i < npcShifts.length; i++) npcCounts[String(i)] = 0; // NPC keyed by index
    for (let i = 0; i < cleanupShifts.length; i++) {
      const label = String(cleanupShifts[i]);
      cleanupCounts[label] = 0; // Cleanup keyed by label
    }

    const regsSnap = await db.collection('events').doc(String(eventId)).collection('registrations').get();
    regsSnap.forEach(doc => {
      const r = doc.data() || {};
      const primaryNpc = Array.isArray(r.selectedNpcShifts) ? r.selectedNpcShifts : [];
      const primaryCleanup = Array.isArray(r.selectedCleanupShifts) ? r.selectedCleanupShifts : [];
      for (const idx of primaryNpc) {
        const key = String(parseInt(idx));
        if (npcCounts[key] !== undefined) npcCounts[key] += 1;
      }
      for (const label of primaryCleanup) {
        const key = String(label);
        if (cleanupCounts[key] !== undefined) cleanupCounts[key] += 1;
      }
      // Include secondary preferences in counts (separate keys)
      const secNpc = r.secondaryNpcShift;
      const secCleanup = r.secondaryCleanupShift;
      if (secNpc !== undefined && secNpc !== null) {
        const key = String(parseInt(secNpc));
        if (npcCounts[key] !== undefined) npcCounts[key] += 0; // keep primary in npcCounts; secondary shown via separate map below if needed
      }
      if (secCleanup !== undefined && secCleanup !== null) {
        const key = String(parseInt(secCleanup));
        if (cleanupCounts[key] !== undefined) cleanupCounts[key] += 0;
      }
    });

    return res.status(200).json({ ok: true, eventId, npcCounts, cleanupCounts, npcShifts, cleanupShifts });
  } catch (error) {
    console.error('Error in getEventShiftSummary:', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

// Get attendees for a specific shift (includes primary and secondary picks)
// Params: eventId, shiftType ('npc' | 'cleanup'), shiftName (string label for cleanup, index string for npc)
exports.getShiftAttendees = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }

  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }
  try {
    const idToken = req.headers.authorization.split(' ')[1];
    await getAuth().verifyIdToken(idToken);

    const eventId = req.query.eventId || req.body?.eventId;
    const shiftType = (req.query.shiftType || req.body?.shiftType || '').toString();
    const shiftName = (req.query.shiftName || req.body?.shiftName || '').toString();
    if (!eventId || !shiftType || !shiftName) {
      return res.status(400).json({ ok: false, error: 'eventId_shiftType_shiftName_required' });
    }
    if (!['npc', 'cleanup'].includes(shiftType)) {
      return res.status(400).json({ ok: false, error: 'invalid_shift_type' });
    }

    const regsSnap = await db.collection('events').doc(String(eventId)).collection('registrations').get();
    const attendeeUids = [];
    const secondaryUids = [];
    regsSnap.forEach(doc => {
      const r = doc.data() || {};
      if (shiftType === 'npc') {
        const primary = Array.isArray(r.selectedNpcShifts) ? r.selectedNpcShifts.map(x => String(parseInt(x))) : [];
        if (primary.includes(shiftName)) attendeeUids.push(doc.id);
        const sec = r.secondaryNpcShift;
        if (sec !== undefined && sec !== null && String(parseInt(sec)) === shiftName) secondaryUids.push(doc.id);
      } else {
        const primary = Array.isArray(r.selectedCleanupShifts) ? r.selectedCleanupShifts : [];
        if (primary.includes(shiftName)) attendeeUids.push(doc.id);
        const sec = r.secondaryCleanupShift;
        if (sec === shiftName) secondaryUids.push(doc.id);
      }
    });

    // Resolve basic identity (email) for display
    const attendees = [];
    for (const uid of attendeeUids) {
      try {
        const user = await getAuth().getUser(uid);
        attendees.push({ uid, email: user.email || null, displayName: user.displayName || null, source: 'primary' });
      } catch {
        attendees.push({ uid, source: 'primary' });
      }
    }
    for (const uid of secondaryUids) {
      try {
        const user = await getAuth().getUser(uid);
        attendees.push({ uid, email: user.email || null, displayName: user.displayName || null, source: 'secondary' });
      } catch {
        attendees.push({ uid, source: 'secondary' });
      }
    }

    return res.status(200).json({ ok: true, eventId, shiftType, shiftName, count: attendees.length, attendees });
  } catch (error) {
    console.error('Error in getShiftAttendees:', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});
// Get user's event registration (includes secondary shifts if present)
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
      
      // Generate unique number with collision checking
      let uniqueNumber;
      let isUnique = false;
      let attempts = 0;
      const maxAttempts = 100;

      while (!isUnique && attempts < maxAttempts) {
        uniqueNumber = Math.floor(Math.random() * 1000000) + 1;
        
        // Check if this number already exists in Firestore
        const existingDoc = await db.collection('monster_cores').doc(uniqueNumber.toString()).get();
        isUnique = !existingDoc.exists;
        attempts++;
        
        if (!isUnique) {
          console.log(`⚠️ Collision detected for number ${uniqueNumber}, trying again... (attempt ${attempts})`);
        }
      }

      if (!isUnique) {
        throw new Error(`Could not generate unique number after ${maxAttempts} attempts. Please try again.`);
      }

      console.log(`✅ Generated unique number: ${uniqueNumber} (attempt ${attempts})`);
      
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
    try {
      if (typeof tradeTrackingRef !== 'undefined') {
        await tradeTrackingRef.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
    } catch (trackingError) {
      console.error('Error updating trade tracking:', trackingError);
    }
    
    return res.status(500).json({ ok: false, error: 'Internal server error: ' + error.message });
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

    // Check for impersonation parameter
    const impersonateUid = req.query.impersonateUid;
    let targetUid = uid;
    
    if (impersonateUid && impersonateUid !== uid) {
      // Check if the requesting user is a super admin using the correct structure
      const isAdmin = await isSuperAdmin(uid);
      
      if (!isAdmin) {
        return res.status(403).json({ 
          ok: false, 
          error: 'Only super admins can impersonate other users' 
        });
      }
      
      targetUid = impersonateUid;
      console.log(`🔍 Super admin ${uid} impersonating user ${targetUid}`);
    }

    // Get user's characters from new structure: players/{targetUid}/characters
    console.log(`🔍 Looking for characters for user ${targetUid} in new structure...`);
    
    const playerRef = db.collection('players').doc(targetUid);
    const playerDoc = await playerRef.get();
    
    if (!playerDoc.exists) {
      console.log(`❌ Player document not found for user ${targetUid}`);
      return res.status(200).json({
        ok: true,
        characters: [],
        debug: {
          searchedForUid: targetUid,
          playerExists: false,
          message: 'Player document not found'
        }
      });
    }
    
    const charactersRef = playerRef.collection('characters');
    const charactersSnapshot = await charactersRef.get();
    
    if (charactersSnapshot.empty) {
      console.log(`❌ No characters found for user ${targetUid}`);
      return res.status(200).json({
        ok: true,
        characters: [],
        debug: {
          searchedForUid: targetUid,
          playerExists: true,
          charactersCount: 0,
          message: 'No characters found in player document'
        }
      });
    }

    const characters = [];
    charactersSnapshot.forEach(doc => {
      const data = doc.data();
      // Create character ID in the format expected by the frontend: {targetUid}_{characterNumber}
      const characterId = `${targetUid}_${doc.id}`;
      characters.push({
        id: characterId, // This is the format the frontend expects
        characterNumber: doc.id, // The actual character number from the document ID
        playerName: data.playerName || 'Unknown',
        characterName: data.characterName || 'Unknown',
        race: data.race || 'Unknown',
        cultivationTier: data.cultivationTier || 'Unknown'
      });
    });

    console.log(`📋 Found ${characters.length} characters for user ${targetUid}`);

    return res.status(200).json({
      ok: true,
      characters: characters,
      debug: {
        searchedForUid: targetUid,
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

    // Get target player's characters from new structure: players/{uid}/characters
    console.log(`🔍 Looking for characters for target player ${targetUid} in new structure...`);
    
    const playerRef = db.collection('players').doc(targetUid);
    const playerDoc = await playerRef.get();
    
    if (!playerDoc.exists) {
      console.log(`❌ Player document not found for target user ${targetUid}`);
      return res.status(404).json({ ok: false, error: 'Target player not found' });
    }
    
    const charactersRef = playerRef.collection('characters');
    const charactersSnapshot = await charactersRef.get();
    
    if (charactersSnapshot.empty) {
      console.log(`❌ No characters found for target user ${targetUid}`);
      return res.status(404).json({ ok: false, error: 'Target player has no characters' });
    }

    const characters = [];
    charactersSnapshot.forEach(doc => {
      const data = doc.data();
      // Create character ID in the format expected by the frontend: {uid}_{characterNumber}
      const characterId = `${targetUid}_${doc.id}`;
      characters.push({
        id: characterId, // This is the format the frontend expects
        characterNumber: doc.id, // The actual character number from the document ID
        playerName: data.playerName || 'Unknown',
        characterName: data.characterName || 'Unknown',
        race: data.race || 'Unknown',
        cultivationTier: data.cultivationTier || 'Unknown'
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
// Search characters by playerName, characterName, or characterNumber (Super Admin only)
exports.searchCharacters = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Auth required
  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Verify super admin
    const superAdminDoc = await db
      .collection('roles')
      .doc('superadmin')
      .collection('members')
      .doc(uid)
      .get();

    if (!superAdminDoc.exists) {
      return res.status(403).json({ ok: false, error: 'forbidden' });
    }

    const { playerName, characterName, characterNumber } = req.query;
    if (!playerName && !characterName && !characterNumber) {
      return res.status(400).json({ ok: false, error: 'At least one search parameter is required' });
    }

    // Prefer a single where filter, then filter remaining parameters in memory
    const primaryField = characterNumber ? 'characterNumber' : (playerName ? 'playerName' : (characterName ? 'characterName' : null));
    let snap;
    try {
      if (primaryField) {
        const value = primaryField === 'characterNumber' ? String(characterNumber) : (primaryField === 'playerName' ? String(playerName) : String(characterName));
        snap = await db.collectionGroup('characters').where(primaryField, '==', value).limit(200).get();
      } else {
        snap = await db.collectionGroup('characters').limit(200).get();
      }
    } catch (err) {
      // Fallback: scan players collection if collection group index is missing
      console.warn('collectionGroup query failed, falling back to player scan:', err.message);
      const playersSnap = await db.collection('players').limit(50).get();
      const docs = [];
      for (const playerDoc of playersSnap.docs) {
        const chars = await playerDoc.ref.collection('characters').limit(50).get();
        chars.forEach(d => docs.push(d));
      }
      snap = { docs };
    }

    const qPlayer = (playerName || '').toString().toLowerCase();
    const qChar = (characterName || '').toString().toLowerCase();
    const qNum = (characterNumber || '').toString();

    const characters = [];
    snap.docs.forEach(doc => {
      const data = doc.data();
      const playerRef = doc.ref.parent.parent; // players/{uid}
      const parentUid = playerRef ? playerRef.id : data.playerUid;
      const charNum = (data.characterNumber || doc.id || '').toString();
      const pName = (data.playerName || 'Unknown').toString();
      const cName = (data.characterName || 'Unknown').toString();

      // In-memory filters (case-insensitive contains for names, exact for number)
      if (qNum && charNum !== qNum) return;
      if (qPlayer && !pName.toLowerCase().includes(qPlayer)) return;
      if (qChar && !cName.toLowerCase().includes(qChar)) return;

      characters.push({
        id: `${parentUid}_${charNum}`,
        playerUid: parentUid,
        characterNumber: charNum,
        playerName: pName,
        characterName: cName,
        race: data.race || 'Unknown',
        cultivationTier: data.cultivationTier || 'Unknown',
      });
    });

    return res.status(200).json({ ok: true, characters });
  } catch (error) {
    console.error('Error in searchCharacters:', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
  }
});

// Get full character by composite ID {uid}_{characterNumber} (Super Admin only)
exports.getCharacterById = onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (!req.headers.authorization) {
    return res.status(401).json({ ok: false, error: 'Missing authorization header' });
  }

  const idToken = req.headers.authorization.split(' ')[1];
  try {
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Verify super admin
    const superAdminDoc = await db
      .collection('roles')
      .doc('superadmin')
      .collection('members')
      .doc(uid)
      .get();

    if (!superAdminDoc.exists) {
      return res.status(403).json({ ok: false, error: 'forbidden' });
    }

    const { characterId } = req.query;
    if (!characterId || typeof characterId !== 'string') {
      return res.status(400).json({ ok: false, error: 'characterId is required' });
    }

    const [playerUid, charNum] = characterId.split('_');
    if (!playerUid || !charNum) {
      return res.status(400).json({ ok: false, error: 'invalid_character_id' });
    }

    let character = null;

    // 1) Prefer Storage pc.json for full fidelity
    try {
      // Try to obtain player email from players doc; fallback to auth record
      let email = null;
      const playerDoc = await db.collection('players').doc(playerUid).get();
      if (playerDoc.exists) {
        email = playerDoc.data().email || null;
      }
      if (!email) {
        try {
          const userRecord = await getAuth().getUser(playerUid);
          email = userRecord.email || null;
        } catch (_) {}
      }

      if (email) {
        const bucket = getStorage().bucket();
        const file = bucket.file(`users/${email}/pc.json`);
        const [exists] = await file.exists();
        if (exists) {
          const [fileContent] = await file.download();
          const pc = JSON.parse(fileContent.toString());
          character = pc;
        }
      }
    } catch (storageErr) {
      console.warn('⚠️ getCharacterById storage read failed:', storageErr.message);
    }

    // 2) Fallback to Firestore document
    if (!character) {
      const docRef = db.collection('players').doc(playerUid).collection('characters').doc(charNum);
      const docSnap = await docRef.get();
      if (docSnap.exists) {
        character = docSnap.data();
      } else {
        return res.status(404).json({ ok: false, error: 'not_found' });
      }
    }

    // 3) Normalize response shape
    character = character || {};
    character.id = characterId;
    character.playerUid = playerUid;
    const parsedNum = parseInt((character.characterNumber ?? charNum), 10);
    character.characterNumber = isNaN(parsedNum) ? 0 : parsedNum;

    return res.status(200).json({ ok: true, character });
  } catch (error) {
    console.error('Error in getCharacterById:', error);
    return res.status(500).json({ ok: false, error: 'server_error', message: error.message });
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
    
    // Ensure default core item docs exist under items collection (no nested cores subcollection)
    console.log(`💎 Ensuring core item documents exist under items for character ${characterNumber}...`);
    try {
      const nowTs = admin.firestore.FieldValue.serverTimestamp();
      const coreItemDocs = ['coreIron', 'coreSilver', 'coreGold', 'coreJade', 'coreSaint', 'coreSovereign'];
      for (const docName of coreItemDocs) {
        const docRef = itemsRef.doc(docName);
        const docSnap = await docRef.get();
        if (!docSnap.exists) {
          console.log(`📝 Creating ${docName} document for character ${characterNumber}`);
          await docRef.set({ count: 0, lastUpdated: nowTs });
        } else {
          await docRef.set({ lastUpdated: nowTs }, { merge: true });
        }
      }
      console.log(`✅ Core item documents ensured under items`);
    } catch (coresError) {
      console.error(`❌ Error ensuring core item documents:`, coresError);
      throw coresError;
    }
    
    console.log(`✅ Character structure ensured for player ${uid}, character ${characterNumber}`);
    console.log(`🎯 Final verification - checking all components exist...`);
    
    // Final verification
    const finalPlayerDoc = await playerRef.get();
    const finalCharacterDoc = await characterRef.get();
    const finalItemsDoc = await charactersRef.doc(characterNumber).collection('items').doc('metadata').get();
    const finalCoreIronDoc = await itemsRef.doc('coreIron').get();
    
    console.log(`🎯 Final verification results:`);
    console.log(`  - Player exists: ${finalPlayerDoc.exists}`);
    console.log(`  - Character exists: ${finalCharacterDoc.exists}`);
    console.log(`  - Items exists: ${finalItemsDoc.exists}`);
    console.log(`  - coreIron doc exists: ${finalCoreIronDoc.exists}`);
    
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

      // Also run calculateCharacter automatically after sync
      try {
        const region = process.env.FUNCTIONS_EMULATOR === 'true' ? 'us-central1' : (process.env.GCLOUD_REGION || 'us-central1');
        const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_CONFIG && JSON.parse(process.env.FIREBASE_CONFIG).projectId || 'crucible-helper';
        const url = `https://${region}-${projectId}.cloudfunctions.net/calculateCharacter`;
        const payload = { playerUid: uid, characterNumber: String(characterData.characterNumber || 'main') };
        const calcResp = await axios.post(url, payload, { headers: { Authorization: `Bearer ${idToken}` } });
        console.log('🧮 calculateCharacter after sync status:', calcResp.status);
      } catch (e) {
        console.error('⚠️ calculateCharacter after sync failed:', e.message || e);
      }

      return res.status(200).json({
        ok: true,
        message: 'Character synced to Firestore successfully (calculate attempted)',
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

    // Align verification with items/<coreTier> document schema
    const finalCoreIronDoc = await itemsRef.doc('coreIron').get();

    return res.status(200).json({
      ok: true,
      message: 'Character structure test completed',
      result: result,
      verification: {
        playerExists: playerDoc.exists,
        characterExists: characterDoc.exists,
        itemsExists: itemsDoc.exists,
        coresExists: finalCoreIronDoc.exists,
        ironTierExists: finalCoreIronDoc.exists
      },
      paths: {
        player: `players/${uid}`,
        character: `players/${uid}/characters/${characterNumber}`,
        items: `players/${uid}/characters/${characterNumber}/items`,
        cores: `players/${uid}/characters/${characterNumber}/items/coreIron`,
        ironTier: `players/${uid}/characters/${characterNumber}/items/coreIron`
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

    // Ensure core documents exist directly under items collection (no cores subcollection)
    let coresCreated = false;
    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    const coreItemDocs = ['coreIron', 'coreSilver', 'coreGold', 'coreJade', 'coreSaint', 'coreSovereign'];
    for (const docName of coreItemDocs) {
      const docRef = itemsRef.doc(docName);
      const docSnap = await docRef.get();
      if (!docSnap.exists) {
        console.log(`💎 Creating ${docName} document for character ${characterNumber}`);
        await docRef.set({ count: 0, lastUpdated: nowTs });
        coresCreated = true;
      }
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
          console.log(`⏭️ Past event ${event.id} detected (starts at ${startDateTime.format()}); archiving Discord assets if any`);
          try {
            const archiveRes = await archiveDiscordAssetsForEvent(event);
            results.push({
              eventId: event.id,
              eventName: eventName,
              status: archiveRes.archived ? 'archived' : 'skipped',
              message: archiveRes.archived ? 'Archived past event channels/category' : 'No assets to archive',
              actions: archiveRes.actions
            });
          } catch (archErr) {
            results.push({
              eventId: event.id,
              eventName: eventName,
              status: 'error',
              message: `Archive failed: ${archErr.response?.status || archErr.message}`
            });
          }
          continue;
        }

        // Ensure Discord artifacts for upcoming/active registrations
        if (event.registrationActivated && event.registrationDetails) {
          console.log(`🧩 Ensuring Discord assets for event ${event.id}...`);
          try {
            await ensureDiscordCategoryForEvent(event);
            await ensureDiscordChannelForEvent(event);
            await ensureDiscordRoleForEvent(event);
            await updateEventDiscordMembershipsForAll(event, { skipEnsureNpcChannels: true });
          } catch (assetErr) {
            console.log('⚠️ Ensuring Discord assets failed:', assetErr.response?.data || assetErr.message || assetErr);
          }
        } else {
          console.log(`ℹ️ Event ${event.id} has no active registration; skipping Discord channel/role ensure.`);
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
        total: results.length,
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

// Verify Master Log "Attending Event" entries for an event's checked-in players and optionally resubmit
exports.verifyEventAttending = onRequest(async (req, res) => {
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
    // Auth required and must be super admin
    if (!req.headers.authorization) {
      return res.status(401).json({ ok: false, error: 'Missing authorization header' });
    }
    const idToken = req.headers.authorization.split(' ')[1];
    const decodedToken = await getAuth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const isAdmin = await isSuperAdmin(uid);
    if (!isAdmin) {
      return res.status(403).json({ ok: false, error: 'User must be super admin' });
    }

    const { eventId, resubmit, containerDocId } = req.body || {};
    if (!eventId) {
      return res.status(400).json({ ok: false, error: 'Event ID is required' });
    }

    // Load event to compute date range and name
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      return res.status(404).json({ ok: false, error: 'Event not found' });
    }
    const eventData = eventDoc.data() || {};
    const startDateRaw = eventData.startDate;
    const endDateRaw = eventData.endDate;

    const parseDateOnly = (v) => {
      if (!v) return null;
      const d = new Date(v);
      return isNaN(d.getTime()) ? null : new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
    };
    const formatYmd = (d) => d.toISOString().slice(0, 10);

    const startDate = parseDateOnly(startDateRaw);
    const endDate = parseDateOnly(endDateRaw);
    if (!startDate || !endDate) {
      return res.status(400).json({ ok: false, error: 'Event start/end dates are invalid' });
    }
    // Candidate dates inclusive between start and end
    const candidateDates = [];
    for (let d = new Date(startDate); d <= endDate; d = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1))) {
      candidateDates.push(formatYmd(d));
    }

    // Determine event name for sheet row
    let eventName = eventData.type || 'Unknown Event';
    if (eventData.registrationActivated && eventData.registrationDetails && eventData.registrationDetails.eventName) {
      eventName = eventData.registrationDetails.eventName;
    }

    // Load checked-in players for this event
    const checkinsSnap = await db.collection('events').doc(eventId).collection('checkins').get();
    const attendees = [];
    for (const doc of checkinsSnap.docs) {
      const playerUid = doc.id;
      // Resolve email/display name
      let email = null;
      let displayName = null;
      try {
        const userRecord = await getAuth().getUser(playerUid);
        email = userRecord.email || null;
        displayName = userRecord.displayName || null;
      } catch (e) {
        const userDoc = await db.collection('users').doc(playerUid).get();
        if (userDoc.exists) {
          const u = userDoc.data() || {};
          email = email || u.email || null;
          displayName = displayName || u.displayName || null;
        }
      }
      attendees.push({ uid: playerUid, email, displayName });
    }

    // Load Master Logs from Firestore mirror
    const logsDocId = (containerDocId || 'root').toString();
    const masterLogsRef = db.collection('Master Logs').doc(logsDocId).collection('All');
    const masterLogsSnap = await masterLogsRef.get();

    // Build index by normalized date for reason == 'Attending Event'
    const normalizeDate = (value) => {
      if (!value) return '';
      const v = String(value).trim();
      if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      const dt = new Date(v);
      if (!isNaN(dt.getTime())) return dt.toISOString().slice(0, 10);
      const m = v.split('/');
      if (m.length === 3) {
        const month = String(parseInt(m[0], 10)).padStart(2, '0');
        const day = String(parseInt(m[1], 10)).padStart(2, '0');
        const year = String(parseInt(m[2], 10));
        if (year && month && day) return `${year}-${month}-${day}`;
      }
      return '';
    };
    const getFieldValue = (rowObj, candidates) => {
      for (const k of candidates) {
        if (Object.prototype.hasOwnProperty.call(rowObj, k)) return rowObj[k];
      }
      return undefined;
    };
    const emailKeys = [
      'Player Email', 'Email', 'PlayerEmail', 'Email Address', 'EmailAddress', 'Player E-mail', 'E-mail'
    ];

    const byDate = new Map();
    masterLogsSnap.forEach((doc) => {
      const row = doc.data() || {};
      const reason = String(row['Advancement Reason'] || row['AdvancementReason'] || '').trim();
      if (reason.toLowerCase() !== 'attending event') return;
      const dateStr = normalizeDate(row['Date'] || row['date'] || row['_date']);
      if (!dateStr) return;
      if (!byDate.has(dateStr)) byDate.set(dateStr, []);
      byDate.get(dateStr).push(row);
    });

    const found = [];
    const missing = [];
    for (const a of attendees) {
      const playerEmail = (a.email || '').toLowerCase();
      let matched = false;
      if (playerEmail) {
        for (const dateStr of candidateDates) {
          const rows = byDate.get(dateStr) || [];
          for (const row of rows) {
            const rowEmail = String(getFieldValue(row, emailKeys) || '').toLowerCase().trim();
            if (rowEmail && rowEmail === playerEmail) { matched = true; break; }
          }
          if (matched) break;
        }
      }
      if (matched) found.push(a); else missing.push(a);
    }

    let appended = 0;
    if (resubmit === true && missing.length > 0) {
      // Prepare Google Sheets API once
      const auth = new googleapis.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
        keyFile: './service-account-key.json'
      });
      const sheets = googleapis.sheets({ version: 'v4', auth });

      // Build rows to append for each missing attendee using their registration details
      const rowsToAppend = [];
      for (const m of missing) {
        if (!m.email) continue; // cannot append without target email
        // Load registration details for build/AP and attendingAs
        const regDoc = await db.collection('events').doc(eventId).collection('registrations').doc(m.uid).get();
        const reg = regDoc.exists ? (regDoc.data() || {}) : {};
        const attendingAs = reg.attendeeTypeName || 'Unknown';
        const buildAdjustment = reg.buildForEvent || 0;
        const apAdjustment = reg.affinityPointsForEvent || 0;
        rowsToAppend.push([
          decodedToken.email || 'admin@local', // scanner/admin email
          new Date().toISOString(),            // timestamp now
          m.email,                              // player email
          eventName,                            // event name
          attendingAs,                          // attending as
          buildAdjustment,                      // build adj
          apAdjustment                          // ap adj
        ]);
      }

      if (rowsToAppend.length > 0) {
        const resp = await sheets.spreadsheets.values.append({
          spreadsheetId: config.google_sheets.checkin_spreadsheet_id,
          range: `${config.google_sheets.checkin_sheet_name}!A:G`,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
          resource: { values: rowsToAppend }
        });
        appended = rowsToAppend.length;
        console.log('Resubmitted check-ins appended:', resp.data && appended);
      }
    }

    return res.status(200).json({
      ok: true,
      eventId,
      eventName,
      candidateDates,
      found,
      missing,
      appended
    });
  } catch (error) {
    console.error('Error verifying event attending:', error);
    res.status(500).json({ ok: false, error: 'server_error', message: error.message });
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