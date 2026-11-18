import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_state.dart';
import '../../user_session.dart';
import '../data/chat_db.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
// Deliberately small: the old screen was eight toggles that did
// nothing (no persistence, nothing read them), a fake "Export Chat
// History", a fake "Blocked List", and a "Clear All Chats" that
// deleted nothing. Everything here is real: the profile card shows
// the logged-in user, and "Clear cached chats" actually clears the
// local message cache on this device.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final bg = AppStateProvider.of(context).bg;
    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              children: [
                _profileCard(context),
                const SizedBox(height: 20),
                _section(context, 'Storage', [
                  _action(
                    context,
                    'Clear cached chats on this device',
                    Icons.cleaning_services_rounded,
                    const Color(0xFFE05C5C),
                    'Removes saved messages from this phone only. '
                    'They stay on the server and reload next time.',
                    () => _confirmClear(context),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final hero = AppStateProvider.of(context).heroGradient;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hero,
          stops: const [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat Settings',
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.6,
                      ),
                    ),
                    Text(
                      'Your profile and saved chats',
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile card (real user, from the session) ─────────────────────────────
  Widget _profileCard(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final session = UserSession.instance;
    final name = session.fullName.isNotEmpty ? session.fullName : 'You';
    final status = session.bio.isNotEmpty
        ? session.bio
        : session.profileStatus.isNotEmpty
            ? session.profileStatus
            : session.email;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: appState.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: appState.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: appState.btnShadow.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: appState.btnGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: appState.btnShadow.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                session.initials,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: appState.txtMain,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    color: appState.txtSub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section container ──────────────────────────────────────────────────────
  Widget _section(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final appState = AppStateProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: appState.txtSub.withOpacity(0.6),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: appState.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: appState.border, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: appState.btnShadow.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: children.asMap().entries.map((e) {
              final isLast = e.key == children.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    Divider(
                      indent: 56,
                      endIndent: 0,
                      color: appState.border,
                      height: 1,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Action row ─────────────────────────────────────────────────────────────
  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    onTap: onTap,
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 18),
    ),
    title: Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        color: AppStateProvider.of(context).txtSub,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );

  // ── Clear cached chats confirmation ────────────────────────────────────────
  // Local only: the backend has no delete endpoint, so the server
  // history stays and reloads next time a chat is opened — the
  // dialog says so honestly (same wording as the thread screen's
  // "Clear Chat").
  void _confirmClear(BuildContext context) => showDialog(
    context: context,
    builder: (ctx) {
      final appState = AppStateProvider.of(ctx);
      return AlertDialog(
        backgroundColor: appState.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Clear cached chats?',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w800,
            color: appState.txtMain,
          ),
        ),
        content: Text(
          'Saved messages will be cleared on this device only. They stay on the server and reload next time you open a chat.',
          style: GoogleFonts.dmSans(color: appState.txtSub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(
                color: appState.txtSub,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ChatDB.clearAll();
              if (context.mounted) {
                _toast(context, 'Cached chats cleared');
              }
            },
            child: Text(
              'Clear',
              style: GoogleFonts.dmSans(
                color: const Color(0xFFE05C5C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );

  void _toast(BuildContext context, String msg) {
    final accent = AppStateProvider.of(context).accent;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
        backgroundColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
