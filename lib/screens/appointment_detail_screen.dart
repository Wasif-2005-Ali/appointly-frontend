import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import '../models/appointment.dart';
import '../models/personal_task.dart' show PersonalTaskStore;
import 'incoming_requests_screen.dart';
import 'my_appointments_screen.dart' show RescheduleScreen;

class RequestDetailScreen extends StatefulWidget {
  final IncomingRequest request;
  const RequestDetailScreen({super.key, required this.request});
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}
class _RequestDetailScreenState extends State<RequestDetailScreen> with DarkMode {
  late IncomingRequest _req;
  @override
  void initState() { super.initState(); _req = widget.request; }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final isPending = _req.status == RequestStatus.pending;
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _buildHero(),
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _c(child: Row(children: [
              Stack(children: [
                Container(decoration: BoxDecoration(shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _req.avatarColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0,4))]),
                  child: CircleAvatar(radius: 32, backgroundColor: _req.avatarColor.withOpacity(dark ? 0.2 : 0.15),
                      child: Text(_req.initials, style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900, color: _req.avatarColor)))),
                if (_req.isNew && isPending) Positioned(top: 0, right: 0, child: Container(width: 14, height: 14,
                    decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle, border: Border.all(color: dmCard, width: 2)))),
              ]),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_req.clientName, style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w900,
                    color: dmTxtMain, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(_req.service, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: dmAccent)),
                const SizedBox(height: 6),
                _statusBadge(),
              ])),
            ])),
            const SizedBox(height: 14),
            _c(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Appointment Details', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: dmTxtMain)),
              const SizedBox(height: 14),
              _dRow(Icons.calendar_today_rounded, 'Requested Date', _req.requestedDate, dmTxtMain),
              const SizedBox(height: 12),
              _dRow(Icons.access_time_rounded, 'Requested Time', _req.requestedTime, dmAccent),
              const SizedBox(height: 12),
              _dRow(Icons.medical_services_outlined, 'Service', _req.service, AppColors.green),
              const SizedBox(height: 12),
              _dRow(Icons.schedule_rounded, 'Received', _req.timeAgo, AppColors.warning),
            ])),
            const SizedBox(height: 14),
            _c(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Message from Client', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: dmTxtMain)),
              const SizedBox(height: 14),
              Container(width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dmBorder2)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.format_quote_rounded, color: dmAccent.withOpacity(0.5), size: 20),
                    const SizedBox(width: 6),
                    Text('Client note', style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: dmAccent, letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 10),
                  Text(_req.message, style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtBody, fontWeight: FontWeight.w500, height: 1.6)),
                ])),
            ])),
            if (isPending) ...[
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () { setState(() => _req.status = RequestStatus.declined); Navigator.pop(context); },
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.danger.withOpacity(0.25))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.close_rounded, color: AppColors.danger, size: 18), const SizedBox(width: 8),
                      Text('Decline', style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.danger)),
                    ])),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () {
                    setState(() => _req.status = RequestStatus.accepted);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${_req.clientName}\'s request accepted!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.green, behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
                    Navigator.pop(context);
                  },
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: AppStateProvider.of(context).cardGradient(0)),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: dmTxtMain.withOpacity(0.4), blurRadius: 12, offset: const Offset(0,4))]),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 18), const SizedBox(width: 8),
                      Text('Accept', style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    ])),
                )),
              ]),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _buildHero() => Container(
    decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: AppStateProvider.of(context).heroGradient)),
    child: Stack(children: [
      Positioned(right: -40, top: -40, child: Container(width: 160, height: 160,
          decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [dmAccent.withOpacity(0.1), Colors.transparent])))),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
              child: _glass(child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18))),
          const Spacer(),
          Text('Request Details', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
          const Spacer(),
          _glass(child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20)),
        ]),
      )),
    ]),
  );

  Widget _statusBadge() {
    Color bg, fg; String lbl;
    if (_req.status == RequestStatus.accepted) { bg = AppColors.green.withOpacity(dark ? 0.15 : 0.12); fg = AppColors.green; lbl = 'Accepted'; }
    else if (_req.status == RequestStatus.declined) { bg = AppColors.danger.withOpacity(dark ? 0.15 : 0.1); fg = AppColors.danger; lbl = 'Declined'; }
    else { bg = AppColors.warning.withOpacity(dark ? 0.15 : 0.1); fg = AppColors.warning; lbl = 'Pending'; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withOpacity(0.3))),
        child: Text(lbl, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: fg)));
  }

  Widget _dRow(IconData icon, String label, String value, Color c) => Row(children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
        child: Icon(icon, color: c, size: 18)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: dmTxtSub, letterSpacing: 0.3)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: dmTxtMain)),
    ])),
  ]);

  Widget _c({required Widget child}) => Container(padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05), blurRadius: 16, offset: const Offset(0,4))]),
    child: child);

  Widget _glass({required Widget child, double size = 42}) => Container(
    width: size, height: size, decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Center(child: child));
}

