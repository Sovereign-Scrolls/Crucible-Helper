# Regenerate Character from Master Logs Setup Guide

## Overview

This setup enables the "Sync Character" function to regenerate character JSON files directly from the Master Logs Google Sheet through a Firebase Function, ensuring that character data always reflects the latest information in the sheet.

## How It Works

When you click "Sync Character" in the Flutter app:

1. **Flutter calls Firebase Function** → `regenerateCharacterFromMasterLogs`
2. **Firebase calls your existing Apps Script** → Sends `{ action: 'regenerateCharacter', characterNumber: '89' }`
3. **Apps Script generates JSON** → Calls `generateCharacterJsonFromLogs(characterNumber)`
4. **Uploads to Storage** → Fresh `pc.json` uploaded to Firebase Storage
5. **Flutter fetches** → App downloads the updated JSON
6. **Firestore updated** → `calculateCharacter` function processes the data
7. **Sheet refreshes** → Character sheet page reloads with new data

## Setup Instructions

### Step 1: Add Handler to Your Existing Apps Script

Your Apps Script already has the functions needed (`generateCharacterJsonFromLogs`, `uploadJsonToGCS`, etc.). You just need to add a handler to your `doPost` function.

**Option A: If you don't have a `doPost` function yet**

Add this to your Google Apps Script:

```javascript
function doPost(e) {
  try {
    const requestBody = JSON.parse(e.postData.contents);
    const { action, characterNumber } = requestBody;
    
    if (action === 'regenerateCharacter') {
      const jsonData = generateCharacterJsonFromLogs(characterNumber);
      const playerEmail = jsonData.playerEmail;
      const bucket = getStorageBucket_();
      const path = `users/${playerEmail}/pc.json`;
      uploadJsonToGCS(bucket, path, jsonData);
      
      return ContentService.createTextOutput(JSON.stringify({
        ok: true,
        message: 'Character JSON regenerated and uploaded successfully',
        characterNumber: characterNumber,
        playerEmail: playerEmail,
        generatedAt: jsonData.generatedAt
      }))
      .setMimeType(ContentService.MimeType.JSON);
    }
    
    // Handle other actions...
    return ContentService.createTextOutput(JSON.stringify({
      ok: false,
      error: 'unknown_action'
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
```

**Option B: If you already have a `doPost` function**

Just add this case to your existing logic:

```javascript
if (action === 'regenerateCharacter') {
  const jsonData = generateCharacterJsonFromLogs(characterNumber);
  const playerEmail = jsonData.playerEmail;
  const bucket = getStorageBucket_();
  const path = `users/${playerEmail}/pc.json`;
  uploadJsonToGCS(bucket, path, jsonData);
  
  return ContentService.createTextOutput(JSON.stringify({
    ok: true,
    message: 'Character JSON regenerated and uploaded successfully',
    characterNumber: characterNumber,
    generatedAt: jsonData.generatedAt
  }))
  .setMimeType(ContentService.MimeType.JSON);
}
```

### Step 2: Verify Your Apps Script Deployment

