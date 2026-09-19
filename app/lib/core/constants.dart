/// App-wide constants. All third-party keys are injected at build time via
/// --dart-define and default to empty placeholders so the project compiles and
/// runs before the accounts exist.
library;

const String vitaApiBaseUrl = String.fromEnvironment(
  'VITA_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8260',
);

/// RevenueCat public SDK key (from the RevenueCat dashboard).
const String revenueCatApiKey = String.fromEnvironment(
  'VITA_REVENUECAT_KEY',
  defaultValue: '',
);

/// Google OAuth web client ID (server-side audience). Required on Android to
/// receive a usable ID token; on iOS the app client ID from
/// GoogleService-Info.plist is used.
const String googleServerClientId = String.fromEnvironment(
  'VITA_GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);
