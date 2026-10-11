import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../app_state.dart';
import '../theme/dark_theme.dart';
import '../widgets/save_icon_button.dart';

class MyAvailabilityScreen extends StatefulWidget {
  const MyAvailabilityScreen({super.key});
  @override
  State<MyAvailabilityScreen> createState() => _MyAvailabilityScreenState();
}

class _MyAvailabilityScreenState extends State<MyAvailabilityScreen> with DarkMode, TickerProviderStateMixin {

  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  final Map<String, bool> _days = {
    'Mon': true, 'Tue': true, 'Wed': true,
    'Thu': true, 'Fri': true, 'Sat': false, 'Sun': false,
  };

  final Map<String, List<_Slot>> _slots = {
    'Mon': [_Slot('9:00 AM', '1:00 PM'), _Slot('2:00 PM', '6:00 PM')],
    'Tue': [_Slot('9:00 AM', '1:00 PM'), _Slot('2:00 PM', '6:00 PM')],
    'Wed': [_Slot('10:00 AM', '3:00 PM')],
    'Thu': [_Slot('9:00 AM', '1:00 PM'), _Slot('2:00 PM', '5:00 PM')],
    'Fri': [_Slot('9:00 AM', '12:00 PM')],
    'Sat': [],
    'Sun': [],
  };

