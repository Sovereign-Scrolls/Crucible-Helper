
function getStorageBucket_() {
  const bucket = PropertiesService.getScriptProperties().getProperty('STORAGE_BUCKET');
  if (!bucket) {
    throw new Error(
      'Missing Script Property STORAGE_BUCKET. ' +
      'Set it via Project Settings → Script properties, or run setStorageBucket_("your-bucket").'
    );
  }
  return bucket;
}

function uploadJsonToStorage(destinationPath, jsonData) {
  return uploadJsonToGCS(getStorageBucket_(), destinationPath, jsonData);
}

function uploadSelectedCharacter(characterData) {
  const [characterNumber] = characterData.split("|");
  const jsonData = generateCharacterJsonFromLogs(characterNumber); // contains playerEmail, etc.
  const playerEmail = jsonData.playerEmail;

  const path = `users/${playerEmail}/pc.json`;
  // Upload JSON as before (bucket comes from Script Property)
  uploadJsonToGCS(getStorageBucket_(), path, jsonData);

  // Now upload the QR right next to it: users/{email}/qr.png
  //generateAndUploadQrForPc_(jsonData);
}

function generateAndUploadCharacterJson(newSs, characterNumber, characterName, playerName, playerEmail) {
  const jsonData = generateCharacterJson(newSs, characterNumber, characterName, playerName, playerEmail);
  const path = `users/${playerEmail}/pc.json`; // 🛠 NOT encoded anymore
  uploadJsonToStorage(path, jsonData);
  generateAndUploadQrForPc_(jsonData);
}

function uploadJsonToGCS(bucketName, destinationPath, jsonData) {
  const token = ScriptApp.getOAuthToken();
  const url = [
    "https://storage.googleapis.com/upload/storage/v1/b",
    encodeURIComponent(bucketName),
    "o?uploadType=media&name=" + encodeURIComponent(destinationPath)
  ].join("/");

  const res = UrlFetchApp.fetch(url, {
    method:   "post",
    contentType: "application/json",
    payload:    JSON.stringify(jsonData),
    headers:    { Authorization: "Bearer " + token },
    muteHttpExceptions: true
  });

  const code = res.getResponseCode();
  const body = res.getContentText();
  if (code !== 200 && code !== 201) {
    throw new Error("GCS upload failed: " + code + " – " + body);
  }
  return JSON.parse(body);
}

