# Google Apps Script Setup Guide

## Step 1: Create New Google Apps Script Project

1. Go to [script.google.com](https://script.google.com)
2. Click "New project"
3. Name it "Crucible Advancement Intake"

## Step 2: Copy the Code

1. Delete the default `Code.gs` content
2. Copy the entire content from `App Script/advancement_intake` file
3. Paste it into your Google Apps Script project

## Step 3: Configure the Script

**Update the CONFIG section in your script:**

```javascript
const CONFIG = {
  // If your Flutter PWA uses Firebase Auth (web):
  FIREBASE: {
    API_KEY: 'AIzaSyD6pJb56UjgUI2Pk5fFoHYTazY843Xciho', // Your Firebase API key
    PROJECT_ID: 'crucible-helper' // Your Firebase project ID
  },
  
  SHEETS: {
    AFFINITY: 'Affinity Changes', // Email | Time Stamp | Affinity Name | Change
    SKILL:    'Skill Changes',    // Email | Time Stamp | Skill Name | Type | Change
    ESSENCE:  'Essence Changes'   // Email | Time Stamp | Change
  },
  
  // Optional fallback if this project is ever converted to standalone:
  SPREADSHEET_ID: ''
};
```

## Step 4: Create Google Sheets

1. Create a new Google Sheets document
2. Add three sheets with these exact names:
   - `Affinity Changes`
   - `Skill Changes`
   - `Essence Changes`
3. **Important**: Make sure the script and spreadsheet are in the same Google account

## Step 5: Deploy as Web App

1. In your Google Apps Script project, click **"Deploy"** → **"New deployment"**
2. Configure these settings:
   - **Type**: Web app
   - **Execute as**: Me (your email address)
   - **Who has access**: Anyone (even anonymous)
   - **Version**: New version
3. Click **"Deploy"**
4. **Authorize** the script when prompted:
   - Click "Authorize access"
   - Choose your Google account
   - Click "Advanced" → "Go to [Project Name] (unsafe)"
   - Click "Allow"
5. Copy the **Web app URL** that appears

## Step 6: Test the Deployment

**Test the URL in your browser:**
```
https://script.google.com/macros/s/YOUR_NEW_SCRIPT_ID/exec
```

You should see: `{"ok":true,"message":"Crucible intake endpoint is alive."}`

## Step 7: Update Flutter App

**Update the URL in `lib/main.dart`:**

```dart
final String scriptUrl = 'YOUR_NEW_SCRIPT_URL_HERE';
```

## Step 8: Verify Everything Works

1. **Test the script URL** in a browser
2. **Make some changes** in edit mode in your Flutter app
3. **Click "Submit"** in the unsubmitted advancement dialog
4. **Check your Google Sheets** for new rows

## Troubleshooting

### Common Issues:

1. **"Page Not Found" Error**
   - Ensure the script is deployed as a web app
   - Check that "Who has access" is set to "Anyone"

2. **"401 Unauthorized" Error**
   - Make sure "Execute as" is set to your email
   - Re-authorize the script if needed

3. **CORS Errors**
   - Ensure the script is deployed with "Anyone" access
   - Check that the URL is correct

4. **No Data in Sheets**
   - Verify sheet names match exactly: "Affinity Changes", "Skill Changes", "Essence Changes"
   - Ensure script and spreadsheet are in the same Google account

### Testing Commands:

**Test with curl:**
```bash
curl -X POST "YOUR_SCRIPT_URL" \
  -H "Content-Type: application/json" \
  -d '{"idToken":"test","affinityChanges":[],"skillChanges":[],"essenceChanges":[]}'
```

**Expected response:**
```json
{"ok":true,"email":"test@example.com","counts":{"affinityChanges":0,"skillChanges":0,"essenceChanges":0}}
```

## Security Notes

- The script accepts requests from anyone (as configured)
- Firebase authentication validates the user identity
- Only authenticated users can submit data
- Data is stored in your Google Sheets

## Support

If you continue to have issues:
1. Check the Google Apps Script logs (Executions tab)
2. Verify all configuration steps above
3. Test the script URL directly in a browser
4. Ensure Firebase API key is correct

