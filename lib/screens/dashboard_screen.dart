import 'dart:math' as math;
import 'dart:typed_data';
import 'call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/drawer_widget.dart';
import '../widgets/appointly_hand_icon.dart';
import '../models/appointment.dart';
import '../user_session.dart';
import '../database/bd_helper.dart';
import 'incoming_requests_screen.dart';
import 'profile_screen.dart';
import 'action_screens.dart';
import '../screens/personal_tasks_screen.dart';
import 'personal_tasks_screen.dart';
import 'appointment_detail_screen.dart';
import '../chat/chat.dart';
import 'my_availability_screen.dart';
import 'my_appointments_screen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // 0.0 = fully expanded, 1.0 = fully collapsed — drives smooth scroll-linked header
  late final ValueNotifier<double> _headerProgress;
  bool _isPinned = false;

  // Scroll controllers for each tab
  final ScrollController _homeScrollCtrl     = ScrollController();
  final ScrollController _scheduleScrollCtrl = ScrollController();
  final ScrollController _actionsScrollCtrl  = ScrollController();
  final ScrollController _clientsScrollCtrl  = ScrollController();

  // Accessibility FAB state
  bool _showAccessFAB = false;
  double _fabRight = 16.0;
  double _fabBottom = 80.0;
  // ValueNotifier lets only the Positioned child rebuild during drag (not the whole screen)
  late final ValueNotifier<Offset> _fabPosNotifier;
  String _userStatus = 'Available';
  String _userPrivacy = 'Public';

  late TabController _tabController;
  late AnimationController _heroCtrl;
  late AnimationController _cardsCtrl;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;
  late Animation<double> _cardsFade;
  int _selectedTab = 0;

  int    _selectedDayIndex = 0; // set in initState to today
  bool   _showNotifications = false;

  // ── Chart filters ──────────────────────────────────────────────────────────
  String _chartPeriod = 'This Week';
  String _chartMetric = 'All';

  // ── Schedule: computed real-date week (Sun=0..Sat=6) ─────────────────────
  static int _todayWeekIdx() {
    return DateTime.now().weekday % 7; // Mon=1→1 ... Sun=7→0
  }
  static DateTime _weekStart() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: _todayWeekIdx()));
  }
  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _weekStart().add(Duration(days: i)));
  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  String get _userName     => UserSession.instance.fullName.isNotEmpty ? UserSession.instance.fullName : 'User';
  String get _userInitials => UserSession.instance.initials;
  String get _firstName    => UserSession.instance.firstName;

  /// Returns ordinal label: 1 → "1st", 2 → "2nd", 3 → "3rd", 4 → "4th" …
  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1:  return '${n}st';
      case 2:  return '${n}nd';
      case 3:  return '${n}rd';
      default: return '${n}th';
    }
  }

  /// Bottom-sheet shown when a cancelled appointment tile is tapped.
  void _showCancelledOptions(Appointment a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20, 12, 20,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: _border, borderRadius: BorderRadius.circular(2))),
            Row(children: [
              CircleAvatar(radius: 22,
                  backgroundColor: a.avatarColor.withOpacity(0.15),
                  child: Text(a.initials, style: GoogleFonts.dmSans(
                      fontSize: 13, fontWeight: FontWeight.w900,
                      color: a.avatarColor))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(a.name, style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w800, color: _txtMain)),
                Text('${a.service} · Cancelled', style: GoogleFonts.dmSans(
                    fontSize: 12, color: const Color(0xFFB83232))),
              ])),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _sheetBtn(
                label: 'Reschedule',
                icon: Icons.edit_calendar_rounded,
                bg: _accent.withOpacity(0.1),
                fg: _accent,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => RescheduleScreen(
                        appointment: a,
                        onConfirm: (newDt, {String note = ''}) async {
                          await AppStateProvider.of(context).updateAppointment(
                            a.copyWith(
                              dateTime: newDt,
                              status: ApptStatus.confirmed,
                              cancellationNote: note,
                            ),
                          );
                        },
                      )));
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _sheetBtn(
                label: 'Re-confirm',
                icon: Icons.check_circle_rounded,
                bg: const Color(0xFF2ECC96).withOpacity(0.1),
                fg: const Color(0xFF2ECC96),
                onTap: () async {
                  Navigator.pop(context);
                  if (a.id == null) return;
                  await AppStateProvider.of(context)
                      .updateAppointmentStatus(a.id!, ApptStatus.confirmed);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Appointment re-confirmed!',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFF2ECC96),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ));
                  }
                },
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showAppointmentSheet(Appointment a) {
    // For cancelled: show reschedule/re-confirm options
    if (a.status == ApptStatus.cancelled) {
      _showCancelledOptions(a);
      return;
    }
    // For all other statuses: push full detail screen
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointment: a)));
  }

  Widget _sheetBtn({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: fg.withOpacity(0.3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 7),
            Text(label, style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      );

  // Pills are built dynamically from AppState — no hardcoded list

  // ── Real appointment accessors (read from AppState) ──────────────────────
  List<Appointment> get _currentDayAppts =>
      AppStateProvider.of(context).appointmentsForDate(_weekDays[_selectedDayIndex])
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  // Tracks which notification keys the user has marked read
  final Set<String> _readNotifs = {};

  int get _unreadCount => _liveNotifications.where((n) => !(n['read'] as bool)).length;

  List<Map<String, dynamic>> get _liveNotifications {
    final all = AppStateProvider.of(context).appointments;
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    String relTime(DateTime dt) {
      final diff = now.difference(dt).abs();
      if (diff.inMinutes < 1)  return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }
    String ahead(DateTime dt) {
      final diff = dt.difference(now);
      if (diff.inMinutes < 60) return 'in ${diff.inMinutes}m';
      if (diff.inHours   < 24) return 'in ${diff.inHours}h';
      return 'Tomorrow';
    }

    for (final a in all) {
      // Upcoming within 3 hours (unread by default)
      if ((a.status == ApptStatus.confirmed || a.status == ApptStatus.pending) &&
          a.dateTime.isAfter(now) &&
          a.dateTime.difference(now).inHours < 3) {
        final key = 'upcoming_${a.id}';
        result.add({'key': key, 'icon': Icons.notifications_active_rounded,
          'title': 'Upcoming appointment', 'sub': '${a.name} — ${a.time}',
          'time': ahead(a.dateTime), 'read': _readNotifs.contains(key),
          'color': const Color(0xFFF4A24A)});
      }
      // Completed today
      if (a.status == ApptStatus.completed && a.isToday) {
        final key = 'done_${a.id}';
        result.add({'key': key, 'icon': Icons.task_alt_rounded,
          'title': 'Session completed', 'sub': '${a.name} — ${a.time}',
          'time': relTime(a.dateTime), 'read': _readNotifs.contains(key),
          'color': const Color(0xFF2E7D32)});
      }
      // Cancelled today or recently confirmed
      if (a.status == ApptStatus.cancelled && a.isToday) {
        final key = 'cancel_${a.id}';
        result.add({'key': key, 'icon': Icons.cancel_rounded,
          'title': 'Booking cancelled', 'sub': '${a.name} — ${a.time}',
          'time': relTime(a.dateTime), 'read': _readNotifs.contains(key),
          'color': const Color(0xFFE05C5C)});
      }
      // Pending today (awaiting confirmation)
      if (a.status == ApptStatus.pending && a.isToday) {
        final key = 'pending_${a.id}';
        result.add({'key': key, 'icon': Icons.hourglass_top_rounded,
          'title': 'Awaiting confirmation', 'sub': '${a.name} — ${a.time}',
          'time': relTime(a.dateTime), 'read': _readNotifs.contains(key),
          'color': const Color(0xFF4A90D9)});
      }
      // Confirmed (non-expired, today)
      if (a.status == ApptStatus.confirmed && a.isToday && !a.isExpired) {
        final key = 'confirmed_${a.id}';
        result.add({'key': key, 'icon': Icons.check_circle_rounded,
          'title': 'Appointment confirmed', 'sub': '${a.name} — ${a.time}',
          'time': relTime(a.dateTime), 'read': _readNotifs.contains(key),
          'color': const Color(0xFF0B3D91)});
      }
    }

    // Unread first, then sort by appointment time descending
    result.sort((a, b) {
      final ra = (a['read'] as bool) ? 1 : 0;
      final rb = (b['read'] as bool) ? 1 : 0;
      return ra.compareTo(rb);
    });
    return result.take(12).toList();
  }

  // Pixels of scroll over which the header fully collapses
  // Kept tight (160px) so the header moves at near 1:1 with the finger —
  // the "screen going up" effect works best when collapse is snappy.
  static const double _collapseRange = 160.0;

  void _onScroll(ScrollController ctrl) {
    if (_isPinned) return;
    final offset = ctrl.hasClients ? ctrl.offset : 0.0;
    _headerProgress.value = (offset / _collapseRange).clamp(0.0, 1.0);
  }

  // Sync header progress with current tab's scroll position (e.g. on tab switch)
  void _syncHeaderWithCurrentTab() {
    if (_isPinned) return;
    ScrollController activeCtrl;
    switch (_selectedTab) {
      case 0: activeCtrl = _homeScrollCtrl; break;
      case 1: activeCtrl = _scheduleScrollCtrl; break;
      case 2: activeCtrl = _actionsScrollCtrl; break;
      case 3: activeCtrl = _clientsScrollCtrl; break;
      default: activeCtrl = _homeScrollCtrl;
    }
    if (!activeCtrl.hasClients) return;
    _headerProgress.value = (activeCtrl.offset / _collapseRange).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _headerProgress = ValueNotifier(0.0);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
        _syncHeaderWithCurrentTab();
      }
    });

    _heroCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _cardsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _heroFade  = CurvedAnimation(parent: _heroCtrl,  curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));
    _cardsFade = CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOut);
    _heroCtrl.forward();
    Future.delayed(const Duration(milliseconds: 300), () => _cardsCtrl.forward());

    // Set today as the default selected day
    _selectedDayIndex = _todayWeekIdx();

    // Initialize FAB position notifier; async _loadFabPosition will update it
    _fabPosNotifier = ValueNotifier(Offset(_fabRight, _fabBottom));

    // Load persisted FAB position
    _loadFabPosition();

    // Add scroll listeners
    void addListener(ScrollController ctrl) => ctrl.addListener(() => _onScroll(ctrl));
    addListener(_homeScrollCtrl);
    addListener(_scheduleScrollCtrl);
    addListener(_actionsScrollCtrl);
    addListener(_clientsScrollCtrl);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _heroCtrl.dispose();
    _cardsCtrl.dispose();
    _homeScrollCtrl.dispose();
    _scheduleScrollCtrl.dispose();
    _actionsScrollCtrl.dispose();
    _clientsScrollCtrl.dispose();
    _headerProgress.dispose();
    _fabPosNotifier.dispose();
    super.dispose();
  }

  // ── FAB position persistence ───────────────────────────────────────────────
  Future<void> _loadFabPosition() async {
    final uid = UserSession.instance.userId;
    if (uid == null) return;
    final rStr = await DBHelper.instance.getUserSetting(uid, 'fab_right');
    final bStr = await DBHelper.instance.getUserSetting(uid, 'fab_bottom');
    if (!mounted) return;
    final mq         = MediaQuery.of(context);
    final statusBarH = mq.padding.top;
    final navBarH    = mq.padding.bottom;
    const fabSize    = 60.0;
    const margin     = 12.0;
    // kBottomBarCoreH: fixed height of the Scaffold's custom bottom navigation bar
    // (outer padding 8+8 + inner padding 10+10 + icon 20 + label ~14 ≈ 70px)
    const kBottomBarCoreH = 70.0;
    setState(() {
      _fabRight  = (double.tryParse(rStr ?? '') ?? 16.0)
          .clamp(margin, mq.size.width  - fabSize - margin);
      _fabBottom = (double.tryParse(bStr ?? '') ?? 80.0)
          .clamp(navBarH + margin,
          mq.size.height - kBottomBarCoreH - navBarH - fabSize - statusBarH - margin);
    });
    // Sync the ValueNotifier so the lightweight FAB overlay shows the correct position
    _fabPosNotifier.value = Offset(_fabRight, _fabBottom);
  }

  Future<void> _saveFabPosition() async {
    final uid = UserSession.instance.userId;
    if (uid == null) return;
    // Read current position from the notifier (most up-to-date after dragging)
    final pos = _fabPosNotifier.value;
    await DBHelper.instance.setUserSetting(uid, 'fab_right',  pos.dx.toStringAsFixed(2));
    await DBHelper.instance.setUserSetting(uid, 'fab_bottom', pos.dy.toStringAsFixed(2));
  }

  bool get _dark => AppState_ext.of(context);
  Color get _bg          => AppStateProvider.of(context).bg;
  Color get _cardBg      => AppStateProvider.of(context).cardBg;
  Color get _border      => AppStateProvider.of(context).border;
  Color get _txtMain     => AppStateProvider.of(context).txtMain;
  Color get _txtSub      => AppStateProvider.of(context).txtSub;
  Color get _accent      => AppStateProvider.of(context).accent;
  List<Color> get _btnGradient => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow   => AppStateProvider.of(context).btnShadow;

  PageRoute _route(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 350),
  );

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: DrawerWidget(userName: _userName, userInitials: _userInitials),
      body: Stack(children: [
        Column(children: [
          ValueListenableBuilder<double>(
            valueListenable: _headerProgress,
            builder: (_, rawProgress, __) {
              final progress = _isPinned ? 0.0 : rawProgress;
              // ── Physical "screen going up" feel ───────────────────────
              // Use LINEAR progress (no easing) so the header moves at
              // exactly the same pace as the user's finger — 1:1 physical.
              // Content slides UPWARD inside the ClipRect faster than the
              // clip shrinks, so it feels like a page peeling off the top.
              final contentOpacity = (1.0 - progress / 0.65).clamp(0.0, 1.0);
              // Linear height shrink — physical, not eased
              final heightFactor   = (1.0 - progress).clamp(0.0, 1.0);
              // Content translate: slides up at 1.4× the height reduction
              // — this is the core "screen going up" effect
              final slideUp        = progress * 55.0;
              final heroColors     = AppStateProvider.of(context).heroGradient;

              return SlideTransition(
                position: _heroSlide,
                child: FadeTransition(
                  opacity: _heroFade,
                  child: Container(
                    decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: heroColors,
                      stops: const [0.0, 0.35, 0.7, 1.0],
                    )),
                    child: Stack(children: [
                      // Decorative orbs — fade with content
                      Positioned(right: -50, top: -50,
                          child: Opacity(opacity: contentOpacity, child: _orb(220, _accent, 0.14))),
                      Positioned(left: -40, bottom: 20,
                          child: Opacity(opacity: contentOpacity, child: _orb(160, Colors.white, 0.05))),
                      Positioned(right: 80, bottom: -15,
                          child: Opacity(opacity: contentOpacity, child: _orb(90, _accent, 0.18))),
                      SafeArea(bottom: false, child: Column(children: [
                        // Top row — slides up and clips away (physical scroll)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: heightFactor,
                            child: Transform.translate(
                              offset: Offset(0, -slideUp * 1.1),
                              child: Opacity(opacity: contentOpacity, child: _buildTopRow()),
                            ),
                          ),
                        ),
                        // Greeting + stat pills — slide up slightly slower
                        // (parallax layering so they all move together)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: heightFactor,
                            child: Transform.translate(
                              offset: Offset(0, -slideUp * 0.65),
                              child: Opacity(
                                opacity: contentOpacity,
                                child: Column(children: [
                                  _buildGreeting(),
                                  _buildStatPills(),
                                ]),
                              ),
                            ),
                          ),
                        ),
                        // Search bar — always visible, anchors the header bottom
                        _buildSearchBar(),
                      ])),
                    ]),
                  ),
                ),
              );
            },
          ),
          Expanded(child: TabBarView(controller: _tabController, children: [
            _buildHomeTab(), _buildScheduleTab(), _buildActionsTab(), _buildClientsTab(),
          ])),
        ]),
        // ── Notification overlay with smooth fade ────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _showNotifications
              ? Stack(
            key: const ValueKey('notif-open'),
            children: [
              GestureDetector(
                onTap: () => setState(() => _showNotifications = false),
                child: AnimatedOpacity(
                  opacity: _showNotifications ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(color: Colors.black.withOpacity(0.4)),
                ),
              ),
              _buildNotificationPanel(),
            ],
          )
              : const SizedBox.shrink(key: ValueKey('notif-closed')),
        ),
        _buildDraggableFABOverlay(),
      ]),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── DRAGGABLE ACCESSIBILITY FAB OVERLAY ────────────────────────────────────
  Widget _buildDraggableFABOverlay() {
    final appState = AppStateProvider.of(context);
    if (!appState.showAccessibilityButton) return const SizedBox.shrink();

    const fabSize = 60.0;
    const margin  = 12.0;
    // Fixed height of the Scaffold's custom bottom navigation bar
    // (outer padding 8+8 + inner padding 10+10 + icon 20 + label ~14 ≈ 70px)
    const kBottomBarCoreH = 70.0;

    final mq         = MediaQuery.of(context);
    final statusBarH = mq.padding.top;
    final navBarH    = mq.padding.bottom;
    final screenH    = mq.size.height;
    final screenW    = mq.size.width;

    // Maximum bottom value: keeps the FAB top edge just below the status bar.
    // stackHeight = screenH - kBottomBarCoreH - navBarH
    // To keep FAB top >= statusBarH + margin:
    // maxBottom = stackHeight - fabSize - statusBarH - margin
    final maxBottom = screenH - kBottomBarCoreH - navBarH - fabSize - statusBarH - margin;
    // Minimum bottom value: keeps the bottom edge above the system nav bar
    final minBottom = navBarH + margin;
    // Left/right clamping via right offset
    final maxRight  = screenW - fabSize - margin;
    const minRight  = margin;

    // ── Positioned.fill hosts a nested Stack so the ValueListenableBuilder
    //    can reposition the FAB on every drag frame WITHOUT rebuilding the full
    //    dashboard screen. The parent setState fires only for tap interactions.
    return Positioned.fill(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _fabPosNotifier,
        builder: (_, fabPos, __) {
          final clampedRight  = fabPos.dx.clamp(minRight,  maxRight);
          final clampedBottom = fabPos.dy.clamp(minBottom, maxBottom);

          // The Scaffold body Stack height (excludes status bar + bottom bars).
          final stackH = screenH - statusBarH - kBottomBarCoreH - navBarH;

          // FAB's actual position relative to the Stack's top-left corner.
          final fabLeft = screenW - clampedRight - fabSize;
          final fabTop  = stackH  - clampedBottom - fabSize;

          // Which quadrant is the FAB in?
          //   isOnLeft → popup should open to the RIGHT  (anchor Positioned by left:)
          //   isOnTop  → popup should open DOWNWARD      (anchor Positioned by top:)
          final isOnLeft = fabLeft < screenW / 2;
          final isOnTop  = fabTop  < stackH  / 2;

          // Build Positioned with the correct anchor so the popup always
          // expands toward the centre of the screen and stays fully visible.
          return Stack(
            children: [
              Positioned(
                // Horizontal anchor: left: when FAB is on left half,
                //                    right: when FAB is on right half.
                left:   isOnLeft ? fabLeft       : null,
                right:  isOnLeft ? null          : clampedRight,
                // Vertical anchor:   top: when FAB is in top half,
                //                    bottom: when FAB is in bottom half.
                top:    isOnTop  ? fabTop        : null,
                bottom: isOnTop  ? null          : clampedBottom,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    // Update notifier directly — no setState on parent
                    _fabPosNotifier.value = Offset(
                      (fabPos.dx - details.delta.dx).clamp(minRight,  maxRight),
                      (fabPos.dy - details.delta.dy).clamp(minBottom, maxBottom),
                    );
                    // Close the menu if it was open (single setState, not per-frame)
                    if (_showAccessFAB) setState(() => _showAccessFAB = false);
                  },
                  onPanEnd: (_) => _saveFabPosition(),
                  child: _buildAccessibilityFAB(
                    isOnLeft: isOnLeft,
                    isOnTop: isOnTop,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── ACCESSIBILITY FAB ──────────────────────────────────────────────────────
  Color get _statusColor {
    switch (_userStatus) {
      case 'Available': return const Color(0xFF2ECC96);
      case 'Busy':      return const Color(0xFFF4A24A);
      case 'Leave':     return const Color(0xFF8AA0BC);
      default:          return _accent;
    }
  }
  IconData get _statusIcon {
    switch (_userStatus) {
      case 'Available': return Icons.check_circle_rounded;
      case 'Busy':      return Icons.do_not_disturb_rounded;
      case 'Leave':     return Icons.beach_access_rounded;
      default:          return Icons.circle_rounded;
    }
  }
  IconData get _privacyIcon {
    switch (_userPrivacy) {
      case 'Public':        return Icons.public_rounded;
      case 'Contacts Only': return Icons.people_rounded;
      case 'Protected':     return Icons.verified_user_rounded;
      case 'Private':       return Icons.lock_rounded;
      default:              return Icons.public_rounded;
    }
  }
  Color get _privacyColor {
    switch (_userPrivacy) {
      case 'Public':        return const Color(0xFF2ECC96);
      case 'Contacts Only': return const Color(0xFF4A90D9);
      case 'Protected':     return const Color(0xFFF4A24A);
      case 'Private':       return const Color(0xFFE05C5C);
      default:              return _accent;
    }
  }

  Widget _buildAccessibilityFAB({bool isOnLeft = false, bool isOnTop = false}) {
    // The popup margin sits between the FAB button and the popup panel.
    // When the FAB is in the top half we open the popup BELOW the button,
    // so the gap goes on top; otherwise it goes on the bottom (default).
    final popupMargin = isOnTop
        ? const EdgeInsets.only(top: 10)
        : const EdgeInsets.only(bottom: 10);

    // Horizontal alignment of the popup relative to the FAB button:
    //   • Right half of screen → align popup to the RIGHT edge (default)
    //   • Left  half of screen → align popup to the LEFT  edge
    final colAlign = isOnLeft
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;

    final popupPanel = AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: _showAccessFAB
          ? Container(
        width: 230,
        margin: popupMargin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 30, height: 30,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [_accent, _accent.withOpacity(0.7)]), borderRadius: BorderRadius.circular(9)),
                child: Center(child: AppointlyHandIcon(size: 16, color: Colors.white))),
            const SizedBox(width: 8),
            Text('Quick Access', style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w900, color: _txtMain)),
          ]),
          const SizedBox(height: 10),
          _fabBtn(Icons.add_circle_rounded, 'New Appointment', _accent, () {
            setState(() => _showAccessFAB = false);
            Navigator.push(context, _route(const NewAppointmentScreen()));
          }),
          const SizedBox(height: 6),
          _fabBtn(_statusIcon, 'Status: $_userStatus', _statusColor, () {
            setState(() {
              final statuses = ['Available','Busy','Leave'];
              _userStatus = statuses[(statuses.indexOf(_userStatus)+1) % statuses.length];
              _showAccessFAB = false;
            });
          }),
          const SizedBox(height: 6),
          _fabBtn(_privacyIcon, 'Privacy: $_userPrivacy', _privacyColor, () {
            setState(() {
              final modes = ['Public','Contacts Only','Protected','Private'];
              _userPrivacy = modes[(modes.indexOf(_userPrivacy)+1) % modes.length];
              _showAccessFAB = false;
            });
          }),
          const SizedBox(height: 6),
          _fabBtn(Icons.notifications_rounded, 'Notifications', const Color(0xFFF4A24A), () {
            setState(() { _showNotifications = true; _showAccessFAB = false; });
          }),
          const SizedBox(height: 6),
          _fabBtn(Icons.palette_rounded, 'Theme: ${AppStateProvider.of(context).themeMode.label}', const Color(0xFF9333EA), () {
            final appState = AppStateProvider.of(context);
            final modes = AppThemeMode.values
                .where((m) => m != AppThemeMode.customDark && m != AppThemeMode.customLight)
                .toList();
            final next = modes[(modes.indexOf(appState.themeMode)+1) % modes.length];
            appState.setTheme(next);
            setState(() => _showAccessFAB = false);
          }),
          const SizedBox(height: 6),
          _fabBtn(Icons.person_rounded, 'My Profile', const Color(0xFF2ECC96), () {
            setState(() => _showAccessFAB = false);
            Navigator.push(context, _route(const ProfileScreen())).then((_) => setState(() {}));
          }),
        ]),
      )
          : const SizedBox.shrink(),
    );

    final fabButton = Stack(
      alignment: Alignment.center,
      children: [
        // Themed background container — keeps icon visible on ALL themes
        GestureDetector(
          onTap: () => setState(() => _showAccessFAB = !_showAccessFAB),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_accent, _accent.withOpacity(0.75)],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            child: Center(
              child: AppointlyHandIcon(
                isClose: _showAccessFAB,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // Status dot (when closed)
        if (!_showAccessFAB)
          Positioned(
            top: 2, right: 2,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: _statusColor.withOpacity(0.5), blurRadius: 4)],
              ),
            ),
          ),
      ],
    );

    // Build the Column with correct child order and alignment based on position:
    //   • isOnTop  → FAB button first, popup panel below (avoids top overflow)
    //   • !isOnTop → popup panel first (above), FAB button below (default)
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: colAlign,
      children: isOnTop
          ? [fabButton, popupPanel]
          : [popupPanel, fabButton],
    );
  }

  Widget _fabBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: GoogleFonts.dmSans(
                fontSize: 12, fontWeight: FontWeight.w700, color: _txtMain),
                overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );

  // ── BOTTOM NAV ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final tabs = [
      {'icon': Icons.home_rounded,           'label': 'Home'},
      {'icon': Icons.calendar_today_rounded, 'label': 'Schedule'},
      {'icon': Icons.bolt_rounded,           'label': 'Actions'},
      {'icon': Icons.people_alt_rounded,     'label': 'Clients'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.1),
            blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: List.generate(tabs.length, (i) {
          final sel = _selectedTab == i;
          return Expanded(child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _tabController.animateTo(i);
              setState(() => _selectedTab = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: AppStateProvider.of(context).btnGradient,
                ) : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: sel ? [BoxShadow(
                    color: AppStateProvider.of(context).btnShadow.withOpacity(0.35),
                    blurRadius: 12, offset: const Offset(0, 4))] : [],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(tabs[i]['icon'] as IconData, size: 20,
                    color: sel ? Colors.white : _txtSub),
                const SizedBox(height: 4),
                Text(tabs[i]['label'] as String,
                    style: GoogleFonts.dmSans(fontSize: 10.5,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                        color: sel ? Colors.white : _txtSub)),
              ]),
            ),
          ));
        })),
      )),
    );
  }

  // ── FULL HERO HEADER ──────────────────────────────────────────────────────
  Widget _buildHero() {
    final heroColors = AppStateProvider.of(context).heroGradient;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: heroColors,
        stops: const [0.0, 0.35, 0.7, 1.0],
      )),
      child: Stack(children: [
        Positioned(right: -50, top: -50,
            child: _orb(220, _accent, 0.14)),
        Positioned(left: -40, bottom: 20,
            child: _orb(160, Colors.white, 0.05)),
        Positioned(right: 80, bottom: -15,
            child: _orb(90, _accent, 0.18)),
        SafeArea(bottom: false, child: Column(children: [
          _buildTopRow(),
          _buildGreeting(),
          _buildStatPills(),
          _buildSearchBar(),
        ])),
      ]),
    );
  }

  Widget _buildTopRow() {
    final unreadChats = 6; // sum of inbox unread
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(children: [
        // ── Menu ───────────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: _glassBox(child: const Icon(Icons.menu_rounded, color: Colors.white, size: 21)),
        ),

        const Spacer(),

        // ── Chat icon with unread badge ────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.push(context, _route(const ChatInboxScreen())),
          child: Stack(clipBehavior: Clip.none, children: [
            _glassBox(
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 20),
            ),
            if (unreadChats > 0)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFFF4A24A), const Color(0xFFE07C2A)],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppStateProvider.of(context).heroGradient.first,
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFF4A24A).withOpacity(0.55),
                          blurRadius: 6),
                    ],
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 10),

        // ── Bell ───────────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _showNotifications = !_showNotifications),
          child: Stack(children: [
            _glassBox(child: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 21)),
            if (_unreadCount > 0)
              Positioned(top: 8, right: 8, child: Container(
                width: 9, height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4A24A),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppStateProvider.of(context).heroGradient.first,
                      width: 1.5),
                ),
              )),
          ]),
        ),
        const SizedBox(width: 10),

        // ── Profile avatar ─────────────────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.push(context, _route(const ProfileScreen())).then((_) => setState(() {})),
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _btnGradient),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
              boxShadow: [BoxShadow(
                  color: _btnShadow.withOpacity(0.5), blurRadius: 10)],
            ),
            child: ClipOval(child: UserSession.instance.profileImageBytes != null
                ? Image.memory(UserSession.instance.profileImageBytes!,
                fit: BoxFit.cover, width: 42, height: 42)
                : Center(child: Text(_userInitials, style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w900,
                color: Colors.white)))),
          ),
        ),
      ]),
    );
  }

  String _currentDateString() {
    final now = DateTime.now();
    const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months   = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(_currentDateString(),
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 12,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text('Good morning, $_firstName!',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 25,
                fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.8)),
        const SizedBox(height: 4),
        Text('You have ${AppStateProvider.of(context).appointments.where((a) => a.isToday).length} appointments today',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 13,
                color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildStatPills() {
    final appState = AppStateProvider.of(context);
    final accentC  = appState.accent;
    final all      = appState.appointments;

    final todayCount = all.where((a) => a.isToday).length;

    // Unique client names
    final clientCount = all.map((a) => a.name.trim().toLowerCase()).toSet().length;

    final pendingCount = all.where((a) => a.status == ApptStatus.pending).length;

    // Completed this week
    final now       = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd   = weekStart.add(const Duration(days: 7));
    final completedThisWeek = all.where((a) =>
    (a.status == ApptStatus.completed ||
        (a.status == ApptStatus.confirmed && a.isExpired)) &&
        !a.dateTime.isBefore(weekStart) &&
        a.dateTime.isBefore(weekEnd)).length;

    final confirmedToday = all.where((a) =>
    a.isToday && a.status == ApptStatus.confirmed).length;

    final pills = [
      {'label': 'TODAY',     'value': '$todayCount',         'trend': 'Appointments'},
      {'label': 'CLIENTS',   'value': '$clientCount',        'trend': 'Unique'},
      {'label': 'PENDING',   'value': '$pendingCount',       'trend': 'Unconfirmed'},
      {'label': 'DONE',      'value': '$completedThisWeek',  'trend': 'This week'},
    ];

    return SizedBox(
      height: 80,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        scrollDirection: Axis.horizontal,
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(
          width: 106,
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(pills[i]['label']!, style: GoogleFonts.dmSans(fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.45), letterSpacing: 0.8)),
                  Text(pills[i]['value']!, style: GoogleFonts.dmSans(fontSize: 19,
                      fontWeight: FontWeight.w900, color: Colors.white,
                      height: 1.0, letterSpacing: -0.5)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentC.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(pills[i]['trend']!, style: GoogleFonts.dmSans(
                        fontSize: 8.5, fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.85)),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Row(children: [
        Expanded(child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(children: [
            Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4), size: 19),
            const SizedBox(width: 10),
            Text('Search appointments...', style: GoogleFonts.dmSans(
                color: Colors.white.withOpacity(0.35), fontSize: 13)),
          ]),
        )),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => setState(() {
            _isPinned = !_isPinned;
            if (!_isPinned) {
              _syncHeaderWithCurrentTab();
            } else {
              _headerProgress.value = 0.0;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 44, width: 44,
            decoration: BoxDecoration(
              gradient: _isPinned
                  ? LinearGradient(colors: _btnGradient)
                  : null,
              color: _isPinned ? null : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Center(
              child: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── MINIMIZED SEARCH‑ONLY BAR ─────────────────────────────────────────────
  Widget _buildMinimizedSearchOnly() {
    final heroColors = AppStateProvider.of(context).heroGradient;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: heroColors,
        stops: const [0.0, 0.35, 0.7, 1.0],
      )),
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Row(children: [
          Expanded(child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4), size: 19),
              const SizedBox(width: 10),
              Text('Search appointments...', style: GoogleFonts.dmSans(
                  color: Colors.white.withOpacity(0.35), fontSize: 13)),
            ]),
          )),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => setState(() {
              _isPinned = !_isPinned;
              if (!_isPinned) {
                _syncHeaderWithCurrentTab();
              } else {
                _headerProgress.value = 0.0;
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44, width: 44,
              decoration: BoxDecoration(
                gradient: _isPinned ? LinearGradient(colors: _btnGradient) : null,
                color: _isPinned ? null : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Center(
                child: Icon(
                  _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: Colors.white, size: 20,
                ),
              ),
            ),
          ),
        ]),
      )),
    );
  }

  // ── NOTIFICATION PANEL ─────────────────────────────────────────────────────
  Widget _buildNotificationPanel() {
    return Positioned(
      top: 0, right: 0, left: 0,
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 68, 14, 0),
        child: Material(color: Colors.transparent, child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border, width: 1.5),
            boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.3),
                blurRadius: 32, offset: const Offset(0, 12))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _btnGradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Notifications', style: GoogleFonts.dmSans(
                      fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
                  Text('$_unreadCount unread', style: GoogleFonts.dmSans(
                      fontSize: 11, color: _txtSub, fontWeight: FontWeight.w500)),
                ])),
                GestureDetector(
                  onTap: () => setState(() => _showNotifications = false),
                  child: Container(width: 32, height: 32,
                      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.close_rounded, color: _txtSub, size: 18)),
                ),
              ]),
            ),
            Divider(color: _border, height: 1, thickness: 1),
            if (_liveNotifications.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(children: [
                  Icon(Icons.notifications_none_rounded, size: 36, color: _txtSub.withOpacity(0.4)),
                  const SizedBox(height: 10),
                  Text('No notifications today', style: GoogleFonts.dmSans(
                      fontSize: 13, color: _txtSub, fontWeight: FontWeight.w500)),
                ]),
              ),
            ...List.generate(_liveNotifications.length, (i) {
              final n = _liveNotifications[i];
              final read = n['read'] as bool;
              return GestureDetector(
                  onTap: () => setState(() => _readNotifs.add(n['key'] as String)),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(10, 5, 10, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: read ? Colors.transparent : (n['color'] as Color).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: read ? Colors.transparent : (n['color'] as Color).withOpacity(0.15),
                      ),
                    ),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                          decoration: BoxDecoration(
                              color: (n['color'] as Color).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(11)),
                          child: Icon(n['icon'] as IconData, color: n['color'] as Color, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n['title'] as String, style: GoogleFonts.dmSans(
                            fontSize: 12.5, fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                            color: _txtMain)),
                        const SizedBox(height: 2),
                        Text(n['sub'] as String, style: GoogleFonts.dmSans(
                            fontSize: 11, color: _txtSub, fontWeight: FontWeight.w500)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(n['time'] as String, style: GoogleFonts.dmSans(
                            fontSize: 10, color: _txtSub)),
                        if (!read) ...[
                          const SizedBox(height: 5),
                          Container(width: 7, height: 7, decoration: const BoxDecoration(
                              color: Color(0xFF4A90D9), shape: BoxShape.circle)),
                        ],
                      ]),
                    ]),
                  ));
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: GestureDetector(
                onTap: () => setState(() {
                  for (final n in _liveNotifications) { _readNotifs.add(n['key'] as String); }
                  _showNotifications = false;
                }),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _border),
                  ),
                  child: Text('Mark all as read', textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(fontSize: 13,
                          fontWeight: FontWeight.w700, color: _accent)),
                ),
              ),
            ),
          ]),
        )),
      )),
    );
  }

  // ── HOME TAB ────────────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _homeScrollCtrl,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: ConstrainedBox(
            // Guarantee the content is always tall enough to scroll
            // _collapseRange px — prevents the bouncing-header glitch on
            // short content where over-pull snaps back and jitters the header.
            constraints: BoxConstraints(
                minHeight: constraints.maxHeight + _collapseRange),
            child: FadeTransition(
              opacity: _cardsFade,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionLabel('Overview'),
                const SizedBox(height: 4),
                Text('Your business at a glance', style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: _txtSub,
                    fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),
                _buildStatCards(),
                const SizedBox(height: 14),
                _buildIncomingBanner(),
                const SizedBox(height: 18),
                _buildUpcomingSection(),
                const SizedBox(height: 18),
                RepaintBoundary(child: _buildWeeklyChart()),
                const SizedBox(height: 18),
                RepaintBoundary(child: _buildAnalyticsDonut()),
                const SizedBox(height: 18),
                RepaintBoundary(child: _buildClientSatisfactionCard()),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCards() {
    final appState = AppStateProvider.of(context);
    final accentC = appState.accent;
    final g = (int i) => appState.cardGradient(i);

    final now       = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd   = weekStart.add(const Duration(days: 7));
    final allAppts  = appState.appointments;

    final completedWeek = allAppts.where((a) =>
        a.status == ApptStatus.completed &&
        !a.dateTime.isBefore(weekStart) && a.dateTime.isBefore(weekEnd)).length;

    final pendingAll    = allAppts.where((a) =>
        a.status == ApptStatus.pending).length;

    final cancelledWeek = allAppts.where((a) =>
        a.status == ApptStatus.cancelled &&
        !a.dateTime.isBefore(weekStart) && a.dateTime.isBefore(weekEnd)).length;

    return Column(children: [
      Row(children: [
        _quickStatTile(
          icon: Icons.event_available_rounded,
          label: 'This Week',
          value: '$completedWeek',
          sub: 'Completed',
          gradColors: g(0),
          accentC: accentC,
        ),
        const SizedBox(width: 10),
        _quickStatTile(
          icon: Icons.pending_actions_rounded,
          label: 'Awaiting',
          value: '$pendingAll',
          sub: 'Unconfirmed',
          gradColors: g(1),
          accentC: accentC,
        ),
        const SizedBox(width: 10),
        _quickStatTile(
          icon: Icons.cancel_rounded,
          label: 'Cancelled',
          value: '$cancelledWeek',
          sub: 'This week',
          gradColors: g(2),
          accentC: accentC,
        ),
      ]),

    ]);
  }

  Widget _quickStatTile({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required List<Color> gradColors,
    required Color accentC,
  }) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: gradColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentC.withOpacity(0.2)),
        boxShadow: [BoxShadow(
          color: gradColors[0].withOpacity(0.4),
          blurRadius: 12, offset: const Offset(0, 5),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 28, height: 28,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 15)),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.dmSans(
            fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white,
            height: 1.0, letterSpacing: -0.8)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 9.5, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(sub, style: GoogleFonts.dmSans(
              fontSize: 8.5, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
        ),
      ]),
    ));
  }

  Widget _buildIncomingBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(context, _route(const IncomingRequestsScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: _btnGradient,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.5),
              blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(width: 50, height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.11),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Center(
              child: AnimatedAppointlyHandIcon(size: 28, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Incoming Requests', style: GoogleFonts.dmSans(
                fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 3),
            Text('3 new appointment requests waiting', style: GoogleFonts.dmSans(
                fontSize: 12, color: Colors.white.withOpacity(0.6))),
          ])),
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF4A24A), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFF4A24A).withOpacity(0.5), blurRadius: 8)]),
              child: Center(child: Text('3', style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)))),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.45), size: 14),
        ]),
      ),
    );
  }

  // ── CHART DATA SETS ────────────────────────────────────────────────────────
  // ── CHART: compute live from AppState ─────────────────────────────────────
  Map<String, dynamic> get _activeChartData {
    final all = AppStateProvider.of(context).appointments;
    final now = DateTime.now();

    bool matchMetric(Appointment a) {
      switch (_chartMetric) {
        case 'Confirmed': return a.status == ApptStatus.confirmed || a.status == ApptStatus.completed;
        case 'Cancelled': return a.status == ApptStatus.cancelled;
        case 'Pending':   return a.status == ApptStatus.pending;
        default:          return true; // All
      }
    }

    int countIn(DateTime start, DateTime end) =>
        all.where((a) => matchMetric(a) &&
            !a.dateTime.isBefore(start) && a.dateTime.isBefore(end)).length;

    switch (_chartPeriod) {
      case 'This Week': {
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        const labels = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
        final data = List.generate(7, (i) {
          final d = monday.add(Duration(days: i));
          return countIn(d, d.add(const Duration(days: 1)));
        });
        return {'data': data, 'labels': labels, 'todayIdx': now.weekday - 1};
      }
      case 'Last Week': {
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1 + 7));
        const labels = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
        final data = List.generate(7, (i) {
          final d = monday.add(Duration(days: i));
          return countIn(d, d.add(const Duration(days: 1)));
        });
        return {'data': data, 'labels': labels, 'todayIdx': -1};
      }
      case 'This Month': {
        final mStart = DateTime(now.year, now.month, 1);
        final labels = ['Wk 1','Wk 2','Wk 3','Wk 4'];
        final data = List.generate(4, (i) {
          final s = mStart.add(Duration(days: i * 7));
          final e = s.add(const Duration(days: 7));
          return countIn(s, e);
        });
        final todayIdx = ((now.day - 1) ~/ 7).clamp(0, 3);
        return {'data': data, 'labels': labels, 'todayIdx': todayIdx};
      }
      case 'Last 3 Months':
      default: {
        final months = List.generate(3, (i) =>
            DateTime(now.year, now.month - 2 + i, 1));
        final labels = months.map((m) {
          const mo = ['Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'];
          return mo[m.month - 1];
        }).toList();
        final data = List.generate(3, (i) {
          final s = months[i];
          final e = DateTime(s.year, s.month + 1, 1);
          return countIn(s, e);
        });
        return {'data': data, 'labels': labels, 'todayIdx': 2};
      }
    }
  }

  String get _chartSubtitle {
    switch (_chartPeriod) {
      case 'This Week':     return 'Day-by-day appointments this week';
      case 'Last Week':     return 'Day-by-day appointments last week';
      case 'This Month':    return 'Weekly breakdown this month';
      case 'Last 3 Months': return 'Monthly trend over last 3 months';
      default:              return 'Appointment performance';
    }
  }

  // ── WEEKLY LINE CHART ──────────────────────────────────────────────────────
  Widget _buildWeeklyChart() {
    final chartData = _activeChartData;
    final data     = (chartData['data']    as List).cast<int>();
    final labels   = (chartData['labels']  as List).cast<String>();
    final todayIdx = chartData['todayIdx'] as int;

    const periods = ['This Week', 'Last Week', 'This Month', 'Last 3 Months'];
    const metrics = ['All', 'Confirmed', 'Cancelled', 'Pending'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Title row ────────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Performance', style: GoogleFonts.dmSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 2),
            Text(_chartSubtitle, style: GoogleFonts.dmSans(
                fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
          ])),
          // Live total badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withOpacity(0.25)),
            ),
            child: Text(
              '${data.reduce((a, b) => a + b)} total',
              style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: _accent),
            ),
          ),
        ]),

        const SizedBox(height: 14),

        // ── Period filter chips ───────────────────────────────────────────────
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: periods.map((p) {
              final sel = _chartPeriod == p;
              return GestureDetector(
                onTap: () => setState(() => _chartPeriod = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: sel ? LinearGradient(colors: _btnGradient) : null,
                    color: sel ? null : _cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _accent.withOpacity(0.5) : _border,
                      width: 1.3,
                    ),
                    boxShadow: sel ? [BoxShadow(
                        color: _btnShadow.withOpacity(0.28),
                        blurRadius: 8, offset: const Offset(0, 3))] : [],
                  ),
                  child: Text(p, style: GoogleFonts.dmSans(
                      fontSize: 11.5, fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : _txtSub)),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        // ── Metric filter chips ───────────────────────────────────────────────
        SizedBox(
          height: 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: metrics.map((m) {
              final sel = _chartMetric == m;
              final metricColor = m == 'Confirmed' ? const Color(0xFF2ECC96)
                  : m == 'Cancelled' ? const Color(0xFFE05C5C)
                  : m == 'Pending'   ? const Color(0xFFF4A24A)
                  : _accent;
              return GestureDetector(
                onTap: () => setState(() => _chartMetric = m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? metricColor.withOpacity(0.14) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? metricColor.withOpacity(0.55) : _border.withOpacity(0.6),
                      width: 1.2,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: sel ? metricColor : _txtSub.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(m, style: GoogleFonts.dmSans(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: sel ? metricColor : _txtSub)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // ── Chart ─────────────────────────────────────────────────────────────
        SizedBox(height: 150, child: CustomPaint(
          painter: _LineChartPainter(
            data:           data,
            labels:         labels,
            todayIdx:       todayIdx,
            lineColor:      _chartMetric == 'Confirmed' ? const Color(0xFF2ECC96)
                : _chartMetric == 'Cancelled' ? const Color(0xFFE05C5C)
                : _chartMetric == 'Pending'   ? const Color(0xFFF4A24A)
                : _accent,
            todayDotColor:  _btnShadow,
            gridColor:      _border,
            labelColor:     _txtSub,
            todayLabelColor: _btnShadow,
            bgDark:         _dark,
          ),
          size: const Size(double.infinity, 150),
        )),

        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (todayIdx >= 0) ...[
            _legendDot(_btnShadow, 'Today'),
            const SizedBox(width: 20),
          ],
          _legendDot(
            _chartMetric == 'Confirmed' ? const Color(0xFF2ECC96)
                : _chartMetric == 'Cancelled' ? const Color(0xFFE05C5C)
                : _chartMetric == 'Pending'   ? const Color(0xFFF4A24A)
                : _accent,
            _chartMetric == 'All' ? 'Appointments' : _chartMetric,
          ),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: GoogleFonts.dmSans(
        fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w600)),
  ]);

  // ── DONUT CHART CARD ───────────────────────────────────────────────────────
  Widget _buildAnalyticsDonut() {
    final appState = AppStateProvider.of(context);
    final now      = DateTime.now();
    final todayAll = appState.appointments.where((a) =>
        a.dateTime.year  == now.year &&
        a.dateTime.month == now.month &&
        a.dateTime.day   == now.day).toList();

    final confirmedN = todayAll.where((a) => a.status == ApptStatus.confirmed).length;
    final completedN = todayAll.where((a) => a.status == ApptStatus.completed).length;
    final cancelledN = todayAll.where((a) => a.status == ApptStatus.cancelled).length;
    final totalN     = todayAll.length;

    final cFrac  = totalN > 0 ? confirmedN / totalN : 0.0;
    final dFrac  = totalN > 0 ? completedN / totalN : 0.0;
    final xFrac  = totalN > 0 ? cancelledN / totalN : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text("Today's Breakdown", style: GoogleFonts.dmSans(
              fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain))),
          Text('$totalN total', style: GoogleFonts.dmSans(
              fontSize: 12, color: _txtSub, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          SizedBox(width: 100, height: 100, child: CustomPaint(
            painter: _DonutPainter(
              trackColor: _border,
              accentColor: _accent,
              secondColor: _btnShadow,
              confirmedFrac: cFrac,
              completedFrac: dFrac,
              cancelledFrac: xFrac,
            ),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$totalN', style: GoogleFonts.dmSans(
                  fontSize: 22, fontWeight: FontWeight.w900, color: _txtMain, letterSpacing: -1)),
              Text('appts', style: GoogleFonts.dmSans(
                  fontSize: 9, color: _txtSub, fontWeight: FontWeight.w700)),
            ])),
          )),
          const SizedBox(width: 22),
          Expanded(child: Column(children: [
            _donutLeg(_accent, 'Confirmed', '$confirmedN'),
            const SizedBox(height: 10),
            _donutLeg(_btnShadow, 'Completed', '$completedN'),
            const SizedBox(height: 10),
            _donutLeg(const Color(0xFFE05C5C), 'Cancelled', '$cancelledN'),
          ])),
        ]),
      ]),
    );
  }

  Widget _donutLeg(Color c, String label, String count) => Row(children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 10),
    Expanded(child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 12.5, color: _txtSub, fontWeight: FontWeight.w500))),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Text(count, style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w900, color: c)),
    ),
  ]);

  // ── CLIENT SATISFACTION CARD ──────────────────────────────────────────────
  Widget _buildClientSatisfactionCard() {
    final appState = AppStateProvider.of(context);
    final g = (int i) => appState.cardGradient(i);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: _card(),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: g(0),
            ),
            shape: BoxShape.circle,
            border: Border.all(color: _accent.withOpacity(0.3), width: 2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('4.9', style: GoogleFonts.dmSans(
                fontSize: 18, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: -0.5, height: 1)),
            Icon(Icons.star_rounded, color: const Color(0xFFF4A24A), size: 13),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Client Satisfaction', style: GoogleFonts.dmSans(
              fontSize: 14.5, fontWeight: FontWeight.w800, color: _txtMain)),
          const SizedBox(height: 3),
          Text('Based on 87 reviews this month',
              style: GoogleFonts.dmSans(fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(children: List.generate(5, (i) => Icon(
            Icons.star_rounded, color: const Color(0xFFF4A24A), size: 15,
          ))),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2ECC96).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2ECC96).withOpacity(0.3)),
            ),
            child: Text('+6%', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: const Color(0xFF2ECC96))),
          ),
          const SizedBox(height: 4),
          Text('vs last\nmonth', textAlign: TextAlign.right,
              style: GoogleFonts.dmSans(fontSize: 9.5, color: _txtSub)),
        ]),
      ]),
    );
  }

  Widget _buildUpcomingSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionLabel("Today's Upcoming"),
        GestureDetector(
          onTap: () { _tabController.animateTo(1); setState(() => _selectedTab = 1); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Text('View All →', style: GoogleFonts.dmSans(
                fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Container(decoration: _card(), padding: const EdgeInsets.all(8),
        child: Column(children: AppStateProvider.of(context)
            .appointmentsForDate(DateTime.now())
            .take(3).map(_apptTile).toList()),
      ),
    ]);
  }

  // ── SCHEDULE TAB ───────────────────────────────────────────────────────────
  Widget _buildScheduleTab() {
    final days  = _weekDays;
    final today = days[_selectedDayIndex];
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final headerLabel =
        '${_dayNames[_selectedDayIndex]}, ${monthNames[today.month - 1]} ${today.day}';
    final appts = _currentDayAppts;

    return Stack(children: [
      Column(children: [
        // ── Date nav is STICKY — lives outside the scroll view so it
        //    stays visible no matter how far down the user scrolls ──────
        Container(
          color: _bg,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildDateNav(),
        ),

        // ── Scrollable day content ────────────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scheduleScrollCtrl,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                child: ConstrainedBox(
                  // Guarantee at least _collapseRange px of scrollable space
                  // so the header can always collapse fully without bouncing back.
                  constraints: BoxConstraints(
                      minHeight: constraints.maxHeight + _collapseRange),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Row(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(headerLabel, style: GoogleFonts.dmSans(
                                        fontSize: 26, fontWeight: FontWeight.w900,
                                        color: _txtMain, letterSpacing: -1)),
                                    Container(margin: const EdgeInsets.only(top: 5),
                                        width: 40, height: 4,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: _btnGradient),
                                          borderRadius: BorderRadius.circular(2),
                                        )),
                                    const SizedBox(height: 6),
                                    Text(
                                        '${appts.length} appointment${appts.length == 1 ? '' : 's'}',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13, color: _txtSub,
                                            fontWeight: FontWeight.w500)),
                                  ])),
                            ]),
                        const SizedBox(height: 22),
                        if (appts.isEmpty)
                          _buildEmptySchedule()
                        else
                          _buildScheduleCard(appts),
                      ]),
                ),
              );
            },
          ),
        ),
      ]),

      // Floating Add Task Button — bottom-left to avoid the accessibility FAB
      Positioned(
        bottom: 24, left: 16,
        child: GestureDetector(
          onTap: () => Navigator.push(context, _route(const NewAppointmentScreen())),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: _btnGradient,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _accent.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(color: _btnShadow.withOpacity(0.55),
                    blurRadius: 20, offset: const Offset(0, 8)),
                BoxShadow(color: _accent.withOpacity(0.25),
                    blurRadius: 12, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Text('Add Task', style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: -0.2)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Original schedule card (flat list of appointment tiles) ────────────────
  Widget _buildScheduleCard(List<Appointment> appts) {
    // Compute per-day sequential numbers; cancelled appointments get null (no badge).
    int dayCounter = 0;
    final List<int?> dayNums = appts.map((a) {
      if (a.status == ApptStatus.cancelled) return null;
      return ++dayCounter;
    }).toList();

    return Container(padding: const EdgeInsets.all(16), decoration: _card(),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Appointments', style: GoogleFonts.dmSans(
              fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
          GestureDetector(
            onTap: () => Navigator.push(
                context, _route(const NewAppointmentScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF4A90D9).withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded,
                    color: Color(0xFF4A90D9), size: 14),
                const SizedBox(width: 4),
                Text('New', style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: Color(0xFF4A90D9))),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Divider(color: _border, thickness: 1.5),
        const SizedBox(height: 2),
        ...List.generate(appts.length, (i) => _apptTile(appts[i], dayNum: dayNums[i])),
      ]),
    );
  }

  Widget _buildEmptySchedule() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 52),
      decoration: _card(),
      child: Column(children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _btnGradient),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 30)),
        const SizedBox(height: 16),
        Text('No appointments', style: GoogleFonts.dmSans(
            fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
        const SizedBox(height: 6),
        Text('Tap Add Task to book a new appointment', style: GoogleFonts.dmSans(
            fontSize: 13, color: _txtSub, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildDateNav() {
    final days     = _weekDays;
    final todayIdx = _todayWeekIdx();
    // Real appointment counts per day from AppState
    final appState = AppStateProvider.of(context);
    final counts   = List.generate(7,
            (i) => appState.appointmentsForDate(days[i]).length);

    return SizedBox(height: 88, child: ListView.separated(
      scrollDirection: Axis.horizontal,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final sel      = _selectedDayIndex == i;
        final isToday  = i == todayIdx;
        final d        = days[i];

        return GestureDetector(
          onTap: () => setState(() => _selectedDayIndex = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 58,
            decoration: BoxDecoration(
              gradient: sel ? LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: _btnGradient,
              ) : null,
              color: sel ? null : _cardBg,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: sel
                    ? _accent.withOpacity(0.6)
                    : isToday
                    ? _accent.withOpacity(0.35)
                    : _border,
                width: isToday && !sel ? 2.0 : 1.5,
              ),
              boxShadow: sel
                  ? [BoxShadow(color: _btnShadow.withOpacity(0.4),
                  blurRadius: 14, offset: const Offset(0, 5))]
                  : [BoxShadow(color: _btnShadow.withOpacity(0.04), blurRadius: 5)],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Day name — "TODAY" badge for today when not selected
              if (isToday && !sel)
                Container(
                  margin: const EdgeInsets.only(bottom: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('TODAY', style: GoogleFonts.dmSans(
                      fontSize: 7, fontWeight: FontWeight.w900,
                      color: _accent, letterSpacing: 0.5)),
                )
              else
                Text(_dayNames[i], style: GoogleFonts.dmSans(fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white.withOpacity(0.75) : _txtSub)),
              const SizedBox(height: 2),
              Text('${d.day}', style: GoogleFonts.dmSans(fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: sel ? Colors.white : isToday ? _accent : _txtMain,
                  letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(counts[i].clamp(0, 3), (_) => Container(
                    width: 4, height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white.withOpacity(0.7) : _accent,
                      shape: BoxShape.circle,
                    ),
                  ))),
            ]),
          ),
        );
      },
    ));
  }



  // ── ACTIONS TAB ────────────────────────────────────────────────────────────
  Widget _buildActionsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _actionsScrollCtrl,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: ConstrainedBox(
            // Ensure content is always taller than the viewport so scroll
            // events fire and the header collapse/expand animation works
            // even when there is limited content on this tab.
            constraints: BoxConstraints(minHeight: constraints.maxHeight + _collapseRange),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionLabel('Quick Actions'),
              const SizedBox(height: 6),
              Text('What would you like to do?', style: GoogleFonts.dmSans(
                  fontSize: 13.5, color: _txtSub, fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              _buildActionsGrid(),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildActionsGrid() {
    final appState = AppStateProvider.of(context);
    final actions = [
      {'label': 'New Appointment', 'desc': 'Book a new slot',     'icon': Icons.add_circle_rounded,     's': const NewAppointmentScreen()},

      // YAHAN YEH NAYI LINE ADD KI HAI (Video Call ke liye)
      {'label': 'Test Video Call', 'desc': 'Start WebRTC call',   'icon': Icons.video_camera_front_rounded, 's': const CallScreen(callerId: 'test_user_1')},

      {'label': 'Add Client',      'desc': 'Register new client', 'icon': Icons.person_add_rounded,     's': const AddClientScreen()},
      {'label': 'Send Reminder',   'desc': 'Notify your clients', 'icon': Icons.send_rounded,            's': const SendReminderScreen()},
      {'label': 'My Availability', 'desc': 'Set your open slots', 'icon': Icons.event_available_rounded, 's': const MyAvailabilityScreen()},
      {'label': 'My Reviews',      'desc': 'See client feedback', 'icon': Icons.star_rounded,            's': const MyReviewsScreen()},
      {'label': 'Personal Tasks',  'desc': 'Manage your to-dos',  'icon': Icons.check_circle_rounded,    's': const PersonalTasksScreen()},
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.1),
      itemCount: actions.length,
      itemBuilder: (_, i) {
        final grad = appState.cardGradient(i);
        return GestureDetector(
          onTap: () => Navigator.push(context, _route(actions[i]['s'] as Widget)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: grad,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent.withOpacity(0.22)),
              boxShadow: [BoxShadow(
                color: grad[0].withOpacity(0.45),
                blurRadius: 12, offset: const Offset(0, 5),
              )],
            ),
            child: Row(children: [
              Container(width: 38, height: 38,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(actions[i]['icon'] as IconData, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(actions[i]['label'] as String, style: GoogleFonts.dmSans(
                        fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white,
                        height: 1.1, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(actions[i]['desc'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 9.5,
                            color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w500)),
                  ])),
            ]),
          ),
        );
      },
    );
  }

  // ── CLIENTS TAB ────────────────────────────────────────────────────────────
  Widget _buildClientsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _clientsScrollCtrl,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: ConstrainedBox(
            // Ensure content is always taller than the viewport so scroll
            // events fire and the header collapse/expand animation works
            // even when there is limited content on this tab.
            constraints: BoxConstraints(minHeight: constraints.maxHeight + _collapseRange),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _sectionLabel('Recent Clients'),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                    ),
                    child: Text('All →', style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: _accent))),
              ]),
              const SizedBox(height: 6),
              Text('248 total clients', style: GoogleFonts.dmSans(
                  fontSize: 13.5, color: _txtSub, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              _buildRecentClients(),
            ]),
          ),
        );
      },
    );
  }

  // ── SHARED HELPERS ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String t) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(t, style: GoogleFonts.dmSans(
        fontSize: 28, fontWeight: FontWeight.w900, color: _txtMain,
        letterSpacing: -1.2, height: 1.1)),
    Container(margin: const EdgeInsets.only(top: 4), width: 40, height: 4,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _btnGradient),
          borderRadius: BorderRadius.circular(2),
        )),
  ]);

  Widget _glassBox({required Widget child, double size = 42}) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.18))),
    child: Center(child: child),
  );

  BoxDecoration _card({double r = 20}) => BoxDecoration(
    color: _cardBg,
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: _border, width: 1.5),
    boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.07),
        blurRadius: 18, offset: const Offset(0, 5))],
  );

  Widget _orb(double size, Color c, double op) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c.withOpacity(op), Colors.transparent])),
  );

  Widget _apptTile(Appointment a, {int? dayNum}) {
    Color sBg, sFg; String sLbl;
    switch (a.status) {
      case ApptStatus.confirmed:
        sBg = const Color(0xFFDEECFF); sFg = const Color(0xFF0B3D91); sLbl = 'Confirmed'; break;
      case ApptStatus.pending:
        sBg = const Color(0xFFFFF3E0); sFg = const Color(0xFFB86A00); sLbl = 'Pending';   break;
      case ApptStatus.cancelled:
        sBg = const Color(0xFFFFECEC); sFg = const Color(0xFFB83232); sLbl = 'Cancelled'; break;
      case ApptStatus.completed:
        sBg = const Color(0xFFE8F5E9); sFg = const Color(0xFF2E7D32); sLbl = 'Completed'; break;
    }
    final compact = AppStateProvider.of(context).compactView;
    final vPad    = compact ? 5.0  : 10.0;
    final avatarR = compact ? 16.0 : 20.0;
    final nameSz  = compact ? 12.0 : 13.5;
    final svcSz   = compact ? 10.5 : 11.5;
    final timeSz  = compact ? 13.0 : 15.0;
    final timeSubSz = compact ? 8.5 : 10.0;
    final boxW    = compact ? 38.0 : 46.0;

    return GestureDetector(
      onTap: () => _showAppointmentSheet(a),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: vPad),
        child: Row(children: [
          Container(width: boxW, padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(compact ? 9 : 12),
              border: Border.all(color: _border),
            ),
            child: Column(children: [
              Text(a.time.split(':')[0], style: GoogleFonts.dmSans(
                  fontSize: timeSz, fontWeight: FontWeight.w900, color: _txtMain)),
              Text(':${a.time.split(':')[1]}', style: GoogleFonts.dmSans(
                  fontSize: timeSubSz, color: _txtSub, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(radius: avatarR, backgroundColor: a.avatarColor.withOpacity(_dark ? 0.2 : 0.15),
                  child: Text(a.initials, style: GoogleFonts.dmSans(
                      fontSize: compact ? 9.0 : 11.0, fontWeight: FontWeight.w900, color: a.avatarColor))),
              if (dayNum != null)
                Positioned(
                  right: -6, top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _cardBg, width: 1.5),
                    ),
                    child: Text(_ordinal(dayNum), style: GoogleFonts.dmSans(
                        fontSize: 8, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: GoogleFonts.dmSans(
                fontSize: nameSz, fontWeight: FontWeight.w700, color: _txtMain, letterSpacing: -0.1)),
            if (!compact) const SizedBox(height: 2),
            Text(a.service, style: GoogleFonts.dmSans(
                fontSize: svcSz, color: _txtSub, fontWeight: FontWeight.w500)),
          ])),
          Row(children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 3 : 4),
              decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sFg.withOpacity(0.2))),
              child: Text(sLbl, style: GoogleFonts.dmSans(
                  fontSize: compact ? 9.0 : 10.0, fontWeight: FontWeight.w800, color: sFg)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: _txtSub.withOpacity(0.5)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildRecentClients() {
    final clients = [
      {'name': 'Aisha Khan',     'last': 'Today 9:00 AM',  'ac': _accent,                         'bg': _accent.withOpacity(0.12)},
      {'name': 'Omar Farooq',    'last': 'Today 10:00 AM', 'ac': const Color(0xFF2ECC96),          'bg': const Color(0xFF2ECC96).withOpacity(0.12)},
      {'name': 'Zara Malik',     'last': 'Yesterday',      'ac': const Color(0xFFF4A24A),          'bg': const Color(0xFFF4A24A).withOpacity(0.12)},
      {'name': 'Bilal Chaudhry', 'last': '2 days ago',     'ac': const Color(0xFF7C3AED),          'bg': const Color(0xFF7C3AED).withOpacity(0.12)},
    ];
    return Container(decoration: _card(), child: Column(
      children: List.generate(clients.length, (i) {
        final c = clients[i];
        final initials = (c['name'] as String).split(' ').map((w) => w[0]).join();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: i.isEven ? Colors.transparent : const Color(0xFF4A90D9).withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: c['bg'] as Color,
                child: Text(initials, style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w900, color: c['ac'] as Color))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] as String, style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain)),
              const SizedBox(height: 2),
              Text('Last visit: ${c['last']}', style: GoogleFonts.dmSans(
                  fontSize: 12, color: _txtSub, fontWeight: FontWeight.w500)),
            ])),
            Container(width: 34, height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _btnGradient),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20)),
          ]),
        );
      }),
    ));
  }
}

