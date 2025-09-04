# Discord Event Sync Fixes

## Issues Fixed

### 1. Sync Issue: Creating New Events Every Time
**Problem**: The sync function was creating a new Discord event every time it ran, even when events already existed.

**Root Cause**: The function was checking for existing Discord events but then always proceeding to create new ones instead of properly handling the flow. Additionally, Discord API calls were failing intermittently due to rate limiting and network issues, causing the function to think events didn't exist when they actually did.

**Solution**: 
- Restructured the logic to check for existing Discord events first
- If a Discord event exists and is up to date, skip it
- If a Discord event exists but data has changed, update it
- If a Discord event doesn't exist, create a new one
- Added proper `continue` statements to prevent duplicate processing
- **Added retry logic with exponential backoff** for Discord API calls
- **Added timeout handling** (10 seconds) for API requests
- **Added error-specific handling** - only clear Discord event ID on 404 errors, skip on other errors
- **Added rate limiting protection** with delays between event processing
- **Added detailed logging** to track what's happening during sync

### 2. Timezone Issue: Wrong Timezone in Discord Events
**Problem**: Discord events were showing incorrect times due to improper timezone handling.

**Root Cause**: The function was using a hardcoded timezone (`America/New_York`) instead of location-specific timezones.

**Solution**:
- Added timezone detection from location data
- Each location can now have a `timezone` field
- The sync function looks up the location's timezone and uses it for date parsing
- Improved timezone handling with proper moment-timezone usage
- Added fallback to `America/New_York` if no timezone is set

## How the Fixed Sync Works

### 1. Event Processing Flow
```
For each event:
1. Extract event data (name, description, dates, location)
2. Get location timezone from Firestore
3. Parse dates with proper timezone handling
4. Check if Discord event ID exists
   - If exists: Verify it still exists in Discord (with retry logic)
     - If exists and up to date: Skip
     - If exists but changed: Update (with retry logic)
     - If 404 error: Clear ID and create new
     - If other error: Skip to avoid duplicates
   - If no ID: Create new Discord event (with retry logic)
5. Update Firestore with Discord event ID
6. Add delay between events to avoid rate limiting
```

### 2. Timezone Handling
```
1. Look up location in Firestore
2. Get location's timezone field
3. Parse event dates as local time in that timezone
4. Convert to ISO string for Discord API
5. Discord displays times in the correct timezone
```

## New Functions Added

### 1. `setLocationTimezone`
**Purpose**: Set timezone for a specific location
**Endpoint**: `https://us-central1-crucible-helper.cloudfunctions.net/setLocationTimezone`
**Method**: POST
**Body**: 
```json
{
  "locationName": "Location Name",
  "timezone": "America/New_York"
}
```

### 2. `getLocationsWithTimezone`
**Purpose**: Get all locations with their timezone status
**Endpoint**: `https://us-central1-crucible-helper.cloudfunctions.net/getLocationsWithTimezone`
**Method**: POST
**Body**: `{}`
**Response**:
```json
{
  "ok": true,
  "locations": [
    {
      "id": "location-id",
      "name": "Location Name",
      "address": "123 Main St",
      "timezone": "America/New_York",
      "hasTimezone": true,
      "timezoneUpdatedAt": "2024-01-01T00:00:00Z"
    }
  ],
  "summary": {
    "total": 5,
    "withTimezone": 3,
    "withoutTimezone": 2
  }
}
```

## Migration Steps

### Step 1: Set Timezones for Locations
You can set timezones for your locations using the new function:

```bash
# Using curl (replace with your Firebase ID token)
curl -X POST \
  https://us-central1-crucible-helper.cloudfunctions.net/setLocationTimezone \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "locationName": "Your Location Name",
    "timezone": "America/New_York"
  }'
```

### Step 2: Check Timezone Status
Check which locations need timezones:

```bash
curl -X POST \
  https://us-central1-crucible-helper.cloudfunctions.net/getLocationsWithTimezone \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Step 3: Sync Events to Discord
Once timezones are set, sync events to Discord:

1. Go to the Events page in your Flutter app
2. Click "Sync to Discord" button (super admin only)
3. The function will now:
   - Use correct timezones for each location
   - Update existing Discord events instead of creating duplicates
   - Show detailed results of the sync process

## Supported Timezones

Common timezones you can use:
- `America/New_York` - Eastern Time
- `America/Chicago` - Central Time
- `America/Denver` - Mountain Time
- `America/Los_Angeles` - Pacific Time
- `America/Phoenix` - Mountain Time (no DST)
- `America/Anchorage` - Alaska Time
- `Pacific/Honolulu` - Hawaii Time
- `Europe/London` - GMT/BST
- `Europe/Paris` - Central European Time

## Testing the Fixes

### 1. Test Sync Behavior
1. Create an event in your app
2. Sync to Discord (should create new Discord event)
3. Sync again (should skip or update if changed)
4. Modify the event in your app
5. Sync again (should update existing Discord event)

### 2. Test Timezone Handling
1. Set timezone for a location
2. Create an event at that location
3. Sync to Discord
4. Check Discord event times match your local timezone

### 3. Test Error Recovery
1. Delete a Discord event manually
2. Sync from your app
3. Should recreate the Discord event automatically

## Troubleshooting

### Events Still Creating Duplicates
- Check that events have `discordEventId` field in Firestore
- Verify Discord events still exist in Discord
- Check function logs for errors
- **New**: Check for Discord API rate limiting or network errors in logs
- **New**: Look for retry attempts in the logs to identify intermittent failures

### Discord API Errors
- **Rate Limiting**: The function now includes delays and retry logic
- **Network Timeouts**: Added 10-second timeout for API calls
- **404 Errors**: Only these will trigger recreation of Discord events
- **Other Errors**: Will skip the event to avoid duplicates

### Wrong Times in Discord
- Verify location has correct timezone set
- Check that timezone is a valid IANA timezone identifier
- Ensure event dates are in the future

### Permission Errors
- Ensure you're logged in as a super admin
- Check that your Firebase ID token is valid
- Verify Discord bot has proper permissions

## Recent Improvements (Latest Update)

### Robust Discord API Handling
- **Retry Logic**: Up to 3 retries with exponential backoff for all Discord API calls
- **Timeout Protection**: 10-second timeout for all API requests
- **Error-Specific Handling**: 
  - 404 errors: Clear Discord event ID and recreate
  - Other errors: Skip event to avoid duplicates
- **Rate Limiting Protection**: 500ms delay between processing events
- **Detailed Logging**: Comprehensive logs showing what's happening during sync

### Better Data Comparison
- **Normalized Comparison**: Handles null/undefined values properly
- **Detailed Change Logging**: Shows exactly what changed when updating events
- **Progress Tracking**: Shows which event is being processed (e.g., "Processing event 2/5")

## Future Enhancements

- **Selective Sync**: Choose specific events to sync
- **Real-time Updates**: Sync automatically when events change
- **Delete Sync**: Remove Discord events when Firestore events are deleted
- **Batch Processing**: Handle large numbers of events more efficiently
- **Webhook Integration**: Real-time sync on event changes
