import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../models/appointment.dart' as appt_model;
import '../models/personal_task.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PERSONAL TASKS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class PersonalTasksScreen extends StatefulWidget {
  const PersonalTasksScreen({super.key});
  @override
  State<PersonalTasksScreen> createState() => _PersonalTasksState();
}

class _PersonalTasksState extends State<PersonalTasksScreen>
    with DarkMode, TickerProviderStateMixin {

  final _store       = PersonalTaskStore.instance;
  String  _filter    = 'All';   // All | Today | Upcoming | Done
  TaskCategory? _catFilter;
  String  _searchQ   = '';
  final _searchCtrl  = TextEditingController();
  bool    _searching = false;

  late final _fabCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 600))..repeat(reverse: true);

  @override
  void dispose() { _fabCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }

  // ── Derived data ────────────────────────────────────────────────────────────

  List<PersonalTask> get _all => _store.tasks.toList();

  List<PersonalTask> get _filtered {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _all.where((t) {
      // search
      if (_searchQ.isNotEmpty &&
          !t.title.toLowerCase().contains(_searchQ.toLowerCase()) &&
          !t.description.toLowerCase().contains(_searchQ.toLowerCase()) &&
          !t.tags.any((g) => g.toLowerCase().contains(_searchQ.toLowerCase()))) {
        return false;
      }
      // category filter
      if (_catFilter != null && t.category != _catFilter) return false;
      // tab filter
      switch (_filter) {
        case 'Today':
          return !t.done && t.dueDate != null &&
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) == today;
        case 'Upcoming':
          return !t.done && (t.dueDate == null ||
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day).isAfter(today));
        case 'Done':
          return t.done;
        default:
          return true;
      }
    }).toList();
  }

  int get _todayCount   => _all.where((t) {
    if (t.done || t.dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) == today;
  }).length;

  int get _overdueCount => _all.where((t) {
    if (t.done || t.dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day).isBefore(today);
  }).length;

  int get _doneCount    => _all.where((t) => t.done).length;
  int get _totalCount   => _all.length;

  double get _progress => _totalCount == 0 ? 0 : _doneCount / _totalCount;

  // ── Group tasks for list display ────────────────────────────────────────────

  Map<String, List<PersonalTask>> get _grouped {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tmr   = today.add(const Duration(days: 1));
    final week  = today.add(const Duration(days: 7));

    final Map<String, List<PersonalTask>> g = {};
    for (final t in _filtered) {
      String key;
      if (t.done) {
        key = 'Completed';
      } else if (t.dueDate == null) {
        key = 'No Due Date';
      } else {
        final d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today))   key = '⚠️  Overdue';
        else if (d == today)     key = 'Today';
        else if (d == tmr)       key = 'Tomorrow';
        else if (d.isBefore(week)) key = 'This Week';
        else                     key = 'Later';
      }
      g.putIfAbsent(key, () => []).add(t);
    }
    // Sort by priority within each group
    for (final list in g.values) {
      list.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    }
    return g;
  }

  static const _groupOrder = [
    '⚠️  Overdue', 'Today', 'Tomorrow', 'This Week', 'Later', 'No Due Date', 'Completed'
  ];

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _toggle(String id) {
    HapticFeedback.lightImpact();
    setState(() => _store.toggle(id));
  }

  void _delete(String id) {
    HapticFeedback.mediumImpact();
    setState(() => _store.remove(id));
  }

  void _showAddSheet([PersonalTask? editing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTaskSheet(
        editing: editing,
        appointments: AppStateProvider.of(context).appointments,
        dmColors: _DmColors(bg: dmBg, card: dmCard, card2: dmCard2,
            border: dmBorder, txtMain: dmTxtMain, txtSub: dmTxtSub,
            accent: dmAccent, btnGradient: dmBtnGradient, heroGradient: dmHeroGradient,
            dark: dark),
        onSave: (task) {
          setState(() {
            if (editing != null) {
              final idx = _store.tasks.indexWhere((t) => t.id == editing.id);
              if (idx != -1) {
                // replace in store — we have to remove+insert since store is unmodifiable
                _store.remove(editing.id);
                _store.add(task);
              }
            } else {
              _store.add(task);
            }
          });
        },
      ),
    );
  }

  void _showDetail(PersonalTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskDetailSheet(
        task: task,
        appointments: AppStateProvider.of(context).appointments,
        dmColors: _DmColors(bg: dmBg, card: dmCard, card2: dmCard2,
            border: dmBorder, txtMain: dmTxtMain, txtSub: dmTxtSub,
            accent: dmAccent, btnGradient: dmBtnGradient, heroGradient: dmHeroGradient,
            dark: dark),
        onToggle: () => _toggle(task.id),
        onDelete: () { Navigator.pop(context); _delete(task.id); },
        onEdit:   () { Navigator.pop(context); _showAddSheet(task); },
        onSubtaskToggle: (idx) {
          setState(() => task.subtasks[idx].done = !task.subtasks[idx].done);
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _buildHeader(),
        _buildTabBar(),
        _buildSearchAndCategory(),
        Expanded(child: _buildTaskList()),
      ]),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── Hero Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: dmHeroGradient,
      )),
      child: Stack(children: [
        // Decorative circles
        Positioned(right: -60, top: -60, child: Container(width: 220, height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(
                colors: [const Color(0xFFA78BFA).withOpacity(0.18), Colors.transparent])))),
        Positioned(left: -40, bottom: -30, child: Container(width: 160, height: 160,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(
                colors: [dmAccent.withOpacity(0.12), Colors.transparent])))),
        SafeArea(bottom: false, child: Column(children: [
          // Top row
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white.withOpacity(0.22))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Personal Tasks', style: GoogleFonts.dmSans(fontSize: 22,
                  fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.6)),
              Text('Your personal todo board', style: GoogleFonts.dmSans(
                  fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
            ])),
            // Search toggle
            GestureDetector(
              onTap: () => setState(() { _searching = !_searching; if (!_searching) { _searchQ = ''; _searchCtrl.clear(); } }),
              child: Container(width: 42, height: 42,
                  decoration: BoxDecoration(
                      color: _searching ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white.withOpacity(0.22))),
                  child: Icon(_searching ? Icons.close_rounded : Icons.search_rounded,
                      color: Colors.white, size: 20)),
            ),
          ])),
          const SizedBox(height: 20),
          // Stats row with ring
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), child: Row(children: [
            // Animated progress ring
            SizedBox(width: 72, height: 72, child: CustomPaint(
              painter: _RingPainter(_progress, dmAccent),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(_progress * 100).round()}%', style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
                Text('done', style: GoogleFonts.dmSans(
                    fontSize: 8.5, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
              ])),
            )),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [
              Row(children: [
                _statChip('$_totalCount', 'Total', Colors.white.withOpacity(0.15)),
                const SizedBox(width: 8),
                _statChip('$_todayCount', 'Today', dmAccent.withOpacity(0.3)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _statChip('$_overdueCount', 'Overdue', const Color(0xFFE05C5C).withOpacity(_overdueCount > 0 ? 0.35 : 0.15)),
                const SizedBox(width: 8),
                _statChip('$_doneCount', 'Done', const Color(0xFF2ECC96).withOpacity(0.3)),
              ]),
            ])),
          ])),
        ])),
      ]),
    );
  }

  Widget _statChip(String v, String l, Color bg) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12))),
    child: Row(children: [
      Text(v, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
      const SizedBox(width: 5),
      Text(l, style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600)),
    ]),
  ));

  // ── Tab Bar ──────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    const tabs = ['All', 'Today', 'Upcoming', 'Done'];
    return Container(
      color: dmCard,
      child: Row(children: tabs.map((t) {
        final sel = _filter == t;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _filter = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: sel ? dmAccent : Colors.transparent, width: 2.5)),
            ),
            child: Text(t, textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                    color: sel ? dmAccent : dmTxtSub)),
          ),
        ));
      }).toList()),
    );
  }

  // ── Search + Category Chips ──────────────────────────────────────────────────

  Widget _buildSearchAndCategory() {
    return Column(children: [
      if (_searching)
        Container(
          color: dmCard,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dmBorder)),
            child: Row(children: [
              Icon(Icons.search_rounded, color: dmTxtSub, size: 18),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _searchCtrl, autofocus: true,
                onChanged: (v) => setState(() => _searchQ = v),
                style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain),
                decoration: InputDecoration(border: InputBorder.none,
                    hintText: 'Search tasks, tags…',
                    hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)),
              )),
              if (_searchQ.isNotEmpty) GestureDetector(
                onTap: () => setState(() { _searchQ = ''; _searchCtrl.clear(); }),
                child: Icon(Icons.close_rounded, color: dmTxtSub, size: 18),
              ),
            ]),
          ),
        ),
      // Category scroll
      SizedBox(height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          children: [
            _catChip(null, 'All', Icons.apps_rounded),
            ...TaskCategory.values.map((c) => _catChip(c, c.label, c.icon)),
          ],
        ),
      ),
    ]);
  }

  Widget _catChip(TaskCategory? cat, String label, IconData icon) {
    final sel = _catFilter == cat;
    final color = cat?.color ?? dmAccent;
    return GestureDetector(
      onTap: () => setState(() => _catFilter = cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: sel ? LinearGradient(colors: [color, color.withOpacity(0.7)]) : null,
          color: sel ? null : dmCard2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : dmBorder, width: sel ? 1.5 : 1),
          boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: sel ? Colors.white : color),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.dmSans(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: sel ? Colors.white : dmTxtSub)),
        ]),
      ),
    );
  }

  // ── Task List ────────────────────────────────────────────────────────────────

  Widget _buildTaskList() {
    final grouped = _grouped;
    if (grouped.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline_rounded, size: 64, color: dmTxtSub.withOpacity(0.3)),
        const SizedBox(height: 14),
        Text('All clear!', style: GoogleFonts.dmSans(
            fontSize: 20, fontWeight: FontWeight.w800, color: dmTxtSub.withOpacity(0.4))),
        const SizedBox(height: 6),
        Text('No tasks match this filter.', style: GoogleFonts.dmSans(
            fontSize: 13.5, color: dmTxtSub.withOpacity(0.35))),
      ]));
    }

    final orderedKeys = _groupOrder.where((k) => grouped.containsKey(k)).toList();

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        for (final key in orderedKeys) ...[
          _buildGroupHeader(key, grouped[key]!),
          const SizedBox(height: 8),
          ...grouped[key]!.map((t) => _buildTaskCard(t)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String label, List<PersonalTask> tasks) {
    Color color = dmTxtSub;
    if (label == '⚠️  Overdue') color = const Color(0xFFE05C5C);
    if (label == 'Today')       color = dmAccent;
    if (label == 'Completed')   color = const Color(0xFF2ECC96);

    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 5)])),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.dmSans(
          fontSize: 12.5, fontWeight: FontWeight.w800, color: dmTxtSub, letterSpacing: 0.3)),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
          child: Text('${tasks.length}', style: GoogleFonts.dmSans(
              fontSize: 11, fontWeight: FontWeight.w800, color: color))),
    ]);
  }

  Widget _buildTaskCard(PersonalTask task) {
    final isDone = task.done;
    final pc     = task.priority.color;
    final cc     = task.category.color;
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final isOverdue = !isDone && task.dueDate != null &&
        DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day).isBefore(today);

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: const Color(0xFFE05C5C).withOpacity(0.9),
            borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => setState(() => _store.remove(task.id)),
      child: GestureDetector(
        onTap: () => _showDetail(task),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDone ? dmCard2.withOpacity(0.6) : dmCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: isOverdue ? const Color(0xFFE05C5C).withOpacity(0.4) : dmBorder,
                width: isOverdue ? 1.5 : 1.2),
            boxShadow: isDone ? [] : [BoxShadow(
                color: dmAccent.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            // Priority stripe
            Container(width: 4, height: 72,
                decoration: BoxDecoration(
                    color: isDone ? dmBorder : pc,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18), bottomLeft: Radius.circular(18)))),
            const SizedBox(width: 12),
            // Checkbox
            GestureDetector(
              onTap: () => _toggle(task.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 28, height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: isDone ? const LinearGradient(
                        colors: [Color(0xFF2ECC96), Color(0xFF0D9E6A)]) : null,
                    color: isDone ? null : Colors.transparent,
                    border: Border.all(color: isDone ? AppColors.green : dmBorder, width: 2),
                    boxShadow: isDone ? [BoxShadow(
                        color: AppColors.green.withOpacity(0.35), blurRadius: 8)] : []),
                child: isDone
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title + category icon
                Row(children: [
                  Expanded(child: Text(task.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 14.5, fontWeight: FontWeight.w700,
                          color: isDone ? dmTxtSub : dmTxtMain,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          decorationColor: dmTxtSub))),
                  const SizedBox(width: 8),
                  // Appointment-conflict badge
                  if (!isDone && task.hasTime && task.dueDate != null && task.startTime != null)
                    Builder(builder: (_) {
                      final start = DateTime(task.dueDate!.year, task.dueDate!.month,
                          task.dueDate!.day, task.startTime!.hour, task.startTime!.minute);
                      final end   = start.add(Duration(minutes: _AddTaskSheetState._durMins(task.duration)));
                      final hasApptConflict = AppStateProvider.of(context).appointments.any((a) {
                        if (a.status == appt_model.ApptStatus.cancelled) return false;
                        final ae = a.dateTime.add(Duration(minutes: _AddTaskSheetState._durMinsAppt(a.duration)));
                        return start.isBefore(ae) && end.isAfter(a.dateTime);
                      });
                      if (!hasApptConflict) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4A24A).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF4A24A).withOpacity(0.50)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.event_busy_rounded, size: 10, color: Color(0xFFF4A24A)),
                          const SizedBox(width: 3),
                          Text('Appt', style: GoogleFonts.dmSans(
                              fontSize: 9.5, fontWeight: FontWeight.w800,
                              color: const Color(0xFFF4A24A))),
                        ]),
                      );
                    }),
                  Container(width: 26, height: 26,
                      decoration: BoxDecoration(color: cc.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(task.category.icon, size: 14, color: cc)),
                ]),
                const SizedBox(height: 5),
                // Meta row
                Row(children: [
                  if (task.hasTime && task.startTime != null) ...[
                    Icon(Icons.schedule_rounded, size: 12, color: dmAccent.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text(_fmtTime(task.startTime!), style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: dmAccent.withOpacity(0.9))),
                    const SizedBox(width: 8),
                  ] else if (task.dueDate != null) ...[
                    Icon(Icons.event_rounded, size: 12,
                        color: isOverdue ? const Color(0xFFE05C5C) : dmTxtSub),
                    const SizedBox(width: 3),
                    Text(_fmtDate(task.dueDate!), style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: isOverdue ? const Color(0xFFE05C5C) : dmTxtSub)),
                    const SizedBox(width: 8),
                  ],
                  if (task.subtasks.isNotEmpty) ...[
                    Icon(Icons.checklist_rounded, size: 12, color: dmTxtSub),
                    const SizedBox(width: 3),
                    Text('${task.completedSubtasks}/${task.subtasks.length}',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w600, color: dmTxtSub)),
                    const SizedBox(width: 8),
                  ],
                  if (task.hasReminder)
                    Icon(Icons.notifications_active_rounded, size: 12,
                        color: AppColors.warning.withOpacity(0.7)),
                  if (task.repeat != TaskRepeat.none) ...[
                    if (task.hasReminder) const SizedBox(width: 4),
                    Icon(Icons.repeat_rounded, size: 12, color: dmTxtSub.withOpacity(0.7)),
                  ],
                ]),
                // Subtask progress bar
                if (task.subtasks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ClipRRect(borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: task.subtaskProgress,
                        backgroundColor: dmBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            isDone ? const Color(0xFF2ECC96) : dmAccent),
                        minHeight: 3,
                      )),
                ],
                // Tags
                if (task.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, children: task.tags.take(3).map((tag) =>
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: dmAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('#$tag', style: GoogleFonts.dmSans(
                              fontSize: 10, color: dmAccent.withOpacity(0.8),
                              fontWeight: FontWeight.w600)))).toList()),
                ],
              ]),
            )),
            const SizedBox(width: 12),
            // Priority badge + chevron
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: pc.withOpacity(dark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: pc.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(task.priority.icon, size: 11, color: pc),
                    const SizedBox(width: 3),
                    Text(task.priority.label, style: GoogleFonts.dmSans(
                        fontSize: 9.5, fontWeight: FontWeight.w800, color: pc)),
                  ])),
              const SizedBox(height: 6),
              Icon(Icons.chevron_right_rounded, size: 16, color: dmTxtSub.withOpacity(0.4)),
            ]),
            const SizedBox(width: 12),
          ]),
        ),
      ),
    );
  }

  // ── FAB ──────────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    return AnimatedBuilder(
      animation: _fabCtrl,
      builder: (_, child) {
        final pulse = 1.0 + _fabCtrl.value * 0.04;
        return Transform.scale(scale: pulse, child: child);
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: dmBtnGradient,
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: FloatingActionButton.extended(
          backgroundColor: Colors.transparent, elevation: 0,
          onPressed: () => _showAddSheet(),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text('New Task', style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _fmtTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  String _fmtDate(DateTime d) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd    = DateTime(d.year, d.month, d.day);
    if (dd == today) return 'Today';
    if (dd == today.add(const Duration(days: 1))) return 'Tomorrow';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ADD / EDIT TASK SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AddTaskSheet extends StatefulWidget {
  final PersonalTask?                    editing;
  final List<appt_model.Appointment>     appointments;
  final _DmColors                        dmColors;
  final void Function(PersonalTask task) onSave;
  const _AddTaskSheet({this.editing, required this.appointments,
      required this.dmColors, required this.onSave});
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _tagCtrl;
  late TaskPriority  _priority;
  late TaskCategory  _category;
  late DateTime?     _dueDate;
  late TimeOfDay?    _startTime;
  late String        _duration;
  late bool          _hasTime;
  late bool          _hasReminder;
  late TaskRepeat    _repeat;
  late List<SubTask> _subtasks;
  late List<String>  _tags;
  late bool          _blockAppointments;

  final _subtaskCtrl = TextEditingController();

  _ConflictInfo? _conflict;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _titleCtrl   = TextEditingController(text: e?.title ?? '');
    _descCtrl    = TextEditingController(text: e?.description ?? '');
    _tagCtrl     = TextEditingController();
    _priority    = e?.priority    ?? TaskPriority.medium;
    _category    = e?.category    ?? TaskCategory.personal;
    _dueDate     = e?.dueDate;
    _startTime   = e?.startTime;
    _duration    = e?.duration    ?? '30 min';
    _hasTime     = e?.hasTime     ?? false;
    _hasReminder = e?.hasReminder ?? false;
    _repeat      = e?.repeat      ?? TaskRepeat.none;
    _subtasks    = List.from(e?.subtasks ?? []);
    _tags        = List.from(e?.tags ?? []);
    _blockAppointments = e?.blockAppointments ?? true;
    if (_hasTime && _dueDate != null && _startTime != null) _checkConflict();
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose();
    _tagCtrl.dispose(); _subtaskCtrl.dispose();
    super.dispose();
  }

  void _checkConflict() {
    if (!_hasTime || _dueDate == null || _startTime == null) {
      _conflict = null; return;
    }
    final start = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day,
        _startTime!.hour, _startTime!.minute);
    final end   = start.add(Duration(minutes: _durMins(_duration)));

    // Check appointments
    for (final appt in widget.appointments) {
      if (appt.status == appt_model.ApptStatus.cancelled) continue;
      final as_ = appt.dateTime;
      final ae  = as_.add(Duration(minutes: _durMinsAppt(appt.duration)));
      if (start.isBefore(ae) && end.isAfter(as_)) {
        _conflict = _ConflictInfo(
            label: 'Appointment — ${appt.name}',
            time: _fmt24(as_),
            isAppointment: true,
            appointment: appt);
        return;
      }
    }

    // Check existing personal tasks (excluding self when editing)
    final editId = widget.editing?.id;
    final block  = PersonalTaskStore.instance.conflictFor(start, end);
    if (block != null && block.id != editId) {
      _conflict = _ConflictInfo(
          label: 'Task — ${block.title}',
          time: _fmtTOD(block.startTime!),
          isAppointment: false);
      return;
    }

    _conflict = null;
  }

  Future<void> _pickDate() async {
    final c = widget.dmColors;
    final bright = c.dark ? Brightness.dark : Brightness.light;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
            colorScheme: ColorScheme(brightness: bright,
                primary: c.accent, onPrimary: Colors.white,
                secondary: c.accent, onSecondary: Colors.white,
                error: Colors.red, onError: Colors.white,
                surface: c.card, onSurface: c.txtMain),
            dialogBackgroundColor: c.card),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() { _dueDate = picked; _checkConflict(); });
  }

  Future<void> _pickTime() async {
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please pick a date first',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF4A24A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final c    = widget.dmColors;
    final durM = _durMins(_duration);
    final step = durM < 15 ? 15 : durM;

    // ── Build ALL slots (7 AM – 9 PM) ──────────────────────────────────────
    final allSlots            = <TimeOfDay>[];
    // Slots that overlap an existing *appointment* (orange warning)
    final apptConflicts       = <String>{};
    // Slots that overlap another *personal task* (subtle dimmed)
    final taskConflicts       = <String>{};
    final editId              = widget.editing?.id;

    for (int m = 7 * 60; m + durM <= 21 * 60; m += step) {
      final t     = TimeOfDay(hour: m ~/ 60, minute: m % 60);
      final start = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day,
          t.hour, t.minute);
      final end   = start.add(Duration(minutes: durM));
      final key   = '${t.hour}:${t.minute}';

      allSlots.add(t);

      // Check appointment overlap
      for (final appt in widget.appointments) {
        if (appt.status == appt_model.ApptStatus.cancelled) continue;
        final as_ = appt.dateTime;
        final ae  = as_.add(Duration(minutes: _durMinsAppt(appt.duration)));
        if (start.isBefore(ae) && end.isAfter(as_)) {
          apptConflicts.add(key);
          break;
        }
      }

      // Check personal task overlap (only if no appt conflict already flagged)
      if (!apptConflicts.contains(key)) {
        final blk = PersonalTaskStore.instance.conflictFor(start, end);
        if (blk != null && blk.id != editId) taskConflicts.add(key);
      }
    }

    allSlots.sort((a, b) => (a.hour * 60 + a.minute)
        .compareTo(b.hour * 60 + b.minute));

    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (_) => _TaskSlotPicker(
        slots:         allSlots,
        apptConflicts: apptConflicts,
        taskConflicts: taskConflicts,
        selectedTime:  _startTime,
        dmColors:      c,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() { _startTime = picked; _checkConflict(); });
  }

  void _addSubtask() {
    if (_subtaskCtrl.text.trim().isEmpty) return;
    setState(() { _subtasks.add(SubTask(title: _subtaskCtrl.text.trim())); _subtaskCtrl.clear(); });
  }

  void _addTag() {
    final raw = _tagCtrl.text.trim().replaceAll('#', '');
    if (raw.isEmpty || _tags.contains(raw)) return;
    setState(() { _tags.add(raw); _tagCtrl.clear(); });
  }

  void _save() {
    if (!_canSave) return;
    // If there's an appointment conflict, ask the user what to do first.
    if (_conflict != null && _conflict!.isAppointment && _conflict!.appointment != null) {
      _showConflictConfirmDialog(_conflict!.appointment!);
      return;
    }
    _doSave();
  }

  void _doSave() {
    final task = PersonalTask(
      id:                widget.editing?.id ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
      title:             _titleCtrl.text.trim(),
      description:       _descCtrl.text.trim(),
      priority:          _priority,
      category:          _category,
      dueDate:           _dueDate,
      startTime:         _hasTime ? _startTime : null,
      duration:          _duration,
      hasTime:           _hasTime && _startTime != null,
      hasReminder:       _hasReminder,
      repeat:            _repeat,
      subtasks:          _subtasks,
      tags:              _tags,
      done:              widget.editing?.done ?? false,
      blockAppointments: _blockAppointments,
    );
    widget.onSave(task);
    Navigator.pop(context);
  }

  /// Shows the conflict confirmation dialog for an appointment overlap.
  void _showConflictConfirmDialog(appt_model.Appointment appt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppointmentConflictSheet(
        appt: appt,
        dmColors: widget.dmColors,
        onKeepBoth: () {
          Navigator.pop(context); // close conflict sheet
          setState(() {
            _conflict = null;
            _blockAppointments = false; // allow appointments at this slot
          });
        },
        onCancelAppt: () async {
          final appState = AppStateProvider.of(context);
          if (appt.id != null) {
            await appState.updateAppointmentStatus(appt.id!, appt_model.ApptStatus.cancelled);
          }
          if (!mounted) return;
          Navigator.pop(context); // close conflict sheet
          setState(() => _conflict = null);
          _doSave();
        },
        onReschedule: (newDateTime) async {
          final appState = AppStateProvider.of(context);
          final updated  = appt.copyWith(dateTime: newDateTime);
          await appState.updateAppointment(updated);
          if (!mounted) return;
          Navigator.pop(context); // close conflict sheet
          setState(() => _checkConflict());
          _doSave();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.dmColors;
    final isEditing = widget.editing != null;

    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final screenH   = MediaQuery.of(context).size.height;
    final safeBot   = MediaQuery.of(context).padding.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        height: screenH * 0.92,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: c.border, width: 1.5)),
        ),
        child: Column(children: [
          // Handle + title (fixed, never scrolls)
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(isEditing ? 'Edit Task' : 'New Task',
                  style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w900, color: c.txtMain))),
              // Category badge
              GestureDetector(
                onTap: () => _cycleCat(),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _category.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _category.color.withOpacity(0.35))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_category.icon, size: 13, color: _category.color),
                      const SizedBox(width: 5),
                      Text(_category.label, style: GoogleFonts.dmSans(
                          fontSize: 11, fontWeight: FontWeight.w700, color: _category.color)),
                    ])),
              ),
            ]),
          ])),
          // Scrollable form body — fills remaining space
          Expanded(child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Title ─────────────────────────────────────────────────────
              _fld(c, child: TextField(
                autofocus: false,
                controller: _titleCtrl,
                style: GoogleFonts.dmSans(fontSize: 15, color: c.txtMain, fontWeight: FontWeight.w600),
                decoration: InputDecoration(border: InputBorder.none,
                    hintText: 'Task title…',
                    hintStyle: GoogleFonts.dmSans(color: c.txtSub, fontSize: 14),
                    prefixIcon: Icon(Icons.edit_rounded, size: 18, color: c.accent)),
              )),
              const SizedBox(height: 10),
              // ── Description ───────────────────────────────────────────────
              _fld(c, child: TextField(
                autofocus: false,
                controller: _descCtrl, maxLines: 2,
                style: GoogleFonts.dmSans(fontSize: 13.5, color: c.txtMain),
                decoration: InputDecoration(border: InputBorder.none,
                    hintText: 'Add details, notes…',
                    hintStyle: GoogleFonts.dmSans(color: c.txtSub, fontSize: 13),
                    contentPadding: const EdgeInsets.all(14)),
              )),
              const SizedBox(height: 14),
              // ── Priority ──────────────────────────────────────────────────
              _sectionLabel('Priority', Icons.flag_rounded, c),
              const SizedBox(height: 8),
              Row(children: TaskPriority.values.map((p) {
                final sel = _priority == p;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _priority = p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: p != TaskPriority.low ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        gradient: sel ? LinearGradient(colors: [p.color, p.color.withOpacity(0.75)]) : null,
                        color: sel ? null : c.card2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? p.color : c.border, width: sel ? 1.5 : 1),
                        boxShadow: sel ? [BoxShadow(color: p.color.withOpacity(0.3), blurRadius: 8)] : []),
                    child: Column(children: [
                      Icon(p.icon, size: 16, color: sel ? Colors.white : p.color),
                      const SizedBox(height: 3),
                      Text(p.label, style: GoogleFonts.dmSans(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : c.txtSub)),
                    ]),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 14),
              // ── Category ──────────────────────────────────────────────────
              _sectionLabel('Category', Icons.category_rounded, c),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: TaskCategory.values.map((cat) {
                final sel = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                        color: sel ? cat.color.withOpacity(0.18) : c.card2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? cat.color : c.border,
                            width: sel ? 1.5 : 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(cat.icon, size: 13, color: sel ? cat.color : c.txtSub),
                      const SizedBox(width: 5),
                      Text(cat.label, style: GoogleFonts.dmSans(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? cat.color : c.txtSub)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 14),
              // ── Due Date ──────────────────────────────────────────────────
              _sectionLabel('Schedule', Icons.event_rounded, c),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _pickDate,
                  child: _infoTile(c,
                      icon: Icons.calendar_today_rounded,
                      label: _dueDate != null ? _fmtDateFull(_dueDate!) : 'Pick date',
                      filled: _dueDate != null),
                )),
                const SizedBox(width: 10),
                // Time toggle
                GestureDetector(
                  onTap: () => setState(() {
                    _hasTime = !_hasTime;
                    if (!_hasTime) { _startTime = null; _conflict = null; }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: _hasTime ? c.accent.withOpacity(0.15) : c.card2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _hasTime ? c.accent : c.border,
                            width: _hasTime ? 1.5 : 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.access_time_rounded, size: 16,
                          color: _hasTime ? c.accent : c.txtSub),
                      const SizedBox(width: 6),
                      Text('Timed', style: GoogleFonts.dmSans(
                          fontSize: 12.5, fontWeight: FontWeight.w700,
                          color: _hasTime ? c.accent : c.txtSub)),
                    ]),
                  ),
                ),
              ]),
              // Time row (if timed)
              if (_hasTime) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: _pickTime,
                    child: _infoTile(c,
                        icon: Icons.schedule_rounded,
                        label: _startTime != null ? _fmtTOD(_startTime!) : 'Pick time',
                        filled: _startTime != null),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _durationPicker(c)),
                ]),
                // Conflict banner
                if (_conflict != null) ...[
                  const SizedBox(height: 10),
                  _conflictBanner(c),
                ] else if (_startTime != null && _dueDate != null) ...[
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: const Color(0xFF2ECC96).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2ECC96).withOpacity(0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2ECC96)),
                        const SizedBox(width: 8),
                        Text('Slot is free — no conflicts', style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2ECC96))),
                      ])),
                ],
              ],
              const SizedBox(height: 14),
              // ── Subtasks ──────────────────────────────────────────────────
              _sectionLabel('Subtasks', Icons.checklist_rounded, c),
              const SizedBox(height: 8),
              if (_subtasks.isNotEmpty) ...[
                ..._subtasks.asMap().entries.map((e) {
                  final i = e.key; final s = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: c.card2, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border)),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => setState(() => _subtasks[i].done = !s.done),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22, height: 22,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: s.done ? const Color(0xFF2ECC96) : Colors.transparent,
                              border: Border.all(color: s.done ? const Color(0xFF2ECC96) : c.border, width: 2)),
                          child: s.done ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.title, style: GoogleFonts.dmSans(
                          fontSize: 13, color: s.done ? c.txtSub : c.txtMain,
                          fontWeight: FontWeight.w500,
                          decoration: s.done ? TextDecoration.lineThrough : null,
                          decorationColor: c.txtSub))),
                      GestureDetector(
                        onTap: () => setState(() => _subtasks.removeAt(i)),
                        child: Icon(Icons.close_rounded, size: 16, color: c.txtSub.withOpacity(0.5)),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 6),
              ],
              // Add subtask input
              _fld(c, child: Row(children: [
                Icon(Icons.add_rounded, size: 18, color: c.accent),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  autofocus: false,
                  controller: _subtaskCtrl,
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: c.txtMain),
                  onSubmitted: (_) => _addSubtask(),
                  decoration: InputDecoration(border: InputBorder.none,
                      hintText: 'Add a subtask…',
                      hintStyle: GoogleFonts.dmSans(color: c.txtSub, fontSize: 13)),
                )),
                GestureDetector(onTap: _addSubtask,
                    child: Text('Add', style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: c.accent))),
              ])),
              const SizedBox(height: 14),
              // ── Tags ──────────────────────────────────────────────────────
              _sectionLabel('Tags', Icons.label_outline_rounded, c),
              const SizedBox(height: 8),
              if (_tags.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: _tags.map((tag) =>
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: c.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.accent.withOpacity(0.3))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('#$tag', style: GoogleFonts.dmSans(
                              fontSize: 12, fontWeight: FontWeight.w700, color: c.accent)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() => _tags.remove(tag)),
                            child: Icon(Icons.close_rounded, size: 12, color: c.accent.withOpacity(0.6)),
                          ),
                        ]))).toList()),
                const SizedBox(height: 6),
              ],
              _fld(c, child: Row(children: [
                Icon(Icons.tag_rounded, size: 18, color: c.accent),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  autofocus: false,
                  controller: _tagCtrl,
                  onSubmitted: (_) => _addTag(),
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: c.txtMain),
                  decoration: InputDecoration(border: InputBorder.none,
                      hintText: 'Add tag (e.g. clinic, urgent)',
                      hintStyle: GoogleFonts.dmSans(color: c.txtSub, fontSize: 13)),
                )),
                GestureDetector(onTap: _addTag,
                    child: Text('Add', style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: c.accent))),
              ])),
              const SizedBox(height: 14),
              // ── Options row ───────────────────────────────────────────────
              Row(children: [
                // Reminder
                Expanded(child: GestureDetector(
                  onTap: () => setState(() => _hasReminder = !_hasReminder),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                        color: _hasReminder ? AppColors.warning.withOpacity(0.15) : c.card2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _hasReminder ? AppColors.warning : c.border,
                            width: _hasReminder ? 1.5 : 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notifications_rounded, size: 16,
                          color: _hasReminder ? AppColors.warning : c.txtSub),
                      const SizedBox(width: 6),
                      Text('Reminder', style: GoogleFonts.dmSans(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: _hasReminder ? AppColors.warning : c.txtSub)),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                // Repeat
                Expanded(child: GestureDetector(
                  onTap: () {
                    final next = TaskRepeat.values[(_repeat.index + 1) % TaskRepeat.values.length];
                    setState(() => _repeat = next);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                        color: _repeat != TaskRepeat.none ? c.accent.withOpacity(0.12) : c.card2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _repeat != TaskRepeat.none ? c.accent : c.border,
                            width: _repeat != TaskRepeat.none ? 1.5 : 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_repeat.icon, size: 16,
                          color: _repeat != TaskRepeat.none ? c.accent : c.txtSub),
                      const SizedBox(width: 6),
                      Text(_repeat.label, style: GoogleFonts.dmSans(
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: _repeat != TaskRepeat.none ? c.accent : c.txtSub)),
                    ]),
                  ),
                )),
              ]),
              // ── Block Appointments Toggle ─────────────────────────────────
              if (_hasTime) ...[ // Only meaningful when task has a time slot
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _blockAppointments = !_blockAppointments),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: _blockAppointments
                          ? const Color(0xFFE05C5C).withOpacity(0.10)
                          : const Color(0xFF2ECC96).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _blockAppointments
                            ? const Color(0xFFE05C5C).withOpacity(0.40)
                            : const Color(0xFF2ECC96).withOpacity(0.40),
                        width: 1.4,
                      ),
                    ),
                    child: Row(children: [
                      // Icon
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: _blockAppointments
                              ? const Color(0xFFE05C5C).withOpacity(0.15)
                              : const Color(0xFF2ECC96).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _blockAppointments
                              ? Icons.block_rounded
                              : Icons.event_available_rounded,
                          size: 17,
                          color: _blockAppointments
                              ? const Color(0xFFE05C5C)
                              : const Color(0xFF2ECC96),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Labels
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Block appointments during this task',
                            style: GoogleFonts.dmSans(
                                fontSize: 12.5, fontWeight: FontWeight.w700,
                                color: _blockAppointments
                                    ? const Color(0xFFE05C5C)
                                    : const Color(0xFF2ECC96))),
                        const SizedBox(height: 2),
                        Text(
                          _blockAppointments
                              ? 'Clients cannot book this time slot'
                              : 'Clients can book appointments at this time',
                          style: GoogleFonts.dmSans(
                              fontSize: 11, fontWeight: FontWeight.w500,
                              color: _blockAppointments
                                  ? const Color(0xFFE05C5C).withOpacity(0.65)
                                  : const Color(0xFF2ECC96).withOpacity(0.65)),
                        ),
                      ])),
                      const SizedBox(width: 10),
                      // Custom animated toggle switch
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 46, height: 26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: _blockAppointments
                              ? const Color(0xFFE05C5C)
                              : const Color(0xFF2ECC96),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          alignment: _blockAppointments
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 20, height: 20,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ]),
          ))),  // SingleChildScrollView + GestureDetector + Expanded
          // ── Save button — pinned outside the scroll area ─────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, 10, 20, safeBot > 0 ? safeBot : 20),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.border, width: 1)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Validation hints
              if (_titleCtrl.text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 13,
                        color: c.txtSub.withOpacity(0.55)),
                    const SizedBox(width: 6),
                    Text('Add a title to save',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: c.txtSub.withOpacity(0.55))),
                  ]),
                ),
              if (_dueDate == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 13,
                        color: Color(0xFFF4A24A)),
                    const SizedBox(width: 6),
                    Text('A date is required before saving',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF4A24A))),
                  ]),
                ),
              if (_dueDate != null && !_hasTime)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.access_time_rounded, size: 13,
                        color: Color(0xFFF4A24A)),
                    const SizedBox(width: 6),
                    Text('A time is required before saving',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF4A24A))),
                  ]),
                ),
              if (_hasTime && _startTime == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, size: 13,
                        color: Color(0xFFF4A24A)),
                    const SizedBox(width: 6),
                    Text('Pick a specific time slot to continue',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF4A24A))),
                  ]),
                ),
              // The button itself
              GestureDetector(
                onTap: _canSave ? _save : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _canSave
                        ? LinearGradient(colors: c.btnGradient)
                        : null,
                    color: _canSave ? null : c.card2,
                    borderRadius: BorderRadius.circular(16),
                    border: _canSave
                        ? null
                        : Border.all(color: c.border, width: 1.2),
                    boxShadow: _canSave ? [
                      BoxShadow(color: c.accent.withOpacity(0.35),
                          blurRadius: 14, offset: const Offset(0, 5))
                    ] : [],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(isEditing
                        ? Icons.save_rounded
                        : Icons.add_task_rounded,
                        color: _canSave ? Colors.white : c.txtSub, size: 20),
                    const SizedBox(width: 10),
                    Text(isEditing ? 'Save Changes' : 'Create Task',
                        style: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: _canSave ? Colors.white : c.txtSub)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// True when all required fields are filled and no unresolved conflict.
  bool get _canSave =>
      _titleCtrl.text.trim().isNotEmpty &&
      _dueDate != null &&
      _hasTime &&
      _startTime != null;

  // helpers inside sheet
  Widget _conflictBanner(_DmColors c) {
    final isAppt = _conflict!.isAppointment;
    const red    = Color(0xFFE05C5C);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: red.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: red.withOpacity(0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ───────────────────────────────────────────────────────
        Row(children: [
          Container(width: 32, height: 32,
              decoration: BoxDecoration(color: red.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.event_busy_rounded, size: 17, color: red)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Schedule conflict', style: GoogleFonts.dmSans(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: red)),
            Text(_conflict!.label, style: GoogleFonts.dmSans(
                fontSize: 11.5, color: red.withOpacity(0.75), fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_conflict!.time, style: GoogleFonts.dmSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: red))),
        ]),
        if (isAppt) ...[ // ── Quick-action chips for appointment conflicts ──
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _conflictChip(c, Icons.visibility_rounded, 'View', const Color(0xFF4A90D9), () {
                final appt = _conflict!.appointment!;
                showModalBottomSheet(
                  context: context, backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => _AppointmentQuickView(appt: appt, dmColors: c),
                );
              }),
              const SizedBox(width: 6),
              _conflictChip(c, Icons.cancel_outlined, 'Cancel Appt', red, () async {
                final appState = AppStateProvider.of(context);
                final appt = _conflict!.appointment!;
                if (appt.id != null) {
                  await appState.updateAppointmentStatus(appt.id!, appt_model.ApptStatus.cancelled);
                }
                if (!mounted) return;
                setState(() => _checkConflict());
              }),
              const SizedBox(width: 6),
              _conflictChip(c, Icons.edit_calendar_rounded, 'Reschedule', const Color(0xFFF4A24A), () async {
                final appt = _conflict!.appointment!;
                final newDT = await _pickRescheduleDateTime(appt.dateTime);
                if (!mounted || newDT == null) return;
                final appState = AppStateProvider.of(context);
                await appState.updateAppointment(appt.copyWith(dateTime: newDT));
                if (!mounted) return;
                setState(() => _checkConflict());
              }),
              const SizedBox(width: 6),
              _conflictChip(c, Icons.done_all_rounded, 'Keep Both', const Color(0xFF2ECC96), () {
                // Clear banner + automatically allow appointments at this time
                // since user explicitly accepted the overlap.
                setState(() {
                  _conflict = null;
                  _blockAppointments = false;
                });
              }),
            ]),
          ),
          const SizedBox(height: 4),
          Text('Tap "Create Task" to confirm keeping both, or choose an action above.',
              style: GoogleFonts.dmSans(fontSize: 10.5, color: red.withOpacity(0.6),
                  fontWeight: FontWeight.w500)),
        ],
      ]),
    );
  }

  Widget _conflictChip(_DmColors c, IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.40), width: 1.2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label, style: GoogleFonts.dmSans(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );

  /// Picks a new date + time for rescheduling the given appointment.
  Future<DateTime?> _pickRescheduleDateTime(DateTime current) async {
    final c = widget.dmColors;
    final bright = c.dark ? Brightness.dark : Brightness.light;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
            colorScheme: ColorScheme(brightness: bright,
                primary: c.accent, onPrimary: Colors.white,
                secondary: c.accent, onSecondary: Colors.white,
                error: Colors.red, onError: Colors.white,
                surface: c.card, onSurface: c.txtMain),
            dialogBackgroundColor: c.card),
        child: child!,
      ),
    );
    if (!mounted || date == null) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (ctx, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
            colorScheme: ColorScheme(brightness: bright,
                primary: c.accent, onPrimary: Colors.white,
                secondary: c.accent, onSecondary: Colors.white,
                error: Colors.red, onError: Colors.white,
                surface: c.card, onSurface: c.txtMain),
            dialogBackgroundColor: c.card),
        child: child!,
      ),
    );
    if (!mounted || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Widget _infoTile(_DmColors c, {required IconData icon, required String label, required bool filled}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: filled ? c.accent.withOpacity(0.1) : c.card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: filled ? c.accent.withOpacity(0.4) : c.border, width: filled ? 1.5 : 1)),
        child: Row(children: [
          Icon(icon, size: 16, color: filled ? c.accent : c.txtSub),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: GoogleFonts.dmSans(
              fontSize: 12.5, fontWeight: FontWeight.w600,
              color: filled ? c.txtMain : c.txtSub), overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _durationPicker(_DmColors c) {
    final durations = ['15 min', '30 min', '45 min', '1 hr', '1.5 hr', '2 hr'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: c.card2, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: _duration, isExpanded: true, dropdownColor: c.card,
        icon: Icon(Icons.expand_more_rounded, color: c.txtSub, size: 18),
        style: GoogleFonts.dmSans(fontSize: 13, color: c.txtMain, fontWeight: FontWeight.w600),
        items: durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
        onChanged: (v) { if (v != null) setState(() { _duration = v; _checkConflict(); }); },
      )),
    );
  }

  Widget _fld(_DmColors c, {required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(color: c.card2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border)),
    child: child,
  );

  Widget _sectionLabel(String t, IconData icon, _DmColors c) => Row(children: [
    Icon(icon, size: 14, color: c.accent), const SizedBox(width: 6),
    Text(t, style: GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w800,
        color: c.txtSub, letterSpacing: 0.4)),
  ]);

  void _cycleCat() {
    setState(() {
      final next = (_category.index + 1) % TaskCategory.values.length;
      _category = TaskCategory.values[next];
    });
  }

  String _fmtDateFull(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const w = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${w[d.weekday - 1]}, ${d.day} ${m[d.month - 1]}';
  }

  String _fmtTOD(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  String _fmt24(DateTime dt) {
    final t = TimeOfDay.fromDateTime(dt);
    return _fmtTOD(t);
  }

  static int _durMins(String d) {
    if (d == '15 min') return 15; if (d == '30 min') return 30;
    if (d == '45 min') return 45; if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90; if (d == '2 hr')   return 120;
    return 30;
  }
  static int _durMinsAppt(String d) => _durMins(d);
}

