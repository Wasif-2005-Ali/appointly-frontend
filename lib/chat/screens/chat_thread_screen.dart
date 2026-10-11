import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';
import '../data/chat_db.dart';
import '../models/chat_models.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/chat_misc_widgets.dart';
import '../widgets/chat_popup_menus.dart';
import 'chat_search_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT THREAD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ChatThreadScreen extends StatefulWidget {
  final ChatConversation conversation;
  final List<ChatConversation> allConversations;

  const ChatThreadScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with TickerProviderStateMixin {
  final TextEditingController _msgCtrl    = TextEditingController();
  final ScrollController      _scrollCtrl = ScrollController();
  final List<ChatMessage>     _msgs       = [];

  bool _typing = false, _showEmoji = false, _clientTyping = false;
  bool _recording = false, _loadedFromDb = false;
  ChatMessage? _replyTo;

  late AnimationController _typCtrl, _sendCtrl, _recCtrl;
  int _emojiTab    = 0;
  int _recSeconds  = 0;
  Timer? _recTimer;

  String get _convId => widget.conversation.id;

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? "AM" : "PM"}';
  }

  String _mkId() => '${DateTime.now().millisecondsSinceEpoch}${_msgs.length}';

  // ── Theme helpers ──────────────────────────────────────────────────────────
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
    _typCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _sendCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _recCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _initMessages();
  }

  Future<void> _initMessages() async {
    try {
      final saved = await ChatDB.load(_convId);
      if (saved.isNotEmpty) {
        setState(() { _msgs.addAll(saved); _loadedFromDb = true; });
      } else {
        _loadHistory();
      }
    } catch (_) {
      _loadHistory();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
  }

  void _loadHistory() {
    final now = DateTime.now();
    final t1  = _fmt(now.subtract(const Duration(hours: 2)));
    final t2  = _fmt(now.subtract(const Duration(hours: 1)));
    final t3  = _fmt(now.subtract(const Duration(minutes: 15)));
    final c   = widget.conversation;
    final day = ['Monday','Tuesday','Wednesday','Thursday','Friday'][now.weekday % 5];

    final m1 = ChatMessage(id:'1', text:'Hi! I wanted to confirm my appointment for $day.', fromMe:false, time:t1, type:MessageType.text, status:MessageStatus.read);
    final m2 = ChatMessage(id:'2', text:'Hello ${c.name.split(" ").first}! Yes, your ${c.service} appointment is confirmed ✓', fromMe:true, time:t1, type:MessageType.text, status:MessageStatus.read);
    final m3 = ChatMessage(id:'3', text:'Perfect, thank you! Should I bring anything special?', fromMe:false, time:t2, type:MessageType.text, status:MessageStatus.read);
    final m4 = ChatMessage(id:'4', text:'Nothing special needed. Just arrive 5 minutes early 😊', fromMe:true, time:t2, type:MessageType.text, status:MessageStatus.read, replyTo:m3);
    final m5 = ChatMessage(id:'5', text:c.lastMsg, fromMe:false, time:t3, type:MessageType.text, status:MessageStatus.delivered);

    setState(() => _msgs.addAll([m1, m2, m3, m4, m5]));
    for (final m in _msgs) ChatDB.save(_convId, m).catchError((_) {});
  }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _typCtrl.dispose(); _sendCtrl.dispose(); _recCtrl.dispose();
    _recTimer?.cancel();
    super.dispose();
  }

  // ── Message sending ────────────────────────────────────────────────────────
  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _sendCtrl.forward().then((_) => _sendCtrl.reverse());
    final msg = ChatMessage(
      id: _mkId(), text: text, fromMe: true,
      time: _fmt(DateTime.now()), type: MessageType.text,
      replyTo: _replyTo, status: MessageStatus.sent,
    );
    setState(() { _msgs.add(msg); _msgCtrl.clear(); _typing = false; _showEmoji = false; _replyTo = null; });
    ChatDB.save(_convId, msg).catchError((_) {});
    _scrollDown();
    // Simulate delivery + read
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => msg.status = MessageStatus.delivered);
      ChatDB.update(_convId, msg).catchError((_) {});
    });
    // Simulate reply
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _clientTyping = true);
      _scrollDown();
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        final reply = ChatMessage(
          id: _mkId(), text: 'Got it, thanks! 👍', fromMe: false,
          time: _fmt(DateTime.now()), type: MessageType.text, status: MessageStatus.delivered,
        );
        setState(() { _clientTyping = false; msg.status = MessageStatus.read; _msgs.add(reply); });
        ChatDB.update(_convId, msg).catchError((_) {});
        ChatDB.save(_convId, reply).catchError((_) {});
        _scrollDown();
      });
    });
  }

  void _sendEmoji(String e) {
    final msg = ChatMessage(id: _mkId(), text: e, fromMe: true, time: _fmt(DateTime.now()), type: MessageType.emoji);
    setState(() { _msgs.add(msg); _showEmoji = false; });
    ChatDB.save(_convId, msg).catchError((_) {});
    _scrollDown();
  }

  void _sendVoice(String dur) {
    final msg = ChatMessage(id: _mkId(), text: dur, fromMe: true, time: _fmt(DateTime.now()), type: MessageType.voice, voiceDuration: dur, status: MessageStatus.sent);
    setState(() => _msgs.add(msg));
    ChatDB.save(_convId, msg).catchError((_) {});
    _scrollDown();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => msg.status = MessageStatus.delivered);
      ChatDB.update(_convId, msg).catchError((_) {});
    });
  }

  /// Send a shared appointment card
  void _sendAppointment(String title, String date, String time) {
    final msg = ChatMessage(
      id: _mkId(), text: 'Appointment shared', fromMe: true,
      time: _fmt(DateTime.now()), type: MessageType.appointment,
      appointmentTitle: title, appointmentDate: date, appointmentTime: time,
      status: MessageStatus.sent,
    );
    setState(() => _msgs.add(msg));
    ChatDB.save(_convId, msg).catchError((_) {});
    _scrollDown();
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 80), () {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  });

  // ── Reaction logic ─────────────────────────────────────────────────────────
  void _react(ChatMessage msg, String emoji) {
    setState(() {
      if (msg.myReaction == emoji) {
        final cnt = (msg.reactions[emoji] ?? 1) - 1;
        if (cnt <= 0) msg.reactions.remove(emoji); else msg.reactions[emoji] = cnt;
        msg.myReaction = null;
      } else {
        if (msg.myReaction != null) {
          final old = msg.myReaction!;
          final cnt = (msg.reactions[old] ?? 1) - 1;
          if (cnt <= 0) msg.reactions.remove(old); else msg.reactions[old] = cnt;
        }
        msg.reactions[emoji] = (msg.reactions[emoji] ?? 0) + 1;
        msg.myReaction = emoji;
      }
    });
    ChatDB.update(_convId, msg).catchError((_) {});
    Navigator.pop(context);
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final c = widget.conversation;
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        _buildHeader(c),
        Expanded(child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: DotBackgroundPainter(_accent.withOpacity(0.025)))),
          ListView.builder(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            itemCount: _msgs.length + (_clientTyping ? 1 : 0),
            itemBuilder: (_, i) {
              if (_clientTyping && i == _msgs.length) return _typingBubble(c);
              final msg = _msgs[i];
              return Column(children: [
                if (i == 0) _dateSep('Today'),
                SwipeableMessage(onReply: () => setState(() => _replyTo = msg), child: _bubble(msg, c, i)),
              ]);
            },
          ),
        ])),
        if (_replyTo != null) _replyBar(),
        if (_recording) _recordingOverlay(),
        if (_showEmoji) _emojiKeyboard(),
        if (!_recording) _inputBar(c),
      ]),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(ChatConversation c) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _hero, stops: const [0.0, 0.35, 0.7, 1.0]),
    ),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
      child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 38, height: 38,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.22))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16))),
        const SizedBox(width: 8),
        GestureDetector(onTap: () => _toast('Contact info'),
            child: Stack(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                      border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
                      boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Center(child: Text(c.initials,
                      style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)))),
              if (c.online) Positioned(bottom: 0, right: 0, child: Container(width: 13, height: 13,
                  decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle,
                      border: Border.all(color: _hero.last, width: 2)))),
            ])),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(onTap: () => _toast('Contact info'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              Row(children: [
                if (c.online) ...[
                  Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(color: Color(0xFF2ECC96), shape: BoxShape.circle)),
                  Text('Active now', style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w500)),
                ] else Text(c.service, style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w500)),
              ]),
            ]))),
        // Video call
        GestureDetector(onTap: () => _toast('Video call'),
            child: Container(width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 17))),
        // Voice call
        GestureDetector(onTap: () => _toast('Voice call'),
            child: Container(width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: const Icon(Icons.phone_rounded, color: Colors.white, size: 17))),
        ThreadPopupMenu(accent: _accent, cardBg: _cardBg, border: _border, txtMain: _txtMain, onSelect: (v) {
          switch (v) {
            case 'search':    _openSearch(); break;
            case 'contact':   _toast('View contact'); break;
            case 'mute':      setState(() => c.isMuted = !c.isMuted); _toast(c.isMuted ? 'Muted' : 'Unmuted'); break;
            case 'timer':     _toast('Disappearing messages'); break;
            case 'starred':   _showStarred(); break;
            case 'wallpaper': _toast('Chat wallpaper'); break;
            case 'clear':     _clearChat(); break;
            case 'block':     _toast('Contact blocked'); break;
            case 'report':    _toast('Reported'); break;
          }
        }),
      ]),
    )),
  );

  // ── Date separator ─────────────────────────────────────────────────────────
  Widget _dateSep(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Expanded(child: Divider(color: _border, height: 1)),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border, width: 1)),
          child: Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: _txtSub))),
      Expanded(child: Divider(color: _border, height: 1)),
    ]),
  );

  // ── Message bubble ─────────────────────────────────────────────────────────
  Widget _bubble(ChatMessage msg, ChatConversation c, int idx) {
    final isMe    = msg.fromMe;
    final isEmoji = msg.type == MessageType.emoji;
    final isVoice = msg.type == MessageType.voice;
    final isAppt  = msg.type == MessageType.appointment;
    final showAv  = !isMe && (idx == 0 || _msgs[idx - 1].fromMe);

    if (msg.isDeleted) {
      return Padding(
        padding: EdgeInsets.only(bottom: 4, top: showAv ? 8 : 0),
        child: Row(mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
          if (!isMe) const SizedBox(width: 38),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: _cardBg.withOpacity(0.7), borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border, width: 1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.block_rounded, size: 14, color: _txtSub.withOpacity(0.5)), const SizedBox(width: 6),
                Text(isMe ? 'You deleted this message' : 'This message was deleted',
                    style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub, fontStyle: FontStyle.italic)),
              ])),
        ]),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 220 + (math.min(idx, 8) * 25)),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(isMe ? (1 - v) * 18 : (1 - v) * -18, 0),
        child: Opacity(opacity: v, child: child),
      ),
      child: GestureDetector(
        onLongPress: () => _msgMenu(msg, c),
        child: Padding(
          padding: EdgeInsets.only(bottom: 4, top: showAv && !isMe ? 8 : 0),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: showAv ? 1.0 : 0.0,
                    child: Container(width: 28, height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.6), c.avatarColor])),
                        child: Center(child: Text(c.initials[0], style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white))))),
                const SizedBox(width: 6),
              ],
              Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                if (msg.isForwarded) Padding(padding: const EdgeInsets.only(bottom: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shortcut_rounded, size: 12, color: _txtSub.withOpacity(0.6)), const SizedBox(width: 4),
                      Text('Forwarded', style: GoogleFonts.dmSans(fontSize: 11, color: _txtSub.withOpacity(0.6), fontStyle: FontStyle.italic)),
                    ])),
                // Appointment card or emoji or normal bubble
                if (isAppt)
                  _appointmentBubble(msg, isMe)
                else if (isEmoji)
                  Text(msg.text, style: const TextStyle(fontSize: 40))
                else
                  _textBubble(msg, c, isMe, isVoice),
                // Reactions
                if (msg.reactions.isNotEmpty)
                  Transform.translate(offset: const Offset(0, -4),
                      child: GestureDetector(
                        onTap: () => _showReactionDetails(msg, c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border, width: 1),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]),
                          child: Row(mainAxisSize: MainAxisSize.min,
                              children: msg.reactions.entries.map((e) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    padding: msg.myReaction == e.key ? const EdgeInsets.all(2) : EdgeInsets.zero,
                                    decoration: msg.myReaction == e.key ? BoxDecoration(color: _accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)) : null,
                                    child: Text(e.key, style: const TextStyle(fontSize: 13)),
                                  ),
                                  if (e.value > 1) ...[const SizedBox(width: 2), Text('${e.value}', style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: _txtSub))],
                                ]),
                              )).toList()),
                        ),
                      )),
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (msg.isStarred) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFD700))),
                  Text(msg.time, style: GoogleFonts.dmSans(fontSize: 10, color: _txtSub.withOpacity(0.7))),
                  if (isMe) ...[const SizedBox(width: 4), _tick(msg.status)],
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textBubble(ChatMessage msg, ChatConversation c, bool isMe, bool isVoice) => Container(
    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isVoice ? 0.75 : 0.68)),
    decoration: BoxDecoration(
      gradient: isMe ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      color: isMe ? null : _cardBg,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
      ),
      border: isMe ? null : Border.all(color: _border, width: 1.2),
      boxShadow: [BoxShadow(color: (isMe ? _btnShadow : Colors.black).withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // Reply preview
      if (msg.replyTo != null)
        Container(margin: const EdgeInsets.fromLTRB(10, 10, 10, 0), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.15) : _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: isMe ? Colors.white.withOpacity(0.6) : _accent, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(msg.replyTo!.fromMe ? 'You' : c.name.split(' ').first,
                  style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white.withOpacity(0.9) : _accent)),
              Text(msg.replyTo!.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12, color: isMe ? Colors.white.withOpacity(0.7) : _txtSub)),
            ])),
      Padding(
        padding: EdgeInsets.fromLTRB(isVoice ? 12 : 14, 10, isVoice ? 12 : 14, 10),
        child: isVoice
            ? VoiceBubble(duration: msg.voiceDuration ?? '0:00', isMe: isMe, accent: _accent, btnGrad: _btnGrad)
            : Text(msg.text, style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w500,
                color: isMe ? Colors.white : _txtMain, height: 1.45)),
      ),
    ]),
  );

  /// Appointment card bubble — new feature
  Widget _appointmentBubble(ChatMessage msg, bool isMe) => Container(
    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
    decoration: BoxDecoration(
      color: isMe ? null : _cardBg,
      gradient: isMe ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
      ),
      border: isMe ? null : Border.all(color: _border, width: 1.2),
      boxShadow: [BoxShadow(color: (isMe ? _btnShadow : Colors.black).withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.2) : _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_month_rounded, color: isMe ? Colors.white : _accent, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appointment', style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600,
                color: isMe ? Colors.white.withOpacity(0.7) : _txtSub)),
            Text(msg.appointmentTitle ?? 'Consultation', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w800,
                color: isMe ? Colors.white : _txtMain)),
          ])),
        ]),
        const SizedBox(height: 10),
        Container(height: 1, color: isMe ? Colors.white.withOpacity(0.2) : _border),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.today_rounded, size: 14, color: isMe ? Colors.white.withOpacity(0.75) : _txtSub),
          const SizedBox(width: 6),
          Text(msg.appointmentDate ?? '', style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isMe ? Colors.white.withOpacity(0.9) : _txtMain)),
          const SizedBox(width: 14),
          Icon(Icons.access_time_rounded, size: 14, color: isMe ? Colors.white.withOpacity(0.75) : _txtSub),
          const SizedBox(width: 6),
          Text(msg.appointmentTime ?? '', style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isMe ? Colors.white.withOpacity(0.9) : _txtMain)),
        ]),
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.15) : _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isMe ? Colors.white.withOpacity(0.2) : _accent.withOpacity(0.2)),
            ),
            child: Center(child: Text('View Appointment',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700,
                    color: isMe ? Colors.white : _accent)))),
      ]),
    ),
  );

  Widget _tick(MessageStatus s) {
    switch (s) {
      case MessageStatus.sent:      return Icon(Icons.check_rounded, size: 13, color: _txtSub.withOpacity(0.6));
      case MessageStatus.delivered: return Icon(Icons.done_all_rounded, size: 13, color: _txtSub.withOpacity(0.6));
      case MessageStatus.read:      return Icon(Icons.done_all_rounded, size: 13, color: _accent);
    }
  }

  // ── Typing bubble ──────────────────────────────────────────────────────────
  Widget _typingBubble(ChatConversation c) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Row(children: [
      Container(width: 28, height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.6), c.avatarColor])),
          child: Center(child: Text(c.initials[0], style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)))),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: _cardBg,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(20)),
            border: Border.all(color: _border, width: 1.2)),
        child: AnimatedBuilder(animation: _typCtrl, builder: (_, __) => Row(mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase  = ((_typCtrl.value * 3) - i).clamp(0.0, 1.0);
              final bounce = math.sin(phase * math.pi);
              return Container(margin: const EdgeInsets.symmetric(horizontal: 2.5), width: 7, height: 7,
                  transform: Matrix4.translationValues(0, -bounce * 5, 0),
                  decoration: BoxDecoration(color: _txtSub.withOpacity(0.4 + bounce * 0.6), shape: BoxShape.circle));
            }))),
      ),
    ]),
  );

  // ── Reply bar ──────────────────────────────────────────────────────────────
  Widget _replyBar() {
    final msg = _replyTo!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1))),
      child: Row(children: [
        Container(width: 3, height: 40, decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.fromMe ? 'You' : widget.conversation.name.split(' ').first,
              style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
          Text(msg.type == MessageType.voice ? '🎤 Voice message' : msg.text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
        ])),
        GestureDetector(onTap: () => setState(() => _replyTo = null),
            child: Icon(Icons.close_rounded, color: _txtSub, size: 20)),
      ]),
    );
  }

  // ── Recording overlay ──────────────────────────────────────────────────────
  Widget _recordingOverlay() {
    final mins = _recSeconds ~/ 60;
    final secs = (_recSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1)),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -4))]),
      child: Row(children: [
        AnimatedBuilder(animation: _recCtrl, builder: (_, __) => Container(width: 46, height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE05C5C).withOpacity(0.1 + _recCtrl.value * 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.4 + _recCtrl.value * 0.3), width: 2),
            ),
            child: const Icon(Icons.mic_rounded, color: Color(0xFFE05C5C), size: 22))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recording...', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFE05C5C))),
          const SizedBox(height: 3),
          AnimatedBuilder(animation: _recCtrl, builder: (_, __) => Row(children: [
            ...List.generate(20, (i) {
              final rng = math.Random(i * 13 + _recSeconds);
              final h   = (0.2 + rng.nextDouble() * 0.8) * 18;
              return Container(margin: const EdgeInsets.only(right: 2), width: 3, height: h,
                  decoration: BoxDecoration(color: const Color(0xFFE05C5C).withOpacity(0.4 + _recCtrl.value * 0.5), borderRadius: BorderRadius.circular(2)));
            }),
          ])),
        ])),
        const SizedBox(width: 12),
        Text('$mins:$secs', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFE05C5C))),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () { _recTimer?.cancel(); setState(() { _recording = false; _recSeconds = 0; }); },
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: _txtSub.withOpacity(0.1), borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
              child: Icon(Icons.close_rounded, color: _txtSub, size: 18)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            _recTimer?.cancel();
            final m2 = _recSeconds ~/ 60;
            final s2 = (_recSeconds % 60).toString().padLeft(2, '0');
            setState(() { _recording = false; _recSeconds = 0; });
            _sendVoice('$m2:$s2');
          },
          child: Container(width: 46, height: 46,
              decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19)),
        ),
      ]),
    );
  }

  // ── Emoji keyboard ─────────────────────────────────────────────────────────
  Widget _emojiKeyboard() => Container(
    height: 280,
    decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1))),
    child: Column(children: [
      Container(height: 44, color: _bg, child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          itemCount: emojiCategories.length,
          itemBuilder: (_, i) {
            final sel = _emojiTab == i;
            return GestureDetector(onTap: () => setState(() => _emojiTab = i),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? _accent.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: sel ? Border.all(color: _accent.withOpacity(0.4), width: 1.5) : null,
                    ),
                    child: Text(emojiCategories[i].icon, style: TextStyle(fontSize: sel ? 20 : 17))));
          })),
      Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: emojiCategories[_emojiTab].emojis.length,
          itemBuilder: (_, i) {
            final e = emojiCategories[_emojiTab].emojis[i];
            return GestureDetector(onTap: () => _sendEmoji(e),
                child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 22)))));
          })),
    ]),
  );

  // ── Attachment picker ──────────────────────────────────────────────────────
  void _showAttach() {
    final rows = [
      [Icons.camera_alt_rounded,       'Camera',      const Color(0xFF4A90D9)],
      [Icons.image_rounded,             'Gallery',     const Color(0xFF7C3AED)],
      [Icons.videocam_rounded,          'Video',       const Color(0xFF2ECC96)],
      [Icons.insert_drive_file_rounded, 'Document',    const Color(0xFFE8805A)],
      [Icons.calendar_month_rounded,    'Appointment', const Color(0xFF3B73C0)],
      [Icons.location_on_rounded,       'Location',    const Color(0xFFE05C5C)],
      [Icons.contact_page_rounded,      'Contact',     const Color(0xFF2A6AB5)],
      [Icons.payments_rounded,          'Payment',     const Color(0xFF2ECC96)],
    ];
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _border, width: 1.2)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
          Text('Share', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: rows.sublist(0, 4).map((r) => _attIcon(r[0] as IconData, r[1] as String, r[2] as Color, r[1] == 'Appointment')).toList()),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: rows.sublist(4).map((r) => _attIcon(r[0] as IconData, r[1] as String, r[2] as Color, r[1] == 'Appointment')).toList()),
        ]),
      ),
    ));
  }

  Widget _attIcon(IconData icon, String label, Color color, bool isAppt) => GestureDetector(
    onTap: () {
      Navigator.pop(context);
      if (isAppt) {
        _showAppointmentPicker();
      } else {
        _toast('$label coming soon');
      }
    },
    child: SizedBox(width: 68, child: Column(children: [
      Container(width: 54, height: 54,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, color: color, size: 26)),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center, maxLines: 1,
          style: GoogleFonts.dmSans(fontSize: 10.5, fontWeight: FontWeight.w600, color: _txtSub)),
    ])),
  );

  // ── Appointment picker (NEW FEATURE) ───────────────────────────────────────
  void _showAppointmentPicker() {
    final appts = [
      {'title': 'Consultation',    'date': 'Monday, May 12', 'time': '10:00 AM'},
      {'title': 'Follow-up Visit', 'date': 'Tuesday, May 13','time': '2:30 PM'},
      {'title': 'Physiotherapy',   'date': 'Wednesday, May 14','time': '9:00 AM'},
    ];
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: _border, width: 1.2)),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.fromLTRB(0, 10, 0, 16),
              decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18)),
                const SizedBox(width: 14),
                Text('Share Appointment', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900, color: _txtMain)),
              ])),
          const SizedBox(height: 16),
          Divider(color: _border, height: 1),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: appts.length,
            itemBuilder: (_, i) {
              final a = appts[i];
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _sendAppointment(a['title']!, a['date']!, a['time']!);
                },
                child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _border, width: 1.3),
                        boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
                    child: Row(children: [
                      Container(width: 44, height: 44,
                          decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                          child: Icon(Icons.calendar_month_rounded, color: _accent, size: 22)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['title']!, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: _txtMain)),
                        const SizedBox(height: 3),
                        Text('${a['date']}  •  ${a['time']}',
                            style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                      ])),
                      Container(width: 34, height: 34,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(11)),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 16)),
                    ])),
              );
            },
          )),
        ]),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _inputBar(ChatConversation c) {
    final vInsets = MediaQuery.of(context).viewInsets.bottom;
    final vPad    = MediaQuery.of(context).viewPadding.bottom;
    final botPad  = vInsets > 0 ? 0.0 : vPad;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + botPad),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1)),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -4))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Emoji toggle
        GestureDetector(
          onTap: () { FocusScope.of(context).unfocus(); setState(() => _showEmoji = !_showEmoji); },
          child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 40, height: 40,
              decoration: BoxDecoration(
                color: _showEmoji ? _accent.withOpacity(0.12) : _bg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _showEmoji ? _accent.withOpacity(0.3) : _border),
              ),
              child: Icon(Icons.emoji_emotions_rounded, color: _showEmoji ? _accent : _txtSub, size: 20)),
        ),
        const SizedBox(width: 8),
        // Text field
        Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _typing ? _accent.withOpacity(0.6) : _border, width: _typing ? 1.8 : 1.5),
                boxShadow: _typing ? [BoxShadow(color: _accent.withOpacity(0.10), blurRadius: 8)] : []),
            child: TextField(
              controller: _msgCtrl,
              onTap: () => setState(() => _showEmoji = false),
              onChanged: (v) => setState(() => _typing = v.isNotEmpty),
              onSubmitted: (_) => _send(),
              maxLines: 4, minLines: 1,
              style: GoogleFonts.dmSans(fontSize: 14, color: _txtMain, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Message ${c.name.split(" ").first}...',
                hintStyle: GoogleFonts.dmSans(color: _txtSub, fontSize: 14),
                border: InputBorder.none, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ))),
        const SizedBox(width: 8),
        // Attach (only when not typing)
        if (!_typing) ...[
          GestureDetector(onTap: _showAttach,
              child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
                  child: Icon(Icons.attach_file_rounded, color: _txtSub, size: 19))),
          const SizedBox(width: 8),
        ],
        // Send / Mic
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 0.88).chain(CurveTween(curve: Curves.easeOut)).animate(_sendCtrl),
          child: _typing
              ? GestureDetector(onTap: _send,
              child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 19)))
              : GestureDetector(
              onLongPressStart: (_) {
                HapticFeedback.heavyImpact();
                _recSeconds = 0;
                _recTimer   = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _recSeconds++); });
                setState(() => _recording = true);
              },
              onLongPressEnd: (_) {
                if (_recording) {
                  _recTimer?.cancel();
                  final m = _recSeconds ~/ 60;
                  final s = (_recSeconds % 60).toString().padLeft(2, '0');
                  setState(() { _recording = false; _recSeconds = 0; });
                  _sendVoice('$m:$s');
                }
              },
              child: AnimatedBuilder(animation: _recCtrl, builder: (_, __) => Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border, width: 1.5)),
                  child: Icon(Icons.mic_rounded, color: _txtSub, size: 20)))),
        ),
      ]),
    );
  }

  // ── Message long-press menu ────────────────────────────────────────────────
  void _msgMenu(ChatMessage msg, ChatConversation c) {
    HapticFeedback.mediumImpact();
    const qe = ['❤️', '😂', '😮', '😢', '🙏', '👍'];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: Container(
        decoration: BoxDecoration(color: _cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _border, width: 1.2)),
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 12), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                child: Text(msg.type == MessageType.voice ? '🎤 Voice message (${msg.voiceDuration})' : msg.text,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub))),
            // Quick reactions
            Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: qe.map((e) {
                  final mine = msg.myReaction == e;
                  return GestureDetector(onTap: () => _react(msg, e),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                          width: 44, height: 44,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: mine ? _accent.withOpacity(0.2) : _cardBg,
                              border: Border.all(color: mine ? _accent : _border, width: mine ? 2 : 1)),
                          child: Stack(children: [
                            Center(child: Text(e, style: const TextStyle(fontSize: 21))),
                            if (mine) Positioned(top: 2, right: 2, child: Container(width: 8, height: 8,
                                decoration: BoxDecoration(color: _accent, shape: BoxShape.circle))),
                          ])));
                }).toList())),
            Divider(color: _border, height: 1),
            _mAction(Icons.reply_rounded,          'Reply',    () => setState(() => _replyTo = msg)),
            _mAction(Icons.shortcut_rounded,        'Forward',  () => _showForwardSheet(msg)),
            _mAction(Icons.copy_rounded,            'Copy',     () { Clipboard.setData(ClipboardData(text: msg.text)); _toast('Copied'); }),
            _mAction(msg.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                msg.isStarred ? 'Unstar' : 'Star',
                () { setState(() => msg.isStarred = !msg.isStarred); ChatDB.update(_convId, msg).catchError((_) {}); },
                color: msg.isStarred ? const Color(0xFFFFD700) : null),
            _mAction(Icons.delete_outline_rounded, 'Delete', () => _deleteMenu(msg), color: const Color(0xFFE05C5C)),
          ]),
        )),
      )),
    );
  }

  Widget _mAction(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
    leading: Icon(icon, color: color ?? _accent, size: 22),
    title: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600,
        color: color == const Color(0xFFE05C5C) ? color! : _txtMain)),
    onTap: () { Navigator.pop(context); onTap(); },
  );

  // ── Starred messages ───────────────────────────────────────────────────────
  void _showStarred() {
    final starred = _msgs.where((m) => m.isStarred).toList();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
        builder: (_) => Container(
          height: 400, padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 22), const SizedBox(width: 10),
              Text('Starred Messages', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: _txtMain)),
            ])),
            const SizedBox(height: 12),
            if (starred.isEmpty)
              Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.star_outline_rounded, size: 52, color: _txtSub.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text('No starred messages', style: GoogleFonts.dmSans(fontSize: 15, color: _txtSub)),
              ])))
            else
              Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: starred.length,
                  itemBuilder: (_, i) {
                    final m = starred[i];
                    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                        child: Row(children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 16),
                          const SizedBox(width: 10),
                          Expanded(child: Text(m.text, style: GoogleFonts.dmSans(fontSize: 13.5, color: _txtMain))),
                          Text(m.time, style: GoogleFonts.dmSans(fontSize: 10.5, color: _txtSub)),
                        ]));
                  })),
          ]),
        ));
  }

  // ── Clear chat ─────────────────────────────────────────────────────────────
  void _clearChat() => showDialog(context: context, builder: (_) => AlertDialog(
    backgroundColor: _cardBg,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text('Clear Chat?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: _txtMain)),
    content: Text('All messages will be deleted.', style: GoogleFonts.dmSans(color: _txtSub)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.dmSans(color: _txtSub, fontWeight: FontWeight.w600))),
      TextButton(onPressed: () {
        Navigator.pop(context);
        setState(() => _msgs.clear());
        ChatDB.clear(_convId).catchError((_) {});
      }, child: Text('Clear', style: GoogleFonts.dmSans(color: const Color(0xFFE05C5C), fontWeight: FontWeight.w700))),
    ],
  ));

  // ── In-chat search (NEW FEATURE) ───────────────────────────────────────────
  void _openSearch() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSearchScreen(messages: _msgs)));
  }

  // ── Reaction details ───────────────────────────────────────────────────────
  void _showReactionDetails(ChatMessage msg, ChatConversation c) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Text('Reactions', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 16),
            ...msg.reactions.entries.map((e) => ListTile(
              leading: Text(e.key, style: const TextStyle(fontSize: 28)),
              title: Text(e.key == msg.myReaction ? 'You' : c.name.split(' ').first,
                  style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: _txtMain)),
              subtitle: Text('${e.value} reaction${e.value > 1 ? "s" : ""}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
              trailing: e.key == msg.myReaction ? GestureDetector(
                onTap: () { Navigator.pop(context); _react(msg, e.key); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFE05C5C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.3))),
                    child: Text('Remove', style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFE05C5C), fontWeight: FontWeight.w600))),
              ) : null,
            )).toList(),
          ]),
        ));
  }

  // ── Forward message ────────────────────────────────────────────────────────
  void _showForwardSheet(ChatMessage original) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (ctx) => Container(
          height: MediaQuery.of(ctx).size.height * 0.62,
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.shortcut_rounded, color: Colors.white, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Forward to', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900, color: _txtMain, letterSpacing: -0.5)),
                Text('Select a conversation', style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
              ])),
              GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _border.withOpacity(0.5), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.close_rounded, color: _txtSub, size: 16))),
            ])),
            Divider(color: _border, height: 1),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: widget.allConversations.where((c) => !c.isArchived).length,
              itemBuilder: (_, i) {
                final c = widget.allConversations.where((c) => !c.isArchived).toList()[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (c.id == _convId) {
                      final fwd = ChatMessage(id: _mkId(), text: original.text, fromMe: true,
                          time: _fmt(DateTime.now()), type: original.type, isForwarded: true, voiceDuration: original.voiceDuration);
                      setState(() => _msgs.add(fwd));
                      ChatDB.save(_convId, fwd).catchError((_) {});
                      _scrollDown();
                    } else {
                      _showForwardSuccess(c.name);
                    }
                  },
                  child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _border, width: 1.3),
                          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: Row(children: [
                        Stack(children: [
                          Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                              boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                              child: Center(child: Text(c.initials, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)))),
                          if (c.online) Positioned(bottom: 0, right: 0, child: Container(width: 12, height: 12,
                              decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle, border: Border.all(color: _cardBg, width: 2)))),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w700, color: _txtMain)),
                          Text(c.service, style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                        ])),
                        Container(width: 36, height: 36, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(11),
                            boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]),
                            child: const Icon(Icons.send_rounded, color: Colors.white, size: 16)),
                      ])),
                );
              },
            )),
          ]),
        ));
  }

  void _showForwardSuccess(String name) {
    showDialog(context: context, barrierColor: Colors.black26, builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border, width: 1.2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 12))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 4))]),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 32)),
            const SizedBox(height: 18),
            Text('Message Forwarded', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 8),
            Text('Forwarded to $name', style: GoogleFonts.dmSans(fontSize: 13.5, color: _txtSub, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 22),
            GestureDetector(onTap: () => Navigator.pop(context),
                child: Container(width: double.infinity, height: 50,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))]),
                    child: Center(child: Text('Done', style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))))),
          ])),
    ));
  }

  // ── Delete menu ────────────────────────────────────────────────────────────
  void _deleteMenu(ChatMessage msg) => showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Text('Delete Message?', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 20),
            _delBtn('Delete for Me', const Color(0xFFE05C5C), () {
              setState(() => msg.isDeleted = true);
              ChatDB.update(_convId, msg).catchError((_) {});
            }),
            if (msg.fromMe) ...[
              const SizedBox(height: 10),
              _delBtn('Delete for Everyone', const Color(0xFFE05C5C), () {
                setState(() { msg.isDeleted = true; msg.text = 'This message was deleted'; });
                ChatDB.update(_convId, msg).catchError((_) {});
              }),
            ],
            const SizedBox(height: 10),
            _delBtn('Cancel', _txtSub, () {}, outline: true),
          ])));

  Widget _delBtn(String label, Color color, VoidCallback onTap, {bool outline = false}) =>
      GestureDetector(onTap: () { Navigator.pop(context); onTap(); },
          child: Container(width: double.infinity, height: 50,
              decoration: BoxDecoration(color: outline ? Colors.transparent : color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: outline ? _border : color.withOpacity(0.4), width: 1.5)),
              child: Center(child: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: color)))));

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
    backgroundColor: _accent, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));
}