function generateCharacterJsonFromLogs(characterNumber) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const pcsSheet = ss.getSheetByName("PCs");
  const masterLogSheet = ss.getSheetByName("Master Logs");

  const pcsData = pcsSheet.getRange(2, 1, pcsSheet.getLastRow() - 1, pcsSheet.getLastColumn()).getValues();
  const pcRow = pcsData.find(row => String(row[5]).trim() === String(characterNumber).trim());

  if (!pcRow) throw new Error(`Character ${characterNumber} not found in PCs sheet.`);

  const [
    playerName,         // A
    playerEmail,        // B
    characterName,      // C
    race,               // D
  ] = pcRow;

  const masterData = masterLogSheet.getRange(5, 1, masterLogSheet.getLastRow() - 4, 22).getValues();
  const filteredLogs = masterData.filter(row => String(row[0]).trim() === String(characterNumber).trim());

  // 🧠 Cultivation tier from highest Q value (index 16)
  const cultivationTier = (() => {
    const tierOrder = ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"];
    let highestIndex = -1;

    filteredLogs.forEach(row => {
      const tier = row[16];
      const idx = tierOrder.indexOf(tier);
      if (idx > highestIndex) highestIndex = idx;
    });

    return highestIndex >= 0 ? tierOrder[highestIndex] : "";
  })();




  // 🔢 Build total from column E (index 4)
  const buildLog = (() => {
    const total = filteredLogs.reduce((sum, row) => {
      const value = parseFloat(row[4]);
      return value > 0 ? sum + value : sum;
    }, 0);

    // Lookup max build total required to ascend for the current tier
    let needToAscend = null;
    try {
      const tierSheet = ss.getSheetByName("Import: Cultivation Tier");
      const tierValues = tierSheet.getRange("A2:C").getValues(); // Column A = Tier, C = Max Build

      const tierRow = tierValues.find(row => sanitize(row[0]) === cultivationTier);
      if (tierRow && tierRow[1]) {
        const maxBuild = parseFloat(tierRow[2]);
        if (!isNaN(maxBuild)) {
          needToAscend = Math.max(0, maxBuild - total); // ensure it's not negative
        }
      }
    } catch (err) {
      Logger.log("❌ Failed to calculate needToAscend: " + err.message);
    }



    const unspent = filteredLogs.reduce((sum, row) => {
      const value = parseFloat(row[4]);
      return sum + (isNaN(value) ? 0 : value);
    }, 0);

    let starting = null;
    const gains = [];

    for (const row of filteredLogs) {
      const value = parseFloat(row[4]);
      if (!value || value <= 0) continue;

      const rawDate = row[2] || row[1];
      const formattedDate = (rawDate instanceof Date)
        ? rawDate.toISOString().split("T")[0]
        : String(rawDate);

      let reason = row[6] || "";
      let note = row[18] || "";

      // Blank out 'Import' reason
      if (reason.trim().toLowerCase() === "import") {
        reason = "";
      }

      // Remove case-insensitive MXAPP references from notes
      note = note.replace(/mxapps?/gi, "").trim();

      if (!starting) {
        starting = {
          amount: value,
          date: formattedDate
        };
        continue;
      }

      gains.push({
        amount: value,
        reason,
        note,
        date: formattedDate
      });
    }

    return {
      total,
      unspent,
      needToAscend,
      starting,
      gains
    };
  })();

  // HitPoint Breakdown
  const hitPointBreakdown = (() => {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const essenceSheet = ss.getSheetByName("Import: Body Essence-DR Chart");
    const essenceData = essenceSheet.getRange("A2:B").getValues().filter(row => row[0] !== "");

    const tiersList = ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"];
    const base = 5;
    const tierBonuses = {};
    let totalBodyBonus = 0;

    const getEssenceSumUpTo = (level) => {
      return essenceData
        .filter(row => parseInt(row[0]) <= level)
        .reduce((sum, row) => {
          const gain = row[1] === "" ? 5 : parseFloat(row[1]);
          return sum + (isNaN(gain) ? 0 : gain);
        }, 0);
    };

    tiersList.forEach(tier => {
      const rows = filteredLogs.filter(row => row[3] === tier && row[14] === "Body");
      const tierLevel = rows.reduce((sum, row) => {
        const lvl = parseInt(row[15]);
        return (!isNaN(lvl) ? sum + lvl : sum);
      }, 0);

      const tierBonus = getEssenceSumUpTo(tierLevel);
      tierBonuses[`body${tier}`] = tierBonus;
      totalBodyBonus += tierBonus;
    });

    const extra = filteredLogs.reduce((sum, row) => sum + (parseFloat(row[10]) || 0), 0);

    return {
      total: base + extra + totalBodyBonus,
      base,
      extra,
      ...tierBonuses
    };
  })();

  // HitPoint Breakdown
  const drBreakdown = (() => {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const essenceSheet = ss.getSheetByName("Import: Body Essence-DR Chart");
    const essenceData = essenceSheet.getRange("A2:C").getValues().filter(row => row[0] !== "");

    const tiersList = ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"];
    const tierBonuses = {};
    let totalDR = 0;

    const getDRSumUpTo = (level) => {
      let sum = 0;
      for (let i = 0; i < essenceData.length; i++) {
        const essenceLevel = essenceData[i][0];
        const drValue = parseFloat(essenceData[i][2]) || 0;

        if (essenceLevel > level) break;
        sum += drValue;
      }
      return sum;
    };

    tiersList.forEach(tier => {
      const rows = filteredLogs.filter(row => row[3] === tier && row[14] === "Body");
      const tierLevel = rows.reduce((max, row) => {
        const lvl = parseInt(row[15]);
        return (!isNaN(lvl) && lvl > max) ? lvl : max;
      }, 0);

      const tierDR = getDRSumUpTo(tierLevel);
      tierBonuses[`dr${tier}`] = tierDR;
      totalDR += tierDR;
    });

    return {
      total: totalDR,
      ...tierBonuses
    };
  })();

  // 🧠 Skills
  const skillMap = new Map();

  filteredLogs
    .filter(row => row[7] && row[8]) // Has Type and Name
    .forEach(row => {
      const name = row[8];
      const type = row[7];
      const key = `${name}|||${type}`;
      const level = parseInt(row[9]) || 0;

      if (!skillMap.has(key)) {
        const details = getSkillDetails(name, type);

        // Calculate total real cost from the logs
        const realCost = filteredLogs
          .filter(log =>
            log[6] === "Buying Skill" &&
            sanitize(log[7]) === sanitize(type) &&
            sanitize(log[8]) === sanitize(name)
          )
          .reduce((sum, log) => sum + (parseFloat(log[4]) || 0), 0);

        skillMap.set(key, {
          name,
          type,
          level,
          frequency: details.frequency,
          verbal: details.verbal,
          description: details.description,
          baseCost: details.baseCost,
          realCost: Math.abs(realCost),
          delivery: details.delivery
        });
      } else {
        skillMap.get(key).level += level;
      }
    });

  const skills = Array.from(skillMap.values());

  
  // === Affinity Breakdown and effectLevel Calculation ===
  const tiersList = ["Iron", "Silver", "Gold", "Jade", "Saint", "Sovereign"];
  const affinityMap = {}; // Final structure
  const tierIndexMap = Object.fromEntries(tiersList.map((t, i) => [t, i]));
  const currentTierIndex = tiersList.indexOf(cultivationTier);

  // Collect all affinity levels by tier
  tiersList.forEach(tier => {
    const rows = filteredLogs.filter(row => row[3] === tier && row[14]);
    rows.forEach(row => {
      const name = row[14];
      const level = parseInt(row[15]);
      if (!name || isNaN(level)) return;

      if (!affinityMap[name]) affinityMap[name] = {};
      affinityMap[name][tier] = (affinityMap[name][tier] || 0) + level;
    });
  });

  // Compute effectLevel for each affinity
  for (const [name, tiers] of Object.entries(affinityMap)) {
    let effectLevel = 0;
    for (const tier of tiersList) {
      const level = tiers[tier] || 0;
      const tierIdx = tierIndexMap[tier];
      if (tierIdx < currentTierIndex) {
        effectLevel += Math.max(0, level - 2);
      } else if (tierIdx === currentTierIndex) {
        effectLevel += level;
      }
    }
    affinityMap[name].effectLevel = effectLevel;
  }

  // === Affinity Points Summary ===
  const affinityPoints = (() => {
    // Extract values from Import: Cultivation Tier table
    const tierSheet = ss.getSheetByName("Import: Cultivation Tier");
    const tierValues = tierSheet.getRange("A2:C8").getValues(); // [Tier, Slots, MaxPoints]

    // Create lookup map from tier → maxPoints (column C)
    const tierMaxMap = Object.fromEntries(tierValues.map(row => [row[0], row[2]]));

    // Sum of column F (affinity point adjustment), column N (perfect cultivation points)
    const pointTotal = filteredLogs
      .filter(row => parseFloat(row[5]) >= 0)
      .reduce((sum, row) => sum + (parseFloat(row[5]) || 0), 0);

    const pointUnspent = Math.abs(
      filteredLogs.reduce((sum, row) => sum + (parseFloat(row[5]) || 0), 0)
    );

    const perfectPointsTotal = filteredLogs
      .filter(row => row[13])
      .reduce((sum, row) => sum + (parseFloat(row[13]) || 0), 0);

    const maxPoints = Math.floor((tierMaxMap[cultivationTier] || 0) - 40 + perfectPointsTotal);

    // Tier-specific
    const tierPointTotal = filteredLogs
      .filter(row => row[3] === cultivationTier && parseFloat(row[5]) >= 0)
      .reduce((sum, row) => sum + (parseFloat(row[5]) || 0), 0);

    const tierPointUnspent = Math.abs(
      filteredLogs
        .filter(row => row[3] === cultivationTier)
        .reduce((sum, row) => sum + (parseFloat(row[5]) || 0), 0)
    );

    const tierPointMax = Math.floor(80 + filteredLogs
      .filter(row => row[3] === cultivationTier && row[13])
      .reduce((sum, row) => sum + (parseFloat(row[13]) || 0), 0));

    const tierPointUnslotted = tierPointMax - tierPointTotal;

    return {
      affinityPointsTotal: pointTotal,
      affinityPointsMax: maxPoints,
      affinityPointUnspent: pointUnspent,
      affinityTierPointsTotal: tierPointTotal,
      affinityTierPointsMax: tierPointMax,
      affinityTierPointUnspent: tierPointUnspent,
      affinityTierPointsUnslotted: tierPointUnslotted
    };
  })();


  return {
    characterNumber: Number(characterNumber),
    playerName,
    characterName,
    playerEmail,
    race,
    build: buildLog,
    affinityPoints,
    hitPoints: hitPointBreakdown,
    dr: drBreakdown,
    cultivationTier,
    skills,
    affinities: affinityMap,
    version: "2025.06.02.v1",
    generatedAt: new Date().toISOString()
  };
}

