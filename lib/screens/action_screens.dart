import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../models/appointment.dart' as appt_model;
import '../services/api_client.dart';
import '../services/appointment_service.dart';
import '../services/user_service.dart';
import 'user_picker_screen.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import '../widgets/save_icon_button.dart';
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
  /// The provider being booked with, picked from the user directory.
  /// The ID is mirrored into [_providerIdCtrl] because the calendar
  /// dialog and the submit path read it from there.
  AppUser? _selectedProvider;
  final _providerIdCtrl = TextEditingController();
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
        providerId: _providerIdCtrl.text.trim().isEmpty
            ? null
            : _providerIdCtrl.text.trim(),
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
            // ── PROVIDER (who this appointment is booked with) ────────────
            _dmCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dmCardTitle('Provider', Icons.badge_rounded, const Color(0xFF1A5EA8)),
              const SizedBox(height: 16),
              _dmLabel('Choose provider'),
              _buildProviderPicker(),
              const SizedBox(height: 8),
              Text('Choose the provider you want to book with — the booking '
                  'is sent to them for approval. Choosing one also shows '
                  'their real available slots in the calendar below.',
                  style: GoogleFonts.dmSans(fontSize: 11.5, color: dmTxtSub,
                      fontWeight: FontWeight.w500, height: 1.4)),
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
                  try {
                    await _saveToDb();
                  } on ApiException catch (e) {
                    // Booking failed (e.g. the time conflicts, or the
                    // provider has no availability then). Show the reason
                    // and keep the form open.
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.message,
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFE05C5C),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ));
                    return;
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'Appointment requested! Waiting for the provider to accept.',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600))),
                    ]),
                    backgroundColor: const Color(0xFF2ECC96),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ));
                  Navigator.pop(context);
                }),
          ]),
        )),
      ]),
    );
  }

  // ── Book the appointment through the backend via AppState ─────────────────
  Future<void> _saveToDb() async {
    // A date AND a time must be picked first — the defaults (today,
    // 09:00) are not a booking, and without this check tapping "Book
    // Appointment" would fail with a raw backend 400 or silently
    // book today at 09:00.
    if (!_dateSelected || !_timeSelected) {
      throw const ApiException('Please choose a date and time first.');
    }
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
    // The booking API has no service or location fields, so they are
    // folded into the notes the provider sees.
    final service = _service ?? 'Consultation';
    final extra = _notesCtrl.text.trim();
    // The booking API has no client-name field, so the typed client
    // name is folded into the notes (like service/location) — it
    // was previously dropped and never reached the server.
    final clientName = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : 'Unknown Client';
    final note = 'Client: $clientName\nService: $service\nLocation: $location'
        '${extra.isEmpty ? '' : '\n$extra'}';
    final appointment = appt_model.Appointment(
      name       : _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Unknown Client',
      service    : service,
      dateTime   : dateTime,
      duration   : _selectedDuration,
      location   : location,
      note       : note,
      status     : appt_model.ApptStatus.pending,
      colorValue : 0xFF4A90D9,
      providerId : _providerIdCtrl.text.trim(),
    );
    // Throws ApiException when the provider ID is missing or the
    // backend rejects the booking.
    await AppStateProvider.of(context).addAppointment(appointment);
  }

  /// Provider picker (replaces the old numeric user-ID field): search
  /// the user directory by name or email, tap a provider. The picked
  /// provider's ID is mirrored into [_providerIdCtrl] for the
  /// calendar dialog and the submit path.
  Widget _buildProviderPicker() {
    final provider = _selectedProvider;
    return GestureDetector(
      onTap: () async {
        final user = await Navigator.push<AppUser?>(
          context,
          MaterialPageRoute(
            builder: (_) => const UserPickerScreen(title: 'Choose provider'),
          ),
        );
        if (user == null || !mounted) return;
        setState(() {
          _selectedProvider = user;
          _providerIdCtrl.text = user.id.toString();
        });
      },
      child: _dmFieldBox(Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dmAccent.withOpacity(0.15),
          ),
          child: Center(
            child: provider == null
                ? Icon(Icons.person_search_rounded, color: dmAccent, size: 18)
                : Text(provider.initials,
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w900, color: dmAccent)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: provider == null
              ? Text('Tap to choose a provider…',
                  style: GoogleFonts.dmSans(fontSize: 13, color: dmTxtSub))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(provider.fullName,
                      style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain,
                          fontWeight: FontWeight.w700)),
                  if (provider.email.isNotEmpty)
                    Text(provider.email,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 11.5, color: dmTxtSub)),
                ]),
        ),
        Icon(Icons.chevron_right_rounded, color: dmTxtSub.withOpacity(0.6)),
      ])),
    );
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
  /// When set, the selected day's slots come from this provider's real
  /// published availability (GET /availability/slots/). When null, slots
  /// are computed locally from my own availability, as before.
  final String? providerId;
  const _CalendarPickerDialog({
    required this.accent,
    required this.selectedDuration,
    required this.existingAppointments,
    this.providerId,
  });
  @override
  State<_CalendarPickerDialog> createState() => _CalendarPickerDialogState();
}

