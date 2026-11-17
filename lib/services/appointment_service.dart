import 'dart:convert';

import '../models/appointment.dart';
import '../user_session.dart';
import 'api_client.dart';

/// A weekly availability rule: one time window on one weekday.
/// Weekday follows the backend: 0 = Monday … 6 = Sunday.
/// Times are 24-hour "HH:MM" strings.
class AvailabilityRule {
  final int weekday;
  final String startsAt;
  final String endsAt;

  const AvailabilityRule({
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
  });

  factory AvailabilityRule.fromJson(Map<String, dynamic> json) =>
      AvailabilityRule(
        weekday: json['weekday'] as int,
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
      );

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'starts_at': startsAt,
    'ends_at': endsAt,
  };
}

/// A provider's weekly schedule as returned by `/availability/me/`.
class WeeklySchedule {
  final String providerId;
  final String? timezone;
  final List<AvailabilityRule> rules;

  const WeeklySchedule({
    required this.providerId,
    required this.timezone,
    required this.rules,
  });

  factory WeeklySchedule.fromJson(Map<String, dynamic> json) => WeeklySchedule(
    providerId: json['provider_id'].toString(),
    timezone: json['timezone'] as String?,
    rules: (json['rules'] as List)
        .map((r) => AvailabilityRule.fromJson(r as Map<String, dynamic>))
        .toList(),
  );
}

/// One free slot from `/availability/slots/` (times converted to local).
class TimeSlot {
  final DateTime startsAt;
  final DateTime endsAt;

  const TimeSlot({required this.startsAt, required this.endsAt});

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
  );
}

/// Appointments + availability operations against `/api/v1/appointments/`
/// and `/api/v1/availability/`.
///
/// Throws [ApiException] with a user-friendly message on failure.
/// All methods return the app's local [Appointment] model, mapped from
/// the backend JSON (see [Appointment.fromApi]).
class AppointmentService {
  AppointmentService._();
  static final AppointmentService instance = AppointmentService._();

  static const _appointments = '/api/v1/appointments';
  static const _availability = '/api/v1/availability';

  String? get _myId => UserSession.instance.userId?.toString();

  /// The backend requires ISO 8601 with a UTC offset
  /// (e.g. `2026-11-14T09:00:00Z`).
  static String _isoWithOffset(DateTime dt) => dt.toUtc().toIso8601String();

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Appointment _map(Map<String, dynamic> json) =>
      Appointment.fromApi(json, currentUserId: _myId);

  List<Appointment> _mapList(String body) {
    final decoded = jsonDecode(body);
    final List items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      // Paginated shape, in case the backend enables pagination later.
      items = decoded['results'] as List;
    } else {
      return const [];
    }
    return items.map((e) => _map(e as Map<String, dynamic>)).toList();
  }

  /// GET /appointments/ — my appointments (as requester or provider),
  /// newest first. Optional [status] filter: pending, accepted, rejected,
  /// cancelled, completed.
  Future<List<Appointment>> listAppointments({String? status}) async {
    final path = status == null || status.isEmpty
        ? '$_appointments/'
        : '$_appointments/?status=${Uri.encodeComponent(status)}';
    final res = await ApiClient.instance.get(path);
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load appointments.'),
        statusCode: res.statusCode,
      );
    }
    return _mapList(res.body);
  }

  /// GET /appointments/{id}/ — one appointment (must be a participant).
  Future<Appointment> getAppointment(int id) async {
    final res = await ApiClient.instance.get('$_appointments/$id/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /appointments/ — book with a provider. The new appointment
  /// starts as `pending` until the provider accepts it.
  /// Throws a 409 [ApiException] when the time conflicts, and a 400
  /// when the time is outside the provider's availability.
  Future<Appointment> createAppointment({
    required String providerId,
    required DateTime startsAt,
    required DateTime endsAt,
    String notes = '',
  }) async {
    final res = await ApiClient.instance.post(
      '$_appointments/',
      body: {
        'provider_id': providerId,
        'starts_at': _isoWithOffset(startsAt),
        'ends_at': _isoWithOffset(endsAt),
        'notes': notes,
      },
    );
    if (res.statusCode != 201) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not book the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /appointments/{id}/accept/ — provider only, pending only.
  Future<Appointment> acceptAppointment(int id) async {
    final res = await ApiClient.instance.post('$_appointments/$id/accept/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not accept the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /appointments/{id}/reject/ — provider only, pending only.
  Future<Appointment> rejectAppointment(int id) async {
    final res = await ApiClient.instance.post('$_appointments/$id/reject/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not decline the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /appointments/{id}/cancel/ — either participant,
  /// pending or accepted only.
  Future<Appointment> cancelAppointment(int id) async {
    final res = await ApiClient.instance.post('$_appointments/$id/cancel/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not cancel the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /appointments/{id}/complete/ — provider only, accepted only.
  Future<Appointment> completeAppointment(int id) async {
    final res = await ApiClient.instance.post('$_appointments/$id/complete/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not mark the appointment complete.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// DELETE /appointments/{id}/ — either participant, not completed.
  Future<void> deleteAppointment(int id) async {
    final res = await ApiClient.instance.delete('$_appointments/$id/');
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not delete the appointment.'),
        statusCode: res.statusCode,
      );
    }
  }

  /// PATCH /appointments/{id}/reschedule/ — requester only,
  /// pending or accepted only. The status does not change.
  Future<Appointment> rescheduleAppointment({
    required int id,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final res = await ApiClient.instance.patch(
      '$_appointments/$id/reschedule/',
      body: {
        'starts_at': _isoWithOffset(startsAt),
        'ends_at': _isoWithOffset(endsAt),
      },
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not reschedule the appointment.'),
        statusCode: res.statusCode,
      );
    }
    return _map(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /availability/me/ — my weekly schedule. Returns an empty rule
  /// list (and null timezone) when nothing has been published yet.
  Future<WeeklySchedule> fetchMyAvailability() async {
    final res = await ApiClient.instance.get('$_availability/me/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load your availability.'),
        statusCode: res.statusCode,
      );
    }
    return WeeklySchedule.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// PUT /availability/me/ — replaces my whole weekly schedule.
  /// [timezone] must be a valid IANA name (e.g. `Asia/Karachi`).
  /// Rules on the same weekday must not overlap.
  Future<WeeklySchedule> setMyAvailability({
    required String timezone,
    required List<AvailabilityRule> rules,
  }) async {
    final res = await ApiClient.instance.put(
      '$_availability/me/',
      body: {
        'timezone': timezone,
        'rules': rules.map((r) => r.toJson()).toList(),
      },
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not save your availability.'),
        statusCode: res.statusCode,
      );
    }
    return WeeklySchedule.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// GET /availability/slots/ — a provider's free slots on one day.
  /// Public endpoint (no login needed). [durationMinutes] must be a
  /// multiple of 15, between 15 and 240. Returns an empty list when
  /// the provider has published no availability.
  Future<List<TimeSlot>> fetchSlots({
    required String providerId,
    required DateTime date,
    int durationMinutes = 30,
  }) async {
    final res = await ApiClient.instance.get(
      '$_availability/slots/?provider_id=${Uri.encodeComponent(providerId)}'
      '&date=${_dateOnly(date)}&duration_minutes=$durationMinutes',
      auth: false,
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load available slots.'),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final slots = data['slots'];
    if (slots is! List) return const [];
    return slots
        .map((s) => TimeSlot.fromJson(s as Map<String, dynamic>))
        .toList();
  }
}
