//Advancement.gs

// ==== Advancement Worksheet Actions ==== //

function submitAdvancement() {
  deselectUserSelection();
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Advancement Worksheet");
  const logSheet = ss.getSheetByName("PC Advancement Staging");
  const user = Session.getActiveUser().getEmail();

  const action = sheet.getRange("B9").getValue().toString().trim();
  const subaction = sheet.getRange("B10").getValue().toString().trim();

  if (!sheet.getRange("A2").getValue()) {
    SpreadsheetApp.getUi().alert("Character Number is required.");
  return;
  }

  let rowData = Array(17).fill("");

  // General fields
  rowData[0] = sheet.getRange("A2").getValue();  // Character Number
  rowData[1] = new Date();                       // Log Date
  rowData[2] = sheet.getRange("B5").getValue();  // Date Override
  rowData[3] = sheet.getRange("B2").getValue();  // Cultivation Tier
  rowData[17] = Session.getActiveUser().getEmail();

  // -- Adding Build Actions --
  if (action === "Adding Build" && subaction === "Attending Event") {
    rowData[4] = sheet.getRange("E18").getValue();  // Build Adjustment
    rowData[18] = sheet.getRange("F18").getValue(); // Notes
    rowData[6] = subaction;

  } else if (action === "Adding Build" && subaction === "Consuming Cores") {
    rowData[4] = sheet.getRange("D28").getValue();  // Build
    rowData[18] = sheet.getRange("G28").getValue(); // Notes
    rowData[6] = subaction;

  } else if (action === "Adding Build" && subaction === "Donations") {
    rowData[4] = sheet.getRange("E8").getValue();
    rowData[6] = subaction;

  // -- Spending Build: Buying Skill --
  } else if (action === "Spending Build" && subaction === "Buying Skill") {
    rowData[4] = sheet.getRange("G49").getValue(); // Build Adjustment
    if (sheet.getRange("D49").getValue() === "Player Race") {
    rowData[7] = sheet.getRange("F13").getValue(); // Skill Type
    } else {
      rowData[7] = sheet.getRange("D49").getValue(); // Skill Type
    }
    rowData[8] = sheet.getRange("E49").getValue(); // Skill Name
    rowData[9] = sheet.getRange("F49").getValue() // Skill Level
    
    rowData[6] = subaction;
    logSheet.appendRow(rowData);
  
    // Second skill if "Illusional Race"
    if (rowData[8].toString().trim() === "Illusional Race") {
      const illusionRow = [...rowData];
      illusionRow[6] = "Illusional Race - " + sheet.getRange("H49").getValue();
      illusionRow[4] = -Math.abs(sheet.getRange("I49").getValue());
      illusionRow[8] = sheet.getRange("D48").getValue(); // Second skill name
      logSheet.appendRow(illusionRow);
    }

    // Add "Trained" row
    const isTrained = rowData[8].toString().trim().toLowerCase() === "trained";
    if (isTrained) {
      // Row for training cost
      const trainedCostRow = [...rowData];
      trainedCostRow[6] = "Trained - " + sheet.getRange("H49").getValue(); // Reason
      trainedCostRow[4] = -Math.abs(sheet.getRange("I49").getValue());     // Negative build adjustment
      trainedCostRow[8] = sheet.getRange("H49").getValue(); // Skill Name
      logSheet.appendRow(trainedCostRow);
    }


    resetAdvancementForm();
    return; // Prevent duplicate appending

  // -- Spending Build: Buying HP --
  } else if (action === "Spending Build" && subaction === "Buying Hit Points") {
    rowData[4] = sheet.getRange("E58").getValue();
    rowData[10] = sheet.getRange("D58").getValue();
    rowData[6] = subaction;

  // -- Affinity Point Actions --
  } else if (action === "Adding Affinity Points" && subaction === "Slotting Cores") {
    rowData[5] = sheet.getRange("F68").getValue();  // Affinity Point Adjustment
    rowData[11] = sheet.getRange("F68").getValue(); // Slotted Cores
    rowData[12] = sheet.getRange("D68").getValue(); // Tier of core slotted
    rowData[13] = sheet.getRange("G68").getValue(); // Perfect Cultivation Points
    rowData[18] = sheet.getRange("H68").getValue(); // Note
    rowData[6] = subaction;

  } else if (action === "Spending Affinity points" && subaction === "Raising Affinity Level") {
    rowData[5] = sheet.getRange("F78").getValue();  // Affinity Point Adjustment
    rowData[14] = sheet.getRange("D78").getValue(); // Affinity
    rowData[15] = sheet.getRange("E78").getValue(); // Affinity Level
    rowData[6] = subaction;

  // -- Special Actions --
  } else if (action === "Special" && subaction === "Ascend") {
    const buildGain = sheet.getRange("F87").getValue();
    const ascendedAffinity = sheet.getRange("H13").getValue();  // new: affinity name
    
    if (buildGain) {
      // Main Ascend row
      rowData[4] = buildGain;
      rowData[16] = sheet.getRange("E87").getValue(); // Editor override
      rowData[6] = subaction;
      logSheet.appendRow(rowData);
    }

    if (ascendedAffinity) {
      // Add Ascension Bonus Affinity row
      const affinityRow = Array(19).fill("");
      affinityRow[0] = sheet.getRange("A2").getValue();  // Character Number
      affinityRow[1] = new Date();                       // Log Date
      affinityRow[3] = sheet.getRange("E87").getValue();                      // Cultivation Tier
      affinityRow[5] = 0;                                // Affinity Point Adjustment
      affinityRow[14] = ascendedAffinity;                // Affinity
      affinityRow[15] = 1;                               // Affinity Level
      affinityRow[6] = "Ascension Bonus";                // Advancement Reason
      affinityRow[17] = Session.getActiveUser().getEmail();
      logSheet.appendRow(affinityRow);
    }
    resetAdvancementForm();
    return;
  } else if (action === "Special" && subaction === "Marshal Override") {
      if (sheet.getRange("D98").getValue().toString().trim() !== "") {
        rowData[3] = sheet.getRange("D98").getValue();
      }
    rowData[4] = sheet.getRange("E98").getValue();  // Build Adjustment
    rowData[5] = sheet.getRange("F98").getValue();  // Affinity Point Adjustment
    rowData[11] = sheet.getRange("G98").getValue(); // Slotted Cores
    rowData[12] = sheet.getRange("H98").getValue(); // Tier of cores Slotted
    rowData[18] = sheet.getRange("I98").getValue(); // Note
    rowData[6] = subaction;

  } else if (action === "Special" && subaction === "Slotting Core 2 Tiers Higher (Reset)") {
    rowData[4] = sheet.getRange("E108").getValue();
    rowData[5] = sheet.getRange("F108").getValue();
    rowData[6] = subaction;
  }

  // Append single-entry row (default flow)
  logSheet.appendRow(rowData);
  resetAdvancementForm();
}

