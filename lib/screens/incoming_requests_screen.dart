import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import 'appointment_detail_screen.dart';

enum RequestStatus { pending, accepted, declined }

class IncomingRequest {
  final String id, clientName, service, requestedDate, requestedTime, message, timeAgo;
  final Color avatarColor;
  final bool isNew;
  RequestStatus status;
  IncomingRequest({required this.id, required this.clientName, required this.service,
    required this.requestedDate, required this.requestedTime, required this.message,
    required this.avatarColor, required this.timeAgo,
    required this.isNew, this.status = RequestStatus.pending});
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

  final List<IncomingRequest> _requests = [
    IncomingRequest(id:'001', clientName:'Mahnoor Siddiqui', service:'Deep Tissue Massage', requestedDate:'Tue, Mar 18', requestedTime:'10:00 AM', message:"Hi! I'd like to book a session for my back pain. Please let me know if this slot works!", avatarColor:const Color(0xFF7C3AED), timeAgo:'5 min ago', isNew:true),
    IncomingRequest(id:'002', clientName:'Rahim Shah', service:'Consultation', requestedDate:'Wed, Mar 19', requestedTime:'2:00 PM', message:'Looking for an initial consultation. First time booking with you. Excited!', avatarColor:const Color(0xFF2ECC96), timeAgo:'22 min ago', isNew:true),
    IncomingRequest(id:'003', clientName:'Nida Hussain', service:'Hair Coloring', requestedDate:'Thu, Mar 20', requestedTime:'11:00 AM', message:'I want highlights done. I saw your work on Instagram and loved it!', avatarColor:const Color(0xFFE05C5C), timeAgo:'1 hr ago', isNew:true),
    IncomingRequest(id:'004', clientName:'Jawad Malik', service:'Physiotherapy', requestedDate:'Fri, Mar 21', requestedTime:'9:30 AM', message:'Referred by Dr. Ahmed. Need post-surgery rehab sessions.', avatarColor:const Color(0xFF4A90D9), timeAgo:'3 hrs ago', isNew:false),
    IncomingRequest(id:'005', clientName:'Sobia Raza', service:'Skin Care Session', requestedDate:'Mon, Mar 24', requestedTime:'3:00 PM', message:'Would love a facial + skin consultation. Flexible with timing!', avatarColor:const Color(0xFFF4A24A), timeAgo:'Yesterday', isNew:false),
  ];

  List<IncomingRequest> get _filtered {
    if (_selectedFilter == 0) return _requests;
    if (_selectedFilter == 1) return _requests.where((r) => r.status == RequestStatus.pending).toList();
    if (_selectedFilter == 2) return _requests.where((r) => r.status == RequestStatus.accepted).toList();
    return _requests.where((r) => r.status == RequestStatus.declined).toList();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Column(children: [
        _buildHero(),
        _buildFilterRow(),
        Expanded(child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade,
          child: _filtered.isEmpty ? _emptyState() : _buildList()))),
      ]),
    );
  }

  Widget _buildHero() => Container(
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
            _glass(child: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 20)),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            _hStat('${_requests.where((r)=>r.status==RequestStatus.pending).length}', 'Pending', AppColors.warning),
            const SizedBox(width: 10),
            _hStat('${_requests.where((r)=>r.isNew&&r.status==RequestStatus.pending).length}', 'New Today', AppColors.green),
            const SizedBox(width: 10),
            _hStat('${_requests.where((r)=>r.status==RequestStatus.accepted).length}', 'Accepted', dmAccent),
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

  Widget _buildList() => ListView.separated(
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
    itemCount: _filtered.length,
    separatorBuilder: (_, __) => const SizedBox(height: 12),
    itemBuilder: (_, i) => _requestCard(_filtered[i]),
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
                onTap: () => setState(() => r.status = RequestStatus.declined),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withOpacity(0.25))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.close_rounded, color: AppColors.danger, size: 16),
                    const SizedBox(width: 6),
                    Text('Decline', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.danger)),
                  ])),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () {
                  setState(() => r.status = RequestStatus.accepted);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${r.clientName}\'s request accepted!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.green, behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
                },
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: AppStateProvider.of(context).cardGradient(0)),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: dmTxtMain.withOpacity(0.4), blurRadius: 8, offset: const Offset(0,3))]),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
