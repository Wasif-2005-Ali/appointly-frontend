import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';
import '../models/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  IN-CHAT SEARCH SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ChatSearchScreen extends StatefulWidget {
  final List<ChatMessage> messages;
  const ChatSearchScreen({super.key, required this.messages});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  int _current  = 0;

  Color get _bg      => AppStateProvider.of(context).bg;
  Color get _cardBg  => AppStateProvider.of(context).cardBg;
  Color get _border  => AppStateProvider.of(context).border;
  Color get _txtMain => AppStateProvider.of(context).txtMain;
  Color get _txtSub  => AppStateProvider.of(context).txtSub;
  Color get _accent  => AppStateProvider.of(context).accent;
  List<Color> get _btnGrad => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow     => AppStateProvider.of(context).btnShadow;
  List<Color> get _hero    => AppStateProvider.of(context).heroGradient;

  List<ChatMessage> get _results => _query.isEmpty
      ? []
      : widget.messages
          .where((m) =>
              !m.isDeleted &&
              m.type != MessageType.voice &&
              m.text.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final results = _results;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(results),
        Expanded(child: results.isEmpty ? _emptyState() : _buildResults(results)),
      ]),
    );
  }

  Widget _buildHeader(List<ChatMessage> results) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _hero, stops: const [0.0, 0.35, 0.7, 1.0]),
    ),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      child: Column(children: [
        Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.22))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16))),
          const SizedBox(width: 12),
          Expanded(child: Text('Search Messages',
              style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -0.5))),
          if (results.isNotEmpty) ...[
            GestureDetector(
              onTap: () => setState(() => _current = (_current - 1 + results.length) % results.length),
              child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20)),
            ),
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_current + 1}/${results.length}',
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _current = (_current + 1) % results.length),
              child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20)),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Container(height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.2))),
            child: Row(children: [
              const SizedBox(width: 14),
              const Icon(Icons.search_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _ctrl, autofocus: true,
                onChanged: (v) => setState(() { _query = v; _current = 0; }),
                style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search in conversation...',
                  hintStyle: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                ),
              )),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() { _ctrl.clear(); _query = ''; _current = 0; }),
                  child: Padding(padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.6), size: 17)),
                ),
            ])),
      ]),
    )),
  );

  Widget _emptyState() {
    if (_query.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 76, height: 76,
            decoration: BoxDecoration(color: _accent.withOpacity(0.08), borderRadius: BorderRadius.circular(22)),
            child: Icon(Icons.search_rounded, size: 36, color: _accent.withOpacity(0.4))),
        const SizedBox(height: 18),
        Text('Search Messages', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: _txtMain)),
        const SizedBox(height: 8),
        Text('Type to find messages in this chat',
            style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub)),
      ]));
    }
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 76, height: 76,
          decoration: BoxDecoration(color: _accent.withOpacity(0.08), borderRadius: BorderRadius.circular(22)),
          child: Icon(Icons.search_off_rounded, size: 36, color: _accent.withOpacity(0.4))),
      const SizedBox(height: 18),
      Text('No Results Found', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: _txtMain)),
      const SizedBox(height: 8),
      Text('No messages matching "$_query"',
          style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub)),
    ]));
  }

  Widget _buildResults(List<ChatMessage> results) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    itemCount: results.length,
    itemBuilder: (_, i) {
      final msg = results[i];
      final isActive = i == _current;
      return GestureDetector(
        onTap: () => setState(() => _current = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive ? _accent.withOpacity(0.08) : _cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isActive ? _accent.withOpacity(0.4) : _border,
                width: isActive ? 2 : 1.3),
            boxShadow: [BoxShadow(
                color: (isActive ? _accent : Colors.black).withOpacity(isActive ? 0.1 : 0.04),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: msg.fromMe ? _accent.withOpacity(0.12) : _cardBg.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: msg.fromMe ? _accent.withOpacity(0.3) : _border),
                  ),
                  child: Text(msg.fromMe ? 'You' : 'Them',
                      style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700,
                          color: msg.fromMe ? _accent : _txtSub))),
              const Spacer(),
              if (msg.isStarred) const Padding(padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD700))),
              Text(msg.time, style: GoogleFonts.dmSans(fontSize: 11, color: _txtSub.withOpacity(0.7))),
            ]),
            const SizedBox(height: 10),
            _highlightedText(msg.text, _query),
          ]),
        ),
      );
    },
  );

  /// Highlight matched query text in a message
  Widget _highlightedText(String text, String query) {
    if (query.isEmpty) return Text(text, style: GoogleFonts.dmSans(fontSize: 14, color: _txtMain));
    final lower  = text.toLowerCase();
    final qLower = query.toLowerCase();
    final spans  = <TextSpan>[];
    int start    = 0;
    while (true) {
      final idx = lower.indexOf(qLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.w800, color: _accent,
          backgroundColor: _accent.withOpacity(0.13),
        ),
      ));
      start = idx + query.length;
    }
    return RichText(text: TextSpan(
        style: GoogleFonts.dmSans(fontSize: 14, color: _txtMain, height: 1.5), children: spans));
  }
}
