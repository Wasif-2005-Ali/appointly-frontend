import 'dart:convert';
import 'package:flutter/material.dart';
import 'user_session.dart';
import 'database/bd_helper.dart';
import 'models/appointment.dart';
import 'models/personal_task.dart';

/// Available app themes — 5 preset pairs + 1 fully-custom slot
enum AppThemeMode {
  // Pair 1 — Navy Blue + Alice Blue
  navyDark,
  navyLight,
  // Pair 2 — Black & White
  blackDark,
  whiteDark,
  // Pair 3 — Warm Earth
  warmDark,
  warmLight,
  // Pair 4 — Ocean Teal
  tealDark,
  tealLight,
  // Pair 5 — Lavender & Off-White
  lavenderDark,
  lavenderLight,
  // Pair 6 — Fully Custom (accent derived)
  customDark,
  customLight,
}

extension AppThemeModeExt on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.navyDark:       return 'Navy Dark';
      case AppThemeMode.navyLight:      return 'Alice Blue';
      case AppThemeMode.blackDark:      return 'Black';
      case AppThemeMode.whiteDark:      return 'White';
      case AppThemeMode.warmDark:       return 'Warm Dark';
      case AppThemeMode.warmLight:      return 'Warm Light';
      case AppThemeMode.tealDark:       return 'Ocean Dark';
      case AppThemeMode.tealLight:      return 'Ocean Light';
      case AppThemeMode.lavenderDark:   return 'Lavender Dark';
      case AppThemeMode.lavenderLight:  return 'Off-White';
      case AppThemeMode.customDark:     return 'Custom Dark';
      case AppThemeMode.customLight:    return 'Custom Light';
    }
  }

  String get pairLabel {
    switch (this) {
      case AppThemeMode.navyDark:
      case AppThemeMode.navyLight:      return 'Navy & Alice Blue';
      case AppThemeMode.blackDark:
      case AppThemeMode.whiteDark:      return 'Black & White';
      case AppThemeMode.warmDark:
      case AppThemeMode.warmLight:      return 'Warm Earth';
      case AppThemeMode.tealDark:
      case AppThemeMode.tealLight:      return 'Ocean Teal';
      case AppThemeMode.lavenderDark:
      case AppThemeMode.lavenderLight:  return 'Lavender & Off-White';
      case AppThemeMode.customDark:
      case AppThemeMode.customLight:    return 'My Custom Colour';
    }
  }

  String get description {
    switch (this) {
      case AppThemeMode.navyDark:      return 'Deep navy with blue accents';
      case AppThemeMode.navyLight:     return 'Clean light with ocean tones';
      case AppThemeMode.blackDark:     return 'Pure black, crisp & minimal';
      case AppThemeMode.whiteDark:     return 'Pure white, clean & minimal';
      case AppThemeMode.warmDark:      return 'Deep charcoal with warm earth tones';
      case AppThemeMode.warmLight:     return 'Soft beige & sage green';
      case AppThemeMode.tealDark:      return 'Deep navy with ocean teal accents';
      case AppThemeMode.tealLight:     return 'Bright cyan & teal palette';
      case AppThemeMode.lavenderDark:  return 'Deep plum with dreamy lavender';
      case AppThemeMode.lavenderLight: return 'Airy off-white with lavender blush';
      case AppThemeMode.customDark:    return 'Your colour, dark base';
      case AppThemeMode.customLight:   return 'Your colour, light base';
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeMode.navyDark:      return Icons.nights_stay_rounded;
      case AppThemeMode.navyLight:     return Icons.wb_sunny_rounded;
      case AppThemeMode.blackDark:     return Icons.dark_mode_rounded;
      case AppThemeMode.whiteDark:     return Icons.light_mode_rounded;
      case AppThemeMode.warmDark:      return Icons.grain_rounded;
      case AppThemeMode.warmLight:     return Icons.eco_rounded;
      case AppThemeMode.tealDark:      return Icons.water_rounded;
      case AppThemeMode.tealLight:     return Icons.waves_rounded;
      case AppThemeMode.lavenderDark:  return Icons.auto_awesome_rounded;
      case AppThemeMode.lavenderLight: return Icons.spa_rounded;
      case AppThemeMode.customDark:    return Icons.palette_rounded;
      case AppThemeMode.customLight:   return Icons.palette_outlined;
    }
  }

  bool get isDark =>
      this == AppThemeMode.navyDark     ||
          this == AppThemeMode.blackDark    ||
          this == AppThemeMode.warmDark     ||
          this == AppThemeMode.tealDark     ||
          this == AppThemeMode.lavenderDark ||
          this == AppThemeMode.customDark;
}