// ── EXTENSION ──────────────────────────────────────────────────────────────────
extension AppState_ext on AppState {
  static bool of(BuildContext context) => AppStateProvider.of(context).isDarkMode;
}

// ── LINE CHART CUSTOM PAINTER ─────────────────────────────────────────────────
class _LineChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final int todayIdx;
  final Color lineColor;
  final Color todayDotColor;
  final Color gridColor;
  final Color labelColor;
  final Color todayLabelColor;
  final bool bgDark;

  const _LineChartPainter({
    required this.data,
    required this.labels,
    required this.todayIdx,
    required this.lineColor,
    required this.todayDotColor,
    required this.gridColor,
    required this.labelColor,
    required this.todayLabelColor,
    required this.bgDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = data.reduce((a, b) => a > b ? a : b).toDouble();
    final chartH = size.height - 28.0;
    final stepX = size.width / (data.length - 1);

    final gridP = Paint()..color = gridColor..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = chartH * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridP);
    }

    final pts = List.generate(data.length, (i) => Offset(
      i * stepX,
      chartH * (1 - data[i] / maxVal),
    ));

    final fillPath = Path()..moveTo(pts.first.dx, chartH);
    for (int i = 0; i < pts.length - 1; i++) {
      final c1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final c2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      fillPath.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    fillPath..lineTo(pts.last.dx, chartH)..close();

    final fillP = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.28), lineColor.withOpacity(0.03)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH));
    canvas.drawPath(fillPath, fillP);

    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final c1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final c2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      linePath.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = lineColor..strokeWidth = 2.5
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    for (int i = 0; i < pts.length; i++) {
      final isToday = i == todayIdx;
      canvas.drawCircle(pts[i], isToday ? 7 : 4.5,
          Paint()..color = isToday ? todayDotColor : lineColor..style = PaintingStyle.fill);
      canvas.drawCircle(pts[i], isToday ? 3.5 : 2,
          Paint()..color = Colors.white..style = PaintingStyle.fill);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < labels.length; i++) {
      final isToday = i == todayIdx;
      tp.text = TextSpan(text: labels[i], style: TextStyle(
        fontSize: 11, fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
        color: isToday ? todayLabelColor : labelColor,
      ));
      tp.layout();
      tp.paint(canvas, Offset(i * stepX - tp.width / 2, chartH + 10));
    }
  }

  @override bool shouldRepaint(_) => false;
}

