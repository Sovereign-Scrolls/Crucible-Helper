
// ==== Helper Utilities ==== //

function getSkillDetails(skillName, skillType) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sName = sanitize(skillName);
  const sType = sanitize(skillType);

  // === Common Skills (A: Name, B: Frequency, C: Base Cost, G: Description) ===
  const commonSheet = ss.getSheetByName("Import: Common Skills");
  const commonData = commonSheet.getRange(2, 1, commonSheet.getLastRow() - 1, 7).getValues();

  const commonMatch = commonData.find(row => sanitize(row[0]) === sName);
  if (commonMatch) {
    return {
      frequency: sanitize(commonMatch[1] || ""),
      verbal: "",
      description: sanitize(commonMatch[6] || ""),
      baseCost: parseFloat(commonMatch[2]) || null,
      delivery: ""
    };
  }

  // === Race Skills (A: Name, B: Cost, C: Race, D: Frequency, E: Description) ===
  const raceSheet = ss.getSheetByName("Import: Race Skills");
  const raceData = raceSheet.getRange(2, 1, raceSheet.getLastRow() - 1, 7).getValues();

  const raceMatch = raceData.find(row =>
    sanitize(row[0]) === sName && sanitize(row[2]) === sType
  );
  if (raceMatch) {
    return {
      frequency: sanitize(raceMatch[3] || ""),
      verbal: sanitize(raceMatch[6] || ""),
      description: sanitize(raceMatch[5] || ""),
      baseCost: parseFloat(raceMatch[1]) || null,
      delivery: ""
    };
  }

  // === Affinity Skills (A: Name, B: Affinity, C: Frequency, D: Cost, E: Delivery, F: Description, G: Verbal) ===
  const affinitySheet = ss.getSheetByName("Import: Affinity Skills");
  const affinityData = affinitySheet.getRange(2, 1, affinitySheet.getLastRow() - 1, 9).getValues();

  const affinityMatch = affinityData.find(row =>
    sanitize(row[0]) === sName && sanitize(row[1]) === sType
  );
  if (affinityMatch) {
    return {
      frequency: sanitize(affinityMatch[2] || ""),
      verbal: sanitize(affinityMatch[7] || ""),
      description: sanitize(affinityMatch[8] || ""),
      baseCost: parseFloat(affinityMatch[3]) || null,
      delivery: sanitize(affinityMatch[6] || "")
    };
  }

  // === No match fallback ===
  return {
    frequency: "",
    verbal: "",
    description: "",
    baseCost: null,
    delivery: ""
  };
}



function deselectUserSelection() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  const cell = sheet.getRange("A1");
  sheet.setActiveRange(cell);
}

function getAvailableCharacters() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const pcsSheet = ss.getSheetByName("PCs");
  const data = pcsSheet.getRange(2, 1, pcsSheet.getLastRow()-1, pcsSheet.getLastColumn()).getValues();

  const characters = data
    .filter(row => !row[10]) // Column K (Character Sheet Link) is empty
    .filter(row => row[5])   // Column F (Character Number) exists
    .map(row => ({
      value: row[5] + "|" + row[0], // "CharacterNumber|PlayerName"
      label: row[5] + " - " + row[0] // "44 - Jeffrey Brite"
    }));

  return characters.sort((a, b) => {
    // Sort numerically by Character Number
    return Number(a.value.split("|")[0]) - Number(b.value.split("|")[0]);
  });
}

function getAllCharacters() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("PCs");
  const data = sheet.getRange(2, 1, sheet.getLastRow()-1, sheet.getLastColumn()).getValues();

  const characters = data
    .filter(row => row[5]) // Must have Character Number (F)
    .map(row => ({
      value: row[5] + "|" + row[0], // Character Number | Player Name
      label: row[5] + " - " + row[0]
    }));

  return characters;
}

// ==== onEdit Handlers ==== //

function onEdit(e) {
  if (!e) return;
  handleAdvancementUI(e);
  handleCheckboxInitialize(e);
}



