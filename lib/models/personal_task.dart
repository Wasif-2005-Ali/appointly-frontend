import 'package:flutter/material.dart';

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
  bool              hasReminder;
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
    this.hasReminder       = false,
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
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLOBAL TASK STORE  (in-memory, session-scoped)
//  Shared between PersonalTasksScreen and NewAppointment's CalendarPickerDialog
// ─────────────────────────────────────────────────────────────────────────────

class PersonalTaskStore {
  PersonalTaskStore._();
  static final PersonalTaskStore instance = PersonalTaskStore._();

  final List<PersonalTask> _tasks = _defaultTasks();

  List<PersonalTask> get tasks => List.unmodifiable(_tasks);

  void add(PersonalTask t)    => _tasks.insert(0, t);
  void remove(String id)      => _tasks.removeWhere((t) => t.id == id);
  void toggle(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) _tasks[idx].done = !_tasks[idx].done;
  }

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

// ── Rich sample data ──────────────────────────────────────────────────────────

List<PersonalTask> _defaultTasks() {
  final now = DateTime.now();
  final today    = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final nextWeek = today.add(const Duration(days: 5));
  final later    = today.add(const Duration(days: 10));

  return [
    PersonalTask(
      id: 't1', title: 'Submit tax documents',
      description: 'Upload the Q1 financial reports to the portal before deadline.',
      priority: TaskPriority.urgent, category: TaskCategory.finance,
      dueDate: today, hasTime: false,
      tags: ['deadline', 'finance'],
      subtasks: [
        SubTask(title: 'Gather receipts', done: true),
        SubTask(title: 'Fill Form-A', done: true),
        SubTask(title: 'Upload to portal', done: false),
      ],
    ),
    PersonalTask(
      id: 't2', title: 'Call insurance company',
      description: 'Follow up on the pending health policy renewal.',
      priority: TaskPriority.high, category: TaskCategory.finance,
      dueDate: today, startTime: const TimeOfDay(hour: 14, minute: 0),
      duration: '30 min', hasTime: true, hasReminder: true,
      tags: ['insurance', 'urgent'],
    ),
    PersonalTask(
      id: 't3', title: 'Reply to Mahnoor\'s inquiry',
      priority: TaskPriority.high, category: TaskCategory.work,
      dueDate: today, startTime: const TimeOfDay(hour: 16, minute: 30),
      duration: '15 min', hasTime: true,
      tags: ['client', 'email'],
    ),
    PersonalTask(
      id: 't4', title: 'Buy clinic supplies',
      description: 'Order gauze, gloves (L), sanitizer, and cotton rolls.',
      priority: TaskPriority.medium, category: TaskCategory.shopping,
      dueDate: tomorrow,
      subtasks: [
        SubTask(title: 'Gauze rolls × 4'),
        SubTask(title: 'Latex gloves (L)'),
        SubTask(title: 'Hand sanitizer × 2'),
      ],
      tags: ['supplies'],
    ),
    PersonalTask(
      id: 't5', title: 'Review client feedback form',
      priority: TaskPriority.medium, category: TaskCategory.work,
      dueDate: tomorrow, startTime: const TimeOfDay(hour: 11, minute: 0),
      duration: '45 min', hasTime: true, repeat: TaskRepeat.weekly,
      tags: ['review'],
    ),
    PersonalTask(
      id: 't6', title: 'Morning jog — 5 km',
      priority: TaskPriority.medium, category: TaskCategory.health,
      dueDate: tomorrow, startTime: const TimeOfDay(hour: 7, minute: 0),
      duration: '45 min', hasTime: true, repeat: TaskRepeat.daily,
      hasReminder: true,
    ),
    PersonalTask(
      id: 't7', title: 'Update service pricing page',
      priority: TaskPriority.medium, category: TaskCategory.work,
      dueDate: nextWeek, tags: ['website'],
    ),
    PersonalTask(
      id: 't8', title: 'Research new physiotherapy techniques',
      priority: TaskPriority.low, category: TaskCategory.health,
      dueDate: nextWeek, tags: ['learning'],
    ),
    PersonalTask(
      id: 't9', title: 'Order business card reprint',
      priority: TaskPriority.low, category: TaskCategory.work,
      dueDate: later,
    ),
    PersonalTask(
      id: 't10', title: 'Organize client database',
      priority: TaskPriority.low, category: TaskCategory.work,
      done: true, dueDate: today.subtract(const Duration(days: 1)),
    ),
    PersonalTask(
      id: 't11', title: 'Set up appointment reminder automation',
      priority: TaskPriority.medium, category: TaskCategory.work,
      done: true, dueDate: today.subtract(const Duration(days: 2)),
      subtasks: [SubTask(title: 'Configure templates', done: true), SubTask(title: 'Test with dummy client', done: true)],
    ),
  ];
}