function uploadAllCharacters() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const pcsSheet = ss.getSheetByName("PCs");
  const data = pcsSheet.getDataRange().getValues();

  let uploadCount = 0;
  let errorCount = 0;

  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    const characterNumber = row[5]; // Column F = index 5

    if (characterNumber && !isNaN(characterNumber)) {
      try {
        const jsonData = generateCharacterJsonFromLogs(characterNumber);
        const playerEmail = jsonData.playerEmail;
        const path = `users/${playerEmail}/pc.json`;

        uploadJsonToGCS(getStorageBucket_(), path, jsonData);
        generateAndUploadQrForPc_(jsonData);
        
        uploadCount++;
      } catch (error) {
        Logger.log(`❌ Failed for character ${characterNumber}: ${error.message}`);
        errorCount++;
      }
    }
  }

  SpreadsheetApp.getUi().alert(`✅ Upload complete.\nSuccess: ${uploadCount}\nErrors: ${errorCount}`);
}

function doPost(e) {
  try {
    // Parse the incoming request
    const payload = JSON.parse(e.postData.contents);
    const { action, characterNumber } = payload;
    
    // Handle regenerateCharacter action
    if (action === 'regenerateCharacter') {
      if (!characterNumber) {
        return ContentService.createTextOutput(JSON.stringify({
          ok: false,
          error: 'missing_character_number',
          message: 'Character number is required'
        }))
        .setMimeType(ContentService.MimeType.JSON);
      }
      
      // Call your existing functions!
      const jsonData = generateCharacterJsonFromLogs(characterNumber);
      const playerEmail = jsonData.playerEmail;
      const bucket = getStorageBucket_();
      const path = `users/${playerEmail}/pc.json`;
      uploadJsonToGCS(bucket, path, jsonData);
      
      // Return success
      return ContentService.createTextOutput(JSON.stringify({
        ok: true,
        message: 'Character JSON regenerated and uploaded successfully',
        characterNumber: characterNumber,
        playerEmail: playerEmail,
        generatedAt: jsonData.generatedAt
      }))
      .setMimeType(ContentService.MimeType.JSON);
    }
    
    // Unknown action
    return ContentService.createTextOutput(JSON.stringify({
      ok: false,
      error: 'unknown_action',
      message: `Unknown action: ${action}`
    }))
    .setMimeType(ContentService.MimeType.JSON);
    
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      ok: false,
      error: 'server_error',
      message: error.message
    }))
    .setMimeType(ContentService.MimeType.JSON);
  }
}
