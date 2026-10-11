import 'package:flutter/material.dart';

enum ApptStatus { confirmed, pending, cancelled, completed }

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
  });

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
  }) => Appointment(
    id: id ?? this.id, apptNumber: apptNumber ?? this.apptNumber,
    name: name ?? this.name,
    service: service ?? this.service, dateTime: dateTime ?? this.dateTime,
    duration: duration ?? this.duration, location: location ?? this.location,
    note: note ?? this.note,
    cancellationNote: cancellationNote ?? this.cancellationNote,
    status: status ?? this.status,
    colorValue: colorValue ?? this.colorValue,
  );
}
