import 'package:flutter/material.dart';

enum ApptStatus { confirmed, pending, cancelled, completed, rejected }

class Appointment {
  int?       id;
  int?       apptNumber;   // Sequential #1, #2, #3 ... per user
  String     name;
  String     service;
  DateTime   dateTime;
  String     duration;
  String     location;
  String     note;
  /// Reason note added by the provider when cancelling/rescheduling due to emergency.
  String     cancellationNote;
  ApptStatus status;
  int        colorValue;
  /// Backend participant ids (API appointments only; not stored in SQLite).
  String?    requesterId;
  String?    providerId;
  /// When the backend created the appointment (API appointments only).
  DateTime?  createdAt;

  Appointment({
    this.id,
    this.apptNumber,
    required this.name,
    required this.service,
    required this.dateTime,
    this.duration          = '30 min',
    this.location          = '',
    this.note              = '',
    this.cancellationNote  = '',
    this.status            = ApptStatus.pending,
    this.colorValue        = 0xFF4A90D9,
    this.requesterId,
    this.providerId,
    this.createdAt,
  });

  // ── Backend API ───────────────────────────────────────────────────────────
  /// Avatar colours cycled through for API appointments (stable per id).
  static const _apiColors = [
    0xFF4A90D9, 0xFF2ECC96, 0xFF7C3AED, 0xFFF4A24A,
    0xFFE05C5C, 0xFF0D9E6A, 0xFF1A5EA8,
  ];

  static ApptStatus _statusFromApi(String s) {
    switch (s) {
      case 'accepted':  return ApptStatus.confirmed;
      case 'rejected':  return ApptStatus.rejected;
      case 'cancelled': return ApptStatus.cancelled;
      case 'completed': return ApptStatus.completed;
      case 'pending':
      default:          return ApptStatus.pending;
    }
  }

  /// Duration label for [minutes], using the labels the UI already knows
  /// (`15 min`, `1 hr`, …) and falling back to `N min`.
  static String durationLabel(int minutes) {
    switch (minutes) {
      case 15:  return '15 min';
      case 30:  return '30 min';
      case 45:  return '45 min';
      case 60:  return '1 hr';
      case 90:  return '1.5 hr';
      case 120: return '2 hr';
      default:  return '$minutes min';
    }
  }

  /// Maps a backend appointment object to the local model.
  ///
  /// The display name is the other party, picked with [currentUserId]:
  /// the backend's `provider_name` / `requester_name` full name when
  /// present, falling back to `Provider #<id>` / `Requester #<id>`
  /// when the payload has no name. The service is a generic
  /// `Appointment` (the API has no services or locations).
  factory Appointment.fromApi(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final id          = json['id'] as int;
    final requesterId = json['requester_id']?.toString() ?? '';
    final providerId  = json['provider_id']?.toString() ?? '';
    final providerName  = (json['provider_name']  as String?)?.trim() ?? '';
    final requesterName = (json['requester_name'] as String?)?.trim() ?? '';
    final startsAt    = DateTime.parse(json['starts_at'] as String).toLocal();
    final endsAt      = DateTime.parse(json['ends_at'] as String).toLocal();
    final createdRaw  = json['created_at'] as String?;
    final isRequester =
        currentUserId != null && requesterId == currentUserId;
    return Appointment(
      id: id,
      apptNumber: id,
      name: isRequester
          ? (providerName.isNotEmpty ? providerName : 'Provider #$providerId')
          : (requesterName.isNotEmpty ? requesterName : 'Requester #$requesterId'),
      service: 'Appointment',
      dateTime: startsAt,
      duration: durationLabel(endsAt.difference(startsAt).inMinutes),
      location: '',
      note: (json['notes'] as String?) ?? '',
      status: _statusFromApi((json['status'] as String?) ?? 'pending'),
      colorValue: _apiColors[id % _apiColors.length],
      requesterId: requesterId,
      providerId: providerId,
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
    );
  }

