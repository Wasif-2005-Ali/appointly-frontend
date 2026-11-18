import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_config.dart';
import 'token_storage.dart';

/// Thrown for API failures with a message safe to show to the user.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Thrown when the stored tokens are no longer valid (refresh failed).
/// The UI should send the user back to the login screen.
class SessionExpiredException extends ApiException {
  const SessionExpiredException()
    : super('Your session has expired. Please log in again.');
}

/// Outcome of a token refresh attempt.
enum _RefreshResult {
  /// New tokens were stored.
  ok,

  /// The refresh token was rejected (401) or is missing — the session
  /// is really over and the stored tokens were cleared.
  expired,

  /// The refresh request failed for a non-auth reason (server 5xx,
  /// dropped connection, ...). The stored tokens were kept: the
  /// session may still be valid, so this must NOT log the user out.
  transient,
}

/// Thin HTTP wrapper over the Appointly backend.
///
/// - Attaches the stored access token as `Authorization: Bearer ...`.
/// - On a 401 it refreshes the access token once (rotation is enabled on
///   the backend, so a new refresh token is stored too) and retries the
///   request once.
/// - Network failures surface as [ApiException] with a friendly message.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _timeout = Duration(seconds: 45);

  /// Uploads (photos, documents) take longer than JSON calls.
  static const _uploadTimeout = Duration(seconds: 60);

  final http.Client _http = http.Client();

  /// Called when a token refresh fails with 401, i.e. the session is
  /// really over (not on transient refresh failures — those keep the
  /// stored tokens). Registered by the app shell in `main.dart`, which
  /// clears the session and sends the user to the login screen. A
  /// callback (rather than a direct navigation) keeps this service
  /// free of screen imports and avoids import cycles.
  static void Function()? onSessionExpired;

  /// In-flight refresh, shared so parallel 401s only refresh once.
  Future<_RefreshResult>? _refreshFuture;

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Map<String, String>> _authHeaders() async {
    final headers = Map<String, String>.from(_jsonHeaders);
    final token = await TokenStorage.instance.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> get(String path, {bool auth = true}) {
    return _send(
      () async => _http.get(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: auth ? await _authHeaders() : _jsonHeaders,
      ),
      retryOnAuth: auth,
    );
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) {
    return _send(
      () async => _http.post(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: auth ? await _authHeaders() : _jsonHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      retryOnAuth: auth,
    );
  }

  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) {
    return _send(
      () async => _http.patch(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: auth ? await _authHeaders() : _jsonHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      retryOnAuth: auth,
    );
  }

  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) {
    return _send(
      () async => _http.put(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: auth ? await _authHeaders() : _jsonHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      retryOnAuth: auth,
    );
  }

  Future<http.Response> delete(String path, {bool auth = true}) {
    return _send(
      () async => _http.delete(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: auth ? await _authHeaders() : _jsonHeaders,
      ),
      retryOnAuth: auth,
    );
  }

  /// Authenticated multipart file upload. The request is rebuilt on
  /// every attempt, so the 401 → refresh → retry flow works the same
  /// as for JSON calls. Uses the longer upload timeout.
  Future<http.Response> uploadMultipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) {
    return _send(
      () async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiConfig.baseUrl}$path'),
        );
        final token = await TokenStorage.instance.accessToken;
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.headers['Accept'] = 'application/json';
        request.files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: mimeType == null ? null : MediaType.parse(mimeType),
          ),
        );
        final streamed = await request.send();
        return http.Response.fromStream(streamed);
      },
      retryOnAuth: true,
      timeout: _uploadTimeout,
    );
  }

  /// Runs [request] once; on a 401 (and only for authenticated calls)
  /// refreshes the token and retries once.
  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required bool retryOnAuth,
    Duration? timeout,
  }) async {
    final t = timeout ?? _timeout;
    var res = await _guarded(request, timeout: t);
    if (res.statusCode == 401 && retryOnAuth) {
      final result = await _refreshAccessToken();
      if (result != _RefreshResult.ok) {
        if (result == _RefreshResult.expired) {
          // The session is really over — tell the app shell so it
          // can clear the session and show the login screen.
          onSessionExpired?.call();
          throw const SessionExpiredException();
        }
        // Transient refresh failure (server 5xx, dropped
        // connection): the tokens were kept, so this is not a
        // session expiry — just a failed request.
        throw const ApiException(
          'Could not refresh your session. Please try again.',
        );
      }
      res = await _guarded(request, timeout: t);
      if (res.statusCode == 401) {
        // Even a freshly refreshed token was rejected: the session
        // is dead. Clear the tokens so nothing keeps retrying with
        // them, and send the user back to login.
        await TokenStorage.instance.clear();
        onSessionExpired?.call();
        throw const SessionExpiredException();
      }
    }
    return res;
  }

  /// Runs [request] and converts transport failures into [ApiException].
  /// A timeout or a dropped connection is retried ONCE before throwing:
  /// the free-tier backend takes ~30s to wake from a cold start, and
  /// Render also drops connections mid-request fairly often, so the
  /// first attempt after idle (or mid-request) would otherwise always
  /// fail. (No retry on the 401 path — that is handled by the token
  /// refresh in [_send] — and no retry on 4xx/5xx responses.)
  Future<http.Response> _guarded(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await request().timeout(timeout ?? _timeout);
      } on TimeoutException {
        if (attempt == 1) {
          throw const ApiException(
            'The server is taking too long to respond. Please try again.',
          );
        }
        // First timeout — retry once (likely a cold start).
      } on SocketException {
        if (attempt == 1) {
          throw const ApiException(
            'Connection dropped. Please try again.',
          );
        }
        // First drop — retry once (Render drops connections
        // mid-request on the free tier).
      } on http.ClientException {
        if (attempt == 1) {
          throw const ApiException(
            'Connection dropped. Please try again.',
          );
        }
        // First drop — retry once, as for SocketException.
      }
    }
    throw const ApiException(
      'The server is taking too long to respond. Please try again.',
    );
  }

  Future<_RefreshResult> _refreshAccessToken() {
    _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);
    return _refreshFuture!;
  }

  /// Refreshes the access token. Only a 401 clears the stored tokens:
  /// any other failure (server 5xx, dropped connection, malformed
  /// body) keeps them, because the session may still be valid and a
  /// transient Render blip must not destroy it.
  Future<_RefreshResult> _doRefresh() async {
    final refresh = await TokenStorage.instance.refreshToken;
    if (refresh == null || refresh.isEmpty) return _RefreshResult.expired;
    try {
      final res = await _http
          .post(
            Uri.parse('${ApiConfig.authBase}/token/refresh/'),
            headers: _jsonHeaders,
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(_timeout);
      if (res.statusCode == 401) {
        await TokenStorage.instance.clear();
        return _RefreshResult.expired;
      }
      if (res.statusCode != 200) {
        // Transient server failure — keep the tokens.
        return _RefreshResult.transient;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) return _RefreshResult.transient;
      // Refresh-token rotation is enabled: store the new refresh token too.
      final newRefresh = data['refresh'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await TokenStorage.instance.saveTokens(
          access: access,
          refresh: newRefresh,
        );
      } else {
        await TokenStorage.instance.saveAccessToken(access);
      }
      return _RefreshResult.ok;
    } catch (_) {
      // Dropped connection / timeout — keep the tokens.
      return _RefreshResult.transient;
    }
  }

  /// Extracts the first human-readable message from a DRF error body:
  /// `{"detail": "..."}` or `{"email": ["..."], ...}` or
  /// `{"non_field_errors": ["..."]}`. Falls back to [fallback].
  static String errorMessage(http.Response res, String fallback) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
          if (value is String && value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // Not JSON — fall through to the fallback message.
    }
    return fallback;
  }
}
