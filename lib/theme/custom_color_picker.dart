import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';

class CustomColourPickerScreen extends StatefulWidget {
  final Color initialColour;
  final bool initialDark;
  const CustomColourPickerScreen({
    super.key,
    required this.initialColour,
    required this.initialDark,
  });
  @override
  State<CustomColourPickerScreen> createState() => _CustomColourPickerScreenState();
}

class _CustomColourPickerScreenState extends State<CustomColourPickerScreen>
    with TickerProviderStateMixin {
  late double _hue, _sat, _val;
  late bool _isDark;
  late final ValueNotifier<HSVColor> _colorNotifier;
  late AnimationController _fadeCtrl;
  late TabController _tabCtrl;
  final _hexCtrl = TextEditingController();
  bool _hexValid = true;
  int? _activePreset;
  int  _activeHarmony = -1;
  int  _colorMode = 1; // 0=RGB 1=HSV
  int  _mixMode   = 1; // 0=Linear 1=Perceptual

  static final List<Color> _recentColors = [];

  // ── Colour math ────────────────────────────────────────────────────────────
  static double _relativeLuminance(Color c) {
    double lin(int v) {
      final s = v / 255.0;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }
    return 0.2126 * lin((c.r * 255).round()) +
        0.7152 * lin((c.g * 255).round()) +
        0.0722 * lin((c.b * 255).round());
  }
  Color _contrastText(Color bg) =>
      _relativeLuminance(bg) > 0.35 ? const Color(0xFF0D0D1A) : Colors.white;

  // ── Preset data ────────────────────────────────────────────────────────────
  static const _presets = [
    Color(0xFF0052CC),Color(0xFF0747A6),Color(0xFF1E88E5),Color(0xFF42A5F5),
    Color(0xFF90CAF9),Color(0xFF1A5EA8),Color(0xFF003F88),Color(0xFF4A90D9),
    Color(0xFF1B4332),Color(0xFF2D6A4F),Color(0xFF40916C),Color(0xFF52B788),
    Color(0xFF00695C),Color(0xFF00897B),Color(0xFF26A69A),Color(0xFF4DB6AC),
    Color(0xFF2D1B69),Color(0xFF4C1D95),Color(0xFF6D28D9),Color(0xFF7C3AED),
    Color(0xFF8B5CF6),Color(0xFFA78BFA),Color(0xFF9C27B0),Color(0xFFCE93D8),
    Color(0xFFD00000),Color(0xFFE53935),Color(0xFFEC407A),Color(0xFFFF006E),
    Color(0xFFF72585),Color(0xFFFB5607),Color(0xFFC9184A),Color(0xFFFF4D6D),
    Color(0xFFE65100),Color(0xFFF57C00),Color(0xFFFFB300),Color(0xFFF48C06),
    Color(0xFFE07A5F),Color(0xFFD4603A),Color(0xFFFF6B35),Color(0xFFF7C59F),
    Color(0xFF172B4D),Color(0xFF253858),Color(0xFF344563),Color(0xFF42526E),
    Color(0xFF505F79),Color(0xFF6B778D),Color(0xFF97A0AF),Color(0xFFB3BAC5),
    Color(0xFFC9A227),Color(0xFF9C6644),Color(0xFF6D2B3D),Color(0xFF4A1942),
    Color(0xFF2C2C54),Color(0xFF6D1A36),Color(0xFFA0313D),Color(0xFFB5838D),
    Color(0xFF5865F2),Color(0xFF0D99FF),Color(0xFF0ACF83),Color(0xFFA259FF),
    Color(0xFF1ABCFE),Color(0xFFFF7262),Color(0xFF14AE5C),Color(0xFFEB5757),
  ];
  static const _presetFamilies = [
    'Professional Blues','Forest & Teal','Premium Purples','Bold Reds & Pinks',
    'Warm Oranges','Slate & Neutrals','Luxury & Premium','Designer Picks',
  ];
  static const _presetFamilyColors = [
    Color(0xFF1E88E5),Color(0xFF40916C),Color(0xFF7C3AED),Color(0xFFEC407A),
    Color(0xFFF57C00),Color(0xFF6B778D),Color(0xFFC9A227),Color(0xFF5865F2),
  ];

  List<Color> get _harmonies => [
    HSVColor.fromAHSV(1,(_hue+180)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+120)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+240)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+30)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue-30+360)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+150)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+210)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+90)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,_hue,(_sat*0.4).clamp(0,1),_val).toColor(),
    HSVColor.fromAHSV(1,_hue,_sat,(_val*0.55).clamp(0,1)).toColor(),
    HSVColor.fromAHSV(1,(_hue+60)%360,_sat,_val).toColor(),
    HSVColor.fromAHSV(1,(_hue+300)%360,_sat,_val).toColor(),
  ];
  static const _harmonyLabels = [
    'Complement','Triadic ①','Triadic ②','Analog +',
    'Analog −','Split ①','Split ②','Tetradic',
    'Tint','Shade','Near Analog','Split Far',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _isDark = widget.initialDark;
    final hsv = HSVColor.fromColor(widget.initialColour);
    _hue = hsv.hue; _sat = hsv.saturation; _val = hsv.value;
    _colorNotifier = ValueNotifier(hsv);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))..forward();
    _tabCtrl  = TabController(length: 2, vsync: this);
    _updateHexField();
  }

  @override
  void dispose() {
    _hexCtrl.dispose(); _fadeCtrl.dispose(); _tabCtrl.dispose();
    _colorNotifier.dispose();
    super.dispose();
  }

  // ── Colour update paths ────────────────────────────────────────────────────
  void _setColorFast(double h, double s, double v) {
    _hue = h; _sat = s; _val = v;
    final hsv = HSVColor.fromAHSV(1, h, s, v);
    _colorNotifier.value = hsv;
    final hex = hsv.toColor().value.toRadixString(16).substring(2).toUpperCase();
    if (_hexCtrl.text != hex) {
      _hexCtrl.value = _hexCtrl.value.copyWith(
          text: hex, selection: TextSelection.collapsed(offset: hex.length));
    }
  }

  void _setColorFull(double h, double s, double v) {
    _hue = h; _sat = s; _val = v;
    final hsv = HSVColor.fromAHSV(1, h, s, v);
    setState(() { _colorNotifier.value = hsv; });
    _updateHexField();
  }

  void _updateHexField() {
    final hex = _colorNotifier.value.toColor().value.toRadixString(16).substring(2).toUpperCase();
    if (_hexCtrl.text != hex) _hexCtrl.text = hex;
    _hexValid = true;
  }

  void _setRgbFast(int r, int g, int b) {
    final c = Color.fromARGB(255, r.clamp(0,255), g.clamp(0,255), b.clamp(0,255));
    final hsv = HSVColor.fromColor(c);
    _setColorFast(hsv.hue, hsv.saturation, hsv.value);
  }

  void _onHexChanged(String raw) {
    final txt = raw.replaceAll('#','').toUpperCase();
    if (txt.length == 6) {
      final v = int.tryParse('FF$txt', radix: 16);
      if (v != null) {
        final c = Color(v);
        final hsv = HSVColor.fromColor(c);
        setState(() { _activePreset = null; _hexValid = true; });
        _setColorFull(hsv.hue, hsv.saturation, hsv.value);
        return;
      }
    }
    setState(() => _hexValid = false);
  }

  void _pickPreset(int i) {
    final hsv = HSVColor.fromColor(_presets[i]);
    setState(() { _activePreset = i; _activeHarmony = -1; });
    _setColorFull(hsv.hue, hsv.saturation, hsv.value);
    HapticFeedback.lightImpact();
    _addToRecent(_presets[i]);
  }

  void _addToRecent(Color c) {
    _recentColors.removeWhere((r) => r.value == c.value);
    _recentColors.insert(0, c);
    if (_recentColors.length > 14) _recentColors.removeLast();
  }

  void _randomColor() {
    final rng = math.Random();
    final h = rng.nextDouble() * 360;
    final s = 0.55 + rng.nextDouble() * 0.45;
    final v = 0.65 + rng.nextDouble() * 0.35;
    setState(() { _activePreset = null; _activeHarmony = -1; });
    _setColorFull(h, s, v);
    HapticFeedback.mediumImpact();
  }

  void _copyHex([Color? override]) {
    final c = override ?? _colorNotifier.value.toColor();
    final hex = '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
    Clipboard.setData(ClipboardData(text: hex));
    HapticFeedback.lightImpact();
    _showCopiedSnackBar(hex, c);
  }

  void _showCopiedSnackBar(String hex, Color c) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Container(width: 20, height: 20,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white.withOpacity(0.3)))),
        const SizedBox(width: 10),
        Text('Copied $hex',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: _contrastText(_acc))),
      ]),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: _acc,
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _apply() async {
    _addToRecent(_colorNotifier.value.toColor());
    final appState = AppStateProvider.of(context);
    await appState.setCustomTheme(_colorNotifier.value.toColor(), dark: _isDark);
    if (mounted) Navigator.pop(context, true);
  }

  // ── Live-preview theme colours ─────────────────────────────────────────────
  Color _setL(Color col, double l, double s) {
    final hsl = HSLColor.fromColor(col);
    return hsl.withLightness(l.clamp(0.0,1.0)).withSaturation(s.clamp(0.0,1.0)).toColor();
  }
  Color get _lc   => _colorNotifier.value.toColor();
  Color get _bg   { final c = _lc; return _isDark ? _setL(c,0.06,0.20) : _setL(c,0.97,0.08); }
  Color get _card { final c = _lc; return _isDark ? _setL(c,0.11,0.22) : Colors.white; }
  Color get _acc  {
    final c = _lc; final hsl = HSLColor.fromColor(c);
    return _isDark ? hsl.withLightness(hsl.lightness.clamp(0.52,0.72)).toColor()
        : hsl.withLightness(hsl.lightness.clamp(0.32,0.52)).toColor();
  }
  Color get _txt  { final c = _lc; return _isDark ? Colors.white : _setL(c,0.10,0.38); }
  Color get _sub  => _isDark ? _acc.withOpacity(0.55) : _setL(_lc,0.40,0.32);
  Color get _brd  { final c = _lc; return _isDark ? _setL(c,0.20,0.28) : _setL(c,0.86,0.22); }

  // ══════════════════════════════════════════════════════════════════════════
  //  ROOT BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HSVColor>(
      valueListenable: _colorNotifier,
      builder: (_, __, ___) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: _bg,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // RepaintBoundary stops FadeTransition's inherited-opacity from reaching
          // complex child renderers → eliminates the Impeller SetInheritedOpacity spam.
          body: RepaintBoundary(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
              child: Column(children: [
                _buildHeader(),
                _buildTabBar(),
                Expanded(child: TabBarView(
                  controller: _tabCtrl,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  children: [
                    // ── Tab 0: Colour Picker ───────────────────────────────
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(16,20,16,120),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_recentColors.isNotEmpty) ...[
                          _buildRecentColors(),
                          const SizedBox(height: 18),
                        ],
                        _buildPickerSection(),
                        const SizedBox(height: 18),
                        _buildHexInput(),
                        const SizedBox(height: 18),
                        _buildRgbReadout(),
                        const SizedBox(height: 18),
                        _buildDarkLightToggle(),
                        const SizedBox(height: 18),
                        _buildLivePreview(),
                      ]),
                    ),
                    // ── Tab 1: Presets & Harmony ───────────────────────────
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(16,20,16,120),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildHarmonySection(),
                        const SizedBox(height: 28),
                        _buildPresetsGrid(),
                      ]),
                    ),
                  ],
                )),
                _buildApplyBar(),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HEADER  — gradient, live circle (tap=copy), info strip (tap=copy)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return ValueListenableBuilder<HSVColor>(
      valueListenable: _colorNotifier,
      builder: (_, hsv, __) {
        final c    = hsv.toColor();
        final deep = Color.lerp(c, Colors.black, 0.80)!;
        final mid  = Color.lerp(c, Colors.black, 0.50)!;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [deep, mid, Color.lerp(c, Colors.black, 0.20)!],
              stops: const [0.0, 0.55, 1.0],
            ),
            boxShadow: [BoxShadow(color: c.withOpacity(0.40), blurRadius: 28, offset: const Offset(0,10))],
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(8,6,16,20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _PickerGlassBtn(onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Custom Colour', style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 2),
                  Text('Craft your perfect theme accent', style: GoogleFonts.dmSans(
                      fontSize: 12, color: Colors.white.withOpacity(0.58), fontWeight: FontWeight.w500)),
                ])),
                // Tap live circle → copy hex
                GestureDetector(
                  onTap: _copyHex,
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: c, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.30), width: 3),
                      boxShadow: [
                        BoxShadow(color: c.withOpacity(0.65), blurRadius: 18, offset: const Offset(0,6)),
                        BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 8),
                      ],
                    ),
                    child: Center(child: Icon(Icons.copy_rounded,
                        color: _contrastText(c).withOpacity(0.55), size: 14)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              // Info strip — tap to copy
              GestureDetector(
                onTap: _copyHex,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: Row(children: [
                    Text('#', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.48))),
                    const SizedBox(width: 3),
                    Text(c.value.toRadixString(16).substring(2).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w800,
                            color: Colors.white, letterSpacing: 2.5)),
                    const Spacer(),
                    _headerChip('H','${hsv.hue.round()}°'),
                    const SizedBox(width: 12),
                    _headerChip('S','${(hsv.saturation*100).round()}%'),
                    const SizedBox(width: 12),
                    _headerChip('V','${(hsv.value*100).round()}%'),
                    const SizedBox(width: 10),
                    Icon(Icons.copy_rounded, color: Colors.white.withOpacity(0.50), size: 14),
                  ]),
                ),
              ),
            ]),
          )),
        );
      },
    );
  }

  Widget _headerChip(String label, String val) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text('$label ', style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.48))),
    Text(val, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
  ]);

  // ══════════════════════════════════════════════════════════════════════════
  //  TAB BAR
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _brd, width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0,2))],
      ),
      padding: const EdgeInsets.fromLTRB(16,0,16,0),
      child: ValueListenableBuilder<HSVColor>(
        valueListenable: _colorNotifier,
        builder: (_, hsv, __) {
          final c = hsv.toColor();
          return TabBar(
            controller: _tabCtrl,
            labelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w800),
            unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600),
            labelColor: c, unselectedLabelColor: _sub,
            indicatorColor: c, indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: '🎨  Colour Picker'), Tab(text: '✦  Presets & Harmony')],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  RECENT COLOURS TRAY  (tap=pick, long-press=copy, clear button)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRecentColors() {
    final current = _colorNotifier.value.toColor();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brd, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 12,
              decoration: BoxDecoration(color: _acc, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('RECENT', style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
          const Spacer(),
          GestureDetector(
            onTap: () { setState(() => _recentColors.clear()); HapticFeedback.lightImpact(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _brd, borderRadius: BorderRadius.circular(8)),
              child: Text('Clear', style: GoogleFonts.dmSans(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: _sub)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _recentColors.map((rc) {
              final isActive = rc.value == current.value;
              return GestureDetector(
                onTap: () {
                  final hsv = HSVColor.fromColor(rc);
                  setState(() { _activePreset = null; _activeHarmony = -1; });
                  _setColorFull(hsv.hue, hsv.saturation, hsv.value);
                  HapticFeedback.selectionClick();
                },
                onLongPress: () => _copyHex(rc),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: rc, borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? Colors.white.withOpacity(0.9) : rc.withOpacity(0.25),
                      width: isActive ? 2.5 : 1,
                    ),
                    boxShadow: [BoxShadow(
                        color: rc.withOpacity(isActive ? 0.55 : 0.25),
                        blurRadius: isActive ? 14 : 4, offset: const Offset(0,3))],
                  ),
                  child: isActive
                      ? Icon(Icons.check_rounded, color: _contrastText(rc), size: 16)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PICKER SECTION  — wheel + brightness slider + hue strip + value rows
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPickerSection() {
    return ValueListenableBuilder<HSVColor>(
      valueListenable: _colorNotifier,
      builder: (_, hsv, __) {
        final c = hsv.toColor();
        return Container(
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _brd, width: 1.5),
            boxShadow: [BoxShadow(color: c.withOpacity(0.14), blurRadius: 28, offset: const Offset(0,10))],
          ),
          child: Column(children: [

            // ── Section header + Random button ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16,14,16,0),
              child: Row(children: [
                Container(width: 4, height: 16,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2),
                        boxShadow: [BoxShadow(color: c.withOpacity(0.55), blurRadius: 7)])),
                const SizedBox(width: 10),
                Text('COLOUR WHEEL', style: GoogleFonts.dmSans(
                    fontSize: 10.5, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.4)),
                const Spacer(),
                GestureDetector(
                  onTap: _randomColor,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.withOpacity(0.22)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.casino_rounded, color: c, size: 13),
                      const SizedBox(width: 5),
                      Text('Random', style: GoogleFonts.dmSans(
                          fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Mode toggles ─────────────────────────────────────────────
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _buildModeToggles(c)),
            const SizedBox(height: 14),

            // ── Colour wheel + brightness slider ─────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: LayoutBuilder(builder: (ctx, constraints) {
                const sliderW = 32.0;
                const gap     = 14.0;
                final wheelSz = constraints.maxWidth - sliderW - gap;
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: wheelSz, height: wheelSz,
                    child: RepaintBoundary(
                      child: _BlenderColorWheel(
                        hue: _hue, sat: _sat, val: _val,
                        onChanged: (h, s) => _setColorFast(h, s, _val),
                      ),
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(width: sliderW, height: wheelSz,
                    child: RepaintBoundary(
                      child: _BlenderValueSlider(
                        hue: _hue, sat: _sat, val: _val,
                        onChanged: (v) => _setColorFast(_hue, _sat, v),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: 14),

            // ── Hue precision strip (NEW) ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 3, height: 10,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text('HUE  ${_hue.round()}°', style: GoogleFonts.dmSans(
                      fontSize: 9.5, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.1)),
                ]),
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: _HueStripSlider(
                    hue: _hue,
                    onChanged: (h) => _setColorFast(h, _sat, _val),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Interactive HSV / RGB value rows ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14,0,14,14),
              child: _buildColorValueRows(hsv),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildModeToggles(Color c) {
    return Column(children: [
      _toggleRow(left:'Linear', right:'Perceptual',
          selected: _mixMode, activeColor: c,
          onLeft:  () => setState(() => _mixMode = 0),
          onRight: () => setState(() => _mixMode = 1)),
      const SizedBox(height: 8),
      _toggleRow(left:'RGB', right:'HSV',
          selected: _colorMode, activeColor: c,
          onLeft:  () => setState(() => _colorMode = 0),
          onRight: () => setState(() => _colorMode = 1)),
    ]);
  }

  Widget _toggleRow({
    required String left, required String right,
    required int selected, required Color activeColor,
    required VoidCallback onLeft, required VoidCallback onRight,
  }) {
    Widget pill(String label, bool active, VoidCallback tap) {
      final textCol = active ? _contrastText(activeColor) : _sub;
      return Expanded(child: GestureDetector(
        onTap: () { tap(); HapticFeedback.selectionClick(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 34, margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [BoxShadow(color: activeColor.withOpacity(0.38), blurRadius: 8, offset: const Offset(0,3))]
                : [],
          ),
          child: Center(child: Text(label, style: GoogleFonts.dmSans(
              fontSize: 12.5, fontWeight: FontWeight.w800, color: textCol))),
        ),
      ));
    }
    return Container(
      height: 40,
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _brd)),
      child: Row(children: [pill(left, selected==0, onLeft), pill(right, selected==1, onRight)]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INTERACTIVE VALUE ROWS  — every bar is a drag slider
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildColorValueRows(HSVColor hsv) {
    final c = hsv.toColor();
    if (_colorMode == 1) {
      return Column(children: [
        _blenderRow('Hue',        hsv.hue/360,         _fmt3(hsv.hue/360),        c,
            onChanged: (f) => _setColorFast(f*360, _sat, _val)),
        const SizedBox(height: 6),
        _blenderRow('Saturation', hsv.saturation,       _fmt3(hsv.saturation),     c,
            onChanged: (f) => _setColorFast(_hue, f, _val)),
        const SizedBox(height: 6),
        _blenderRow('Value',      hsv.value,            _fmt3(hsv.value),          c,
            onChanged: (f) => _setColorFast(_hue, _sat, f)),
      ]);
    } else {
      return Column(children: [
        _blenderRow('Red',   c.red/255,   _fmt3(c.red/255),   const Color(0xFFE53935),
            onChanged: (f) => _setRgbFast((f*255).round(), c.green, c.blue)),
        const SizedBox(height: 6),
        _blenderRow('Green', c.green/255, _fmt3(c.green/255), const Color(0xFF43A047),
            onChanged: (f) => _setRgbFast(c.red, (f*255).round(), c.blue)),
        const SizedBox(height: 6),
        _blenderRow('Blue',  c.blue/255,  _fmt3(c.blue/255),  const Color(0xFF1E88E5),
            onChanged: (f) => _setRgbFast(c.red, c.green, (f*255).round())),
      ]);
    }
  }

  String _fmt3(double v) => ((v*1000).round()/1000).toStringAsFixed(3);

  Widget _blenderRow(String label, double fraction, String valStr, Color barColor,
      {void Function(double)? onChanged}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12,9,12,9),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.80), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _brd),
      ),
      child: Row(children: [
        SizedBox(width: 80,
            child: Text(label, style: GoogleFonts.dmSans(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: _txt))),
        Expanded(child: onChanged != null
            ? _InteractiveSliderBar(
            fraction: fraction.clamp(0.0,1.0),
            barColor: barColor, bgColor: _brd, onChanged: onChanged)
            : _StaticBar(
            fraction: fraction.clamp(0.0,1.0),
            barColor: barColor, bgColor: _brd)),
        const SizedBox(width: 12),
        SizedBox(width: 46,
            child: Text(valStr, textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: _txt, letterSpacing: 0.5))),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HEX INPUT  — with one-tap copy button
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHexInput() {
    return ValueListenableBuilder<HSVColor>(
      valueListenable: _colorNotifier,
      builder: (_, hsv, __) {
        final c = hsv.toColor();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hexValid ? _brd : const Color(0xFFE05C5C).withOpacity(0.70),
              width: _hexValid ? 1.5 : 2,
            ),
            boxShadow: [BoxShadow(
              color: _hexValid ? Colors.black.withOpacity(0.04) : const Color(0xFFE05C5C).withOpacity(0.12),
              blurRadius: 12, offset: const Offset(0,4),
            )],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 3, height: 12,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('HEX CODE', style: GoogleFonts.dmSans(
                  fontSize: 10, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _brd, width: 1.5),
                      boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 12, offset: const Offset(0,4))])),
              const SizedBox(width: 14),
              Expanded(child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _bg, borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _hexValid ? _brd : const Color(0xFFE05C5C).withOpacity(0.5)),
                ),
                child: Row(children: [
                  Text('#', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w800,
                      color: _sub.withOpacity(0.45))),
                  const SizedBox(width: 4),
                  Expanded(child: TextField(
                    controller: _hexCtrl, onChanged: _onHexChanged,
                    style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w800,
                        color: _hexValid ? _txt : const Color(0xFFE05C5C), letterSpacing: 2),
                    decoration: InputDecoration.collapsed(
                      hintText: 'RRGGBB',
                      hintStyle: GoogleFonts.spaceGrotesk(color: _sub.withOpacity(0.35), letterSpacing: 2),
                    ),
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f]'))],
                    textCapitalization: TextCapitalization.characters,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  )),
                  // ── Copy button ──
                  GestureDetector(
                    onTap: _copyHex,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.copy_rounded, color: c, size: 18),
                    ),
                  ),
                ]),
              )),
            ]),
            if (!_hexValid) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFE05C5C), size: 14),
                const SizedBox(width: 6),
                Text('Enter a valid 6-character hex code',
                    style: GoogleFonts.dmSans(fontSize: 11.5, color: const Color(0xFFE05C5C),
                        fontWeight: FontWeight.w600)),
              ]),
            ],
          ]),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  RGB READOUT  — gradient bars are now draggable sliders
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRgbReadout() {
    return RepaintBoundary(
      child: ValueListenableBuilder<HSVColor>(
        valueListenable: _colorNotifier,
        builder: (_, hsv, __) {
          final c   = hsv.toColor();
          final hsl = HSLColor.fromColor(c);
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _brd, width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 3, height: 12,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('CHANNEL VALUES', style: GoogleFonts.dmSans(
                    fontSize: 10, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
              ]),
              const SizedBox(height: 16),
              _gradientBar('Red',   c.red,   const Color(0xFFE53935),
                  onChanged: (v) => _setRgbFast(v, c.green, c.blue)),
              const SizedBox(height: 10),
              _gradientBar('Green', c.green, const Color(0xFF43A047),
                  onChanged: (v) => _setRgbFast(c.red, v, c.blue)),
              const SizedBox(height: 10),
              _gradientBar('Blue',  c.blue,  const Color(0xFF1E88E5),
                  onChanged: (v) => _setRgbFast(c.red, c.green, v)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.05), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withOpacity(0.12)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _hslChip('Hue',   '${hsl.hue.round()}°'),
                  Container(width: 1, height: 28, color: _brd),
                  _hslChip('Sat',   '${(hsl.saturation*100).round()}%'),
                  Container(width: 1, height: 28, color: _brd),
                  _hslChip('Light', '${(hsl.lightness*100).round()}%'),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _gradientBar(String label, int val, Color barColor,
      {void Function(int)? onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: barColor)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: barColor.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
          child: Text('$val', style: GoogleFonts.spaceGrotesk(
              fontSize: 11, fontWeight: FontWeight.w800, color: barColor)),
        ),
      ]),
      const SizedBox(height: 6),
      if (onChanged != null)
        _InteractiveSliderBar(
          fraction: val/255, barColor: barColor, bgColor: _brd,
          onChanged: (f) => onChanged((f*255).round()),
        )
      else
        LayoutBuilder(builder: (ctx, box) => Stack(children: [
          Container(height: 8, decoration: BoxDecoration(color: _brd, borderRadius: BorderRadius.circular(4))),
          Container(height: 8, width: box.maxWidth * val / 255,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [barColor.withOpacity(0.4), barColor]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: barColor.withOpacity(0.35), blurRadius: 6, offset: const Offset(0,2))],
              )),
        ])),
    ]);
  }

  Widget _hslChip(String label, String val) => Column(children: [
    Text(label, style: GoogleFonts.dmSans(fontSize: 9.5, fontWeight: FontWeight.w600, color: _sub)),
    const SizedBox(height: 3),
    Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w800, color: _txt)),
  ]);

  // ══════════════════════════════════════════════════════════════════════════
  //  DARK / LIGHT TOGGLE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDarkLightToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brd, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ValueListenableBuilder<HSVColor>(valueListenable: _colorNotifier, builder: (_, hsv, __) =>
            Row(children: [
              Container(width: 3, height: 12, decoration: BoxDecoration(
                  color: hsv.toColor(), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('BASE VARIANT', style: GoogleFonts.dmSans(
                  fontSize: 10, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
            ])),
        const SizedBox(height: 4),
        Text('Choose how your colour applies to the app base',
            style: GoogleFonts.dmSans(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _variantTile(true)),
          const SizedBox(width: 12),
          Expanded(child: _variantTile(false)),
        ]),
      ]),
    );
  }

  Widget _variantTile(bool dark) {
    final sel = _isDark == dark;
    return ValueListenableBuilder<HSVColor>(
      valueListenable: _colorNotifier,
      builder: (_, hsv, __) {
        final c         = hsv.toColor();
        final previewBg = dark ? Color.lerp(c, Colors.black, 0.82)! : Color.lerp(c, Colors.white, 0.90)!;
        final previewAc = dark
            ? HSLColor.fromColor(c).withLightness(0.62).toColor()
            : HSLColor.fromColor(c).withLightness(0.38).toColor();
        return GestureDetector(
          onTap: () { setState(() => _isDark = dark); HapticFeedback.selectionClick(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(0.09) : _bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sel ? c.withOpacity(0.65) : _brd, width: sel ? 2 : 1.5),
              boxShadow: sel
                  ? [BoxShadow(color: c.withOpacity(0.20), blurRadius: 14, offset: const Offset(0,5))]
                  : [],
            ),
            child: Column(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: dark
                        ? [previewBg, Color.lerp(previewBg, previewAc, 0.40)!]
                        : [previewBg, Color.lerp(previewBg, previewAc, 0.20)!],
                  )),
                  child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                    Container(width: 20, height: 20,
                        decoration: BoxDecoration(color: previewAc.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(6)),
                        child: Icon(dark ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
                            color: previewAc, size: 12)),
                    const SizedBox(width: 6),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(height: 3, width: 30, decoration: BoxDecoration(
                              color: dark ? Colors.white.withOpacity(0.75) : previewAc.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 4),
                          Container(height: 2, width: 20, decoration: BoxDecoration(
                              color: dark ? Colors.white.withOpacity(0.35) : previewAc.withOpacity(0.30),
                              borderRadius: BorderRadius.circular(2))),
                        ])),
                  ])),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12,10,12,12),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dark ? 'Dark Mode' : 'Light Mode', style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w800, color: sel ? c : _txt)),
                    Text(dark ? 'Deep dark base' : 'Bright light base',
                        style: GoogleFonts.dmSans(fontSize: 10.5, color: _sub, fontWeight: FontWeight.w500)),
                  ])),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                        color: sel ? c : _brd.withOpacity(0.5), shape: BoxShape.circle),
                    child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LIVE PREVIEW  — overflow fixed with ClipRect
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildLivePreview() {
    return RepaintBoundary(
      child: ValueListenableBuilder<HSVColor>(
        valueListenable: _colorNotifier,
        builder: (_, hsv, __) => _livePreviewContent(hsv.toColor()),
      ),
    );
  }

  Widget _livePreviewContent(Color c) {
    Color setL(Color col, double l, double s) =>
        HSLColor.fromColor(col).withLightness(l.clamp(0,1)).withSaturation(s.clamp(0,1)).toColor();
    final prevBg     = _isDark ? setL(c,0.06,0.20) : setL(c,0.97,0.10);
    final prevCard   = _isDark ? setL(c,0.12,0.22) : Colors.white;
    final prevAcc    = _isDark
        ? HSLColor.fromColor(c).withLightness(HSLColor.fromColor(c).lightness.clamp(0.52,0.72)).toColor()
        : HSLColor.fromColor(c).withLightness(HSLColor.fromColor(c).lightness.clamp(0.30,0.50)).toColor();
    final prevTxt    = _isDark ? Colors.white : setL(c,0.12,0.40);
    final prevSub    = _isDark ? prevAcc.withOpacity(0.55) : setL(c,0.42,0.35);
    final prevBorder = _isDark ? setL(c,0.20,0.30) : setL(c,0.86,0.28);
    final gradStart  = _isDark ? setL(c,0.08,0.50) : setL(c,0.28,0.65);
    final gradEnd    = _isDark ? setL(c,0.22,0.72) : setL(c,0.44,0.76);

    return Container(
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brd, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16,14,16,0),
          child: Row(children: [
            Container(width: 3, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text('LIVE PREVIEW', style: GoogleFonts.dmSans(
                fontSize: 10, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_isDark ? '  Dark' : '  Light',
                  style: GoogleFonts.dmSans(fontSize: 9.5, fontWeight: FontWeight.w700, color: _sub)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(14,0,14,14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ClipRect(   // ← eliminates the overflow assertion
              child: Container(
                height: 290,
                decoration: BoxDecoration(color: prevBg, border: Border.all(color: prevBorder, width: 1)),
                child: Column(children: [
                  // ── Header gradient ──
                  Container(
                    decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [gradStart, gradEnd])),
                    padding: const EdgeInsets.fromLTRB(12,12,12,0),
                    child: Column(children: [
                      Row(children: [
                        Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.menu_rounded, color: Colors.white, size: 12)),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 5, width: 65, decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(3))),
                          const SizedBox(height: 4),
                          Container(height: 3, width: 45, decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.45), borderRadius: BorderRadius.circular(2))),
                        ])),
                        Container(width: 22, height: 22,
                            decoration: BoxDecoration(color: prevAcc, shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: prevAcc.withOpacity(0.5), blurRadius: 6)])),
                      ]),
                      const SizedBox(height: 10),
                      // Nav pills
                      SizedBox(height: 36, child: ListView.separated(
                        scrollDirection: Axis.horizontal, itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) => Container(
                          width: 56, height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Container(height: 4, width: 18, decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 3),
                            Container(height: 3, width: 26, decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.45), borderRadius: BorderRadius.circular(2))),
                          ]),
                        ),
                      )),
                      const SizedBox(height: 10),
                      // Search bar
                      Container(height: 28,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: Colors.white.withOpacity(0.16))),
                          child: Row(children: [
                            const SizedBox(width: 8),
                            Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.45), size: 12),
                            const SizedBox(width: 5),
                            Container(height: 3, width: 55, decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.32), borderRadius: BorderRadius.circular(2))),
                          ])),
                      const SizedBox(height: 10),
                    ]),
                  ),
                  // ── Body content ─────────────────────────────────────────
                  Expanded(child: Container(
                    color: prevBg, padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      // Stat cards
                      Row(children: List.generate(3, (i) => Expanded(child: Container(
                        margin: EdgeInsets.only(left: i==0?0:6),
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Color.lerp(prevAcc, Colors.black, 0.20+i*0.08)!,
                            Color.lerp(prevAcc, Colors.black, 0.08+i*0.06)!,
                          ]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: prevAcc.withOpacity(0.25), blurRadius: 6, offset: const Offset(0,2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 4, width: 14, decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.70), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 4),
                          Container(height: 7, width: 20, decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.88), borderRadius: BorderRadius.circular(2))),
                        ]),
                      )))),
                      const SizedBox(height: 6),
                      // Single appointment tile
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(color: prevCard, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: prevBorder)),
                        child: Row(children: [
                          Container(width: 26, height: 26,
                              decoration: BoxDecoration(color: prevAcc.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(7)),
                              child: Center(child: Container(width: 9, height: 9,
                                  decoration: BoxDecoration(color: prevAcc, shape: BoxShape.circle)))),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(height: 4, width: 58, decoration: BoxDecoration(
                                color: prevTxt.withOpacity(0.8), borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 4),
                            Container(height: 3, width: 38, decoration: BoxDecoration(
                                color: prevSub.withOpacity(0.6), borderRadius: BorderRadius.circular(2))),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: prevAcc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                            child: Container(height: 3, width: 20, decoration: BoxDecoration(
                                color: prevAcc, borderRadius: BorderRadius.circular(2))),
                          ),
                        ]),
                      ),
                    ]),
                  )),
                  // ── Bottom nav ────────────────────────────────────────────
                  Container(height: 34,
                      decoration: BoxDecoration(color: prevCard, border: Border(top: BorderSide(color: prevBorder))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: List.generate(4, (i) => Container(width: 26, height: 26,
                              decoration: BoxDecoration(
                                gradient: i==0 ? LinearGradient(colors: [prevAcc, Color.lerp(prevAcc,Colors.black,0.2)!]) : null,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(child: Container(
                                  width: i==0?8:5, height: i==0?8:5,
                                  decoration: BoxDecoration(
                                      color: i==0 ? Colors.white : prevSub.withOpacity(0.45),
                                      shape: BoxShape.circle))))))),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HARMONY SECTION  — long-press any swatch to copy hex
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHarmonySection() {
    final harmonies = _harmonies;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: _brd, width: 1.5),
        ),
        child: ValueListenableBuilder<HSVColor>(
          valueListenable: _colorNotifier,
          builder: (_, hsv, __) {
            final c = hsv.toColor();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 3, height: 14,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('COLOUR HARMONIES', style: GoogleFonts.dmSans(
                      fontSize: 10.5, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
                  Text('Mathematically related colours', style: GoogleFonts.dmSans(
                      fontSize: 11, color: _sub.withOpacity(0.7), fontWeight: FontWeight.w500)),
                ])),
                Container(width: 30, height: 30, decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(color: _brd, width: 2),
                    boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 10)])),
              ]),
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(7),
                  child: SizedBox(height: 12, child: Row(
                      children: harmonies.map((h) => Expanded(child: ColoredBox(color: h))).toList()))),
            ]);
          },
        ),
      ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card.withOpacity(0.7),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          border: Border(
            left: BorderSide(color: _brd, width: 1.5),
            right: BorderSide(color: _brd, width: 1.5),
            bottom: BorderSide(color: _brd, width: 1.5),
          ),
        ),
        child: GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.85),
          itemCount: harmonies.length,
          itemBuilder: (ctx, i) {
            final hc    = harmonies[i];
            final isAct = _activeHarmony == i;
            return GestureDetector(
              onTap: () {
                final hsv = HSVColor.fromColor(hc);
                setState(() { _activeHarmony = i; _activePreset = null; });
                _setColorFull(hsv.hue, hsv.saturation, hsv.value);
                HapticFeedback.lightImpact();
                _addToRecent(hc);
              },
              onLongPress: () => _copyHex(hc),   // ← long-press = copy
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: hc, borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAct ? Colors.white.withOpacity(0.95) : Colors.transparent,
                    width: isAct ? 2.5 : 0,
                  ),
                  boxShadow: [BoxShadow(
                    color: hc.withOpacity(isAct ? 0.60 : 0.28),
                    blurRadius: isAct ? 16 : 5, offset: const Offset(0,4),
                  )],
                ),
                child: Column(children: [
                  if (isAct) Expanded(child: Center(child: Icon(Icons.check_rounded, color: _contrastText(hc), size: 20)))
                  else const Expanded(child: SizedBox.shrink()),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.30),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: Text(_harmonyLabels[i], textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PRESETS GRID  — long-press any swatch to copy hex
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPresetsGrid() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 14,
            decoration: BoxDecoration(color: _acc, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('COLOUR PRESETS', style: GoogleFonts.dmSans(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 1.2)),
          Text('64 hand-picked colours across 8 families',
              style: GoogleFonts.dmSans(fontSize: 11, color: _sub.withOpacity(0.7), fontWeight: FontWeight.w500)),
        ]),
      ]),
      const SizedBox(height: 14),
      ...List.generate(8, (fam) {
        final famColor = _presetFamilyColors[fam % _presetFamilyColors.length];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _brd, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14,12,14,10),
              decoration: BoxDecoration(
                color: famColor.withOpacity(0.07),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: _brd)),
              ),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: famColor, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: famColor.withOpacity(0.5), blurRadius: 5)])),
                const SizedBox(width: 8),
                Text(_presetFamilies[fam], style: GoogleFonts.dmSans(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: _txt)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: famColor.withOpacity(0.10), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: famColor.withOpacity(0.25)),
                  ),
                  child: Text('8 colours', style: GoogleFonts.dmSans(
                      fontSize: 9.5, fontWeight: FontWeight.w700, color: famColor)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8,
                children: List.generate(8, (j) {
                  final i     = fam * 8 + j;
                  if (i >= _presets.length) return const SizedBox.shrink();
                  final pc    = _presets[i];
                  final isAct = _activePreset == i;
                  return GestureDetector(
                    onTap: () => _pickPreset(i),
                    onLongPress: () => _copyHex(pc),  // ← long-press = copy
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: pc, borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAct ? Colors.white.withOpacity(0.95) : pc.withOpacity(0.25),
                          width: isAct ? 2.5 : 1,
                        ),
                        boxShadow: [BoxShadow(
                          color: pc.withOpacity(isAct ? 0.65 : 0.22),
                          blurRadius: isAct ? 16 : 4, offset: const Offset(0,3),
                        )],
                      ),
                      child: isAct ? Center(child: Icon(Icons.check_rounded, color: _contrastText(pc), size: 18)) : null,
                    ),
                  );
                }),
              ),
            ),
          ]),
        );
      }),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  APPLY BAR
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildApplyBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _brd, width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0,-4))],
      ),
      child: ValueListenableBuilder<HSVColor>(
        valueListenable: _colorNotifier,
        builder: (_, hsv, __) {
          final c   = hsv.toColor();
          final ct  = _contrastText(c);
          final hex = c.value.toRadixString(16).substring(2).toUpperCase();
          final dark = Color.lerp(c, Colors.black, 0.28)!;
          return Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 56, padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _bg, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _brd, width: 1.5),
                ),
                child: Center(child: Text('Cancel', style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _sub))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: _apply,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [dark, c]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: c.withOpacity(0.55), blurRadius: 20, offset: const Offset(0,7)),
                    BoxShadow(color: dark.withOpacity(0.25), blurRadius: 8, offset: const Offset(0,2)),
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 28, height: 28,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                      child: Icon(Icons.palette_rounded, color: ct, size: 16)),
                  const SizedBox(width: 10),
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Apply Theme', style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w900, color: ct)),
                    Text('#$hex  •  ${_isDark ? "Dark" : "Light"}',
                        style: GoogleFonts.dmSans(fontSize: 10.5, fontWeight: FontWeight.w600,
                            color: ct.withOpacity(0.65), letterSpacing: 0.5)),
                  ]),
                ]),
              ),
            )),
          ]);
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  GLASS BUTTON
// ═════════════════════════════════════════════════════════════════════════════
class _PickerGlassBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PickerGlassBtn({required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Center(child: child),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  INTERACTIVE SLIDER BAR
//  Tap = jump to position.  Horizontal drag = scrub from start fraction.
// ═════════════════════════════════════════════════════════════════════════════
class _InteractiveSliderBar extends StatefulWidget {
  final double fraction;
  final Color barColor;
  final Color bgColor;
  final void Function(double) onChanged;
  const _InteractiveSliderBar({
    required this.fraction,
    required this.barColor,
    required this.bgColor,
    required this.onChanged,
  });
  @override
  State<_InteractiveSliderBar> createState() => _InteractiveSliderBarState();
}

class _InteractiveSliderBarState extends State<_InteractiveSliderBar> {
  double? _startFrac;
  double  _delta    = 0;
  double  _width    = 1;

  void _onDragStart(DragStartDetails d) {
    _startFrac = widget.fraction;
    _delta     = 0;
    HapticFeedback.selectionClick();
  }
  void _onDragUpdate(DragUpdateDetails d) {
    if (_startFrac == null) return;
    _delta += d.delta.dx;
    widget.onChanged((_startFrac! + _delta / _width).clamp(0.0, 1.0));
  }
  void _onDragEnd(DragEndDetails _) { _startFrac = null; _delta = 0; }
  void _onTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    widget.onChanged((d.localPosition.dx / _width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final frac = widget.fraction.clamp(0.0, 1.0);
    return LayoutBuilder(builder: (ctx, box) {
      _width = (box.maxWidth > 0 && box.maxWidth.isFinite) ? box.maxWidth : 1;
      final thumbL = (_width * frac - 6).clamp(0.0, _width - 12.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTap,
        onHorizontalDragStart:  _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd:    _onDragEnd,
        child: SizedBox(
          height: 24,
          child: Center(
            child: SizedBox(
              height: 8,
              child: Stack(clipBehavior: Clip.none, children: [
                // Track background
                Container(decoration: BoxDecoration(
                    color: widget.bgColor, borderRadius: BorderRadius.circular(4))),
                // Filled section
                FractionallySizedBox(widthFactor: frac,
                  child: Container(decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [widget.barColor.withOpacity(0.5), widget.barColor]),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(color: widget.barColor.withOpacity(0.35), blurRadius: 4)],
                  )),
                ),
                // Thumb
                Positioned(left: thumbL, top: -4,
                  child: Container(width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle,
                      border: Border.all(color: widget.barColor, width: 2),
                      boxShadow: [BoxShadow(color: widget.barColor.withOpacity(0.45),
                          blurRadius: 6, offset: const Offset(0,2))],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STATIC BAR  (read-only visual — no gesture)
// ═════════════════════════════════════════════════════════════════════════════
class _StaticBar extends StatelessWidget {
  final double fraction;
  final Color barColor;
  final Color bgColor;
  const _StaticBar({required this.fraction, required this.barColor, required this.bgColor});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Stack(children: [
      Container(height: 6, color: bgColor),
      FractionallySizedBox(widthFactor: fraction.clamp(0,1),
        child: Container(height: 6, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [barColor.withOpacity(0.5), barColor]),
          borderRadius: BorderRadius.circular(4),
        )),
      ),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  HUE STRIP SLIDER
//  Full-spectrum horizontal hue bar — tap or drag to set hue precisely.
// ═════════════════════════════════════════════════════════════════════════════
class _HueStripSlider extends StatefulWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueStripSlider({required this.hue, required this.onChanged});
  @override
  State<_HueStripSlider> createState() => _HueStripSliderState();
}
class _HueStripSliderState extends State<_HueStripSlider> {
  double _width = 1;
  void _handle(Offset local) =>
      widget.onChanged((local.dx / _width).clamp(0.0,1.0) * 360);
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      _width = (box.maxWidth > 0 && box.maxWidth.isFinite) ? box.maxWidth : 1;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) { HapticFeedback.selectionClick(); _handle(d.localPosition); },
        onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
        onHorizontalDragUpdate: (d) => _handle(d.localPosition),
        child: SizedBox(height: 28, width: double.infinity,
            child: CustomPaint(painter: _HueStripPainter(hue: widget.hue))),
      );
    });
  }
}

class _HueStripPainter extends CustomPainter {
  final double hue;
  _HueStripPainter({required this.hue});
  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 12.0;
    final trackY  = (size.height - trackH) / 2;
    final rect    = Rect.fromLTWH(0, trackY, size.width, trackH);
    final rr      = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    final colors  = List.generate(13, (i) => HSVColor.fromAHSV(1, (i*30.0)%360, 1, 1).toColor());
    canvas.drawRRect(rr, Paint()..shader = LinearGradient(colors: colors).createShader(rect));
    canvas.drawRRect(rr, Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke ..strokeWidth = 1);
    final tx         = size.width * hue / 360;
    final ty         = size.height / 2;
    final thumbColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawCircle(Offset(tx,ty), 11, Paint()
      ..color = thumbColor.withOpacity(0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(Offset(tx,ty), 9, Paint()..color = thumbColor);
    canvas.drawCircle(Offset(tx,ty), 9, Paint()
      ..color = Colors.white ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
    canvas.drawCircle(Offset(tx,ty), 9, Paint()
      ..color = Colors.black.withOpacity(0.22) ..style = PaintingStyle.stroke ..strokeWidth = 1);
  }
  @override bool shouldRepaint(_HueStripPainter o) => o.hue != hue;
}

// ═════════════════════════════════════════════════════════════════════════════
//  BLENDER COLOR WHEEL
// ═════════════════════════════════════════════════════════════════════════════
class _BlenderColorWheel extends StatefulWidget {
  final double hue, sat, val;
  final void Function(double hue, double sat) onChanged;
  const _BlenderColorWheel({required this.hue, required this.sat, required this.val, required this.onChanged});
  @override State<_BlenderColorWheel> createState() => _BlenderColorWheelState();
}
class _BlenderColorWheelState extends State<_BlenderColorWheel> {
  final ValueNotifier<Offset> _indicator = ValueNotifier(Offset.zero);
  Size _sz = Size.zero;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _sync()); }
  @override void didUpdateWidget(_BlenderColorWheel old) {
    super.didUpdateWidget(old);
    if (old.hue != widget.hue || old.sat != widget.sat) _sync();
  }
  void _sync() {
    if (_sz == Size.zero) return;
    _indicator.value = _toOffset(widget.hue, widget.sat, _sz);
  }
  static Offset _toOffset(double hue, double sat, Size size) {
    final cx = size.width/2; final cy = size.height/2;
    final r  = math.min(cx,cy) - 1;
    final rad = hue * math.pi / 180;
    return Offset(cx + r*sat*math.cos(rad), cy + r*sat*math.sin(rad));
  }
  void _handle(Offset local) {
    final cx = _sz.width/2; final cy = _sz.height/2;
    final r  = math.min(cx,cy) - 1;
    final dx = local.dx-cx; final dy = local.dy-cy;
    final dist = math.sqrt(dx*dx + dy*dy);
    final sat  = (dist/r).clamp(0.0,1.0);
    double angle = math.atan2(dy,dx) * 180 / math.pi;
    if (angle < 0) angle += 360;
    _indicator.value = Offset(
      cx + r*sat*math.cos(angle*math.pi/180),
      cy + r*sat*math.sin(angle*math.pi/180),
    );
    widget.onChanged(angle, sat);
  }
  @override void dispose() { _indicator.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      _sz = Size(box.maxWidth, box.maxHeight);
      if (_indicator.value == Offset.zero) _indicator.value = _toOffset(widget.hue, widget.sat, _sz);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart:  (d) => _handle(d.localPosition),
        onPanUpdate: (d) => _handle(d.localPosition),
        onTapDown:   (d) { HapticFeedback.selectionClick(); _handle(d.localPosition); },
        child: SizedBox.expand(child: Stack(children: [
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _WheelPainter(widget.val)))),
          Positioned.fill(child: RepaintBoundary(child: ValueListenableBuilder<Offset>(
            valueListenable: _indicator,
            builder: (_, pos, __) => CustomPaint(painter: _WheelIndicatorPosPainter(pos)),
          ))),
        ])),
      );
    });
  }
}

class _WheelPainter extends CustomPainter {
  final double val;
  _WheelPainter(this.val);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2; final cy = size.height/2;
    final radius = math.min(cx,cy) - 1;
    final center = Offset(cx,cy);
    final rect   = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final hueColors = <Color>[];
    for (int i = 0; i <= 360; i += 30) hueColors.add(HSVColor.fromAHSV(1, (i%360).toDouble(), 1, 1).toColor());
    canvas.drawRect(Offset.zero & size, Paint()..shader = SweepGradient(
        colors: hueColors, startAngle: 0, endAngle: 2*math.pi).createShader(rect));
    canvas.drawRect(Offset.zero & size, Paint()..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withOpacity(0)], stops: const [0.0,1.0]).createShader(rect));
    if (val < 1.0) canvas.drawRect(Offset.zero & size,
        Paint()..color = Colors.black.withOpacity((1-val).clamp(0.0,1.0)));
    canvas.restore();
    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.white.withOpacity(0.12) ..style = PaintingStyle.stroke ..strokeWidth = 1.5);
  }
  @override bool shouldRepaint(_WheelPainter o) => o.val != val;
}

