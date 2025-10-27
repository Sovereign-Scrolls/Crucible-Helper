/***** CHECK-INS → MASTER LOGS *****/
const CI_SOURCE_TAB        = 'Check-Ins';
const CI_START_ROW         = 6;     // header above
const CI_NUM_COLS          = 10;    // A..J

const EA_REMOTE_TAB               = 'Event Attending'; // remote tab name

// A = Character Number
// E = Timestamp
// G = Event Name
// I = Build Adjust
// J = Affinity Point Adjust
const CI_IDX = {
  CHAR: 0,   // A
  EMAIL: 3,  // D
  TS:   4,   // E
  EVENT:6,   // G
  BUILD:8,   // I
  AP:   9    // J
};

/**
 * One-click entry point you can assign to a button:
 * - Uses the signed-in user's email (or falls back to the picker you already have).
 */
function processCheckIns() {
  const editorEmail = Session.getActiveUser().getEmail() || Session.getEffectiveUser().getEmail() || '';
  if (editorEmail) {
    importCheckInsToMasterLogs_(editorEmail);
    EA_removeProcessedCheckIns_();
  } else {
    openEditorPickerAndImportCheckIns_();
  }
}

/**
 * Import all rows from Check-Ins!A6:J → Master Logs, one write.
 * Mapping:
 * A Character Number          ← A
 * B Date                      ← E (Timestamp)
 * D Character Tier            ← =CHARACTER_TIER(character_number)
 * E Build Adjustment          ← I (as-is)
 * F Affinity Adjustment       ← J (as-is)
 * G Advancement Reason        ← "Attending Event"
 * R Editor                    ← editorEmail
 * S Notes                     ← "Check-In Script Automation"
 * T Event                     ← G (Event Name)
 */
function importCheckInsToMasterLogs_(editorEmail) {
  const ss  = SpreadsheetApp.getActive();
  const src = ss.getSheetByName(CI_SOURCE_TAB);
  const dst = ss.getSheetByName(ML_DESTINATION_TAB);
  if (!src || !dst) throw new Error('Missing required sheet(s).');

  const lastRow = src.getLastRow();
  if (lastRow < CI_START_ROW) {
    toast_('No Check-Ins rows to import.');
    return;
  }

  const rows = src.getRange(CI_START_ROW, 1, lastRow - CI_START_ROW + 1, CI_NUM_COLS).getValues();

  // Filter: require Character Number present (rest can be blank)
  const entries = rows.filter(r => r[CI_IDX.CHAR] !== '' && r[CI_IDX.CHAR] != null);
  if (!entries.length) {
    toast_('No Check-Ins with a Character Number found.');
    return;
  }

  // Cache tiers per character to avoid repeated evaluation
  const tierCache = new Map();
  const getTier = (charNum) => {
    const k = String(charNum).trim();
    if (tierCache.has(k)) return tierCache.get(k);
    const tier = evaluateNamedFunction_(
      `=CHARACTER_TIER(${typeof charNum === 'number' ? charNum : `"${k}"`})`
    );
    tierCache.set(k, tier);
    return tier;
  };

  const COLS = 20; // Master Logs columns A..T
  const out = [];

  for (const r of entries) {
    const charNum = r[CI_IDX.CHAR];
    const ts      = r[CI_IDX.TS];
    const eventNm = r[CI_IDX.EVENT];
    const build   = r[CI_IDX.BUILD];
    const ap      = r[CI_IDX.AP];

    const tier = getTier(charNum);

    const row = new Array(COLS).fill('');
    row[0]  = charNum;                      // A Character Number
    row[1]  = ts;                           // B Date
    row[3]  = tier;                         // D Character Tier
    row[4]  = build;                        // E Build Adjustment (as provided)
    row[5]  = ap;                           // F Affinity Adjustment (as provided)
    row[6]  = 'Attending Event';            // G Advancement Reason
    row[17] = editorEmail || '';            // R Editor
    row[18] = 'Check-In Script Automation'; // S Notes
    row[19] = eventNm;                      // T Event
    out.push(row);
  }

  const startRow = dst.getLastRow() + 1;
  dst.getRange(startRow, 1, out.length, COLS).setValues(out);

  toast_(`Imported ${out.length} check-in entr${out.length===1?'y':'ies'} to Master Logs.`);
}

/***** Editor picker reuse (only if Session email isn’t available) *****/
function openEditorPickerAndImportCheckIns_() {
  const choices = getActiveRulesMarshalls_();
  if (!choices.length) return uiAlert_(`No active Rules Marshalls found in "${RULES_MARSHALLS_TAB}".`);
  const html = buildPickerHtml_(choices, 'importCheckInsToMasterLogs_');
  SpreadsheetApp.getUi().showModalDialog(html, 'Select Editor');
}


