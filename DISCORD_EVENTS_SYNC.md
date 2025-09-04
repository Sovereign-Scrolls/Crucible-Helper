# Discord Events Sync Feature

## Overview

The Discord Events Sync feature allows super admins to automatically sync events from the Flutter app to Discord as scheduled events. This replaces the previous Google Apps Script approach with a direct Firebase Function integration.

## How It Works

1. **Trigger**: Super admin clicks "Sync to Discord" button in the AppBar of the events page
2. **Authentication**: System verifies user is a super admin
3. **Event Processing**: 
   - Fetches all events from Firestore
   - Skips events already synced to Discord
   - Validates event data (dates, times, location)
   - Uses registration details if available, otherwise uses basic event data
4. **Discord API Integration**: Creates Discord scheduled events for each valid event
5. **Status Tracking**: Updates Firestore with Discord event IDs and sync status
6. **Results Display**: Shows detailed results to the admin

## Firebase Function

### `syncEventsToDiscord`

**Endpoint**: `https://us-central1-crucible-helper.cloudfunctions.net/syncEventsToDiscord`

**Method**: POST

**Authentication**: Requires Firebase ID token and super admin privileges

**Request Body**: Empty object `{}`

**Response**:
```json
{
  "ok": true,
  "message": "Events sync completed",
  "results": [
    {
      "eventId": "event123",
      "eventName": "Summer Event 2024",
      "status": "success",
      "message": "Discord event created: Summer Event 2024",
      "discordEventId": "discord_event_456"
    },
    {
      "eventId": "event456",
      "eventName": "Updated Event 2024",
      "status": "updated",
      "message": "Discord event updated: Updated Event 2024",
      "discordEventId": "discord_event_789"
    }
  ],
  "summary": {
    "total": 5,
    "successful": 2,
    "updated": 1,
    "errors": 1,
    "skipped": 1
  }
}
```

## Event Validation

The function validates each event before creating Discord events:

- **Registration Status**: Events can be synced with or without activated registration
- **Required Fields**: startDate, endDate, locationName
- **Date Validation**: Start time must be in the future
- **Time Validation**: End time must be after start time
- **Discord Event Verification**: Checks if existing Discord events still exist
- **Data Comparison**: Compares event data to detect changes

## Discord Event Structure

Each Discord event is created with:

- **Name**: Event name from registration details (if available) or event type name
- **Description**: Location information (name and address if available)
- **Start Time**: Event start date/time (with proper timezone handling)
- **End Time**: Event end date/time (with proper timezone handling)
- **Type**: External event (entity_type: 3)
- **Privacy**: Guild only (privacy_level: 2)
- **Location**: Event location name

### Data Source Priority

1. **With Registration**: Uses `registrationDetails.eventName` and enhanced description
2. **Without Registration**: Uses `typeName` and basic location description

### Sync Behavior

The function implements intelligent sync behavior:
- **Discord Event Verification**: Checks if existing Discord events still exist
- **Data Comparison**: Compares event data to detect changes
- **Smart Updates**: Updates Discord events when data has changed
- **Auto-Recovery**: Recreates Discord events if they were deleted
- **Discord ID Tracking**: Stores Discord event IDs in Firestore for future reference
- **Re-run Safe**: Can be run multiple times with intelligent handling
- **Detailed Logging**: Comprehensive logging for debugging sync issues

### Timezone Handling

The function uses `moment-timezone` to properly handle timezone conversion:
- **Default Timezone**: America/New_York (configurable)
- **Date Parsing**: Treats input dates as local time in the specified timezone
- **Discord Format**: Converts to ISO string with proper timezone offset
- **Start Time**: Set to 00:00:00 of the start date
- **End Time**: Set to 23:59:59 of the end date

## Firestore Updates

When a Discord event is successfully created or updated, the Firestore event document is updated with:

- `discordEventId`: The Discord event ID
- `discordEventCreated`: Boolean flag (true)
- `discordEventCreatedAt`: Timestamp of creation/update

### Status Types

The sync process can result in different status types:

- **success**: New Discord event created
- **updated**: Existing Discord event updated with new data
- **skipped**: Discord event exists and is up to date
- **error**: Failed to process event (validation or API error)

## UI Integration

### Button Location
The "Sync to Discord" button appears in the AppBar actions for super admins only, alongside other admin functions like "Add Event", "Edit Event Type", and "Edit Locations".

### User Experience
1. **Loading State**: Shows progress dialog during sync
2. **Results Dialog**: Displays detailed results after completion
3. **Error Handling**: Shows error messages for failed operations
4. **Auto-refresh**: Events list refreshes to show sync status

## Error Handling

The function handles various error scenarios:

- **Authentication Errors**: Invalid or missing tokens
- **Permission Errors**: Non-admin users
- **Validation Errors**: Missing or invalid event data
- **Discord API Errors**: Network issues or API limitations
- **Database Errors**: Firestore connection issues

## Configuration

The function uses the Discord bot token stored as a Firebase secret:

- **Secret Name**: `DISCORD_TOKEN`
- **Guild ID**: `1102958641503547394` (hardcoded in function)

## Comparison with Google Apps Script

| Feature | Google Apps Script | Firebase Function |
|---------|-------------------|-------------------|
| **Trigger** | Manual execution | UI button click |
| **Data Source** | Google Sheets | Firestore |
| **Authentication** | Service account | Firebase Auth |
| **Error Handling** | Basic logging | Detailed results |
| **Status Tracking** | Sheet updates | Firestore updates |
| **Real-time** | No | Yes |
| **Integration** | External | Native |

## Future Enhancements

- **Selective Sync**: Choose specific events to sync
- **Update Existing**: Update Discord events when Firestore events change
- **Delete Sync**: Remove Discord events when Firestore events are deleted
- **Batch Processing**: Handle large numbers of events more efficiently
- **Webhook Integration**: Real-time sync on event changes
