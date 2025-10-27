//PCSheets.gs

// ==== PC Setup and Advancement ==== //

function initializePCSheet(newSs, characterNumber, pcsSheet, masterLogSheet, playerEmail, characterName, playerName) {
  const pcViewSheet = newSs.getSheetByName("PC View");
  const advancementSheet = newSs.getSheetByName("Advancement Worksheet");
  const newLogSheet = newSs.getSheetByName("Master Logs");
  const newPCsSheet = newSs.getSheetByName("PCs");

  if (pcViewSheet) pcViewSheet.getRange("B1").setValue(characterNumber);
  if (advancementSheet) advancementSheet.getRange("A1").setValue(characterNumber);

  const masterLogData = masterLogSheet.getRange(5, 1, masterLogSheet.getLastRow()-4, 19).getValues();
  const matchingLogs = masterLogData.filter(row => String(row[0]).trim() == String(characterNumber).trim());
  if (newLogSheet && matchingLogs.length) newLogSheet.getRange(5, 1, matchingLogs.length, matchingLogs[0].length).setValues(matchingLogs);

  const pcsData = pcsSheet.getRange(2, 1, pcsSheet.getLastRow()-1, pcsSheet.getLastColumn()).getValues();
  const matchingPC = pcsData.find(row => row[5] == characterNumber);
  if (newPCsSheet && matchingPC) newPCsSheet.getRange(2, 1, 1, matchingPC.length).setValues([matchingPC]);

  generateCharacterJsonAndUpload(newSs, characterNumber, characterName, playerName, playerEmail);
}

