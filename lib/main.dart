import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'screens/splash_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _appState.addListener(() => setState(() {}));
    // Load all appointments from SQLite into AppState
    _appState.loadAppointments();
  }

  @override
  void dispose() {
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