function resetAdvancementForm() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Advancement Worksheet");

  sheet.getRange("B9:B10").clearContent();

  const inputRanges = [
    "B5",             // Clear Date override
    "E18:F18",        // Attended Event
    "D28:E28","G28",   // Consuming Cores
    "E38",            // Donations
    "D49:F49", "H49", // Buying Skill
    "D58",            // Buying Hit Points
    "D68:E68",        // Sloting Cores and Perfect Cultivation
    "D78:E78",        // Raising Affinity Level
    "D98:I98",        // Marshal Override
    "D108"            // Sloting Core 2 Tiers Higher (Reset)
  ];

  inputRanges.forEach(range => sheet.getRange(range).clearContent());

  const sectionStarts = [15, 25, 35, 45, 55, 65, 75, 85, 95, 105];
  sectionStarts.forEach(row => sheet.hideRows(row, 10));
}


function submitStagedToMasterLogs() {
  /**
   * Enhanced version that moves staged data to Master Logs, syncs to Firestore, 
   * and calculates affected characters
   */
  
  const ui = SpreadsheetApp.getUi();
  
  try {
    // Step 1: Move data from staging to master logs
    console.log('📋 Moving staged data to Master Logs...');
    
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const stagingSheet = ss.getSheetByName("PC Advancement Staging");
    const masterSheet = ss.getSheetByName("Master Logs");

    const startRow = 5;
    const lastRow = stagingSheet.getLastRow();
    const numRows = lastRow - startRow + 1;

    if (numRows < 1) {
      ui.alert("There are no entries to submit.");
      return;
    }

    const dataRange = stagingSheet.getRange(startRow, 1, numRows, stagingSheet.getLastColumn());
    const data = dataRange.getValues();

    const rowsToSubmit = data.filter(row => row.some(cell => cell !== "")); // Skip blank rows

    if (rowsToSubmit.length === 0) {
      ui.alert("No data to move (rows may be blank).");
      return;
    }

    // Move the data
    masterSheet.getRange(masterSheet.getLastRow() + 1, 1, rowsToSubmit.length, rowsToSubmit[0].length).setValues(rowsToSubmit);
    dataRange.clearContent(); // Clear the submitted rows

    // Step 2: Upload JSON for each unique character
    console.log(`✅ Moved ${rowsToSubmit.length} rows to Master Logs.\n🔄 Generating character JSON files...`);
    
    const uniqueCharacters = [...new Set(rowsToSubmit.map(row => row[0]))];
    let jsonUploadErrors = 0;

    // Process characters one at a time to avoid data interference
    for (const characterNumber of uniqueCharacters) {
      try {
        console.log(`🔄 Processing character ${characterNumber}...`);
        const jsonData = generateCharacterJsonFromLogs(characterNumber);
        const playerEmail = jsonData.playerEmail;
        const bucket = "crucible-helper.firebasestorage.app";
        const path = `users/${playerEmail}/pc.json`;

        uploadJsonToGCS(bucket, path, jsonData);
        console.log(`✅ Generated JSON for character ${characterNumber}`);
      } catch (error) {
        console.error(`❌ Failed to generate/upload JSON for character ${characterNumber}: ${error.message}`);
        jsonUploadErrors++;
      }
    }

    // Step 3: Trigger sync to Firestore
    console.log('📤 Syncing Master Logs to Firestore...\nThis may take a moment.');
    
    const syncResult = triggerSyncMasterLog();
    
    // Step 4: Calculate affected characters
    console.log('🔢 Calculating character progressions...\nThis may take a moment for multiple characters.');
    
    let calculationResults = null;
    let calculationErrors = [];
    
    try {
      // For now, we need the character IDs (uid_characterNumber format)
      // Since we only have character numbers from the staging data, 
      // we'll need to let the sync complete first and then the calculateCharacter 
      // function will be called separately or triggered from the Firebase side
      
      console.log(`Characters that need calculation: ${uniqueCharacters.join(', ')}`);
      
    } catch (calcError) {
      console.error('Error during character calculations:', calcError);
      calculationErrors.push(calcError.message);
      console.error(`⚠️ Character calculations encountered errors:\n${calcError.message}\n\nData has been synced successfully, but character calculations may need to be run manually.`);
    }
    
    // Step 5: Show final success message
    const successMessage = `🎉 Process Complete!

📋 Moved: ${rowsToSubmit.length} rows to Master Logs
👥 Characters: ${uniqueCharacters.length} unique characters updated
📤 Sync Results:
  • Written: ${syncResult.stats.written} records
  • Mirrored: ${syncResult.stats.mirrored} character records
  • Deleted: ${syncResult.stats.deletedFromCharacters} obsolete records

✅ All data has been successfully synced to Firestore!

The following characters need their progressions calculated:
${uniqueCharacters.join(', ')}

Note: Character calculations require character UIDs which are resolved during sync.
Run individual character calculations manually if needed.

${jsonUploadErrors > 0 ? `⚠️ JSON Upload Errors: ${jsonUploadErrors} characters failed to upload` : ''}
${calculationErrors.length > 0 ? '⚠️ Note: Some character calculations may need manual attention.' : ''}`;

    ui.alert(successMessage);
    
    return {
      success: true,
      rowsMoved: rowsToSubmit.length,
      charactersAffected: uniqueCharacters.length,
      syncStats: syncResult.stats,
      jsonUploadErrors: jsonUploadErrors,
      calculationErrors: calculationErrors
    };

  } catch (error) {
    console.error('Error in submitStagedToMasterLogsWithSync:', error);
    
    const errorMessage = `❌ Error during submission/sync process:

${error.message}

Please check the script logs for more details.`;
    
    ui.alert(errorMessage);
    throw error;
  }
}


function resetStagingSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const stagingSheet = ss.getSheetByName("PC Advancement Staging");

  const startRow = 5;
  const lastRow = stagingSheet.getLastRow();
  const numRows = lastRow - startRow + 1;

  if (numRows > 0) {
    stagingSheet.getRange(startRow, 1, numRows, stagingSheet.getLastColumn()).clearContent();
  }
}

function handleAdvancementUI(e) {
  const sheet = e.source.getSheetByName("Advancement Worksheet");
  if (!sheet || e.range.getSheet().getName() !== "Advancement Worksheet") return;

  const range = e.range;
  const cell = range.getA1Notation();

  if (cell === "B9" || cell === "B10") {
    const action = sheet.getRange("B9").getValue().toString().trim();
    const subaction = sheet.getRange("B10").getValue().toString().trim();

    const allSections = [15, 25, 35, 45, 55, 65, 75, 85, 95, 105];
    sheet.showRows(1, sheet.getMaxRows());
    allSections.forEach(row => sheet.hideRows(row, 10));

    let sectionToShow = null;

    if (action === "Adding Build" && subaction === "Attending Event") sectionToShow = 15;
    else if (action === "Adding Build" && subaction === "Consuming Cores") sectionToShow = 25;
    else if (action === "Adding Build" && subaction === "Donations") sectionToShow = 35;
    else if (action === "Spending Build" && subaction === "Buying Skill") sectionToShow = 45;
    else if (action === "Spending Build" && subaction === "Buying Hit Points") sectionToShow = 55;
    else if (action === "Adding Affinity Points" && subaction === "Slotting Cores") sectionToShow = 65;
    else if (action === "Spending Affinity points" && subaction === "Raising Affinity Level") sectionToShow = 75;
    else if (action === "Special" && subaction === "Ascend") sectionToShow = 85;
    else if (action === "Special" && subaction === "Marshal Override") sectionToShow = 95;
    else if (action === "Special" && subaction === "Slotting Core 2 Tiers Higher (Reset)") sectionToShow = 105;

    if (sectionToShow) {
      sheet.showRows(sectionToShow, 10);
    }
  }
}