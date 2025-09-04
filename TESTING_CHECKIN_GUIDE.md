# Testing Event Check-In System

## 🔧 **Setup Required**

### **1. Get Your Firebase UID**

1. **Open the app** in your browser
2. **Open Developer Tools** (F12)
3. **Go to Console tab**
4. **Look for the permission check logs** - you should see something like:
   ```
   🔍 Checking permissions for user: abc123def456 (your-email@example.com)
   ```

5. **Copy your UID** (the long string like `abc123def456`)

### **2. Add Test Data to Firestore**

**Option A: Use Firebase Console (Recommended)**
1. Go to [Firebase Console](https://console.firebase.google.com/project/crucible-helper/firestore)
2. Navigate to **Firestore Database**
3. Create the following collections and documents:

```
/roles/superadmin/members/{YOUR_UID}
{
  "role": "superadmin",
  "addedAt": "2024-01-01T00:00:00.000Z",
  "email": "your-email@example.com"
}
```

```
/events/weekend/registrations/{YOUR_UID}
{
  "registeredAt": "2024-01-01T00:00:00.000Z",
  "status": "registered"
}
```

**Option B: Use the Script**
1. Replace `your-firebase-uid-here` in `add_test_data.js` with your actual UID
2. Run: `node add_test_data.js`

### **3. Test the Functionality**

1. **Refresh the Events page** in your app
2. **Look for "Check In Players" buttons** on event cards
3. **Check the console** for permission check logs
4. **Click "Check In Players"** to test QR scanning

## 🔍 **Debugging**

### **Console Logs to Look For:**

✅ **Success:**
```
🔍 Checking permissions for user: abc123def456 (your-email@example.com)
🔍 Super admin check result: true
✅ User is super admin
```

❌ **No Permissions:**
```
🔍 Checking permissions for user: abc123def456 (your-email@example.com)
🔍 Super admin check result: false
🔍 Checking event registration for: weekend
🔍 Event registration check result: false
❌ User is not registered for event: weekend
```

❌ **Not Authenticated:**
```
❌ No authenticated user found
```

## 🎯 **Expected Behavior**

- **With Super Admin**: All events show "Check In Players" button
- **With Event Registration**: Only that specific event shows the button
- **Without Permissions**: No check-in buttons appear
- **QR Scanner**: Opens modal with camera access
- **QR Display**: Shows scanned QR code content

## 🚀 **Next Steps**

Once testing works:
1. Add real admin users to Firestore
2. Test with actual player QR codes
3. Implement actual check-in logic
4. Add check-in history tracking