function EA_removeProcessedCheckIns_() {
  // Read Check-Ins rows
  const ss  = SpreadsheetApp.getActive();
  const src = ss.getSheetByName(CI_SOURCE_TAB); // 'Check-Ins'
  if (!src) throw new Error(`Missing sheet: ${CI_SOURCE_TAB}`);

  const lastRow = src.getLastRow();
  if (lastRow < CI_START_ROW) {
    toast_('No Check-Ins rows to clean.');
    return 0;
  }

  const rows = src.getRange(CI_START_ROW, 1, lastRow - CI_START_ROW + 1, CI_NUM_COLS).getValues();

  // Build key set from Check-Ins: email + timestamp(minute bucket) + event
  // (A=Char#, D=playerEmail, E=Timestamp, G=Event Name)
  const keys = new Set();
  for (const r of rows) {
    const email = normalizeText_(r[CI_IDX.EMAIL]);  // D
    const tsKey = tsMinuteBucketKey_(r[CI_IDX.TS]); // E
    const evKey = normalizeText_(r[CI_IDX.EVENT]);  // G
    if (!email) continue;                           // skip lines without an email
    // Require at least email + event; timestamp can be string or date
    keys.add(`${email}||${tsKey}||${evKey}`);
  }

  if (!keys.size) {
    toast_('No Check-Ins emails found to delete in Event Attending.');
    return 0;
  }

  // Open remote "Event Attending"
  const sh = openRemoteSheetByTab_(EA_REMOTE_TAB); // 'Event Attending'
  const last = sh.getLastRow();
  const cols = sh.getLastColumn();
  if (last < 2) {
    toast_('No data rows in "Event Attending".');
    return 0;
  }

  // Map headers (case-insensitive, supports checkInUserEmail or playerEmail)
  const header = sh.getRange(1, 1, 1, cols).getValues()[0].map(h => String(h).trim());
  const lower  = header.map(h => h.toLowerCase());

  const emailIdxs = [];
  const tryEmails = ['playeremail','checkinuseremail','player email','check in user email','email','useremail','user email'];
  for (let i = 0; i < lower.length; i++) if (tryEmails.includes(lower[i])) emailIdxs.push(i);
  if (!emailIdxs.length) throw new Error('Could not find an email column in "Event Attending".');

  const tsIdx = (() => {
    const names = ['timestamp','time stamp','created_at','time','datetime','date'];
    const i = lower.findIndex(h => names.includes(h));
    if (i >= 0) return i;
    throw new Error('Could not find "Timestamp" column in "Event Attending".');
  })();

  const eventIdx = (() => {
    const names = ['event name','event','name'];
    const i = lower.findIndex(h => names.includes(h));
    if (i >= 0) return i;
    throw new Error('Could not find "Event Name" column in "Event Attending".');
  })();

  // Scan remote and mark matches for deletion
  const data = sh.getRange(2, 1, last - 1, cols).getValues();
  const rowsToDelete = [];

  for (let i = 0; i < data.length; i++) {
    const row = data[i];
    const evKey = normalizeText_(row[eventIdx]);
    const tsKey = tsMinuteBucketKey_(row[tsIdx]);

    // Some files store either playerEmail or checkInUserEmail. Check both.
    for (const eIdx of emailIdxs) {
      const email = normalizeText_(row[eIdx]);
      if (!email) continue;
      const key = `${email}||${tsKey}||${evKey}`;
      if (keys.has(key)) {
        rowsToDelete.push(i + 2); // +2 for header row
        break;
      }
    }
  }

  if (!rowsToDelete.length) {
    toast_('No matching Event Attending rows found to delete.');
    return 0;
  }

  rowsToDelete.sort((a,b)=>b-a).forEach(r => sh.deleteRow(r));
  toast_(`Deleted ${rowsToDelete.length} row(s) from "${EA_REMOTE_TAB}".`);
  return rowsToDelete.length;
}


/* Helper */
function normalizeTimeMs_(v) {
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') {
    // Sheets serial date? (days since 1899-12-30)
    if (v > 59 && v < 600000) return Math.round((v - 25569) * 86400 * 1000);
    return Math.round(v);
  }
  const d = new Date(v);
  return isNaN(d.getTime()) ? NaN : d.getTime();
}

function normalizeText_(s) {
  return String(s || '').trim().toLowerCase();
}

// Bucket timestamps to minute granularity so 10:32:15 and 10:32:42 match
function tsMinuteBucketKey_(v) {
  const ms = normalizeTimeMs_(v);
  if (isFinite(ms)) return 'm:' + Math.floor(ms / 60000);
  return 's:' + normalizeText_(v); // fall back to string compare
}

