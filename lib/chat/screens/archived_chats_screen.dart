import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';
import '../models/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ARCHIVED CHATS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ArchivedChatsScreen extends StatefulWidget {
  final List<ChatConversation> archivedConvos;
  final void Function(ChatConversation) onUnarchive;
  final void Function(ChatConversation) onTap;

  const ArchivedChatsScreen({
    super.key,
    required this.archivedConvos,
    required this.onUnarchive,
    required this.onTap,
  });

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  late List<ChatConversation> _list;

  Color get _bg        => AppStateProvider.of(context).bg;
  Color get _cardBg    => AppStateProvider.of(context).cardBg;
  Color get _border    => AppStateProvider.of(context).border;
  Color get _txtMain   => AppStateProvider.of(context).txtMain;
  Color get _txtSub    => AppStateProvider.of(context).txtSub;
  Color get _accent    => AppStateProvider.of(context).accent;
  List<Color> get _btnGrad  => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow      => AppStateProvider.of(context).btnShadow;
  List<Color> get _hero     => AppStateProvider.of(context).heroGradient;

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.archivedConvos);
  }

  void _unarchive(ChatConversation c) {
    setState(() => _list.remove(c));
    widget.onUnarchive(c);
    _toast('${c.name} unarchived');
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _list.isEmpty ? _emptyState() : _buildList()),
      ]),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 80, height: 80,
        decoration: BoxDecoration(color: _accent.withOpacity(0.08), borderRadius: BorderRadius.circular(24)),
        child: Icon(Icons.archive_rounded, size: 38, color: _accent.withOpacity(0.4))),
    const SizedBox(height: 18),
    Text('No Archived Chats', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: _txtMain)),
    const SizedBox(height: 8),
    Text('Swipe a chat left to archive it', style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub)),
  ]));

  Widget _buildList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    itemCount: _list.length,
    itemBuilder: (_, i) {
      final c = _list[i];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _cardBg, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 1.5),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          onTap: () { Navigator.pop(context); widget.onTap(c); },
          leading: Stack(children: [
            Container(width: 50, height: 50,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                    boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                child: Center(child: Text(c.initials,
                    style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)))),
            if (c.online) Positioned(bottom: 0, right: 0,
                child: Container(width: 13, height: 13,
                    decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle,
                        border: Border.all(color: _cardBg, width: 2)))),
          ]),
          title: Text(c.name,
              style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: _txtMain)),
          subtitle: Text(c.lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: 12.5, color: _txtSub)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.time, style: GoogleFonts.dmSans(fontSize: 11, color: _txtSub.withOpacity(0.6))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _unarchive(c),
              child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _btnGrad),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.unarchive_rounded, color: Colors.white, size: 17)),
            ),
          ]),
        ),
      );
    },
  );

  Widget _buildHeader() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _hero, stops: const [0.0, 0.35, 0.7, 1.0]),
    ),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white.withOpacity(0.22))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Archived Chats', style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w900,
              color: Colors.white, letterSpacing: -0.6)),
          Text('${_list.length} archived conversation${_list.length == 1 ? "" : "s"}',
              style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w500)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.25))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.archive_rounded, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Text('${_list.length}', style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
      ]),
    )),
  );

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
    backgroundColor: _accent, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));
}
