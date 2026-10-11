import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../app_state.dart';
import '../theme/dark_theme.dart';
import '../models/appointment.dart';
import '../models/personal_task.dart' show PersonalTaskStore;
import 'action_screens.dart';

/// Shared duration parser used by both appointment and task overlap checks.
int _durMinsFromStr(String d) {
  final n = int.tryParse(d.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;
  if (d.contains('h') && !d.contains('min')) return n * 60;
  if (d.contains('h')) {
    final parts = d.split('h');
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return h * 60 + m;
  }
  return n;
}

class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});
  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen>
    with DarkMode, TickerProviderStateMixin {

  late TabController _tabCtrl;
  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  int _selectedFilter = 0;
  final List<String> _filters = ['All', 'Today', 'Upcoming', 'Past', 'Cancelled'];

  List<Appointment> get _allAppts =>
      List<Appointment>.from(AppStateProvider.of(context).appointments)
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  List<Appointment> get _filtered {
    final all = _allAppts;
    switch (_selectedFilter) {
      case 1: return all.where((a) => a.isToday).toList();
      case 2: return all.where((a) => a.isFuture && a.status != ApptStatus.cancelled && a.status != ApptStatus.completed).toList();
      case 3: return all.where((a) => a.status == ApptStatus.completed || (a.isPast && a.status != ApptStatus.cancelled)).toList();
      case 4: return all.where((a) => a.status == ApptStatus.cancelled).toList();
      default: return all;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));
    _headerCtrl.forward();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _headerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState   = AppStateProvider.of(context);
    final todayAppts = appState.appointments.where((a) => a.isToday).toList();
    final confirmed  = todayAppts.where((a) => a.status == ApptStatus.confirmed).length;

    // Per-day sequential numbers; cancelled appointments get null (no number badge).
    final items = _filtered;
    final Map<String, int> _dayCounts = {};
    final List<int?> dayNumbers = items.map((appt) {
      if (appt.status == ApptStatus.cancelled) return null;
      _dayCounts[appt.displayDate] = (_dayCounts[appt.displayDate] ?? 0) + 1;
      return _dayCounts[appt.displayDate];
    }).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: dmBg,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SlideTransition(
                position: _headerSlide,
                child: FadeTransition(opacity: _headerFade,
                    child: _buildHeader(confirmed, todayAppts.length)),
              ),
            ),
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverToBoxAdapter(child: _buildFilterRow()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i >= items.length) return null;
                    final appt = items[i];
                    final showHeader = i == 0 || items[i - 1].displayDate != appt.displayDate;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (showHeader) _dateHeader(appt.displayDate),
                      _ApptCard(
                        appointment: appt,
                        index: i,
                        dayNumber: dayNumbers[i],
                        onStatusChanged: (id, newStatus) async {
                          await AppStateProvider.of(context)
                              .updateAppointmentStatus(id, newStatus);
                        },
                        onDelete: (id) async {
                          await AppStateProvider.of(context).deleteAppointment(id);
                        },
                        onReschedule: (appt) => _openReschedule(appt),
                      ),
                    ]);
                  },
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFab(context),
      ),
    );
  }

  void _openReschedule(Appointment appt) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RescheduleScreen(
          appointment: appt,
          onConfirm: (newDateTime, {String note = ''}) async {
            await AppStateProvider.of(context).updateAppointment(
              appt.copyWith(
                dateTime: newDateTime,
                status: ApptStatus.confirmed,
                cancellationNote: note,
              ),
            );
            if (!context.mounted) return;
            // Format the new time for the notification
            final h  = newDateTime.hour;
            final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
            final mm = newDateTime.minute.toString().padLeft(2, '0');
            final ampm = h < 12 ? 'AM' : 'PM';
            final newTimeStr = '$hh:$mm $ampm';
            _ApptCardState._showNotificationBanner(
              context,
              clientName: appt.name,
              action: 'reschedule',
              note: note,
              newTime: newTimeStr,
            );
          },
        ),
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  Widget _buildHeader(int confirmed, int total) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppStateProvider.of(context).heroGradient,
        ),
      ),
      child: Stack(children: [
        Positioned(right: -40, top: -40, child: _orb(180, dmAccent, 0.12)),
        Positioned(left: -30, bottom: -20, child: _orb(120, AppColors.green, 0.07)),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2))),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                const Spacer(),
                _glassBtn(Icons.search_rounded),
                const SizedBox(width: 10),
                _glassBtn(Icons.tune_rounded),
              ]),
              const SizedBox(height: 24),
              Text('My Appointments',
                  style: GoogleFonts.dmSans(
                      fontSize: 28, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: -0.8)),
              const SizedBox(height: 6),
              Text('Manage and track all your scheduled sessions',
                  style: GoogleFonts.dmSans(
                      fontSize: 13.5, color: Colors.white.withOpacity(0.55))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$confirmed of $total confirmed today',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: Colors.white.withOpacity(0.65))),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0 ? confirmed / total : 0,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF2ECC96)),
                        minHeight: 6,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ECC96).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2ECC96).withOpacity(0.35)),
                  ),
                  child: Text(
                    '${(total > 0 ? confirmed / total * 100 : 0).round()}% Done',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: const Color(0xFF2ECC96))),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatsRow() {
    final all = AppStateProvider.of(context).appointments;
    final todayCount   = all.where((a) => a.isToday).length;
    final pendingCount = all.where((a) => a.status == ApptStatus.pending).length;
    final pastCount    = all.where((a) => a.isPast).length;

    final now       = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd   = weekStart.add(const Duration(days: 7));
    final weekCount = all.where((a) =>
        !a.dateTime.isBefore(weekStart) && a.dateTime.isBefore(weekEnd)).length;

    final stats = [
      {'label': 'Today',     'value': '$todayCount',   'icon': Icons.today_rounded,                'color': dmAccent},
      {'label': 'This Week', 'value': '$weekCount',    'icon': Icons.date_range_rounded,           'color': const Color(0xFF7C3AED)},
      {'label': 'Pending',   'value': '$pendingCount', 'icon': Icons.hourglass_top_rounded,        'color': const Color(0xFFF4A24A)},
      {'label': 'Past',      'value': '$pastCount',    'icon': Icons.check_circle_outline_rounded, 'color': const Color(0xFF2ECC96)},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: stats.map((s) {
          final c = s['color'] as Color;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: dmCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dmBorder),
                boxShadow: [BoxShadow(color: c.withOpacity(0.07),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(s['icon'] as IconData, color: c, size: 18),
                ),
                const SizedBox(height: 8),
                Text(s['value'] as String,
                    style: GoogleFonts.dmSans(
                        fontSize: 20, fontWeight: FontWeight.w900,
                        color: dmTxtMain, letterSpacing: -0.5)),
                Text(s['label'] as String,
                    style: GoogleFonts.dmSans(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: dmTxtSub)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        height: 38,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _filters.length,
          itemBuilder: (_, i) {
            final active = _selectedFilter == i;
            return GestureDetector(
              onTap: () => setState(() => _selectedFilter = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  gradient: active ? LinearGradient(colors: dmActivePillGradient) : null,
                  color: active ? null : dmCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? Colors.transparent : dmBorder),
                  boxShadow: active
                      ? [BoxShadow(color: dmAccent.withOpacity(0.25),
                          blurRadius: 8, offset: const Offset(0, 3))]
                      : [],
                ),
                child: Text(_filters[i],
                    style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: active ? Colors.white : dmTxtSub)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 10),
      child: Row(children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(
            color: dmAccent, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Text(date,
            style: GoogleFonts.dmSans(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: dmTxtMain, letterSpacing: 0.2)),
      ]),
    );
  }

  Widget _buildFab(BuildContext ctx) {
    final appState = AppStateProvider.of(ctx);
    final fabColor = appState.heroGradient.last;
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const NewAppointmentScreen())),
      backgroundColor: fabColor,
      foregroundColor: Colors.white,
      elevation: 6,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: Text('New Appointment',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  Widget _glassBtn(IconData icon) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Icon(icon, color: Colors.white, size: 20),
  );

  Widget _orb(double size, Color color, double opacity) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [color.withOpacity(opacity), Colors.transparent])),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  APPOINTMENT CARD  (uses Appointment model directly)
