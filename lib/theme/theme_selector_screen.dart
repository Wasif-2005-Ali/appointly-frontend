import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';
import '../widgets/save_icon_button.dart';
import 'custom_color_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  THEME SELECTOR — Stunning professional redesign
//  • Cinematic gradient header with animated status
//  • Full-bleed theme cards with dual dark/light live previews
//  • Animated mode banner, premium section buttons, features grid
// ─────────────────────────────────────────────────────────────────────────────

class ThemeSelectorScreen extends StatefulWidget {
  const ThemeSelectorScreen({super.key});
  @override
  State<ThemeSelectorScreen> createState() => _ThemeSelectorScreenState();
}

class _ThemeSelectorScreenState extends State<ThemeSelectorScreen>
    with TickerProviderStateMixin {

  final _cs = ValueNotifier<int>(0);
  late AnimationController _headerAnim;
  late Animation<double>   _headerFade;
  bool _showDefaultTheme = false;
  bool _showPresetThemes = false;

  static const _pairs = [
    _PairData(
      darkMode:      AppThemeMode.navyDark,
      lightMode:     AppThemeMode.navyLight,
      name:          'Navy & Alice Blue',
      desc:          'Sophisticated professional look',
      iconBg:        Color(0xFF003566),
      icon:          Icons.waves_rounded,
      gradientDark:  [Color(0xFF050E22), Color(0xFF0B2447), Color(0xFF163870)],
      darkSwatches:  [Color(0xFF002855), Color(0xFF003f88), Color(0xFF0074d9)],
      lightSwatches: [Color(0xFFe8f4fd), Color(0xFF90caf9), Color(0xFF1565c0)],
    ),
    _PairData(
      darkMode:      AppThemeMode.blackDark,
      lightMode:     AppThemeMode.whiteDark,
      name:          'Black & White',
      desc:          'Minimalist monochrome elegance',
      iconBg:        Color(0xFF222222),
      icon:          Icons.contrast_rounded,
      gradientDark:  [Color(0xFF000000), Color(0xFF111111), Color(0xFF1C1C1C)],
      darkSwatches:  [Color(0xFF111111), Color(0xFF2c2c2c), Color(0xFF555555)],
      lightSwatches: [Color(0xFFf9f9f9), Color(0xFFe0e0e0), Color(0xFF757575)],
    ),
    _PairData(
      darkMode:      AppThemeMode.warmDark,
      lightMode:     AppThemeMode.warmLight,
      name:          'Warm Earth',
      desc:          'Cozy organic tones for focus',
      iconBg:        Color(0xFF5c4033),
      icon:          Icons.eco_rounded,
      gradientDark:  [Color(0xFF0E0A07), Color(0xFF1A1410), Color(0xFF32241A)],
      darkSwatches:  [Color(0xFF3e2723), Color(0xFF6d4c41), Color(0xFFa1887f)],
      lightSwatches: [Color(0xFFefebe9), Color(0xFFd7ccc8), Color(0xFF8d6e63)],
    ),
    _PairData(
      darkMode:      AppThemeMode.tealDark,
      lightMode:     AppThemeMode.tealLight,
      name:          'Ocean Teal',
      desc:          'Fresh aquatic energy & depth',
      iconBg:        Color(0xFF006d6d),
      icon:          Icons.water_rounded,
      gradientDark:  [Color(0xFF010810), Color(0xFF031163), Color(0xFF05716C)],
      darkSwatches:  [Color(0xFF004d40), Color(0xFF00695c), Color(0xFF00897b)],
      lightSwatches: [Color(0xFFe0f2f1), Color(0xFF80cbc4), Color(0xFF00897b)],
    ),
    _PairData(
      darkMode:      AppThemeMode.lavenderDark,
      lightMode:     AppThemeMode.lavenderLight,
      name:          'Lavender Dream',
      desc:          'Dreamy violet luxury palette',
      iconBg:        Color(0xFF4a1942),
      icon:          Icons.auto_awesome_rounded,
      gradientDark:  [Color(0xFF070310), Color(0xFF18093A), Color(0xFF4A1A8A)],
      darkSwatches:  [Color(0xFF2d1b69), Color(0xFF4c1d95), Color(0xFF7c3aed)],
      lightSwatches: [Color(0xFFf3e5f5), Color(0xFFce93d8), Color(0xFF8e24aa)],
    ),
  ];

  AppState get _s => AppStateProvider.of(context);

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerAnim.forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    _cs.dispose();
    super.dispose();
  }

  AppThemeMode _toDark(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.navyLight:     return AppThemeMode.navyDark;
      case AppThemeMode.whiteDark:     return AppThemeMode.blackDark;
      case AppThemeMode.warmLight:     return AppThemeMode.warmDark;
      case AppThemeMode.tealLight:     return AppThemeMode.tealDark;
      case AppThemeMode.lavenderLight: return AppThemeMode.lavenderDark;
      case AppThemeMode.customLight:   return AppThemeMode.customDark;
      default:                         return m;
    }
  }

  AppThemeMode _toLight(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.navyDark:      return AppThemeMode.navyLight;
      case AppThemeMode.blackDark:     return AppThemeMode.whiteDark;
      case AppThemeMode.warmDark:      return AppThemeMode.warmLight;
      case AppThemeMode.tealDark:      return AppThemeMode.tealLight;
      case AppThemeMode.lavenderDark:  return AppThemeMode.lavenderLight;
      case AppThemeMode.customDark:    return AppThemeMode.customLight;
      default:                         return m;
    }
  }

  Future<void> _openCustomPicker() async {
    final isCustom = _s.themeMode == AppThemeMode.customDark ||
        _s.themeMode == AppThemeMode.customLight;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CustomColourPickerScreen(
        initialColour: isCustom ? _s.customAccent : _s.accent,
        initialDark: _s.themeMode.isDark,
      )),
    );
    if (result == true && mounted) {
      _cs.value++;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarH = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _s.bg,
        body: Column(children: [
          _buildHeader(statusBarH),
          Expanded(
            child: RepaintBoundary(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildModeBanner(),
                  const SizedBox(height: 22),
                  // Default theme section
                  _buildSectionButton(
                    icon: Icons.star_rounded,
                    label: 'Default Theme',
                    subtitle: 'Navy & Alice Blue — Recommended palette',
                    isExpanded: _showDefaultTheme,
                    onTap: () => setState(() => _showDefaultTheme = !_showDefaultTheme),
                    accentColor: const Color(0xFF0074d9),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildThemeCard(_pairs[0], isDefault: true),
                    ),
                    crossFadeState: _showDefaultTheme
                        ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 280),
                    sizeCurve: Curves.easeOutCubic,
                  ),
                  const SizedBox(height: 14),
                  // Preset themes section
                  _buildSectionButton(
                    icon: Icons.palette_rounded,
                    label: 'Preset Themes',
                    subtitle: '4 curated palettes for every style',
                    isExpanded: _showPresetThemes,
                    onTap: () => setState(() => _showPresetThemes = !_showPresetThemes),
                    accentColor: _s.accent,
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(children: [
                        ..._pairs.skip(1).map((p) => _buildThemeCard(p)),
                      ]),
                    ),
                    crossFadeState: _showPresetThemes
                        ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                    sizeCurve: Curves.easeOutCubic,
                  ),
                  const SizedBox(height: 14),
                  // Custom colour button
                  _buildCustomButton(),
                  const SizedBox(height: 28),
                  _buildThemeFeatures(),
                  const SizedBox(height: 16),
                  _buildFooterLegend(),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Cinematic gradient header ──────────────────────────────────────────────
  Widget _buildHeader(double statusBarH) {
    final heroColors = _s.heroGradient;
    final isCustom   = _s.themeMode == AppThemeMode.customDark ||
        _s.themeMode == AppThemeMode.customLight;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: heroColors.take(4).toList(),
          stops: const [0.0, 0.35, 0.70, 1.0],
        ),
        boxShadow: [BoxShadow(
          color: heroColors.last.withOpacity(0.40),
          blurRadius: 32, offset: const Offset(0, 12),
        )],
      ),
      child: Stack(children: [
        // Decorative orbs
        Positioned(right: -40, top: -40,
            child: _Orb(180, heroColors.last, 0.14)),
        Positioned(left: -30, bottom: 0,
            child: _Orb(120, Colors.white, 0.06)),
        SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top row
            Row(children: [
              _GlassIconButton(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FadeTransition(
                  opacity: _headerFade,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('App Theme', style: GoogleFonts.spaceGrotesk(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: -0.6)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.shade400,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                              color: Colors.greenAccent.shade400.withOpacity(0.7),
                              blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_s.themeMode.label}  •  ${_s.isDarkMode ? "Dark" : "Light"} mode',
                        style: GoogleFonts.dmSans(fontSize: 12,
                            color: Colors.white.withOpacity(0.70),
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              SaveIconButton(
                changeSignal: _cs,
                foregroundColor: Colors.white,
                onSave: () async {
                  await Future.delayed(const Duration(milliseconds: 450));
                },
              ),
            ]),
            const SizedBox(height: 20),
            // Info strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.11),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(children: [
                // Current theme swatch
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _s.accent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
                    boxShadow: [BoxShadow(color: _s.accent.withOpacity(0.55), blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_s.themeMode.label,
                      style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(
                    isCustom
                        ? '#${_s.customAccent.value.toRadixString(16).substring(2).toUpperCase()}  •  Custom palette'
                        : '${_s.isDarkMode ? "Dark" : "Light"} variant active',
                    style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white.withOpacity(0.62),
                        fontWeight: FontWeight.w500),
                  ),
                ])),
                // Mini swatch row from current gradient
                Row(children: heroColors.take(3).map((c) => Container(
                  width: 12, height: 28,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )).toList()),
              ]),
            ),
          ]),
        )),
      ]),
    );
  }

  // ── Dark / Light mode banner ───────────────────────────────────────────────
  Widget _buildModeBanner() {
    final isDark = _s.isDarkMode;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _s.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _s.border, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Expanded(child: _ModeTab(
          label: 'Dark Mode', icon: Icons.nights_stay_rounded,
          isActive: isDark, accent: _s.accent, txtSub: _s.txtSub,
          onTap: () async {
            if (isDark) return;
            HapticFeedback.lightImpact();
            await _s.setTheme(_toDark(_s.themeMode));
            _cs.value++;
          },
        )),
        Expanded(child: _ModeTab(
          label: 'Light Mode', icon: Icons.wb_sunny_rounded,
          isActive: !isDark, accent: _s.accent, txtSub: _s.txtSub,
          onTap: () async {
            if (!isDark) return;
            HapticFeedback.lightImpact();
            await _s.setTheme(_toLight(_s.themeMode));
            _cs.value++;
          },
        )),
      ]),
    );
  }

  // ── Collapsible section button ─────────────────────────────────────────────
  Widget _buildSectionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isExpanded ? accentColor.withOpacity(0.09) : _s.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isExpanded ? accentColor.withOpacity(0.55) : _s.border,
            width: isExpanded ? 2 : 1.5,
          ),
          boxShadow: isExpanded
              ? [BoxShadow(color: accentColor.withOpacity(0.16), blurRadius: 18, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          // Icon badge
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [accentColor, Color.lerp(accentColor, Colors.black, 0.30)!]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: accentColor.withOpacity(0.42), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: _s.txtMain, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.dmSans(
                fontSize: 12, color: _s.txtSub, fontWeight: FontWeight.w500)),
          ])),
          AnimatedRotation(
            turns: isExpanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.expand_more_rounded, color: accentColor, size: 20),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Theme card ─────────────────────────────────────────────────────────────
  Widget _buildThemeCard(_PairData pair, {bool isDefault = false}) {
    final isActive = _s.themeMode == pair.darkMode || _s.themeMode == pair.lightMode;
    final isDark   = _s.isDarkMode;
    final acc      = pair.darkSwatches[2];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        HapticFeedback.lightImpact();
        await _s.setTheme(isDark ? pair.darkMode : pair.lightMode);
        _cs.value++;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _s.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive ? acc.withOpacity(0.72) : _s.border,
            width: isActive ? 2.5 : 1.5,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: acc.withOpacity(0.24), blurRadius: 28, offset: const Offset(0, 10))]
              : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Full-bleed gradient identity strip
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 60,
              child: Stack(children: [
                // Dark half
                Positioned.fill(child: Row(children: [
                  Expanded(child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: pair.gradientDark),
                    ),
                  )),
                  Expanded(child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        pair.lightSwatches[2],
                        pair.lightSwatches[1],
                        pair.lightSwatches[0],
                      ]),
                    ),
                  )),
                ])),
                // Divider line
                Center(child: Container(width: 1.5, height: 60,
                    color: Colors.white.withOpacity(0.25))),
                // Labels
                Positioned(left: 12, bottom: 8, child: Text('Dark',
                    style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.75)))),
                Positioned(right: 12, bottom: 8, child: Text('Light',
                    style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w800,
                        color: pair.lightSwatches[2].withOpacity(0.85)))),
                // Active mode indicator
                if (isActive)
                  Positioned(
                    top: 10,
                    left: isDark ? 10 : null,
                    right: isDark ? null : 10,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.shade400,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: Colors.greenAccent.shade400.withOpacity(0.8),
                            blurRadius: 6)],
                      ),
                    ),
                  ),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Head row
              Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [pair.iconBg, Color.lerp(pair.iconBg, Colors.black, 0.34)!]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: pair.iconBg.withOpacity(0.45),
                        blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Icon(pair.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(pair.name, style: GoogleFonts.spaceGrotesk(
                        fontSize: 15.5, fontWeight: FontWeight.w800, color: _s.txtMain),
                        overflow: TextOverflow.ellipsis)),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      _DefaultBadge(),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(pair.desc, style: GoogleFonts.dmSans(
                      fontSize: 12, color: _s.txtSub, fontWeight: FontWeight.w500)),
                ])),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim, child: ScaleTransition(scale: anim, child: child)),
                  child: isActive
                      ? _ActiveBadge(key: const ValueKey('on'), color: acc)
                      : const SizedBox.shrink(key: ValueKey('off')),
                ),
              ]),

              const SizedBox(height: 16),

              // Side-by-side rich preview
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 90,
                  child: Row(children: [
                    Expanded(child: _RichPreview(
                      swatches: pair.darkSwatches, label: 'Dark',
                      isCurrentMode: isActive && isDark,
                    )),
                    Container(width: 2, color: _s.bg),
                    Expanded(child: _RichPreview(
                      swatches: pair.lightSwatches, label: 'Light',
                      isCurrentMode: isActive && !isDark,
                    )),
                  ]),
                ),
              ),

              const SizedBox(height: 14),

              // Swatch palette row
              _SwatchPaletteRow(
                darkSwatches: pair.darkSwatches,
                lightSwatches: pair.lightSwatches,
                txtSub: _s.txtSub, txtMain: _s.txtMain,
              ),

              const SizedBox(height: 14),

              // Apply button row
              Row(children: [
                // Dark variant button
                Expanded(child: _VariantButton(
                  label: 'Apply Dark',
                  icon: Icons.nights_stay_rounded,
                  isActive: isActive && isDark,
                  color: pair.darkSwatches[2],
                  bg: pair.gradientDark[1],
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await _s.setTheme(pair.darkMode);
                    _cs.value++;
                  },
                )),
                const SizedBox(width: 10),
                // Light variant button
                Expanded(child: _VariantButton(
                  label: 'Apply Light',
                  icon: Icons.wb_sunny_rounded,
                  isActive: isActive && !isDark,
                  color: pair.lightSwatches[2],
                  bg: pair.lightSwatches[0],
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await _s.setTheme(pair.lightMode);
                    _cs.value++;
                  },
                )),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Custom colour standalone button ───────────────────────────────────────
  Widget _buildCustomButton() {
    final isActive  = _s.themeMode == AppThemeMode.customDark ||
        _s.themeMode == AppThemeMode.customLight;
    final customAcc = _s.customAccent;
    const rainbowGrad = LinearGradient(colors: [
      Color(0xFFFF6B6B), Color(0xFFFF9F43),
      Color(0xFFFECA57), Color(0xFF48DBFB),
      Color(0xFF4ECDC4), Color(0xFF6C5CE7),
    ]);

    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); _openCustomPicker(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        decoration: BoxDecoration(
          color: isActive ? customAcc.withOpacity(0.08) : _s.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive ? customAcc.withOpacity(0.58) : _s.border,
            width: isActive ? 2.5 : 1.5,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: customAcc.withOpacity(0.22), blurRadius: 24, offset: const Offset(0, 8))]
              : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Full-bleed rainbow/custom strip
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              height: isActive ? 8 : 7,
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(colors: [customAcc, customAcc.withOpacity(0.5)])
                    : rainbowGrad,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Icon badge
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [customAcc, Color.lerp(customAcc, Colors.black, 0.28)!])
                      : rainbowGrad,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: (isActive ? customAcc : const Color(0xFFFF6B6B)).withOpacity(0.45),
                    blurRadius: 12, offset: const Offset(0, 4),
                  )],
                ),
                child: const Icon(Icons.palette_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Custom Colour', style: GoogleFonts.spaceGrotesk(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: _s.txtMain, letterSpacing: -0.3)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(colors: [customAcc, customAcc.withOpacity(0.7)])
                          : rainbowGrad,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('PRO', style: GoogleFonts.dmSans(
                        fontSize: 9, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: 0.8)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? '#${customAcc.value.toRadixString(16).substring(2).toUpperCase()}  •  Currently active'
                      : 'Pick any colour from the full spectrum',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _s.txtSub,
                      fontWeight: FontWeight.w500),
                ),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    // Active colour swatch
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: customAcc, borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _s.border),
                        boxShadow: [BoxShadow(color: customAcc.withOpacity(0.50), blurRadius: 8)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Tap to change colour',
                        style: GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w700,
                            color: customAcc)),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios_rounded, color: customAcc, size: 13),
                  ]),
                ],
              ])),
              const SizedBox(width: 8),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isActive ? customAcc.withOpacity(0.13) : _s.border.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.tune_rounded,
                    color: isActive ? customAcc : _s.txtSub, size: 20),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Theme features grid ────────────────────────────────────────────────────
  Widget _buildThemeFeatures() {
    final items = [
      _FeatureItem(Icons.public_rounded,       _s.accent, 'Works on all screens',
          'Applied globally throughout the entire app'),
      _FeatureItem(Icons.brightness_6_rounded, _s.accent, 'Dark & Light variants',
          'Toggle anytime — changes are live instantly'),
      _FeatureItem(Icons.bolt_rounded,         _s.accent, 'Instant apply',
          'No restart needed — reflects immediately'),
      _FeatureItem(Icons.color_lens_outlined,  _s.accent, 'Full colour support',
          '1 default + 4 presets + unlimited custom'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _s.cardBg, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _s.border, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: _s.accent.withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: _s.border)),
          ),
          child: Row(children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: _s.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome_rounded, color: _s.accent, size: 17),
            ),
            const SizedBox(width: 12),
            Text('Theme Features', style: GoogleFonts.spaceGrotesk(
                fontSize: 15.5, fontWeight: FontWeight.w800, color: _s.txtMain)),
          ]),
        ),
        // Feature list
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(children: items.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Container(width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: f.color.withOpacity(0.10), borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(f.icon, color: f.color, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.title, style: GoogleFonts.dmSans(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: _s.txtMain)),
                Text(f.subtitle, style: GoogleFonts.dmSans(
                    fontSize: 11.5, color: _s.txtSub, fontWeight: FontWeight.w500)),
              ])),
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: f.color.withOpacity(0.12), shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, color: f.color, size: 14),
              ),
            ]),
          )).toList()),
        ),
      ]),
    );
  }

  // ── Footer legend ──────────────────────────────────────────────────────────
  Widget _buildFooterLegend() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _LegendDot(color: _s.accent,  label: 'Active theme',  txtSub: _s.txtSub),
      const SizedBox(width: 28),
      _LegendDot(color: _s.border,  label: 'Available',     txtSub: _s.txtSub),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  VARIANT BUTTON  (Apply Dark / Apply Light per card)
