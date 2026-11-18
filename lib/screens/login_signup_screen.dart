import 'package:flutter/material.dart';
import '../app_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../user_session.dart';
import '../widgets/appointly_logo.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Google "G" logo
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({this.size = 22});
  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#FFC107" d="M43.6 20.1H42V20H24v8h11.3C33.7 32.7 29.3 36 24 36
    c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3l5.7-5.7
    C34 6.1 29.3 4 24 4 13 4 4 13 4 24s9 20 20 20 20-9 20-20
    c0-1.3-.1-2.7-.4-3.9z"/>
  <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12
    c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4
    16.3 4 9.7 8.3 6.3 14.7z"/>
  <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2
    C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5
    C9.5 39.6 16.2 44 24 44z"/>
  <path fill="#1976D2" d="M43.6 20.1H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6
    l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.7-.4-3.9z"/>
</svg>''';
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: SvgPicture.string(_svg, fit: BoxFit.contain),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Theme-aware background — reads AppStateProvider
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumBg extends StatelessWidget {
  final Widget child;
  const _PremiumBg({required this.child});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final grad = appState.heroGradient;
    // Blend hero gradient at lower opacity for a subtle background on light themes
    final c1 = Color.lerp(appState.bg, grad[0], appState.isDarkMode ? 0.6 : 0.25)!;
    final c2 = Color.lerp(appState.bg, grad.last, appState.isDarkMode ? 0.5 : 0.18)!;

    return Container(
      width: double.infinity, height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: [c1, Color.lerp(c1, c2, 0.5)!, c2],
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared Google Sign-In flow (Welcome + Login screens)
// ─────────────────────────────────────────────────────────────────────────────

/// True while a Google sign-in is in flight anywhere — the double-tap
/// guard (the old Welcome button could be tapped twice and start two
/// sign-ins).
bool googleSignInInFlight = false;

/// Real Google Sign-In: opens the Google account picker, exchanges
/// the ID token at POST /api/v1/auth/google/, then goes to the
/// dashboard — the same landing as email login. When Google Sign-In
/// is not configured yet (empty client ID), the service throws a
/// friendly message shown in the snackbar below.
///
/// The loading dialog has a Cancel button: on a cold Render wake-up
/// the sign-in can hang ~90s, and the old barrierDismissible:false
/// dialog with no cancel left the user stuck.
Future<void> runGoogleSignIn(BuildContext context) async {
  if (googleSignInInFlight) return;
  googleSignInInFlight = true;
  bool dialogOpen = false;
  void dismissLoading() {
    if (!dialogOpen) return;
    dialogOpen = false;
    if (context.mounted) Navigator.pop(context);
  }

  void showLoading() {
    dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                // Cancels the WAIT, not the sign-in: the request
                // keeps running in the background and still lands on
                // the dashboard if it succeeds.
                dismissLoading();
              },
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      ),
    ).then((_) => dialogOpen = false);
  }

  void showError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE05C5C),
      ),
    );
  }

  Future<Map<String, dynamic>?> attempt() async {
    try {
      return await AuthService.instance.signInWithGoogle();
    } on GoogleSignInCancelledException {
      // The user dismissed the picker — not an error, stay silent.
      return null;
    } on ApiException catch (e) {
      // Brand-new Google users need a profession (backend 400);
      // ask for it and retry once with the chosen value.
      if (_needsProfession(e.message)) {
        dismissLoading();
        final profession = await _askProfession(context);
        if (profession == null || profession.isEmpty) return null;
        if (!context.mounted) return null;
        showLoading();
        try {
          return await AuthService.instance
              .signInWithGoogle(profession: profession);
        } on GoogleSignInCancelledException {
          return null;
        } on ApiException catch (e2) {
          dismissLoading();
          showError(e2.message);
          return null;
        } catch (_) {
          dismissLoading();
          showError('Something went wrong. Please try again.');
          return null;
        }
      }
      dismissLoading();
      showError(e.message);
      return null;
    } catch (_) {
      dismissLoading();
      showError('Something went wrong. Please try again.');
      return null;
    }
  }

  try {
    showLoading();
    final user = await attempt();
    if (user == null) return;
    if (!context.mounted) return;
    dismissLoading();
    UserSession.instance.setFromMap(user);
    await AppStateProvider.of(context).loadUserData();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      _slide(const DashboardScreen()),
      (r) => false,
    );
  } finally {
    googleSignInInFlight = false;
  }
}

/// The backend rejects a brand-new Google account without a
/// profession; its error message names the missing field.
// The backend 400 for a brand-new Google user is
// {"profession": ["This field is required for new Google users."]} and
// ApiClient.errorMessage returns only the value text, so the field
// name never appears in the message — match the message wording too.
bool _needsProfession(String message) {
  final m = message.toLowerCase();
  return m.contains('profession') || m.contains('new google user');
}

/// Asks a first-time Google user for their profession (free text
/// plus suggested chips). Returns null when the user cancels.
Future<String?> _askProfession(BuildContext context) async {
  final ctrl = TextEditingController();
  const suggestions = ['Doctor', 'Therapist', 'Consultant', 'Other'];
  String? error;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('What is your profession?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Google sign-in needs a profession for new accounts.',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: suggestions.map((s) => ChoiceChip(
            label: Text(s, style: GoogleFonts.poppins(fontSize: 13)),
            selected: ctrl.text == s,
            onSelected: (_) => setDialogState(() => ctrl.text = s),
          )).toList()),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Doctor',
              errorText: error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = ctrl.text.trim();
              if (value.isEmpty) {
                setDialogState(() => error = 'Please enter or pick a profession.');
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: Text('Continue', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result;
}

/// Theme-aware error box (the old one used hardcoded light colours
/// — 0xFFFFECEC background, dark-red text — which looked wrong in
/// dark mode).
Widget _errorBox(String message, bool isDark) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE05C5C).withOpacity(isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFE05C5C), size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: isDark ? const Color(0xFFFF9D9D) : const Color(0xFFB83232),
                fontWeight: FontWeight.w500))),
      ]),
    );

PageRoute _slide(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, a, __, child) => SlideTransition(
    position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 360),
);

// ─────────────────────────────────────────────────────────────────────────────
//  WelcomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final isDark   = appState.isDarkMode;
    final txtMain  = appState.txtMain;
    final txtSub   = appState.txtSub;
    final cardBg   = appState.cardBg;
    final accent   = appState.accent;
    final border   = appState.border;

    return Scaffold(
      backgroundColor: appState.bg,
      body: _PremiumBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppointlyLogo(size: 110),
                  const SizedBox(height: 16),
                  Text('Welcome to Appointly', style: GoogleFonts.poppins(
                      fontSize: 24, fontWeight: FontWeight.bold, color: txtMain)),
                  const SizedBox(height: 6),
                  Text('Your appointments, simplified.', style: GoogleFonts.poppins(
                      fontSize: 14, color: txtSub)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text("Don't have an account? ", style: GoogleFonts.poppins(
                        fontSize: 14, color: txtSub)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, _slide(const SignupScreen())),
                      child: Text('Join here', style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.bold,
                          color: accent, decoration: TextDecoration.underline,
                          decorationColor: accent)),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  // ── Card ───────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(28.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: border),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                        blurRadius: 24, offset: const Offset(0, 12),
                      )],
                    ),
                    child: Column(children: [
                      _socialBtn(context, 'Continue with Google',
                          isGoogle: true, accent: accent, border: border, txtMain: txtMain,
                          onTap: googleSignInInFlight ? null : () => _signInWithGoogle(context)),
                      const SizedBox(height: 16),
                      _socialBtn(context, 'Continue with email',
                          icon: Icons.email_outlined, accent: accent, border: border, txtMain: txtMain,
                          onTap: () => Navigator.push(context, _slide(const LoginScreen()))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Real Google Sign-In — shared with the login screen (see
  /// [runGoogleSignIn] below). Guarded against double-taps and with
  /// a cancellable loading dialog.
  Future<void> _signInWithGoogle(BuildContext context) =>
      runGoogleSignIn(context);

  Widget _socialBtn(BuildContext ctx, String text, {
    IconData? icon, bool isGoogle = false, bool isSmall = false,
    Color? iconColor, VoidCallback? onTap,
    required Color accent, required Color border, required Color txtMain,
  }) =>
      InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isSmall ? 12 : 16),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isGoogle) const _GoogleLogo(size: 22)
            else if (icon != null) Icon(icon, size: 22, color: iconColor ?? txtMain),
            SizedBox(width: isSmall ? 8 : 12),
            Text(text, style: GoogleFonts.poppins(
                fontSize: isSmall ? 14 : 15,
                fontWeight: FontWeight.w500, color: txtMain)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LoginScreen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  /// Optional informational banner shown above the form, e.g.
  /// "Account created — please sign in" after a register-then-login
  /// race, or the session-expired notice. Not an error — it renders
  /// in the neutral info style, never the red error box.
  final String? message;
  const LoginScreen({super.key, this.message});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool   _loading  = false;
  String _error    = '';

  @override
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = ''; });
    try {
      final user = await AuthService.instance.login(
        email: _emailCtrl.text.trim(), password: _passCtrl.text,
      );
      if (!mounted) return;
      UserSession.instance.setFromMap(user);
      await AppStateProvider.of(context).loadUserData();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, _slide(const DashboardScreen()), (r) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Something went wrong. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final isDark   = appState.isDarkMode;
    final txtMain  = appState.txtMain;
    final txtSub   = appState.txtSub;
    final cardBg   = appState.cardBg;
    final accent   = appState.accent;
    final border   = appState.border;

    return Scaffold(
      backgroundColor: appState.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: txtMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _PremiumBg(child: SafeArea(child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AppointlyLogo(size: 110),
              const SizedBox(height: 12),
              Text('Welcome Back', style: GoogleFonts.poppins(
                  fontSize: 26, fontWeight: FontWeight.bold, color: txtMain)),
              const SizedBox(height: 8),
              Text('Enter your credentials to continue.', style: GoogleFonts.poppins(
                  fontSize: 14, color: txtSub)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                    blurRadius: 24, offset: const Offset(0, 12),
                  )],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _AppointlyField(label: 'Email', icon: Icons.email_outlined,
                        controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your email';
                          if (!RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(v.trim()))
                            return 'Enter a valid email address';
                          return null;
                        }),
                    const SizedBox(height: 20),
                    _AppointlyField(label: 'Password', icon: Icons.lock_outline,
                        controller: _passCtrl, isPassword: true,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter your password';
                          return null;
                        }),
                    Align(alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _showForgotPassword(context, appState),
                        child: Text('Forgot Password?', style: GoogleFonts.poppins(
                            color: accent, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    if (widget.message != null && widget.message!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: accent.withOpacity(0.35)),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline_rounded, color: accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(widget.message!, style: GoogleFonts.poppins(
                              fontSize: 12.5, color: txtMain, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_error.isNotEmpty) ...[
                      _errorBox(_error, isDark),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(width: double.infinity, height: 55,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            HSLColor.fromColor(accent).withLightness(
                                (HSLColor.fromColor(accent).lightness * 0.75).clamp(0.1, 0.55)).toColor(),
                            accent,
                          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text('LOGIN', style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Google sign-in on the login screen too — the
                    // old login screen had none, forcing users back
                    // to Welcome for Google.
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: (_loading || googleSignInInFlight)
                            ? null
                            : () => runGoogleSignIn(context),
                        icon: const _GoogleLogo(size: 20),
                        label: Text('Continue with Google',
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w500,
                                color: txtMain)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text("Don't have an account?", style: GoogleFonts.poppins(color: txtSub)),
                TextButton(
                  onPressed: () => Navigator.push(context, _slide(const SignupScreen())),
                  child: Text('Sign Up', style: GoogleFonts.poppins(
                      color: accent, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
            ]),
          ),
        ),
      ))),
    );
  }

  void _showForgotPassword(BuildContext ctx, AppState appState) {
    final ctrl = TextEditingController();
    String? error;
    bool sending = false;
    showDialog(context: ctx, barrierDismissible: false,
        builder: (_) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
      backgroundColor: appState.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: appState.border),
      ),
      title: Text('Reset Password', style: GoogleFonts.dmSans(
          fontWeight: FontWeight.w800, color: appState.txtMain)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Enter your email and we'll send you a reset link.",
            style: GoogleFonts.dmSans(fontSize: 13, color: appState.txtSub)),
        const SizedBox(height: 16),
        TextField(
          controller: ctrl, keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: appState.txtMain),
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: GoogleFonts.dmSans(color: appState.txtSub),
            errorText: error,
            filled: true, fillColor: appState.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: appState.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: appState.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: appState.accent, width: 1.5)),
            prefixIcon: Icon(Icons.email_outlined, color: appState.accent, size: 18),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: sending ? null : () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.dmSans(
                color: appState.txtSub, fontWeight: FontWeight.w600))),
        ElevatedButton(
          onPressed: sending ? null : () async {
            final email = ctrl.text.trim();
            // Inline error — never close the dialog silently.
            if (email.isEmpty) {
              setDialogState(() => error = 'Please enter your email address.');
              return;
            }
            if (!RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(email)) {
              setDialogState(() => error = 'Enter a valid email address.');
              return;
            }
            // Await the request INSIDE the dialog with a spinner —
            // the old code closed the dialog first, so the user had
            // no idea whether the request was even running.
            setDialogState(() {
              sending = true;
              error = null;
            });
            try {
              await AuthService.instance.requestPasswordReset(email);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text('Reset link sent! Check your email.',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.white)),
                backgroundColor: const Color(0xFF2ECC96), behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ));
            } on ApiException catch (e) {
              if (dialogCtx.mounted) {
                setDialogState(() {
                  sending = false;
                  error = e.message;
                });
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: appState.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: sending
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text('Send Link', style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    )));
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  SignupScreen
// ─────────────────────────────────────────────────────────────────────────────
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _profCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _confCtrl  = TextEditingController();
  bool   _loading  = false;
  String _error    = '';
  bool _hasMinLength = false, _hasUppercase = false, _hasLowercase = false, _hasNumber = false;
  bool get _pwStrong => _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _profCtrl.dispose();
    _passCtrl.dispose(); _confCtrl.dispose();
    super.dispose();
  }

  void _checkStrength(String pw) {
    final minLen = pw.length >= 8;
    final upper = pw.contains(RegExp(r'[A-Z]'));
    final lower = pw.contains(RegExp(r'[a-z]'));
    final number = pw.contains(RegExp(r'[0-9]'));
    // Only rebuild when a flag actually flips — the old version
    // rebuilt the whole signup form on every keystroke.
    if (minLen == _hasMinLength &&
        upper == _hasUppercase &&
        lower == _hasLowercase &&
        number == _hasNumber) {
      return;
    }
    setState(() {
      _hasMinLength = minLen;
      _hasUppercase = upper;
      _hasLowercase = lower;
      _hasNumber = number;
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_pwStrong) { setState(() => _error = 'Password does not meet all requirements.'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      await AuthService.instance.register(
        fullName: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(),
        password: _passCtrl.text, confirmPassword: _confCtrl.text,
        profession: _profCtrl.text.trim(),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Registration failed. Please try again.'; });
      return;
    }
    // The account now EXISTS — register returns no tokens, so log in
    // right away. If the auto-login fails (e.g. a network blip), do
    // NOT report "Registration failed": send the user to the login
    // screen instead, or retrying register would fail with "email
    // already exists".
    try {
      final user = await AuthService.instance.login(
        email: _emailCtrl.text.trim(), password: _passCtrl.text,
      );
      if (!mounted) return;
      UserSession.instance.setFromMap(user);
      await AppStateProvider.of(context).loadUserData();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, _slide(const DashboardScreen()), (r) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; });
      Navigator.pushAndRemoveUntil(
        context,
        _slide(const LoginScreen(message: 'Account created — please sign in.')),
        (r) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final isDark   = appState.isDarkMode;
    final txtMain  = appState.txtMain;
    final txtSub   = appState.txtSub;
    final cardBg   = appState.cardBg;
    final accent   = appState.accent;
    final border   = appState.border;

    return Scaffold(
      backgroundColor: appState.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: txtMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _PremiumBg(child: SafeArea(child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(children: [
              AppointlyLogo(size: 110),
              const SizedBox(height: 12),
              Text('Create Account', style: GoogleFonts.poppins(
                  fontSize: 26, fontWeight: FontWeight.bold, color: txtMain)),
              const SizedBox(height: 8),
              Text('Join Appointly to book or provide services.',
                  style: GoogleFonts.poppins(fontSize: 14, color: txtSub)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                    blurRadius: 24, offset: const Offset(0, 12),
                  )],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _AppointlyField(label: 'Full Name', icon: Icons.badge_outlined,
                        controller: _nameCtrl,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your name';
                          return null;
                        }),
                    const SizedBox(height: 16),
                    _AppointlyField(label: 'Email', icon: Icons.email_outlined,
                        controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your email';
                          if (!RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(v.trim()))
                            return 'Enter a valid email address';
                          return null;
                        }),
                    const SizedBox(height: 16),
                    _AppointlyField(label: 'Profession / Role',
                        icon: Icons.work_outline, controller: _profCtrl,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your profession';
                          return null;
                        }),
                    const SizedBox(height: 16),
                    _AppointlyField(label: 'Password', icon: Icons.lock_outline,
                        controller: _passCtrl, isPassword: true, onChanged: _checkStrength,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter a password';
                          if (!_pwStrong) return 'Password does not meet requirements';
                          return null;
                        }),
                    const SizedBox(height: 12),
                    _check('At least 8 characters',    _hasMinLength, accent, txtMain, txtSub),
                    const SizedBox(height: 4),
                    _check('At least 1 uppercase letter', _hasUppercase, accent, txtMain, txtSub),
                    const SizedBox(height: 4),
                    _check('At least 1 lowercase letter', _hasLowercase, accent, txtMain, txtSub),
                    const SizedBox(height: 4),
                    _check('At least 1 number',          _hasNumber, accent, txtMain, txtSub),
                    const SizedBox(height: 16),
                    _AppointlyField(label: 'Confirm Password', icon: Icons.lock_outline,
                        controller: _confCtrl, isPassword: true,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please confirm your password';
                          if (v != _passCtrl.text) return 'Passwords do not match';
                          return null;
                        }),
                    const SizedBox(height: 20),
                    if (_error.isNotEmpty) ...[
                      _errorBox(_error, isDark),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(width: double.infinity, height: 55,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            HSLColor.fromColor(accent).withLightness(
                                (HSLColor.fromColor(accent).lightness * 0.75).clamp(0.1, 0.55)).toColor(),
                            accent,
                          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _loading ? null : _register,
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text('CREATE ACCOUNT', style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Already have an account?', style: GoogleFonts.poppins(color: txtSub)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Log In', style: GoogleFonts.poppins(
                      color: accent, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
            ]),
          ),
        ),
      ))),
    );
  }

  Widget _check(String text, bool isMet, Color accent, Color txtMain, Color txtSub) =>
      Row(children: [
        Icon(isMet ? Icons.check_circle : Icons.check_circle_outline,
            color: isMet ? accent : txtSub, size: 18),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.poppins(
            color: isMet ? txtMain : txtSub, fontSize: 13)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable text field — fully theme-aware
// ─────────────────────────────────────────────────────────────────────────────
class _AppointlyField extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Function(String)? onChanged;
  final Color accent, txtMain, txtSub, cardBg, border;

  const _AppointlyField({
    required this.label, required this.icon,
    this.isPassword = false, this.controller,
    this.keyboardType, this.validator, this.onChanged,
    required this.accent, required this.txtMain,
    required this.txtSub, required this.cardBg, required this.border,
  });

  @override
  State<_AppointlyField> createState() => _AppointlyFieldState();
}

class _AppointlyFieldState extends State<_AppointlyField> {
  bool _obscure = true;
  @override
  void initState() { super.initState(); _obscure = widget.isPassword; }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(color: widget.txtMain, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: widget.txtSub, fontSize: 14),
        prefixIcon: Icon(widget.icon, color: widget.txtSub),
        suffixIcon: widget.isPassword
            ? IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: widget.txtSub),
            onPressed: () => setState(() => _obscure = !_obscure))
            : null,
        filled: true,
        fillColor: widget.cardBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: widget.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: widget.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: widget.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE05C5C), width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE05C5C), width: 1.5)),
        errorStyle: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFFB83232)),
      ),
    );
  }
}
