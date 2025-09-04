# Configuration Guide

This guide explains how to configure the Crucible Helper app for different environments and Google Sheets setups.

## Overview

The app now uses a centralized configuration system that allows you to easily change settings without modifying code. This includes:

- Google Sheets API URLs
- Firebase project settings
- Environment-specific configurations

## Configuration Files

### 1. Flutter App Configuration (`lib/config/app_config.dart`)

This file contains all the configuration constants for the Flutter app. It uses Dart's `String.fromEnvironment` to allow configuration via build-time environment variables.

#### Key Configuration Options:

```dart
// Google Sheets API Configuration
static const String googleAppsScriptUrl = String.fromEnvironment(
  'GOOGLE_APPS_SCRIPT_URL',
  defaultValue: 'https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec',
);

// Firebase Configuration
static const String firebaseRegion = String.fromEnvironment(
  'FIREBASE_REGION',
  defaultValue: 'us-central1',
);

static const String firebaseProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'crucible-helper',
);
```

### 2. Firebase Functions Configuration (`functions/config.json`)

This file contains configuration for Firebase Functions, including the Google Apps Script URL.

```json
{
  "discord": {
    "bot_token": "YOUR_DISCORD_BOT_TOKEN"
  },
  "google_sheets": {
    "apps_script_url": "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
  }
}
```

## How to Configure

### Option 1: Build-Time Environment Variables (Recommended)

When building the Flutter app, you can pass environment variables:

```bash
# For development
flutter run --dart-define=GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/DEV_SCRIPT_ID/exec

# For production
flutter build web --dart-define=GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/PROD_SCRIPT_ID/exec
```

### Option 2: Modify Configuration Files Directly

#### For Flutter App:
Edit `lib/config/app_config.dart` and change the `defaultValue` parameters:

```dart
static const String googleAppsScriptUrl = String.fromEnvironment(
  'GOOGLE_APPS_SCRIPT_URL',
  defaultValue: 'https://script.google.com/macros/s/YOUR_NEW_SCRIPT_ID/exec',
);
```

#### For Firebase Functions:
Edit `functions/config.json`:

```json
{
  "google_sheets": {
    "apps_script_url": "https://script.google.com/macros/s/YOUR_NEW_SCRIPT_ID/exec"
  }
}
```

### Option 3: Environment-Specific Builds

Create different build configurations for different environments:

#### Development Build Script (`scripts/build-dev.sh`):
```bash
#!/bin/bash
flutter build web \
  --dart-define=GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/DEV_SCRIPT_ID/exec \
  --dart-define=DEVELOPMENT_MODE=true \
  --dart-define=DEBUG_LOGGING=true
```

#### Production Build Script (`scripts/build-prod.sh`):
```bash
#!/bin/bash
flutter build web \
  --dart-define=GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/PROD_SCRIPT_ID/exec \
  --dart-define=DEVELOPMENT_MODE=false \
  --dart-define=DEBUG_LOGGING=false
```

## Setting Up Different Google Sheets

### 1. Create New Google Apps Script

1. Go to [script.google.com](https://script.google.com)
2. Create a new project
3. Copy the code from `App Script/advancement_intake`
4. Update the CONFIG section with your settings:

```javascript
const CONFIG = {
  FIREBASE: {
    API_KEY: 'YOUR_FIREBASE_API_KEY',
    PROJECT_ID: 'YOUR_FIREBASE_PROJECT_ID'
  },
  
  SHEETS: {
    AFFINITY: 'Affinity Changes',
    SKILL:    'Skill Changes', 
    ESSENCE:  'Essence Changes'
  },
  
  SPREADSHEET_ID: 'YOUR_SPREADSHEET_ID' // Optional
};
```

### 2. Deploy the Script

1. Click "Deploy" → "New deployment"
2. Set type to "Web app"
3. Set "Execute as" to your email
4. Set "Who has access" to "Anyone"
5. Copy the Web app URL

### 3. Update Configuration

Update your configuration with the new script URL:

```bash
flutter run --dart-define=GOOGLE_APPS_SCRIPT_URL=YOUR_NEW_SCRIPT_URL
```

## Environment Variables Reference

### Flutter App Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GOOGLE_APPS_SCRIPT_URL` | Google Apps Script web app URL | Current hardcoded URL |
| `FIREBASE_REGION` | Firebase region | `us-central1` |
| `FIREBASE_PROJECT_ID` | Firebase project ID | `crucible-helper` |
| `DEVELOPMENT_MODE` | Enable development features | `false` |
| `DEBUG_LOGGING` | Enable debug logging | `true` |

### Firebase Functions Configuration

| Key | Description |
|-----|-------------|
| `google_sheets.apps_script_url` | Google Apps Script web app URL |
| `discord.bot_token` | Discord bot token |

## Best Practices

### 1. Environment Separation

- Use different Google Apps Script deployments for development and production
- Use different Google Sheets for different environments
- Use environment variables to switch between configurations

### 2. Security

- Never commit sensitive configuration to version control
- Use environment variables for production deployments
- Regularly rotate API keys and tokens

### 3. Testing

- Test configuration changes in development first
- Use the same configuration structure across environments
- Document any environment-specific requirements

## Troubleshooting

### Common Issues

1. **Configuration not taking effect**
   - Ensure you're using the correct build command with environment variables
   - Check that the configuration file is being loaded correctly
   - Verify the environment variable names match exactly

2. **Google Apps Script errors**
   - Verify the script URL is correct and accessible
   - Check that the script is deployed as a web app
   - Ensure proper permissions are set

3. **Firebase Functions errors**
   - Verify the `functions/config.json` file is valid JSON
   - Check that the configuration is being loaded in the functions
   - Ensure the Google Apps Script URL is accessible from Firebase Functions

### Debug Configuration

Add debug logging to see what configuration is being used:

```dart
if (AppConfig.enableDebugLogging) {
  print('🔧 Configuration loaded:');
  print('  Google Apps Script URL: ${AppConfig.googleAppsScriptUrl}');
  print('  Firebase Region: ${AppConfig.firebaseRegion}');
  print('  Firebase Project ID: ${AppConfig.firebaseProjectId}');
}
```

## Migration from Hardcoded URLs

If you're migrating from the previous hardcoded system:

1. **Backup your current configuration**
2. **Update the configuration files** with your current URLs
3. **Test the new configuration** in development
4. **Deploy with the new configuration**
5. **Verify everything works** in production

The new system maintains backward compatibility while providing much more flexibility for configuration management.
