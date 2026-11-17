// Unit tests for the appointment model mapping (backend API -> local
// model). Pure Dart, no plugins, no network — run with `flutter test`.
//
// Covers the statuses the new backend endpoints produce, so a
// completed appointment coming back from POST .../complete/ (or the
// auto-complete path) maps to ApptStatus.completed instead of
// silently becoming pending.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/models/appointment.dart';

Map<String, dynamic> apiJson({String status = 'pending'}) => {
      'id': 7,
      'requester_id': 2,
      'provider_id': 3,
      'starts_at': '2026-11-19T09:00:00Z',
      'ends_at': '2026-11-19T09:30:00Z',
      'status': status,
      'notes': 'Client: Test Name',
      'created_at': '2026-11-17T10:00:00Z',
    };

void main() {
  group('Appointment.fromApi status mapping', () {
    test('completed maps to ApptStatus.completed', () {
      final appt = Appointment.fromApi(apiJson(status: 'completed'));
      expect(appt.status, ApptStatus.completed);
    });

    test('accepted maps to ApptStatus.confirmed', () {
      final appt = Appointment.fromApi(apiJson(status: 'accepted'));
      expect(appt.status, ApptStatus.confirmed);
    });

    test('pending / rejected / cancelled map through', () {
      expect(Appointment.fromApi(apiJson(status: 'pending')).status,
          ApptStatus.pending);
      expect(Appointment.fromApi(apiJson(status: 'rejected')).status,
          ApptStatus.rejected);
      expect(Appointment.fromApi(apiJson(status: 'cancelled')).status,
          ApptStatus.cancelled);
    });

    test('unknown status falls back to pending, never throws', () {
      final appt = Appointment.fromApi(apiJson(status: 'missed'));
      expect(appt.status, ApptStatus.pending);
    });

    test('keeps ids, notes and a 30-minute duration', () {
      final appt = Appointment.fromApi(apiJson(status: 'accepted'),
          currentUserId: '2');
      expect(appt.id, 7);
      expect(appt.requesterId, '2');
      expect(appt.providerId, '3');
      expect(appt.note, 'Client: Test Name');
      expect(appt.duration, '30 min');
      // Viewed as the requester, the other party is the provider.
      expect(appt.name, 'Provider #3');
    });

    test('provider view names the requester', () {
      final appt = Appointment.fromApi(apiJson(), currentUserId: '3');
      expect(appt.name, 'Requester #2');
    });
  });

  group('Appointment.durationLabel', () {
    test('known buckets', () {
      expect(Appointment.durationLabel(15), '15 min');
      expect(Appointment.durationLabel(30), '30 min');
      expect(Appointment.durationLabel(60), '1 hr');
      expect(Appointment.durationLabel(90), '1.5 hr');
    });

    test('unknown minutes fall back to N min', () {
      expect(Appointment.durationLabel(25), '25 min');
    });
  });
}
