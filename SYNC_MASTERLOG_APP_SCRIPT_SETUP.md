# Sync MasterLog App Script Setup Guide

## Overview

This App Script function allows you to trigger the `syncMasterLogs` Firebase function from Google Apps Script. This is useful for:

- Manual triggering of sync operations
- Scheduled automatic syncing 
- Integration with Google Sheets workflows
- Administrative automation

## Features

The App Script provides several functions:
- **Manual sync triggering** with Firebase authentication
- **Connection testing** to verify Firebase function availability
- **Custom parameter support** for different spreadsheets/sheets
- **Comprehensive error handling** and logging
- **Scheduled trigger setup** (with proper authentication)

## Setup Instructions

### Step 1: Create the Google Apps Script Project

1. Go to [script.google.com](https://script.google.com)
2. Click **"New project"**
3. Name it **"Crucible MasterLog Sync"**

### Step 2: Add the Script Code

1. Delete the default `Code.gs` content
2. Copy the entire content from `App Script/sync_masterlog_trigger` file
3. Paste it into your Google Apps Script project
4. Save the project (Ctrl/Cmd + S)

### Step 3: Configure Script Properties

The script uses your existing Firebase service account credentials from script properties. You already have these set:

- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY` 
- `FIREBASE_SERVICE_ACCOUNT`

#### Set Up Sync-Specific Properties

1. In your Apps Script project, run the function: **`setupSyncMasterLogProperties()`**
2. This will automatically configure the sync-specific properties:
   - `SYNC_MASTERLOG_URL`
   - `SYNC_MASTERLOG_CONTAINER_DOC_ID`
   - `SYNC_MASTERLOG_SHEET_NAME`
   - `SYNC_MASTERLOG_SPREADSHEET_ID`

#### Manual Setup (Alternative)

If you prefer to set properties manually:

1. Go to **Project Settings** → **Script Properties**
2. Add these optional properties (or use defaults):
   ```
   SYNC_MASTERLOG_URL = https://us-central1-crucible-helper.cloudfunctions.net/syncMasterLogs
   SYNC_MASTERLOG_CONTAINER_DOC_ID = root
   SYNC_MASTERLOG_SHEET_NAME = Master Logs
   SYNC_MASTERLOG_SPREADSHEET_ID = 1SD16oPmNp3b1V3rLrUS37O5DC8kd9-Cwrn3Zrboo6-0
   ```

### Step 4: Test the Setup

1. In your Apps Script project, run: **`setupSyncMasterLogProperties()`**
2. Then run: **`testConnection()`**
3. Check the **"Execution transcript"** for results
4. You should see: `✅ Sync masterlog endpoint is reachable`

## Usage Instructions

### Automated Sync (Recommended Method)

1. **One-time setup:**
   ```javascript
   // Run this once to configure properties
   setupSyncMasterLogProperties();
   ```

2. **Run the sync:**
   ```javascript
   // Run this to trigger sync (uses service account automatically)
   triggerSyncMasterLog();
   ```

3. **Check the results:**
   ```javascript
   // Successful response includes:
   {
     success: true,
     message: "Master Logs sync complete",
     stats: {
       cleared: 0,
       written: 150,
       mirrored: 75,
       deletedFromCharacters: 5,
       diagnostics: { ... }
     }
   }
   ```

### Manual Token Sync (Fallback Method)

If service account authentication fails, you can use manual tokens:

1. **Get Firebase ID token from Flutter app** (super admin required)
2. **Run with manual token:**
   ```javascript
   const token = 'eyJhbGciOiJSUzI1NiIs...'; // Your Firebase ID token
   const result = callSyncMasterLogWithToken(token);
   console.log(result);
   ```

### Available Functions

#### Primary Functions

##### 1. `triggerSyncMasterLog()`
**Main automated function** - uses service account authentication.

```javascript
// Automated sync (recommended)
triggerSyncMasterLog();
```

##### 2. `setupSyncMasterLogProperties()`
**One-time setup** - configures script properties with defaults.

```javascript
// Run once to set up configuration
setupSyncMasterLogProperties();
```

##### 3. `testConnection()`
**Test connectivity** to the Firebase function endpoint.

```javascript
testConnection(); // Returns true if endpoint is accessible
```

#### Configuration Functions

##### 4. `updateSyncMasterLogProperty(key, value)`
**Update specific settings** after initial setup.

```javascript
// Update spreadsheet ID
updateSyncMasterLogProperty('SYNC_MASTERLOG_SPREADSHEET_ID', 'new-spreadsheet-id');

// Update sheet name
updateSyncMasterLogProperty('SYNC_MASTERLOG_SHEET_NAME', 'Different Sheet Name');
```

#### Manual Token Functions (Fallback)

##### 5. `callSyncMasterLogWithToken(idToken, options)`
**Manual sync with Firebase ID token.**

```javascript
// Basic usage
callSyncMasterLogWithToken('your-firebase-id-token');

// With custom options
callSyncMasterLogWithToken('your-firebase-id-token', {
  containerDocId: 'root',
  sheetName: 'Master Logs',
  spreadsheetId: 'your-spreadsheet-id'
});
```

##### 6. `syncMasterLogWithCustomParams(idToken, containerDocId, sheetName, spreadsheetId)`
**Manual sync with specific parameters.**

```javascript
syncMasterLogWithCustomParams(
  'your-firebase-id-token',
  'root',                           // containerDocId
  'Master Logs',                    // sheetName  
  '1SD16oPmNp3b1V3rLrUS37O5DC8kd9-Cwrn3Zrboo6-0' // spreadsheetId
);
```

#### Utility Functions

##### 7. `showUsageInstructions()`
**Display detailed usage instructions** in the console.

```javascript
showUsageInstructions(); // Shows comprehensive help
```

### Default Configuration

The script comes pre-configured with:
- **Firebase Function URL:** `https://us-central1-crucible-helper.cloudfunctions.net/syncMasterLogs`
- **Default Container:** `root`
- **Default Sheet:** `Master Logs`
- **Default Spreadsheet:** `1SD16oPmNp3b1V3rLrUS37O5DC8kd9-Cwrn3Zrboo6-0`

## Troubleshooting

### Common Issues

#### 1. "Failed to get Firebase ID token"
**Solution:** 
- Ensure you're signed in as a super admin in the Flutter app
- Get the ID token manually from browser developer tools
- Use `callSyncMasterLogWithToken()` with the manual token

#### 2. "HTTP 401: Missing authorization header"
**Solution:**
- Your Firebase ID token may be expired or invalid
- Get a fresh token from the Flutter app
- Ensure the token includes "Bearer " prefix if added manually

#### 3. "HTTP 403: User must be super admin"  
**Solution:**
- Only super admin users can trigger sync masterlog
- Verify your user has super admin privileges in Firestore
- Check the `users` collection for your user document

#### 4. "Sync masterlog endpoint is not reachable"
**Solution:**
- Check your internet connection
- Verify the Firebase function is deployed
- Ensure the project ID in CONFIG matches your Firebase project

### Getting Firebase ID Token

**Method 1: Browser Developer Tools**
1. Open Flutter app and sign in
2. Open Developer Tools (F12)
3. Go to Network tab
4. Look for requests with `Authorization: Bearer ...` headers
5. Copy the token after "Bearer "

**Method 2: Console Inspection**
1. Open Flutter app and sign in  
2. Open Developer Tools Console
3. Run: `localStorage` or `sessionStorage`
4. Look for Firebase-related tokens

## Security Notes

- **ID tokens expire** - typically after 1 hour
- **Super admin required** - only super admin users can run sync
- **Tokens are sensitive** - don't share or log ID tokens
- **HTTPS only** - all communication is encrypted
- **Firebase Auth** - leverages existing Firebase security

## Scheduling (Advanced)

For automated syncing, you can set up time-based triggers:

```javascript
// Example: Run daily at 2 AM
ScriptApp.newTrigger('triggerSyncMasterLog')
  .timeBased()
  .everyDays(1)
  .atHour(2)
  .create();
```

**Requirements for scheduling:**
- Service account authentication must be configured
- Super admin service account key required
- Additional security setup needed

## Integration with Existing Scripts

You can call the sync function from other Apps Script projects:

```javascript
// From another Apps Script project
function myCustomWorkflow() {
  // Your existing logic...
  
  // Trigger sync masterlog
  const token = getCurrentUserIdToken(); // Your auth method
  const syncResult = callSyncMasterLogWithToken(token);
  
  if (syncResult.success) {
    console.log('Sync completed:', syncResult.stats);
    // Continue with your workflow...
  }
}
```

## Support

If you encounter issues:

1. **Check the Apps Script logs** - Execution transcript shows detailed error info
2. **Verify authentication** - Ensure super admin access and valid tokens
3. **Test connection** - Run `testConnection()` to verify endpoint access
4. **Check Firebase Console** - Look at Functions logs for server-side errors
5. **Validate parameters** - Ensure spreadsheet IDs and sheet names are correct

## Example Complete Workflow

```javascript
// Complete example of manual sync
function runMasterLogSync() {
  try {
    // Step 1: Test connection
    console.log('Testing connection...');
    if (!testConnection()) {
      throw new Error('Cannot reach sync endpoint');
    }
    
    // Step 2: Run sync with your token
    console.log('Starting sync...');
    const token = 'YOUR_FIREBASE_ID_TOKEN_HERE';
    const result = callSyncMasterLogWithToken(token);
    
    // Step 3: Check results
    console.log('Sync completed successfully!');
    console.log('Records written:', result.stats.written);
    console.log('Records mirrored:', result.stats.mirrored);
    console.log('Records deleted:', result.stats.deletedFromCharacters);
    
    return result;
    
  } catch (error) {
    console.error('Sync failed:', error.message);
    throw error;
  }
}
```

This guide should help you get started with automated MasterLog syncing using Google Apps Script!
