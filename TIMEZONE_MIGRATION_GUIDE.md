# Timezone Migration Guide

## Overview

This guide helps you migrate existing locations in your Firestore database to include timezone information, which will fix the Discord event sync timezone issues.

## What Changed

1. **Location Model**: Added `timezone` field to store timezone information
2. **Discord Sync**: Now uses location-specific timezones instead of hardcoded `America/New_York`
3. **UI Updates**: Added timezone selection in location creation/editing forms
4. **Migration Script**: Automated script to add timezones to existing locations

## Migration Steps

### Option 1: Automated Migration (Recommended)

1. **Deploy the updated Firebase Functions**:
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

2. **Run the migration script**:
   ```bash
   cd functions
   node migrate_timezones.js
   ```

   The script will:
   - Detect timezones from location addresses
   - Add timezone information to existing locations
   - Skip locations that already have timezones
   - Provide detailed logging of the migration process

### Option 2: Manual Migration

1. **Update existing locations manually** through the Flutter app:
   - Go to Events page
   - Click "Edit Locations" 
   - Edit each location and set the appropriate timezone
   - Save changes

2. **Or update directly in Firestore**:
   - Open Firebase Console
   - Go to Firestore Database
   - Navigate to `locations` collection
   - Add `timezone` field to each location document

## Timezone Detection Logic

The migration script automatically detects timezones based on:

### US States/Regions:
- **Eastern Time**: NY, FL, GA, NC, SC, VA, MD, DE, PA, NJ, CT, RI, MA, VT, NH, ME, OH, IN, KY, TN, MI
- **Central Time**: IL, WI, MN, IA, MO, AR, LA, MS, AL, OK, KS, NE, ND, SD
- **Mountain Time**: CO, WY, MT, ID, UT, NM, AZ
- **Pacific Time**: CA, OR, WA, NV
- **Alaska**: AK
- **Hawaii**: HI

### Major Cities:
- NYC, New York City → America/New_York
- LA, Los Angeles → America/Los_Angeles
- Chicago → America/Chicago
- Denver → America/Denver
- Phoenix → America/Phoenix
- Anchorage → America/Anchorage
- Honolulu → Pacific/Honolulu

### Default Fallback:
- If no match is found → America/New_York

## Testing the Migration

1. **Check existing locations**:
   - Verify timezone field is added to all locations
   - Confirm timezone values are correct for your locations

2. **Test Discord sync**:
   - Create or edit an event
   - Click "Sync to Discord"
   - Verify the event appears in Discord with correct times

3. **Verify timezone handling**:
   - Check Discord event times match your local timezone
   - Test with locations in different timezones

## Common Issues

### Migration Script Fails
- **Error**: "Firebase not initialized"
  - **Solution**: Uncomment and configure Firebase initialization in `migrate_timezones.js`
  - **Solution**: Or run migration through Firebase Functions

### Wrong Timezone Detected
- **Issue**: Script detects wrong timezone from address
  - **Solution**: Manually edit the location through the Flutter app
  - **Solution**: Or update directly in Firestore

### Discord Events Still Wrong
- **Issue**: Events still show wrong times in Discord
  - **Solution**: Re-sync events after migration
  - **Solution**: Check that location timezone is correctly set

## Manual Timezone Updates

To manually set a timezone for a specific location:

```javascript
// In Firebase Functions console or script
const { setLocationTimezone } = require('./migrate_timezones.js');

await setLocationTimezone('location-id', 'America/Los_Angeles');
```

## Supported Timezones

The app supports all IANA timezone identifiers. Common ones include:

- `America/New_York` - Eastern Time
- `America/Chicago` - Central Time  
- `America/Denver` - Mountain Time
- `America/Los_Angeles` - Pacific Time
- `America/Phoenix` - Mountain Time (no DST)
- `America/Anchorage` - Alaska Time
- `Pacific/Honolulu` - Hawaii Time
- `Europe/London` - GMT/BST
- `Europe/Paris` - Central European Time
- `Asia/Tokyo` - Japan Standard Time
- `Australia/Sydney` - Australian Eastern Time

## Verification Checklist

- [ ] Migration script completed successfully
- [ ] All locations have timezone field
- [ ] Timezone values are correct for your locations
- [ ] Discord sync works with correct times
- [ ] New locations can be created with timezone selection
- [ ] Existing locations can be edited to change timezone

## Rollback Plan

If issues occur, you can:

1. **Revert Firebase Functions**:
   ```bash
   firebase deploy --only functions --project your-project-id
   ```

2. **Remove timezone fields** (if needed):
   ```javascript
   // Script to remove timezone fields
   const locationsSnapshot = await db.collection('locations').get();
   for (const doc of locationsSnapshot.docs) {
     await doc.ref.update({
       timezone: admin.firestore.FieldValue.delete()
     });
   }
   ```

## Support

If you encounter issues during migration:

1. Check the migration script logs for errors
2. Verify Firebase project configuration
3. Test with a single location first
4. Contact support with specific error messages
