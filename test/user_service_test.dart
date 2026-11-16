// Unit tests for the user directory parsing. Pure Dart, no plugins,
// no network — run with `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/services/user_service.dart';

void main() {
  group('AppUser.fromJson', () {
    test('parses all fields', () {
      final user = AppUser.fromJson({
        'id': 3,
        'full_name': 'Test B',
        'email': 'appt-test-b@example.com',
        'profession': 'Doctor',
      });
      expect(user.id, 3);
      expect(user.fullName, 'Test B');
      expect(user.email, 'appt-test-b@example.com');
      expect(user.profession, 'Doctor');
      expect(user.initials, 'TB');
    });

    test('defaults missing fields instead of throwing', () {
      final user = AppUser.fromJson({'id': 7});
      expect(user.id, 7);
      expect(user.fullName, '');
      expect(user.email, '');
      expect(user.profession, '');
      expect(user.initials, '?');
    });

    test('single-word name gives a single initial', () {
      final user = AppUser.fromJson({'id': 1, 'full_name': 'Wasif'});
      expect(user.initials, 'W');
    });
  });
}