class _CalendarPickerDialogState extends State<_CalendarPickerDialog> with DarkMode {
  late DateTime _focusedMonth;
  DateTime? _selectedDate;
  /// Slots fetched from the provider's API for the selected day (null
  /// means "not loaded" — use the local computation instead).
  List<TimeOfDay>? _apiSlots;
  bool _loadingApiSlots = false;

  /// Selects a day and, in provider mode, fetches that provider's real
  /// slots for it. On failure the local slot computation is used.
  void _selectDate(DateTime date) {
    final providerMode =
        widget.providerId != null && widget.providerId!.isNotEmpty;
    setState(() {
      _selectedDate = date;
      _apiSlots = null;
      _loadingApiSlots = providerMode;
    });
    if (providerMode) _loadApiSlots(date);
  }

  Future<void> _loadApiSlots(DateTime date) async {
    final providerId = widget.providerId;
    if (providerId == null || providerId.isEmpty) return;
    List<TimeSlot> fetched;
    try {
      fetched = await AppointmentService.instance.fetchSlots(
        providerId: providerId,
        date: date,
        durationMinutes: _durationToMins(widget.selectedDuration),
      );
    } on ApiException {
      // Offline or the provider has no published schedule — fall back
      // to the local slot computation.
      if (mounted) setState(() => _loadingApiSlots = false);
      return;
    }
    if (!mounted || _selectedDate != date) return;
    setState(() {
      _apiSlots = fetched
          .map((s) => TimeOfDay(hour: s.startsAt.hour, minute: s.startsAt.minute))
          .toList();
      _loadingApiSlots = false;
    });
  }

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

    // Past slots on today are not bookable — the backend slots
    // endpoint filters them too, so the local fallback must as well.
    final now     = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final nowMins = now.hour * 60 + now.minute;

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
        final inPast   = isToday && cur <= nowMins;
        if (!overlaps && !inPast) result.add(TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
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
        ? (_apiSlots ?? _getAvailableSlots(_selectedDate!, appState))
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
                              // In provider mode every future day is tappable
                              // — the provider's API decides which slots exist
                              // on it. Otherwise days are gated on my own
                              // availability, as before.
                              final providerMode = widget.providerId != null &&
                                  widget.providerId!.isNotEmpty;
                              final hasSlots  = providerMode
                                  ? !isPast
                                  : hasAvail && !isFull &&
                                      _getAvailableSlots(date, appState).isNotEmpty;
                              final isSel     = _selectedDate == date;
                              final bookedN   = hasAvail ? _bookedCount(date) : 0;

                              return GestureDetector(
                                onTap: hasSlots ? () => _selectDate(date) : null,
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
                            if (_loadingApiSlots)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  color: dmCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: dmBorder),
                                ),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5, color: accent)),
                                  const SizedBox(width: 10),
                                  Text('Loading provider slots…',
                                      style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtSub)),
                                ]),
                              )
                            else if (slots.isEmpty)
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
//  5. MY REVIEWS  ← fully dark-aware rebuild
// ─────────────────────────────────────────────────────────────────────────────
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});
  @override
  State<MyReviewsScreen> createState() => _MyReviewsState();
}
class _MyReviewsState extends State<MyReviewsScreen> with DarkMode {
  // No review data exists — honest empty state instead of hardcoded
  // fake reviews and fake stats (matches the profile reviews card).
  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _heroHeader(context, 'My Reviews', AppColors.warning),
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  shape: BoxShape.circle),
              child: Icon(Icons.star_outline_rounded,
                  color: AppColors.warning.withOpacity(0.5), size: 36),
            ),
            const SizedBox(height: 16),
            Text('No reviews yet.', style: GoogleFonts.dmSans(
                fontSize: 18, fontWeight: FontWeight.w800, color: dmTxtMain)),
            const SizedBox(height: 6),
            Text('Reviews from your clients will appear here once they leave feedback.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtSub,
                    fontWeight: FontWeight.w500)),
          ]),
        ))),
      ]),
    );
  }
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