import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../database/bd_helper.dart';
import '../services/auth_service.dart';
import 'login_signup_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_selector_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  // NOTE: the old notification toggles, biometric / 2FA toggles and
  // Language / Timezone selectors were removed — all local-only,
  // reset on reopen, and controlling nothing (no notification system,
  // no local_auth, app is English-only). The fake "Subscription /
  // Billing / Connected Apps / Booking Link / Delete Account" rows
  // were removed for the same reason. Every remaining setting saves
  // immediately through AppState, so there is no Save button.

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  AppState get _appState => AppStateProvider.of(context);
  bool get _dark     => _appState.isDarkMode;
  Color get _bg      => _appState.bg;
  Color get _cardBg  => _appState.cardBg;
  Color get _border  => _appState.border;
  Color get _txtMain => _appState.txtMain;
  Color get _txtSub  => _appState.txtSub;
  Color get _accent  => _appState.accent;

  // ── JSON Export ───────────────────────────────────────────────────────────
  Future<void> _exportSettings() async {
    final settings = {
      // The real app version (pubspec 1.0.0+1) — the old export
      // claimed '9.0'.
      'appVersion': '1.0.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'theme': _appState.themeMode.name,
      'customAccent': _appState.customAccent.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'compactView': _appState.compactView,
      'showAccessibilityButton': _appState.showAccessibilityButton,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(settings);
    if (!mounted) return;
    _showExportSuccess(jsonStr);
  }

  void _showExportSuccess(String jsonStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Settings Exported', style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800, color: _txtMain, fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your settings JSON is ready. Download it to your device or copy it to share manually.',
              style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadJsonFile(jsonStr);
              },
              icon: const Icon(Icons.download_rounded, size: 17),
              label: Text('Download JSON', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonStr));
                Navigator.pop(ctx);
                _snack('JSON copied to clipboard ✓');
              },
              icon: Icon(Icons.copy_rounded, size: 16, color: _accent),
              label: Text('Copy JSON', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: _accent)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                side: BorderSide(color: _accent.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: _txtSub)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadJsonFile(String jsonStr) async {
    final bytes    = Uint8List.fromList(utf8.encode(jsonStr));
    final fileName = 'appointly_settings.json';

    // ── Attempt 1: direct write to /storage/emulated/0/Download (Android)
    // This is the actual device Downloads folder users can browse in Files.
    try {
      const downloadPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadPath);
      if (await dir.exists()) {
        final file = File('$downloadPath/$fileName');
        await file.writeAsString(jsonStr);
        if (!mounted) return;
        _snack('Saved to Downloads/$fileName ✓');
        return;
      }
    } catch (_) {}

    // ── Attempt 2: file_saver via MediaStore (Android 10+ without permission)
    try {
      await FileSaver.instance.saveFile(
        name: 'appointly_settings',
        bytes: bytes,
        ext: 'json',
        mimeType: MimeType.other,     // MimeType.json absent in some versions
        customMimeType: 'application/json',
      );
      if (!mounted) return;
      _snack('Saved to Downloads/$fileName ✓');
      return;
    } catch (_) {}

    // ── Attempt 3: share sheet — user taps "Save to Files" / "Downloads"
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Appointly Settings Export',
        text: 'Tap "Save to Files" or "Downloads" to store the file.',
      );
      return;
    } catch (_) {}

    // ── Last resort: clipboard
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: jsonStr));
    _snack('Could not access Downloads — JSON copied to clipboard instead');
  }

  // ── JSON Import — picks a real .json file ──────────────────────────────────
  Future<void> _importSettings() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Appointly Settings JSON',
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      String jsonStr;

      if (pickedFile.bytes != null) {
        // Web / bytes fallback
        jsonStr = String.fromCharCodes(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        jsonStr = await File(pickedFile.path!).readAsString();
      } else {
        _snack('Could not read the selected file');
        return;
      }

      await _applySettingsJson(jsonStr);
    } catch (e) {
      _snack('Error reading file: $e');
    }
  }

  Future<void> _applySettingsJson(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Restore AppState values
      if (data['theme'] != null) {
        final raw   = data['theme'] as String;
        final accent = data['customAccent'] as String?;
        if ((raw == 'customDark' || raw == 'customLight') && accent != null) {
          final hexVal = int.tryParse(accent, radix: 16);
          if (hexVal != null) {
            await _appState.setCustomTheme(
              Color(hexVal),
              dark: raw == 'customDark',
            );
          }
        } else {
          final mode = AppThemeMode.values.firstWhere(
            (m) => m.name == raw,
            orElse: () => _appState.themeMode,
          );
          _appState.setTheme(mode);
        }
      }
      if (data['compactView'] != null) {
        _appState.setCompactView(data['compactView'] as bool);
      }
      if (data['showAccessibilityButton'] != null) {
        _appState.setShowAccessibilityButton(data['showAccessibilityButton'] as bool);
      }

      // Older exports also carried notifications / security /
      // preferences keys — those settings no longer exist, so they
      // are ignored on import.
      setState(() {});

      _snack('Settings restored successfully ✓');
    } catch (_) {
      _snack('Invalid file — not a valid Appointly settings JSON');
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      color: _bg,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(children: [
          _hero(),
          Expanded(child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(children: [
                _section('Privacy', Icons.policy_outlined, AppColors.green, [
                  _tap('Privacy Policy',  Icons.policy_outlined,        'View our data practices', AppColors.green, _openPrivacyPolicy),
                ]),
                const SizedBox(height: 16),
                _section('Appearance', Icons.palette_outlined, _accent, [
                  // ── Appearance button — opens full Theme Selector ──────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const ThemeSelectorScreen(),
                        transitionsBuilder: (_, a, __, child) => SlideTransition(
                          position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                              .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
                          child: child,
                        ),
                        transitionDuration: const Duration(milliseconds: 350),
                      ),
                    ).then((_) => setState(() {})),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                      ),
                      child: Row(children: [
                        Container(width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _accent.withOpacity(0.2)),
                            ),
                            child: Icon(Icons.color_lens_rounded, color: _accent, size: 18)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Theme', style: GoogleFonts.dmSans(
                              fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain)),
                          Text('${_appState.themeMode.label}  •  ${_appState.isDarkMode ? "Dark" : "Light"} mode',
                              style: GoogleFonts.dmSans(
                                  fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
                        ])),
                        // Live colour preview dot
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: _accent, shape: BoxShape.circle,
                            border: Border.all(color: _border, width: 1.5),
                            boxShadow: [BoxShadow(color: _accent.withOpacity(0.4), blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios_rounded, color: _txtSub, size: 15),
                      ]),
                    ),
                  ),
                  _div(),
                  _tog('Compact View', 'Denser list layout', _appState.compactView, _accent, (v) {
                    _appState.setCompactView(v);
                    setState(() {});
                  }),
                  _div(),
                  _tog(
                    'Accessibility Button',
                    'Floating quick-access button on dashboard',
                    _appState.showAccessibilityButton,
                    _accent,
                        (v) { _appState.setShowAccessibilityButton(v); setState(() {}); },
                  ),
                ]),
                const SizedBox(height: 16),
                _section('Account', Icons.manage_accounts_outlined, _accent, [
                  _tap('Export Settings',    Icons.download_rounded,          'Save your settings as JSON',  _accent, () => _exportSettings()),
                  _div(),
                  _tap('Restore Settings',   Icons.restore_rounded,           'Apply settings from JSON',    AppColors.green, () => _importSettings()),
                ]),
                const SizedBox(height: 16),
                _dangerSection(),
              ]),
            ),
          ))),
        ]),
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────
  Widget _hero() => Container(
    decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: _appState.heroGradient)),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Row(children: [
        GestureDetector(onTap: ()=>Navigator.pop(context),
            child: _glass(child: Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18))),
        const SizedBox(width: 14),
        Expanded(child: Text('Settings', style: GoogleFonts.dmSans(
            fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3))),
        // No Save button: every setting here saves immediately
        // through AppState. The old button delayed 600ms and saved
        // nothing.
      ]),
    )),
  );

  // ── section card ───────────────────────────────────────────────────────────
  Widget _section(String title, IconData icon, Color color, List<Widget> children) =>
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border, width: 1.5),
            boxShadow: [BoxShadow(color: _accent.withOpacity(0.05), blurRadius: 14, offset: const Offset(0,4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 34, height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withOpacity(0.18), color.withOpacity(0.06)]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 10),
            Text(title, style: GoogleFonts.dmSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain, letterSpacing: -0.3)),
          ]),
          const SizedBox(height: 16),
          ...children,
        ]),
      );

  // ── toggle ─────────────────────────────────────────────────────────────────
  Widget _tog(String label, String sub, bool val, Color activeColor, ValueChanged<bool> cb) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain)),
            const SizedBox(height: 2),
            Text(sub,   style: GoogleFonts.dmSans(fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
          ])),
          _pillToggle(val, activeColor, (v) => cb(v)),
        ]),
      );

  Widget _pillToggle(bool val, Color activeColor, ValueChanged<bool> cb) =>
      GestureDetector(
        onTap: () => cb(!val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          width: 54, height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: val ? LinearGradient(colors: [activeColor, activeColor.withOpacity(0.7)]) : null,
            color: val ? null : (_dark ? const Color(0xFF30363D) : const Color(0xFFDDE5EF)),
            boxShadow: val ? [BoxShadow(color: activeColor.withOpacity(0.38),
                blurRadius: 10, offset: const Offset(0,2))] : [],
          ),
          child: Stack(alignment: Alignment.center, children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              left: val ? 26 : 2,
              child: Container(width: 26, height: 26,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18),
                          blurRadius: 6, offset: const Offset(0,2))])),
            ),
          ]),
        ),
      );

  Widget _tap(String label, IconData icon, String sub, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(9), border: Border.all(color: color.withOpacity(0.15))),
                child: Icon(icon, color: color, size: 17)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain)),
              Text(sub,   style: GoogleFonts.dmSans(fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
            ])),
            Icon(Icons.chevron_right_rounded, color: _txtSub, size: 20),
          ]),
        ),
      );

  Widget _dangerSection() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withOpacity(0.25), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.danger.withOpacity(0.05), blurRadius: 14, offset: const Offset(0,4))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18)),
        const SizedBox(width: 10),
        Text('Danger Zone', style: GoogleFonts.dmSans(
            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.danger, letterSpacing: -0.3)),
      ]),
      const SizedBox(height: 16),
      GestureDetector(onTap: _logoutDialog, child: _dangerRow('Log Out', Icons.logout_rounded, 'Sign out of Appointly')),
      // No "Delete Account" row: no delete endpoint exists, and the
      // old row just showed a snackbar naming support it never
      // identified. It returns if a real delete flow ships.
    ]),
  );

  Widget _dangerRow(String label, IconData icon, String sub) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Icon(icon, color: AppColors.danger, size: 20), const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger)),
        Text(sub,   style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.danger.withOpacity(0.6), fontWeight: FontWeight.w500)),
      ])),
      Icon(Icons.chevron_right_rounded, color: AppColors.danger.withOpacity(0.4), size: 20),
    ]),
  );

  Widget _div() => Divider(color: _border, thickness: 1.5, height: 1);

  Widget _glass({required Widget child, double size = 42}) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Center(child: child),
  );

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.white)),
    backgroundColor: _accent,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));

  /// Opens the real privacy policy hosted by the backend.
  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('https://appointly-backend-dogk.onrender.com/privacy/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      _snack('Could not open the privacy policy');
    }
  }

  void _logoutDialog() => showDialog(context: context, builder: (ctx) => AlertDialog(
    backgroundColor: _cardBg,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text('Log Out', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: _txtMain)),
    content: Text('Are you sure you want to log out?', style: GoogleFonts.dmSans(color: _txtSub)),
    actions: [
      TextButton(onPressed: ()=>Navigator.pop(ctx),
          child: Text('Cancel', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: _txtSub))),
      ElevatedButton(
        onPressed: () async {
          Navigator.pop(ctx);
          await AuthService.instance.logout();
          await DBHelper.instance.clearSession();
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (r) => false,
          );
        },
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text('Log Out', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    ],
  ));
}


