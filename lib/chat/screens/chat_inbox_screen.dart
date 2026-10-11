import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';
import '../models/chat_models.dart';
import '../widgets/chat_popup_menus.dart';
import 'chat_thread_screen.dart';
import 'archived_chats_screen.dart';
import 'chat_settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT INBOX SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});
  @override State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery  = '';
  int    _selectedFilter = 0;
  bool   _showSearch   = false;

  late AnimationController _headerCtrl, _listCtrl;
  late Animation<double>   _headerFade;

  final _filters = ['All', 'Unread', 'Online'];

  final _stories = [
    const StatusStory('My Status', Color(0xFF4A90D9), isMe: true),
    const StatusStory('Aisha Khan',  Color(0xFF4A90D9)),
    const StatusStory('Omar Farooq', Color(0xFF7C5CBF)),
    const StatusStory('Tariq Ahmed', Color(0xFF3B73C0), viewed: true),
    const StatusStory('Hina Raza',   Color(0xFFE8805A)),
  ];

  final List<ChatConversation> _convos = [
    ChatConversation(id:'1', name:'Aisha Khan',     service:'Consultation',  avatarColor:const Color(0xFF4A90D9), online:true,  lastMsg:'See you tomorrow at 9 AM 👍',           time:'2m',        unread:2, isPinned:true),
    ChatConversation(id:'2', name:'Omar Farooq',    service:'Consultation',  avatarColor:const Color(0xFF7C5CBF), online:true,  lastMsg:'Can we reschedule to next week?',        time:'18m',       unread:1),
    ChatConversation(id:'3', name:'Zara Malik',     service:'Hair Coloring', avatarColor:const Color(0xFF2ECC96), online:false, lastMsg:'Thank you! The session was great.',      time:'1h',        unread:0),
    ChatConversation(id:'4', name:'Bilal Chaudhry', service:'Physiotherapy', avatarColor:const Color(0xFF2A6AB5), online:false, lastMsg:'Your appointment is confirmed',          time:'3h',        unread:0),
    ChatConversation(id:'5', name:'Hina Raza',      service:'Skin Care',     avatarColor:const Color(0xFFE8805A), online:false, lastMsg:'Is 2:30 PM still available Thursday?',  time:'Yesterday', unread:3),
    ChatConversation(id:'6', name:'Tariq Ahmed',    service:'Sports Massage',avatarColor:const Color(0xFF3B73C0), online:true,  lastMsg:'Looking forward to the session!',       time:'Yesterday', unread:0, isMuted:true),
    ChatConversation(id:'7', name:'Sana Qureshi',   service:'Nail Art',      avatarColor:const Color(0xFF4A8FD4), online:false, lastMsg:'I might need to cancel, will confirm.', time:'Mon',       unread:0),
    ChatConversation(id:'8', name:'Imran Shah',     service:'Consultation',  avatarColor:const Color(0xFF0B3D91), online:false, lastMsg:'Reminder: appointment at 8:30 AM',      time:'Mon',       unread:0),
  ];

  // ── Theme helpers ──────────────────────────────────────────────────────────
  Color get _bg        => AppStateProvider.of(context).bg;
  Color get _cardBg    => AppStateProvider.of(context).cardBg;
  Color get _border    => AppStateProvider.of(context).border;
  Color get _txtMain   => AppStateProvider.of(context).txtMain;
  Color get _txtSub    => AppStateProvider.of(context).txtSub;
  Color get _accent    => AppStateProvider.of(context).accent;
  List<Color> get _btnGrad   => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow       => AppStateProvider.of(context).btnShadow;
  List<Color> get _hero      => AppStateProvider.of(context).heroGradient;
  bool get _isDark           => AppStateProvider.of(context).themeMode.isDark;

  int get _totalUnread => _convos.fold(0, (s, c) => s + c.unread);

  List<ChatConversation> get _filtered {
    var list = _convos.where((c) => !c.isArchived).toList();
    if (_searchQuery.isNotEmpty) {
      list = list.where((c) =>
        c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c.service.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    switch (_selectedFilter) {
      case 1: return list.where((c) => c.unread > 0).toList();
      case 2: return list.where((c) => c.online).toList();
      default: return list;
    }
  }

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _listCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerCtrl.forward();
    _listCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _headerCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        _buildStatusStrip(),
        _buildFilterChips(),
        Expanded(child: _buildList()),
      ]),
      floatingActionButton: _buildFab(),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() => FadeTransition(
    opacity: _headerFade,
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _hero, stops: const [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: SafeArea(bottom: false, child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: _glassBtn(Icons.arrow_back_ios_new_rounded, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Messages',
                  style: GoogleFonts.dmSans(fontSize: 24, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: -0.8)),
              Text('${_convos.length} conversations  •  $_totalUnread unread',
                  style: GoogleFonts.dmSans(fontSize: 12,
                      color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w500)),
            ])),
            _hBtn(Icons.camera_alt_rounded, () => _toast('Camera')),
            const SizedBox(width: 8),
            _hBtn(Icons.search_rounded, () => setState(() => _showSearch = !_showSearch)),
            const SizedBox(width: 8),
            InboxPopupMenu(
              accent: _accent, cardBg: _cardBg, border: _border,
              txtMain: _txtMain, txtSub: _txtSub,
              onSelect: (v) {
                if (v == 'settings') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatSettingsScreen()));
                } else if (v == 'archived') {
                  _openArchived();
                } else {
                  _toast(v);
                }
              },
            ),
          ]),
        ),
        // Animated search bar
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: _showSearch ? 52 : 0,
          child: _showSearch ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(children: [
                const SizedBox(width: 14),
                Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.55), size: 18),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    hintStyle: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.45), fontSize: 13.5),
                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                  ),
                )),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                    child: Padding(padding: const EdgeInsets.only(right: 12),
                        child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.6), size: 17)),
                  ),
              ]),
            ),
          ) : const SizedBox(),
        ),
        const SizedBox(height: 14),
      ])),
    ),
  );

  Widget _glassBtn(IconData icon, {double size = 19}) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white.withOpacity(0.22)),
    ),
    child: Icon(icon, color: Colors.white, size: size),
  );

  Widget _hBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap, child: _glassBtn(icon),
  );

  // ── Status strip ───────────────────────────────────────────────────────────
  Widget _buildStatusStrip() => Container(
    height: 100, color: _bg,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: _stories.length,
      itemBuilder: (_, i) {
        final s = _stories[i];
        return GestureDetector(
          onTap: () => _toast(s.isMe ? 'Add Status' : 'View status'),
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: (s.viewed || s.isMe)
                      ? null
                      : LinearGradient(colors: [_accent, _btnGrad.last], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  color: s.viewed ? _border : (s.isMe ? _cardBg : null),
                  border: (s.viewed || s.isMe) ? Border.all(color: _border, width: 2) : null,
                ),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [s.color.withOpacity(0.7), s.color]),
                    border: Border.all(color: _bg, width: 2),
                  ),
                  child: Center(child: s.isMe
                      ? const Icon(Icons.add_rounded, color: Colors.white, size: 22)
                      : Text(s.initials,
                          style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white))),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                width: 60,
                child: Text(
                  s.isMe ? 'My Status' : s.name.split(' ').first,
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 10.5, fontWeight: FontWeight.w600,
                      color: s.viewed ? _txtSub.withOpacity(0.5) : _txtSub),
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );

  // ── Filter chips ───────────────────────────────────────────────────────────
  Widget _buildFilterChips() => Container(
    color: _bg, height: 50,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: _filters.length,
      itemBuilder: (_, i) {
        final sel = _selectedFilter == i;
        return GestureDetector(
          onTap: () => setState(() => _selectedFilter = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              gradient: sel ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: sel ? null : _cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? Colors.transparent : _border, width: 1.5),
              boxShadow: sel ? [BoxShadow(color: _btnShadow.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))] : [],
            ),
            child: Text(_filters[i],
                style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : _txtSub)),
          ),
        );
      },
    ),
  );

  // ── Conversation list ──────────────────────────────────────────────────────
  Widget _buildList() {
    final all = _filtered;
    if (all.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 60, color: _txtSub.withOpacity(0.3)),
        const SizedBox(height: 16),
        Text('No conversations',
            style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: _txtSub)),
      ]));
    }
    final pinned   = all.where((c) => c.isPinned).toList();
    final unpinned = all.where((c) => !c.isPinned).toList();
    final items = <Widget>[];
    if (pinned.isNotEmpty && _searchQuery.isEmpty && _selectedFilter == 0) {
      items.add(_sectionLabel('PINNED', Icons.push_pin_rounded));
      for (var c in pinned) items.add(_dismissible(c));
      items.add(_sectionLabel('RECENT'));
    }
    for (var c in unpinned) items.add(_dismissible(c));

    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final delay = (i * 0.06).clamp(0.0, 0.6);
        return AnimatedBuilder(
          animation: _listCtrl,
          builder: (_, child) {
            final t  = ((_listCtrl.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
            final cv = Curves.easeOutCubic.transform(t);
            return Transform.translate(
              offset: Offset(0, (1 - cv) * 28),
              child: Opacity(opacity: cv, child: child),
            );
          },
          child: items[i],
        );
      },
    );
  }

  Widget _sectionLabel(String t, [IconData? icon]) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
    child: Row(children: [
      if (icon != null) ...[Icon(icon, size: 13, color: _txtSub.withOpacity(0.6)), const SizedBox(width: 5)],
      Text(t, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800,
          color: _txtSub.withOpacity(0.6), letterSpacing: 1.2)),
    ]),
  );

  Widget _dismissible(ChatConversation c) => Dismissible(
    key: ValueKey(c.id + c.isArchived.toString()),
    background: Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(color: const Color(0xFF2ECC96), borderRadius: BorderRadius.circular(20)),
      alignment: Alignment.centerLeft,
      child: const Icon(Icons.archive_rounded, color: Colors.white, size: 26),
    ),
    secondaryBackground: Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(color: const Color(0xFFE05C5C), borderRadius: BorderRadius.circular(20)),
      alignment: Alignment.centerRight,
      child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
    ),
    confirmDismiss: (dir) async {
      if (dir == DismissDirection.startToEnd) {
        setState(() => c.isArchived = true);
        _toast('Chat archived');
        return false;
      }
      return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Chat?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: _txtMain)),
          content: Text('Delete chat with ${c.name}?', style: GoogleFonts.dmSans(color: _txtSub)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.dmSans(color: _txtSub, fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: () { Navigator.pop(context, true); setState(() => _convos.remove(c)); },
              child: Text('Delete', style: GoogleFonts.dmSans(color: const Color(0xFFE05C5C), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    },
    child: _tile(c),
  );

  Widget _tile(ChatConversation c) {
    final hu = c.unread > 0;
    return GestureDetector(
      onTap: () => _openThread(c),
      onLongPress: () => _longPressMenu(c),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hu ? _accent.withOpacity(_isDark ? 0.08 : 0.05) : _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hu ? _accent.withOpacity(0.25) : _border, width: 1.5),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(hu ? 0.10 : 0.04), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Stack(children: [
            Container(width: 52, height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                    boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))]),
                child: Center(child: Text(c.initials,
                    style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)))),
            if (c.online) Positioned(bottom: 1, right: 1,
                child: Container(width: 14, height: 14,
                    decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle,
                        border: Border.all(color: _cardBg, width: 2)))),
          ]),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (c.isPinned) Padding(padding: const EdgeInsets.only(right: 5),
                  child: Icon(Icons.push_pin_rounded, size: 12, color: _accent.withOpacity(0.7))),
              Expanded(child: Text(c.name,
                  style: GoogleFonts.dmSans(fontSize: 15.5, fontWeight: FontWeight.w700, color: _txtMain))),
              if (c.isMuted) Padding(padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.volume_off_rounded, size: 13, color: _txtSub.withOpacity(0.5))),
              Text(c.time, style: GoogleFonts.dmSans(fontSize: 11.5,
                  color: hu ? _accent : _txtSub.withOpacity(0.7),
                  fontWeight: hu ? FontWeight.w700 : FontWeight.w400)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(c.lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 13,
                      color: hu ? _txtMain.withOpacity(0.85) : _txtSub,
                      fontWeight: hu ? FontWeight.w600 : FontWeight.w400))),
              if (hu)
                Container(margin: const EdgeInsets.only(left: 8), width: 22, height: 22,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]),
                    child: Center(child: Text('${c.unread}',
                        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)))),
            ]),
          ])),
        ]),
      ),
    );
  }

  // ── Long press menu ────────────────────────────────────────────────────────
  void _longPressMenu(ChatConversation c) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: _border, width: 1.2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _handle(),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor])),
                    child: Center(child: Text(c.initials, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)))),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
                  Text(c.service, style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                ]),
              ])),
          Divider(color: _border, height: 1),
          _menuItem(Icons.mark_chat_read_rounded, c.unread > 0 ? 'Mark as Read' : 'Mark as Unread',
              () => setState(() => c.unread = c.unread > 0 ? 0 : 1)),
          _menuItem(c.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              c.isPinned ? 'Unpin' : 'Pin Chat', () => setState(() => c.isPinned = !c.isPinned)),
          _menuItem(c.isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              c.isMuted ? 'Unmute' : 'Mute', () => setState(() => c.isMuted = !c.isMuted)),
          _menuItem(Icons.archive_rounded, 'Archive', () { setState(() => c.isArchived = true); _toast('Archived'); }),
          _menuItem(Icons.block_rounded, 'Block', () => _toast('${c.name} blocked')),
        ]),
      ),
    );
  }

  Widget _handle() => Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4)));

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => ListTile(
    leading: Icon(icon, color: _accent, size: 22),
    title: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: _txtMain)),
    onTap: () { Navigator.pop(context); onTap(); },
  );

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _openThread(ChatConversation c) {
    setState(() => c.unread = 0);
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => ChatThreadScreen(conversation: c, allConversations: _convos),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 320),
    ));
  }

  void _openArchived() {
    final archived = _convos.where((c) => c.isArchived).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ArchivedChatsScreen(
      archivedConvos: archived,
      onUnarchive: (c) => setState(() => c.isArchived = false),
      onTap: (c) { setState(() => c.unread = 0); _openThread(c); },
    )));
  }

  // ── FAB + new message ──────────────────────────────────────────────────────
  Widget _buildFab() => FloatingActionButton(
    onPressed: _showNewMsg, backgroundColor: Colors.transparent, elevation: 0,
    child: Container(width: 56, height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22)),
  );

  void _showNewMsg() {
    final contacts = [
      const NewContact('Fatima Malik',  'Dermatology',   Color(0xFF4A90D9), true),
      const NewContact('Usman Raza',    'Physiotherapy', Color(0xFF7C5CBF), false),
      const NewContact('Nadia Sheikh',  'Nutrition',     Color(0xFF2ECC96), true),
      const NewContact('Kamran Baig',   'Cardiology',    Color(0xFFE8805A), false),
      const NewContact('Saira Qureshi', 'Dental',        Color(0xFF3B73C0), true),
    ];
    final sc = TextEditingController();
    var q = '';
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final fl = q.isEmpty ? contacts : contacts.where((c) => c.name.toLowerCase().contains(q.toLowerCase())).toList();
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.78,
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(children: [
            _handle(),
            Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18)),
                  const SizedBox(width: 14),
                  Expanded(child: Text('New Message', style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w900, color: _txtMain, letterSpacing: -0.5))),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: _border.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.close_rounded, color: _txtSub, size: 18))),
                ])),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(height: 46,
                    decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border, width: 1.5)),
                    child: Row(children: [
                      const SizedBox(width: 14), Icon(Icons.search_rounded, color: _txtSub, size: 18), const SizedBox(width: 10),
                      Expanded(child: TextField(controller: sc, onChanged: (v) => set(() => q = v),
                          style: GoogleFonts.dmSans(fontSize: 14, color: _txtMain),
                          decoration: InputDecoration(hintText: 'Search contacts...',
                              hintStyle: GoogleFonts.dmSans(color: _txtSub), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero))),
                    ]))),
            Divider(color: _border, height: 1),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: fl.length,
              itemBuilder: (_, i) {
                final c = fl[i];
                return GestureDetector(
                  onTap: () { Navigator.pop(ctx); _openNewThread(c); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border, width: 1.2)),
                    child: Row(children: [
                      Stack(children: [
                        Container(width: 46, height: 46,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.color.withOpacity(0.7), c.color])),
                            child: Center(child: Text(c.initials, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)))),
                        if (c.online) Positioned(bottom: 0, right: 0,
                            child: Container(width: 13, height: 13, decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle, border: Border.all(color: _cardBg, width: 2)))),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w700, color: _txtMain)),
                        Text(c.service, style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                      ])),
                      Container(width: 32, height: 32,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 15)),
                    ]),
                  ),
                );
              },
            )),
          ]),
        );
      }),
    );
  }

  void _openNewThread(NewContact contact) {
    final ex = _convos.where((c) => c.name == contact.name).toList();
    if (ex.isNotEmpty) { _openThread(ex.first); return; }
    final n = ChatConversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: contact.name, service: contact.service,
      avatarColor: contact.color, online: contact.online,
      lastMsg: 'New conversation', time: 'Now', unread: 0,
    );
    setState(() => _convos.insert(0, n));
    _openThread(n);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
    backgroundColor: _accent, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));
}
