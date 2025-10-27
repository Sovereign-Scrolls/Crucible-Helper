function promptCharacterNumber() {
  const ui = SpreadsheetApp.getUi();
  const response = ui.prompt("Enter Character Number", "This will pull logistics data from the external sheet.", ui.ButtonSet.OK_CANCEL);

  if (response.getSelectedButton() === ui.Button.OK) {
    const characterNumber = response.getResponseText().trim();
    if (!characterNumber || isNaN(characterNumber)) {
      ui.alert("Please enter a valid numeric character number.");
      return;
    }
    importCharacterLogistics(characterNumber);
  }
}

function importCharacterLogistics(characterNumber) {
  const externalSheetId = '1-y0M0hVq4TNmloXel0u_2zCRe-hIminaFT4C3wzSTpA';
  const tabName = `Player ${characterNumber} Logistics Sheet`;

  const tierThresholds = [
    { name: "Iron", minBuild: 0 },
    { name: "Silver", minBuild: 120 },
    { name: "Gold", minBuild: 200 }
    // Add more if needed
  ];

  try {
    const externalSheet = SpreadsheetApp.openById(externalSheetId);
    const logisticsSheet = externalSheet.getSheetByName(tabName);

    if (!logisticsSheet) {
      SpreadsheetApp.getUi().alert(`❌ Logistics sheet not found:\nTab "${tabName}" is missing.`);
      return;
    }

    const rawData = logisticsSheet.getRange("V4:AB100").getValues()
      .filter(row => row.some(cell => cell !== ""));

    if (rawData.length === 0) {
      SpreadsheetApp.getUi().alert(`⚠️ No importable data found in "${tabName}".`);
      return;
    }

    const localSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("PC Advancement Staging");
    const user = Session.getActiveUser().getEmail();
    const now = new Date();

    let rowsToInsert = [];
    let buildTotal = 0;
    let currentTierIndex = 0;

    for (let i = 0; i < rawData.length; i++) {
      const row = rawData[i];

      const dateOverride = row[0];   // V
      const buildAdjRaw  = row[3];   // Y
      const note         = row[5];   // AA
      const loggedBy     = row[6];   // AB

      const buildAdj = parseFloat(String(buildAdjRaw).trim());

      if (isNaN(buildAdj)) {
        Logger.log(`⚠️ Skipping invalid build value on row ${i + 4}: "${buildAdjRaw}"`);
        continue;
      }

      // Skip row 0 (V4:AB4) — initial build
      if (i === 0) {
        buildTotal += buildAdj; // Use it for calculation but not insert
        continue;
      }

      let tierNow = tierThresholds[currentTierIndex];
      let tierNext = tierThresholds[currentTierIndex + 1];
      let remainingBuild = buildAdj;

      while (tierNext && (buildTotal + remainingBuild) >= tierNext.minBuild) {
        const buildNeeded = tierNext.minBuild - buildTotal;

        if (buildNeeded > 0) {
          // Insert a partial build row to hit threshold
          const rowData = Array(19).fill("");
          rowData[0] = characterNumber;
          rowData[1] = now;
          rowData[2] = dateOverride;
          rowData[3] = tierNow.name;
          rowData[4] = buildNeeded;
          rowData[6] = "Import";
          rowData[17] = user;
          rowData[18] = (note || "") + (loggedBy ? ` — ${loggedBy}` : "");
          rowsToInsert.push(rowData);

          buildTotal += buildNeeded;
          remainingBuild -= buildNeeded;
        }

        // Insert ascension row
        rowsToInsert.push(buildAscensionRow({
          charNum: characterNumber,
          date: now,
          overrideDate: dateOverride,
          fromTier: tierNow.name,
          toTier: tierNext.name,
          user
        }));

        currentTierIndex++;
        tierNow = tierThresholds[currentTierIndex];
        tierNext = tierThresholds[currentTierIndex + 1];
      }

      if (remainingBuild > 0) {
        // Insert the leftover build under new tier
        const rowData = Array(19).fill("");
        rowData[0] = characterNumber;
        rowData[1] = now;
        rowData[2] = dateOverride;
        rowData[3] = tierNow.name;
        rowData[4] = remainingBuild;
        rowData[6] = "Import";
        rowData[17] = user;
        rowData[18] = (note || "") + (loggedBy ? ` — ${loggedBy}` : "");
        rowsToInsert.push(rowData);

        buildTotal += remainingBuild;
      }
    }

    // === Check for Extra Essence HP Purchase ===
    const essenceValue = parseFloat(String(logisticsSheet.getRange("C9").getValue()).trim());
    if (!isNaN(essenceValue) && essenceValue > 0) {
      const lastValidDate = (() => {
        for (let j = rawData.length - 1; j >= 0; j--) {
          const val = rawData[j][0]; // column V
          if (val && val !== "") return val;
        }
        return ""; // fallback if none found
      })();

      const row = Array(19).fill("");
      row[0] = characterNumber;
      row[1] = now;
      row[2] = lastValidDate;
      row[3] = tierThresholds[currentTierIndex].name; // final tier
      row[4] = -Math.abs(essenceValue * 2); // negative build
      row[6] = "Buying Hit Points";
      row[10] = essenceValue; // Adjust Hit Points
      row[17] = user;
      row[18] = "Imported from PC Database";

      rowsToInsert.push(row);
    }

    const tierSlottingConfig = [
      { label: "Iron",   slotCell: "N2", perfectCell: "N4", tierIndex: 0 },
      { label: "Silver", slotCell: "O2", perfectCell: "O4", tierIndex: 1 },
      { label: "Gold",   slotCell: "P2", perfectCell: "P4", tierIndex: 2 },
    ];

    for (const { label, slotCell, perfectCell, tierIndex } of tierSlottingConfig) {
      const slotVal = parseFloat(String(logisticsSheet.getRange(slotCell).getValue()).trim());
      const perfectVal = parseFloat(String(logisticsSheet.getRange(perfectCell).getValue()).trim());

      // Find last date that character was still in this tier
      const tierBuildDate = (() => {
        let tempBuildTotal = 0;
        let latestValidDate = "";

        for (let j = 0; j < rawData.length; j++) {
          const row = rawData[j];
          const bAdj = parseFloat(String(row[3]).trim());
          if (!isNaN(bAdj)) tempBuildTotal += bAdj;

          if (tempBuildTotal >= tierThresholds[tierIndex + 1]?.minBuild) break;

          const dateCell = row[0];
          if (
            dateCell &&
            typeof dateCell === "object" && dateCell instanceof Date &&
            !isNaN(dateCell.getTime())
          ) {
            latestValidDate = dateCell;
          }
        }

        return latestValidDate;
      })();

      // Slotting Cores row
      if (!isNaN(slotVal) && slotVal > 0) {
        const row = Array(19).fill("");
        row[0] = characterNumber;
        row[1] = now;
        row[2] = tierBuildDate;
        row[3] = "Iron";               // cultivation tier is always the previous one
        row[5] = slotVal;
        row[6] = "Slotting Cores";
        row[12] = label;               // Tier of cores slotted
        row[17] = user;
        row[18] = "Imported from PC Database";
        rowsToInsert.push(row);
      }

      // Perfect Cultivation row
      if (!isNaN(perfectVal) && perfectVal > 0) {
        const row = Array(19).fill("");
        row[0] = characterNumber;
        row[1] = now;
        row[2] = tierBuildDate;
        row[3] = "Iron";                // cultivation tier remains Iron
        row[5] = perfectVal;
        row[6] = "Slotting Cores";
        row[12] = label;                // Tier of cores slotted
        row[13] = perfectVal * 0.1;     // Perfect Cultivation Points
        row[17] = user;
        row[18] = "Imported from PC Database";
        rowsToInsert.push(row);
      }
    }

    // === Raising Affinity Level from M13:S48 ===
    const affinityDataRange = logisticsSheet.getRange("M13:S48").getValues();
    const affinityColumnMap = [
      { colIndex: 1, tierLabel: "Iron", tierIndex: 0 },   // Column N
      { colIndex: 2, tierLabel: "Silver", tierIndex: 1 }, // Column O
      { colIndex: 3, tierLabel: "Gold", tierIndex: 2 },   // Column P
    ];

    const getLastTierBuildDate = (tierIndex) => {
      let tempBuildTotal = 0;
      let latestValidDate = "";

      for (let j = 0; j < rawData.length; j++) {
        const row = rawData[j];
        const bAdj = parseFloat(String(row[3]).trim());
        if (!isNaN(bAdj)) tempBuildTotal += bAdj;

        if (tempBuildTotal >= tierThresholds[tierIndex + 1]?.minBuild) break;

        const dateCell = row[0];
        if (
          dateCell &&
          typeof dateCell === "object" && dateCell instanceof Date &&
          !isNaN(dateCell.getTime())
        ) {
          latestValidDate = dateCell;
        }
      }

      return latestValidDate;
    };

    for (let rowOffset = 0; rowOffset < affinityDataRange.length; rowOffset += 3) {
      const name = affinityDataRange[rowOffset][0]; // M column

      if (!name) continue; // skip blank rows

      for (const { colIndex, tierLabel, tierIndex } of affinityColumnMap) {
        const level = affinityDataRange[rowOffset][colIndex];       // Tier level
        const pointCost = affinityDataRange[rowOffset + 2][colIndex]; // Tier point cost

        if (!level || !pointCost || isNaN(pointCost)) continue;

        const dateOverride = getLastTierBuildDate(tierIndex);

        const row = Array(19).fill("");
        row[0] = characterNumber;
        row[1] = now;
        row[2] = dateOverride;
        row[3] = tierLabel;               // Cultivation Tier
        row[5] = row[5] = -Math.abs(pointCost);               // Affinity Point Adjustment
        row[6] = "Raising Affinity Level";
        row[14] = sanitize(name);         // Affinity Name
        row[15] = level;                  // Affinity Level
        row[17] = user;
        row[18] = "Imported from PC Database";

        rowsToInsert.push(row);
      }
    }

    // === Importing Skills from A13:C42 ===
    const skillDataRange = logisticsSheet.getRange("A13:C42").getValues();

    // Find last build row date (any tier)
    const lastBuildDate = (() => {
      for (let j = rawData.length - 1; j >= 0; j--) {
        const dateCell = rawData[j][0];
        if (
          dateCell &&
          typeof dateCell === "object" && dateCell instanceof Date &&
          !isNaN(dateCell.getTime())
        ) {
          return dateCell;
        }
      }
      return "";
    })();

    for (let i = 0; i < skillDataRange.length; i++) {
      const [skillName, , buildCostRaw] = skillDataRange[i];

      if (!skillName || buildCostRaw === "" || isNaN(buildCostRaw)) continue;

      const buildCost = -Math.abs(parseFloat(buildCostRaw));

      const row = Array(19).fill("");
      row[0] = characterNumber;
      row[1] = now;
      row[2] = lastBuildDate;
      row[3] = tierThresholds[currentTierIndex].name; // Current tier after build import
      row[4] = buildCost;
      row[6] = "Buying Skill";             // Advancement Reason
      const skillInfo = getSkillType(skillName, characterNumber, rowsToInsert);
      row[7] = skillInfo.type;
      row[8] = skillInfo.name;
      row[9] = "1";
      row[17] = user;
      row[18] = "Imported from PC Database";

      rowsToInsert.push(row);
    }

    // === Importing Bulk Skill Purchases ===
    const skillBlocks = [
      { range: "A46:E65" },
      { range: "G3:K22" },
      { range: "G26:K45" },
      { range: "G49:K68" }
    ];

    for (const { range } of skillBlocks) {
      const blockData = logisticsSheet.getRange(range).getValues();

      for (let i = 0; i < blockData.length; i++) {
        const row = blockData[i];
        const skillName = row[0];
        const buildPerLevel = parseFloat(row[2]); // C or I
        const skillLevel = parseInt(row[4]);       // E or K

        if (!skillName || isNaN(buildPerLevel) || isNaN(skillLevel) || skillLevel <= 0) continue;

        const totalBuild = -Math.abs(buildPerLevel); 

        const rowData = Array(19).fill("");
        rowData[0] = characterNumber;
        rowData[1] = now;
        rowData[2] = lastBuildDate;
        rowData[3] = tierThresholds[currentTierIndex].name;
        rowData[4] = totalBuild;
        rowData[6] = "Buying Skill";
        const skillInfo = getSkillType(skillName, characterNumber, rowsToInsert);
        row[7] = skillInfo.type;
        row[8] = skillInfo.name;
        rowData[9] = skillLevel;
        rowData[17] = user;
        rowData[18] = "Imported from PC Database";

        rowsToInsert.push(rowData);
      }
    }



    // Insert to sheet
    const startRow = localSheet.getLastRow() + 1;
    localSheet.getRange(startRow, 1, rowsToInsert.length, rowsToInsert[0].length).setValues(rowsToInsert);

    SpreadsheetApp.getUi().alert(`✅ Imported ${rowsToInsert.length} row(s) for character ${characterNumber}.`);

  } catch (err) {
    SpreadsheetApp.getUi().alert(`❌ Error: ${err.message}`);
  }
}

