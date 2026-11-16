// Unit tests for the backend integration: the API -> model mapping and the
// error-message parsing the UI shows in snackbars. Pure Dart, no plugins,
// no network — run with `flutter test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:appointly/models/appointment.dart';
import 'package:appointly/services/api_client.dart';

void main() {
  group('Appointment.fromApi', () {
    Map<String, dynamic> json({String status = 'pending'}) => {
      'id': 7,
      'requester_id': 2,
      'provider_id': 3,
      'starts_at': '2026-11-17T10:00:00+05:00',
      'ends_at': '2026-11-17T10:30:00+05:00',
      'status': status,
      'notes': 'Bring reports',
      'created_at': '2026-11-16T20:00:00Z',
    };

    test('maps a pending appointment for the requester', () {
      final a = Appointment.fromApi(json(), currentUserId: '2');
      expect(a.id, 7);
      expect(a.name, 'Provider #3');
      expect(a.status, ApptStatus.pending);
      expect(a.duration, '30 min');
      expect(a.note, 'Bring reports');
      expect(a.providerId, '3');
      expect(a.requesterId, '2');
    });

    test('maps an accepted appointment to confirmed for the provider', () {
      final a = Appointment.fromApi(
        json(status: 'accepted'),
        currentUserId: '3',
      );
      expect(a.name, 'Requester #2');
      expect(a.status, ApptStatus.confirmed);
    });

    test('maps rejected and cancelled statuses', () {
      expect(
        Appointment.fromApi(json(status: 'rejected')).status,
        ApptStatus.rejected,
      );
      expect(
        Appointment.fromApi(json(status: 'cancelled')).status,
        ApptStatus.cancelled,
      );
    });
  });

  group('ApiClient.errorMessage', () {
    test('prefers detail, then message', () {
      expect(
        ApiClient.errorMessage(
          http.Response('{"detail": "Nope."}', 400),
          'fallback',
        ),
        'Nope.',
      );
      expect(
        ApiClient.errorMessage(
          http.Response('{"message": "Hello."}', 400),
          'fallback',
        ),
        'Hello.',
      );
    });

    test('reads DRF field errors and falls back on bad bodies', () {
      expect(
        ApiClient.errorMessage(
          http.Response(
            '{"email": ["A user with this email already exists."]}',
            400,
          ),
          'fallback',
        ),
        'A user with this email already exists.',
      );
      expect(
        ApiClient.errorMessage(http.Response('not json', 500), 'fallback'),
        'fallback',
      );
    });
  });
}
