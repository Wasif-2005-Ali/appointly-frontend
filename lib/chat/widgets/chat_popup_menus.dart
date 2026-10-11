import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  INBOX POPUP MENU
// ─────────────────────────────────────────────────────────────────────────────
class InboxPopupMenu extends StatelessWidget {
  final Color accent, cardBg, border, txtMain, txtSub;
  final void Function(String) onSelect;

  const InboxPopupMenu({
    super.key,
    required this.accent,
    required this.cardBg,
    required this.border,
    required this.txtMain,
    required this.txtSub,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        onSelected: onSelect,
        offset: const Offset(0, 44),
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1.2),
        ),
        elevation: 8,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 19),
        ),
        itemBuilder: (_) => [
          _item('new_group', 'New Group',        Icons.group_rounded),
          _item('starred',   'Starred Messages', Icons.star_outline_rounded),
          _item('archived',  'Archived Chats',   Icons.archive_rounded),
          _item('settings',  'Settings',         Icons.settings_rounded),
        ],
      );

  PopupMenuItem<String> _item(String v, String label, IconData icon) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w600, color: txtMain)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  THREAD POPUP MENU
// ─────────────────────────────────────────────────────────────────────────────
class ThreadPopupMenu extends StatelessWidget {
  final Color accent, cardBg, border, txtMain;
  final void Function(String) onSelect;

  const ThreadPopupMenu({
    super.key,
    required this.accent,
    required this.cardBg,
    required this.border,
    required this.txtMain,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        onSelected: onSelect,
        offset: const Offset(0, 44),
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1.2),
        ),
        elevation: 8,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 17),
        ),
        itemBuilder: (_) => [
          _item('search',    'Search in Chat',        Icons.search_rounded),
          _item('contact',   'View Contact',          Icons.person_rounded),
          _item('mute',      'Mute Notifications',    Icons.volume_off_rounded),
          _item('timer',     'Disappearing Messages', Icons.timer_outlined),
          _item('starred',   'Starred Messages',      Icons.star_outline_rounded),
          _item('wallpaper', 'Chat Wallpaper',        Icons.wallpaper_rounded),
          _item('clear',     'Clear Chat',            Icons.cleaning_services_rounded),
          _item('block',     'Block Contact',         Icons.block_rounded),
          _item('report',    'Report',                Icons.flag_rounded),
        ],
      );

  PopupMenuItem<String> _item(String v, String label, IconData icon) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w600, color: txtMain)),
        ]),
      );
}
