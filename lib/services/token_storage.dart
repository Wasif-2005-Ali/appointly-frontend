import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the JWT access / refresh tokens in the platform secure
/// storage (Android Keystore / iOS Keychain) — never in plain
/// SharedPreferences or SQLite.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const _kAccess = 'appointly_access_token';
  static const _kRefresh = 'appointly_refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> saveAccessToken(String access) async {
    await _storage.write(key: _kAccess, value: access);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);

  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  Future<bool> get hasRefreshToken async =>
      (await _storage.read(key: _kRefresh)) != null;

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
