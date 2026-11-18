import 'package:flutter/material.dart';

import '../database/bd_helper.dart';
import '../user_session.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum TaskPriority { urgent, high, medium, low }
enum TaskCategory { work, health, personal, shopping, finance, other }
enum TaskRepeat   { none, daily, weekly, monthly }

extension TaskPriorityX on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.urgent: return 'Urgent';
      case TaskPriority.high:   return 'High';
      case TaskPriority.medium: return 'Medium';
      case TaskPriority.low:    return 'Low';
    }
  }
  Color get color {
    switch (this) {
      case TaskPriority.urgent: return const Color(0xFFE05C5C);
      case TaskPriority.high:   return const Color(0xFFF4A24A);
      case TaskPriority.medium: return const Color(0xFF4A90D9);
      case TaskPriority.low:    return const Color(0xFF2ECC96);
    }
  }
  IconData get icon {
    switch (this) {
      case TaskPriority.urgent: return Icons.bolt_rounded;
      case TaskPriority.high:   return Icons.keyboard_arrow_up_rounded;
      case TaskPriority.medium: return Icons.remove_rounded;
      case TaskPriority.low:    return Icons.keyboard_arrow_down_rounded;
    }
  }
}

extension TaskCategoryX on TaskCategory {
  String get label {
    switch (this) {
      case TaskCategory.work:     return 'Work';
      case TaskCategory.health:   return 'Health';
      case TaskCategory.personal: return 'Personal';
      case TaskCategory.shopping: return 'Shopping';
      case TaskCategory.finance:  return 'Finance';
      case TaskCategory.other:    return 'Other';
    }
  }
  Color get color {
    switch (this) {
      case TaskCategory.work:     return const Color(0xFF4A90D9);
      case TaskCategory.health:   return const Color(0xFF2ECC96);
      case TaskCategory.personal: return const Color(0xFFA78BFA);
      case TaskCategory.shopping: return const Color(0xFFF4A24A);
      case TaskCategory.finance:  return const Color(0xFF06B6D4);
      case TaskCategory.other:    return const Color(0xFF94A3B8);
    }
  }
  IconData get icon {
    switch (this) {
      case TaskCategory.work:     return Icons.work_outline_rounded;
      case TaskCategory.health:   return Icons.favorite_border_rounded;
      case TaskCategory.personal: return Icons.person_outline_rounded;
      case TaskCategory.shopping: return Icons.shopping_bag_outlined;
      case TaskCategory.finance:  return Icons.account_balance_wallet_outlined;
      case TaskCategory.other:    return Icons.category_outlined;
    }
  }
}

