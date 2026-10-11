import 'dart:typed_data';

class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  int?       userId;
  String     fullName      = '';
  String     email         = '';
  String     profession    = '';
  String     phone         = '';
  String     bio           = '';
  String     profileStatus = 'Available';
  String     privacyMode   = 'Public';
  String     themeMode     = 'navyLight';
  Uint8List? profileImageBytes;

  bool get isLoggedIn => userId != null && fullName.isNotEmpty;

  String get firstName {
    final parts = fullName.trim().split(' ');
    return parts.isNotEmpty ? parts.first : fullName;
  }

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  void setUser({
    required String fullName,
    required String email,
    required String profession,
    int? userId,
    String phone         = '',
    String bio           = '',
    String profileStatus = 'Available',
    String privacyMode   = 'Public',
    String themeMode     = 'navyLight',
  }) {
    this.userId        = userId;
    this.fullName      = fullName;
    this.email         = email;
    this.profession    = profession;
    this.phone         = phone;
    this.bio           = bio;
    this.profileStatus = profileStatus;
    this.privacyMode   = privacyMode;
    this.themeMode     = themeMode;
  }

  void setFromMap(Map<String, dynamic> row) {
    userId        = row['id']             as int?;
    fullName      = (row['full_name']     as String?) ?? '';
    email         = (row['email']         as String?) ?? '';
    profession    = (row['profession']    as String?) ?? '';
    phone         = (row['phone']         as String?) ?? '';
    bio           = (row['bio']           as String?) ?? '';
    profileStatus = (row['profile_status']as String?) ?? 'Available';
    privacyMode   = (row['privacy_mode']  as String?) ?? 'Public';
    themeMode     = (row['theme_mode']    as String?) ?? 'navyLight';
    // profile_image comes back as Uint8List from sqflite BLOB
    final img = row['profile_image'];
    if (img is Uint8List && img.isNotEmpty) {
      profileImageBytes = img;
    } else {
      profileImageBytes = null;
    }
  }

  void clear() {
    userId = null;
    fullName = ''; email = ''; profession = '';
    phone = ''; bio = '';
    profileStatus = 'Available'; privacyMode = 'Public';
    themeMode = 'navyLight';
    profileImageBytes = null;
  }
}