Your Apps Script should already be deployed as a Web App (it's in your `config.json`):
- URL: `https://script.google.com/macros/s/AKfycbx.../exec`
- This is the same deployment used for advancement intake

**You don't need to create a new deployment!** The Firebase Function will use your existing one.

### Step 3: Deploy the Firebase Function

```bash
cd functions
firebase deploy --only functions:regenerateCharacterFromMasterLogs
```

### Step 4: Test the Setup

#### Test Firebase Function (Recommended First Step)

You can test the Firebase Function directly from your browser or Postman:

```bash
# Get your Firebase ID token first (from browser dev tools when logged into the app)
curl -X POST \
  https://us-central1-crucible-helper.cloudfunctions.net/regenerateCharacterFromMasterLogs \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"characterNumber": "89"}'
```

Expected response:
```json
{
  "ok": true,
  "message": "Character regenerated successfully from Master Logs",
  "characterNumber": "89",
  "generatedAt": "2025-01-10T12:34:56.789Z"
}
```

#### Test in Flutter App

1. Build and run the Flutter app: `flutter run -d chrome --web-port=8080`
2. Sign in with a character that exists in Master Logs
3. Open the character sheet
4. Click the three-dot menu (⋮) → **"Sync Character Data"**
5. Watch for these messages:
   - "Regenerating from Master Logs..."
   - "✅ Character data updated!" (if data changed)
   - OR "ℹ️ Character data is up to date" (if no changes)

## How to Verify It's Working

### Check Firebase Function Logs

```bash
firebase functions:log --only regenerateCharacterFromMasterLogs
```

Look for:
```
🔄 Regenerating character 89 from Master Logs via Apps Script
📥 Apps Script response: {...}
✅ Character 89 regenerated from Master Logs
```

### Check Apps Script Logs

1. In Apps Script editor, click **"Executions"** (left sidebar)
2. Look for recent `doPost` executions
3. Click on an execution to see detailed logs
4. Look for: `✅ Successfully regenerated and uploaded pc.json for character X`

### Check Firebase Storage

1. Open Firebase Console → **Storage**
2. Navigate to: `users/{email}/pc.json`
3. Check the **"Updated"** timestamp - it should match when you clicked Sync
4. Download the file and verify the `generatedAt` field

### Check Flutter Console Logs

```
🔄 Calling Firebase Function to regenerate character 89 from Master Logs
📥 Regenerate response status: 200
📥 Regenerate response body: {"ok":true,"message":"Character JSON regenerated..."}
✅ Character JSON regenerated successfully from Master Logs
✅ Generated at: 2025-01-10T12:34:56.789Z
```

## Troubleshooting

### Error: "Apps Script URL not configured in config.json"

**Solution:** 
- Verify `functions/config.json` has the `google_sheets.apps_script_url` field
- The URL should be your existing Apps Script Web App deployment URL

### Error: "Character X not found in PCs sheet"

**Solution:** 
- Verify the character number exists in the "PCs" sheet (column F)
- Check that the character has entries in the "Master Logs" sheet

### Error: "GCS upload failed: 401"

**Solution:**
- Apps Script doesn't have permission to upload to Firebase Storage
- Re-authorize the script by running any function that uses `ScriptApp.getOAuthToken()`

### Error: "Request to Apps Script timed out"

**Solution:**
- The Apps Script is taking too long (> 30 seconds)
- Check Apps Script logs for errors
- Verify the Master Logs sheet isn't too large

### Character sheet doesn't refresh after sync

**Possible causes:**
1. The `generatedAt` timestamp didn't change
   - Check if Apps Script actually regenerated the file
   - Verify the JSON was uploaded with a new timestamp
2. Firebase Storage wasn't updated
   - Check Storage console for the file's "Updated" time
3. Data is cached
   - Try reloading the Flutter app completely

## Architecture

```
Flutter App
    ↓ (HTTP POST with auth token)
Firebase Function (regenerateCharacterFromMasterLogs)
    ↓ (HTTP POST with action + characterNumber)
Google Apps Script (doPost handler)
    ↓ (reads Master Logs)
generateCharacterJsonFromLogs()
    ↓ (uploads JSON)
Firebase Storage (users/{email}/pc.json)
    ↓ (fetched by Flutter)
Flutter App (refreshed character sheet)
```

## Security Notes

- **Firebase Function handles auth** - verifies user can regenerate their own character
- **Apps Script URL is server-side** - not exposed to Flutter app
- **Super admins can regenerate any character** - regular users only their own
- **All communication is over HTTPS** - encrypted end-to-end

## No New Deployment Needed!

**Key Point:** You're using your **existing** Apps Script deployment. You don't need to:
- ❌ Create a new Apps Script project
- ❌ Deploy a new Web App
- ❌ Update any URLs in Flutter (it already uses Firebase Function)

You only need to:
- ✅ Add the `regenerateCharacter` handler to your existing `doPost`
- ✅ Deploy the Firebase Function
- ✅ Test and enjoy!

## Summary

✅ Apps Script handler added to existing `doPost`  
✅ Firebase Function deployed  
✅ No new Apps Script deployment needed  
✅ Flutter app calls Firebase Function (already updated)  
✅ Sync Character regenerates from Master Logs  
✅ Character sheet refreshes with new data  

Your sync flow is now complete! 🎉