extension TaskRepeatX on TaskRepeat {
  String get label {
    switch (this) {
      case TaskRepeat.none:    return 'No Repeat';
      case TaskRepeat.daily:   return 'Daily';
      case TaskRepeat.weekly:  return 'Weekly';
      case TaskRepeat.monthly: return 'Monthly';
    }
  }
  IconData get icon {
    switch (this) {
      case TaskRepeat.none:    return Icons.remove_circle_outline_rounded;
      case TaskRepeat.daily:   return Icons.replay_rounded;
      case TaskRepeat.weekly:  return Icons.date_range_rounded;
      case TaskRepeat.monthly: return Icons.calendar_month_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUB-TASK
// ─────────────────────────────────────────────────────────────────────────────

class SubTask {
  String title;
  bool   done;
  SubTask({required this.title, this.done = false});

  Map<String, dynamic> toJson() => {'title': title, 'done': done};

  factory SubTask.fromJson(Map<String, dynamic> j) => SubTask(
        title: j['title'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  PERSONAL TASK
// ─────────────────────────────────────────────────────────────────────────────

class PersonalTask {
  final String      id;
  String            title;
  String            description;
  TaskPriority      priority;
  TaskCategory      category;
  DateTime?         dueDate;
  TimeOfDay?        startTime;
  String            duration;
  bool              hasTime;
  bool              done;
  TaskRepeat        repeat;
  List<SubTask>     subtasks;
  List<String>      tags;
  DateTime          createdAt;
  /// When true, this task's time slot is marked as unavailable for new appointments.
  bool              blockAppointments;

  PersonalTask({
    required this.id,
    required this.title,
    this.description       = '',
    this.priority          = TaskPriority.medium,
    this.category          = TaskCategory.personal,
    this.dueDate,
    this.startTime,
    this.duration          = '30 min',
    this.hasTime           = false,
    this.done              = false,
    this.repeat            = TaskRepeat.none,
    this.blockAppointments = true,
    List<SubTask>? subtasks,
    List<String>?  tags,
    DateTime?      createdAt,
  })  : subtasks  = subtasks  ?? [],
        tags      = tags      ?? [],
        createdAt = createdAt ?? DateTime.now();

  int get completedSubtasks => subtasks.where((s) => s.done).length;
  double get subtaskProgress => subtasks.isEmpty ? 0 : completedSubtasks / subtasks.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority.name,
        'category': category.name,
        'dueDate': dueDate?.toIso8601String(),
        'startHour': startTime?.hour,
        'startMinute': startTime?.minute,
        'duration': duration,
        'hasTime': hasTime,
        'done': done,
        'repeat': repeat.name,
        'blockAppointments': blockAppointments,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PersonalTask.fromJson(Map<String, dynamic> j) {
    T parseEnum<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    final sh = j['startHour'] as int?;
    final sm = j['startMinute'] as int?;
    return PersonalTask(
      id: j['id'] as String? ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      priority: parseEnum(TaskPriority.values, j['priority'] as String?,
          TaskPriority.medium),
      category: parseEnum(TaskCategory.values, j['category'] as String?,
          TaskCategory.personal),
      dueDate: j['dueDate'] == null
          ? null
          : DateTime.tryParse(j['dueDate'] as String),
      startTime: (sh == null || sm == null)
          ? null
          : TimeOfDay(hour: sh, minute: sm),
      duration: j['duration'] as String? ?? '30 min',
      hasTime: j['hasTime'] as bool? ?? false,
      done: j['done'] as bool? ?? false,
      repeat:
          parseEnum(TaskRepeat.values, j['repeat'] as String?, TaskRepeat.none),
      blockAppointments: j['blockAppointments'] as bool? ?? true,
      subtasks: (j['subtasks'] as List? ?? [])
          .map((e) => SubTask.fromJson(e as Map<String, dynamic>))
          .toList(),
      tags: (j['tags'] as List? ?? []).map((e) => e.toString()).toList(),
      createdAt: j['createdAt'] == null
          ? null
          : DateTime.tryParse(j['createdAt'] as String),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLOBAL TASK STORE  (persisted to SQLite, per user)
//  Shared between PersonalTasksScreen and NewAppointment's CalendarPickerDialog.
//  Starts EMPTY — the old build shipped 11 hardcoded sample tasks as the
//  user's own and lost real tasks on every restart.
// ─────────────────────────────────────────────────────────────────────────────

class PersonalTaskStore {
  PersonalTaskStore._();
  static final PersonalTaskStore instance = PersonalTaskStore._();

  final List<PersonalTask> _tasks = [];
  bool _loaded = false;
  bool get loaded => _loaded;

  List<PersonalTask> get tasks => List.unmodifiable(_tasks);

  /// Loads the user's persisted tasks once. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    final uid = UserSession.instance.userId;
    if (uid != null) {
      final rows = await DBHelper.instance.getPersonalTasks(uid);
      _tasks
        ..clear()
        ..addAll(rows.map(PersonalTask.fromJson));
      // Newest first, matching the add() order.
      _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final uid = UserSession.instance.userId;
    if (uid == null) return;
    await DBHelper.instance.savePersonalTasks(
        uid, _tasks.map((t) => t.toJson()).toList());
  }

  void add(PersonalTask t) {
    _tasks.insert(0, t);
    _persist();
  }

  void remove(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _persist();
  }

  void toggle(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _tasks[idx].done = !_tasks[idx].done;
      _persist();
    }
  }

  /// Persists after an in-place edit (e.g. a subtask checkbox toggle).
  void save() => _persist();

  /// Returns overlapping task for a given [start, end) window on [date].
  PersonalTask? conflictFor(DateTime start, DateTime end) {
    for (final t in _tasks) {
      if (!t.hasTime || t.dueDate == null || t.startTime == null || t.done) continue;
      final ts = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day,
          t.startTime!.hour, t.startTime!.minute);
      final te = ts.add(Duration(minutes: _durMins(t.duration)));
      if (start.isBefore(te) && end.isAfter(ts)) return t;
    }
    return null;
  }

  /// All timed tasks on [date] as [start, end] pairs (for UI blocking).
  /// Only tasks with [blockAppointments] == true are returned.
  List<TaskTimeBlock> blockedRangesOn(DateTime date) {
    final result = <TaskTimeBlock>[];
    for (final t in _tasks) {
      if (!t.hasTime || t.dueDate == null || t.startTime == null || t.done) continue;
      if (!t.blockAppointments) continue; // task allows appointments at this time
      final d = t.dueDate!;
      if (d.year != date.year || d.month != date.month || d.day != date.day) continue;
      final ts = DateTime(d.year, d.month, d.day, t.startTime!.hour, t.startTime!.minute);
      final te = ts.add(Duration(minutes: _durMins(t.duration)));
      result.add(TaskTimeBlock(start: ts, end: te, label: t.title, isTask: true));
    }
    return result;
  }

  static int _durMins(String d) {
    if (d == '15 min') return 15;
    if (d == '30 min') return 30;
    if (d == '45 min') return 45;
    if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90;
    if (d == '2 hr')   return 120;
    return 30;
  }
}

class TaskTimeBlock {
  final DateTime start;
  final DateTime end;
  final String   label;
  final bool     isTask;
  const TaskTimeBlock({required this.start, required this.end, required this.label, required this.isTask});
}
