import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';

import '../user_session.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'call_service.dart';
import 'token_storage.dart';

/// High-level auth operations against `/api/v1/auth/`.
///
/// Throws [ApiException] with a user-friendly message on failure.
/// On success, [login] and [register] return the backend user map
/// (`{id, full_name, email, profession}`), which fits
/// [UserSession.setFromMap] directly.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _auth = '/api/v1/auth';

  /// POST /login/ — saves the token pair and returns the user map.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await ApiClient.instance.post(
      '$_auth/login/',
      body: {'email': email, 'password': password},
      auth: false,
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Invalid email or password.'),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await TokenStorage.instance.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
    );
    // Start listening for incoming calls now that we are logged in.
    unawaited(CallService.instance.connectNotify());
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  /// POST /register/ — creates the account and returns the user map.
  /// Note: register does NOT return tokens, so call [login] afterwards.
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String profession,
    required String password,
    required String confirmPassword,
  }) async {
    final res = await ApiClient.instance.post(
      '$_auth/register/',
      body: {
        'full_name': fullName,
        'email': email,
        'profession': profession,
        'password': password,
        'confirm_password': confirmPassword,
      },
      auth: false,
    );
    if (res.statusCode != 201) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Registration failed. Please try again.'),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  /// POST /google/ — Google Sign-In. Gets an ID token from the Google
  /// SDK and exchanges it for the JWT pair. Returns the user map, like
  /// [login]. Throws [ApiException] when the user cancels or when the
  /// backend rejects the token.
  Future<Map<String, dynamic>> signInWithGoogle({String? profession}) async {
    if (ApiConfig.googleServerClientId.isEmpty) {
      throw const ApiException(
        'Google Sign-In is not set up yet. Please sign in with email for now.',
      );
    }
    final googleSignIn = GoogleSignIn(
      serverClientId: ApiConfig.googleServerClientId,
    );
    GoogleSignInAccount? account;
    try {
      account = await googleSignIn.signIn();
    } catch (_) {
      throw const ApiException(
        'Google Sign-In failed. Check your connection and try again.',
      );
    }
    if (account == null) {
      throw const ApiException('Google Sign-In was cancelled.');
    }
    // Fetching the token can fail (e.g. no network) — keep it inside
    // the try/catch so the friendly Google error is shown, not the
    // generic "Something went wrong".
    String? idToken;
    try {
      idToken = (await account.authentication).idToken;
    } catch (_) {
      throw const ApiException(
        'Google Sign-In failed. Check your connection and try again.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const ApiException(
        'Could not get a Google ID token. Please try again.',
      );
    }
    // The backend requires `profession` for brand-new Google users
    // (400 otherwise); it is ignored for existing accounts.
    final res = await ApiClient.instance.post(
      '$_auth/google/',
      body: {
        'id_token': idToken,
        if (profession != null && profession.isNotEmpty)
          'profession': profession,
      },
      auth: false,
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Google Sign-In failed. Please try again.'),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await TokenStorage.instance.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
    );
    // Start listening for incoming calls now that we are logged in.
    unawaited(CallService.instance.connectNotify());
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  /// GET /me/ — returns the current user's profile.
  Future<Map<String, dynamic>> fetchMe() async {
    final res = await ApiClient.instance.get('$_auth/me/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load your profile.'),
        statusCode: res.statusCode,
      );
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  /// POST /logout/ — blacklists the refresh token, then clears local state.
  /// Best-effort: local state is cleared even if the request fails.
  Future<void> logout() async {
    // End any active call and stop listening for incoming calls.
    await CallService.instance.activeCall?.dispose();
    await CallService.instance.disconnectNotify();
    final refresh = await TokenStorage.instance.refreshToken;
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await ApiClient.instance.post(
          '$_auth/logout/',
          body: {'refresh': refresh},
        );
      }
    } catch (_) {
      // Ignore — the server may already have invalidated the token.
    }
    await TokenStorage.instance.clear();
    UserSession.instance.clear();
  }

  /// POST /password-reset/ — requests a reset email.
  /// The backend never reveals whether the email exists, so this
  /// succeeds for any address (unless the server is unreachable).
  Future<void> requestPasswordReset(String email) async {
    final res = await ApiClient.instance.post(
      '$_auth/password-reset/',
      body: {'email': email},
      auth: false,
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not send the reset link.'),
        statusCode: res.statusCode,
      );
    }
  }

  /// Restores a previous login: loads the profile (refreshing the access
  /// token first if it expired). Returns the user map, or null when there
  /// is no saved session or the tokens are no longer valid.
  Future<Map<String, dynamic>?> restoreSession() async {
    if (!await TokenStorage.instance.hasRefreshToken) return null;
    try {
      final user = await fetchMe();
      unawaited(CallService.instance.connectNotify());
      return user;
    } on ApiException {
      return null;
    }
  }
}