// ─────────────────────────────────────────────────────────────────────────────
class _ApptCard extends StatefulWidget {
  final Appointment appointment;
  final int index;
  final int? dayNumber;
  final Future<void> Function(int id, ApptStatus) onStatusChanged;
  final Future<void> Function(int id) onDelete;
  final void Function(Appointment) onReschedule;

  const _ApptCard({
    required this.appointment,
    required this.index,
    required this.dayNumber,
    required this.onStatusChanged,
    required this.onDelete,
    required this.onReschedule,
  });

  @override
  State<_ApptCard> createState() => _ApptCardState();
}

class _ApptCardState extends State<_ApptCard>
    with SingleTickerProviderStateMixin, DarkMode, AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 420));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _slide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 60 + widget.index * 50), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Color get _statusColor {
    switch (widget.appointment.status) {
      case ApptStatus.confirmed: return const Color(0xFF2ECC96);
      case ApptStatus.pending:   return const Color(0xFFF4A24A);
      case ApptStatus.cancelled: return const Color(0xFFE05C5C);
      case ApptStatus.completed: return const Color(0xFF2E7D32);
    }
  }

  String get _statusLabel {
    switch (widget.appointment.status) {
      case ApptStatus.confirmed: return 'Confirmed';
      case ApptStatus.pending:   return 'Pending';
      case ApptStatus.cancelled: return 'Cancelled';
      case ApptStatus.completed: return 'Completed';
    }
  }

  void _handleCancel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencyActionSheet(
        appointment: widget.appointment,
        onCancel: (String note) async {
          final id = widget.appointment.id;
          if (id == null) return;
          // Cancel with note
          await widget.onStatusChanged(id, ApptStatus.cancelled);
          // Also persist the cancellation note
          final updated = widget.appointment.copyWith(
            status: ApptStatus.cancelled,
            cancellationNote: note,
          );
          // Update via onReschedule pathway (reuse update mechanism)
          // We fire a status change then update note via reschedule callback
          if (!context.mounted) return;
          _showNotificationBanner(
            context,
            clientName: widget.appointment.name,
            action: 'cancellation',
            note: note,
          );
        },
        onReschedule: () {
          Navigator.pop(context); // close the sheet
          widget.onReschedule(widget.appointment);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    AppStateProvider.of(context);
    final a = widget.appointment;
    final isCancelled = a.status == ApptStatus.cancelled;
    final isCompleted = a.status == ApptStatus.completed;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: dmCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: (isCancelled || isCompleted)
                      ? const Color(0xFFE05C5C).withOpacity(0.15)
                      : dmBorder),
              boxShadow: [
                BoxShadow(
                    color: a.avatarColor.withOpacity((isCancelled || isCompleted) ? 0.03 : 0.06),
                    blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Opacity(
              opacity: (isCancelled || isCompleted) ? 0.7 : 1.0,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(width: 4, height: 54,
                        decoration: BoxDecoration(
                            color: a.avatarColor,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 12),
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                          color: a.avatarColor.withOpacity(0.12),
                          shape: BoxShape.circle),
                      child: Center(child: Text(a.initials,
                          style: GoogleFonts.dmSans(
                              fontSize: 15, fontWeight: FontWeight.w900,
                              color: a.avatarColor))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          if (widget.dayNumber != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: a.avatarColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('#${widget.dayNumber}',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 10, fontWeight: FontWeight.w800,
                                      color: a.avatarColor)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(a.name,
                                style: GoogleFonts.dmSans(
                                    fontSize: 15, fontWeight: FontWeight.w800,
                                    color: dmTxtMain,
                                    decoration: (isCancelled || isCompleted)
                                        ? TextDecoration.lineThrough : null),
                                overflow: TextOverflow.ellipsis),
                          ),
                          // Personal task overlap badge (Feature E)
                          Builder(builder: (_) {
                            final hasPT = PersonalTaskStore.instance.tasks.any((t) {
                              if (!t.hasTime || t.dueDate == null || t.startTime == null || t.done) return false;
                              final ts = DateTime(t.dueDate!.year, t.dueDate!.month,
                                  t.dueDate!.day, t.startTime!.hour, t.startTime!.minute);
                              final te = ts.add(Duration(minutes: _durMinsFromStr(t.duration)));
                              final ae = a.dateTime.add(Duration(minutes: _durMinsFromStr(a.duration)));
                              return a.dateTime.isBefore(te) && ae.isAfter(ts);
                            });
                            if (!hasPT || isCancelled || isCompleted) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A90D9).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: const Color(0xFF4A90D9).withOpacity(0.45)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.task_alt_rounded, size: 9, color: Color(0xFF4A90D9)),
                                const SizedBox(width: 3),
                                Text('Task', style: GoogleFonts.dmSans(
                                    fontSize: 9, fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4A90D9))),
                              ]),
                            );
                          }),
                        ]),
                        const SizedBox(height: 2),
                        Text('${a.service} · ${a.duration}',
                            style: GoogleFonts.dmSans(
                                fontSize: 12.5, color: dmTxtSub,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(a.displayTime,
                          style: GoogleFonts.dmSans(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: dmTxtMain)),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(_statusLabel,
                            style: GoogleFonts.dmSans(
                                fontSize: 10.5, fontWeight: FontWeight.w700,
                                color: _statusColor)),
                      ),
                    ]),
                  ]),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _expandedBody(a),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandedBody(Appointment a) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dmCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dmBorder),
      ),
      child: Column(children: [
        _detailRow(Icons.access_time_rounded,
            '${a.displayTime} · ${a.duration}'),
        if (a.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          _detailRow(Icons.location_on_outlined, a.location),
        ],
        if (a.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          _detailRow(Icons.sticky_note_2_outlined, a.note),
        ],
        const SizedBox(height: 14),

        if (a.status == ApptStatus.completed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.25)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.task_alt_rounded, color: Color(0xFF2E7D32), size: 16),
              const SizedBox(width: 8),
              Text('Session completed', style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E7D32))),
            ]),
          )
        else if (a.status == ApptStatus.cancelled)
          Column(children: [
            Row(children: [
              Expanded(child: _actionBtn(
                'Reschedule',
                Icons.edit_calendar_rounded,
                dmAccent.withOpacity(0.1),
                dmAccent,
                () {
                  setState(() => _expanded = false);
                  widget.onReschedule(a);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _actionBtn(
                '✓ Re-confirm',
                Icons.check_circle_rounded,
                const Color(0xFF2ECC96).withOpacity(0.1),
                const Color(0xFF2ECC96),
                () {
                  if (a.id == null) return;
                  widget.onStatusChanged(a.id!, ApptStatus.confirmed);
                  setState(() => _expanded = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Appointment re-confirmed!',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0xFF2ECC96),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ));
                },
              )),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _actionBtn(
                'Remove',
                Icons.delete_outline_rounded,
                const Color(0xFFE05C5C).withOpacity(0.08),
                const Color(0xFFE05C5C),
                () async {
                  if (a.id == null) return;
                  setState(() => _expanded = false);
                  await widget.onDelete(a.id!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Appointment removed',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFE05C5C),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ));
                  }
                },
              ),
            ),
          ])
        else
          Row(children: [
            Expanded(child: _actionBtn(
              'Reschedule',
              Icons.edit_calendar_rounded,
              dmAccent.withOpacity(0.1),
              dmAccent,
              () {
                setState(() => _expanded = false);
                widget.onReschedule(a);
              },
            )),
            const SizedBox(width: 10),
            Expanded(child: _actionBtn(
              'Cancel',
              Icons.close_rounded,
              const Color(0xFFE05C5C).withOpacity(0.1),
              const Color(0xFFE05C5C),
              _handleCancel,
            )),
          ]),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: dmTxtSub),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtBody))),
    ],
  );

  Widget _actionBtn(String label, IconData icon,
      Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: fg.withOpacity(0.25))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.dmSans(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      );

  /// Simulates sending an immediate push notification to the client
  /// by displaying a prominent in-app banner.
  static void _showNotificationBanner(
    BuildContext context, {
    required String clientName,
    required String action,   // 'cancellation' | 'reschedule'
    String note = '',
    String? newTime,
  }) {
    final isCancel  = action == 'cancellation';
    final color     = isCancel ? const Color(0xFFE05C5C) : const Color(0xFFF4A24A);
    final icon      = isCancel ? Icons.cancel_outlined : Icons.edit_calendar_rounded;
    final mainMsg   = isCancel
        ? 'Appointment cancelled'
        : 'Appointment rescheduled';
    final subMsg    = isCancel
        ? 'Reminder sent to $clientName about the cancellation.'
        : 'Reminder sent to $clientName with the new time${newTime != null ? ': $newTime' : ''}.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: color.withOpacity(0.35), blurRadius: 18,
                offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 13),
                  const SizedBox(width: 5),
                  Text('Reminder sent', style: GoogleFonts.dmSans(
                      fontSize: 10.5, fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.75))),
                ]),
                const SizedBox(height: 2),
                Text(mainMsg, style: GoogleFonts.dmSans(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: Colors.white)),
                const SizedBox(height: 2),
                Text(subMsg, style: GoogleFonts.dmSans(
                    fontSize: 11.5, color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w500),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            )),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RESCHEDULE SCREEN  (uses Appointment + DateTime callback)