// ─────────────────────────────────────────────────────────────────────────────
//  TASK DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _TaskDetailSheet extends StatefulWidget {
  final PersonalTask                task;
  final List<appt_model.Appointment> appointments;
  final _DmColors                   dmColors;
  final VoidCallback                onToggle;
  final VoidCallback                onDelete;
  final VoidCallback                onEdit;
  final void Function(int idx)      onSubtaskToggle;
  const _TaskDetailSheet({required this.task, required this.appointments,
      required this.dmColors, required this.onToggle,
      required this.onDelete, required this.onEdit, required this.onSubtaskToggle});
  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final c    = widget.dmColors;
    final task = widget.task;
    final pc   = task.priority.color;
    final cc   = task.category.color;
    final bottomPad = MediaQuery.of(context).padding.bottom + 12;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.border, width: 1.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
        ),
        const SizedBox(height: 18),
        // Scrollable content
        Flexible(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title + badges
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(task.title, style: GoogleFonts.dmSans(
              fontSize: 20, fontWeight: FontWeight.w900, color: c.txtMain,
              letterSpacing: -0.5,
              decoration: task.done ? TextDecoration.lineThrough : null,
              decorationColor: c.txtSub))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: pc.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: pc.withOpacity(0.35))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(task.priority.icon, size: 12, color: pc),
                  const SizedBox(width: 4),
                  Text(task.priority.label, style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w800, color: pc)),
                ])),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: cc.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cc.withOpacity(0.35))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(task.category.icon, size: 12, color: cc),
                  const SizedBox(width: 4),
                  Text(task.category.label, style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w800, color: cc)),
                ])),
          ]),
        ]),
        if (task.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(task.description, style: GoogleFonts.dmSans(
              fontSize: 13.5, color: c.txtSub, height: 1.6, fontWeight: FontWeight.w500)),
        ],
        const SizedBox(height: 14),
        // Meta info chips
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (task.dueDate != null) _chip(c, Icons.event_rounded,
              _fmtDateFull(task.dueDate!), c.txtSub),
          if (task.hasTime && task.startTime != null) _chip(c, Icons.schedule_rounded,
              '${_fmtTOD(task.startTime!)} · ${task.duration}', c.accent),
          if (task.hasReminder) _chip(c, Icons.notifications_rounded, 'Reminder set', AppColors.warning),
          if (task.repeat != TaskRepeat.none) _chip(c, task.repeat.icon, task.repeat.label, c.accent),
        ]),
        // Subtasks
        if (task.subtasks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.checklist_rounded, size: 14, color: c.accent),
            const SizedBox(width: 6),
            Text('Subtasks', style: GoogleFonts.dmSans(fontSize: 12,
                fontWeight: FontWeight.w800, color: c.txtSub, letterSpacing: 0.3)),
            const SizedBox(width: 8),
            Text('${task.completedSubtasks}/${task.subtasks.length}',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: c.accent)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
            value: task.subtaskProgress, minHeight: 4,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation<Color>(c.accent),
          )),
          const SizedBox(height: 8),
          ...task.subtasks.asMap().entries.map((e) {
            final i = e.key; final s = e.value;
            return GestureDetector(
              onTap: () { widget.onSubtaskToggle(i); setState(() {}); },
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
                AnimatedContainer(duration: const Duration(milliseconds: 200),
                    width: 22, height: 22,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: s.done ? const Color(0xFF2ECC96) : Colors.transparent,
                        border: Border.all(color: s.done ? const Color(0xFF2ECC96) : c.border, width: 2)),
                    child: s.done ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null),
                const SizedBox(width: 10),
                Expanded(child: Text(s.title, style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: s.done ? c.txtSub : c.txtMain,
                    fontWeight: FontWeight.w500,
                    decoration: s.done ? TextDecoration.lineThrough : null,
                    decorationColor: c.txtSub))),
              ])),
            );
          }),
        ],
        // Tags
        if (task.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: task.tags.map((t) =>
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: c.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.accent.withOpacity(0.25))),
                  child: Text('#$t', style: GoogleFonts.dmSans(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: c.accent.withOpacity(0.85))))).toList()),
        ],
        const SizedBox(height: 20),
        // Action buttons
        Row(children: [
          Expanded(child: _actionBtn(c,
              icon: task.done ? Icons.undo_rounded : Icons.check_circle_rounded,
              label: task.done ? 'Mark Pending' : 'Mark Done',
              color: const Color(0xFF2ECC96),
              onTap: () { widget.onToggle(); Navigator.pop(context); })),
          const SizedBox(width: 10),
          Expanded(child: _actionBtn(c,
              icon: Icons.edit_rounded, label: 'Edit Task',
              color: c.accent, onTap: widget.onEdit)),
          const SizedBox(width: 10),
          _iconActionBtn(c, Icons.delete_outline_rounded, const Color(0xFFE05C5C), widget.onDelete),
        ]),
        ]))), // close inner Column, SingleChildScrollView, Flexible
      ]),
    );
  }

  Widget _chip(_DmColors c, IconData icon, String label, Color color) =>
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color), const SizedBox(width: 5),
            Text(label, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ]));

  Widget _actionBtn(_DmColors c, {required IconData icon, required String label,
      required Color color, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.35))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: color), const SizedBox(width: 6),
              Text(label, style: GoogleFonts.dmSans(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
            ])),
      );

  Widget _iconActionBtn(_DmColors c, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(width: 48, height: 46,
            decoration: BoxDecoration(color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.35))),
            child: Icon(icon, color: color, size: 20)),
      );

  String _fmtDateFull(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const w = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${w[d.weekday - 1]}, ${d.day} ${m[d.month - 1]}';
  }

  String _fmtTOD(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  APPOINTMENT CONFLICT BOTTOM SHEET
//  Shown when user taps "Create Task" while a conflicting appointment exists.
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentConflictSheet extends StatelessWidget {
  final appt_model.Appointment           appt;
  final _DmColors                        dmColors;
  final VoidCallback                     onKeepBoth;
  final Future<void> Function()          onCancelAppt;
  final Future<void> Function(DateTime)  onReschedule;

  const _AppointmentConflictSheet({
    required this.appt,
    required this.dmColors,
    required this.onKeepBoth,
    required this.onCancelAppt,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    final c = dmColors;
    const red    = Color(0xFFE05C5C);
    const orange = Color(0xFFF4A24A);
    const green  = Color(0xFF2ECC96);
    const blue   = Color(0xFF4A90D9);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.border, width: 1.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 18),
        Flexible(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Warning header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: red.withOpacity(0.09),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: red.withOpacity(0.35)),
              ),
              child: Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: red.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.event_busy_rounded, color: red, size: 22)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Appointment Conflict', style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w900, color: red)),
                  const SizedBox(height: 3),
                  Text('Your task overlaps an existing appointment.',
                      style: GoogleFonts.dmSans(fontSize: 12, color: red.withOpacity(0.7),
                          fontWeight: FontWeight.w500)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Appointment card ────────────────────────────────────────────
            Text('Conflicting Appointment', style: GoogleFonts.dmSans(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: c.txtSub,
                letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border, width: 1.2),
              ),
              child: Row(children: [
                CircleAvatar(radius: 22, backgroundColor: appt.avatarColor.withOpacity(0.2),
                    child: Text(appt.initials, style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w900, color: appt.avatarColor))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appt.name, style: GoogleFonts.dmSans(
                      fontSize: 14, fontWeight: FontWeight.w800, color: c.txtMain)),
                  const SizedBox(height: 3),
                  Text(appt.service, style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 11, color: c.txtSub),
                    const SizedBox(width: 4),
                    Text(appt.displayDate, style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: c.txtSub)),
                    const SizedBox(width: 10),
                    Icon(Icons.access_time_rounded, size: 11, color: c.accent),
                    const SizedBox(width: 4),
                    Text('${appt.displayTime} · ${appt.duration}',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w600, color: c.accent)),
                  ]),
                ])),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Action options label ────────────────────────────────────────
            Text('What would you like to do?', style: GoogleFonts.dmSans(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: c.txtSub,
                letterSpacing: 0.4)),
            const SizedBox(height: 10),

            // Keep Both
            _optionTile(c,
              icon: Icons.done_all_rounded, color: green,
              title: 'Keep Both',
              subtitle: 'Save the task and keep the appointment as-is.',
              onTap: onKeepBoth,
            ),
            const SizedBox(height: 8),

            // View Appointment
            _optionTile(c,
              icon: Icons.visibility_rounded, color: blue,
              title: 'View Appointment',
              subtitle: 'Review the appointment details before deciding.',
              onTap: () {
                showModalBottomSheet(
                  context: context, backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => _AppointmentQuickView(appt: appt, dmColors: c),
                );
              },
            ),
            const SizedBox(height: 8),

            // Cancel Appointment
            _optionTile(c,
              icon: Icons.cancel_outlined, color: red,
              title: 'Cancel Appointment',
              subtitle: 'Cancel the conflicting appointment and save the task.',
              onTap: () async { await onCancelAppt(); },
            ),
            const SizedBox(height: 8),

            // Reschedule Appointment
            _optionTile(c,
              icon: Icons.edit_calendar_rounded, color: orange,
              title: 'Reschedule Appointment',
              subtitle: 'Pick a new date & time for the appointment, then save the task.',
              onTap: () async {
                final bright = c.dark ? Brightness.dark : Brightness.light;
                final date = await showDatePicker(
                  context: context,
                  initialDate: appt.dateTime,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                  builder: (ctx, child) => Theme(
                    data: ThemeData(brightness: bright).copyWith(
                        colorScheme: ColorScheme(brightness: bright,
                            primary: c.accent, onPrimary: Colors.white,
                            secondary: c.accent, onSecondary: Colors.white,
                            error: Colors.red, onError: Colors.white,
                            surface: c.card, onSurface: c.txtMain),
                        dialogBackgroundColor: c.card),
                    child: child!,
                  ),
                );
                if (date == null) return;
                if (!context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(appt.dateTime),
                  builder: (ctx, child) => Theme(
                    data: ThemeData(brightness: bright).copyWith(
                        colorScheme: ColorScheme(brightness: bright,
                            primary: c.accent, onPrimary: Colors.white,
                            secondary: c.accent, onSecondary: Colors.white,
                            error: Colors.red, onError: Colors.white,
                            surface: c.card, onSurface: c.txtMain),
                        dialogBackgroundColor: c.card),
                    child: child!,
                  ),
                );
                if (time == null) return;
                final newDT = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                await onReschedule(newDT);
              },
            ),
          ]),
        )),
      ]),
    );
  }

  Widget _optionTile(_DmColors c, {
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.30), width: 1.3),
      ),
      child: Row(children: [
        Container(width: 38, height: 38,
            decoration: BoxDecoration(color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: color)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.dmSans(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: c.txtMain)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.dmSans(
              fontSize: 11.5, fontWeight: FontWeight.w500,
              color: c.txtSub, height: 1.35)),
        ])),
        Icon(Icons.chevron_right_rounded, size: 18, color: color.withOpacity(0.5)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  APPOINTMENT QUICK VIEW SHEET
//  A compact read-only preview of an appointment's details.
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentQuickView extends StatelessWidget {
  final appt_model.Appointment appt;
  final _DmColors              dmColors;
  const _AppointmentQuickView({required this.appt, required this.dmColors});

  @override
  Widget build(BuildContext context) {
    final c = dmColors;
    final statusColor = _statusColor(appt.status);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.border, width: 1.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 18),
        Flexible(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
          child: Column(children: [
            // Client row
            Row(children: [
              Container(decoration: BoxDecoration(shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: appt.avatarColor.withOpacity(0.3), blurRadius: 12)]),
                child: CircleAvatar(radius: 28, backgroundColor: appt.avatarColor.withOpacity(0.2),
                    child: Text(appt.initials, style: GoogleFonts.dmSans(
                        fontSize: 18, fontWeight: FontWeight.w900, color: appt.avatarColor))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appt.name, style: GoogleFonts.dmSans(
                    fontSize: 18, fontWeight: FontWeight.w900, color: c.txtMain)),
                const SizedBox(height: 3),
                Text(appt.service, style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.accent)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withOpacity(0.35))),
                child: Text(_statusLabel(appt.status), style: GoogleFonts.dmSans(
                    fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
              ),
            ]),
            const SizedBox(height: 18),
            // Details grid
            _row(c, Icons.calendar_today_rounded, 'Date', appt.displayDate, c.txtMain),
            const SizedBox(height: 10),
            _row(c, Icons.access_time_rounded, 'Time', appt.displayTime, c.accent),
            const SizedBox(height: 10),
            _row(c, Icons.timer_outlined, 'Duration', appt.duration, c.txtMain),
            if (appt.location.isNotEmpty) ...[ const SizedBox(height: 10),
              _row(c, Icons.place_rounded, 'Location', appt.location, c.txtMain) ],
            if (appt.note.isNotEmpty) ...[ const SizedBox(height: 10),
              _row(c, Icons.notes_rounded, 'Note', appt.note, c.txtSub) ],
            const SizedBox(height: 20),
            // Close button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: c.card2, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Center(child: Text('Close', style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w700, color: c.txtSub))),
              ),
            ),
          ]),
        )),
      ]),
    );
  }

  Widget _row(_DmColors c, IconData icon, String label, String value, Color vColor) =>
      Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: c.card2, borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.border)),
            child: Icon(icon, size: 15, color: c.accent)),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600,
            color: c.txtSub)),
        const Spacer(),
        Text(value, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700,
            color: vColor)),
      ]);

  Color _statusColor(appt_model.ApptStatus s) {
    switch (s) {
      case appt_model.ApptStatus.confirmed:  return const Color(0xFF2ECC96);
      case appt_model.ApptStatus.pending:    return const Color(0xFFF4A24A);
      case appt_model.ApptStatus.cancelled:  return const Color(0xFFE05C5C);
      case appt_model.ApptStatus.completed:  return const Color(0xFF4A90D9);
    }
  }

  String _statusLabel(appt_model.ApptStatus s) {
    switch (s) {
      case appt_model.ApptStatus.confirmed:  return 'Confirmed';
      case appt_model.ApptStatus.pending:    return 'Pending';
      case appt_model.ApptStatus.cancelled:  return 'Cancelled';
      case appt_model.ApptStatus.completed:  return 'Completed';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _ConflictInfo {
  final String  label;
  final String  time;
  final bool    isAppointment;
  /// The actual appointment object — set only when isAppointment == true.
  final appt_model.Appointment? appointment;
  const _ConflictInfo({required this.label, required this.time,
      required this.isAppointment, this.appointment});
}

class _DmColors {
  final Color        bg, card, card2, border, txtMain, txtSub, accent;
  final List<Color>  btnGradient, heroGradient;
  final bool         dark;
  const _DmColors({required this.bg, required this.card, required this.card2,
      required this.border, required this.txtMain, required this.txtSub,
      required this.accent, required this.btnGradient, required this.heroGradient,
      required this.dark});
}


// ─────────────────────────────────────────────────────────────────────────────
//  TASK SLOT PICKER BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _TaskSlotPicker extends StatelessWidget {
  final List<TimeOfDay> slots;
  /// Keys formatted as "hour:minute" — overlap an appointment.
  final Set<String>     apptConflicts;
  /// Keys formatted as "hour:minute" — overlap another personal task.
  final Set<String>     taskConflicts;
  final TimeOfDay?      selectedTime;
  final _DmColors       dmColors;

  const _TaskSlotPicker({
    required this.slots,
    required this.apptConflicts,
    required this.taskConflicts,
    required this.selectedTime,
    required this.dmColors,
  });

  String _fmt(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  String _key(TimeOfDay t) => '${t.hour}:${t.minute}';

  @override
  Widget build(BuildContext context) {
    final c            = dmColors;
    const orange       = Color(0xFFF4A24A);
    const dimGray      = Color(0xFF94A3B8);
    final freeCount    = slots.where((t) {
      final k = _key(t);
      return !apptConflicts.contains(k) && !taskConflicts.contains(k);
    }).length;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: c.border, width: 1.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 14),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: c.border, borderRadius: BorderRadius.circular(2)),
        )),

        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Icon(Icons.access_time_rounded, size: 16, color: c.accent),
            const SizedBox(width: 8),
            Text('Pick a Time Slot', style: GoogleFonts.dmSans(
                fontSize: 15, fontWeight: FontWeight.w800, color: c.txtMain)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('$freeCount free', style: GoogleFonts.dmSans(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: c.accent)),
            ),
            if (apptConflicts.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${apptConflicts.length} booked',
                    style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: orange)),
              ),
            ],
          ]),
        ),

        // Legend row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: Row(children: [
            _dot(c.accent), const SizedBox(width: 5),
            Text('Free', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w600, color: c.txtSub)),
            const SizedBox(width: 14),
            _dot(orange), const SizedBox(width: 5),
            Text('Appointment booked', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w600, color: c.txtSub)),
            const SizedBox(width: 14),
            _dot(dimGray), const SizedBox(width: 5),
            Text('Task overlap', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w600, color: c.txtSub)),
          ]),
        ),

        // Info banner when there are appointment conflicts
        if (apptConflicts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: orange.withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: orange.withOpacity(0.30)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: orange),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  "Orange slots have existing appointments. You can still select them — "
                  "you'll be asked to keep both, cancel, or reschedule the appointment.",
                  style: GoogleFonts.dmSans(fontSize: 11.5,
                      fontWeight: FontWeight.w500, color: orange, height: 1.4),
                )),
              ]),
            ),
          ),
        const SizedBox(height: 10),

        // Slot grid
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.event_busy_rounded, size: 48,
                  color: c.txtSub.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text('No slots available on this date', style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: c.txtSub.withOpacity(0.5))),
            ]),
          )
        else
          Flexible(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, MediaQuery.of(context).padding.bottom + 24),
            child: Wrap(spacing: 8, runSpacing: 8,
              children: slots.map((t) {
                final k      = _key(t);
                final isAppt = apptConflicts.contains(k);
                final isTask = taskConflicts.contains(k);
                final isSel  = selectedTime?.hour == t.hour &&
                    selectedTime?.minute == t.minute;

                final Color slotBg, slotFg, slotBorder;
                final IconData slotIcon;

                if (isSel && isAppt) {
                  slotBg = orange; slotFg = Colors.white;
                  slotBorder = orange;
                  slotIcon = Icons.warning_amber_rounded;
                } else if (isSel) {
                  slotBg = c.accent; slotFg = Colors.white;
                  slotBorder = c.accent;
                  slotIcon = Icons.check_rounded;
                } else if (isAppt) {
                  slotBg = orange.withOpacity(0.10); slotFg = orange;
                  slotBorder = orange.withOpacity(0.45);
                  slotIcon = Icons.event_busy_rounded;
                } else if (isTask) {
                  slotBg = dimGray.withOpacity(0.08); slotFg = dimGray;
                  slotBorder = dimGray.withOpacity(0.30);
                  slotIcon = Icons.schedule_rounded;
                } else {
                  slotBg = c.card2; slotFg = c.accent;
                  slotBorder = c.border;
                  slotIcon = Icons.schedule_rounded;
                }

                return GestureDetector(
                  onTap: () => Navigator.pop(context, t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSel ? LinearGradient(
                          colors: [slotBg, slotBg.withOpacity(0.78)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight) : null,
                      color: isSel ? null : slotBg,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: slotBorder, width: isSel ? 1.8 : 1.2),
                      boxShadow: isSel ? [BoxShadow(
                          color: slotBg.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3))] : [],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(slotIcon, size: 13,
                          color: isSel
                              ? Colors.white.withOpacity(0.90)
                              : slotFg),
                      const SizedBox(width: 6),
                      Text(_fmt(t), style: GoogleFonts.dmSans(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : slotFg)),
                      if (isAppt && !isSel) ...[
                        const SizedBox(width: 5),
                        Container(width: 6, height: 6,
                            decoration: BoxDecoration(
                                color: orange, shape: BoxShape.circle)),
                      ],
                    ]),
                  ),
                );
              }).toList(),
            ),
          )),
      ]),
    );
  }

  Widget _dot(Color color) => Container(
    width: 9, height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  RING PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color  accent;
  const _RingPainter(this.progress, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    final bg = Paint()
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color      = Colors.white.withOpacity(0.15)
      ..strokeCap  = StrokeCap.round;
    final fg = Paint()
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap  = StrokeCap.round
      ..shader     = LinearGradient(
          colors: [accent, const Color(0xFF2ECC96)]).createShader(
          Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        -math.pi / 2, 2 * math.pi * progress.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent;
}
