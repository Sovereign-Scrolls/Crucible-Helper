/***** CONFIG: sources, destinations, and behavior *****/
const PI_SOURCE_TAB               = 'Progress Import';
const PI_SOURCE_CHARACTER_CELL    = 'B1';

// Progress Import tables
const PI_SOURCE_AFFINITY_RANGE    = 'A12:D23'; // [Timestamp, Affinity, Level, Affinity Points]
const PI_SOURCE_SKILLS_RANGE      = 'M12:Q23'; // [Timestamp, Skill, Type, LevelAdj, Build]
const PI_SOURCE_ESSENCE_RANGE     = 'M7:O7';   // [Timestamp, EssenceAdj, Build] (single row)

const ML_DESTINATION_TAB          = 'Master Logs'; // A..T (20 columns)
const RULES_MARSHALLS_TAB         = 'Rules Marshalls'; // A=name, B=email, C=active (TRUE)

// Remote pending file (same one you IMPORTRANGE from)
const REMOTE_SPREADSHEET_NAMED_RANGE = 'adv_src';
const REMOTE_TAB_AFFINITY         = 'Affinity Changes';
const REMOTE_TAB_SKILL            = 'Skill Changes';
const REMOTE_TAB_ESSENCE          = 'Essence Changes';

// Player email (used for deletions)
const PLAYER_EMAIL_CELL           = 'F3';

// Event placeholder for Master Logs col T
const EVENT_PLACEHOLDER           = 'TODO: set event';


/***** PUBLIC ENTRY POINTS *****/
// One-click: import all (Affinity+Skills+Essence) then delete all for the player email
function processAll() {
  const editorEmail = Session.getActiveUser().getEmail() || Session.getEffectiveUser().getEmail() || '';
  if (editorEmail) {
    processAllWithEditor_(editorEmail);
  } else {
    openEditorPickerAndProcessAll_();
  }
}

// Import only (kept for convenience / separate runs)
function importProgress() {
  const editorEmail = Session.getActiveUser().getEmail() || Session.getEffectiveUser().getEmail() || '';
  if (editorEmail) {
    importAllToMasterLogs_(editorEmail);
  } else {
    openEditorPickerAndImportOnly_();
  }
}

/***** CORE FLOWS *****/
// 1) Import all → 2) Upload JSON → 3) Delete remote rows (by email)
function processAllWithEditor_(editorEmail) {
  // Import
  const importResult = importAllToMasterLogs_(editorEmail);
  if (!importResult || (importResult.counts.affinity + importResult.counts.skills + importResult.counts.essence) === 0) {
    toast_('Nothing imported; skipping upload and delete.');
    return;
  }

  SpreadsheetApp.flush();
  const ss  = SpreadsheetApp.getActive();
  const src = ss.getSheetByName(PI_SOURCE_TAB);
  const characterNumber = src.getRange(PI_SOURCE_CHARACTER_CELL).getValue()
  const jsonData   = generateCharacterJsonFromLogs(characterNumber);
  const playerEmail= jsonData.playerEmail;
  const bucket     = getStorageBucket_();
  const path       = `users/${playerEmail}/pc.json`;
  uploadJsonToGCS(bucket, path, jsonData);

  // Delete all pending rows for this player email across remote tabs
  const email = getActiveSheetValueTrim_(PLAYER_EMAIL_CELL);
  if (!email) {
    toast_('Skipped delete: player email cell is blank.');
    return;
  }
  const del = deleteAllForEmailAcrossRemoteTabs_(email);
  toast_(
    `Imported A:${importResult.counts.affinity}, S:${importResult.counts.skills}, E:${importResult.counts.essence} → `
    + `Deleted A:${del.affinity}, S:${del.skills}, E:${del.essence} for ${email}.`
  );


}

