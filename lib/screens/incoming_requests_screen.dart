import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../models/appointment.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import '../user_session.dart';
import 'appointment_detail_screen.dart';

enum RequestStatus { pending, accepted, declined }

class IncomingRequest {
  final String id, clientName, service, requestedDate, requestedTime, message, timeAgo;
  final Color avatarColor;
  final bool isNew;
  /// The backend appointment id (null only for requests with no API record).
  final int? appointmentId;
  RequestStatus status;
  IncomingRequest({required this.id, required this.clientName, required this.service,
    required this.requestedDate, required this.requestedTime, required this.message,
    required this.avatarColor, required this.timeAgo,
    required this.isNew, this.appointmentId,
    this.status = RequestStatus.pending});
  String get initials => clientName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').join();
}

class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key});
  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen>
    with TickerProviderStateMixin, DarkMode {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  int _selectedFilter = 0;
  // IDs currently being accepted/declined (double-tap guard: the
  // second tap used to fire a second API call and 409).
  final Set<int> _busyIds = {};
  bool _loading = true;
  bool _loadFailed = false;

  /// Requests made TO me, derived from my appointments (I am the provider).
  /// Pending → pending, confirmed (accepted) → accepted, rejected → declined.
  /// Cancelled/completed appointments are not requests, so they are left out.
  /// (This replaces the old hardcoded demo list.)
  List<IncomingRequest> get _requests {
    final myId = UserSession.instance.userId?.toString();
    return AppStateProvider.of(context).appointments
        .where((a) => a.providerId != null && a.providerId == myId)
        .where((a) => a.status == ApptStatus.pending ||
            a.status == ApptStatus.confirmed ||
            a.status == ApptStatus.rejected)
        .map((a) {
          final created = a.createdAt ?? a.dateTime;
          return IncomingRequest(
            id: '${a.id}',
            appointmentId: a.id,
            clientName: a.name,
            service: a.service,
            requestedDate: a.displayDate,
            requestedTime: a.displayTime,
            message: a.note.isEmpty ? 'No message.' : a.note,
            avatarColor: a.avatarColor,
            timeAgo: _timeAgo(created),
            // "New Today" means created on this calendar day — the
            // old check counted the last 24 hours.
            isNew: a.status == ApptStatus.pending &&
                _isCalendarToday(created),
            status: a.status == ApptStatus.confirmed
                ? RequestStatus.accepted
                : (a.status == ApptStatus.rejected
                    ? RequestStatus.declined
                    : RequestStatus.pending),
          );
        })
        .toList();
  }

  static bool _isCalendarToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  static String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  /// Filters a precomputed request list. The old getter rebuilt the
  /// whole list from AppState on every access (hero stats + list +
  /// per-row), making the build O(n²).
  List<IncomingRequest> _filteredFrom(List<IncomingRequest> all) {
    if (_selectedFilter == 0) return all;
    if (_selectedFilter == 1) {
      return all.where((r) => r.status == RequestStatus.pending).toList();
    }
    if (_selectedFilter == 2) {
      return all.where((r) => r.status == RequestStatus.accepted).toList();
    }
    return all.where((r) => r.status == RequestStatus.declined).toList();
  }

  @override
  void initState() {
    super.initState();
    // Post-frame: _refresh reads AppStateProvider, which cannot be
    // depended on during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    final ok = await AppStateProvider.of(context).loadAppointments();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    // Compute the request list ONCE per build and pass it down — the
    // old code rebuilt it in the hero (×3), the empty check, the
    // list length, and once per row.
    final requests = _requests;
    final filtered = _filteredFrom(requests);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _buildHero(requests),
        _buildFilterRow(),
        Expanded(child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade,
          child: _loading
              ? _loadingState()
              : _loadFailed && filtered.isEmpty
                  ? _errorState()
                  : filtered.isEmpty
                      ? _emptyState()
                      : _buildList(filtered)))),
      ]),
    );
  }

  Widget _loadingState() => const Center(child: CircularProgressIndicator());

  Widget _errorState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(color: dmAccent.withOpacity(0.08), shape: BoxShape.circle),
        child: Icon(Icons.cloud_off_rounded, color: dmAccent.withOpacity(0.4), size: 36)),
    const SizedBox(height: 16),
    Text('Couldn\'t load requests', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: dmTxtMain)),
    const SizedBox(height: 6),
    Text('Check your connection and try again.', style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtSub, fontWeight: FontWeight.w500)),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () {
        setState(() => _loading = true);
        _refresh();
      },
      child: const Text('Try again'),
    ),
  ]));

  Widget _buildHero(List<IncomingRequest> requests) => Container(
    decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: AppStateProvider.of(context).heroGradient)),
    child: Stack(children: [
      Positioned(right: -40, top: -40, child: Container(width: 180, height: 180,
          decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [dmAccent.withOpacity(0.1), Colors.transparent])))),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(onTap: () => Navigator.pop(context),
                child: _glass(child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18))),
            const Spacer(),
            Text('Incoming Requests', style: GoogleFonts.dmSans(
                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
            const Spacer(),
            GestureDetector(
              onTap: _showFilterSheet,
              child: _glass(child: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 20)),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            _hStat('${requests.where((r)=>r.status==RequestStatus.pending).length}', 'Pending', AppColors.warning),
            const SizedBox(width: 10),
            _hStat('${requests.where((r)=>r.isNew&&r.status==RequestStatus.pending).length}', 'New Today', AppColors.green),
            const SizedBox(width: 10),
            _hStat('${requests.where((r)=>r.status==RequestStatus.accepted).length}', 'Accepted', dmAccent),
          ]),
        ]),
      )),
    ]),
  );

  Widget _hStat(String v, String l, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(v, style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w900,
          color: Colors.white, letterSpacing: -0.5)),
      const SizedBox(height: 2),
      Text(l, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: c)),
    ]),
  ));

  /// Filter picker for the hero filter icon — same filters as the
  /// filter row below (All / Pending / Accepted / Declined).
  void _showFilterSheet() {
    final filters = ['All', 'Pending', 'Accepted', 'Declined'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: dmCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: dmBorder),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: dmBorder, borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Icon(Icons.filter_list_rounded, size: 18, color: dmAccent),
            const SizedBox(width: 8),
            Text('Filter requests', style: GoogleFonts.dmSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: dmTxtMain)),
          ]),
          const SizedBox(height: 12),
          ...filters.asMap().entries.map((e) {
            final sel = _selectedFilter == e.key;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedFilter = e.key);
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? dmAccent.withOpacity(0.12) : dmCard2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel ? dmAccent.withOpacity(0.5) : dmBorder),
                ),
                child: Row(children: [
                  Expanded(child: Text(e.value, style: GoogleFonts.dmSans(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: sel ? dmAccent : dmTxtMain))),
                  if (sel) Icon(Icons.check_circle_rounded,
                      color: dmAccent, size: 20),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = ['All','Pending','Accepted','Declined'];
    return Container(color: dmCard, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
        children: filters.asMap().entries.map((e) {
          final sel = _selectedFilter == e.key;
          return GestureDetector(onTap: () => setState(() => _selectedFilter = e.key),
            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(colors: AppStateProvider.of(context).cardGradient(0)) : null,
                color: sel ? null : dmCard2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? dmTxtMain : dmBorder),
              ),
              child: Text(e.value, style: GoogleFonts.dmSans(fontSize: 12.5,
                  fontWeight: FontWeight.w700, color: sel ? Colors.white : dmTxtSub))));
        }).toList(),
      )),
    );
  }

  Widget _buildList(List<IncomingRequest> filtered) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView.separated(
      cacheExtent: 200,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _requestCard(filtered[i]),
    ),
  );

  Widget _requestCard(IncomingRequest r) {
    final isPending = r.status == RequestStatus.pending;
    Color sBg, sFg; String sLbl;
    if (r.status == RequestStatus.accepted) { sBg = AppColors.green.withOpacity(dark ? 0.15 : 0.12); sFg = AppColors.green; sLbl = 'Accepted'; }
    else if (r.status == RequestStatus.declined) { sBg = AppColors.danger.withOpacity(dark ? 0.15 : 0.1); sFg = AppColors.danger; sLbl = 'Declined'; }
    else { sBg = AppColors.warning.withOpacity(dark ? 0.15 : 0.1); sFg = AppColors.warning; sLbl = 'Pending'; }

    return GestureDetector(
      onTap: () => Navigator.push(context, PageRouteBuilder(
        pageBuilder: (_, __, ___) => RequestDetailScreen(request: r),
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a), child: child),
        transitionDuration: const Duration(milliseconds: 350),
      )).then((_) => setState(() {})),
      child: Container(
        decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: r.isNew && isPending ? dmAccent.withOpacity(0.45) : dmBorder,
            width: r.isNew && isPending ? 2 : 1.5),
          boxShadow: [BoxShadow(color: r.isNew && isPending
              ? dmAccent.withOpacity(0.08) : dmAccent.withOpacity(0.03),
              blurRadius: 14, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                Container(decoration: BoxDecoration(shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: r.avatarColor.withOpacity(0.25), blurRadius: 8)]),
                  child: CircleAvatar(radius: 24, backgroundColor: r.avatarColor.withOpacity(dark ? 0.2 : 0.15),
                      child: Text(r.initials, style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w800, color: r.avatarColor)))),
                if (r.isNew && isPending) Positioned(top: 0, right: 0, child: Container(
                    width: 10, height: 10, decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle,
                        border: Border.all(color: dmCard, width: 1.5)))),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(r.clientName, style: GoogleFonts.dmSans(fontSize: 15,
                      fontWeight: FontWeight.w800, color: dmTxtMain, letterSpacing: -0.3)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sFg.withOpacity(0.25))),
                    child: Text(sLbl, style: GoogleFonts.dmSans(fontSize: 10,
                        fontWeight: FontWeight.w700, color: sFg))),
                ]),
                const SizedBox(height: 3),
                Text(r.service, style: GoogleFonts.dmSans(fontSize: 12.5,
                    color: dmAccent, fontWeight: FontWeight.w600)),
              ])),
            ])),
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
            _chip(Icons.calendar_today_rounded, r.requestedDate, dmTxtMain),
            const SizedBox(width: 8),
            _chip(Icons.access_time_rounded, r.requestedTime, dmAccent),
            const Spacer(),
            Text(r.timeAgo, style: GoogleFonts.dmSans(fontSize: 11, color: dmTxtSub, fontWeight: FontWeight.w500)),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dmBorder2)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.format_quote_rounded, color: dmAccent.withOpacity(0.5), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(r.message, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: dmTxtBody,
                      fontWeight: FontWeight.w500, height: 1.5))),
            ]),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Row(children: [
            const Spacer(),
            Text('Tap for details', style: GoogleFonts.dmSans(
                fontSize: 10.5, color: dmAccent.withOpacity(0.6), fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios_rounded, size: 9, color: dmAccent.withOpacity(0.6)),
          ])),
          if (isPending)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () async {
                  final id = r.appointmentId;
                  if (id == null || _busyIds.contains(id)) return;
                  setState(() => _busyIds.add(id));
                  try {
                    await AppStateProvider.of(context).rejectAppointment(id);
                  } on ApiException catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.message,
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))));
                  } finally {
                    if (mounted) setState(() => _busyIds.remove(id));
                  }
                },
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withOpacity(0.25))),
                  child: _busyIds.contains(r.appointmentId)
                      ? const Center(child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger)))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.close_rounded, color: AppColors.danger, size: 16),
                          const SizedBox(width: 6),
                          Text('Decline', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.danger)),
                        ])),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () async {
                  final id = r.appointmentId;
                  if (id == null || _busyIds.contains(id)) return;
                  setState(() => _busyIds.add(id));
                  try {
                    await AppStateProvider.of(context).acceptAppointment(id);
                  } on ApiException catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.message,
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))));
                    return;
                  } finally {
                    if (mounted) setState(() => _busyIds.remove(id));
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${r.clientName}\'s request accepted!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.green, behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
                },
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: AppStateProvider.of(context).cardGradient(0)),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: dmTxtMain.withOpacity(0.4), blurRadius: 8, offset: const Offset(0,3))]),
                  child: _busyIds.contains(r.appointmentId)
                      ? const Center(child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text('Accept', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                        ])),
              )),
            ]))
          else const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(color: dmAccent.withOpacity(0.08), shape: BoxShape.circle),
        child: Icon(Icons.mark_email_read_rounded, color: dmAccent.withOpacity(0.4), size: 36)),
    const SizedBox(height: 16),
    Text('All caught up!', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: dmTxtMain)),
    const SizedBox(height: 6),
    Text('No requests in this category', style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtSub, fontWeight: FontWeight.w500)),
  ]));

  Widget _chip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color), const SizedBox(width: 5),
      Text(label, style: GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    ]));

  Widget _glass({required Widget child, double size = 42}) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Center(child: child));
}