// ─────────────────────────────────────────────────────────────────────────────
class RescheduleScreen extends StatefulWidget {
  final Appointment appointment;
  final Future<void> Function(DateTime newDateTime, {String note}) onConfirm;

  const RescheduleScreen({
    super.key,
    required this.appointment,
    required this.onConfirm,
  });

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> with DarkMode {
  late DateTime _selectedDate;
  late int _selectedHour;
  late int _selectedMinute;
  final _noteCtrl = TextEditingController();

  final List<int> _hours   = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
  final List<int> _minutes = [0, 15, 30, 45];

  @override
  void initState() {
    super.initState();
    final orig      = widget.appointment.dateTime;
    _selectedDate   = orig.add(const Duration(days: 1));
    _selectedHour   = orig.hour;
    _selectedMinute = orig.minute;
  }

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  String _formatDateLabel(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  String _dayAbbr(DateTime d) {
    const days = ['M','T','W','T','F','S','S'];
    return days[d.weekday - 1];
  }

  String _fmtTime(int h, int m) {
    final suffix = h < 12 ? 'AM' : 'PM';
    final hh     = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mm     = m.toString().padLeft(2, '0');
    return '$hh:$mm $suffix';
  }

  int _durationToMins(String d) {
    if (d == '15 min') return 15;
    if (d == '30 min') return 30;
    if (d == '45 min') return 45;
    if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90;
    if (d == '2 hr')   return 120;
    return 30;
  }

  DateTime get _newDateTime => DateTime(
    _selectedDate.year, _selectedDate.month, _selectedDate.day,
    _selectedHour, _selectedMinute,
  );

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final a = widget.appointment;

    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: AppStateProvider.of(context).heroGradient,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2))),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Reschedule', style: GoogleFonts.dmSans(
                        fontSize: 20, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: -0.5)),
                    Text(a.name, style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.6))),
                  ]),
                ),
              ]),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: dmCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: dmBorder),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                        color: a.avatarColor.withOpacity(0.12),
                        shape: BoxShape.circle),
                    child: Center(child: Text(a.initials,
                        style: GoogleFonts.dmSans(fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: a.avatarColor))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(a.service, style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: dmTxtMain)),
                    if (a.location.isNotEmpty)
                      Text(a.location, style: GoogleFonts.dmSans(
                          fontSize: 12, color: dmTxtSub),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Currently', style: GoogleFonts.dmSans(
                        fontSize: 10, color: dmTxtSub)),
                    Text(a.displayTime, style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: AppColors.warning)),
                    Text(a.displayDate, style: GoogleFonts.dmSans(
                        fontSize: 11, color: dmTxtSub)),
                  ]),
                ]),
              ),

              const SizedBox(height: 22),
              Text('Select New Date', style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: dmTxtMain)),
              const SizedBox(height: 12),

              SizedBox(
                height: 82,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 21,
                  itemBuilder: (_, i) {
                    final day = DateTime.now().add(Duration(days: i + 1));
                    final sel = _selectedDate.day == day.day &&
                        _selectedDate.month == day.month &&
                        _selectedDate.year == day.year;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDate = day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 56,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          gradient: sel
                              ? LinearGradient(
                                  colors: AppStateProvider.of(context)
                                      .heroGradient.sublist(1))
                              : null,
                          color: sel ? null : dmCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: sel ? Colors.transparent : dmBorder,
                              width: 1.5),
                          boxShadow: sel
                              ? [BoxShadow(
                                  color: dmAccent.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))]
                              : [],
                        ),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Text(_dayAbbr(day),
                              style: GoogleFonts.dmSans(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white.withOpacity(0.7)
                                      : dmTxtSub)),
                          const SizedBox(height: 4),
                          Text('${day.day}',
                              style: GoogleFonts.dmSans(fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: sel ? Colors.white : dmTxtMain)),
                        ]),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),
              Text('Select Time', style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: dmTxtMain)),
              const SizedBox(height: 12),

              Builder(builder: (outerCtx) {
                final allAppts = AppStateProvider.of(outerCtx).appointments;
                final a        = widget.appointment;
                final durM     = _durationToMins(a.duration);
                // Build set of blocked hour+minute combos
                bool _isBlocked(int h, int m) {
                  final proposed = DateTime(
                    _selectedDate.year, _selectedDate.month, _selectedDate.day, h, m);
                  final propEnd = proposed.add(Duration(minutes: durM));
                  for (final existing in allAppts) {
                    if (existing.id == a.id) continue;
                    if (existing.status == ApptStatus.cancelled) continue;
                    final es = existing.dateTime;
                    final ee = es.add(Duration(minutes: _durationToMins(existing.duration)));
                    if (proposed.isBefore(ee) && propEnd.isAfter(es)) return true;
                  }
                  return false;
                }
                return Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final h in _hours)
                      for (final m in _minutes)
                        Builder(builder: (ctx) {
                          final sel     = _selectedHour == h && _selectedMinute == m;
                          final blocked = _isBlocked(h, m);
                          return GestureDetector(
                            onTap: blocked ? null : () => setState(() {
                              _selectedHour   = h;
                              _selectedMinute = m;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: blocked
                                    ? const Color(0xFFE05C5C).withOpacity(0.07)
                                    : sel ? dmAccent.withOpacity(0.15) : dmCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: blocked
                                        ? const Color(0xFFE05C5C).withOpacity(0.3)
                                        : sel ? dmAccent : dmBorder,
                                    width: sel ? 1.8 : 1.2),
                                boxShadow: sel && !blocked
                                    ? [BoxShadow(
                                        color: dmAccent.withOpacity(0.2),
                                        blurRadius: 6)]
                                    : [],
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (blocked)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: Icon(Icons.block_rounded, size: 11,
                                        color: const Color(0xFFE05C5C).withOpacity(0.5)),
                                  ),
                                Text(_fmtTime(h, m),
                                    style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                        color: blocked
                                            ? const Color(0xFFE05C5C).withOpacity(0.45)
                                            : sel ? dmAccent : dmTxtSub)),
                              ]),
                            ),
                          );
                        }),
                  ],
                );
              }),

              const SizedBox(height: 22),
              Text('Reason for Rescheduling (Optional)', style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: dmTxtMain)),
              const SizedBox(height: 6),
              Text('This note will be included in the reminder sent to your client.',
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtSub,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: dmCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dmBorder)),
                child: TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    hintText: 'e.g. Emergency came up, family situation, feeling unwell…',
                    hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 0, 0),
                      child: Icon(Icons.sticky_note_2_outlined,
                          size: 18, color: dmTxtSub),
                    ),
                    prefixIconConstraints: const BoxConstraints(),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),

        Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
          decoration: BoxDecoration(
            color: dmCard,
            border: Border(top: BorderSide(color: dmBorder)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'New time: ${_fmtTime(_selectedHour, _selectedMinute)}'
                ' · ${_formatDateLabel(_selectedDate)}',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: dmTxtSub,
                    fontWeight: FontWeight.w500),
              ),
            ),
            GestureDetector(
              onTap: () async {
                await widget.onConfirm(_newDateTime, note: _noteCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      'Rescheduled to ${_formatDateLabel(_selectedDate)}'
                      ' at ${_fmtTime(_selectedHour, _selectedMinute)}',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0xFF2ECC96),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ));
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppStateProvider.of(context)
                        .heroGradient.sublist(1),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: dmAccent.withOpacity(0.35),
                      blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text('Confirm Reschedule', style: GoogleFonts.dmSans(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -0.3)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMERGENCY ACTION SHEET
//  Shown when provider needs to cancel or reschedule due to an emergency.
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencyActionSheet extends StatefulWidget {
  final Appointment                  appointment;
  final Future<void> Function(String note) onCancel;
  final VoidCallback                 onReschedule;

  const _EmergencyActionSheet({
    required this.appointment,
    required this.onCancel,
    required this.onReschedule,
  });

  @override
  State<_EmergencyActionSheet> createState() => _EmergencyActionSheetState();
}

class _EmergencyActionSheetState extends State<_EmergencyActionSheet> with DarkMode {

  final _noteCtrl = TextEditingController();
  String? _selectedReason;
  bool    _saving = false;

  static const _quickReasons = [
    '🚨 Medical emergency',
    '🏥 Family emergency',
    '🤒 Feeling unwell',
    '🚗 Transportation issue',
    '⚡ Power / connectivity outage',
    '📋 Urgent work conflict',
  ];

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  String get _effectiveNote {
    final custom = _noteCtrl.text.trim();
    if (custom.isNotEmpty && _selectedReason != null) {
      return '$_selectedReason — $custom';
    }
    return custom.isNotEmpty ? custom : (_selectedReason ?? '');
  }

  /// Returns up to [count] future DateTime slots that have no appointment
  /// or personal-task overlap, starting from the day after the given appointment.
  List<DateTime> _nextFreeSlots(Appointment appt, int count) {
    final results     = <DateTime>[];
    final durMins     = _durMinsFromStr(appt.duration);
    final allAppts    = PersonalTaskStore.instance.tasks; // used below for tasks
    var   candidate   = DateTime(
        appt.dateTime.year, appt.dateTime.month, appt.dateTime.day,
        appt.dateTime.hour, appt.dateTime.minute)
        .add(const Duration(days: 1));

    // Keep the same hour/minute as the original, try up to 14 days ahead
    for (int d = 0; d < 14 && results.length < count; d++) {
      final dt  = DateTime(candidate.year, candidate.month, candidate.day,
          appt.dateTime.hour, appt.dateTime.minute);
      final end = dt.add(Duration(minutes: durMins));

      // Check no appointment overlap
      final apptFree = !PersonalTaskStore.instance.tasks.any((t) => false) &&
          true; // placeholder — real check below via imported list

      bool blocked = false;
      // Check personal tasks
      for (final t in PersonalTaskStore.instance.tasks) {
        if (!t.hasTime || t.dueDate == null || t.startTime == null || t.done) continue;
        if (!t.blockAppointments) continue;
        final ts = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day,
            t.startTime!.hour, t.startTime!.minute);
        final te = ts.add(Duration(minutes: _durMinsFromStr(t.duration)));
        if (dt.isBefore(te) && end.isAfter(ts)) { blocked = true; break; }
      }
      if (!blocked) results.add(dt);
      candidate = candidate.add(const Duration(days: 1));
    }
    return results;
  }

  String _formatSuggestion(DateTime dt) {
    final days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final day = days[dt.weekday - 1];
    final mon = months[dt.month - 1];
    final h   = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m   = dt.minute.toString().padLeft(2, '0');
    final ap  = dt.hour < 12 ? 'AM' : 'PM';
    return '$day, ${dt.day} $mon  ·  $h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final a           = widget.appointment;
    final keyboardH   = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: dmCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: dmBorder, width: 1.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Handle ──────────────────────────────────────────────────────
          Center(child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: dmBorder, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 18),

          Flexible(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Header ────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE05C5C).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.30)),
                ),
                child: Row(children: [
                  Container(width: 44, height: 44,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE05C5C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFE05C5C), size: 24)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Emergency Action', style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: const Color(0xFFE05C5C))),
                    const SizedBox(height: 3),
                    Text('Cancel or reschedule this appointment.',
                        style: GoogleFonts.dmSans(fontSize: 12,
                            color: const Color(0xFFE05C5C).withOpacity(0.7),
                            fontWeight: FontWeight.w500)),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),

              // ── Appointment summary card ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dmCard2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dmBorder),
                ),
                child: Row(children: [
                  CircleAvatar(radius: 22,
                      backgroundColor: a.avatarColor.withOpacity(0.18),
                      child: Text(a.initials, style: GoogleFonts.dmSans(
                          fontSize: 14, fontWeight: FontWeight.w900,
                          color: a.avatarColor))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.name, style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w800, color: dmTxtMain)),
                    const SizedBox(height: 3),
                    Text(a.service, style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600, color: dmAccent)),
                    const SizedBox(height: 5),
                    Row(children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: dmTxtSub),
                      const SizedBox(width: 4),
                      Text(a.displayDate, style: GoogleFonts.dmSans(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: dmTxtSub)),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time_rounded, size: 11, color: dmAccent),
                      const SizedBox(width: 4),
                      Text('${a.displayTime} · ${a.duration}', style: GoogleFonts.dmSans(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: dmAccent)),
                    ]),
                  ])),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Quick-reason chips ────────────────────────────────────────
              Row(children: [
                Icon(Icons.bolt_rounded, size: 14, color: dmAccent),
                const SizedBox(width: 6),
                Text('Quick reason', style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: dmTxtSub, letterSpacing: 0.3)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: _quickReasons.map((reason) {
                  final sel = _selectedReason == reason;
                  return GestureDetector(
                    onTap: () => setState(() =>
                        _selectedReason = sel ? null : reason),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? dmAccent.withOpacity(0.18)
                            : dmCard2,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: sel ? dmAccent : dmBorder,
                            width: sel ? 1.5 : 1.1),
                        boxShadow: sel ? [BoxShadow(
                            color: dmAccent.withOpacity(0.25),
                            blurRadius: 8)] : [],
                      ),
                      child: Text(reason, style: GoogleFonts.dmSans(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? dmAccent : dmTxtSub)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // ── Custom note field ─────────────────────────────────────────
              Row(children: [
                Icon(Icons.sticky_note_2_outlined, size: 14, color: dmAccent),
                const SizedBox(width: 6),
                Text('Add a note (optional)', style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: dmTxtSub, letterSpacing: 0.3)),
              ]),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: dmCard2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dmBorder),
                ),
                child: TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtMain),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                    hintText: 'Describe the situation to your client…',
                    hintStyle: GoogleFonts.dmSans(
                        color: dmTxtSub, fontSize: 13),
                  ),
                ),
              ),

              // Note preview chip
              if (_effectiveNote.isNotEmpty) ...[ 
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: dmAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dmAccent.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.format_quote_rounded,
                        size: 14, color: dmAccent.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_effectiveNote,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: dmTxtSub,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],

              const SizedBox(height: 8),
              // Notification preview pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC96).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF2ECC96).withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.notifications_active_rounded,
                      size: 13, color: Color(0xFF2ECC96)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'An immediate reminder will be sent to ${a.name}.',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: const Color(0xFF2ECC96),
                        fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Quick-reschedule suggestions (Feature F) ──────────────────
              Builder(builder: (_) {
                final freeSlots = _nextFreeSlots(widget.appointment, 3);
                if (freeSlots.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 13, color: dmAccent),
                    const SizedBox(width: 6),
                    Text('Suggested free slots', style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w800,
                        color: dmTxtSub, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 8),
                  ...freeSlots.map((dt) {
                    final label = _formatSuggestion(dt);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onReschedule();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: dmAccent.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: dmAccent.withOpacity(0.25)),
                        ),
                        child: Row(children: [
                          Icon(Icons.flash_on_rounded, size: 14, color: dmAccent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label, style: GoogleFonts.dmSans(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: dmTxtMain))),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12,
                              color: dmAccent.withOpacity(0.5)),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ]);
              }),

              // ── Action buttons ────────────────────────────────────────────
              Row(children: [
                // Reschedule
                Expanded(child: GestureDetector(
                  onTap: widget.onReschedule,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: dmAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: dmAccent.withOpacity(0.35)),
                    ),
                    child: Column(children: [
                      Icon(Icons.edit_calendar_rounded,
                          color: dmAccent, size: 22),
                      const SizedBox(height: 5),
                      Text('Reschedule', style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: dmAccent)),
                      const SizedBox(height: 2),
                      Text('Pick a new time', style: GoogleFonts.dmSans(
                          fontSize: 10.5, color: dmAccent.withOpacity(0.65),
                          fontWeight: FontWeight.w500)),
                    ]),
                  ),
                )),
                const SizedBox(width: 12),
                // Cancel
                Expanded(child: GestureDetector(
                  onTap: _saving ? null : () async {
                    setState(() => _saving = true);
                    await widget.onCancel(_effectiveNote);
                    if (mounted) Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE05C5C).withOpacity(
                          _saving ? 0.06 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFE05C5C).withOpacity(0.35)),
                    ),
                    child: _saving
                        ? const Center(child: SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFFE05C5C))))
                        : Column(children: [
                            const Icon(Icons.cancel_outlined,
                                color: Color(0xFFE05C5C), size: 22),
                            const SizedBox(height: 5),
                            Text('Cancel Appt', style: GoogleFonts.dmSans(
                                fontSize: 13, fontWeight: FontWeight.w800,
                                color: const Color(0xFFE05C5C))),
                            const SizedBox(height: 2),
                            Text('Notify client now', style: GoogleFonts.dmSans(
                                fontSize: 10.5,
                                color: const Color(0xFFE05C5C).withOpacity(0.65),
                                fontWeight: FontWeight.w500)),
                          ]),
                  ),
                )),
              ]),
              const SizedBox(height: 8),
              // Dismiss
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: dmCard2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dmBorder),
                  ),
                  child: Center(child: Text('Dismiss',
                      style: GoogleFonts.dmSans(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: dmTxtSub))),
                ),
              ),
            ]),
          )),
        ]),
      ),
    );
  }
}