// ─────────────────────────────────────────────────────────────────────────────
//  APPOINTMENT DETAIL SCREEN  (from dashboard schedule tap)
// ─────────────────────────────────────────────────────────────────────────────
class AppointmentDetailScreen extends StatefulWidget {
  final Appointment appointment;
  const AppointmentDetailScreen({super.key, required this.appointment});
  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> with DarkMode {
  late Appointment _appt;

  @override
  void initState() { super.initState(); _appt = widget.appointment; }

  /// Opens the emergency cancel/reschedule sheet — same UX as the appointments list.
  void _showEmergencySheet(AppState appState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelReasonSheet(
        appointment: _appt,
        onCancel: (String note) async {
          final id = _appt.id;
          if (id == null) return;
          await appState.updateAppointmentStatus(id, ApptStatus.cancelled);
          final updated = _appt.copyWith(
              status: ApptStatus.cancelled, cancellationNote: note);
          await appState.updateAppointment(updated);
          if (!mounted) return;
          setState(() => _appt = updated);
          _showNotificationBanner(clientName: _appt.name, note: note);
        },
        onReschedule: () {
          Navigator.pop(context); // close reason sheet
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => RescheduleScreen(
                appointment: _appt,
                onConfirm: (newDt, {String note = ''}) async {
                  final updated = _appt.copyWith(
                      dateTime: newDt,
                      status: ApptStatus.confirmed,
                      cancellationNote: note);
                  await appState.updateAppointment(updated);
                  if (!mounted) return;
                  setState(() => _appt = updated);
                  final h  = newDt.hour == 0 ? 12 : (newDt.hour > 12 ? newDt.hour - 12 : newDt.hour);
                  final m  = newDt.minute.toString().padLeft(2, '0');
                  final ap = newDt.hour < 12 ? 'AM' : 'PM';
                  _showNotificationBanner(
                      clientName: _appt.name,
                      note: note,
                      isReschedule: true,
                      newTime: '$h:$m $ap');
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
        },
      ),
    );
  }

  void _showNotificationBanner({
    required String clientName,
    String note = '',
    bool isReschedule = false,
    String? newTime,
  }) {
    final color   = isReschedule ? const Color(0xFFF4A24A) : const Color(0xFFE05C5C);
    final icon    = isReschedule ? Icons.edit_calendar_rounded : Icons.cancel_outlined;
    final mainMsg = isReschedule ? 'Appointment rescheduled' : 'Appointment cancelled';
    final subMsg  = isReschedule
        ? 'Reminder sent to $clientName with new time${newTime != null ? ': $newTime' : ''}.'
        : 'Reminder sent to $clientName about the cancellation.';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
          boxShadow: [BoxShadow(color: color.withOpacity(0.35),
              blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
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
                fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 2),
            Text(subMsg, style: GoogleFonts.dmSans(
                fontSize: 11.5, color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    ));
  }

  Color get _statusColor {
    switch (_appt.status) {
      case ApptStatus.confirmed: return AppColors.green;
      case ApptStatus.pending:   return AppColors.warning;
      case ApptStatus.cancelled: return AppColors.danger;
      case ApptStatus.completed: return const Color(0xFF2E7D32);
    }
  }
  String get _statusLabel {
    switch (_appt.status) {
      case ApptStatus.confirmed: return 'Confirmed';
      case ApptStatus.pending:   return 'Pending';
      case ApptStatus.cancelled: return 'Cancelled';
      case ApptStatus.completed: return 'Completed';
    }
  }
  IconData get _statusIcon {
    switch (_appt.status) {
      case ApptStatus.confirmed: return Icons.check_circle_rounded;
      case ApptStatus.pending:   return Icons.hourglass_top_rounded;
      case ApptStatus.cancelled: return Icons.cancel_rounded;
      case ApptStatus.completed: return Icons.task_alt_rounded;
    }
  }

  String get _formattedDate {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final d = _appt.dateTime;
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _buildHero(appState),
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(children: [
            // ── Client card ──────────────────────────────────────────────
            _card(child: Row(children: [
              CircleAvatar(radius: 30,
                backgroundColor: _appt.avatarColor.withOpacity(dark ? 0.2 : 0.14),
                child: Text(_appt.initials, style: GoogleFonts.dmSans(
                    fontSize: 17, fontWeight: FontWeight.w900, color: _appt.avatarColor))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_appt.name, style: GoogleFonts.dmSans(
                    fontSize: 20, fontWeight: FontWeight.w900, color: dmTxtMain, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(_appt.service, style: GoogleFonts.dmSans(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: dmAccent)),
              ])),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _statusColor.withOpacity(dark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor.withOpacity(0.35))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_statusIcon, size: 13, color: _statusColor),
                  const SizedBox(width: 5),
                  Text(_statusLabel, style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w800, color: _statusColor)),
                ]),
              ),
            ])),
            const SizedBox(height: 14),
            // ── Details card ─────────────────────────────────────────────
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle('Appointment Details'),
              const SizedBox(height: 14),
              _dRow(Icons.calendar_today_rounded,   'Date',     _formattedDate,         dmAccent),
              const SizedBox(height: 12),
              _dRow(Icons.access_time_rounded,      'Time',     _appt.time,             AppColors.green),
              const SizedBox(height: 12),
              _dRow(Icons.medical_services_outlined,'Service',  _appt.service,          AppColors.warning),
              const SizedBox(height: 12),
              _dRow(Icons.schedule_rounded,         'Duration', _appt.duration,         dmAccent),
              if (_appt.location.isNotEmpty) ...[
                const SizedBox(height: 12),
                _dRow(Icons.location_on_rounded,    'Location', _appt.location,         AppColors.danger),
              ],
            ])),
            if (_appt.note.isNotEmpty) ...[
              const SizedBox(height: 14),
              _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionTitle('Notes'),
                const SizedBox(height: 10),
                Text(_appt.note, style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: dmTxtSub, height: 1.5)),
              ])),
            ],
            const SizedBox(height: 14),
            // ── Action buttons ───────────────────────────────────────────
            if (_appt.status != ApptStatus.cancelled &&
                _appt.status != ApptStatus.completed) ...[ 
              Row(children: [
                Expanded(child: _actionBtn(
                  'Cancel Appt.', Icons.cancel_outlined, AppColors.danger,
                  () => _showEmergencySheet(appState),
                )),
                const SizedBox(width: 10),
                Expanded(child: _actionBtn(
                  'Confirm', Icons.check_circle_outline_rounded, AppColors.green,
                  () async {
                    await appState.updateAppointmentStatus(_appt.id!, ApptStatus.confirmed);
                    setState(() => _appt = _appt.copyWith(status: ApptStatus.confirmed));
                  },
                  filled: _appt.status != ApptStatus.confirmed,
                )),
              ]),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _buildHero(AppState appState) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: appState.heroGradient)),
      child: Stack(children: [
        Positioned(right: -50, top: -50, child: Container(width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [dmAccent.withOpacity(0.15), Colors.transparent])))),
        SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
          child: Row(children: [
            GestureDetector(onTap: () => Navigator.pop(context),
                child: _glass(child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Appointment', style: GoogleFonts.dmSans(
                  fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              Text(_formattedDate, style: GoogleFonts.dmSans(
                  fontSize: 12, color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w500)),
            ])),
          ]),
        )),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: GoogleFonts.dmSans(
      fontSize: 15, fontWeight: FontWeight.w800, color: dmTxtMain, letterSpacing: -0.3));

  Widget _dRow(IconData icon, String label, String value, Color c) => Row(children: [
    Container(width: 40, height: 40, decoration: BoxDecoration(
        color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.withOpacity(0.2))),
        child: Icon(icon, color: c, size: 19)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700,
          color: dmTxtSub, letterSpacing: 0.3)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700,
          color: dmTxtMain)),
    ])),
  ]);

  Widget _actionBtn(String label, IconData icon, Color c, VoidCallback onTap,
      {bool filled = true}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: filled ? LinearGradient(colors: [c, c.withOpacity(0.75)]) : null,
          color: filled ? null : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? Colors.transparent : c.withOpacity(0.4)),
          boxShadow: filled ? [BoxShadow(color: c.withOpacity(0.3),
              blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: filled ? Colors.white : c),
          const SizedBox(width: 7),
          Text(label, style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w700,
              color: filled ? Colors.white : c)),
        ]),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05),
            blurRadius: 16, offset: const Offset(0, 4))]),
    child: child);

  Widget _glass({required Widget child, double size = 42}) => Container(
    width: size, height: size, decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Center(child: child));
}

