import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../database/bd_helper.dart';
import '../models/appointment.dart' as appt_model;
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import '../widgets/save_icon_button.dart';
import '../widgets/save_success_overlay.dart';
import 'my_availability_screen.dart';
import '../models/personal_task.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Widget _glassBtn({required Widget child, double size = 42}) => Container(
  width: size, height: size,
  decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.13),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white.withOpacity(0.22))),
  child: Center(child: child),
);

/// Theme-aware gradient header — used by every action screen.
/// Pass [onSave] to show the animated save icon in the top-right corner.
Widget _heroHeader(BuildContext ctx, String title, Color accentColor,
    {Future<void> Function()? onSave, Listenable? changeSignal}) {
  final heroColors = AppStateProvider.of(ctx).heroGradient;
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: heroColors,
    )),
    child: Stack(children: [
      Positioned(right: -50, top: -50,
          child: Container(width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: RadialGradient(
                      colors: [accentColor.withOpacity(0.15), Colors.transparent])))),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
        child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(ctx),
              child: _glassBtn(
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18))),
          const SizedBox(width: 14),
          Expanded(child: Text(title,
              style: GoogleFonts.dmSans(
                  fontSize: 20, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -0.5))),
          // ── Save icon button opposite the title ────────────────────────
          if (onSave != null)
            SaveIconButton(
              onSave: onSave,
              changeSignal: changeSignal,
              foregroundColor: Colors.white,   // always on dark gradient header
            ),
        ]),
      )),
    ]),
  );
}

/// Smooth toggle pill — no tick inside.
Widget _beautyToggle(bool val, Color active, ValueChanged<bool> cb,
    {bool dark = false}) {
  return GestureDetector(
    onTap: () => cb(!val),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: 52, height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: val ? LinearGradient(colors: [active, active.withOpacity(0.7)]) : null,
        color: val ? null : (dark ? const Color(0xFF30363D) : const Color(0xFFDDE5EF)),
        boxShadow: val
            ? [BoxShadow(color: active.withOpacity(0.35), blurRadius: 8,
            offset: const Offset(0, 2))]
            : [],
      ),
      child: Stack(alignment: Alignment.center, children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          left: val ? 26 : 2,
          child: Container(width: 24, height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
                      blurRadius: 5, offset: const Offset(0, 2))])),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  1. NEW APPOINTMENT
// ─────────────────────────────────────────────────────────────────────────────
class NewAppointmentScreen extends StatefulWidget {
  const NewAppointmentScreen({super.key});
  @override
  State<NewAppointmentScreen> createState() => _NewAppointmentState();
}

class _NewAppointmentState extends State<NewAppointmentScreen> with DarkMode {
  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  final _nameCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _service;
  String _selectedDuration = '30 min';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  bool _dateSelected = false;
  bool _timeSelected = false;
  String _locationType = 'At Home';
  final _locationCtrl = TextEditingController();

  final _services = ['Consultation','Deep Tissue Massage','Hair Coloring',
    'Physiotherapy','Skin Care Session','Sports Massage','Nail Art'];

  final _locationTypes = [
    {'label': 'At Home',   'icon': Icons.home_rounded,        'color': const Color(0xFF4A90D9)},
    {'label': 'At Office', 'icon': Icons.business_rounded,    'color': const Color(0xFF2ECC96)},
    {'label': 'Online',    'icon': Icons.videocam_rounded,     'color': const Color(0xFF9333EA)},
    {'label': 'Other',     'icon': Icons.location_on_rounded,  'color': const Color(0xFFF4A24A)},
  ];

  Future<void> _pickDate() async {
    final appState = AppStateProvider.of(context);
    final accent = appState.accent;
    final cardC  = appState.cardBg;
    final bright = appState.themeMode.isDark ? Brightness.dark : Brightness.light;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
          colorScheme: ColorScheme(
            brightness: bright,
            primary: accent,
            onPrimary: Colors.white,
            secondary: accent,
            onSecondary: Colors.white,
            error: Colors.red,
            onError: Colors.white,
            surface: cardC,
            onSurface: appState.txtMain,
          ),
          dialogBackgroundColor: cardC,
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    if (picked != null) setState(() { _selectedDate = picked; _dateSelected = true; });
  }

