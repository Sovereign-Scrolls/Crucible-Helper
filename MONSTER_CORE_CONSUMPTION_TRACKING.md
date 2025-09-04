# Monster Core Consumption and Slotting Tracking

## Overview

When a character consumes a monster core for build purposes or slots a core for affinity points, the system now automatically records this information in Google Sheets for tracking and analysis.

## Google Sheet Configuration

The system writes to two different tabs in the configured Google Sheet:

### Build Consumption Tracking
- **Spreadsheet ID**: `1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4`
- **Sheet Name**: `Consume Cores (Build)`

### Affinity Slotting Tracking
- **Spreadsheet ID**: `1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4`
- **Sheet Name**: `Sloting Cores (Affinty Points)`

## Data Structure

### Build Consumption Sheet ("Consume Cores (Build)")

| Column | Description | Data Type |
|--------|-------------|-----------|
| A | Email | User's email address |
| B | Timestamp | ISO timestamp of consumption |
| C | Core Tier | Tier of the consumed core (Iron, Silver, Gold, etc.) |
| D | Event | Event name (currently set to "TBD") |

### Affinity Slotting Sheet ("Sloting Cores (Affinty Points)")

| Column | Description | Data Type |
|--------|-------------|-----------|
| A | Email | User's email address |
| B | Timestamp | ISO timestamp of slotting |
| C | Core Tier | Tier of the slotted core (Iron, Silver, Gold, etc.) |
| D | Perfect Cultivation | Perfect cultivation points (0 if no perfect cultivation) |
| E | Event | Event name (currently set to "TBD") |

## How It Works

### Build Consumption
1. **Trigger**: When a user consumes a monster core for build purposes in the Flutter app
2. **Authentication**: The system verifies the user's identity using Firebase Auth
3. **Data Collection**: 
   - User email (from Firebase Auth or Firestore fallback)
   - Current timestamp
   - Core tier (from the consumed monster core)
   - Event (placeholder for future implementation)
4. **Google Sheets Write**: Data is appended to the "Consume Cores (Build)" sheet
5. **Error Handling**: If Google Sheets write fails, the core consumption still succeeds (non-blocking)

### Affinity Slotting
1. **Trigger**: When a user slots a monster core for affinity points in the Flutter app
2. **Authentication**: The system verifies the user's identity using Firebase Auth
3. **Data Collection**: 
   - User email (from Firebase Auth or Firestore fallback)
   - Current timestamp
   - Core tier (from the slotted monster core)
   - Perfect cultivation points (calculated based on tier difference)
   - Event (placeholder for future implementation)
4. **Perfect Cultivation Calculation**: 
   - Compares character tier vs core tier
   - If core tier is higher than character tier, calculates the difference
   - Tier order: Iron < Silver < Gold < Jade < Saint < Sovereign
5. **Google Sheets Write**: Data is appended to the "Sloting Cores (Affinty Points)" sheet
6. **Error Handling**: If Google Sheets write fails, the core slotting still succeeds (non-blocking)

## Configuration

The feature is configured in `functions/config.json`:

```json
{
  "google_sheets": {
    "consume_cores_spreadsheet_id": "1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4",
    "consume_cores_sheet_name": "Consume Cores (Build)",
    "slot_cores_spreadsheet_id": "1UjoGAQAfUb3KO4OuNgiLclM5SGVAFrFRGyjRFQECIV4",
    "slot_cores_sheet_name": "Sloting Cores (Affinty Points)"
  }
}
```

## Firebase Function

The `consumeMonsterCore` Firebase function has been enhanced to:

1. Process the core consumption as before
2. Check if the consumption type is 'build'
   - If so, write the consumption data to "Consume Cores (Build)" Google Sheet
3. Check if the consumption type is 'affinity'
   - If so, calculate perfect cultivation points and write to "Sloting Cores (Affinty Points)" Google Sheet
4. Continue with the normal response regardless of Google Sheets success/failure

## Future Enhancements

- **Event Integration**: The Event column is currently set to "TBD". Future versions may integrate with event registration to automatically populate this field.
- **Additional Data**: Could include character information, location data, or other relevant details.
- **Analytics**: The Google Sheet data can be used for analytics, reporting, and character progression tracking.

## Testing

### Testing Build Consumption:
1. Scan a monster core QR code in the Flutter app
2. Choose "Consume for Build" option
3. Complete the consumption process
4. Check the "Consume Cores (Build)" tab in the Google Sheet for the new entry

### Testing Affinity Slotting:
1. Scan a monster core QR code in the Flutter app
2. Choose "Slot for Affinity Points" option
3. Complete the slotting process
4. Check the "Sloting Cores (Affinty Points)" tab in the Google Sheet for the new entry
5. Verify that perfect cultivation points are calculated correctly based on tier differences

## Error Handling

- If Google Sheets is unavailable, the core consumption still succeeds
- Errors are logged to Firebase Functions console
- User experience is not impacted by Google Sheets failures
