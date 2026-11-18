import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../app_state.dart';
import '../database/bd_helper.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/incoming_requests_screen.dart';
import '../screens/my_appointments_screen.dart';
import '../screens/my_availability_screen.dart';
import '../screens/action_screens.dart';
import '../screens/personal_tasks_screen.dart';
import '../user_session.dart';
import '../services/auth_service.dart';
import '../screens/login_signup_screen.dart';
import '../chat/chat.dart';
import '../models/appointment.dart';

class DrawerWidget extends StatelessWidget {
  final String userName;
  final String userInitials;
  const DrawerWidget({super.key, required this.userName, required this.userInitials});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    // Real badge counts from AppState — the old hardcoded "5" / "3"
    // contradicted the real pending count. No badge when the count
    // is zero.
    final myId = UserSession.instance.userId?.toString();
    final todayCount = appState.appointments
        .where((a) => a.isToday)
        .length;
    final pendingIncoming = appState.appointments
        .where((a) =>
            a.providerId != null &&
            a.providerId == myId &&
            a.status == ApptStatus.pending)
        .length;
    return Drawer(
      backgroundColor: appState.cardBg,
      child: Column(children: [
        _header(context, appState),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _lbl("MAIN", appState),
              _item(context, appState, Icons.grid_view_rounded,            "Home",              true,  onTap: () => Navigator.pop(context)),
              _item(context, appState, Icons.calendar_month_rounded,       "My Appointments",   false, badge: todayCount > 0 ? '$todayCount' : null, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const MyAppointmentsScreen())); }),
              _item(context, appState, Icons.person_outline_rounded,       "Profile",           false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const ProfileScreen())); }),
              _lbl("MANAGE", appState),
              _item(context, appState, Icons.notifications_none_rounded,   "Incoming Requests", false, badge: pendingIncoming > 0 ? '$pendingIncoming' : null, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const IncomingRequestsScreen())); }),
              _item(context, appState, Icons.chat_bubble_outline_rounded,    "Messages",          false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const ChatInboxScreen())); }),
              _item(context, appState, Icons.access_time_rounded,          "My Availability",   false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const MyAvailabilityScreen())); }),
              _item(context, appState, Icons.star_outline_rounded,         "My Reviews",        false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const MyReviewsScreen())); }),
              _item(context, appState, Icons.check_circle_outline_rounded, "Personal Tasks",    false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const PersonalTasksScreen())); }),
              _lbl("SYSTEM", appState),
              _item(context, appState, Icons.settings_outlined,            "Settings",          false, onTap: () { Navigator.pop(context); Navigator.push(context, _route(const SettingsScreen())); }),
            ]),
          ),
        ),
        _logout(context, appState),
      ]),
    );
  }

  PageRoute _route(Widget p) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => p,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
        child: child),
    transitionDuration: const Duration(milliseconds: 350),
  );

  Widget _header(BuildContext ctx, AppState appState) {
    final headerColors = appState.heroGradient;
    final imgBytes = UserSession.instance.profileImageBytes;
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); Navigator.push(ctx, _route(const ProfileScreen())); },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(18, MediaQuery.of(ctx).padding.top + 14, 18, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [headerColors.first, headerColors.last]),
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.09))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.2), size: 20),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            // ── Profile avatar — shows photo if set, otherwise initials ──
            CircleAvatar(
              radius: 26,
              backgroundColor: appState.accent,
              child: imgBytes != null
                ? ClipOval(
                    child: Image.memory(
                      imgBytes,
                      width: 52,
                      height: 52,
                      cacheWidth: 104,
                      fit: BoxFit.cover,
                    ),
                  )
                : Text(userInitials, style: GoogleFonts.dmSans(
                    fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName, style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
              const SizedBox(height: 2),
              // The user's real profession — the old "Admin · Appointly"
              // subtitle was hardcoded for everyone.
              Text(
                  UserSession.instance.profession.trim().isNotEmpty
                      ? UserSession.instance.profession.trim()
                      : 'Appointly',
                  style: GoogleFonts.dmSans(
                      fontSize: 11.5, color: Colors.white.withOpacity(0.55))),
            ])),
          ]),
          // NOTE: no "Online" pill — there is no presence system, so a
          // permanent Online badge would be a false claim.
        ]),
      ),
    );
  }

  Widget _lbl(String l, AppState appState) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
    child: Text(l, style: GoogleFonts.dmSans(
        fontSize: 10.5, fontWeight: FontWeight.w800,
        color: appState.drawerSectionLabel, letterSpacing: 1.4)),
  );

  Widget _item(BuildContext ctx, AppState appState, IconData icon, String label, bool active,
      {String? badge, VoidCallback? onTap}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
            color: active ? appState.drawerActiveItemBg : Colors.transparent,
            borderRadius: BorderRadius.circular(11)),
        child: ListTile(
          onTap: onTap ?? () => Navigator.pop(ctx),
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(icon,
              color: active ? appState.drawerMenuFg : appState.drawerMenuFgSub, size: 20),
          title: Text(label, style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? appState.drawerMenuFg : appState.drawerMenuFg.withOpacity(appState.themeMode.isDark ? 0.78 : 0.82))),
          trailing: badge != null
              ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(10)),
              child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
              : null,
        ),
      );

  Widget _logout(BuildContext ctx, AppState appState) => Container(
    padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(ctx).padding.bottom + 12),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: appState.drawerDividerColor))),
    child: ListTile(
      onTap: () => _logoutDialog(ctx, appState),
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
      title: Text('Log Out', style: GoogleFonts.dmSans(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.redAccent)),
    ),
  );

  /// Same confirmation as the Settings logout, so a stray tap on the
  /// drawer item cannot sign the user out by accident.
  void _logoutDialog(BuildContext ctx, AppState appState) => showDialog(
    context: ctx,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: appState.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Log Out', style: GoogleFonts.dmSans(
          fontWeight: FontWeight.w800, color: appState.txtMain)),
      content: Text('Are you sure you want to log out?',
          style: GoogleFonts.dmSans(color: appState.txtSub)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: Text('Cancel', style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700, color: appState.txtSub)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(dialogCtx);
            await AuthService.instance.logout();
            await DBHelper.instance.clearSession();
            if (!ctx.mounted) return;
            Navigator.pushAndRemoveUntil(
              ctx,
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
              (route) => false,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Log Out', style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    ),
  );
}