  Future<void> _pickTime() async {
    final appState = AppStateProvider.of(context);
    final accent = appState.accent;
    final cardC  = appState.cardBg;
    final card2  = dmCard2;
    final bright = appState.themeMode.isDark ? Brightness.dark : Brightness.light;
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
          colorScheme: ColorScheme(
            brightness: bright,
            primary: accent,
            onPrimary: Colors.white,
            secondary: accent,
            onSecondary: Colors.white,
            error: Colors.red,
            onError: Colors.white,
            surface: cardC,
            onSurface: appState.txtMain,
          ),
          dialogBackgroundColor: cardC,
          timePickerTheme: TimePickerThemeData(
            backgroundColor: cardC,
            hourMinuteColor: card2,
            hourMinuteTextColor: appState.txtMain,
            dayPeriodTextColor: appState.txtMain,
            dayPeriodColor: card2,
            dialBackgroundColor: card2,
            dialHandColor: accent,
            dialTextColor: appState.txtMain,
            entryModeIconColor: accent,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    if (picked != null) setState(() { _selectedTime = picked; _timeSelected = true; });
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  Future<void> _openCalendarDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CalendarPickerDialog(
        accent: dmAccent,
        selectedDuration: _selectedDuration,
        existingAppointments: AppStateProvider.of(context).appointments,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedDate = result['date'] as DateTime;
        _selectedTime = result['time'] as TimeOfDay;
        _dateSelected = true;
        _timeSelected = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _heroHeader(context, 'New Appointment', dmAccent,
          changeSignal: _cs,
          onSave: null,   // saving handled exclusively by "Book Appointment" button below
        ),
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(children: [
            // ── 1. CLIENT & SERVICE ────────────────────────────────────────
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Client & Service', Icons.person_search_rounded, AppColors.green),
              const SizedBox(height: 16),
              _dmLabel('Client Name'),
              _buildClientAutocomplete(context),
              const SizedBox(height: 14),
              _dmLabel('Service Type'),
              _dmFieldBox(DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _service, isExpanded: true,
                dropdownColor: dmCard,
                hint: Text('Select service', style: GoogleFonts.dmSans(
                    color: dmTxtSub, fontSize: 13)),
                icon: Icon(Icons.expand_more_rounded, color: dmTxtSub),
                style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain,
                    fontWeight: FontWeight.w600),
                items: _services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _service = v),
              ))),
            ])),
            const SizedBox(height: 14),
            // ── 2. DATE & TIME (single button → calendar dialog) ──────────
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Date & Time', Icons.event_rounded, dmAccent),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _openCalendarDialog,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: (_dateSelected && _timeSelected)
                        ? LinearGradient(colors: dmBtnGradient) : null,
                    color: (_dateSelected && _timeSelected) ? null : dmCard2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: (_dateSelected && _timeSelected) ? dmAccent : dmBorder,
                        width: 1.5),
                    boxShadow: (_dateSelected && _timeSelected)
                        ? [BoxShadow(color: dmAccent.withOpacity(0.3),
                        blurRadius: 12, offset: const Offset(0, 4))]
                        : [],
                  ),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                        decoration: BoxDecoration(
                            color: dmAccent.withOpacity(
                                (_dateSelected && _timeSelected) ? 0.25 : 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.calendar_month_rounded,
                            color: (_dateSelected && _timeSelected)
                                ? Colors.white : dmAccent, size: 22)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((_dateSelected && _timeSelected)
                              ? 'Date & Time Selected'
                              : 'Tap to choose date & time',
                              style: GoogleFonts.dmSans(fontSize: 11,
                                  color: (_dateSelected && _timeSelected)
                                      ? Colors.white.withOpacity(0.65) : dmTxtSub,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text((_dateSelected && _timeSelected)
                              ? '${_formatDate(_selectedDate)}  ·  ${_formatTime(_selectedTime)}'
                              : 'Available slots will be shown',
                              style: GoogleFonts.dmSans(fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: (_dateSelected && _timeSelected)
                                      ? Colors.white : dmTxtMain)),
                        ])),
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: (_dateSelected && _timeSelected)
                            ? Colors.white.withOpacity(0.5) : dmTxtSub,
                        size: 14),
                  ]),
                ),
              ),
            ])),
            const SizedBox(height: 14),
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Location', Icons.place_rounded, const Color(0xFF2ECC96)),
              const SizedBox(height: 14),
              Row(children: List.generate(_locationTypes.length, (i) {
                final lt = _locationTypes[i];
                final sel = _locationType == lt['label'];
                final c = lt['color'] as Color;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _locationType = lt['label'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: sel ? LinearGradient(colors: [c.withOpacity(0.9), c]) : null,
                      color: sel ? null : dmCard2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? c : dmBorder, width: sel ? 1.5 : 1),
                      boxShadow: sel ? [BoxShadow(color: c.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))] : [],
                    ),
                    child: Column(children: [
                      Icon(lt['icon'] as IconData, color: sel ? Colors.white : c, size: 20),
                      const SizedBox(height: 5),
                      Text(lt['label'] as String, style: GoogleFonts.dmSans(
                          fontSize: 9.5, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : dmTxtSub), textAlign: TextAlign.center),
                    ]),
                  ),
                ));
              })),
              if (_locationType == 'Other') ...[
                const SizedBox(height: 14),
                _dmLabel('Specify Location'),
                _dmField(_locationCtrl, 'Enter location details', Icons.edit_location_rounded),
              ],
            ])),
            const SizedBox(height: 14),
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Duration', Icons.timelapse_rounded, const Color(0xFF7C3AED)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: ['15 min','30 min','45 min','1 hr','1.5 hr','2 hr'].map((d) {
                  final sel = _selectedDuration == d;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDuration = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF7C3AED).withOpacity(0.15) : dmCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? const Color(0xFF7C3AED) : dmBorder,
                          width: sel ? 1.8 : 1.2,
                        ),
                        boxShadow: sel ? [BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(0.18),
                            blurRadius: 8)] : [],
                      ),
                      child: Text(d, style: GoogleFonts.dmSans(
                        fontSize: 13.5,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? const Color(0xFF7C3AED) : dmTxtSub,
                      )),
                    ),
                  );
                }).toList(),
              ),
            ])),
            const SizedBox(height: 14),
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Notes', Icons.notes_rounded, AppColors.warning),
              const SizedBox(height: 14),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dmBorder)),
                  child: TextField(controller: _notesCtrl, maxLines: 3,
                      style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtMain),
                      decoration: InputDecoration.collapsed(hintText: 'Special instructions...',
                          hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)))),
            ])),
            const SizedBox(height: 24),
            _actionBtn('Book Appointment', Icons.check_circle_outline_rounded,
                dmBtnGradient[0], dmBtnGradient[1], () async {
                  final cancelled = await _saveToDb();
                  if (!mounted) return;
                  _showBookingResult(cancelled);
                  Navigator.pop(context);
                }),
          ]),
        )),
      ]),
    );
  }

  // ── Save new appointment to SQLite via AppState ───────────────────────────
  Future<List<String>> _saveToDb() async {
    final dateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedTime.hour, _selectedTime.minute,
    );
    String location;
    switch (_locationType) {
      case 'At Home':   location = 'At Home'; break;
      case 'At Office': location = 'At Office'; break;
      case 'Online':    location = 'Video Call · Online'; break;
      default:          location = _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim() : 'Location TBD';
    }
    final appointment = appt_model.Appointment(
      name       : _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Unknown Client',
      service    : _service ?? 'Consultation',
      dateTime   : dateTime,
      duration   : _selectedDuration,
      location   : location,
      note       : _notesCtrl.text.trim(),
      status     : appt_model.ApptStatus.confirmed,
      colorValue : 0xFF4A90D9,
    );
    return AppStateProvider.of(context).addAppointment(appointment);
  }


  void _showBookingResult(List<String> cancelled) {
    if (cancelled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('Appointment booked!',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: const Color(0xFF2ECC96),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
    } else {
      // Conflict found — new appointment was downgraded to Pending
      final names = cancelled.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Time slot taken by: $names. New appointment added as Pending — please reschedule.',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
          )),
        ]),
        backgroundColor: const Color(0xFFF4A24A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
    }
  }

  Widget _buildClientAutocomplete(BuildContext context) {
    final names = AppStateProvider.of(context)
        .appointments
        .map((a) => a.name)
        .toSet()
        .toList()
      ..sort();
    return Autocomplete<String>(
      optionsBuilder: (v) {
        if (v.text.isEmpty) return names;
        return names.where((n) =>
            n.toLowerCase().contains(v.text.toLowerCase()));
      },
      onSelected: (s) => _nameCtrl.text = s,
      fieldViewBuilder: (ctx, ctrl, focus, onSubmitted) {
        // keep controllers in sync
        ctrl.text = _nameCtrl.text;
        ctrl.addListener(() => _nameCtrl.text = ctrl.text);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
              color: dmCard2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dmBorder)),
          child: Row(children: [
            Icon(Icons.person_outline_rounded, size: 18, color: dmAccent),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: ctrl, focusNode: focus,
              onSubmitted: (_) => onSubmitted(),
              style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600,
                  color: dmTxtMain),
              decoration: InputDecoration(border: InputBorder.none,
                  hintText: 'Search or enter client name',
                  hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)),
            )),
          ]),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(alignment: Alignment.topLeft,
          child: Material(color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                  color: dmCard, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dmBorder),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
                      blurRadius: 16, offset: const Offset(0, 6))]),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  final initials = opt.trim().split(' ')
                      .where((w) => w.isNotEmpty)
                      .take(2)
                      .map((w) => w[0].toUpperCase())
                      .join();
                  return GestureDetector(
                    onTap: () => onSelected(opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        CircleAvatar(radius: 16,
                            backgroundColor: dmAccent.withOpacity(0.12),
                            child: Text(initials, style: GoogleFonts.dmSans(
                                fontSize: 11, fontWeight: FontWeight.w800,
                                color: dmAccent))),
                        const SizedBox(width: 12),
                        Text(opt, style: GoogleFonts.dmSans(fontSize: 13.5,
                            fontWeight: FontWeight.w600, color: dmTxtMain)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dmCard({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05),
            blurRadius: 16, offset: const Offset(0, 4))]),
    child: child,
  );
  Widget _dmCardTitle(String t, IconData icon, Color c) => Row(children: [
    Container(width: 36, height: 36,
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.withOpacity(0.18), c.withOpacity(0.06)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withOpacity(0.2))),
        child: Icon(icon, color: c, size: 18)),
    const SizedBox(width: 12),
    Text(t, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800,
        color: dmTxtMain, letterSpacing: -0.3)),
  ]);
  Widget _dmLabel(String l) => Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Text(l, style: GoogleFonts.dmSans(fontSize: 11,
          fontWeight: FontWeight.w700, color: dmTxtSub, letterSpacing: 0.5)));
  Widget _dmFieldBox(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dmBorder)), child: child,
  );
  Widget _dmField(TextEditingController ctrl, String hint, IconData icon) =>
      _dmFieldBox(Row(children: [
        Icon(icon, color: dmAccent, size: 18), const SizedBox(width: 10),
        Expanded(child: TextField(controller: ctrl,
            style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(border: InputBorder.none, hintText: hint,
                hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)))),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
//  CALENDAR PICKER DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _CalendarPickerDialog extends StatefulWidget {
  final Color accent;
  final String selectedDuration;
  final List<appt_model.Appointment> existingAppointments;
  const _CalendarPickerDialog({
    required this.accent,
    required this.selectedDuration,
    required this.existingAppointments,
  });
  @override
  State<_CalendarPickerDialog> createState() => _CalendarPickerDialogState();
}

class _CalendarPickerDialogState extends State<_CalendarPickerDialog> with DarkMode {
  late DateTime _focusedMonth;
  DateTime? _selectedDate;

  static const List<String> _dayNames = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  String _weekdayKey(int weekday) => _dayNames[weekday - 1];

  int _durationToMins(String d) {
    if (d == '15 min') return 15;
    if (d == '30 min') return 30;
    if (d == '45 min') return 45;
    if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90;
    if (d == '2 hr')   return 120;
    return 30;
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(RegExp(r'[: ]'));
    int h = int.tryParse(parts[0]) ?? 9;
    int m = int.tryParse(parts[1]) ?? 0;
    final period = parts.length > 2 ? parts[2].toUpperCase() : 'AM';
    if (period == 'PM' && h != 12) h += 12;
    if (period == 'AM' && h == 12) h = 0;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  bool _hasAvailability(DateTime d, AppState appState) {
    final key = _weekdayKey(d.weekday);
    return (appState.availabilityDays[key] ?? false) &&
        (appState.availabilitySlots[key]?.isNotEmpty ?? false);
  }

  int _bookedCount(DateTime d) => widget.existingAppointments.where((a) {
    final ad = a.dateTime;
    return ad.year == d.year && ad.month == d.month && ad.day == d.day &&
        a.status != appt_model.ApptStatus.cancelled;
  }).length;

  bool _isFullDay(DateTime d, AppState appState) =>
      _bookedCount(d) >= appState.maxPerDay;

  List<TimeOfDay> _getAvailableSlots(DateTime d, AppState appState) {
    final key       = _weekdayKey(d.weekday);
    final ranges    = appState.availabilitySlots[key] ?? [];
    final durationM = _durationToMins(widget.selectedDuration);
    final bufferM   = appState.bufferMinutes;

    // Appointment blocks
    final bookedRanges = widget.existingAppointments
        .where((a) {
      final ad = a.dateTime;
      return ad.year == d.year && ad.month == d.month && ad.day == d.day &&
          a.status != appt_model.ApptStatus.cancelled;
    })
        .map((a) {
      final startM = a.dateTime.hour * 60 + a.dateTime.minute;
      final durM   = _durationToMins(a.duration);
      return [startM, startM + durM + bufferM];
    }).toList();

    // Personal task blocks -- timed personal tasks block appointment slots
    final taskBlocks = PersonalTaskStore.instance.blockedRangesOn(d).map((blk) {
      final startM = blk.start.hour * 60 + blk.start.minute;
      final endM   = blk.end.hour   * 60 + blk.end.minute;
      return [startM, endM];
    }).toList();

    final allBlocked = [...bookedRanges, ...taskBlocks];

    final result = <TimeOfDay>[];
    for (final r in ranges) {
      if (r.length < 2) continue;
      final start  = _parseTime(r[0]);
      final end    = _parseTime(r[1]);
      var cur      = start.hour * 60 + start.minute;
      final endMin = end.hour * 60 + end.minute;
      while (cur + durationM <= endMin) {
        final slotEnd  = cur + durationM;
        final overlaps = allBlocked.any((br) => cur < br[1] && slotEnd > br[0]);
        if (!overlaps) result.add(TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
        cur += durationM;
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
  }

  void _prevMonth() => setState(() =>
  _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1));
  void _nextMonth() => setState(() =>
  _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1));

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final accent   = widget.accent;
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);

    final firstDay    = _focusedMonth;
    final daysInMonth = DateUtils.getDaysInMonth(firstDay.year, firstDay.month);
    final startOffset = firstDay.weekday - 1;
    final totalCells  = startOffset + daysInMonth;

    const months = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];

    final slots = _selectedDate != null
        ? _getAvailableSlots(_selectedDate!, appState)
        : <TimeOfDay>[];

    return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 32),
        child: Container(
            decoration: BoxDecoration(
              color: dmCard,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: dmBorder, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45),
                  blurRadius: 36, offset: const Offset(0, 14))],
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // ── Header ────────────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [accent.withOpacity(0.9), accent],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(26), topRight: Radius.circular(26)),
                        ),
                        child: Column(children: [
                          Row(children: [
                            GestureDetector(onTap: _prevMonth,
                                child: Container(width: 36, height: 36,
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(11)),
                                    child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22))),
                            Expanded(child: Text(
                                '${months[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w900,
                                    color: Colors.white, letterSpacing: -0.4))),
                            GestureDetector(onTap: _nextMonth,
                                child: Container(width: 36, height: 36,
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(11)),
                                    child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22))),
                          ]),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.timelapse_rounded, color: Colors.white, size: 13),
                              const SizedBox(width: 5),
                              Text('${widget.selectedDuration}', style: GoogleFonts.dmSans(
                                  fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(width: 10),
                              const Icon(Icons.shield_rounded, color: Colors.white, size: 13),
                              const SizedBox(width: 5),
                              Text('${appState.bufferMinutes} min buffer', style: GoogleFonts.dmSans(
                                  fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            ]),
                          ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Column(children: [
                          Row(children: ['M','T','W','T','F','S','S'].map((d) =>
                              Expanded(child: Center(child: Text(d, style: GoogleFonts.dmSans(
                                  fontSize: 12, fontWeight: FontWeight.w800, color: dmTxtSub))))).toList()),
                          const SizedBox(height: 8),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7, childAspectRatio: 1.0,
                                mainAxisSpacing: 4, crossAxisSpacing: 2),
                            itemCount: totalCells,
                            itemBuilder: (_, idx) {
                              if (idx < startOffset) return const SizedBox();
                              final dayNum = idx - startOffset + 1;
                              final date   = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
                              final isPast    = date.isBefore(today);
                              final isToday   = date == today;
                              final hasAvail  = _hasAvailability(date, appState) && !isPast;
                              final isFull    = hasAvail && _isFullDay(date, appState);
                              final hasSlots  = hasAvail && !isFull &&
                                  _getAvailableSlots(date, appState).isNotEmpty;
                              final isSel     = _selectedDate == date;
                              final bookedN   = hasAvail ? _bookedCount(date) : 0;

                              return GestureDetector(
                                onTap: hasSlots ? () => setState(() => _selectedDate = date) : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    gradient: isSel ? LinearGradient(
                                        colors: [accent, accent.withOpacity(0.75)]) : null,
                                    color: isSel    ? null
                                        : isFull   ? const Color(0xFFE05C5C).withOpacity(0.07)
                                        : hasSlots ? accent.withOpacity(0.09)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: !isSel && isToday ? Border.all(color: accent, width: 1.5)
                                        : !isSel && isFull
                                        ? Border.all(color: const Color(0xFFE05C5C).withOpacity(0.3))
                                        : null,
                                  ),
                                  child: Stack(alignment: Alignment.center, children: [
                                    Text('$dayNum', style: GoogleFonts.dmSans(
                                        fontSize: 13, fontWeight: FontWeight.w700,
                                        color: isSel   ? Colors.white
                                            : isPast   ? dmTxtSub.withOpacity(0.28)
                                            : isFull   ? const Color(0xFFE05C5C).withOpacity(0.5)
                                            : hasSlots ? dmTxtMain
                                            : dmTxtSub.withOpacity(0.40))),
                                    if (hasAvail && !isSel)
                                      Positioned(bottom: 3, child: Container(
                                        width: 4, height: 4,
                                        decoration: BoxDecoration(shape: BoxShape.circle,
                                            color: isFull ? const Color(0xFFE05C5C) : accent),
                                      )),
                                    if (bookedN > 0 && !isSel)
                                      Positioned(top: 2, right: 2, child: Container(
                                        width: 13, height: 13,
                                        decoration: BoxDecoration(
                                            color: isFull
                                                ? const Color(0xFFE05C5C)
                                                : accent.withOpacity(0.85),
                                            shape: BoxShape.circle),
                                        child: Center(child: Text('$bookedN',
                                            style: GoogleFonts.dmSans(fontSize: 7,
                                                fontWeight: FontWeight.w800, color: Colors.white))),
                                      )),
                                  ]),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            _dot(accent), const SizedBox(width: 5),
                            Text('Available', style: GoogleFonts.dmSans(fontSize: 10.5, color: dmTxtSub)),
                            const SizedBox(width: 14),
                            _dot(const Color(0xFFE05C5C)), const SizedBox(width: 5),
                            Text('Full (max ${appState.maxPerDay}/day)',
                                style: GoogleFonts.dmSans(fontSize: 10.5, color: dmTxtSub)),
                          ]),
                        ]),
                      ),
                      // ── Time slots ────────────────────────────────────────────────
                      if (_selectedDate != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: dmCard2, borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: dmBorder)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(width: 28, height: 28,
                                  decoration: BoxDecoration(color: accent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.access_time_rounded, size: 15, color: accent)),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Available slots', style: GoogleFonts.dmSans(
                                    fontSize: 13.5, fontWeight: FontWeight.w800, color: dmTxtMain)),
                                Text('${_fmtSelectedDate()} · ${widget.selectedDuration} per slot',
                                    style: GoogleFonts.dmSans(fontSize: 11, color: dmTxtSub,
                                        fontWeight: FontWeight.w500)),
                              ])),
                            ]),
                            const SizedBox(height: 12),
                            if (slots.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  color: dmCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: dmBorder),
                                ),
                                child: Column(children: [
                                  Icon(Icons.event_busy_rounded, size: 28, color: dmTxtSub.withOpacity(0.4)),
                                  const SizedBox(height: 6),
                                  Text('No slots available on this date',
                                      style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtSub)),
                                ]),
                              )
                            else ...[
                              // ── AM slots ──────────────────────────────────
                              () {
                                final amSlots = slots.where((t) => t.hour < 12).toList();
                                final pmSlots = slots.where((t) => t.hour >= 12).toList();
                                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (amSlots.isNotEmpty) ...[
                                    _slotGroupHeader('Morning', Icons.wb_sunny_outlined, amSlots.length, accent),
                                    const SizedBox(height: 8),
                                    GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        childAspectRatio: 1.55,
                                      ),
                                      itemCount: amSlots.length,
                                      itemBuilder: (_, i) => _buildTimeSlotCard(
                                        amSlots[i], accent,
                                        () => Navigator.pop(context, {'date': _selectedDate!, 'time': amSlots[i]}),
                                      ),
                                    ),
                                  ],
                                  if (pmSlots.isNotEmpty) ...[
                                    if (amSlots.isNotEmpty) const SizedBox(height: 14),
                                    _slotGroupHeader('Afternoon', Icons.wb_twilight_rounded, pmSlots.length, accent),
                                    const SizedBox(height: 8),
                                    GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        childAspectRatio: 1.55,
                                      ),
                                      itemCount: pmSlots.length,
                                      itemBuilder: (_, i) => _buildTimeSlotCard(
                                        pmSlots[i], accent,
                                        () => Navigator.pop(context, {'date': _selectedDate!, 'time': pmSlots[i]}),
                                      ),
                                    ),
                                  ],
                                ]);
                              }(),
                            ],
                          ]),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(color: dmCard2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: dmBorder)),
                            child: Center(child: Text('Cancel', style: GoogleFonts.dmSans(
                                fontSize: 14, fontWeight: FontWeight.w600, color: dmTxtSub))),
                          ),
                        ),
                      ),
                    ])))),
    );
  }

  Widget _slotGroupHeader(String label, IconData icon, int count, Color accent) {
    return Row(children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 12, color: accent),
      ),
      const SizedBox(width: 7),
      Text(label, style: GoogleFonts.dmSans(
          fontSize: 12, fontWeight: FontWeight.w800, color: dmTxtMain)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Text('$count open', style: GoogleFonts.dmSans(
            fontSize: 9.5, fontWeight: FontWeight.w700, color: accent)),
      ),
    ]);
  }

  Widget _buildTimeSlotCard(TimeOfDay t, Color accent, VoidCallback onTap) {
    final isPm  = t.hour >= 12;
    final h12   = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final minStr = t.minute.toString().padLeft(2, '0');
    final period = isPm ? 'PM' : 'AM';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: dmCard2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.08),
                blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Stack(children: [
          // Subtle gradient shimmer at top-right
          Positioned(top: 0, right: 0,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [accent.withOpacity(0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$h12:$minStr', style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w900,
                      color: dmTxtMain, letterSpacing: -0.5, height: 1.0)),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(period, style: GoogleFonts.dmSans(
                        fontSize: 9, fontWeight: FontWeight.w800,
                        color: accent, letterSpacing: 0.3)),
                  ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    width: 5, height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF2ECC96),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Open', style: GoogleFonts.dmSans(
                      fontSize: 8, fontWeight: FontWeight.w600,
                      color: const Color(0xFF2ECC96))),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c));

  String _fmtSelectedDate() {
    if (_selectedDate == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final d = _selectedDate!;
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}


// ─────────────────────────────────────────────────────────────────────────────
class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});
  @override
  State<AddClientScreen> createState() => _AddClientState();
}
class _AddClientState extends State<AddClientScreen> with DarkMode {
  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String _gender = 'Not specified';
  int _avatarColor = 0;
  // _colors built lazily in build() to access dmAccent from context
  List<Color> get _colors => [dmAccent, AppColors.green, AppColors.warning,
    AppColors.purple, AppColors.danger, const Color(0xFF0D9E6A)];

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _heroHeader(context, 'Add New Client', AppColors.green,
          changeSignal: _cs,
          onSave: () async {
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) Navigator.pop(context);
          },
        ),
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(children: [
            _c(child: Column(children: [
              _ct('Profile Picture', Icons.face_rounded, dmAccent),
              const SizedBox(height: 20),
              Center(child: Stack(alignment: Alignment.bottomRight, children: [
                Container(width: 90, height: 90,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: _colors[_avatarColor].withOpacity(0.15),
                        border: Border.all(color: _colors[_avatarColor].withOpacity(0.4), width: 3),
                        boxShadow: [BoxShadow(color: _colors[_avatarColor].withOpacity(0.25),
                            blurRadius: 16, offset: const Offset(0, 6))]),
                    child: Icon(Icons.person_rounded, color: _colors[_avatarColor], size: 44)),
                Container(width: 28, height: 28,
                    decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5)),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13)),
              ])),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_colors.length, (i) => GestureDetector(
                      onTap: () => setState(() => _avatarColor = i),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                          width: _avatarColor == i ? 32 : 26, height: _avatarColor == i ? 32 : 26,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: _colors[i],
                              border: Border.all(
                                  color: _avatarColor == i ? Colors.white : Colors.transparent,
                                  width: 2.5)))))),
            ])),
            const SizedBox(height: 14),
            _c(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ct('Personal Info', Icons.badge_outlined, dmTxtMain),
              const SizedBox(height: 16),
              _l('Full Name'), _f(_name, 'Enter full name', Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _l('Email Address'), _f(_email, 'email@example.com', Icons.email_outlined),
              const SizedBox(height: 12),
              _l('Phone Number'), _f(_phone, '+92 300 0000000', Icons.phone_outlined),
              const SizedBox(height: 12),
              _l('Gender'),
              _fb(DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _gender, isExpanded: true, dropdownColor: dmCard,
                icon: Icon(Icons.expand_more_rounded, color: dmTxtSub),
                style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain,
                    fontWeight: FontWeight.w600),
                items: ['Not specified','Male','Female','Other']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _gender = v!),
              ))),
            ])),
            const SizedBox(height: 14),
            _c(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ct('Notes', Icons.notes_rounded, AppColors.warning),
              const SizedBox(height: 14),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dmBorder)),
                  child: TextField(controller: _notes, maxLines: 3,
                      style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtMain),
                      decoration: InputDecoration.collapsed(hintText: 'Any notes about this client...',
                          hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)))),
            ])),
            const SizedBox(height: 24),
            _actionBtn('Save Client', Icons.person_add_rounded,
                dmBtnGradient[0], dmBtnGradient[1], () async {
                  await Future.delayed(const Duration(milliseconds: 600));
                  if (!mounted) return;
                  Navigator.pop(context);
                }),
          ]),
        )),
      ]),
    );
  }

  Widget _c({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dmBorder, width: 1.5)),
    child: child,
  );
  Widget _ct(String t, IconData icon, Color c) => Row(children: [
    Container(width: 36, height: 36,
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.withOpacity(0.18), c.withOpacity(0.06)]),
            borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
        child: Icon(icon, color: c, size: 18)),
    const SizedBox(width: 12),
    Text(t, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800,
        color: dmTxtMain, letterSpacing: -0.3)),
  ]);
  Widget _l(String l) => Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Text(l, style: GoogleFonts.dmSans(fontSize: 11,
          fontWeight: FontWeight.w700, color: dmTxtSub, letterSpacing: 0.5)));
  Widget _fb(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dmBorder)), child: child,
  );
  Widget _f(TextEditingController ctrl, String hint, IconData icon) =>
      _fb(Row(children: [
        Icon(icon, color: dmAccent, size: 18), const SizedBox(width: 10),
        Expanded(child: TextField(controller: ctrl,
            style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(border: InputBorder.none, hintText: hint,
                hintStyle: GoogleFonts.dmSans(color: dmTxtSub, fontSize: 13)))),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
//  3. SEND REMINDER
// ─────────────────────────────────────────────────────────────────────────────
class SendReminderScreen extends StatefulWidget {
  const SendReminderScreen({super.key});
  @override
  State<SendReminderScreen> createState() => _SendReminderState();
}
class _SendReminderState extends State<SendReminderScreen> with DarkMode {
  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  int _template = 0;
  final _templates = [
    {'t':'Appointment Reminder','m':'Hi {name}, reminder about your appointment tomorrow at {time}. See you soon!','icon':Icons.alarm_rounded},
    {'t':'Upcoming Session','m':'Dear {name}, your session is confirmed for {date} at {time}. Please arrive 5 mins early.','icon':Icons.event_rounded},
    {'t':'Follow-up Check-in','m':'Hi {name}, hope you\'re doing well after your last visit! Ready to book next session?','icon':Icons.favorite_rounded},
  ];
  final _clients = [
    {'n':'Aisha Khan','appt':'Today 9:00 AM','ac':const Color(0xFF4A90D9),'sel':false},
    {'n':'Omar Farooq','appt':'Today 10:00 AM','ac':const Color(0xFF2ECC96),'sel':false},
    {'n':'Zara Malik','appt':'Tomorrow 11:30 AM','ac':const Color(0xFFF4A24A),'sel':true},
    {'n':'Bilal Chaudhry','appt':'Tomorrow 1:00 PM','ac':const Color(0xFF7C3AED),'sel':true},
    {'n':'Hina Raza','appt':'Wed 2:30 PM','ac':const Color(0xFFE05C5C),'sel':false},
  ];
  int get _selCount => _clients.where((c) => c['sel'] == true).length;

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _heroHeader(context, 'Send Reminder', AppColors.warning,
          changeSignal: _cs,
          onSave: () async {
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) Navigator.pop(context);
          },
        ),
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(children: [
            Row(children: [
              _pillAccent('$_selCount', 'Selected', AppColors.warning),
              const SizedBox(width: 10),
              _pillNeutral('${_clients.length}', 'Total Clients'),
            ]),
            const SizedBox(height: 16),
            _box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('Message Template', Icons.message_outlined, AppColors.warning),
              const SizedBox(height: 14),
              ...List.generate(_templates.length, (i) => GestureDetector(
                onTap: () => setState(() => _template = i),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _template == i
                          ? AppColors.warning.withOpacity(0.12)
                          : dmCard2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _template == i ? AppColors.warning.withOpacity(0.5) : dmBorder,
                          width: _template == i ? 2 : 1.5)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: _template == i ? AppColors.warning.withOpacity(0.2) : dmBg,
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(_templates[i]['icon'] as IconData,
                            color: _template == i ? AppColors.warning : dmTxtMain, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_templates[i]['t'] as String,
                          style: GoogleFonts.dmSans(fontSize: 13.5,
                              fontWeight: FontWeight.w800, color: dmTxtMain)),
                      const SizedBox(height: 4),
                      Text(_templates[i]['m'] as String, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(fontSize: 11.5,
                              color: dmTxtSub, fontWeight: FontWeight.w500, height: 1.5)),
                    ])),
                  ]),
                ), // <--- Removed the extra ')' here!
              )),
            ])),
            const SizedBox(height: 14),
            _box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _title('Select Clients', Icons.people_alt_outlined, dmAccent),
                GestureDetector(
                  onTap: () { setState(() { final all = _clients.every((c) => c['sel'] == true); for (var c in _clients) c['sel'] = !all; }); },
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: dmAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text('Select All', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: dmAccent))),
                ),
              ]),
              const SizedBox(height: 14),
              ..._clients.asMap().entries.map((e) {
                final c = e.value; final i = e.key;
                final sel = c['sel'] == true;
                final ini = (c['n'] as String).split(' ').map((w) => w[0]).join();
                return GestureDetector(onTap: () => setState(() => _clients[i]['sel'] = !sel),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: sel ? dmAccent.withOpacity(0.08) : dmCard2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: sel ? dmAccent.withOpacity(0.4) : dmBorder,
                                width: sel ? 2 : 1.5)),
                        child: Row(children: [
                          CircleAvatar(radius: 20, backgroundColor: (c['ac'] as Color).withOpacity(dark ? 0.2 : 0.15),
                              child: Text(ini, style: GoogleFonts.dmSans(fontSize: 12,
                                  fontWeight: FontWeight.w800, color: c['ac'] as Color))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c['n'] as String, style: GoogleFonts.dmSans(
                                fontSize: 13.5, fontWeight: FontWeight.w700, color: dmTxtMain)),
                            Text(c['appt'] as String, style: GoogleFonts.dmSans(
                                fontSize: 11.5, color: dmTxtSub, fontWeight: FontWeight.w500)),
                          ])),
                          AnimatedContainer(duration: const Duration(milliseconds: 150),
                              width: 24, height: 24,
                              decoration: BoxDecoration(shape: BoxShape.circle,
                                  color: sel ? dmAccent : Colors.transparent,
                                  border: Border.all(
                                      color: sel ? dmAccent : dmBorder, width: 2)),
                              child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null),
                        ])));
              }),
            ])),
            const SizedBox(height: 24),
            _actionBtn('Send to $_selCount ${_selCount == 1 ? 'Client' : 'Clients'}',
                Icons.send_rounded, const Color(0xFF9A5A00), const Color(0xFFE8A020), () async {
                  await Future.delayed(const Duration(milliseconds: 600));
                  if (!mounted) return;
                  Navigator.pop(context);
                }),
          ]),
        )),
      ]),
    );
  }
  Widget _box({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05), blurRadius: 14, offset: const Offset(0,4))]),
    child: child,
  );
  Widget _title(String t, IconData icon, Color c) => Row(children: [
    Container(width: 36, height: 36,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [c.withOpacity(0.18), c.withOpacity(0.06)]),
            borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
        child: Icon(icon, color: c, size: 18)),
    const SizedBox(width: 12),
    Text(t, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800,
        color: dmTxtMain, letterSpacing: -0.3)),
  ]);
  // ── FIX: accent pill (gradient) for "Selected" count ──
  Widget _pillAccent(String v, String l, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(gradient: LinearGradient(colors: [c, c.withOpacity(0.75)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: c.withOpacity(0.35), blurRadius: 10, offset: const Offset(0,4))]),
    child: Column(children: [
      Text(v, style: GoogleFonts.dmSans(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
      Text(l, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85))),
    ]),
  ));

  // ── FIX: neutral card for "Total Clients" — always readable in all 8 themes ──
  // Uses dmCard bg + dmTxtMain text + dmBorder border, no colour dependency.
  Widget _pillNeutral(String v, String l) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
        color: dmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dmBorder, width: 1.5)),
    child: Column(children: [
      Text(v, style: GoogleFonts.dmSans(fontSize: 26, fontWeight: FontWeight.w900,
          color: dmTxtMain, letterSpacing: -0.5)),         // ← dmTxtMain always contrasts on dmCard
      Text(l, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600,
          color: dmTxtSub)),                               // ← dmTxtSub always readable
    ]),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  5. MY REVIEWS  ← fully dark-aware rebuild
