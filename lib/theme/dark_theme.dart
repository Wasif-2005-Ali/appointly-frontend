import 'package:flutter/material.dart';
import '../app_state.dart';

/// Theme-aware mixin used by every screen.
/// Reads the active AppThemeMode and returns the correct colour for that theme.
mixin DarkMode<T extends StatefulWidget> on State<T> {

  AppState get _s => AppStateProvider.of(context);
  AppThemeMode get _t => _s.themeMode;
  bool get dark => _t.isDark;
  Color get _ca => _s.customAccent; // custom accent shortcut

  static Color _cSetHSL(Color base, {double? l, double? s}) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((l ?? hsl.lightness).clamp(0.0, 1.0))
        .withSaturation((s ?? hsl.saturation).clamp(0.0, 1.0))
        .toColor();
  }
  static Color _cVibrantDark(Color c) {
    final hsl = HSLColor.fromColor(c);
    final s = hsl.saturation < 0.4 ? 0.65 : hsl.saturation;
    final l = hsl.lightness.clamp(0.52, 0.72);
    return hsl.withSaturation(s).withLightness(l).toColor();
  }
  static Color _cVibrantLight(Color c) {
    final hsl = HSLColor.fromColor(c);
    final s = hsl.saturation < 0.35 ? 0.60 : hsl.saturation;
    final l = hsl.lightness.clamp(0.30, 0.50);
    return hsl.withSaturation(s).withLightness(l).toColor();
  }

  // ── Backgrounds ────────────────────────────────────────────────────────────
  Color get dmBg {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF080E1C);
      case AppThemeMode.navyLight:  return const Color(0xFFEFF6FF);
      case AppThemeMode.blackDark:  return const Color(0xFF000000);
      case AppThemeMode.whiteDark:  return const Color(0xFFFFFFFF);
      case AppThemeMode.warmDark:   return const Color(0xFF1A1410);
      case AppThemeMode.warmLight:  return const Color(0xFFF5EDE4);
      case AppThemeMode.tealDark:   return const Color(0xFF020C12);
      case AppThemeMode.tealLight:  return const Color(0xFFE0F7F6);
      case AppThemeMode.lavenderDark:  return const Color(0xFF0E0814);
      case AppThemeMode.lavenderLight: return const Color(0xFFFAF8FF);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.06, s: 0.20);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.97, s: 0.10);
    }
  }

  Color get dmCard {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF0F1828);
      case AppThemeMode.navyLight:  return Colors.white;
      case AppThemeMode.blackDark:  return const Color(0xFF0D0D0D);
      case AppThemeMode.whiteDark:  return const Color(0xFFF2F2F2);
      case AppThemeMode.warmDark:   return const Color(0xFF231C15);
      case AppThemeMode.warmLight:  return const Color(0xFFEEE0D3);
      case AppThemeMode.tealDark:   return const Color(0xFF071420);
      case AppThemeMode.tealLight:  return const Color(0xFFCDF0EE);
      case AppThemeMode.lavenderDark:  return const Color(0xFF1A1126);
      case AppThemeMode.lavenderLight: return const Color(0xFFFFFFFF);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.11, s: 0.22);
      case AppThemeMode.customLight:      return Colors.white;
    }
  }

  Color get dmCard2 {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF141E2E);
      case AppThemeMode.navyLight:  return const Color(0xFFF4F9FF);
      case AppThemeMode.blackDark:  return const Color(0xFF141414);
      case AppThemeMode.whiteDark:  return const Color(0xFFEAEAEA);
      case AppThemeMode.warmDark:   return const Color(0xFF2C2218);
      case AppThemeMode.warmLight:  return const Color(0xFFE6D4C4);
      case AppThemeMode.tealDark:   return const Color(0xFF0B1C2C);
      case AppThemeMode.tealLight:  return const Color(0xFFB8E8E6);
      case AppThemeMode.lavenderDark:  return const Color(0xFF241535);
      case AppThemeMode.lavenderLight: return const Color(0xFFF3EEFF);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.15, s: 0.24);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.96, s: 0.08);
    }
  }

  // ── Borders ────────────────────────────────────────────────────────────────
  Color get dmBorder {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF1A2D4A);
      case AppThemeMode.navyLight:  return const Color(0xFFDCEBFF);
      case AppThemeMode.blackDark:  return const Color(0xFF2A2A2A);
      case AppThemeMode.whiteDark:  return const Color(0xFFDDDDDD);
      case AppThemeMode.warmDark:   return const Color(0xFF3A2C20);
      case AppThemeMode.warmLight:  return const Color(0xFFCFBBAA);
      case AppThemeMode.tealDark:   return const Color(0xFF0A2232);
      case AppThemeMode.tealLight:  return const Color(0xFF7FDAD6);
      case AppThemeMode.lavenderDark:  return const Color(0xFF2E1F42);
      case AppThemeMode.lavenderLight: return const Color(0xFFE2D9F3);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.20, s: 0.30);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.86, s: 0.28);
    }
  }

  Color get dmBorder2 {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF21334D);
      case AppThemeMode.navyLight:  return const Color(0xFFE8F2FF);
      case AppThemeMode.blackDark:  return const Color(0xFF1E1E1E);
      case AppThemeMode.whiteDark:  return const Color(0xFFEAEAEA);
      case AppThemeMode.warmDark:   return const Color(0xFF2E2018);
      case AppThemeMode.warmLight:  return const Color(0xFFBEAA98);
      case AppThemeMode.tealDark:   return const Color(0xFF081C2A);
      case AppThemeMode.tealLight:  return const Color(0xFF5AC8C4);
      case AppThemeMode.lavenderDark:  return const Color(0xFF221538);
      case AppThemeMode.lavenderLight: return const Color(0xFFD4C8EE);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.16, s: 0.26);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.90, s: 0.20);
    }
  }

  // ── Text ───────────────────────────────────────────────────────────────────
  Color get dmTxtMain {
    switch (_t) {
      case AppThemeMode.navyDark:   return Colors.white;
      case AppThemeMode.navyLight:  return const Color(0xFF0B2447);
      case AppThemeMode.blackDark:  return Colors.white;
      case AppThemeMode.whiteDark:  return Colors.black;
      case AppThemeMode.warmDark:   return const Color(0xFFF0E8E0);
      case AppThemeMode.warmLight:  return const Color(0xFF2E1E10);
      case AppThemeMode.tealDark:   return Colors.white;
      case AppThemeMode.tealLight:  return const Color(0xFF031163);
      case AppThemeMode.lavenderDark:  return const Color(0xFFF0ECFF);
      case AppThemeMode.lavenderLight: return const Color(0xFF2A1A4A);
      case AppThemeMode.customDark:       return Colors.white;
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.12, s: 0.40);
    }
  }

  Color get dmTxtSub {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF6080A8);
      case AppThemeMode.navyLight:  return const Color(0xFF7A96BE);
      case AppThemeMode.blackDark:  return const Color(0xFF888888);
      case AppThemeMode.whiteDark:  return const Color(0xFF666666);
      case AppThemeMode.warmDark:   return const Color(0xFF9A8070);
      case AppThemeMode.warmLight:  return const Color(0xFF7A6050);
      case AppThemeMode.tealDark:   return const Color(0xFF4A8895);
      case AppThemeMode.tealLight:  return const Color(0xFF05716C);
      case AppThemeMode.lavenderDark:  return const Color(0xFFA78BFA);
      case AppThemeMode.lavenderLight: return const Color(0xFF7C3AED);
      case AppThemeMode.customDark:       return _cVibrantDark(_ca).withOpacity(0.60);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.42, s: 0.35);
    }
  }

  Color get dmTxtBody {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFFB8CEE8);
      case AppThemeMode.navyLight:  return const Color(0xFF4A6080);
      case AppThemeMode.blackDark:  return const Color(0xFFCCCCCC);
      case AppThemeMode.whiteDark:  return const Color(0xFF333333);
      case AppThemeMode.warmDark:   return const Color(0xFFD4C4B4);
      case AppThemeMode.warmLight:  return const Color(0xFF5A4030);
      case AppThemeMode.tealDark:   return const Color(0xFF90C8D0);
      case AppThemeMode.tealLight:  return const Color(0xFF1978A5);
      case AppThemeMode.lavenderDark:  return const Color(0xFFCBBEF0);
      case AppThemeMode.lavenderLight: return const Color(0xFF5E3EA8);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.72, s: 0.40);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.30, s: 0.40);
    }
  }

  Color get dmDivider {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF1A2A40);
      case AppThemeMode.navyLight:  return const Color(0xFFEAF2FF);
      case AppThemeMode.blackDark:  return const Color(0xFF1E1E1E);
      case AppThemeMode.whiteDark:  return const Color(0xFFE0E0E0);
      case AppThemeMode.warmDark:   return const Color(0xFF2E2218);
      case AppThemeMode.warmLight:  return const Color(0xFFD4C0AE);
      case AppThemeMode.tealDark:   return const Color(0xFF0A1C2A);
      case AppThemeMode.tealLight:  return const Color(0xFF9ADAD8);
      case AppThemeMode.lavenderDark:  return const Color(0xFF1E1030);
      case AppThemeMode.lavenderLight: return const Color(0xFFEAE0FA);
      case AppThemeMode.customDark:       return _cSetHSL(_ca, l: 0.12, s: 0.18);
      case AppThemeMode.customLight:      return _cSetHSL(_ca, l: 0.92, s: 0.14);
    }
  }

  // ── Accent / Primary ───────────────────────────────────────────────────────
  Color get dmAccent {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF4A90D9);
      case AppThemeMode.navyLight:  return const Color(0xFF1A5EA8);
      case AppThemeMode.blackDark:  return Colors.white;
      case AppThemeMode.whiteDark:  return Colors.black;
      case AppThemeMode.warmDark:   return const Color(0xFFE0CDBE);
      case AppThemeMode.warmLight:  return const Color(0xFF6B8F72);
      case AppThemeMode.tealDark:   return const Color(0xFF1FBFB8);
      case AppThemeMode.tealLight:  return const Color(0xFF05716C);
      case AppThemeMode.lavenderDark:  return const Color(0xFFA78BFA);
      case AppThemeMode.lavenderLight: return const Color(0xFF7C3AED);
      case AppThemeMode.customDark:       return _cVibrantDark(_ca);
      case AppThemeMode.customLight:      return _cVibrantLight(_ca);
    }
  }
  List<Color> get dmHeroGradient {
    switch (_t) {
      case AppThemeMode.navyDark:
        return [const Color(0xFF050E22), const Color(0xFF0B2447), const Color(0xFF153362)];
      case AppThemeMode.navyLight:
        return [const Color(0xFF0B2447), const Color(0xFF1A4A8A), const Color(0xFF2A6AB5)];
      case AppThemeMode.blackDark:
        return [const Color(0xFF000000), const Color(0xFF0A0A0A), const Color(0xFF141414)];
      case AppThemeMode.whiteDark:
        return [const Color(0xFFFFFFFF), const Color(0xFFF5F5F5), const Color(0xFFEBEBEB)];
      case AppThemeMode.warmDark:
        return [const Color(0xFF0E0A07), const Color(0xFF1A1410), const Color(0xFF28201A)];
      case AppThemeMode.warmLight:
        return [const Color(0xFF4A3025), const Color(0xFF604035), const Color(0xFF785045)];
      case AppThemeMode.tealDark:
        return [const Color(0xFF010810), const Color(0xFF031163), const Color(0xFF05716C)];
      case AppThemeMode.tealLight:
        return [const Color(0xFF05716C), const Color(0xFF1978A5), const Color(0xFF1FBFB8)];
      case AppThemeMode.lavenderDark:
        return [const Color(0xFF070310), const Color(0xFF18093A), const Color(0xFF4A1A8A)];
      case AppThemeMode.lavenderLight:
        return [const Color(0xFF3B0F8C), const Color(0xFF5E22C0), const Color(0xFF9B59E8)];
      case AppThemeMode.customDark:     return [_cSetHSL(_ca, l: 0.04, s: 0.18), _cSetHSL(_ca, l: 0.10, s: 0.50), _cSetHSL(_ca, l: 0.20, s: 0.65)];
      case AppThemeMode.customLight:    return [_cSetHSL(_ca, l: 0.22, s: 0.65), _cSetHSL(_ca, l: 0.34, s: 0.70), _cSetHSL(_ca, l: 0.46, s: 0.68)];
    }
  }  // ── Active / selected pill ─────────────────────────────────────────────────
  List<Color> get dmActivePillGradient {
    switch (_t) {
      case AppThemeMode.navyDark:
        return [const Color(0xFF0B2447), const Color(0xFF1E4580)];
      case AppThemeMode.navyLight:
        return [const Color(0xFF0B2447), const Color(0xFF1E4580)];
      case AppThemeMode.blackDark:
        return [const Color(0xFF111111), const Color(0xFF2E2E2E)];
      case AppThemeMode.whiteDark:
        return [const Color(0xFFDDDDDD), const Color(0xFFBBBBBB)];
      case AppThemeMode.warmDark:
        return [const Color(0xFF3A2C20), const Color(0xFF5A4030)];
      case AppThemeMode.warmLight:
        return [const Color(0xFF6B8F72), const Color(0xFFA9C0A6)];
      case AppThemeMode.tealDark:
        return [const Color(0xFF031163), const Color(0xFF05716C)];
      case AppThemeMode.tealLight:
        return [const Color(0xFF05716C), const Color(0xFF1FBFB8)];
      case AppThemeMode.lavenderDark:
        return [const Color(0xFF4A1A8A), const Color(0xFF7C3AED)];
      case AppThemeMode.lavenderLight:
        return [const Color(0xFF5B21B6), const Color(0xFF9B59E8)];
      case AppThemeMode.customDark:     return [_cSetHSL(_ca, l: 0.14, s: 0.55), _cSetHSL(_ca, l: 0.26, s: 0.70)];
      case AppThemeMode.customLight:    return [_cSetHSL(_ca, l: 0.24, s: 0.65), _cSetHSL(_ca, l: 0.40, s: 0.72)];
    }
  }
  List<Color> get dmBtnGradient {
    switch (_t) {
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
      case AppThemeMode.customDark:     return [_cSetHSL(_ca, l: 0.14, s: 0.55), _cSetHSL(_ca, l: 0.26, s: 0.70)];
      case AppThemeMode.customLight:    return [_cSetHSL(_ca, l: 0.24, s: 0.65), _cSetHSL(_ca, l: 0.38, s: 0.72)];
    }
  }

  // ── Stat chip bg on hero ───────────────────────────────────────────────────
  Color get dmChipBg {
    switch (_t) {
      case AppThemeMode.navyDark:   return const Color(0xFF4A90D9).withOpacity(0.18);
      case AppThemeMode.navyLight:  return const Color(0xFF4A90D9).withOpacity(0.18);
      case AppThemeMode.blackDark:  return Colors.white.withOpacity(0.12);
      case AppThemeMode.whiteDark:  return Colors.black.withOpacity(0.08);
      case AppThemeMode.warmDark:   return const Color(0xFFE0CDBE).withOpacity(0.15);
      case AppThemeMode.warmLight:  return const Color(0xFF6B8F72).withOpacity(0.18);
      case AppThemeMode.tealDark:   return const Color(0xFF1FBFB8).withOpacity(0.15);
      case AppThemeMode.tealLight:  return const Color(0xFFFFFFFF).withOpacity(0.25);
      case AppThemeMode.lavenderDark:  return const Color(0xFFA78BFA).withOpacity(0.15);
      case AppThemeMode.lavenderLight: return const Color(0xFFFFFFFF).withOpacity(0.30);
      case AppThemeMode.customDark:       return _cVibrantDark(_ca).withOpacity(0.18);
      case AppThemeMode.customLight:      return _cVibrantLight(_ca).withOpacity(0.15);
    }
  }
}
