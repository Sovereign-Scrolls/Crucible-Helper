// characterSetup.gs

function processCharacterSheet(characterData, shouldShare) {
  const bucket = "crucible-helper.firebasestorage.app";

  const [characterNumber, playerName] = characterData.split("|");
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const pcsSheet = ss.getSheetByName("PCs");
  const masterLogSheet = ss.getSheetByName("Master Logs");

  const templateId = "1_ErPD6mwU5vxaIWQMBntEV1F8dJAHPBo5k7fwGOAVK8";
  const rowIndex = pcsSheet.getRange("F2:F").getValues().flat().indexOf(Number(characterNumber)) + 2;

  if (rowIndex < 2) {
    throw new Error("Character not found in PCs sheet.");
  }

  const playerEmail = pcsSheet.getRange(rowIndex, 2).getValue();
  const path = `users/${playerEmail}/pc.json`;
  const newName = `${characterNumber} - ${playerName}`;
  const characterName = pcsSheet.getRange(rowIndex, 3).getValue();


  const newFile = DriveApp.getFileById(templateId).makeCopy(newName);
  const newSs = SpreadsheetApp.openById(newFile.getId());

  if (shouldShare && playerEmail) {
    try {
      newFile.addEditor(playerEmail);
      GmailApp.sendEmail(playerEmail,
        "Your Character Sheet is Ready!",
        `Hello ${playerName},\n\nYour character sheet has been created and shared with you!\n\nYou can access it here:\n${newFile.getUrl()}\n\nPlease let us know if you have any questions.\n\nThanks,\nThe Staff Team`
      );
    } catch (error) {
      Logger.log("Failed to send email to player: " + error);
      SpreadsheetApp.getUi().alert("\u26a0\ufe0f Character sheet was created, but email could not be sent.");
    }
  }

  const pcViewSheet = newSs.getSheetByName("PC View");
  if (pcViewSheet) pcViewSheet.getRange("B1").setValue(characterNumber);

  const advancementSheet = newSs.getSheetByName("Advancement Worksheet");
  if (advancementSheet) advancementSheet.getRange("A1").setValue(characterNumber);

  const allLogData = masterLogSheet.getRange(5, 1, masterLogSheet.getLastRow() - 4, 19).getValues();
  const matchingLogs = allLogData.filter(row => String(row[0]).trim() == String(characterNumber).trim());

  if (matchingLogs.length > 0 && matchingLogs[0].length > 0) {
    const newLogSheet = newSs.getSheetByName("Master Logs");
    if (newLogSheet) {
      newLogSheet.getRange(5, 1, matchingLogs.length, matchingLogs[0].length).setValues(matchingLogs);
    }
  }

  const pcsData = pcsSheet.getRange(2, 1, pcsSheet.getLastRow()-1, pcsSheet.getLastColumn()).getValues();
  const matchingPC = pcsData.find(row => row[5] == characterNumber);

  if (matchingPC && matchingPC.length > 0) {
    const newPCsSheet = newSs.getSheetByName("PCs");
    if (newPCsSheet) {
      newPCsSheet.getRange(2, 1, 1, matchingPC.length).setValues([matchingPC]);
    }
  } else {
    throw new Error(`No matching PC found for character number: ${characterNumber}`);
  }

  pcsSheet.getRange(rowIndex, 11).setValue(newFile.getUrl());

  generateAndUploadCharacterJson(newSs, characterNumber, characterName, playerName, playerEmail);
  SpreadsheetApp.getUi().alert("✅ JSON uploaded to Firebase Storage!");
  return true;
}

function generateCharacterJson(newSs, characterNumber, characterName, playerName, playerEmail) {
  const pcsSheet = newSs.getSheetByName("PCs");
  const masterLogSheet = newSs.getSheetByName("Master Logs");

  const pcsRow = pcsSheet.getRange(2, 1, 1, pcsSheet.getLastColumn()).getValues()[0];
  const masterLogData = masterLogSheet.getRange(5, 1, masterLogSheet.getLastRow()-4, 22).getValues();

  const race = pcsRow[3];
  const freeAffinity = pcsRow[4];
  const buildTotal = pcsRow[7];
  const extraHitPoints = pcsRow[8]; //This cannot be correct. Need to fix! Nothing on the PCs tab has extra

  const skills = masterLogData
    .filter(row => row[0] == characterNumber && row[7] && row[8])
    .map(row => {
      const skillName = row[8];
      const skillType = row[7];
      const skillLevel = row[9];
      const skillFrequency = getSkillFrequency(skillName, skillType);
      return {
        name: skillName,
        type: skillType,
        level: skillLevel,
        frequency: skillFrequency
      };
    });

  const tiers = {};
  ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"].forEach(tier => {
    const tierAffinities = masterLogData.filter(row => row[0] == characterNumber && row[3] === tier && row[14]);
    tiers[tier] = {
      affinityPointsTotal: tierAffinities.reduce((sum, row) => sum + (row[5] || 0), 0),
      affinities: tierAffinities.map(row => ({
        name: row[14],
        level: row[15],
        affinityPointCost: row[5]
      }))
    };
  });

  const output = {
    playerName,
    characterName,
    characterNumber: Number(characterNumber),
    race,
    freeAffinity,
    cultivationTier: findHighestCultivationTier(masterLogData, characterNumber),
    buildTotal: buildTotal || 0,
    extraHitPoints: extraHitPoints || 0,
    skills,
    tiers
  };
  output.version = `v${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;

  return output; 
}

