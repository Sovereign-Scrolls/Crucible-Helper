# Firebase Functions Test Guide

## Testing Firebase Functions Manually

### 1. Test checkPlayerRegistration Function

```bash
curl -X POST https://us-central1-crucible-helper.cloudfunctions.net/checkPlayerRegistration \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -d '{
    "eventId": "EVENT_ID",
    "playerUid": "PLAYER_UID",
    "qrData": {
      "game": "Crucible",
      "playerUid": "PLAYER_UID",
      "playerName": "Test Player"
    }
  }'
```

### 2. Test checkInPlayer Function

```bash
curl -X POST https://us-central1-crucible-helper.cloudfunctions.net/checkInPlayer \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -d '{
    "eventId": "EVENT_ID",
    "playerUid": "PLAYER_UID",
    "qrData": {
      "game": "Crucible",
      "playerUid": "PLAYER_UID",
      "playerName": "Test Player"
    }
  }'
```

## Getting ID Token

1. Open the app in browser
2. Open Developer Tools → Console
3. Run this JavaScript:
```javascript
firebase.auth().currentUser.getIdToken().then(token => {
  console.log('ID Token:', token);
});
```

## Expected Responses

### checkPlayerRegistration Response
```json
{
  "ok": true,
  "isRegistered": true,
  "isCheckedIn": false,
  "playerName": "Player Name"
}
```

### checkInPlayer Response
```json
{
  "ok": true,
  "message": "Player checked in successfully",
  "checkIn": {
    "playerUid": "PLAYER_UID",
    "checkedInAt": "timestamp",
    "checkedInBy": "ADMIN_UID"
  },
  "sheetsData": {
    "attendingAs": "Attendee Type",
    "buildAdjustment": 0,
    "apAdjustment": 0,
    "characterNumber": "123"
  }
}
```

## Common Error Responses

### 401 Unauthorized
```json
{
  "ok": false,
  "error": "Missing authorization header"
}
```

### 403 Forbidden
```json
{
  "ok": false,
  "error": "User must be super admin"
}
```

### 404 Not Found
```json
{
  "ok": false,
  "error": "Event not found"
}
```

### 409 Conflict
```json
{
  "ok": false,
  "error": "Player is already checked in for this event"
}
```

## Testing Steps

1. **Get a valid ID token** from the app
2. **Replace EVENT_ID** with an actual event ID from your database
3. **Replace PLAYER_UID** with an actual player UID
4. **Test checkPlayerRegistration** first
5. **Test checkInPlayer** if registration check passes
6. **Check Firestore** to verify data was written
7. **Check Google Sheets** to verify data was written there too

## Debugging Tips

- Use `curl -v` for verbose output
- Check Firebase Functions logs in Firebase Console
- Verify CORS is properly configured
- Ensure service account has proper permissions
- Check if Google Sheets API is working