// ─────────────────────────────────────────────────────────────────────────────
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});
  @override
  State<MyReviewsScreen> createState() => _MyReviewsState();
}
class _MyReviewsState extends State<MyReviewsScreen> with DarkMode {
  final _reviews = [
    {'n':'Aisha Khan',    'txt':'Amazing experience! Very professional and caring service.','r':5,'d':'Mar 15','ac':const Color(0xFF4A90D9)},
    {'n':'Omar Farooq',   'txt':'Highly recommend. Excellent service every single time!',  'r':5,'d':'Mar 12','ac':const Color(0xFF2ECC96)},
    {'n':'Zara Malik',    'txt':'Great attention to detail. Definitely will come back!',   'r':4,'d':'Mar 10','ac':const Color(0xFFF4A24A)},
    {'n':'Bilal Chaudhry','txt':'Professional and thorough. 10/10 — would recommend.',     'r':5,'d':'Mar 8', 'ac':const Color(0xFF7C3AED)},
    {'n':'Hina Raza',     'txt':'Good service overall, appreciate a little more speed.',   'r':4,'d':'Mar 5', 'ac':const Color(0xFFE05C5C)},
  ];

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        // ── Hero with stats ──
        Container(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: AppStateProvider.of(context).heroGradient)),
          child: Stack(children: [
            Positioned(right: -50, top: -50, child: Container(width: 200, height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [AppColors.warning.withOpacity(0.15), Colors.transparent])))),
            SafeArea(bottom: false, child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 0), child: Row(children: [
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: _glassBtn(child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18))),
                const SizedBox(width: 14),
                Expanded(child: Text('My Reviews', style: GoogleFonts.dmSans(
                    fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5))),

              ])),
              const SizedBox(height: 20),
              // Overall rating big display
              Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 6), child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.12))),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('4.9', style: GoogleFonts.dmSans(fontSize: 48,
                          fontWeight: FontWeight.w900, color: Colors.white, height: 1.0, letterSpacing: -2)),
                      Padding(padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text('/5', style: GoogleFonts.dmSans(fontSize: 18,
                              color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600))),
                    ]),
                    Row(children: List.generate(5, (i) => Icon(Icons.star_rounded,
                        size: 18, color: i < 5 ? AppColors.warning : Colors.white.withOpacity(0.3)))),
                    const SizedBox(height: 4),
                    Text('Based on ${_reviews.length} reviews', style: GoogleFonts.dmSans(
                        fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
                  ]),
                  const Spacer(),
                  Column(children: [
                    _ratingBar(5, 0.80),
                    _ratingBar(4, 0.40),
                    _ratingBar(3, 0.10),
                    _ratingBar(2, 0.05),
                    _ratingBar(1, 0.00),
                  ]),
                ]),
              )),
              // Stat pills row
              Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 22), child: Row(children: [
                _rStat('${_reviews.length}', 'Reviews', dmAccent),
                const SizedBox(width: 10),
                _rStat('98%', 'Positive', AppColors.green),
                const SizedBox(width: 10),
                _rStat('4.9★', 'Avg Rating', AppColors.warning),
              ])),
            ])),
          ]),
        ),
        // ── Review cards ──
        Expanded(child: ListView.separated(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          itemCount: _reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final r = _reviews[i];
            final ini = (r['n'] as String).split(' ').map((w) => w[0]).join();
            return Container(padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: dmBorder, width: 1.5),
                    boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05),
                        blurRadius: 14, offset: const Offset(0, 4))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(decoration: BoxDecoration(shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: (r['ac'] as Color).withOpacity(0.2), blurRadius: 8)]),
                        child: CircleAvatar(radius: 24, backgroundColor: (r['ac'] as Color).withOpacity(dark ? 0.2 : 0.15),
                            child: Text(ini, style: GoogleFonts.dmSans(fontSize: 14,
                                fontWeight: FontWeight.w800, color: r['ac'] as Color)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['n'] as String, style: GoogleFonts.dmSans(fontSize: 15,
                          fontWeight: FontWeight.w800, color: dmTxtMain, letterSpacing: -0.2)),
                      const SizedBox(height: 5),
                      Row(children: List.generate(5, (j) => Icon(Icons.star_rounded, size: 15,
                          color: j < (r['r'] as int) ? AppColors.warning : dmBorder))),
                    ])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(dark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.warning.withOpacity(0.3))),
                        child: Text(r['d'] as String, style: GoogleFonts.dmSans(
                            fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning))),
                  ]),
                  const SizedBox(height: 14),
                  Container(padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: dmBorder2)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.format_quote_rounded, color: dmAccent.withOpacity(0.5), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r['txt'] as String, style: GoogleFonts.dmSans(
                            fontSize: 13.5, color: dmTxtBody, fontWeight: FontWeight.w500, height: 1.6))),
                      ])),
                ]));
          },
        )),
      ]),
    );
  }

  Widget _ratingBar(int stars, double fill) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Text('$stars', style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      SizedBox(width: 80, height: 6, child: ClipRRect(borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: fill, backgroundColor: Colors.white.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning)))),
    ]),
  );

  Widget _rStat(String v, String l, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15))),
    child: Column(children: [
      Text(v, style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900,
          color: Colors.white, letterSpacing: -0.5)),
      const SizedBox(height: 2),
      Text(l, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: c)),
    ]),
  ));
}


// ─── Shared bottom action button ─────────────────────────────────────────────
Widget _actionBtn(String label, IconData icon, Color g1, Color g2, VoidCallback onTap) =>
    GestureDetector(onTap: onTap,
        child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [g1, g2]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: g1.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))]),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10),
            Text(label, style: GoogleFonts.dmSans(fontSize: 16,
                fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
          ]),
        ));