function getSkillType(skillName, characterNumber, stagedRows = []) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  const commonSheet = ss.getSheetByName("Import: Common Skills");
  const raceSheet = ss.getSheetByName("Import: Race Skills");
  const affinitySheet = ss.getSheetByName("Import: Affinity Skills");

  const commonSkillList = commonSheet.getRange("A2:A").getValues().flat().filter(Boolean);
  const raceSkillData = raceSheet.getRange("A2:C").getValues().filter(row => row[0]);
  const affinitySkillData = affinitySheet.getRange("A2:B").getValues().filter(row => row[0]);

  const masterLogSheet = ss.getSheetByName("Master Logs");
  const masterLogData = masterLogSheet.getDataRange().getValues();
  const allLogs = [
    ...masterLogData.filter(row => row[0] == characterNumber),
    ...stagedRows.filter(row => row[0] == characterNumber)
  ];

  const characterAffinities = new Set(
    allLogs.map(row => row[14]).filter(Boolean).map(sanitize)
  );

  const pcsSheet = ss.getSheetByName("PCs");
  const pcsData = pcsSheet.getDataRange().getValues();
  const characterRace = sanitize((pcsData.find(row => row[5] == characterNumber) || [])[3] || "");

  const skillKey = sanitize(skillName);
  const matchSources = [];
  let resolvedName = null;

  // Common Skills
  for (const name of commonSkillList) {
    if (sanitize(name) === skillKey) {
      matchSources.push("Common");
      resolvedName = name;
      break;
    }
  }

  // Race Skills
  for (const [name, , race] of raceSkillData) {
    if (sanitize(name) === skillKey && sanitize(race) === characterRace) {
      matchSources.push(`Race: ${race}`);
      if (!resolvedName) resolvedName = name;
      break;
    }
  }

  // Affinity Skills
  const affinityMatches = affinitySkillData
    .filter(([name]) => sanitize(name) === skillKey);

  const affinityTypes = new Set(affinityMatches.map(([_, type]) => sanitize(type)));
  const intersectedAffinities = [...affinityTypes].filter(type => characterAffinities.has(type));

  if (intersectedAffinities.length === 1) {
    matchSources.push(intersectedAffinities[0]);
  } else if (intersectedAffinities.length > 1) {
    matchSources.push(intersectedAffinities.join(", "));
  }

  if (affinityMatches.length > 0 && !resolvedName) {
    resolvedName = affinityMatches[0][0];
  }

  return {
    type: matchSources.length > 0 ? matchSources.join(", ") : "Unknown",
    name: resolvedName || skillName
  };
}


// Helper to create ascension row
function buildAscensionRow({ charNum, date, overrideDate, fromTier, toTier, user }) {
  const row = Array(19).fill("");
  row[0] = charNum;
  row[1] = date;
  row[2] = overrideDate;
  row[3] = fromTier;
  row[6] = "Ascend";
  row[16] = toTier;
  row[17] = user;
  return row;
}