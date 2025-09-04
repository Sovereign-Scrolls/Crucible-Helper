# Troubleshooting Submission Issues

## Common Error: "Failed to fetch" or CORS Error

This error typically occurs when the Google Apps Script is not properly configured or deployed.

## Step-by-Step Troubleshooting

### 1. Verify Google Apps Script Deployment

**Check your script deployment settings:**

1. Open your Google Apps Script project
2. Click "Deploy" → "Manage deployments"
3. Click the pencil icon (edit) next to your deployment
4. Ensure these settings:
   - **Type**: Web app
   - **Execute as**: Me
   - **Who has access**: Anyone
   - **Version**: New version (if needed)

### 2. Test the Script URL Directly

**Test in browser:**
```
https://script.google.com/macros/s/AKfycby-ls0uwxES9dIRYk0Xh4DlzM-XOB1uUyKU_peLMr4JkQFTzNH9DXpNvnYhAynq018w/exec
```

You should see: `{"ok":true,"message":"Crucible intake endpoint is alive."}`

### 3. Configure Firebase Authentication

**Update your Google Apps Script configuration:**

In `App Script/advancement_intake`, update the CONFIG section:

```javascript
const CONFIG = {
  // If your Flutter PWA uses Firebase Auth (web):
  FIREBASE: {
    API_KEY: 'AIzaSyD6pJb56UjgUI2Pk5fFoHYTazY843Xciho', // Your Firebase API key
    PROJECT_ID: 'crucible-helper' // Your Firebase project ID
  },
  
  SHEETS: {
    AFFINITY: 'Affinity Changes',
    SKILL:    'Skill Changes', 
    ESSENCE:  'Essence Changes'
  }
};
```

### 4. Check Google Apps Script Logs

**View execution logs:**
1. Open your Google Apps Script project
2. Click "Executions" in the left sidebar
3. Look for recent executions and any error messages

### 5. Verify Spreadsheet Setup

**Ensure your Google Sheets has the required tabs:**
- "Affinity Changes"
- "Skill Changes" 
- "Essence Changes"

### 6. Test with Simple Payload

**Test with minimal data:**
```json
{
  "idToken": "your_firebase_token_here",
  "affinityChanges": [],
  "skillChanges": [],
  "essenceChanges": []
}
```

## Alternative Solutions

### Option 1: Use JSONP (if CORS persists)

If CORS issues continue, you can modify the Google Apps Script to support JSONP:

```javascript
function doPost(e) {
  // Add CORS headers
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
  
  // Handle preflight requests
  if (e.parameter.callback) {
    return ContentService.createTextOutput(
      e.parameter.callback + '(' + JSON.stringify({ ok: true }) + ')'
    ).setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  
  // Rest of your existing code...
}
```

### Option 2: Use Firebase Functions (Recommended)

Instead of Google Apps Script, consider using Firebase Functions which have better CORS support:

1. Create a Firebase Function
2. Deploy it to your Firebase project
3. Update the Flutter app to use the Firebase Function URL

## Debug Information

When testing, check the browser console (F12) for:
- Network requests
- CORS errors
- Response status codes
- Response bodies

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| CORS Error | Ensure script is deployed as web app with "Anyone" access |
| 403 Forbidden | Check "Execute as" is set to "Me" |
| 404 Not Found | Verify the script URL is correct |
| Invalid JSON | Check the payload format matches expected structure |
| Token Error | Ensure Firebase API key is configured in the script |

## Getting Help

If issues persist:
1. Check the browser console for detailed error messages
2. Verify all configuration steps above
3. Test the script URL directly in a browser
4. Check Google Apps Script logs for server-side errors
