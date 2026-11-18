// Unit tests for the call stack's TURN credential generation and ICE
// server list. Pure Dart, no plugins, no network — run with
// `flutter test`.
//
// The TURN fix (FIX 1) depends on Metered's static-auth scheme:
// username "<unix-expiry>:appointly", credential = base64(HMAC-SHA1
// (key "openrelayprojectsecret", message username)). The expected
// values below were computed independently with Python's hmac module
// (hmac.new(b'openrelayprojectsecret', b'1700000000:appointly',
// hashlib.sha1)) — if the Dart output ever drifts from the spec,
// calls behind carrier NATs silently lose their media path again.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/services/call_service.dart';

void main() {
  group('meteredTurnCredentials', () {
    test('matches the known HMAC-SHA1 vector', () {
      final creds = meteredTurnCredentials(expiryUnix: 1700000000);
      expect(creds['username'], '1700000000:appointly');
      expect(creds['credential'], '7sH3lrykFlAPoUdwiuKeB+EIJJo=');
    });

    test('matches a second known vector', () {
      final creds = meteredTurnCredentials(expiryUnix: 1795734000);
      expect(creds['username'], '1795734000:appointly');
      expect(creds['credential'], '0594bMLGTUGLJuGc8xqjJ0KtFJA=');
    });

    test('different expiries give different credentials', () {
      final a = meteredTurnCredentials(expiryUnix: 1700000000);
      final b = meteredTurnCredentials(expiryUnix: 1700000001);
      expect(a['credential'], isNot(b['credential']));
    });
  });

  group('CallConnection.iceServers', () {
    test('uses the static-auth TURN host, never the dead one', () {
      final servers = CallConnection.iceServers(expiryUnix: 1700000000);
      final urls = servers.map((s) => s['urls'] as String).toList();
      // The old host resolves to the 192.0.2.1 TEST-NET sinkhole.
      // (Match the bare host: staticauth.openrelay.metered.ca is the
      // new host and legitimately contains "openrelay.metered.ca".)
      expect(
        urls.any((u) => u.startsWith('turn:openrelay.metered.ca')),
        isFalse,
        reason: 'Dead TURN host must not appear in the ICE servers.',
      );
      expect(urls, contains('turn:staticauth.openrelay.metered.ca:80'));
      expect(urls, contains('turn:staticauth.openrelay.metered.ca:443'));
      // TCP variants: 443 TCP is the most firewall-proof transport.
      expect(
        urls,
        contains('turn:staticauth.openrelay.metered.ca:80?transport=tcp'),
      );
      expect(
        urls,
        contains('turn:staticauth.openrelay.metered.ca:443?transport=tcp'),
      );
    });

    test('keeps Google STUN and adds a second one', () {
      final servers = CallConnection.iceServers(expiryUnix: 1700000000);
      final urls = servers.map((s) => s['urls'] as String).toList();
      expect(urls, contains('stun:stun.l.google.com:19302'));
      expect(urls, contains('stun:stun1.l.google.com:19302'));
    });

    test('TURN entries carry the computed time-limited credentials', () {
      final servers = CallConnection.iceServers(expiryUnix: 1700000000);
      final turnServers = servers.where(
        (s) => (s['urls'] as String).startsWith('turn:'),
      );
      expect(turnServers.length, 4);
      for (final server in turnServers) {
        expect(server['username'], '1700000000:appointly');
        expect(server['credential'], '7sH3lrykFlAPoUdwiuKeB+EIJJo=');
      }
    });

    test('default expiry is about an hour in the future', () {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final servers = CallConnection.iceServers();
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final turn = servers.firstWhere(
        (s) => (s['urls'] as String).startsWith('turn:'),
      );
      final username = turn['username'] as String;
      final expiry = int.parse(username.split(':').first);
      expect(expiry, greaterThanOrEqualTo(before + 3600));
      expect(expiry, lessThanOrEqualTo(after + 3600));
    });
  });
}
