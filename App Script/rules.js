function sanitize(value) {
  if (typeof value === 'string') {
    return value
      .replace(/[\u200B-\u200D\u200E\u200F\u202A-\u202E\uFEFF]/g, '') // invisible & bidi controls
      .replace(/[^\x20-\x7E\n\r\t]/g, '') // non-printable ASCII
      .trim();
  }
  return value;
}

function generateRulesJson() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  const tabNames = [
    "Import: Common Skills",
    "Import: Race",
    "Import: Race Skills",
    "Import: Affinity",
    "Import: Affinity Skills",
    "Import: Prereqs",
    "Import: Cultivation Tier",
    "Import: Status Effects",
    "Import: Frequency"
  ];

  const rulesData = {};

  const rawSheets = {};

  tabNames.forEach(name => {
    try {
      const sheet = ss.getSheetByName(name);
      if (!sheet) return;

      const displayName = name.replace(/^Import[:\s]*/i, "").trim();
      const rawData = sheet.getDataRange().getValues();

      if (rawData.length < 2) return;

      const headers = rawData[0].map(header => sanitize(header));
      const dataRows = rawData.slice(1);

      const structured = dataRows.map(row => {
        const obj = {};
        headers.forEach((key, i) => {
          obj[key] = sanitize(row[i]);
        });
        return obj;
      });

      rawSheets[displayName] = structured;
    } catch (err) {
      Logger.log(`❌ Failed to load ${name}: ${err.message}`);
    }
  });

  // Begin assembling rulesData with special treatment for Races and Race Skills
  rulesData["Common Skills"] = rawSheets["Common Skills"] || [];
  rulesData["Affinity"] = rawSheets["Affinity"] || [];
  rulesData["Affinity Skills"] = rawSheets["Affinity Skills"] || [];
  rulesData["Prereqs"] = rawSheets["Prereqs"] || [];
  rulesData["Cultivation Tier"] = rawSheets["Cultivation Tier"] || [];
  rulesData["Status Effects"] = rawSheets["Status Effects"] || [];
  rulesData["Frequency"] = rawSheets["Frequency"] || [];

  // === Nest Race Skills inside Races ===
  const races = (rawSheets["Race"] || []).map(race => ({
    ...race,
    "Race Skills": []
  }));

  const raceSkills = rawSheets["Race Skills"] || [];

  raceSkills.forEach(skill => {
    const targetRace = skill["Race"];
    const match = races.find(r => r["Name"] === targetRace);
    if (match) {
      match["Race Skills"].push(skill);
    }
  });

  rulesData["Races"] = races;

  return rulesData;
}




function uploadRulesJson() {
  const rulesJson = generateRulesJson();
  const bucket = "crucible-helper.firebasestorage.app";
  const path = "rules.json";

  try {
    uploadJsonToGCS(bucket, path, rulesJson);
  } catch (uploadErr) {
    Logger.log("❌ GCS Upload Error: " + uploadErr.message);
    SpreadsheetApp.getUi().alert("❌ Failed to upload to Firebase:\n" + uploadErr.message);
    return; // exit early if this fails
  }
  SpreadsheetApp.getUi().alert("✅ Rules JSON uploaded to Firebase as 'rules.json'");
}


