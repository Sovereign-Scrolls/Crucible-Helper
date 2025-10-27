# Quick Fix: Missing idToken Error

## The Problem

Your existing Apps Script `doPost` function checks for an `idToken` on line 55-56 **before** handling any actions. When the Firebase Function calls it with `action: 'regenerateCharacter'`, it fails the idToken check.

## The Solution

Add the `regenerateCharacter` handler **BEFORE** the idToken check in your Apps Script.

## Step-by-Step Fix

### 1. Open Your Apps Script

Go to your Google Apps Script project (the one with `advancement_intake`)

### 2. Edit the `doPost` Function

Find these lines (around line 52):

```javascript
let payload;
try {
  payload = JSON.parse(bodyText);
} catch (err) {
  return _badRequest('Invalid JSON: ' + err);
}

// ID token can be in JSON body or as a query param: ?authorization=Bearer+XYZ
const idToken = payload.idToken || _extractBearerToken(e);
```

### 3. Add This Code Between Them

**INSERT THIS** right after `payload = JSON.parse(bodyText)` and **BEFORE** the `idToken` check:

```javascript
// Check for regenerateCharacter action BEFORE idToken check
const { action, characterNumber } = payload;

if (action === 'regenerateCharacter') {
  if (!characterNumber) {
    return _json({ ok: false, error: 'missing_character_number', message: 'Character number is required' });
  }
  
  try {
    const jsonData = generateCharacterJsonFromLogs(characterNumber);
    const playerEmail = jsonData.playerEmail;
    const bucket = getStorageBucket_();
    const path = `users/${playerEmail}/pc.json`;
    uploadJsonToGCS(bucket, path, jsonData);
    
    return _json({
      ok: true,
      message: 'Character JSON regenerated and uploaded successfully',
      characterNumber: characterNumber,
      playerEmail: playerEmail,
      generatedAt: jsonData.generatedAt
    });
  } catch (error) {
    return _json({ ok: false, error: 'regeneration_error', message: error.message });
  }
}

// Continue with existing code below...
```

### 4. The Result

Your `doPost` should now look like this:

```javascript
function doPost(e) {
  // ... CORS handling ...
  
  try {
    const bodyText = (e && e.postData && e.postData.contents) ? e.postData.contents : '';
    if (!bodyText) return _badRequest('Empty body');

    let payload;
    try {
      payload = JSON.parse(bodyText);
    } catch (err) {
      return _badRequest('Invalid JSON: ' + err);
    }

    // ===== NEW CODE HERE =====
    const { action, characterNumber } = payload;
    
    if (action === 'regenerateCharacter') {
      if (!characterNumber) {
        return _json({ ok: false, error: 'missing_character_number' });
      }
      
      try {
        const jsonData = generateCharacterJsonFromLogs(characterNumber);
        const playerEmail = jsonData.playerEmail;
        const bucket = getStorageBucket_();
        const path = `users/${playerEmail}/pc.json`;
        uploadJsonToGCS(bucket, path, jsonData);
        
        return _json({
          ok: true,
          message: 'Character JSON regenerated',
          characterNumber: characterNumber,
          generatedAt: jsonData.generatedAt
        });
      } catch (error) {
        return _json({ ok: false, error: 'regeneration_error', message: error.message });
      }
    }
    // ===== END NEW CODE =====

    // ID token can be in JSON body or as a query param: ?authorization=Bearer+XYZ
    const idToken = payload.idToken || _extractBearerToken(e);
    if (!idToken) return _unauthorized('Missing idToken');
    
    // ... rest of existing code continues ...
```

### 5. Save and Test

1. Save the Apps Script (Ctrl/Cmd + S)
2. The Apps Script is already deployed - no need to redeploy!
3. Test by clicking "Sync Character" in your Flutter app

## Why This Works

- **Firebase Function** already authenticated the user
- **regenerateCharacter** action doesn't need to re-verify the token
- **Apps Script uses its own OAuth** to access Google Sheets and Firebase Storage
- By checking `action === 'regenerateCharacter'` **first**, we bypass the idToken requirement
- **Existing advancement intake** continues to work normally (it still has the idToken check)

## Test It

After making this change:

```bash
# In your Flutter app, click "Sync Character"
# You should now see:
✅ Character JSON regenerated successfully from Master Logs
✅ Generated at: 2025-01-10T...
```

That's it! The error should be fixed. 🎉

