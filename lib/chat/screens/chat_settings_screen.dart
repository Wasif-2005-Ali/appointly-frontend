import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});
  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _readReceipts       = true;
  bool _onlineStatus       = true;
  bool _msgPreview         = true;
  bool _soundEnabled       = true;
  bool _vibrationEnabled   = true;
  bool _backupEnabled      = false;
  bool _autoDownload       = true;
  bool _disappearingMsgs   = false;
  String _disappearTimer   = '7 days';

  Color get _bg      => AppStateProvider.of(context).bg;
  Color get _cardBg  => AppStateProvider.of(context).cardBg;
  Color get _border  => AppStateProvider.of(context).border;
  Color get _txtMain => AppStateProvider.of(context).txtMain;
  Color get _txtSub  => AppStateProvider.of(context).txtSub;
  Color get _accent  => AppStateProvider.of(context).accent;
  List<Color> get _btnGrad => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow     => AppStateProvider.of(context).btnShadow;
  List<Color> get _hero    => AppStateProvider.of(context).heroGradient;

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            _profileCard(),
            const SizedBox(height: 20),
            _section('Privacy', [
              _toggle('Read Receipts',     Icons.done_all_rounded,       _readReceipts,     (v) => setState(() => _readReceipts = v)),
              _toggle('Online Status',     Icons.circle_rounded,         _onlineStatus,     (v) => setState(() => _onlineStatus = v)),
              _toggle('Message Previews', Icons.preview_rounded,         _msgPreview,       (v) => setState(() => _msgPreview = v)),
            ]),
            const SizedBox(height: 16),
            _section('Notifications', [
              _toggle('Sound',     Icons.volume_up_rounded,     _soundEnabled,     (v) => setState(() => _soundEnabled = v)),
              _toggle('Vibration', Icons.vibration_rounded,     _vibrationEnabled, (v) => setState(() => _vibrationEnabled = v)),
            ]),
            const SizedBox(height: 16),
            _section('Messages', [
              _toggle('Disappearing Messages', Icons.timer_outlined, _disappearingMsgs, (v) => setState(() => _disappearingMsgs = v)),
              if (_disappearingMsgs) _picker(
                'Timer', Icons.access_time_rounded, _disappearTimer,
                ['24 hours', '7 days', '30 days', '90 days'],
                (v) => setState(() => _disappearTimer = v!),
              ),
              _toggle('Auto-Download Media', Icons.download_rounded, _autoDownload, (v) => setState(() => _autoDownload = v)),
            ]),
            const SizedBox(height: 16),
            _section('Storage & Backup', [
              _toggle('Chat Backup', Icons.cloud_upload_rounded, _backupEnabled, (v) => setState(() => _backupEnabled = v)),
              _action('Clear All Chats',    Icons.cleaning_services_rounded, const Color(0xFFE05C5C), _confirmClear),
              _action('Export Chat History', Icons.download_for_offline_rounded, _accent, () => _toast('Export started')),
            ]),
            const SizedBox(height: 16),
            _section('Blocked Contacts', [
              _navItem('Blocked List', Icons.block_rounded, '0 contacts blocked'),
            ]),
          ],
        )),
      ]),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
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
          Text('Chat Settings',
              style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -0.6)),
          Text('Customize your messaging experience',
              style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w500)),
        ])),
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withOpacity(0.22))),
            child: const Icon(Icons.settings_rounded, color: Colors.white, size: 19)),
      ]),
    )),
  );

  // ── Profile card ───────────────────────────────────────────────────────────
  Widget _profileCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _cardBg, borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border, width: 1.5),
      boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 5))],
    ),
    child: Row(children: [
      Stack(children: [
        Container(width: 60, height: 60,
            decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Center(child: Text('ME',
                style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)))),
        Positioned(bottom: 0, right: 0, child: Container(width: 18, height: 18,
            decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _cardBg, width: 2)),
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 9))),
      ]),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your Name', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w800, color: _txtMain)),
        const SizedBox(height: 3),
        Text('Hey there! I\'m using Appointly.',
            style: GoogleFonts.dmSans(fontSize: 12.5, color: _txtSub)),
        const SizedBox(height: 8),
        GestureDetector(onTap: () => _toast('Edit profile'),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Text('Edit Profile', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)))),
      ])),
    ]),
  );

  // ── Section container ──────────────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title.toUpperCase(),
              style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800,
                  color: _txtSub.withOpacity(0.6), letterSpacing: 1.2))),
      Container(
        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border, width: 1.3),
            boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(children: children.asMap().entries.map((e) {
          final isLast = e.key == children.length - 1;
          return Column(children: [
            e.value,
            if (!isLast) Divider(indent: 56, endIndent: 0, color: _border, height: 1),
          ]);
        }).toList()),
      ),
    ],
  );

  // ── Toggle row ─────────────────────────────────────────────────────────────
  Widget _toggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: _accent, size: 18)),
            const SizedBox(width: 14),
            Expanded(child: Text(label,
                style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w600, color: _txtMain))),
            Transform.scale(scale: 0.85, child: Switch.adaptive(
              value: value, onChanged: onChanged,
              activeColor: _accent,
              trackColor: MaterialStateProperty.resolveWith((s) =>
                  s.contains(MaterialState.selected) ? _accent.withOpacity(0.3) : _border),
            )),
          ]));

  // ── Picker row ─────────────────────────────────────────────────────────────
  Widget _picker(String label, IconData icon, String current,
      List<String> options, ValueChanged<String?> onChanged) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: _accent, size: 18)),
            const SizedBox(width: 14),
            Expanded(child: Text(label,
                style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w600, color: _txtMain))),
            DropdownButton<String>(
              value: current, underline: const SizedBox(),
              style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: _accent),
              dropdownColor: _cardBg,
              borderRadius: BorderRadius.circular(16),
              onChanged: onChanged,
              items: options.map((o) => DropdownMenuItem(value: o,
                  child: Text(o, style: GoogleFonts.dmSans(fontSize: 13, color: _txtMain)))).toList(),
            ),
          ]));

  // ── Action row ─────────────────────────────────────────────────────────────
  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) =>
      ListTile(
        onTap: onTap,
        leading: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 18)),
        title: Text(label, style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w600, color: color)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );

  // ── Nav item row ───────────────────────────────────────────────────────────
  Widget _navItem(String label, IconData icon, String subtitle) =>
      ListTile(
        onTap: () => _toast('Blocked contacts'),
        leading: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _accent, size: 18)),
        title: Text(label, style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w600, color: _txtMain)),
        subtitle: Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
        trailing: Icon(Icons.chevron_right_rounded, color: _txtSub.withOpacity(0.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );

  // ── Clear chat confirmation ─────────────────────────────────────────────────
  void _confirmClear() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: _cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Clear All Chats?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: _txtMain)),
      content: Text('This will permanently delete all your messages. This action cannot be undone.',
          style: GoogleFonts.dmSans(color: _txtSub, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: _txtSub, fontWeight: FontWeight.w600))),
        TextButton(onPressed: () { Navigator.pop(context); _toast('All chats cleared'); },
            child: Text('Clear', style: GoogleFonts.dmSans(color: const Color(0xFFE05C5C), fontWeight: FontWeight.w700))),
      ],
    ),
  );

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
    backgroundColor: _accent, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));
}
