import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'screens/call_screen.dart';
import 'screens/splash_screen.dart';
import 'services/call_service.dart';

/// Global navigator key, so the incoming-call handler in
/// [_AppointlyRootState] can show the incoming-call dialog from
/// anywhere in the app.
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Do NOT await DB here — let runApp fire immediately so the Flutter
  // engine can paint the splash background before any heavy work.
  // DB is initialised inside SplashScreen.initState() during the animation.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  runApp(const AppointlyRoot());
}

/// Smooth bouncing scroll on all platforms
class _SmoothScrollBehavior extends MaterialScrollBehavior {
  const _SmoothScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class AppointlyRoot extends StatefulWidget {
  const AppointlyRoot({super.key});
  @override
  State<AppointlyRoot> createState() => _AppointlyRootState();
}

class _AppointlyRootState extends State<AppointlyRoot> {
  final AppState _appState = AppState();
  StreamSubscription<IncomingCall>? _incomingSub;
  StreamSubscription<String>? _notifyErrorSub;
  bool _incomingDialogOpen = false;
  // Last theme-relevant values, so AppState notifications that only
  // change data (appointments, chat badges, ...) do NOT rebuild the
  // whole MaterialApp — only a real theme change does.
  AppThemeMode? _lastThemeMode;
  Color? _lastBg;
  Color? _lastAccent;

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onAppStateChanged);
    // NOTE: appointments are loaded by the splash screen's
    // loadUserData() — do not fetch them here too (duplicate request
    // on every launch).
    // Show the incoming-call dialog whenever the server pushes one.
    _incomingSub = CallService.instance.incomingCalls.listen(
      _onIncomingCall,
    );
    // Surface notify-socket failures (incoming calls paused) instead
    // of letting them fail silently.
    _notifyErrorSub = CallService.instance.notifyErrors.listen(
      _onNotifyError,
    );
  }

  /// Only rebuild the app shell when something theme-related changed.
  /// Data-only notifications (appointments, unread badges, ...) are
  /// consumed by the screens themselves via AppStateProvider.
  void _onAppStateChanged() {
    if (_lastThemeMode != _appState.themeMode ||
        _lastBg != _appState.bg ||
        _lastAccent != _appState.accent) {
      _lastThemeMode = _appState.themeMode;
      _lastBg = _appState.bg;
      _lastAccent = _appState.accent;
      setState(() {});
    }
  }

  /// The notify socket (incoming calls) failed. Show it once with a
  /// retry action instead of silently missing calls. Auth failures
  /// need a fresh login, so they get no retry button.
  void _onNotifyError(String message) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || !mounted) return;
    final authFailed = CallService.instance.notifyAuthFailed;
    ScaffoldMessenger.of(navigator.context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: authFailed
            ? null
            : SnackBarAction(
                label: 'Retry',
                onPressed: () => CallService.instance.reconnectNotify(),
              ),
      ),
    );
  }

  /// An incoming call arrived on the notify socket. Shows the
  /// accept/decline dialog (unless one is already open or a call is
  /// already in progress), then acts on the answer.
  Future<void> _onIncomingCall(IncomingCall incoming) async {
    if (_incomingDialogOpen) return;
    if (CallService.instance.hasActiveCall) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    _incomingDialogOpen = true;
    final accepted = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => IncomingCallDialog(incoming: incoming),
    );
    _incomingDialogOpen = false;
    if (accepted == true) {
      final result = await navigator.push<String?>(
        MaterialPageRoute(
          builder: (_) => CallScreen.incoming(incoming: incoming),
        ),
      );
      if (result != null && result.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result)));
      }
    } else if (accepted == false) {
      await CallService.instance.declineCall(incoming);
    }
    // null = the dialog timed out (30s) or was dismissed: the
    // caller's ring timeout ends the session server-side, so there
    // is nothing to do here.
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _notifyErrorSub?.cancel();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _appState.themeMode;
    final isDark = t.isDark;

    Color scaffoldBg;
    Color seedColor;
    switch (t) {
      case AppThemeMode.navyDark:
        scaffoldBg = const Color(0xFF080E1C); seedColor = const Color(0xFF0B2447); break;
      case AppThemeMode.navyLight:
        scaffoldBg = const Color(0xFFEFF6FF); seedColor = const Color(0xFF0B2447); break;
      case AppThemeMode.blackDark:
        scaffoldBg = const Color(0xFF000000); seedColor = const Color(0xFF111111); break;
      case AppThemeMode.whiteDark:
        scaffoldBg = const Color(0xFFFFFFFF); seedColor = const Color(0xFF222222); break;
      case AppThemeMode.warmDark:
        scaffoldBg = const Color(0xFF1A1410); seedColor = const Color(0xFF3A2C20); break;
      case AppThemeMode.warmLight:
        scaffoldBg = const Color(0xFFF5EDE4); seedColor = const Color(0xFF6B8F72); break;
      case AppThemeMode.tealDark:
        scaffoldBg = const Color(0xFF020C12); seedColor = const Color(0xFF05716C); break;
      case AppThemeMode.tealLight:
        scaffoldBg = const Color(0xFFE0F7F6); seedColor = const Color(0xFF031163); break;
      case AppThemeMode.lavenderDark:
        scaffoldBg = const Color(0xFF0E0814); seedColor = const Color(0xFF7C3AED); break;
      case AppThemeMode.lavenderLight:
        scaffoldBg = const Color(0xFFFAF8FF); seedColor = const Color(0xFF5B21B6); break;
      case AppThemeMode.customDark:
      case AppThemeMode.customLight:
        scaffoldBg = _appState.bg; seedColor = _appState.accent; break;
    }

    return AppStateProvider(
      state: _appState,
      child: MaterialApp(
        title: 'Appointly',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        scrollBehavior: const _SmoothScrollBehavior(),
        theme: ThemeData(
          scaffoldBackgroundColor: scaffoldBg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: seedColor,
            primary: seedColor,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
          useMaterial3: true,
          drawerTheme: DrawerThemeData(backgroundColor: _appState.cardBg),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