  // ── Convenience getters ───────────────────────────────────────────────────
  Color get avatarColor => Color(colorValue);

  String get initials => name.trim().split(' ')
      .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

  /// "9:00" format — backward-compatible with dashboard _apptTile which does
  /// a.time.split(':') expecting ["9", "00"]
  String get time {
    final h  = dateTime.hour;
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Full display time: "9:00 AM"
  String get displayTime {
    final h  = dateTime.hour;
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm ${h < 12 ? "AM" : "PM"}';
  }

  /// "Today", "Tomorrow", "Yesterday", or "Apr 29"
  String get displayDate {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diff  = d.difference(today).inDays;
    if (diff ==  0) return 'Today';
    if (diff ==  1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dateTime.month - 1]} ${dateTime.day}';
  }

  bool get isToday {
    final n = DateTime.now();
    return dateTime.year == n.year && dateTime.month == n.month && dateTime.day == n.day;
  }
  bool get isFuture {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return DateTime(dateTime.year, dateTime.month, dateTime.day).isAfter(today);
  }
  bool get isPast {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return DateTime(dateTime.year, dateTime.month, dateTime.day).isBefore(today);
  }
  // True when the appointment's end time (start + duration) has passed
  bool get isExpired {
    final endTime = dateTime.add(Duration(minutes: _durationMins(duration)));
    return DateTime.now().isAfter(endTime);
  }

  static int _durationMins(String d) {
    if (d == '15 min') return 15;
    if (d == '30 min') return 30;
    if (d == '45 min') return 45;
    if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90;
    if (d == '2 hr')   return 120;
    final m = RegExp(r'^(\d+)\s*min$').firstMatch(d.trim());
    if (m != null) return int.parse(m.group(1)!);
    return 30;
  }

  // ── SQLite ────────────────────────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'name': name, 'service': service,
      'date_time': dateTime.toIso8601String(),
      'duration': duration, 'location': location, 'note': note,
      'cancellation_note': cancellationNote,
      'status': status.name, 'color_value': colorValue,
    };
    if (id != null)         m['id']          = id;
    if (apptNumber != null) m['appt_number'] = apptNumber;
    return m;
  }

  factory Appointment.fromMap(Map<String, dynamic> m) => Appointment(
    id        : m['id']                as int?,
    apptNumber: m['appt_number']       as int?,
    name      : m['name']              as String,
    service   : m['service']           as String,
    dateTime  : DateTime.parse(m['date_time'] as String),
    duration  : (m['duration']         as String?) ?? '30 min',
    location  : (m['location']         as String?) ?? '',
    note      : (m['note']             as String?) ?? '',
    cancellationNote: (m['cancellation_note'] as String?) ?? '',
    colorValue: (m['color_value']      as int?)    ?? 0xFF4A90D9,
    status    : ApptStatus.values.firstWhere(
      (s) => s.name == (m['status'] as String? ?? 'pending'),
      orElse: () => ApptStatus.pending,
    ),
  );

  Appointment copyWith({
    int? id, int? apptNumber, String? name, String? service, DateTime? dateTime,
    String? duration, String? location, String? note, String? cancellationNote,
    ApptStatus? status, int? colorValue,
    String? requesterId, String? providerId, DateTime? createdAt,
  }) => Appointment(
    id: id ?? this.id, apptNumber: apptNumber ?? this.apptNumber,
    name: name ?? this.name,
    service: service ?? this.service, dateTime: dateTime ?? this.dateTime,
    duration: duration ?? this.duration, location: location ?? this.location,
    note: note ?? this.note,
    cancellationNote: cancellationNote ?? this.cancellationNote,
    status: status ?? this.status,
    colorValue: colorValue ?? this.colorValue,
    requesterId: requesterId ?? this.requesterId,
    providerId: providerId ?? this.providerId,
    createdAt: createdAt ?? this.createdAt,
  );
}
