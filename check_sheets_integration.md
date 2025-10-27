# Google Sheets Integration Verification

## Steps to Test Character Creation and Google Sheets Integration

### 1. Test Character Creation
1. Open the Flutter app in browser (http://localhost:8080)
2. Log in with a test user account
3. Create a new character using the form
4. Verify the character is created successfully

### 2. Check Firebase Functions Logs
1. Go to Firebase Console → Functions → Logs
2. Look for the `createCharacter` function logs
3. Check for these log messages:
   - `✅ Character data written to Google Sheets Form Responses:`
   - `❌ Error writing to Google Sheets Form Responses:` (if there's an error)

### 3. Verify Google Sheets Data
1. Open the PC DB Google Sheet
2. Navigate to the "Form Responses" tab
3. Check if a new row was added with:
   - Timestamp
   - Email Address
   - Character Name
   - Player Name
   - Race
   - Pick an Affinity to start with

### 4. Expected Data Format
The row should contain:
- **Column A**: ISO timestamp (e.g., "2024-01-15T10:30:00.000Z")
- **Column B**: User's email address
- **Column C**: Character name
- **Column D**: Player name
- **Column E**: Selected race
- **Column F**: Selected free affinity (or "N/A")

### 5. Troubleshooting
If data is not appearing in Google Sheets:
1. Check Firebase Functions logs for errors
2. Verify the service account has access to the spreadsheet
3. Check if the "Form Responses" sheet exists
4. Verify the spreadsheet ID is correct

### 6. Test Different Scenarios
- Create character with single affinity option (should auto-select)
- Create character with multiple affinity options (should require selection)
- Test with different races
- Test error handling (network issues, invalid data)
