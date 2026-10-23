// Settings given at build time with --dart-define (same values as the web .env).
// Put them in env.json and run: flutter run --dart-define-from-file=env.json   (see env.example.json)
class Config {
  static const apiHost = String.fromEnvironment('API_HOST'); // from env.json, never written here
  static const apiKey = String.fromEnvironment('API_AUTH_KEY');
  // the web app (business screens that are still web open inside the app; email links finish there)
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'http://localhost:3000');
  // the web keeps its login in localStorage under this key (VITE_LOGIN_STORAGE_KEY)
  static const webLoginKey = String.fromEnvironment('WEB_LOGIN_KEY', defaultValue: 'bizhub_login');

  // Firebase (same project as the website): proves the email — Google or a confirm link
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY'); // = VITE_FIREBASE_API_KEY
  // Google sign-in: the "Web client ID" (Firebase → Authentication → Google → Web SDK configuration)
  static const googleClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  // test only (same as VITE_FAKE_PHONE_AUTH): no real Google / email; the API accepts the fake
  // tokens only when NODE_ENV=test and FIREBASE_TEST_TOKENS=1.
  static const fakeAuth = bool.fromEnvironment('FAKE_AUTH');
}
