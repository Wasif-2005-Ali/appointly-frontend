import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../database/bd_helper.dart';
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
                          onTap: () => _showGoogleDialog(context, appState)),
                      const SizedBox(height: 16),
                      _socialBtn(context, 'Continue with email',
                          icon: Icons.email_outlined, accent: accent, border: border, txtMain: txtMain,
                          onTap: () => Navigator.push(context, _slide(const LoginScreen()))),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(child: Divider(color: border)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR', style: TextStyle(color: txtSub, fontSize: 12))),
                        Expanded(child: Divider(color: border)),
                      ]),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(child: _socialBtn(context, 'Apple',
                            icon: Icons.apple, isSmall: true, accent: accent, border: border, txtMain: txtMain)),
                        const SizedBox(width: 16),
                        Expanded(child: _socialBtn(context, 'Facebook',
                            icon: Icons.facebook, isSmall: true,
                            iconColor: const Color(0xFF1877F2),
                            accent: accent, border: border, txtMain: txtMain)),
                      ]),
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

  void _showGoogleDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: appState.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: appState.border),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(appState.isDarkMode ? 0.4 : 0.12),
              blurRadius: 40, offset: const Offset(0, 16),
            )],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF4285F4).withOpacity(0.18), width: 1.5),
              ),
              child: const Center(child: _GoogleLogo(size: 34)),
            ),
            const SizedBox(height: 22),
            Text('Coming Soon!', style: GoogleFonts.poppins(
                fontSize: 24, fontWeight: FontWeight.w800, color: appState.txtMain)),
            const SizedBox(height: 10),
            Text(
              'Google Sign-In will be available in an upcoming update. Stay tuned!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13.5, color: appState.txtSub, height: 1.6),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              _Dot(Color(0xFF4285F4)), SizedBox(width: 5),
              _Dot(Color(0xFF34A853)), SizedBox(width: 5),
              _Dot(Color(0xFFEA4335)), SizedBox(width: 5),
              _Dot(Color(0xFFFBBC05)),
            ]),
            const SizedBox(height: 26),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [appState.accent,
                      HSLColor.fromColor(appState.accent).withLightness(
                          (HSLColor.fromColor(appState.accent).lightness + 0.10).clamp(0.1, 0.65)).toColor()],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                    color: appState.accent.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5),
                  )],
                ),
                child: Center(child: Text('Got it',
                    style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

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

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) =>
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

// ─────────────────────────────────────────────────────────────────────────────
//  LoginScreen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
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
    final result = await DBHelper.instance.loginUser(
      email: _emailCtrl.text.trim(), password: _passCtrl.text,
    );
    if (!mounted) return;
    switch (result.result) {
      case LoginResult.success:
        UserSession.instance.setFromMap(result.userRow!);
        await DBHelper.instance.saveSession(result.userRow!['id'] as int);
        if (!mounted) return;
        await AppStateProvider.of(context).loadUserData();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, _slide(const DashboardScreen()), (r) => false);
        break;
      case LoginResult.emailNotFound:
        setState(() { _loading = false; _error = 'No account found with this email address.'; });
        break;
      case LoginResult.wrongPassword:
        setState(() { _loading = false; _error = 'Incorrect password. Please try again.'; });
        break;
      default:
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
                          if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v.trim()))
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
                    if (_error.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFE05C5C), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error, style: GoogleFonts.poppins(
                              fontSize: 12.5, color: const Color(0xFFB83232), fontWeight: FontWeight.w500))),
                        ]),
                      ),
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
    showDialog(context: ctx, builder: (_) => AlertDialog(
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
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmSans(
                color: appState.txtSub, fontWeight: FontWeight.w600))),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text('Reset link sent! Check your email.',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.white)),
              backgroundColor: const Color(0xFF2ECC96), behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: appState.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Send Link', style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    ));
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

  void _checkStrength(String pw) => setState(() {
    _hasMinLength = pw.length >= 8;
    _hasUppercase = pw.contains(RegExp(r'[A-Z]'));
    _hasLowercase = pw.contains(RegExp(r'[a-z]'));
    _hasNumber    = pw.contains(RegExp(r'[0-9]'));
  });

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_pwStrong) { setState(() => _error = 'Password does not meet all requirements.'); return; }
    setState(() { _loading = true; _error = ''; });
    final result = await DBHelper.instance.registerUser(
      fullName: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(),
      password: _passCtrl.text, profession: _profCtrl.text.trim(),
    );
    if (!mounted) return;
    switch (result) {
      case RegisterResult.success:
        final login = await DBHelper.instance.loginUser(
          email: _emailCtrl.text.trim(), password: _passCtrl.text,
        );
        if (!mounted) return;
        if (login.result == LoginResult.success) {
          UserSession.instance.setFromMap(login.userRow!);
          await DBHelper.instance.saveSession(login.userRow!['id'] as int);
          if (!mounted) return;
          await AppStateProvider.of(context).loadUserData();
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(context, _slide(const DashboardScreen()), (r) => false);
        } else {
          setState(() { _loading = false; _error = 'Account created! Please log in.'; });
        }
        break;
      case RegisterResult.emailAlreadyExists:
        setState(() { _loading = false; _error = 'An account with this email already exists.'; });
        break;
      default:
        setState(() { _loading = false; _error = 'Registration failed. Please try again.'; });
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
                          if (v == null || v.trim().isEmpty) return 'Please enter your full name';
                          if (v.trim().split(' ').length < 2) return 'Enter first and last name';
                          return null;
                        }),
                    const SizedBox(height: 16),
                    _AppointlyField(label: 'Email', icon: Icons.email_outlined,
                        controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                        accent: accent, txtMain: txtMain, txtSub: txtSub, cardBg: cardBg, border: border,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your email';
                          if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v.trim()))
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFE05C5C), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error, style: GoogleFonts.poppins(
                              fontSize: 12.5, color: const Color(0xFFB83232), fontWeight: FontWeight.w500))),
                        ]),
                      ),
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

// kept for any SVG-based references in this file
class _GlowLogo extends StatelessWidget {
  final double size;
  const _GlowLogo({required this.size});
  @override
  Widget build(BuildContext context) {
    final accent = AppStateProvider.of(context).accent;
    return Stack(alignment: Alignment.center, children: [
      Container(width: size * 1.15, height: size * 1.15,
          decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                accent.withOpacity(0.22), accent.withOpacity(0.08), Colors.transparent,
              ], stops: const [0.0, 0.5, 1.0]))),
      Container(width: size, height: size,
          decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [accent, HSLColor.fromColor(accent).withLightness(0.18).toColor()]),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.40), blurRadius: size * 0.45, offset: Offset(0, size * 0.06)),
              ]),
          child: Padding(padding: EdgeInsets.all(size * 0.040),
              child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  child: Padding(padding: EdgeInsets.all(size * 0.11),
                      child: SvgPicture.asset('assets/logo.svg', fit: BoxFit.contain))))),
    ]);
  }
}
