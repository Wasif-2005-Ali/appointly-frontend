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
}
