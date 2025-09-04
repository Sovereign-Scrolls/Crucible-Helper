# QR Code Generation Function Test Guide

## ✅ **Successfully Implemented!**

### **What's Been Deployed:**

1. **Firebase Function**: `generateQRCode` - Automatically triggers when `pc.json` files are updated
2. **QR Code Content**: Contains game identifier, player info, and verification hash
3. **Security**: Hash-based verification with secret key
4. **Integration**: Works with existing profile page QR display

### **How It Works:**

1. **Trigger**: When a `pc.json` file is uploaded/updated in Firebase Storage
2. **Data Extraction**: Reads character data and gets player info
3. **QR Generation**: Creates QR code with:
   - Game: "Crucible"
   - Player Number: From character data
   - Player Name: From character data  
   - Player Email: From file path
   - Player UID: From Firebase Auth (if available)
   - Timestamp: Current time
   - Verification Hash: SHA-256 hash with secret key

4. **File Upload**: Saves `qr.png` to same user folder
5. **App Display**: Profile page shows the generated QR code

### **Testing Steps:**

1. **Upload a pc.json file** to Firebase Storage at `users/email/pc.json`
2. **Check Firebase Functions logs** for QR generation
3. **Verify qr.png** appears in the same folder
4. **Test QR scanning** with the app

### **Expected Log Output:**
```
🔄 Processing pc.json update: users/test@example.com/pc.json
📧 Processing QR code for user: test@example.com
🔍 Found Firebase UID for test@example.com: abc123def456
🔐 Generated verification hash: a1b2c3d4
📱 Generated QR code image (1234 bytes)
✅ QR code uploaded to: users/test@example.com/qr.png
📊 QR Code Data: { game: "Crucible", playerNumber: 123, ... }
```

### **Security Features:**

- ✅ **Secret Key**: Hash includes server-side secret
- ✅ **Timestamp**: Prevents replay attacks  
- ✅ **Data Integrity**: Hash validates all fields
- ✅ **UID Verification**: Links to Firebase Auth

### **Next Steps:**

1. **Test with real character data**
2. **Verify QR codes scan correctly**
3. **Check profile page display**
4. **Monitor function performance**

The function is now live and ready to generate QR codes automatically! 🎉
