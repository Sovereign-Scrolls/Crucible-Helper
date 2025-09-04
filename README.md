# Crucible Helper

A Flutter web application for managing Crucible character data, scanning monster cores, and tracking game events.

## Features

- Character sheet management
- QR code scanning for monster cores
- Event tracking
- Google Sheets integration for advancement tracking
- Firebase authentication and data storage

## Quick Start

### Prerequisites

- Flutter SDK (latest stable version)
- Firebase project setup
- Google Apps Script deployment

### Running the App

```bash
# Development mode
flutter run -d chrome --web-port=8080

# Or use the build script
./scripts/build-dev.sh
```

### Configuration

The app uses a centralized configuration system. See [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) for detailed setup instructions.

#### Quick Configuration

1. **Update Google Apps Script URL** in `functions/config.json`:
   ```json
   {
     "google_sheets": {
       "apps_script_url": "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
     }
   }
   ```

2. **Build with custom configuration**:
   ```bash
   flutter run --dart-define=GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec
   ```

## Documentation

- [Configuration Guide](CONFIGURATION_GUIDE.md) - How to configure the app for different environments
- [Google Apps Script Setup](GOOGLE_APPS_SCRIPT_SETUP.md) - Setting up Google Sheets integration
- [Firebase Function Deployment](FIREBASE_FUNCTION_DEPLOYMENT.md) - Deploying Firebase Functions
- [Testing Guide](TESTING_CHECKIN_GUIDE.md) - Testing procedures

## Development

### Project Structure

```
lib/
├── config/           # Configuration files
├── models/           # Data models
├── pages/            # UI pages
├── shared/           # Shared services
└── utils/            # Utility functions

functions/            # Firebase Functions
├── config.json       # Function configuration
└── index.js          # Function implementations

App Script/           # Google Apps Script code
└── advancement_intake # Main script for Google Sheets integration
```

### Build Scripts

- `scripts/build-dev.sh` - Development build
- `scripts/build-prod.sh` - Production build

## License

This project is licensed under the MIT License.