// ─────────────────────────────────────────────────────────────────────────────
class _VariantButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color, bg;
  final VoidCallback onTap;
  const _VariantButton({
    required this.label, required this.icon,
    required this.isActive, required this.color,
    required this.bg, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.14) : bg.withOpacity(0.20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color.withOpacity(0.65) : color.withOpacity(0.20),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withOpacity(0.22), blurRadius: 10, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          if (isActive) ...[
            const SizedBox(width: 5),
            Icon(Icons.check_circle_rounded, size: 12, color: color),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ORB  (decorative header background element)
// ─────────────────────────────────────────────────────────────────────────────
class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Orb(this.size, this.color, this.opacity);
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color.withOpacity(opacity), Colors.transparent]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLASS ICON BUTTON  (header back)
// ─────────────────────────────────────────────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _GlassIconButton({required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.24)),
      ),
      child: Center(child: child),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color accent, txtSub;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.icon,
    required this.isActive, required this.accent,
    required this.txtSub, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(colors: [accent, accent.withOpacity(0.72)])
            : null,
        borderRadius: BorderRadius.circular(15),
        boxShadow: isActive
            ? [BoxShadow(color: accent.withOpacity(0.30), blurRadius: 12, offset: const Offset(0, 4))]
            : [],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: isActive ? Colors.white : txtSub, size: 16),
        const SizedBox(width: 7),
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 13.5, fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : txtSub)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ACTIVE BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveBadge extends StatelessWidget {
  final Color color;
  const _ActiveBadge({super.key, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withOpacity(0.45)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle_rounded, color: color, size: 11),
      const SizedBox(width: 4),
      Text('Active', style: GoogleFonts.dmSans(
          fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DEFAULT BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();
  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFF4A24A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: gold.withOpacity(0.50)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, color: gold, size: 10),
        const SizedBox(width: 4),
        Text('Default', style: GoogleFonts.dmSans(
            fontSize: 10.5, fontWeight: FontWeight.w800, color: gold)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RICH PREVIEW  (mini mock-app card, dark or light)
// ─────────────────────────────────────────────────────────────────────────────
class _RichPreview extends StatelessWidget {
  final List<Color> swatches;
  final String label;
  final bool isCurrentMode;
  const _RichPreview({required this.swatches, required this.label, required this.isCurrentMode});

  @override
  Widget build(BuildContext context) {
    final bg  = swatches[0];
    final mid = swatches[1];
    final acc = swatches[2];
    final lum     = bg.computeLuminance();
    final textCol = lum < 0.40 ? Colors.white.withOpacity(0.88) : Colors.black.withOpacity(0.80);
    final subCol  = lum < 0.40 ? Colors.white.withOpacity(0.40) : Colors.black.withOpacity(0.28);

    return Container(
      color: bg,
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Simulated top bar
          Row(children: [
            Container(width: 28, height: 5,
                decoration: BoxDecoration(color: acc, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Expanded(child: Container(height: 5,
                decoration: BoxDecoration(color: mid.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(3)))),
          ]),
          // Simulated card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: mid.withOpacity(0.30), borderRadius: BorderRadius.circular(7),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 3, width: 34, decoration: BoxDecoration(
                  color: textCol, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 4),
              Container(height: 2, width: 22, decoration: BoxDecoration(
                  color: subCol, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
          // Footer row
          Row(children: [
            Expanded(child: Text(label, style: GoogleFonts.dmSans(
                fontSize: 9, fontWeight: FontWeight.w700, color: textCol))),
            if (isCurrentMode)
              Container(width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade400, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.greenAccent.shade400.withOpacity(0.7), blurRadius: 5)],
                  )),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SWATCH PALETTE ROW
// ─────────────────────────────────────────────────────────────────────────────
class _SwatchPaletteRow extends StatelessWidget {
  final List<Color> darkSwatches, lightSwatches;
  final Color txtSub, txtMain;
  const _SwatchPaletteRow({required this.darkSwatches, required this.lightSwatches,
    required this.txtSub, required this.txtMain});
  Widget _bar(List<Color> colors) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(height: 22, child: Row(
        children: colors.map((c) => Expanded(child: ColoredBox(color: c))).toList())),
  );
  Widget _label(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 9, color: txtSub.withOpacity(0.65)),
    const SizedBox(width: 3),
    Text(text, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600,
        color: txtSub, letterSpacing: 0.2)),
  ]);
  @override
  Widget build(BuildContext context) => Row(children: [
    _label(Icons.nights_stay_rounded, 'Dark'),
    const SizedBox(width: 6),
    Expanded(child: _bar(darkSwatches)),
    const SizedBox(width: 12),
    _label(Icons.wb_sunny_rounded, 'Light'),
    const SizedBox(width: 6),
    Expanded(child: _bar(lightSwatches)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEGEND DOT
// ─────────────────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color, txtSub;
  final String label;
  const _LegendDot({required this.color, required this.label, required this.txtSub});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w600, color: txtSub)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureItem {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  const _FeatureItem(this.icon, this.color, this.title, this.subtitle);
}

class _PairData {
  final AppThemeMode darkMode, lightMode;
  final String name, desc;
  final Color iconBg;
  final IconData icon;
  final List<Color> gradientDark, darkSwatches, lightSwatches;
  const _PairData({
    required this.darkMode, required this.lightMode,
    required this.name, required this.desc,
    required this.iconBg, required this.icon,
    required this.gradientDark, required this.darkSwatches, required this.lightSwatches,
  });
}