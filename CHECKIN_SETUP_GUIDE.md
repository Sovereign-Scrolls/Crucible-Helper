# Event Check-In Setup Guide

This guide explains how to set up the event check-in system that writes directly to Google Sheets when players are checked in at events.

## Overview

The check-in system uses:
- **Event QR Scanner** → **Firebase Function** → **Google Sheets API** → **Google Sheet**

When a super admin scans a player's QR code at an event, the system automatically writes the check-in data to your Google Sheet with the correct information from their event registration.

## Prerequisites

1. **Google Cloud Project** with Google Sheets API enabled
2. **Service Account** with Google Sheets permissions
3. **Firebase Project** with Functions deployed

## Step 1: Enable Google Sheets API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Go to "APIs & Services" → "Library"
4. Search for "Google Sheets API"
5. Click "Enable"

## Step 2: Create Service Account

1. Go to "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "Service Account"
3. Fill in the details:
   - **Name**: `crucible-checkin-service`
   - **Description**: `Service account for Crucible check-in system`
4. Click "Create and Continue"
5. Skip role assignment (we'll handle permissions manually)
6. Click "Done"

## Step 3: Generate Service Account Key

1. Click on the service account you just created
2. Go to "Keys" tab
3. Click "Add Key" → "Create New Key"
4. Choose "JSON" format
5. Download the key file
6. **Rename it to** `service-account-key.json`
7. **Place it in** the `functions/` directory of your project

## Step 4: Share Google Sheet with Service Account

1. Open your Google Sheet: `https://docs.google.com/spreadsheets/d/1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4/edit`
2. Click "Share" button
3. Add the service account email (found in the JSON key file under `client_email`)
4. Give it "Editor" permissions
5. Click "Send"

## Step 5: Update Configuration

The configuration is already set up in `functions/config.json`:

```json
{
  "google_sheets": {
    "checkin_spreadsheet_id": "1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4",
    "checkin_sheet_name": "Event Attending"
  }
}
```

## Step 6: Deploy Firebase Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

## Step 7: Test the Check-In System

1. **Run the Flutter app**:
   ```bash
   flutter run -d chrome --web-port=8080
   ```

2. **Navigate to Events page** and test the check-in process:
   - Create an event with registration activated
   - Register a player for the event with an attendee type
   - Use the QR scanner in the event details to scan a player's QR code
   - The system will automatically write to Google Sheets

3. **Check the Google Sheet** to verify the data was written

## Data Format

The check-in data is automatically written to the "Event Attending" sheet when a player is checked in at an event. The data comes from their event registration:

| Column | Description | Source |
|--------|-------------|---------|
| A | checkInUserEmail | Player's email from Firebase Auth |
| B | Timestamp | Current timestamp when checked in |
| C | characterNumber | Player's character number (if available) |
| D | attendingAs | Attendee type name from event registration |
| E | Build Adj | Build points from attendee type definition |
| F | AP Adj | Affinity points from attendee type definition |

## Troubleshooting

### Common Issues

1. **"Service account key not found"**
   - Ensure `service-account-key.json` is in the `functions/` directory
   - Check that the file name matches exactly

2. **"Permission denied"**
   - Verify the service account email has "Editor" access to the Google Sheet
   - Check that the Google Sheets API is enabled

3. **"Spreadsheet not found"**
   - Verify the spreadsheet ID in `functions/config.json`
   - Ensure the service account has access to the spreadsheet

4. **"Sheet not found"**
   - Verify the sheet name "Event Attending" exists in the spreadsheet
   - Check for typos in the sheet name

### Debug Logs

Check Firebase Function logs:
```bash
firebase functions:log --only checkIn
```

### Testing the Function Directly

You can test the Firebase Function directly:

```bash
curl -X POST "https://us-central1-crucible-helper.cloudfunctions.net/checkInPlayer" \
  -H "Authorization: Bearer YOUR_FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "YOUR_EVENT_ID",
    "playerUid": "PLAYER_UID"
  }'
```

## Security Considerations

1. **Service Account Key**: Keep the `service-account-key.json` file secure and never commit it to version control
2. **Sheet Permissions**: Only give the service account the minimum required permissions
3. **Firebase Security Rules**: Ensure your Firebase Functions are properly secured

## Next Steps

Once the check-in system is working, you can:

1. **Add character progression logic** to process the check-in data
2. **Create reports** based on attendance data
3. **Integrate with other systems** that need attendance information

## Support

If you encounter issues:

1. Check the Firebase Function logs
2. Verify all configuration steps were completed
3. Test with the curl command above
4. Ensure the Google Sheet is accessible and has the correct format
