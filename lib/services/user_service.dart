import 'dart:convert';

import 'api_client.dart';

/// A user from the auth API: `{id, full_name, email, profession}`.
class AppUser {
  final int id;
  final String fullName;
  final String email;
  final String profession;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.profession,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    fullName: json['full_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    profession: json['profession'] as String? ?? '',
  );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}

/// User directory + profile updates against `/api/v1/auth/`.
///
/// Throws [ApiException] with a user-friendly message on failure.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  static const _auth = '/api/v1/auth';

  /// GET /api/v1/auth/users/?search=<query> — search users by name or
  /// email. The backend excludes the requester and returns at most 20
  /// matches; an empty query returns [] (short-circuited here too, so
  /// no request goes out).
  Future<List<AppUser>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final res = await ApiClient.instance.get(
      '$_auth/users/?search=${Uri.encodeQueryComponent(q)}',
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not search users.'),
        statusCode: res.statusCode,
      );
    }
    final decoded = jsonDecode(res.body);
    final List items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      // Paginated shape, in case the backend enables pagination later.
      items = decoded['results'] as List;
    } else {
      return const [];
    }
    return items
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cache for [fetchUserById]: call history resolves a name per
  /// peer, and the list must not refire a request per row per build.
  final Map<int, AppUser> _userCache = {};

  /// GET /api/v1/auth/users/<id>/ — one user by ID, for showing
  /// names (instead of "User #id") in call history. Cached: repeat
  /// lookups for the same ID never hit the network again. Returns
  /// null on any failure (unknown user, endpoint missing, offline)
  /// — callers fall back to "User #id".
  Future<AppUser?> fetchUserById(int id) async {
    final cached = _userCache[id];
    if (cached != null) return cached;
    try {
      final res = await ApiClient.instance.get('$_auth/users/$id/');
      if (res.statusCode != 200) return null;
      final user = AppUser.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      _userCache[id] = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/v1/auth/me/ — update the logged-in user's name and/or
  /// profession. Only the fields passed are sent. Returns the full
  /// updated user object (same shape as GET /me/).
  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? profession,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (profession != null) body['profession'] = profession;
    final res = await ApiClient.instance.patch('$_auth/me/', body: body);
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not update your profile.'),
        statusCode: res.statusCode,
      );
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }
}