class _WheelIndicatorPosPainter extends CustomPainter {
  final Offset pos;
  _WheelIndicatorPosPainter(this.pos);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(pos, 14, Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(pos, 10, Paint()..color = Colors.white ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
    canvas.drawCircle(pos, 10, Paint()..color = Colors.black.withOpacity(0.22) ..style = PaintingStyle.stroke ..strokeWidth = 1);
  }
  @override bool shouldRepaint(_WheelIndicatorPosPainter o) => o.pos != pos;
}

// ═════════════════════════════════════════════════════════════════════════════
//  BLENDER VALUE SLIDER  — vertical brightness bar
// ═════════════════════════════════════════════════════════════════════════════
class _BlenderValueSlider extends StatelessWidget {
  final double hue, sat, val;
  final ValueChanged<double> onChanged;
  const _BlenderValueSlider({required this.hue, required this.sat, required this.val, required this.onChanged});
  void _handle(Offset local, double height) => onChanged((1.0 - local.dy/height).clamp(0.0,1.0));
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final h = box.maxHeight;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart:  (d) => _handle(d.localPosition, h),
        onPanUpdate: (d) => _handle(d.localPosition, h),
        onTapDown:   (d) { HapticFeedback.selectionClick(); _handle(d.localPosition, h); },
        child: SizedBox(width: box.maxWidth, height: h,
            child: CustomPaint(painter: _ValueSliderPainter(hue: hue, sat: sat, val: val))),
      );
    });
  }
}

