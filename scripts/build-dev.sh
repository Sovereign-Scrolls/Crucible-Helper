#!/bin/bash

# Development Build Script for Crucible Helper
# This script builds the Flutter app with development configuration

echo "🔧 Building Crucible Helper for development..."

# Set development configuration
export GOOGLE_APPS_SCRIPT_URL="https://script.google.com/macros/s/DEV_SCRIPT_ID/exec"
export FIREBASE_REGION="us-central1"
export FIREBASE_PROJECT_ID="crucible-helper"
export DEVELOPMENT_MODE="true"
export DEBUG_LOGGING="true"

# Build the app
flutter build web \
  --dart-define=GOOGLE_APPS_SCRIPT_URL="$GOOGLE_APPS_SCRIPT_URL" \
  --dart-define=FIREBASE_REGION="$FIREBASE_REGION" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  --dart-define=DEVELOPMENT_MODE="$DEVELOPMENT_MODE" \
  --dart-define=DEBUG_LOGGING="$DEBUG_LOGGING" \
  --release

echo "✅ Development build completed!"
echo "📁 Output: build/web/"
echo "🌐 To run: flutter run -d chrome --web-port=8080"
