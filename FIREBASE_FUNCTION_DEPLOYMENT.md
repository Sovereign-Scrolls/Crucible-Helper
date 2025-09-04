# Firebase Function Deployment Guide

## Step 1: Install Firebase CLI (if not already installed)

```bash
npm install -g firebase-tools
```

## Step 2: Login to Firebase

```bash
firebase login
```

## Step 3: Navigate to Functions Directory

```bash
cd functions
```

## Step 4: Install Dependencies

```bash
npm install
```

## Step 5: Deploy the Function

```bash
firebase deploy --only functions
```

## Step 6: Verify Deployment

After deployment, you should see output like:
```
✔  functions[advancementIntake(us-central1)] Successful create operation. 
Function URL (advancementIntake): https://us-central1-crucible-helper.cloudfunctions.net/advancementIntake
```

## Step 7: Test the Function

You can test the function with curl:

```bash
curl -X POST "https://us-central1-crucible-helper.cloudfunctions.net/advancementIntake" \
  -H "Content-Type: application/json" \
  -d '{"idToken":"test","affinityChanges":[],"skillChanges":[],"essenceChanges":[]}'
```

## Troubleshooting

### If you get permission errors:
1. Make sure you're logged in with the correct Firebase account
2. Verify you have the correct project selected: `firebase use crucible-helper`

### If the function fails to deploy:
1. Check the Firebase console for error messages
2. Verify your Firebase project has Functions enabled
3. Make sure you have the Blaze (pay-as-you-go) plan (required for Functions)

### If you get CORS errors:
The function already includes CORS headers, but if you still get errors, check:
1. The function URL is correct
2. The request includes the correct Content-Type header
3. The Firebase project ID matches your app

## Benefits of Firebase Functions

1. **Better CORS support** - Native CORS handling
2. **Automatic scaling** - Handles traffic spikes
3. **Built-in monitoring** - Logs and metrics in Firebase console
4. **Security** - Automatic Firebase Auth integration
5. **Reliability** - Google's infrastructure

## Data Storage

The function stores data in Firestore. You can view the data in the Firebase console under Firestore Database.