// ── DONUT PAINTER ─────────────────────────────────────────────────────────────
class _DonutPainter extends CustomPainter {
  final Color trackColor;
  final Color accentColor;
  final Color secondColor;
  final double confirmedFrac;
  final double completedFrac;
  final double cancelledFrac;
  const _DonutPainter({
    required this.trackColor,
    required this.accentColor,
    required this.secondColor,
    this.confirmedFrac = 5 / 8,
    this.completedFrac = 2 / 8,
    this.cancelledFrac = 1 / 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 11;

    final track = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 13
      ..color = trackColor;
    canvas.drawCircle(Offset(cx, cy), radius, track);

    // If no data at all, draw a single grey arc
    final total = confirmedFrac + completedFrac + cancelledFrac;
    if (total <= 0) return;

    final segs = [
      [accentColor,                    confirmedFrac / total],
      [secondColor,                    completedFrac / total],
      [const Color(0xFFE05C5C),        cancelledFrac / total],
    ];

    double angle = -math.pi / 2;
    for (final s in segs) {
      if ((s[1] as double) <= 0) continue;
      final sweep = (s[1] as double) * 2 * math.pi * 0.91;
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          angle, sweep, false,
          Paint()
            ..color = s[0] as Color..strokeWidth = 13
            ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
      angle += sweep + 0.09;
    }
  }

  @override bool shouldRepaint(_DonutPainter old) =>
      old.confirmedFrac != confirmedFrac ||
      old.completedFrac != completedFrac ||
      old.cancelledFrac != cancelledFrac;
}