function handleCheckboxInitialize(e) {
  const sheet = e.source.getActiveSheet();
  const range = e.range;

  const checkboxCol = 10; // Column J
  const pcsSheetName = "PCs";
  const logSheetName = "Master Logs";

  if (sheet.getName() !== pcsSheetName || range.getColumn() !== checkboxCol) {
    return;
  }

  const row = range.getRow();
  const value = range.getValue();
  const characterNumber = sheet.getRange(row, 6).getValue(); // Column F (index 6)

  const logSheet = e.source.getSheetByName(logSheetName);
  const logData = logSheet.getRange(2, 1, logSheet.getLastRow() - 1, 7).getValues(); // Columns A:G

  const alreadyInitialized = logData.some(row => {
    const logCharNum = row[0];
    const reason = row[6];
    return logCharNum === characterNumber && reason === "Character Initialization";
  });

  // 🔁 If user tries to uncheck after initialization, reject it
  if (value === false && alreadyInitialized) {
    SpreadsheetApp.getUi().alert("This character has already been initialized and cannot be unchecked.");
    range.setValue(true); // Re-check the box
    return;
  }

  // ✅ Only continue initialization if box is being checked
  if (value !== true || alreadyInitialized) {
    return;
  }

  // (Continue with the rest of your initialization logic)
  const rowData = sheet.getRange(row, 1, 1, sheet.getLastColumn()).getValues()[0];

  const freeAffinity = rowData[4];    // E
  const firstEvent = rowData[6];      // G
  const startingBuild = rowData[7];   // H
  const startingTier = rowData[8];    // I

  if (!characterNumber || !firstEvent || !startingBuild || !startingTier) {
    SpreadsheetApp.getUi().alert("Please fill out all character data (F to I) before initializing.");
    range.setValue(false);
    return;
  }

  const newRow = Array(19).fill("");
  newRow[0] = characterNumber;
  newRow[1] = new Date();
  newRow[2] = firstEvent;
  newRow[3] = startingTier;
  newRow[4] = startingBuild;
  newRow[6] = "Character Initialization";
  newRow[14] = freeAffinity;
  newRow[15] = "1";
  newRow[16] = startingTier;
  newRow[17] = Session.getActiveUser().getEmail();

  logSheet.appendRow(newRow);
}

function findHighestCultivationTier(masterLogData, characterNumber) {
  const tierOrder = {
    "Iron": 1,
    "Silver": 2,
    "Gold": 3,
    "Jade": 4,
    "Saint": 5,
    "Sovereign": 6
  };
  
  let highestTier = null;
  let highestRank = -1;

  for (const row of masterLogData) {
    if (String(row[0]).trim() !== String(characterNumber).trim()) continue;

    const tier = row[16]; // Column Q (index 16)

    if (tier && tierOrder[tier] && tierOrder[tier] > highestRank) {
      highestTier = tier;
      highestRank = tierOrder[tier];
    }
  }

  return highestTier || ""; // Return empty string if no tiers found
}

function cleanAllSheets() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheets = ss.getSheets();

  const invisibleCharRegex = /[\u200B-\u200D\u200E\u200F\u202A-\u202E\uFEFF]/g;
  const nonPrintableRegex = /[^\x20-\x7E\n\r\t]/g;

  sheets.forEach(sheet => {
    const range = sheet.getDataRange();
    const values = range.getValues();

    let cleaned = false;

    const cleanedValues = values.map(row => row.map(cell => {
      if (typeof cell === 'string') {
        const cleanedCell = cell
          .replace(invisibleCharRegex, '')
          .replace(nonPrintableRegex, '')
          .trim();

        if (cleanedCell !== cell) cleaned = true;
        return cleanedCell;
      }
      return cell;
    }));

    if (cleaned) {
      range.setValues(cleanedValues);
      Logger.log(`✅ Cleaned: ${sheet.getName()}`);
    } else {
      Logger.log(`⚠️ Already clean: ${sheet.getName()}`);
    }
  });

  SpreadsheetApp.getUi().alert("🧼 Cleaning complete!");
}


function populateEditorList() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const file = DriveApp.getFileById(ss.getId());

  const editors = file.getEditors();
  const emails = editors.map(user => user.getEmail());

  const sheetName = "Rules Marshalls";
  let sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
  }

  // Clear previous entries starting from A2
  sheet.getRange("A2:A").clearContent();

  // Write new list of editors starting at A2
  sheet.getRange(2, 1, emails.length, 1).setValues(emails.map(e => [e]));
}

// ==== Form Response Sorting ==== //

/**
 * Sorts the form response sheet by timestamp column
 * This function should be called after form submissions to maintain chronological order
 */
function sortByTimestamp() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Form Responses");
  
  try {
    // Get the data range
    const dataRange = sheet.getDataRange();
    
    // Check if we have data (more than just headers)
    if (dataRange.getNumRows() <= 1) {
      console.log('No data to sort (only headers or empty sheet)');
      return;
    }
    
    // Sort by timestamp column (assuming it's column A)
    // Change the column number if your timestamp is in a different column
    // Exclude header row by sorting only data rows (row 2 onwards)
    const dataOnlyRange = sheet.getRange(2, 1, dataRange.getNumRows() - 1, dataRange.getNumColumns());
    dataOnlyRange.sort({column: 1, ascending: true}); // 1 = column A, true = ascending order (oldest first)
    
    console.log('Data sorted by timestamp successfully');
    
  } catch (error) {
    console.error('Error sorting data:', error);
  }
}

