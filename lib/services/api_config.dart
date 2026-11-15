/// Central place for the backend address used by [ApiClient].
///
/// ── Android emulator ──────────────────────────────────────────────
/// The emulator cannot reach your laptop through `localhost`, so use the
/// special alias `10.0.2.2`, which maps to the host machine. Keep
/// [baseUrl] as-is when you run the app in the emulator.
///
/// ── Physical phone ────────────────────────────────────────────────
/// A real phone is on your Wi-Fi network, so point it at your laptop's
/// LAN IP instead, e.g. 'http://192.168.1.5:8000'.
/// Find the IP on Windows with `ipconfig` (look for IPv4 Address).
/// The backend must be started with `python manage.py runserver 0.0.0.0:8000`
/// so the phone can reach it.
class ApiConfig {
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Base path for the auth endpoints (register, login, me, ...).
  static const String authBase = '$baseUrl/api/v1/auth';
}
