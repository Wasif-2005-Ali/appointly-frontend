/// Central place for the backend address used by [ApiClient].
///
/// ── Deployed backend (default) ────────────────────────────────────
/// The backend is deployed on Render (free tier), so the app works on
/// any phone or emulator with no LAN IP setup. Note the free Render
/// instance sleeps after 15 minutes idle — the first request after a
/// pause can take up to a minute.
///
/// ── Local development ─────────────────────────────────────────────
/// To run against a local backend instead, change [baseUrl] to
/// 'http://10.0.2.2:8000' (Android emulator) or your laptop's LAN IP
/// (physical phone, e.g. 'http://192.168.1.5:8000') and start the
/// backend with `python manage.py runserver 0.0.0.0:8000`.
class ApiConfig {
  static const String baseUrl = 'https://appointly-backend-dogk.onrender.com';

  /// Base path for the auth endpoints (register, login, me, ...).
  static const String authBase = '$baseUrl/api/v1/auth';

  /// Web OAuth client ID for Google Sign-In (Google Cloud Console →
  /// APIs & Services → Credentials → OAuth 2.0 Client IDs, type "Web
  /// application"). The backend verifies ID tokens against the same
  /// client ID (GOOGLE_CLIENT_ID on Render). GCP project "Appointly"
  /// (appointly-514920); the consent screen was published on 17 Nov
  /// 2026, so any Google account can sign in.
  static const String googleServerClientId =
      '1079927760935-c1qptn5omdikssrl58cu7ehkdkki4643.apps.googleusercontent.com';
}