/**
 * Enhanced sorting function with more detailed logging
 * Use this for debugging or when you need more information about the sorting process
 */
function sortByTimestampDetailed() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Form Responses");
  
  try {
    // Get the data range
    const dataRange = sheet.getDataRange();
    const numRows = dataRange.getNumRows();
    const numCols = dataRange.getNumColumns();
    
    // Check if we have data
    if (numRows <= 1) {
      console.log('No data to sort (only headers or empty sheet)');
      return;
    }
    
    // Get the first few rows to check the structure
    const sampleData = sheet.getRange(1, 1, Math.min(3, numRows), numCols).getValues();
    console.log('Sample data structure before sorting:', sampleData);
    
    // Sort by timestamp column (column A)
    // Exclude header row by sorting only data rows (row 2 onwards)
    const dataOnlyRange = sheet.getRange(2, 1, dataRange.getNumRows() - 1, dataRange.getNumColumns());
    dataOnlyRange.sort({column: 1, ascending: true}); // 1 = column A, true = ascending (oldest first)
    
    console.log(`Sorted ${numRows - 1} data rows by timestamp`);
    
    // Log the first few rows after sorting
    const sortedData = sheet.getRange(1, 1, Math.min(3, numRows), numCols).getValues();
    console.log('After sorting:', sortedData);
    
  } catch (error) {
    console.error('Error sorting data:', error);
  }
}

/**
 * Analyzes the data structure to help identify timestamp columns
 * Run this first to understand your sheet structure
 */
function analyzeDataStructure() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Form Responses");
  
  try {
    const dataRange = sheet.getDataRange();
    const numRows = dataRange.getNumRows();
    const numCols = dataRange.getNumColumns();
    
    console.log(`Sheet has ${numRows} rows and ${numCols} columns`);
    
    if (numRows > 1) {
      // Show headers
      const headers = sheet.getRange(1, 1, 1, numCols).getValues()[0];
      console.log('Headers:', headers);
      
      // Show first few data rows
      const sampleData = sheet.getRange(2, 1, Math.min(3, numRows - 1), numCols).getValues();
      console.log('Sample data rows:', sampleData);
      
      // Check which columns contain timestamps
      for (let col = 1; col <= numCols; col++) {
        const cellValue = sheet.getRange(2, col).getValue();
        if (cellValue instanceof Date) {
          console.log(`Column ${col} contains timestamps`);
        }
      }
    }
    
  } catch (error) {
    console.error('Error analyzing data:', error);
  }
}

// ==== Automatic Sorting Triggers ==== //

// Store the last known row count
let lastRowCount = 0;

/**
 * Sets up the smart edit trigger that only sorts when new rows are added
 * Run this function once to enable automatic sorting
 */
function setupRowCountTrigger() {
  // Delete any existing triggers first
  const triggers = ScriptApp.getProjectTriggers();
  triggers.forEach(trigger => {
    if (trigger.getHandlerFunction() === 'onRowCountChange') {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  
  // Create new trigger
  ScriptApp.newTrigger('onRowCountChange')
    .for(SpreadsheetApp.getActiveSpreadsheet())
    .onEdit()
    .create();
    
  console.log('Row count trigger created successfully');
  
  // Initialize the row count
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Form Responses");
  if (sheet) {
    lastRowCount = sheet.getLastRow();
    console.log(`Initialized row count: ${lastRowCount}`);
  }
}

/**
 * Triggered on any edit to the spreadsheet
 * Only sorts when a new row is added to Form Responses sheet
 */
function onRowCountChange(e) {
  const sheet = e.source.getActiveSheet();
  
  // Only trigger for Form Responses sheet
  if (sheet.getName() !== 'Form Responses') {
    return;
  }
  
  const currentRowCount = sheet.getLastRow();
  
  // Only sort if a new row was added
  if (currentRowCount > lastRowCount) {
    lastRowCount = currentRowCount;
    
    // Wait a moment for the edit to complete
    Utilities.sleep(1000);
    
    // Sort the data
    sortByTimestamp();
    
    console.log(`New row added (${currentRowCount} total), data sorted`);
  }
}

/**
 * Manually reset the row count (useful for testing or if something goes wrong)
 */
function resetRowCount() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Form Responses");
  if (sheet) {
    lastRowCount = sheet.getLastRow();
    console.log(`Row count reset to: ${lastRowCount}`);
  }
}
