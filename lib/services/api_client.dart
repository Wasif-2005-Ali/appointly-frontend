import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

  static const _timeout = Duration(seconds: 15);

  final http.Client _http = http.Client();

  /// In-flight refresh, shared so parallel 401s only refresh once.
  Future<bool>? _refreshFuture;

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

  /// Runs [request] once; on a 401 (and only for authenticated calls)
  /// refreshes the token and retries once.
  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required bool retryOnAuth,
  }) async {
    var res = await _guarded(request);
    if (res.statusCode == 401 && retryOnAuth) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) throw const SessionExpiredException();
      res = await _guarded(request);
      if (res.statusCode == 401) throw const SessionExpiredException();
    }
    return res;
  }

  /// Runs [request] and converts transport failures into [ApiException].
  Future<http.Response> _guarded(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'The server is taking too long to respond. Please try again.',
      );
    } on SocketException {
      throw const ApiException(
        'Could not reach the server. Make sure the backend is running.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Make sure the backend is running.',
      );
    }
  }

  Future<bool> _refreshAccessToken() {
    _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);
    return _refreshFuture!;
  }

  Future<bool> _doRefresh() async {
    final refresh = await TokenStorage.instance.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _http
          .post(
            Uri.parse('${ApiConfig.authBase}/token/refresh/'),
            headers: _jsonHeaders,
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        await TokenStorage.instance.clear();
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) return false;
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
      return true;
    } catch (_) {
      return false;
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
