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
import '../app_state.dart';
import '../database/bd_helper.dart';
import '../user_session.dart';
import 'login_signup_screen.dart';
import '../theme/app_theme.dart';
import '../theme/custom_color_picker.dart';
import '../theme/theme_selector_screen.dart';
import '../widgets/save_icon_button.dart';
import '../widgets/save_success_overlay.dart';


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

  // ── Change signal: notifies SaveIconButton to reset tick → idle on any edit ─
  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  bool _notifAppointments = true;
  bool _notifReminders    = true;
  bool _notifMessages     = false;
  bool _notifMarketing    = false;
  bool _biometrics        = true;
  bool _twoFactor         = false;
  bool _showThemePicker   = false;
  String _language = 'English';
  String _timezone = 'PKT (UTC+5)';

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
  void dispose() { _ctrl.dispose(); _cs.dispose(); super.dispose(); }

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
      'appVersion': '9.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'theme': _appState.themeMode.name,
      'customAccent': _appState.customAccent.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'compactView': _appState.compactView,
      'showAccessibilityButton': _appState.showAccessibilityButton,
      'notifications': {
        'appointments': _notifAppointments,
        'reminders': _notifReminders,
        'messages': _notifMessages,
        'marketing': _notifMarketing,
      },
      'security': {
        'biometrics': _biometrics,
        'twoFactor': _twoFactor,
      },
      'preferences': {
        'language': _language,
        'timezone': _timezone,
      },
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

      // Restore screen-local settings
      final notif = data['notifications'] as Map<String, dynamic>?;
      final sec   = data['security']     as Map<String, dynamic>?;
      final pref  = data['preferences']  as Map<String, dynamic>?;

      setState(() {
        if (notif != null) {
          _notifAppointments = notif['appointments'] as bool? ?? _notifAppointments;
          _notifReminders    = notif['reminders']    as bool? ?? _notifReminders;
          _notifMessages     = notif['messages']     as bool? ?? _notifMessages;
          _notifMarketing    = notif['marketing']    as bool? ?? _notifMarketing;
        }
        if (sec != null) {
          _biometrics = sec['biometrics'] as bool? ?? _biometrics;
          _twoFactor  = sec['twoFactor']  as bool? ?? _twoFactor;
        }
        if (pref != null) {
          _language = pref['language'] as String? ?? _language;
          _timezone = pref['timezone'] as String? ?? _timezone;
        }
      });

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
                _section('Notifications', Icons.notifications_outlined, _accent, [
                  _tog('New Appointments', 'Get notified for bookings',       _notifAppointments, _accent, (v)=>setState(()=>_notifAppointments=v)),
                  _div(),
                  _tog('Reminders',        'Appointment reminders 1hr before', _notifReminders,    _accent, (v)=>setState(()=>_notifReminders=v)),
                  _div(),
                  _tog('Messages',         'Client messages & chat',           _notifMessages,     _accent, (v)=>setState(()=>_notifMessages=v)),
                  _div(),
                  _tog('Marketing',        'Tips, offers & product updates',   _notifMarketing,    _accent, (v)=>setState(()=>_notifMarketing=v)),
                ]),
                const SizedBox(height: 16),
                _section('Privacy & Security', Icons.security_outlined, AppColors.green, [
                  _tog('Biometric Login', 'Fingerprint or Face ID',     _biometrics, AppColors.green, (v)=>setState(()=>_biometrics=v)),
                  _div(),
                  _tog('Two-Factor Auth', 'Extra SMS verification step', _twoFactor,  AppColors.green, (v)=>setState(()=>_twoFactor=v)),
                  _div(),
                  _tap('Change Password', Icons.lock_outline_rounded,   'Update your password',   AppColors.green, ()=>_snack('Change Password')),
                  _div(),
                  _tap('Privacy Policy',  Icons.policy_outlined,        'View our data practices', AppColors.green, ()=>_snack('Privacy Policy')),
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
                _section('Preferences', Icons.tune_rounded, AppColors.warning, [
                  _drop('Language', _language, ['English','Urdu','Arabic'], (v)=>setState(()=>_language=v!)),
                  _div(),
                  _drop('Timezone',  _timezone, ['PKT (UTC+5)','GST (UTC+4)','UTC','EST (UTC-5)'], (v)=>setState(()=>_timezone=v!)),
                  _div(),
                  _tap('Booking Link', Icons.link_rounded, 'appointly.pk/${UserSession.instance.fullName.trim().toLowerCase().replaceAll(' ', '')}', AppColors.warning, () { Clipboard.setData(ClipboardData(text: 'https://appointly.pk/${UserSession.instance.fullName.trim().toLowerCase().replaceAll(" ", "")}')); _snack('Booking link copied ✓'); }),
                ]),
                const SizedBox(height: 16),
                _section('Account', Icons.manage_accounts_outlined, _accent, [
                  _tap('Subscription Plan',  Icons.workspace_premium_rounded, 'Pro Plan · Active',       _accent, ()=>_snack('Manage Subscription')),
                  _div(),
                  _tap('Billing & Payments', Icons.credit_card_rounded,       'Manage payment methods',  _accent, ()=>_snack('Billing')),
                  _div(),
                  _tap('Export Settings',    Icons.download_rounded,          'Save your settings as JSON',  _accent, () => _exportSettings()),
                  _div(),
                  _tap('Restore Settings',   Icons.restore_rounded,           'Apply settings from JSON',    AppColors.green, () => _importSettings()),
                  _div(),
                  _tap('Connected Apps',     Icons.apps_rounded,              'Google Calendar, WhatsApp',_accent, ()=>_snack('Connected Apps')),
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
        SaveIconButton(
          changeSignal: _cs,
          // FIX: white logo so it's visible on the dark gradient header
          foregroundColor: Colors.white,
          onSave: () async {
            await Future.delayed(const Duration(milliseconds: 600));
          },
        ),
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

  // ── 4-pair Theme selector ─────────────────────────────────────────────────
  // ── Open the custom colour picker ──────────────────────────────────────────
  Future<void> _openCustomPicker() async {
    final appState = _appState;
    final isCustom = appState.themeMode == AppThemeMode.customDark ||
        appState.themeMode == AppThemeMode.customLight;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CustomColourPickerScreen(
        initialColour: isCustom ? appState.customAccent : appState.accent,
        initialDark: appState.themeMode.isDark,
      )),
    );
    if (result == true && mounted) setState(() {});
  }

  Widget _themeSelector() {
    final appState = _appState;
    final isCustomActive = appState.themeMode == AppThemeMode.customDark ||
        appState.themeMode == AppThemeMode.customLight;

    final pairs = <List<AppThemeMode>>[
      [AppThemeMode.navyDark,      AppThemeMode.navyLight],
      [AppThemeMode.blackDark,     AppThemeMode.whiteDark],
      [AppThemeMode.warmDark,      AppThemeMode.warmLight],
      [AppThemeMode.tealDark,      AppThemeMode.tealLight],
      [AppThemeMode.lavenderDark,  AppThemeMode.lavenderLight],
    ];

    final previews = <AppThemeMode, List<Color>>{
      AppThemeMode.navyDark:       [const Color(0xFF080E1C), const Color(0xFF0B2447), const Color(0xFF4A90D9)],
      AppThemeMode.navyLight:      [const Color(0xFFEFF6FF), const Color(0xFF1A4A8A), const Color(0xFF4A90D9)],
      AppThemeMode.blackDark:      [const Color(0xFF000000), const Color(0xFF1A1A1A), Colors.white],
      AppThemeMode.whiteDark:      [const Color(0xFFFFFFFF), const Color(0xFFDDDDDD), Colors.black],
      AppThemeMode.warmDark:       [const Color(0xFF1A1410), const Color(0xFF3A2C20), const Color(0xFFE0CDBE)],
      AppThemeMode.warmLight:      [const Color(0xFFF5EDE4), const Color(0xFFCFBBAA), const Color(0xFFA9C0A6)],
      AppThemeMode.tealDark:       [const Color(0xFF020C12), const Color(0xFF031163), const Color(0xFF1FBFB8)],
      AppThemeMode.tealLight:      [const Color(0xFFE0F7F6), const Color(0xFF1978A5), const Color(0xFF05716C)],
      AppThemeMode.lavenderDark:   [const Color(0xFF0E0814), const Color(0xFF2E1060), const Color(0xFFA78BFA)],
      AppThemeMode.lavenderLight:  [const Color(0xFFFAF8FF), const Color(0xFFE2D9F3), const Color(0xFF7C3AED)],
    };

    final pairLabels = ['Navy & Alice Blue', 'Black & White', 'Warm Earth', 'Ocean Teal', 'Lavender & Off-White'];
    final pairIcons  = [Icons.nights_stay_rounded, Icons.contrast_rounded, Icons.eco_rounded, Icons.water_rounded, Icons.auto_awesome_rounded];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 14),
        child: Text('App Theme', style: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain)),
      ),

      // ── Custom Colour Card ─────────────────────────────────────────────────
      GestureDetector(
        onTap: _openCustomPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCustomActive ? appState.customAccent.withOpacity(0.08) : _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCustomActive
                  ? appState.customAccent.withOpacity(0.60)
                  : _border,
              width: isCustomActive ? 2 : 1.5,
            ),
            boxShadow: isCustomActive ? [BoxShadow(
              color: appState.customAccent.withOpacity(0.18),
              blurRadius: 14, offset: const Offset(0, 4),
            )] : [],
          ),
          child: Row(children: [
            // Colour preview swatch
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: isCustomActive
                      ? [appState.customAccent.withOpacity(0.7), appState.customAccent]
                      : [const Color(0xFFFF6B6B), const Color(0xFF4ECDC4), ],
                ),
              ),
              child: isCustomActive
                  ? Center(child: Icon(Icons.palette_rounded, color: Colors.white, size: 20))
                  : CustomPaint(painter: _RainbowSwatch()),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Custom Colour', style: GoogleFonts.dmSans(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: isCustomActive ? _txtMain : _txtSub)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFF4ECDC4)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('NEW', style: GoogleFonts.dmSans(
                      fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                isCustomActive
                    ? '#${appState.customAccent.value.toRadixString(16).substring(2).toUpperCase()}  •  ${appState.themeMode == AppThemeMode.customDark ? "Dark" : "Light"} variant'
                    : 'Pick any colour from the spectrum',
                style: GoogleFonts.dmSans(fontSize: 11.5, color: _txtSub, fontWeight: FontWeight.w500)),
            ])),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCustomActive ? appState.customAccent.withOpacity(0.15) : _border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tune_rounded,
                color: isCustomActive ? appState.customAccent : _txtSub, size: 18),
            ),
            if (isCustomActive) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, color: appState.customAccent, size: 18),
            ],
          ]),
        ),
      ),

      // ── Preset Pairs ──────────────────────────────────────────────────────
      ...List.generate(pairs.length, (pi) {
        final darkMode  = pairs[pi][0];
        final lightMode = pairs[pi][1];
        final isActive  = appState.themeMode == darkMode || appState.themeMode == lightMode;
        final isDarkSel = appState.themeMode == darkMode;
        final selColor  = previews[darkMode]![2];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive ? selColor.withOpacity(0.07) : _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? selColor.withOpacity(0.55) : _border,
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: isActive ? [BoxShadow(
              color: selColor.withOpacity(0.14),
              blurRadius: 14, offset: const Offset(0, 4),
            )] : [],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: selColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selColor.withOpacity(0.2)),
                  ),
                  child: Icon(pairIcons[pi], color: isActive ? selColor : _txtSub, size: 15)),
              const SizedBox(width: 10),
              Expanded(child: Text(pairLabels[pi], style: GoogleFonts.dmSans(
                  fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: isActive ? _txtMain : _txtSub))),
              if (isActive) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selColor.withOpacity(0.3)),
                ),
                child: Text('Active', style: GoogleFonts.dmSans(
                    fontSize: 10, fontWeight: FontWeight.w700, color: selColor)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _themeTile(darkMode,  previews[darkMode]!,  appState, isDark: true)),
              const SizedBox(width: 8),
              Expanded(child: _themeTile(lightMode, previews[lightMode]!, appState, isDark: false)),
            ]),
          ]),
        );
      }),
    ]);
  }

  Widget _themeTile(AppThemeMode mode, List<Color> colors, AppState appState, {required bool isDark}) {
    final sel = appState.themeMode == mode;
    final accentCol = colors[2];
    return GestureDetector(
      onTap: () async { await appState.setTheme(mode); setState(() {}); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sel ? accentCol.withOpacity(0.10) : colors[0].withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? accentCol.withOpacity(0.6) : _border,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: colors[0],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors[1].withOpacity(0.5), width: 0.5),
            ),
            child: Stack(children: [
              Positioned(left: 8, top: 10, child: Container(
                  width: 28, height: 5,
                  decoration: BoxDecoration(color: colors[1].withOpacity(0.8), borderRadius: BorderRadius.circular(3)))),
              Positioned(left: 8, top: 19, child: Container(
                  width: 18, height: 4,
                  decoration: BoxDecoration(color: colors[1].withOpacity(0.5), borderRadius: BorderRadius.circular(2)))),
              Positioned(right: 8, bottom: 8, child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: colors[2], shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: colors[2].withOpacity(0.4), blurRadius: 4)]))),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(isDark ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
                size: 11, color: sel ? accentCol : _txtSub),
            const SizedBox(width: 4),
            Expanded(child: Text(isDark ? 'Dark' : 'Light',
                style: GoogleFonts.dmSans(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? accentCol : _txtSub))),
            if (sel) Icon(Icons.check_circle_rounded, color: accentCol, size: 14),
          ]),
        ]),
      ),
    );
  }

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

  Widget _drop(String label, String val, List<String> items, ValueChanged<String?> cb) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w700, color: _txtMain))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12), border: Border.all(color: _accent.withOpacity(0.2))),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: val, isDense: true,
              icon: Icon(Icons.expand_more_rounded, color: _accent, size: 16),
              style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: _accent),
              dropdownColor: _cardBg,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: cb,
            )),
          ),
        ]),
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
      _div(),
      GestureDetector(onTap: ()=>_snack('Contact support to delete account'),
          child: _dangerRow('Delete Account', Icons.delete_forever_rounded, 'Permanently remove your data')),
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
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: _txtMain)),
    backgroundColor: _cardBg,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));

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
          await DBHelper.instance.clearSession();
          UserSession.instance.clear();
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

// ── Rainbow swatch painter for the 'not yet custom' state ─────────────────
class _RainbowSwatch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()
      ..shader = SweepGradient(colors: [
        const Color(0xFFFF0000), const Color(0xFFFF8000),
        const Color(0xFFFFFF00), const Color(0xFF00FF00),
        const Color(0xFF00FFFF), const Color(0xFF0000FF),
        const Color(0xFF8000FF), const Color(0xFFFF0080),
        const Color(0xFFFF0000),
      ]).createShader(rect));
    // White center overlay for palette look
    canvas.drawCircle(Offset(size.width / 2, size.height / 2),
      size.width * 0.3,
      Paint()..color = Colors.white.withOpacity(0.70));
  }
  @override
  bool shouldRepaint(_) => false;
}