// ─────────────────────────────────────────────────────────────────────────────
//  COLOUR GENERATION ALGORITHM
//  Derives a full 8-colour semantic palette from a single accent colour.
//  Works for any hue; handles desaturated (grey) inputs gracefully.
// ─────────────────────────────────────────────────────────────────────────────
Color _setHSL(Color base, {double? l, double? s}) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withLightness((l ?? hsl.lightness).clamp(0.0, 1.0))
      .withSaturation((s ?? hsl.saturation).clamp(0.0, 1.0))
      .toColor();
}

/// Accent that is vibrant enough to read on dark backgrounds.
Color _vibrantDark(Color c) {
  final hsl = HSLColor.fromColor(c);
  final s = hsl.saturation < 0.4 ? 0.65 : hsl.saturation;
  final l = hsl.lightness.clamp(0.52, 0.72);
  return hsl.withSaturation(s).withLightness(l).toColor();
}

/// Accent that has enough contrast on white backgrounds.
Color _vibrantLight(Color c) {
  final hsl = HSLColor.fromColor(c);
  final s = hsl.saturation < 0.35 ? 0.60 : hsl.saturation;
  final l = hsl.lightness.clamp(0.30, 0.50);
  return hsl.withSaturation(s).withLightness(l).toColor();
}

// ─────────────────────────────────────────────────────────────────────────────
//  APP STATE
// ─────────────────────────────────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.navyLight;

  /// The user-chosen accent colour for the custom theme slots.
  Color _customAccent = const Color(0xFF4A90D9);
  Color get customAccent => _customAccent;

  // ── Compact / Accessibility ───────────────────────────────────────────────
  bool _compactView = false;
  bool get compactView => _compactView;
  void setCompactView(bool value) {
    if (_compactView == value) return;
    _compactView = value;
    notifyListeners();
  }

  bool _showAccessibilityButton = true;
  bool get showAccessibilityButton => _showAccessibilityButton;
  void setShowAccessibilityButton(bool value) {
    if (_showAccessibilityButton == value) return;
    _showAccessibilityButton = value;
    notifyListeners();
  }

  AppThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode.isDark;

  void setDarkMode(bool value) {} // legacy shim

  Future<void> setTheme(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persistTheme();
  }

  /// Apply a fully-custom accent colour and activate the custom slot.
  Future<void> setCustomTheme(Color accent, {required bool dark}) async {
    _customAccent = accent;
    _themeMode = dark ? AppThemeMode.customDark : AppThemeMode.customLight;
    notifyListeners();
    await _persistTheme();
  }

  Future<void> _persistTheme() async {
    final uid = UserSession.instance.userId;
    if (uid == null) return;
    String encoded;
    if (_themeMode == AppThemeMode.customDark || _themeMode == AppThemeMode.customLight) {
      final hex = _customAccent.value.toRadixString(16).padLeft(8, '0').toUpperCase();
      encoded = '${_themeMode.name}_$hex';
    } else {
      encoded = _themeMode.name;
    }
    await DBHelper.instance.updateUserProfile(uid, themeMode: encoded);
    UserSession.instance.themeMode = encoded;
  }

  // ── Semantic colour getters ───────────────────────────────────────────────

  Color get bg {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return const Color(0xFF080E1C);
      case AppThemeMode.navyLight:        return const Color(0xFFEFF6FF);
      case AppThemeMode.blackDark:        return const Color(0xFF000000);
      case AppThemeMode.whiteDark:        return const Color(0xFFFFFFFF);
      case AppThemeMode.warmDark:         return const Color(0xFF1A1410);
      case AppThemeMode.warmLight:        return const Color(0xFFF5EDE4);
      case AppThemeMode.tealDark:         return const Color(0xFF020C12);
      case AppThemeMode.tealLight:        return const Color(0xFFE0F7F6);
      case AppThemeMode.lavenderDark:     return const Color(0xFF0E0814);
      case AppThemeMode.lavenderLight:    return const Color(0xFFFAF8FF);
      case AppThemeMode.customDark:       return _setHSL(_customAccent, l: 0.06, s: 0.20);
      case AppThemeMode.customLight:      return _setHSL(_customAccent, l: 0.97, s: 0.08);
    }
  }

  Color get cardBg {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return const Color(0xFF0F1828);
      case AppThemeMode.navyLight:        return Colors.white;
      case AppThemeMode.blackDark:        return const Color(0xFF0D0D0D);
      case AppThemeMode.whiteDark:        return const Color(0xFFF2F2F2);
      case AppThemeMode.warmDark:         return const Color(0xFF231C15);
      case AppThemeMode.warmLight:        return const Color(0xFFEEE0D3);
      case AppThemeMode.tealDark:         return const Color(0xFF071420);
      case AppThemeMode.tealLight:        return const Color(0xFFCDF0EE);
      case AppThemeMode.lavenderDark:     return const Color(0xFF1A1126);
      case AppThemeMode.lavenderLight:    return Colors.white;
      case AppThemeMode.customDark:       return _setHSL(_customAccent, l: 0.11, s: 0.22);
      case AppThemeMode.customLight:      return Colors.white;
    }
  }

  Color get border {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return const Color(0xFF1A2D4A);
      case AppThemeMode.navyLight:        return const Color(0xFFD0E5FF);
      case AppThemeMode.blackDark:        return const Color(0xFF2A2A2A);
      case AppThemeMode.whiteDark:        return const Color(0xFFDDDDDD);
      case AppThemeMode.warmDark:         return const Color(0xFF3A2C20);
      case AppThemeMode.warmLight:        return const Color(0xFFCFBBAA);
      case AppThemeMode.tealDark:         return const Color(0xFF0A2232);
      case AppThemeMode.tealLight:        return const Color(0xFF7FDAD6);
      case AppThemeMode.lavenderDark:     return const Color(0xFF2E1F42);
      case AppThemeMode.lavenderLight:    return const Color(0xFFE2D9F3);
      case AppThemeMode.customDark:       return _setHSL(_customAccent, l: 0.20, s: 0.28);
      case AppThemeMode.customLight:      return _setHSL(_customAccent, l: 0.86, s: 0.22);
    }
  }

  Color get txtMain {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return Colors.white;
      case AppThemeMode.navyLight:        return const Color(0xFF0B2447);
      case AppThemeMode.blackDark:        return Colors.white;
      case AppThemeMode.whiteDark:        return Colors.black;
      case AppThemeMode.warmDark:         return const Color(0xFFF0E8E0);
      case AppThemeMode.warmLight:        return const Color(0xFF2E1E10);
      case AppThemeMode.tealDark:         return Colors.white;
      case AppThemeMode.tealLight:        return const Color(0xFF031163);
      case AppThemeMode.lavenderDark:     return const Color(0xFFF0ECFF);
      case AppThemeMode.lavenderLight:    return const Color(0xFF2A1A4A);
      case AppThemeMode.customDark:       return Colors.white;
      case AppThemeMode.customLight:      return _setHSL(_customAccent, l: 0.10, s: 0.38);
    }
  }

  Color get txtSub {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return const Color(0xFF6080A8);
      case AppThemeMode.navyLight:        return const Color(0xFF7A96BE);
      case AppThemeMode.blackDark:        return const Color(0xFF888888);
      case AppThemeMode.whiteDark:        return const Color(0xFF666666);
      case AppThemeMode.warmDark:         return const Color(0xFF9A8070);
      case AppThemeMode.warmLight:        return const Color(0xFF7A6050);
      case AppThemeMode.tealDark:         return const Color(0xFF4A8895);
      case AppThemeMode.tealLight:        return const Color(0xFF05716C);
      case AppThemeMode.lavenderDark:     return const Color(0xFF8878AA);
      case AppThemeMode.lavenderLight:    return const Color(0xFF9E8EC0);
      case AppThemeMode.customDark:       return _vibrantDark(_customAccent).withOpacity(0.55);
      case AppThemeMode.customLight:      return _setHSL(_customAccent, l: 0.40, s: 0.32);
    }
  }

  Color get accent {
    switch (_themeMode) {
      case AppThemeMode.navyDark:         return const Color(0xFF4A90D9);
      case AppThemeMode.navyLight:        return const Color(0xFF4A90D9);
      case AppThemeMode.blackDark:        return Colors.white;
      case AppThemeMode.whiteDark:        return Colors.black;
      case AppThemeMode.warmDark:         return const Color(0xFFE0CDBE);
      case AppThemeMode.warmLight:        return const Color(0xFF6B8F72);
      case AppThemeMode.tealDark:         return const Color(0xFF1FBFB8);
      case AppThemeMode.tealLight:        return const Color(0xFF05716C);
      case AppThemeMode.lavenderDark:     return const Color(0xFFA78BFA);
      case AppThemeMode.lavenderLight:    return const Color(0xFF7C3AED);
      case AppThemeMode.customDark: {
        final hsl = HSLColor.fromColor(_customAccent);
        return hsl.withLightness(hsl.lightness.clamp(0.52, 0.72)).toColor();
      }
      case AppThemeMode.customLight: {
        final hsl = HSLColor.fromColor(_customAccent);
        return hsl.withLightness(hsl.lightness.clamp(0.32, 0.52)).toColor();
      }
    }
  }

  List<Color> get heroGradient {
    switch (_themeMode) {
      case AppThemeMode.navyDark:
        return [const Color(0xFF050E22), const Color(0xFF0B2447), const Color(0xFF0F3060), const Color(0xFF163870)];
      case AppThemeMode.navyLight:
        return [const Color(0xFF0B2447), const Color(0xFF1A4A8A), const Color(0xFF2060B0), const Color(0xFF2A6AB5)];
      case AppThemeMode.blackDark:
        return [const Color(0xFF000000), const Color(0xFF090909), const Color(0xFF111111), const Color(0xFF181818)];
      case AppThemeMode.whiteDark:
        return [const Color(0xFF111111), const Color(0xFF1C1C1C), const Color(0xFF262626), const Color(0xFF303030)];
      case AppThemeMode.warmDark:
        return [const Color(0xFF0E0A07), const Color(0xFF1A1410), const Color(0xFF261C14), const Color(0xFF32241A)];
      case AppThemeMode.warmLight:
        return [const Color(0xFF4A3025), const Color(0xFF604030), const Color(0xFF725040), const Color(0xFF856050)];
      case AppThemeMode.tealDark:
        return [const Color(0xFF010810), const Color(0xFF031163), const Color(0xFF05716C), const Color(0xFF1978A5)];
      case AppThemeMode.tealLight:
        return [const Color(0xFF05716C), const Color(0xFF1978A5), const Color(0xFF1FBFB8), const Color(0xFF3DD6CF)];
      case AppThemeMode.lavenderDark:
        return [const Color(0xFF070310), const Color(0xFF18093A), const Color(0xFF2E1060), const Color(0xFF4A1A8A)];
      case AppThemeMode.lavenderLight:
        return [const Color(0xFF3B0F8C), const Color(0xFF5E22C0), const Color(0xFF7C3AED), const Color(0xFF9B59E8)];
      case AppThemeMode.customDark:
        return [
          _setHSL(_customAccent, l: 0.04, s: 0.18),
          _setHSL(_customAccent, l: 0.10, s: 0.50),
          _setHSL(_customAccent, l: 0.18, s: 0.65),
          _setHSL(_customAccent, l: 0.26, s: 0.72),
        ];
      case AppThemeMode.customLight:
        return [
          _setHSL(_customAccent, l: 0.22, s: 0.65),
          _setHSL(_customAccent, l: 0.32, s: 0.70),
          _setHSL(_customAccent, l: 0.42, s: 0.72),
          _setHSL(_customAccent, l: 0.52, s: 0.68),
        ];
    }
  }

  // ── Drawer colours ────────────────────────────────────────────────────────
  Color get drawerMenuFg {
    switch (_themeMode) {
      case AppThemeMode.navyDark:      return Colors.white;
      case AppThemeMode.navyLight:     return const Color(0xFF0B2447);
      case AppThemeMode.blackDark:     return Colors.white;
      case AppThemeMode.whiteDark:     return Colors.black;
      case AppThemeMode.warmDark:      return const Color(0xFFF0E8E0);
      case AppThemeMode.warmLight:     return const Color(0xFF2E1E10);
      case AppThemeMode.tealDark:      return Colors.white;
      case AppThemeMode.tealLight:     return const Color(0xFF031163);
      case AppThemeMode.lavenderDark:  return const Color(0xFFF0ECFF);
      case AppThemeMode.lavenderLight: return const Color(0xFF2A1A4A);
      case AppThemeMode.customDark:    return Colors.white;
      case AppThemeMode.customLight:   return _setHSL(_customAccent, l: 0.10, s: 0.38);
    }
  }

  Color get drawerMenuFgSub => drawerMenuFg.withOpacity(_themeMode.isDark ? 0.55 : 0.62);
  Color get drawerSectionLabel => drawerMenuFg.withOpacity(_themeMode.isDark ? 0.32 : 0.42);
  Color get drawerActiveItemBg => drawerMenuFg.withOpacity(_themeMode.isDark ? 0.11 : 0.08);
  Color get drawerDividerColor => drawerMenuFg.withOpacity(_themeMode.isDark ? 0.07 : 0.10);

  // ── Button gradient ────────────────────────────────────────────────────────
  List<Color> get btnGradient {
    switch (_themeMode) {
      case AppThemeMode.navyDark:
        return [const Color(0xFF0B2447), const Color(0xFF1A4A8A)];
      case AppThemeMode.navyLight:
        return [const Color(0xFF0B2447), const Color(0xFF1A4A8A)];
      case AppThemeMode.blackDark:
        return [const Color(0xFF111111), const Color(0xFF2E2E2E)];
      case AppThemeMode.whiteDark:
        return [const Color(0xFF222222), const Color(0xFF444444)];
      case AppThemeMode.warmDark:
        return [const Color(0xFF3A2C20), const Color(0xFF5A4030)];
      case AppThemeMode.warmLight:
        return [const Color(0xFF5A4030), const Color(0xFF785545)];
      case AppThemeMode.tealDark:
        return [const Color(0xFF031163), const Color(0xFF05716C)];
      case AppThemeMode.tealLight:
        return [const Color(0xFF031163), const Color(0xFF1978A5)];
      case AppThemeMode.lavenderDark:
        return [const Color(0xFF4A1A8A), const Color(0xFF7C3AED)];
      case AppThemeMode.lavenderLight:
        return [const Color(0xFF5B21B6), const Color(0xFF7C3AED)];
      case AppThemeMode.customDark:
        return [_setHSL(_customAccent, l: 0.14, s: 0.55), _setHSL(_customAccent, l: 0.26, s: 0.70)];
      case AppThemeMode.customLight:
        return [_setHSL(_customAccent, l: 0.24, s: 0.65), _setHSL(_customAccent, l: 0.38, s: 0.72)];
    }
  }

  Color get btnShadow {
    switch (_themeMode) {
      case AppThemeMode.navyDark:
      case AppThemeMode.navyLight:      return const Color(0xFF0B2447);
      case AppThemeMode.blackDark:      return const Color(0xFF111111);
      case AppThemeMode.whiteDark:      return const Color(0xFF222222);
      case AppThemeMode.warmDark:
      case AppThemeMode.warmLight:      return const Color(0xFF3A2C20);
      case AppThemeMode.tealDark:
      case AppThemeMode.tealLight:      return const Color(0xFF031163);
      case AppThemeMode.lavenderDark:
      case AppThemeMode.lavenderLight:  return const Color(0xFF4A1A8A);
      case AppThemeMode.customDark:
      case AppThemeMode.customLight:    return _setHSL(_customAccent, l: 0.10, s: 0.30);
    }
  }

  List<Color> cardGradient(int index) {
    final sets = <AppThemeMode, List<List<Color>>>{
      AppThemeMode.navyDark: [
        [const Color(0xFF0B2447), const Color(0xFF1A4A8A)],
        [const Color(0xFF0D3060), const Color(0xFF2A6AB5)],
        [const Color(0xFF163870), const Color(0xFF4A90D9)],
      ],
      AppThemeMode.navyLight: [
        [const Color(0xFF0B2447), const Color(0xFF1A4A8A)],
        [const Color(0xFF0D3060), const Color(0xFF2A6AB5)],
        [const Color(0xFF163870), const Color(0xFF4A90D9)],
      ],
      AppThemeMode.blackDark: [
        [const Color(0xFF0A0A0A), const Color(0xFF1E1E1E)],
        [const Color(0xFF111111), const Color(0xFF2A2A2A)],
        [const Color(0xFF181818), const Color(0xFF353535)],
      ],
      AppThemeMode.whiteDark: [
        [const Color(0xFF111111), const Color(0xFF2A2A2A)],
        [const Color(0xFF1A1A1A), const Color(0xFF333333)],
        [const Color(0xFF222222), const Color(0xFF3C3C3C)],
      ],
      AppThemeMode.warmDark: [
        [const Color(0xFF261C14), const Color(0xFF42301E)],
        [const Color(0xFF2E2018), const Color(0xFF503824)],
        [const Color(0xFF36261E), const Color(0xFF5E422C)],
      ],
      AppThemeMode.warmLight: [
        [const Color(0xFF5A3D28), const Color(0xFF7A5540)],
        [const Color(0xFF4A3020), const Color(0xFF6B8F72)],
        [const Color(0xFF3E2A18), const Color(0xFF5A7A60)],
      ],
      AppThemeMode.tealDark: [
        [const Color(0xFF031163), const Color(0xFF05716C)],
        [const Color(0xFF041A72), const Color(0xFF1978A5)],
        [const Color(0xFF053072), const Color(0xFF1FBFB8)],
      ],
      AppThemeMode.tealLight: [
        [const Color(0xFF1FBFB8), const Color(0xFF1978A5)],
        [const Color(0xFF05716C), const Color(0xFF031163)],
        [const Color(0xFF1978A5), const Color(0xFF1FBFB8)],
      ],
      AppThemeMode.lavenderDark: [
        [const Color(0xFF1A0938), const Color(0xFF3D1478)],
        [const Color(0xFF240C4A), const Color(0xFF5B21B6)],
        [const Color(0xFF2E1060), const Color(0xFF7C3AED)],
      ],
      AppThemeMode.lavenderLight: [
        [const Color(0xFF5B21B6), const Color(0xFF7C3AED)],
        [const Color(0xFF4A1A8A), const Color(0xFF6D28D9)],
        [const Color(0xFF6D28D9), const Color(0xFF9B59E8)],
      ],
    };
    if (_themeMode == AppThemeMode.customDark || _themeMode == AppThemeMode.customLight) {
      final a = _vibrantDark(_customAccent);
      final b = _vibrantLight(_customAccent);
      final combos = [
        [_setHSL(a, l: 0.14), _setHSL(a, l: 0.28)],
        [_setHSL(a, l: 0.18), _setHSL(b, l: 0.38)],
        [_setHSL(a, l: 0.22), _setHSL(a, l: 0.44)],
      ];
      return combos[index % combos.length];
    }
    final list = sets[_themeMode]!;
    return list[index % list.length];
  }

  // ── Availability ──────────────────────────────────────────────────────────
  Map<String, bool> _availDays = {
    'Mon': true, 'Tue': true, 'Wed': true, 'Thu': true, 'Fri': true,
    'Sat': false, 'Sun': false,
  };
  // Each entry = list of [startTime, endTime] slot ranges as strings
  Map<String, List<List<String>>> _availSlots = {
    'Mon': [['9:00 AM', '1:00 PM'], ['2:00 PM', '6:00 PM']],
    'Tue': [['9:00 AM', '1:00 PM'], ['2:00 PM', '6:00 PM']],
    'Wed': [['10:00 AM', '3:00 PM']],
    'Thu': [['9:00 AM', '1:00 PM'], ['2:00 PM', '5:00 PM']],
    'Fri': [['9:00 AM', '12:00 PM']],
    'Sat': [],
    'Sun': [],
  };
  int _maxPerDay     = 8;
  int _bufferMinutes = 15;

  Map<String, bool> get availabilityDays    => Map.unmodifiable(_availDays);
  Map<String, List<List<String>>> get availabilitySlots => Map.unmodifiable(_availSlots);
  int get maxPerDay      => _maxPerDay;
  int get bufferMinutes  => _bufferMinutes;

  Future<void> updateAvailability({
    required Map<String, bool> days,
    required Map<String, List<List<String>>> slots,
    int maxPerDay     = 8,
    int bufferMinutes = 15,
  }) async {
    _availDays = Map.from(days);
    _availSlots = {};
    slots.forEach((k, v) =>
    _availSlots[k] = v.map((s) => List<String>.from(s)).toList());
    _maxPerDay     = maxPerDay;
    _bufferMinutes = bufferMinutes;
    // Persist to DB
    final userId = UserSession.instance.userId;
    if (userId != null) {
      await DBHelper.instance.saveAvailability(userId, _availDays, _availSlots);
    }
    notifyListeners();
  }

  // ── Appointments ──────────────────────────────────────────────────────────
  List<Appointment> _appointments = [];
  List<Appointment> get appointments => List.unmodifiable(_appointments);

  Future<void> loadUserData() async {
    final userId = UserSession.instance.userId;
    if (userId == null) return;
    final savedTheme = UserSession.instance.themeMode;
    _applyEncodedTheme(savedTheme);
    _appointments = await DBHelper.instance.getAllAppointments(userId);
    // Load persisted availability
    final avail = await DBHelper.instance.loadAvailability(userId);
    if (avail != null) {
      try {
        final dMap = jsonDecode(avail['days']!) as Map<String, dynamic>;
        dMap.forEach((k, v) { if (_availDays.containsKey(k)) _availDays[k] = v as bool; });
        final sMap = jsonDecode(avail['slots']!) as Map<String, dynamic>;
        sMap.forEach((k, v) {
          _availSlots[k] = (v as List).map<List<String>>((r) =>
              (r as List).map<String>((e) => e.toString()).toList()).toList();
        });
      } catch (_) { /* keep defaults if parse fails */ }
    }
    await autoCompleteExpired();
    notifyListeners();
  }

  /// Marks all expired confirmed/pending appointments as [ApptStatus.completed].
  Future<void> autoCompleteExpired() async {
    bool changed = false;
    for (final a in _appointments) {
      if (a.status == ApptStatus.completed) continue;
      if (a.status == ApptStatus.cancelled) continue;
      if (!a.isExpired) continue;
      await DBHelper.instance.updateAppointmentStatus(a.id!, ApptStatus.completed);
      a.status = ApptStatus.completed;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> loadAppointments() async {
    final userId = UserSession.instance.userId;
    if (userId == null) return;
    _appointments = await DBHelper.instance.getAllAppointments(userId);
    // ── Heal any existing conflicts in DB ──────────────────────────────
    // If two confirmed appointments overlap, the earlier-inserted one wins
    // (lower id = booked first). Downgrade the later one to pending.
    _appointments.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    final healed = <int>{};
    for (int i = 0; i < _appointments.length; i++) {
      final a = _appointments[i];
      if (a.status == ApptStatus.cancelled || healed.contains(a.id)) continue;
      final aStart = a.dateTime.millisecondsSinceEpoch;
      final aEnd   = aStart + _durationMins(a.duration) * 60000;
      for (int j = i + 1; j < _appointments.length; j++) {
        final b = _appointments[j];
        if (b.status == ApptStatus.cancelled || healed.contains(b.id)) continue;
        final bStart = b.dateTime.millisecondsSinceEpoch;
        final bEnd   = bStart + _durationMins(b.duration) * 60000;
        if (aStart < bEnd && aEnd > bStart) {
          // b was booked later — downgrade to pending
          if (b.id != null) {
            healed.add(b.id!);
            await DBHelper.instance.updateAppointmentStatus(b.id!, ApptStatus.pending);
            _appointments[j] = _appointments[j].copyWith(status: ApptStatus.pending);
          }
        }
      }
    }
    _appointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
  }

  /// Parse the encoded theme string (handles both plain names and custom_HEX).
  void _applyEncodedTheme(String encoded) {
    if (encoded.startsWith('customDark_') || encoded.startsWith('customLight_')) {
      final parts = encoded.split('_');
      final hexStr = parts.length > 1 ? parts[1] : '';
      final hexVal = int.tryParse(hexStr, radix: 16);
      if (hexVal != null) _customAccent = Color(hexVal);
      _themeMode = encoded.startsWith('customDark')
          ? AppThemeMode.customDark
          : AppThemeMode.customLight;
      return;
    }
    final parsed = AppThemeMode.values
        .where((m) => m.name == encoded)
        .firstOrNull;
    if (parsed != null) _themeMode = parsed;
  }

  // Returns list of appointment names that were auto-cancelled due to conflict
  Future<List<String>> addAppointment(Appointment appt) async {
    final userId = UserSession.instance.userId ?? 0;
    final id     = await DBHelper.instance.insertAppointment(appt, userId);
    appt.id = id;
    // appt_number was computed inside insertAppointment — reload it from DB
    // so the in-memory object shows the ordinal badge immediately
    final fresh = await DBHelper.instance.getAppointmentById(id);
    if (fresh != null) appt.apptNumber = fresh.apptNumber;
    _appointments.add(appt);
    _appointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // ── Conflict detection ─────────────────────────────────────────────
    // The FIRST (existing) confirmed appointment always wins.
    // If the new appointment overlaps an existing one, downgrade the NEW one to pending.
    final cancelled = <String>[];
    final newStartDt = appt.dateTime;
    final newEndDt   = newStartDt.add(Duration(minutes: _durationMins(appt.duration)));
    final newStart   = newStartDt.millisecondsSinceEpoch;
    final newEnd     = newEndDt.millisecondsSinceEpoch;

    bool hasConflict = false;
    for (final existing in _appointments) {
      if (existing.id == appt.id) continue;
      if (existing.status == ApptStatus.cancelled) continue;
      final exStart = existing.dateTime.millisecondsSinceEpoch;
      final exEnd   = exStart + _durationMins(existing.duration) * 60000;
      if (newStart < exEnd && newEnd > exStart) {
        hasConflict = true;
        cancelled.add(existing.name); // report the conflict name
      }
    }

    // Also check personal tasks
    final taskBlock = PersonalTaskStore.instance.conflictFor(newStartDt, newEndDt);
    if (taskBlock != null) {
      hasConflict = true;
      cancelled.add('Task: ${taskBlock.title}');
    }

    // If conflict found, downgrade the NEW appointment to pending (existing stays confirmed)
    if (hasConflict) {
      appt.status = ApptStatus.pending;
      await DBHelper.instance.updateAppointmentStatus(appt.id!, ApptStatus.pending);
      final idx = _appointments.indexWhere((a) => a.id == appt.id);
      if (idx != -1) _appointments[idx].status = ApptStatus.pending;
    }

    notifyListeners();
    return cancelled;
  }

  int _durationMins(String d) {
    if (d == '15 min') return 15;
    if (d == '30 min') return 30;
    if (d == '45 min') return 45;
    if (d == '1 hr')   return 60;
    if (d == '1.5 hr') return 90;
    if (d == '2 hr')   return 120;
    return 30;
  }

  Future<void> updateAppointment(Appointment appt) async {
    await DBHelper.instance.updateAppointment(appt);
    final idx = _appointments.indexWhere((a) => a.id == appt.id);
    if (idx != -1) _appointments[idx] = appt;
    notifyListeners();
  }

  Future<void> updateAppointmentStatus(int id, ApptStatus status) async {
    await DBHelper.instance.updateAppointmentStatus(id, status);
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx != -1) _appointments[idx].status = status;
    notifyListeners();
  }

  Future<void> deleteAppointment(int id) async {
    await DBHelper.instance.deleteAppointment(id);
    _appointments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  List<Appointment> appointmentsForDate(DateTime date) =>
      _appointments.where((a) =>
      a.dateTime.year  == date.year &&
          a.dateTime.month == date.month &&
          a.dateTime.day   == date.day
      ).toList();

  List<Appointment> appointmentsForWeekdayIndex(int index) {
    final now    = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    return appointmentsForDate(sunday.add(Duration(days: index)));
  }
}

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AppStateProvider>();
    assert(provider != null, 'No AppStateProvider found in widget tree');
    return provider!.notifier!;
  }
}