class _ValueSliderPainter extends CustomPainter {
  final double hue, sat, val;
  _ValueSliderPainter({required this.hue, required this.sat, required this.val});
  @override
  void paint(Canvas canvas, Size size) {
    final fullColor = HSVColor.fromAHSV(1, hue, sat, 1).toColor();
    const trackW = 12.0;
    final tx     = size.width/2 - trackW/2;
    final trackR = Rect.fromLTWH(tx, 0, trackW, size.height);
    final rr     = RRect.fromRectAndRadius(trackR, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [fullColor, Colors.black]).createShader(trackR));
    canvas.drawRRect(rr, Paint()
      ..color = Colors.white.withOpacity(0.10) ..style = PaintingStyle.stroke ..strokeWidth = 1.2);
    final ty       = (1-val) * size.height;
    final thumbClr = HSVColor.fromAHSV(1, hue, sat, val).toColor();
    canvas.drawCircle(Offset(size.width/2, ty), 12, Paint()
      ..color = thumbClr.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(Offset(size.width/2, ty), 9, Paint()..color = thumbClr);
    canvas.drawCircle(Offset(size.width/2, ty), 9, Paint()
      ..color = Colors.white ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
    canvas.drawCircle(Offset(size.width/2, ty), 9, Paint()
      ..color = Colors.black.withOpacity(0.18) ..style = PaintingStyle.stroke ..strokeWidth = 1);
  }
  @override bool shouldRepaint(_ValueSliderPainter o) => o.hue != hue || o.sat != sat || o.val != val;
}