#!/bin/bash

# Production Build Script for Crucible Helper
# This script builds the Flutter app with production configuration

echo "🚀 Building Crucible Helper for production..."

# Set production configuration
export GOOGLE_APPS_SCRIPT_URL="https://script.google.com/macros/s/PROD_SCRIPT_ID/exec"
export FIREBASE_REGION="us-central1"
export FIREBASE_PROJECT_ID="crucible-helper"
export DEVELOPMENT_MODE="false"
export DEBUG_LOGGING="false"

# Build the app
flutter build web \
  --dart-define=GOOGLE_APPS_SCRIPT_URL="$GOOGLE_APPS_SCRIPT_URL" \
  --dart-define=FIREBASE_REGION="$FIREBASE_REGION" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  --dart-define=DEVELOPMENT_MODE="$DEVELOPMENT_MODE" \
  --dart-define=DEBUG_LOGGING="$DEBUG_LOGGING" \
  --release

echo "✅ Production build completed!"
echo "📁 Output: build/web/"
echo "🌐 Ready for deployment to Firebase Hosting"
