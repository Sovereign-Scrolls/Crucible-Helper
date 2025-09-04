# QR Scanner Debugging Guide

## Issue Description
QR scanner is returning empty data, causing JSON parsing errors.

## Current Error
```
🔍 QR data: 
❌ Error processing QR code: FormatException: SyntaxError: Unexpected end of JSON input
```

## Enhanced Debugging Added

The following logging has been added to track the QR scanning process:

### 1. QR Scanner Initialization
- `📱 Opening camera scanner for event: [eventId]`

### 2. QR Scanner Data Reception
- `📱 QR Scanner: Received scan data`
- `📱 QR Scanner: scanData.code = "[qrCode]"` or `null`
- `📱 QR Scanner: scanData.code is null = [true/false]`

### 3. QR Scanner Processing
- `📱 QR Scanner: Calling _handleQRCodeScan with: "[qrCode]"`
- `📱 QR Scanner: _handleQRCodeScan called with: "[qrCode]"`
- `📱 QR Scanner: qrCode length: [length]`
- `📱 QR Scanner: Debouncing duplicate scan` (if duplicate)
- `📱 QR Scanner: Calling widget.onQRCodeScanned with: "[qrCode]"`

### 4. Callback Processing
- `📱 Camera scanner callback received: "[qrCode]"`
- `📱 Camera scanner callback length: [length]`

### 5. QR Data Processing
- `🔍 Processing check-in QR code for event: [eventId]`
- `🔍 QR data length: [length]`
- `🔍 QR data: "[qrData]"`
- `❌ QR data is empty or contains only whitespace` (if empty)
- `❌ JSON parsing error: [error]` (if JSON fails)
- `❌ Raw QR data that failed to parse: "[qrData]"`

## Possible Causes

### 1. QR Code Issues
- **Empty QR Code**: The QR code itself might be empty or corrupted
- **Wrong QR Code**: Scanning a non-Crucible QR code
- **QR Code Format**: QR code might not be in the expected JSON format

### 2. Scanner Issues
- **Camera Problems**: Camera not focusing properly
- **Scanner Library**: Issues with qr_code_scanner_plus library
- **Web Platform**: Web-specific scanner limitations

### 3. Data Transmission Issues
- **Callback Problems**: Data not being passed correctly through callbacks
- **Navigation Issues**: Data lost during navigation
- **Memory Issues**: Data being cleared unexpectedly

## Testing Steps

### 1. Test QR Code Generation
1. Generate a new QR code for a player
2. Verify the QR code contains valid JSON data
3. Test the QR code with a different QR scanner app

### 2. Test Scanner in Different Environment
1. Test the scanner in development environment
2. Test the scanner in production environment
3. Compare the behavior between environments

### 3. Test with Different QR Codes
1. Try scanning a known good QR code
2. Try scanning a different player's QR code
3. Try scanning a test QR code

### 4. Check Browser Console
1. Open browser console during scanning
2. Look for all the debug messages
3. Check for any JavaScript errors
4. Verify the data flow through each step

## Expected Flow

1. **Scanner Opens** → `📱 Opening camera scanner for event: [eventId]`
2. **QR Code Scanned** → `📱 QR Scanner: Received scan data`
3. **Data Received** → `📱 QR Scanner: scanData.code = "[qrCode]"`
4. **Processing Started** → `📱 QR Scanner: Calling _handleQRCodeScan`
5. **Callback Triggered** → `📱 Camera scanner callback received: "[qrCode]"`
6. **Data Processing** → `🔍 Processing check-in QR code`
7. **JSON Parsing** → `🔍 Parsed QR data: [data]` or error

## Debugging Commands

### Browser Console Commands
```javascript
// Check if QR scanner is working
console.log('Testing QR scanner...');

// Check if camera permissions are granted
navigator.mediaDevices.getUserMedia({ video: true })
  .then(stream => console.log('Camera access granted'))
  .catch(err => console.log('Camera access denied:', err));
```

### Manual QR Code Test
Create a test QR code with this JSON:
```json
{
  "game": "Crucible",
  "playerNumber": 1,
  "playerName": "Test Player",
  "playerEmail": "test@example.com",
  "playerUid": "test-uid-123",
  "timestamp": 1234567890,
  "verificationHash": "test-hash"
}
```

## Troubleshooting

### If QR data is empty:
1. Check if the QR code is valid
2. Try a different QR code
3. Check camera permissions
4. Try refreshing the page
5. Check for JavaScript errors

### If JSON parsing fails:
1. Verify QR code contains valid JSON
2. Check for special characters in QR code
3. Try encoding/decoding the QR data
4. Check if QR code is truncated

### If scanner doesn't work:
1. Check browser compatibility
2. Verify HTTPS is being used (required for camera)
3. Check camera permissions
4. Try a different browser
5. Check for ad blockers or security software

## Next Steps

1. **Deploy the updated build** with enhanced debugging
2. **Test with a known good QR code**
3. **Check the console logs** for the detailed flow
4. **Compare behavior** between development and production
5. **Test with different QR codes** to isolate the issue
