class AppConfig {
  // Google Sheets API Configuration
  static const String googleAppsScriptUrl = String.fromEnvironment(
    'GOOGLE_APPS_SCRIPT_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbxCSEd5kTXtN03UyAcMnAcnXlWGzbLYCjmZ8P5EuvBXeE5zw-aA4f5uHAVcGpNLtw0-/exec',
  );

  // Firebase Functions Configuration
  static const String firebaseRegion = String.fromEnvironment(
    'FIREBASE_REGION',
    defaultValue: 'us-central1',
  );

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'crucible-helper',
  );

  // API Endpoints
  static String get advancementIntakeUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/advancementIntake';

  static String get checkSuperAdminUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/checkSuperAdmin';

  static String get getMonsterCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/getMonsterCore';

  static String get trackMonsterCoreScanUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/trackMonsterCoreScan';

  static String get consumeMonsterCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/consumeMonsterCore';

  static String get generateMonsterCorePrintoutUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/generateMonsterCorePrintout';

  static String get regenerateAllQRCodesUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/regenerateAllQRCodes';

  static String get reactivateMonsterCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/reactivateMonsterCore';

  static String get getMonsterCoreReactivationHistoryUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/getMonsterCoreReactivationHistory';

  static String get storeMonsterCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/storeMonsterCore';

  static String get getStoredCoresUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/getStoredCores';

  static String get useStoredCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/useStoredCore';

  static String get tradeStoredCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/tradeStoredCore';

  static String get getPlayerCharactersUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/getPlayerCharacters';

  static String get getCharactersUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/getCharacters';

  static String get fixCharacterPlayerUidUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/fixCharacterPlayerUid';

  static String get syncCharacterToFirestoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/syncCharacterToFirestore';

  static String get checkCharacterExistsUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/checkCharacterExists';

  static String get initializeUserStructureUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/initializeUserStructure';

  static String get tradeMonsterCoreUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/tradeMonsterCore';

  static String get testCharacterStructureUrl => 
    'https://$firebaseRegion-$firebaseProjectId.cloudfunctions.net/testCharacterStructure';

  // Development/Production flags
  static const bool isDevelopment = bool.fromEnvironment(
    'DEVELOPMENT_MODE',
    defaultValue: false,
  );

  // Debug logging
  static const bool enableDebugLogging = bool.fromEnvironment(
    'DEBUG_LOGGING',
    defaultValue: true,
  );
}
