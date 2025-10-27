function verifyPC() {
  const ui = SpreadsheetApp.getUi();
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const masterSheet = ss.getSheetByName("Master Logs");

  const response = ui.prompt("Verify Character", "Enter the character number to verify:", ui.ButtonSet.OK_CANCEL);

  if (response.getSelectedButton() === ui.Button.OK) {
    const characterNumber = response.getResponseText().trim();
    if (!characterNumber || isNaN(characterNumber)) {
      ui.alert("❌ Please enter a valid numeric character number.");
      return;
    }
    verifyCharacterLogs(characterNumber); // placeholder for next step
  }
}


function verifyCharacterLogs(characterNumber) {
  const ui = SpreadsheetApp.getUi();
  Logger.log(`🧪 Verifying logs for character ${characterNumber}...`);

  // TODO: Add actual validation logic here

  ui.alert(`✅ Verification started for character ${characterNumber}.\n\n(Next: Add validation rules.)`);
}


function verifyCharacterLogs(characterNumber) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const ui = SpreadsheetApp.getUi();

  const masterSheet = ss.getSheetByName("Master Logs");
  const pcsSheet = ss.getSheetByName("PCs");

  const masterData = masterSheet.getDataRange().getValues();
  const pcsData = pcsSheet.getDataRange().getValues();

  // 🔍 Step 1: Find the expected Free Affinity for this character
  const pcRow = pcsData.find(row => String(row[5]).trim() === String(characterNumber).trim());
  if (!pcRow) {
    ui.alert(`❌ Character ${characterNumber} not found in the PCs tab.`);
    return;
  }

  const expectedAffinity = sanitize(pcRow[4]); // Column E = Free Affinity

  // 🔍 Step 2: Search for matching "Character Initialization" entry in Master Logs
  const initEntry = masterData.find(row =>
    String(row[0]).trim() === String(characterNumber).trim() &&   // Column A = char number
    String(row[6]).trim() === "Character Initialization" &&       // Column G = reason
    sanitize(row[14]) === expectedAffinity &&                     // Column O = affinity
    Number(row[15]) === 1                                         // Column P = level 1
  );

  if (!initEntry) {
    ui.alert(`❌ Initialization error for character ${characterNumber}:\n\nNo matching "Character Initialization" entry with ${expectedAffinity} affinity and level 1.`);
  } else {
    ui.alert(`✅ Character ${characterNumber} has valid initialization for ${expectedAffinity}.`);
  }

  // 🔍 Step 3: Validate Ascension Chain
  const tierOrder = ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"];

  // Get all ascension rows for this character
  const ascendLogs = masterData.filter(row =>
    String(row[0]).trim() === String(characterNumber).trim() &&
    String(row[6]).trim() === "Ascend"
  );

  const errors = [];

  const ascendedTiers = new Set();

  ascendLogs.forEach(row => {
    const fromTier = sanitize(row[3]);
    const toTier = sanitize(row[14]);

    const fromIndex = tierOrder.indexOf(fromTier);
    const toIndex = tierOrder.indexOf(toTier);

    // Check: one tier up only
    if (toIndex !== fromIndex + 1) {
      errors.push(`❌ Invalid ascension: ${fromTier} → ${toTier} (should be one step up)`);
    }

    // Check: only one Ascend per fromTier
    if (ascendedTiers.has(fromTier)) {
      errors.push(`❌ Multiple Ascend entries from ${fromTier}`);
    } else {
      ascendedTiers.add(fromTier);
    }
  });

  // Check: no skipped tiers
  for (let i = 0; i < tierOrder.length - 1; i++) {
    const fromTier = tierOrder[i];
    const toTier = tierOrder[i + 1];

    if (ascendedTiers.has(toTier) && !ascendedTiers.has(fromTier)) {
      errors.push(`❌ Invalid sequence: Ascended to ${toTier} without ascending from ${fromTier}`);
    }
  }

  // ✅ Show results
  if (errors.length > 0) {
    ui.alert(`Character ${characterNumber} Ascension Errors:\n\n${errors.join("\n")}`);
  } else {
    ui.alert(`✅ Character ${characterNumber} ascension is valid.`);
  }


}
