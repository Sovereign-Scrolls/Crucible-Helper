# Testing Timezone Functionality

## Overview

This guide helps you test that the timezone fixes are working correctly for Discord event syncing.

## Pre-Testing Checklist

- [ ] Firebase Functions deployed successfully
- [ ] Flutter app updated with timezone support
- [ ] Migration script ready (if needed)

## Test Steps

### 1. Test Location Creation with Timezone

1. **Open the Flutter app**
2. **Go to Events page**
3. **Click "Edit Locations"**
4. **Click "+" to create a new location**
5. **Fill in the form**:
   - Name: "Test Location - Pacific"
   - Address: "123 Main St, Los Angeles, CA"
   - Timezone: Select "America Los Angeles"
6. **Click "Create Location"**
7. **Verify**: Location appears in list with timezone shown

### 2. Test Location Editing with Timezone

1. **In the locations list, click edit on any location**
2. **Change the timezone** to a different one
3. **Save the changes**
4. **Verify**: Timezone is updated in the list

### 3. Test Discord Sync with Different Timezones

1. **Create a test event**:
   - Start Date: Tomorrow
   - End Date: Tomorrow
   - Location: Select a location with a specific timezone
   - Type: Any event type

2. **Click "Sync to Discord"**
3. **Check Discord**:
   - Event should appear with correct local time
   - Time should match the location's timezone

### 4. Test Multiple Timezones

1. **Create locations in different timezones**:
   - "East Coast Event" - America/New_York
   - "West Coast Event" - America/Los_Angeles
   - "Mountain Event" - America/Denver

2. **Create events for each location**
3. **Sync all to Discord**
4. **Verify**: Each event shows correct time for its timezone

## Expected Results

### Before Fix (What was wrong):
- All Discord events showed same time (hardcoded to Eastern Time)
- Events in different timezones appeared at wrong times
- No timezone information in location management

### After Fix (What should work):
- Discord events show correct local time for each location
- Location creation/editing includes timezone selection
- Timezone information visible in location list
- Events sync with location-specific timezones

## Troubleshooting

### Issue: Discord events still show wrong times
**Solution**: 
1. Check that location has correct timezone set
2. Re-sync events after updating timezone
3. Verify Firebase Functions are deployed

### Issue: Timezone dropdown not showing
**Solution**:
1. Make sure Flutter app is updated
2. Hot reload the app
3. Check for any console errors

### Issue: Migration needed for existing locations
**Solution**:
1. Run the migration script: `node migrate_timezones.js`
2. Or manually edit locations through the app
3. Verify timezone field is added to all locations

## Verification Commands

### Check Firebase Functions Logs
```bash
firebase functions:log --only syncEventsToDiscord
```

### Test Timezone Detection
```javascript
// In Firebase Functions console
const { detectTimezoneFromAddress } = require('./migrate_timezones.js');

console.log(detectTimezoneFromAddress('123 Main St, Los Angeles, CA'));
// Should output: America/Los_Angeles
```

### Check Location Data
```javascript
// In Firebase Console > Firestore
// Navigate to locations collection
// Verify each location has timezone field
```

## Success Criteria

- [ ] New locations can be created with timezone selection
- [ ] Existing locations can be edited to change timezone
- [ ] Discord events sync with correct times for each timezone
- [ ] Location list shows timezone information
- [ ] No errors in Firebase Functions logs
- [ ] Events in different timezones appear at correct times in Discord

## Next Steps

After successful testing:

1. **Run migration script** for existing locations (if needed)
2. **Update existing locations** with correct timezones
3. **Re-sync existing Discord events** to fix their times
4. **Monitor Discord events** to ensure they continue working correctly

## Support

If testing reveals issues:

1. Check Firebase Functions logs for errors
2. Verify timezone values in Firestore
3. Test with a single location first
4. Contact support with specific error messages and test results