// Imports Affinity + Skills + Essence into Master Logs (one write)
// Returns { counts, exportPayload }
function importAllToMasterLogs_(editorEmail) {
  const ss  = SpreadsheetApp.getActive();
  const src = ss.getSheetByName(PI_SOURCE_TAB);
  const dst = ss.getSheetByName(ML_DESTINATION_TAB);
  if (!src || !dst) throw new Error('Missing required sheet(s).');

  const characterNumber = src.getRange(PI_SOURCE_CHARACTER_CELL).getValue();
  if (characterNumber === '' || characterNumber == null) {
    toast_(`Character Number (${PI_SOURCE_TAB}!${PI_SOURCE_CHARACTER_CELL}) is blank.`);
    return { counts: { affinity:0, skills:0, essence:0 }, exportPayload: null };
  }

  // Read tables
  const affVals = src.getRange(PI_SOURCE_AFFINITY_RANGE).getValues(); // [ts, affinity, level, points]
  const sklVals = src.getRange(PI_SOURCE_SKILLS_RANGE).getValues();   // [ts, skill, type, levelAdj, build]
  const essVals = src.getRange(PI_SOURCE_ESSENCE_RANGE).getValues();  // [ts, essenceAdj, build]
  const affEntries = affVals.filter(r => r.some(v => v !== '' && v != null));
  const sklEntries = sklVals.filter(r => r.some(v => v !== '' && v != null));
  const essEntries = essVals.filter(r => r.some(v => v !== '' && v != null));

  if (!affEntries.length && !sklEntries.length && !essEntries.length) {
    toast_('Nothing to import from Progress Import.');
    return { counts: { affinity:0, skills:0, essence:0 }, exportPayload: null };
  }

  // Character Tier (evaluate once)
  const characterTier = evaluateNamedFunction_(
    `=CHARACTER_TIER(${typeof characterNumber === 'number' ? characterNumber : `"${characterNumber}"`})`
  );

  const COLS = 20;
  const outRows = [];

  // Build export payload (what we just imported)
  const runAt = new Date();
  const exportPayload = {
    runAt,
    editorEmail,
    characterNumber,
    characterTier,
    imported: {
      affinities: affEntries.map(([ts, name, level, points]) => ({
        timestamp: ts, name, level, points,
        pointsWritten: toNegativeNumberOrBlank_(points)
      })),
      skills: sklEntries.map(([ts, skillName, skillType, levelAdj, buildAdj]) => ({
        timestamp: ts, skillName, skillType, levelAdj, buildAdj,
        buildWritten: toNegativeNumberOrBlank_(buildAdj)
      })),
      essence: essEntries.map(([ts, essenceAdj, buildAdj]) => ({
        timestamp: ts, essenceAdj, buildAdj,
        buildWritten: toNegativeNumberOrBlank_(buildAdj)
      }))
    }
  };

  // ---- Affinity rows
  for (const [ts, affinity, level, points] of affEntries) {
    const row = new Array(COLS).fill('');
    row[0]  = characterNumber;                   // A
    row[1]  = ts;                                // B
    row[3]  = characterTier;                     // D
    row[4]  = '';                                // E
    row[5]  = toNegativeNumberOrBlank_(points);  // F
    row[6]  = 'Raising Affinity Level';          // G
    row[14] = affinity;                          // O
    row[15] = level;                             // P
    row[17] = editorEmail || '';                 // R
    row[19] = EVENT_PLACEHOLDER;                 // T
    outRows.push(row);
  }

  // ---- Skill rows
  for (const [ts, skillName, skillType, levelAdj, buildAdj] of sklEntries) {
    const row = new Array(COLS).fill('');
    row[0]  = characterNumber;                       // A
    row[1]  = ts;                                    // B
    row[3]  = characterTier;                         // D
    row[4]  = toNegativeNumberOrBlank_(buildAdj);    // E
    row[6]  = 'Buying Skill';                        // G
    row[7]  = skillType;                             // H
    row[8]  = skillName;                             // I
    row[9]  = levelAdj;                              // J
    row[17] = editorEmail || '';                     // R
    row[19] = EVENT_PLACEHOLDER;                     // T
    outRows.push(row);
  }

  // ---- Essence rows
  for (const [ts, essenceAdj, buildAdj] of essEntries) {
    const row = new Array(COLS).fill('');
    row[0]  = characterNumber;                       // A
    row[1]  = ts;                                    // B
    row[3]  = characterTier;                         // D
    row[4]  = toNegativeNumberOrBlank_(buildAdj);    // E
    row[6]  = 'Buying Hit Points';                   // G
    row[10] = essenceAdj;                            // K
    row[17] = editorEmail || '';                     // R
    row[19] = EVENT_PLACEHOLDER;                     // T
    outRows.push(row);
  }

  // Write once
  const startRow = dst.getLastRow() + 1;
  dst.getRange(startRow, 1, outRows.length, COLS).setValues(outRows);

  const counts = { affinity: affEntries.length, skills: sklEntries.length, essence: essEntries.length };
  toast_(`Imported A:${counts.affinity}, S:${counts.skills}, E:${counts.essence} rows to Master Logs.`);
  return { counts, exportPayload };
}

/***** DELETION (uniform across tabs) *****/
function deleteAllForEmailAcrossRemoteTabs_(email) {
  return {
    affinity: deleteAllByEmailInRemoteTab_(REMOTE_TAB_AFFINITY, email),
    skills:   deleteAllByEmailInRemoteTab_(REMOTE_TAB_SKILL,   email),
    essence:  deleteAllByEmailInRemoteTab_(REMOTE_TAB_ESSENCE, email)
  };
}

function deleteAllByEmailInRemoteTab_(tabName, email) {
  const sh = openRemoteSheetByTab_(tabName);
  const lastRow = sh.getLastRow();
  const lastCol = sh.getLastColumn();
  if (lastRow < 2) return 0;

  // Find Email header (case-insensitive)
  const header = sh.getRange(1, 1, 1, lastCol).getValues()[0].map(h => String(h).trim());
  const emailIdx = header.map(h => h.toLowerCase()).indexOf('email');
  if (emailIdx < 0) throw new Error(`Could not find "Email" header in "${tabName}".`);

  const data = sh.getRange(2, 1, lastRow - 1, lastCol).getValues();
  const target = String(email || '').trim().toLowerCase();
  const rowsToDelete = [];
  for (let i = 0; i < data.length; i++) {
    const rowEmail = String(data[i][emailIdx] || '').trim().toLowerCase();
    if (rowEmail === target) rowsToDelete.push(i + 2); // account for header
  }
  if (!rowsToDelete.length) return 0;

  rowsToDelete.sort((a,b)=>b-a).forEach(r => sh.deleteRow(r));
  return rowsToDelete.length;
}