// ─────────────────────────────────────────────────────────────────────────────
//  CANCEL REASON SHEET  (reusable inside AppointmentDetailScreen)
// ─────────────────────────────────────────────────────────────────────────────

class _CancelReasonSheet extends StatefulWidget {
  final Appointment                    appointment;
  final Future<void> Function(String)  onCancel;
  final VoidCallback                   onReschedule;
  const _CancelReasonSheet({
    required this.appointment,
    required this.onCancel,
    required this.onReschedule,
  });
  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> with DarkMode {
  final _noteCtrl = TextEditingController();
  String? _selectedReason;
  bool    _sendReminder = true;
  bool    _saving       = false;

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
    if (custom.isNotEmpty && _selectedReason != null) return '$_selectedReason — $custom';
    return custom.isNotEmpty ? custom : (_selectedReason ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final a        = widget.appointment;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    const red      = Color(0xFFE05C5C);
    const green    = Color(0xFF2ECC96);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
        decoration: BoxDecoration(
          color: dmCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: dmBorder, width: 1.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Center(child: Container(margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: dmBorder, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),

          Flexible(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Warning header ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: red.withOpacity(0.30)),
                ),
                child: Row(children: [
                  Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.cancel_outlined, color: red, size: 24)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cancel Appointment', style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w900, color: red)),
                    const SizedBox(height: 3),
                    Text('You can add an optional reason for ${a.name}.',
                        style: GoogleFonts.dmSans(fontSize: 12,
                            color: red.withOpacity(0.7), fontWeight: FontWeight.w500)),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),

              // ── Appointment summary ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dmBorder)),
                child: Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: a.avatarColor.withOpacity(0.18),
                      child: Text(a.initials, style: GoogleFonts.dmSans(
                          fontSize: 14, fontWeight: FontWeight.w900, color: a.avatarColor))),
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

              // ── Quick reason chips ────────────────────────────────────────
              Row(children: [
                Icon(Icons.bolt_rounded, size: 14, color: dmAccent),
                const SizedBox(width: 6),
                Text('Quick reason (optional)', style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: dmTxtSub, letterSpacing: 0.3)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _quickReasons.map((r) {
                final sel = _selectedReason == r;
                return GestureDetector(
                  onTap: () => setState(() => _selectedReason = sel ? null : r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? dmAccent.withOpacity(0.18) : dmCard2,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: sel ? dmAccent : dmBorder,
                          width: sel ? 1.5 : 1.1),
                    ),
                    child: Text(r, style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? dmAccent : dmTxtSub)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 16),

              // ── Custom note ───────────────────────────────────────────────
              Row(children: [
                Icon(Icons.sticky_note_2_outlined, size: 14, color: dmAccent),
                const SizedBox(width: 6),
                Text('Add a note (optional)', style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: dmTxtSub, letterSpacing: 0.3)),
              ]),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: dmCard2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dmBorder)),
                child: TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtMain),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                    hintText: 'Describe the reason to your client…',
                    hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13),
                  ),
                ),
              ),

              // Note preview
              if (_effectiveNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: dmAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dmAccent.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.format_quote_rounded, size: 14,
                        color: dmAccent.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_effectiveNote,
                        style: GoogleFonts.dmSans(fontSize: 12, color: dmTxtSub,
                            fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              // ── Send reminder toggle ──────────────────────────────────────
              GestureDetector(
                onTap: () => setState(() => _sendReminder = !_sendReminder),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _sendReminder
                        ? green.withOpacity(0.09)
                        : dmCard2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _sendReminder
                            ? green.withOpacity(0.40)
                            : dmBorder,
                        width: 1.4),
                  ),
                  child: Row(children: [
                    Container(width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _sendReminder
                              ? green.withOpacity(0.15)
                              : dmCard2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _sendReminder
                              ? green.withOpacity(0.35) : dmBorder),
                        ),
                        child: Icon(Icons.notifications_active_rounded,
                            size: 18,
                            color: _sendReminder ? green : dmTxtSub)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Send reminder to client', style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: _sendReminder ? green : dmTxtMain)),
                      const SizedBox(height: 2),
                      Text(
                        _sendReminder
                            ? '${a.name} will be notified immediately'
                            : 'Client will not be notified',
                        style: GoogleFonts.dmSans(fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: _sendReminder
                                ? green.withOpacity(0.70)
                                : dmTxtSub.withOpacity(0.55)),
                      ),
                    ])),
                    const SizedBox(width: 10),
                    // Toggle switch
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 46, height: 26,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: _sendReminder ? green : dmBorder),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        alignment: _sendReminder
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 20, height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),

              // ── Action buttons ────────────────────────────────────────────
              Row(children: [
                // Reschedule instead
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
                      Icon(Icons.edit_calendar_rounded, color: dmAccent, size: 22),
                      const SizedBox(height: 5),
                      Text('Reschedule', style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w800, color: dmAccent)),
                      const SizedBox(height: 2),
                      Text('Pick a new time', style: GoogleFonts.dmSans(
                          fontSize: 10.5, color: dmAccent.withOpacity(0.65),
                          fontWeight: FontWeight.w500)),
                    ]),
                  ),
                )),
                const SizedBox(width: 12),
                // Confirm cancellation
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
                      color: red.withOpacity(_saving ? 0.05 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: red.withOpacity(0.35)),
                    ),
                    child: _saving
                        ? const Center(child: SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: red)))
                        : Column(children: [
                            const Icon(Icons.cancel_outlined, color: red, size: 22),
                            const SizedBox(height: 5),
                            Text('Cancel Appt', style: GoogleFonts.dmSans(
                                fontSize: 13, fontWeight: FontWeight.w800, color: red)),
                            const SizedBox(height: 2),
                            Text(_sendReminder ? 'Notify client now' : 'No notification',
                                style: GoogleFonts.dmSans(
                                    fontSize: 10.5, color: red.withOpacity(0.65),
                                    fontWeight: FontWeight.w500)),
                          ]),
                  ),
                )),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: dmCard2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: dmBorder)),
                  child: Center(child: Text('Dismiss', style: GoogleFonts.dmSans(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: dmTxtSub))),
                ),
              ),
            ]),
          )),
        ]),
      ),
    );
  }
}