  bool _breakEnabled = true;
  String _breakStart = '1:00 PM';
  String _breakEnd   = '2:00 PM';
  int _bufferMinutes = 15;
  final List<int> _bufferOptions = [0, 5, 10, 15, 30];
  int _maxPerDay = 8;
  int _bookingWindowDays = 30;
  String _status = 'Available';
  String _selectedDay = 'Mon';

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));
    _headerCtrl.forward();
    // Load persisted availability after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromAppState());
  }

  void _loadFromAppState() {
    final appState = AppStateProvider.of(context);
    final days  = appState.availabilityDays;
    final slots = appState.availabilitySlots;
    setState(() {
      days.forEach((k, v) { if (_days.containsKey(k)) _days[k] = v; });
      slots.forEach((k, v) {
        if (_slots.containsKey(k)) {
          _slots[k] = v.map((s) => _Slot(s[0], s[1])).toList();
        }
      });
    });
  }

  @override
  void dispose() { _headerCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: dmBg,
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: SlideTransition(position: _headerSlide,
              child: FadeTransition(opacity: _headerFade, child: _buildHeader())),
          ),
          SliverToBoxAdapter(child: _buildStatusCard()),
          SliverToBoxAdapter(child: _buildWeeklySchedule()),
          SliverToBoxAdapter(child: _buildDaySlots()),
          SliverToBoxAdapter(child: _buildSettings()),
          SliverToBoxAdapter(child: _buildBreakTime()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: AppStateProvider.of(context).heroGradient,
      )),
      child: Stack(children: [
        Positioned(right: -40, top: -40, child: _orb(180, dmAccent, 0.11)),
        Positioned(left: -30, bottom: 0, child: _orb(110, Colors.white, 0.05)),
        SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
              ),
              const SizedBox(width: 14),

              const Spacer(),
              SaveIconButton(
                size: 42,
                onSave: () async {
                  await Future.delayed(const Duration(milliseconds: 400));
                  if (mounted) await _showSaved();
                },
                changeSignal: _cs,
                foregroundColor: Colors.white,
              ),
            ]),
            const SizedBox(height: 22),
            Text('My Availability', style: GoogleFonts.dmSans(
                fontSize: 28, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: -0.8)),
            const SizedBox(height: 5),
            Text('Set when clients can book appointments with you',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: Colors.white.withOpacity(0.55))),
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _statPill(Icons.calendar_today_rounded, '5 days / week'),
              _statPill(Icons.schedule_rounded,        '8 hrs / day'),
              _statPill(Icons.people_alt_rounded,      'Max $_maxPerDay'),
            ]),
          ]),
        )),
      ]),
    );
  }

  Widget _statPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.white.withOpacity(0.8)),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.dmSans(
          fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9))),
    ]),
  );

  // ── STATUS CARD ────────────────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final statuses = [
      {'label': 'Available', 'color': AppColors.green,   'icon': Icons.check_circle_rounded},
      {'label': 'Busy',      'color': AppColors.warning,  'icon': Icons.do_not_disturb_rounded},
      {'label': 'Away',      'color': AppColors.danger,   'icon': Icons.flight_takeoff_rounded},
    ];
    return _section(
      title: 'Current Status',
      subtitle: 'Visible to clients when booking',
      child: Row(children: statuses.map((s) {
        final active = _status == s['label'];
        final c = s['color'] as Color;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _status = s['label'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? c.withOpacity(0.12) : dmCard2,  // ← theme-aware inactive
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: active ? c : dmBorder,
                  width: active ? 1.5 : 1),
              boxShadow: active ? [BoxShadow(color: c.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 3))] : [],
            ),
            child: Column(children: [
              Icon(s['icon'] as IconData,
                  color: active ? c : dmTxtSub, size: 22),
              const SizedBox(height: 6),
              Text(s['label'] as String, style: GoogleFonts.dmSans(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? c : dmTxtSub)),
            ]),
          ),
        ));
      }).toList()),
    );
  }

  // ── WEEKLY SCHEDULE ────────────────────────────────────────────────────────
  Widget _buildWeeklySchedule() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _section(
      title: 'Working Days',
      subtitle: 'Tap a day to edit its time slots',
      child: Column(children: [
        Row(children: days.map((d) {
          final enabled  = _days[d]!;
          final selected = _selectedDay == d;
          return Expanded(child: GestureDetector(
            onTap: () => setState(() { _selectedDay = d; if (!enabled) _days[d] = true; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                // selected: accent gradient; enabled: subtle accent tint; disabled: plain bg
                gradient: selected
                    ? LinearGradient(colors: dmActivePillGradient)
                    : null,
                color: selected ? null : (enabled ? dmAccent.withOpacity(0.08) : dmCard2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : (enabled ? dmAccent.withOpacity(0.25) : dmBorder)),
              ),
              child: Column(children: [
                Text(d, style: GoogleFonts.dmSans(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: selected ? Colors.white
                        : (enabled ? dmTxtMain : dmTxtSub))),
                const SizedBox(height: 4),
                Container(width: 5, height: 5, decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withOpacity(0.6)
                      : (enabled ? AppColors.green : Colors.transparent),
                )),
              ]),
            ),
          ));
        }).toList()),
        const SizedBox(height: 14),
        Row(children: [
          Text('${_days[_selectedDay]! ? "Enabled" : "Disabled"} on $_selectedDay',
              style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: dmTxtSub)),
          const Spacer(),
          Switch.adaptive(
            value: _days[_selectedDay]!,
            activeColor: AppColors.green,
            onChanged: (v) => setState(() => _days[_selectedDay] = v),
          ),
        ]),
      ]),
    );
  }

  // ── TIME SLOTS ─────────────────────────────────────────────────────────────
  Widget _buildDaySlots() {
    final slots = _slots[_selectedDay]!;
    final enabled = _days[_selectedDay]!;
    return _section(
      title: '$_selectedDay · Time Slots',
      subtitle: enabled ? 'Tap + to add a slot' : 'Enable $_selectedDay to add slots',
      child: Column(children: [
        if (slots.isEmpty && enabled)
          _emptySlot()
        else
          ...slots.asMap().entries.map((e) => _slotRow(e.key, e.value, enabled)),
        if (enabled) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _slots[_selectedDay]!.add(_Slot('9:00 AM', '5:00 PM'))),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: dmAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dmBorder, style: BorderStyle.solid),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_rounded, size: 18, color: dmAccent),
                const SizedBox(width: 6),
                Text('Add time slot', style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: dmAccent)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _emptySlot() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
        color: dmCard2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dmBorder)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.schedule_rounded, size: 18, color: dmTxtSub),
      const SizedBox(width: 8),
      Text('No slots yet — tap + to add',
          style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtSub)),
    ]),
  );

  Widget _slotRow(int i, _Slot slot, bool enabled) {
    // Parse times to compute duration
    String _dur(String start, String end) {
      int _toMin(String t) {
        final p = t.split(RegExp(r'[: ]'));
        int h = int.tryParse(p[0]) ?? 0;
        final m = int.tryParse(p[1]) ?? 0;
        if (p.length > 2 && p[2] == 'PM' && h != 12) h += 12;
        if (p.length > 2 && p[2] == 'AM' && h == 12) h = 0;
        return h * 60 + m;
      }
      final diff = _toMin(end) - _toMin(start);
      if (diff <= 0) return '—';
      final h = diff ~/ 60;
      final m = diff % 60;
      if (h == 0) return '${m}m';
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }

    final duration = _dur(slot.start, slot.end);

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: dmCard2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dmBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08),
                blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(children: [
          // ── Top: time display row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              // Start block
              Expanded(child: GestureDetector(
                onTap: () => _pickTime(true, i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: dmAccent.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dmAccent.withOpacity(0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('START', style: GoogleFonts.dmSans(
                        fontSize: 8.5, fontWeight: FontWeight.w800,
                        color: dmTxtSub, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text(slot.start, style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: dmAccent, letterSpacing: -0.3)),
                  ]),
                ),
              )),
              // Middle: duration + visual bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  Text(duration, style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: dmTxtSub)),
                  const SizedBox(height: 5),
                  SizedBox(width: 48, child: Stack(alignment: Alignment.center,
                    children: [
                      Container(height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [dmAccent.withOpacity(0.2), dmAccent.withOpacity(0.6), dmAccent.withOpacity(0.2)],
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(width: 5, height: 5, decoration: BoxDecoration(
                              shape: BoxShape.circle, color: dmAccent.withOpacity(0.6))),
                          Container(width: 5, height: 5, decoration: BoxDecoration(
                              shape: BoxShape.circle, color: dmAccent.withOpacity(0.6))),
                        ]),
                    ],
                  )),
                ]),
              ),
              // End block
              Expanded(child: GestureDetector(
                onTap: () => _pickTime(false, i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: dmAccent.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dmAccent.withOpacity(0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('END', style: GoogleFonts.dmSans(
                        fontSize: 8.5, fontWeight: FontWeight.w800,
                        color: dmTxtSub, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text(slot.end, style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: dmAccent.withOpacity(0.75), letterSpacing: -0.3)),
                  ]),
                ),
              )),
              // Delete button
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _slots[_selectedDay]!.removeAt(i)),
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withOpacity(0.2))),
                  child: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger.withOpacity(0.8)),
                ),
              ),
            ]),
          ),
          // ── Bottom: visual duration bar ───────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: dmBorder,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              // Visual fill: proportion of the day (approx)
              widthFactor: (() {
                int _toMin(String t) {
                  final p = t.split(RegExp(r'[: ]'));
                  int h = int.tryParse(p[0]) ?? 0;
                  final m = int.tryParse(p[1]) ?? 0;
                  if (p.length > 2 && p[2] == 'PM' && h != 12) h += 12;
                  if (p.length > 2 && p[2] == 'AM' && h == 12) h = 0;
                  return h * 60 + m;
                }
                final diff = (_toMin(slot.end) - _toMin(slot.start)).clamp(0, 1440);
                return (diff / 1440).clamp(0.05, 1.0);
              })(),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [dmAccent, dmAccent.withOpacity(0.4)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _timeChip(String t, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: dmAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dmAccent.withOpacity(0.3))),
      child: Text(t, style: GoogleFonts.dmSans(
          fontSize: 12.5, fontWeight: FontWeight.w700, color: dmAccent)),
    ),
  );

  Future<void> _pickTime(bool isStart, int slotIndex) async {
    final parts = isStart
        ? _slots[_selectedDay]![slotIndex].start.split(RegExp(r'[: ]'))
        : _slots[_selectedDay]![slotIndex].end.split(RegExp(r'[: ]'));
    int hour = int.tryParse(parts[0]) ?? 9;
    if (parts.length > 2 && parts[2] == 'PM' && hour != 12) hour += 12;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked == null || !mounted) return;
    final formatted = picked.format(context);
    setState(() {
      if (isStart) _slots[_selectedDay]![slotIndex] = _Slot(formatted, _slots[_selectedDay]![slotIndex].end);
      else         _slots[_selectedDay]![slotIndex] = _Slot(_slots[_selectedDay]![slotIndex].start, formatted);
    });
  }

  // ── BOOKING RULES ──────────────────────────────────────────────────────────
  Widget _buildSettings() {
    return _section(
      title: 'Booking Rules',
      subtitle: 'Applied to all appointment requests',
      child: Column(children: [
        // Buffer time
        _settingRow(
          icon: Icons.timer_outlined,
          label: 'Buffer between appointments',
          value: '$_bufferMinutes min',
          child: Wrap(spacing: 6, children: _bufferOptions.map((m) {
            final sel = _bufferMinutes == m;
            return GestureDetector(
              onTap: () => setState(() => _bufferMinutes = m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  // selected: accent gradient; unselected: plain bg
                  gradient: sel ? LinearGradient(colors: dmActivePillGradient) : null,
                  color: sel ? null : dmCard2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? Colors.transparent : dmBorder),
                ),
                child: Text('${m}m', style: GoogleFonts.dmSans(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : dmTxtSub)),
              ),
            );
          }).toList()),
        ),
        const SizedBox(height: 14),
        // Max per day
        _settingRow(
          icon: Icons.people_outline_rounded,
          label: 'Max appointments per day',
          value: '$_maxPerDay',
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(() { if (_maxPerDay > 1) _maxPerDay--; }),
              child: _countBtn(Icons.remove_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('$_maxPerDay', style: GoogleFonts.dmSans(
                  fontSize: 18, fontWeight: FontWeight.w900, color: dmTxtMain)),
            ),
            GestureDetector(
              onTap: () => setState(() { if (_maxPerDay < 20) _maxPerDay++; }),
              child: _countBtn(Icons.add_rounded),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // Booking window
        _settingRow(
          icon: Icons.event_available_rounded,
          label: 'Booking window',
          value: '$_bookingWindowDays days ahead',
          child: Wrap(spacing: 6, children: [14, 30, 60, 90].map((d) {
            final sel = _bookingWindowDays == d;
            return GestureDetector(
              onTap: () => setState(() => _bookingWindowDays = d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: sel ? LinearGradient(colors: dmActivePillGradient) : null,
                  color: sel ? null : dmCard2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? Colors.transparent : dmBorder),
                ),
                child: Text('${d}d', style: GoogleFonts.dmSans(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : dmTxtSub)),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _settingRow({required IconData icon, required String label, required String value, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dmCard2,       // ← theme-aware nested card
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dmBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: dmAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w600, color: dmTxtMain))),
          Text(value, style: GoogleFonts.dmSans(
              fontSize: 12, color: dmTxtSub)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _countBtn(IconData icon) => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
        color: dmAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dmAccent.withOpacity(0.3))),
    child: Icon(icon, size: 16, color: dmAccent),
  );

  // ── BREAK TIME ─────────────────────────────────────────────────────────────
  Widget _buildBreakTime() {
    return _section(
      title: 'Break Time',
      subtitle: 'Block off a daily break — no bookings during this window',
      child: Column(children: [
        Row(children: [
          Text('Enable daily break', style: GoogleFonts.dmSans(
              fontSize: 13.5, fontWeight: FontWeight.w600, color: dmTxtMain)),
          const Spacer(),
          Switch.adaptive(
            value: _breakEnabled,
            activeColor: dmAccent,
            onChanged: (v) => setState(() => _breakEnabled = v),
          ),
        ]),
        if (_breakEnabled) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Start', style: GoogleFonts.dmSans(fontSize: 11, color: dmTxtSub)),
              const SizedBox(height: 4),
              _timeChip(_breakStart, () async {
                final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 13, minute: 0));
                if (t != null && mounted) setState(() => _breakStart = t.format(context));
              }),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('to', style: GoogleFonts.dmSans(color: dmTxtSub))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('End', style: GoogleFonts.dmSans(fontSize: 11, color: dmTxtSub)),
              const SizedBox(height: 4),
              _timeChip(_breakEnd, () async {
                final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 14, minute: 0));
                if (t != null && mounted) setState(() => _breakEnd = t.format(context));
              }),
            ])),
            const Spacer(),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.2))),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text('$_breakStart – $_breakEnd is blocked every working day',
                  style: GoogleFonts.dmSans(
                      fontSize: 11.5, color: AppColors.warning, fontWeight: FontWeight.w500))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── SHARED SECTION WRAPPER ─────────────────────────────────────────────────
  Widget _section({required String title, required String subtitle, required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dmCard,        // ← theme-aware card (was hardcoded Colors.white!)
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dmBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w800, color: dmTxtMain)),
        const SizedBox(height: 2),
        Text(subtitle, style: GoogleFonts.dmSans(
            fontSize: 12, color: dmTxtSub)),
        const SizedBox(height: 16),
        child,
      ]),
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
        gradient: RadialGradient(colors: [color.withOpacity(opacity), Colors.transparent])),
  );

  Future<void> _persistToAppState() async {
    final slotsRaw = <String, List<List<String>>>{};
    _slots.forEach((day, list) {
      slotsRaw[day] = list.map((s) => [s.start, s.end]).toList();
    });
    await AppStateProvider.of(context).updateAvailability(
      days: _days,
      slots: slotsRaw,
      maxPerDay: _maxPerDay,
      bufferMinutes: _bufferMinutes,
    );
  }

  Future<void> _showSaved() async {
    await _persistToAppState();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dmAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text('Availability saved!', style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    ));
  }
}

class _Slot {
  String start;
  String end;
  _Slot(this.start, this.end);
}