/***** EDITOR PICKERS (fallback if Session email not available) *****/
function openEditorPickerAndProcessAll_() {
  const choices = getActiveRulesMarshalls_();
  if (!choices.length) return uiAlert_(`No active Rules Marshalls found in "${RULES_MARSHALLS_TAB}".`);

  const html = buildPickerHtml_(choices, 'processAllWithEditor_');
  SpreadsheetApp.getUi().showModalDialog(html, 'Select Editor');
}

function openEditorPickerAndImportOnly_() {
  const choices = getActiveRulesMarshalls_();
  if (!choices.length) return uiAlert_(`No active Rules Marshalls found in "${RULES_MARSHALLS_TAB}".`);

  const html = buildPickerHtml_(choices, 'importAllToMasterLogs_');
  SpreadsheetApp.getUi().showModalDialog(html, 'Select Editor');
}

function getActiveRulesMarshalls_() {
  const ss = SpreadsheetApp.getActive();
  const rules = ss.getSheetByName(RULES_MARSHALLS_TAB);
  if (!rules) throw new Error(`Missing sheet: ${RULES_MARSHALLS_TAB}`);
  const rows = Math.max(0, rules.getLastRow() - 1);
  if (rows === 0) return [];
  const data = rules.getRange(2, 1, rows, 3).getValues(); // A=name, B=email, C=active
  return data
    .filter(r => (String(r[2]).toLowerCase() === 'true' || r[2] === true) && r[0] && r[1])
    .map(r => ({ name: String(r[0]), email: String(r[1]) }));
}

function buildPickerHtml_(choices, callbackName) {
  const options = choices
    .map(p => `<option value="${escapeHtml_(p.email)}">${escapeHtml_(p.name)} — ${escapeHtml_(p.email)}</option>`)
    .join('');
  return HtmlService.createHtmlOutput(`
    <!doctype html><html><head><base target="_top">
    <style>
      body { font: 14px/1.4 system-ui, Arial; padding: 16px; }
      select, button { font-size: 14px; padding: 6px 8px; }
      .row { margin-bottom: 12px; }
    </style></head><body>
      <div class="row">
        <label for="editor">Select editor:</label><br/>
        <select id="editor">${options}</select>
      </div>
      <div>
        <button onclick="submit()">Continue</button>
        <button onclick="google.script.host.close()">Cancel</button>
      </div>
      <script>
        function submit(){
          var email = document.getElementById('editor').value;
          google.script.run
            .withSuccessHandler(function(){ google.script.host.close(); })
            .${callbackName}(email);
        }
      </script>
    </body></html>
  `).setWidth(380).setHeight(200);
}

/***** HELPERS *****/
function openRemoteSheetByTab_(tabName) {
  const id = getNamedRangeValue_(REMOTE_SPREADSHEET_NAMED_RANGE);
  if (!id) throw new Error(`Named range "${REMOTE_SPREADSHEET_NAMED_RANGE}" is blank or missing.`);
  const remote = SpreadsheetApp.openById(id);
  const sh = remote.getSheetByName(tabName);
  if (!sh) throw new Error(`Remote tab "${tabName}" not found.`);
  return sh;
}

function getNamedRangeValue_(name) {
  const ss = SpreadsheetApp.getActive();
  const r = ss.getRangeByName(name);
  return r ? String(r.getValue() || '').trim() : '';
}

function getActiveSheetValueTrim_(a1) {
  const sh = SpreadsheetApp.getActiveSheet();
  return String(sh.getRange(a1).getValue() || '').trim();
}

function evaluateNamedFunction_(formula) {
  const ss = SpreadsheetApp.getActive();
  let sh = ss.getSheetByName('__tmp_eval');
  if (!sh) sh = ss.insertSheet('__tmp_eval');
  sh.clear();
  sh.getRange(1, 1).setFormula(formula);
  SpreadsheetApp.flush();
  const val = sh.getRange(1, 1).getValue();
  try { sh.hideSheet(); } catch (e) {}
  return val;
}

function toNegativeNumberOrBlank_(v) {
  if (v === '' || v == null) return '';
  const n = Number(v);
  if (!isFinite(n)) return '';
  return n === 0 ? 0 : -Math.abs(n);
}

function escapeHtml_(s) {
  return String(s)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;');
}

function uiAlert_(msg){ SpreadsheetApp.getUi().alert(msg); }
function toast_(msg){ SpreadsheetApp.getActive().toast(msg); }
