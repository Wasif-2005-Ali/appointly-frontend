import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../theme/dark_theme.dart';
import '../user_session.dart';
import '../database/bd_helper.dart';
import '../widgets/image_crop_dialog.dart';
import '../widgets/save_icon_button.dart';
import '../widgets/save_success_overlay.dart';
import '../widgets/appointly_hand_icon.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, DarkMode {

  final _cs = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) { super.setState(fn); _cs.value++; }

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  bool _isEditing = true;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  final _bioCtrl = TextEditingController(
      text: 'Professional service provider with 6+ years of experience. Passionate about delivering excellence.');

  String _selectedStatus = 'Available';
  String _privacyMode    = 'Public';
  bool   _leaveEnabled   = false;
  DateTime _leaveFrom    = DateTime.now();
  DateTime _leaveTo      = DateTime.now().add(const Duration(days: 1));
  bool _showAccessibility = false;

  // ── Draggable FAB position (right, bottom offsets) ────────────────────────
  late ValueNotifier<Offset> _fabPosNotifier;
  static const double _kFabRight  = 16.0;
  static const double _kFabBottom = 80.0;

  final List<Map<String,dynamic>> _allContacts = [
    {'name':'Aisha Khan',     'sel':true},
    {'name':'Omar Farooq',    'sel':true},
    {'name':'Bilal Chaudhry', 'sel':false},
    {'name':'Zara Malik',     'sel':false},
    {'name':'Hina Raza',      'sel':true},
    {'name':'Tariq Ahmed',    'sel':false},
  ];

  String get _initials {
    final p = _nameCtrl.text.trim().split(' ');
    return p.length >= 2 ? '${p.first[0]}${p.last[0]}'.toUpperCase() : (p.first.isNotEmpty ? p.first[0].toUpperCase() : '?');
  }

  // ── Profile photo via image_picker + circular crop ────────────────────────
  Future<void> _pickProfilePhoto() async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      // Show the circular crop/frame selector
      final cropped = await showImageCropDialog(
        context: context,
        imageBytes: bytes,
      );

      if (cropped != null && mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          UserSession.instance.profileImageBytes = cropped;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open gallery. Please grant photo permission.',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFE05C5C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    final s    = UserSession.instance;
    _nameCtrl  = TextEditingController(text: s.fullName);
    _emailCtrl = TextEditingController(text: s.email);
    _phoneCtrl = TextEditingController(text: s.phone);
    if (s.bio.isNotEmpty) _bioCtrl.text = s.bio;
    _selectedStatus = s.profileStatus.isNotEmpty ? s.profileStatus : 'Available';
    _privacyMode    = s.privacyMode.isNotEmpty   ? s.privacyMode   : 'Public';
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _fabPosNotifier = ValueNotifier(const Offset(_kFabRight, _kFabBottom));
  }

  @override
  void dispose() {
    _cs.dispose();
    _ctrl.dispose();
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _bioCtrl.dispose();
    _fabPosNotifier.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month-1]} ${d.year}';
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    final appState = AppStateProvider.of(context);
    final bright = appState.themeMode.isDark ? Brightness.dark : Brightness.light;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData(brightness: bright).copyWith(
          colorScheme: ColorScheme(
            brightness: bright, primary: appState.accent, onPrimary: Colors.white,
            secondary: appState.accent, onSecondary: Colors.white,
            error: Colors.red, onError: Colors.white,
            surface: appState.cardBg, onSurface: appState.txtMain,
          ),
          dialogBackgroundColor: appState.cardBg,
        ),
        child: child!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: dmBg,
      body: Stack(children: [
        Column(children: [
          _buildHero(),
          Expanded(child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: _buildAvatarCard()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildStatsRow(),
                      const SizedBox(height: 16),
                      RepaintBoundary(child: _buildStatusCard()),
                      const SizedBox(height: 16),
                      RepaintBoundary(child: _buildPrivacyCard()),
                      const SizedBox(height: 16),
                      RepaintBoundary(child: _buildLeaveTimeCard()),
                      const SizedBox(height: 16),
                      _buildInfoCard(),
                      const SizedBox(height: 16),
                      _buildBioCard(),
                      const SizedBox(height: 16),
                      RepaintBoundary(child: _buildServicesCard()),
                      const SizedBox(height: 16),
                      RepaintBoundary(child: _buildReviewsCard()),
                      const SizedBox(height: 80),
                    ]),
                  ),
                ),
              ],
            ),
          ))),
        ]),
        _buildAccessibilityFAB(),
      ]),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────────────
  Widget _buildHero() => Container(
    decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: AppStateProvider.of(context).heroGradient)),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
            child: _glass(child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18))),
        const SizedBox(width: 14),
        Expanded(child: Text('My Profile', style: GoogleFonts.dmSans(
            fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3))),
        // Save icon button — top right (white so it pops on any theme gradient)
        SaveIconButton(
          changeSignal: _cs,
          foregroundColor: Colors.white,
          onSave: () async {
            final uid = UserSession.instance.userId;
            if (uid == null) return;
            // Persist all profile fields to SQLite
            await DBHelper.instance.updateUserProfile(
              uid,
              name:          _nameCtrl.text.trim(),
              phone:         _phoneCtrl.text.trim(),
              bio:           _bioCtrl.text.trim(),
              profileStatus: _selectedStatus,
              privacyMode:   _privacyMode,
              profileImage:  UserSession.instance.profileImageBytes,
            );
            // Update in-memory session
            UserSession.instance.fullName      = _nameCtrl.text.trim();
            UserSession.instance.phone         = _phoneCtrl.text.trim();
            UserSession.instance.bio           = _bioCtrl.text.trim();
            UserSession.instance.profileStatus = _selectedStatus;
            UserSession.instance.privacyMode   = _privacyMode;
          },
        ),
      ]),
    )),
  );

  // ── AVATAR CARD (no overlap with header) ──────────────────────────────────
  Widget _buildAvatarCard() {
    final imgBytes = UserSession.instance.profileImageBytes;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: dmCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        // ── Avatar with tap-to-change ────────────────────────────────────
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Stack(alignment: Alignment.bottomRight, children: [
            // Gradient ring outer
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    dmAccent,
                    dmAccent.withOpacity(0.5),
                    AppColors.green.withOpacity(0.7),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: dmAccent.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
                  BoxShadow(color: AppColors.green.withOpacity(0.15), blurRadius: 12, spreadRadius: 2),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(3.5),   // ring thickness
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dmCard,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: CircleAvatar(
                      radius: 47,
                      backgroundColor: dmAccent.withOpacity(0.15),
                      child: imgBytes != null
                        ? ClipOval(
                            child: Image.memory(
                              imgBytes,
                              width: 94,
                              height: 94,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Text(_initials, style: GoogleFonts.dmSans(
                            fontSize: 30, fontWeight: FontWeight.w900, color: dmAccent)),
                    ),
                  ),
                ),
              ),
            ),
            // Camera badge
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.green, const Color(0xFF1A9E5C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: dmCard, width: 2.5),
                boxShadow: [BoxShadow(color: AppColors.green.withOpacity(0.45), blurRadius: 10, offset: const Offset(0,3))],
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
            ),
          ]),
        ),

        const SizedBox(height: 16),
        Text(_nameCtrl.text, style: GoogleFonts.dmSans(
            fontSize: 22, fontWeight: FontWeight.w900, color: dmTxtMain, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('Admin · Appointly', style: GoogleFonts.dmSans(
            fontSize: 13, color: dmTxtSub, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),

        // Privacy badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _privacyColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _privacyColor.withOpacity(0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_privacyIcon, size: 13, color: _privacyColor),
            const SizedBox(width: 5),
            Text(_privacyMode, style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w700, color: _privacyColor)),
          ]),
        ),

        const SizedBox(height: 20),

        // ── LinkedIn-style Message & Call buttons ─────────────────────────
        Row(children: [
          Expanded(child: _actionBtn(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Message',
            gradient: [dmAccent, const Color(0xFF1565C0)],
            textColor: Colors.white,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Chat coming soon!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              backgroundColor: dmAccent, behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
          )),
          const SizedBox(width: 10),
          Expanded(child: _outlineBtn(
            icon: Icons.phone_outlined,
            label: 'Call',
            color: AppColors.green,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Call coming soon!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              backgroundColor: AppColors.green, behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
          )),
        ]),
      ]),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required Color textColor,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: gradient.last.withOpacity(0.4),
          blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: textColor, size: 18),
        const SizedBox(width: 7),
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
      ]),
    ),
  );

  Widget _outlineBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 7),
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]),
    ),
  );

  // ── STATUS CARD ───────────────────────────────────────────────────────────
  Widget _buildStatusCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _cardTitle('Status', Icons.circle_rounded, dmAccent),
    const SizedBox(height: 14),
    Row(children: [
      _statusChip('Available', AppColors.green,   Icons.check_circle_rounded),
      const SizedBox(width: 8),
      _statusChip('Busy',      AppColors.warning, Icons.do_not_disturb_rounded),
      const SizedBox(width: 8),
      _statusChip('Leave',     const Color(0xFF8AA0BC), Icons.beach_access_rounded),
    ]),
  ]));

  Widget _statusChip(String label, Color color, IconData icon) {
    final sel = _selectedStatus == label;
    return Expanded(child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedStatus = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: sel ? LinearGradient(colors: [color.withOpacity(0.9), color]) : null,
          color: sel ? null : dmCard2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? color : dmBorder, width: sel ? 1.5 : 1),
          boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0,3))] : [],
        ),
        child: Column(children: [
          Icon(icon, color: sel ? Colors.white : color, size: 18),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: sel ? Colors.white : dmTxtSub)),
        ]),
      ),
    ));
  }

  // ── PRIVACY ───────────────────────────────────────────────────────────────
  Color get _privacyColor {
    switch (_privacyMode) {
      case 'Public':        return const Color(0xFF2ECC96);
      case 'Contacts Only': return dmAccent;
      case 'Protected':     return AppColors.warning;
      case 'Private':       return const Color(0xFFE05C5C);
      default:              return dmAccent;
    }
  }
  IconData get _privacyIcon {
    switch (_privacyMode) {
      case 'Public':        return Icons.public_rounded;
      case 'Contacts Only': return Icons.people_rounded;
      case 'Protected':     return Icons.verified_user_rounded;
      case 'Private':       return Icons.lock_rounded;
      default:              return Icons.public_rounded;
    }
  }

  Widget _buildPrivacyCard() {
    final modes = [
      {'label':'Public',        'icon':Icons.public_rounded,         'color':const Color(0xFF2ECC96),  'desc':'Anyone can send you appointment requests'},
      {'label':'Contacts Only', 'icon':Icons.people_rounded,         'color':const Color(0xFF4A90D9),  'desc':'Only people in your contacts can book'},
      {'label':'Protected',     'icon':Icons.verified_user_rounded,  'color':const Color(0xFFF4A24A),  'desc':'Only selected people can send requests'},
      {'label':'Private',       'icon':Icons.lock_rounded,           'color':const Color(0xFFE05C5C),  'desc':'No one can send requests — you initiate only'},
    ];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Privacy Mode', Icons.privacy_tip_outlined, _privacyColor),
      const SizedBox(height: 14),
      ...modes.map((m) {
        final sel = _privacyMode == m['label'];
        final c = m['color'] as Color;
        return GestureDetector(
          onTap: () => setState(() => _privacyMode = m['label'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(0.1) : dmCard2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? c.withOpacity(0.5) : dmBorder, width: sel ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: sel ? LinearGradient(colors: [c.withOpacity(0.8), c]) : null,
                  color: sel ? null : dmCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? c : dmBorder),
                ),
                child: Icon(m['icon'] as IconData, color: sel ? Colors.white : c, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['label'] as String, style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: sel ? c : dmTxtMain)),
                const SizedBox(height: 2),
                Text(m['desc'] as String, style: GoogleFonts.dmSans(
                    fontSize: 11.5, color: dmTxtSub, fontWeight: FontWeight.w500)),
              ])),
              if (sel) Icon(Icons.check_circle_rounded, color: c, size: 20),
            ]),
          ),
        );
      }),
      if (_privacyMode == 'Protected') ...[ 
        const SizedBox(height: 4),
        Container(height: 1, color: dmBorder),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.manage_accounts_rounded, size: 15, color: AppColors.warning),
          const SizedBox(width: 6),
          Text('Allowed Contacts', style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w800, color: dmTxtMain)),
          const Spacer(),
          Text('${_allContacts.where((c) => c['sel'] == true).length} selected',
              style: GoogleFonts.dmSans(fontSize: 11, color: dmTxtSub, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ..._allContacts.asMap().entries.map((e) {
          final c = e.value; final i = e.key;
          final sel = c['sel'] as bool;
          return GestureDetector(
            onTap: () => setState(() => _allContacts[i]['sel'] = !sel),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.warning.withOpacity(0.08) : dmCard2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? AppColors.warning.withOpacity(0.4) : dmBorder),
              ),
              child: Row(children: [
                CircleAvatar(radius: 15, backgroundColor: dmAccent.withOpacity(0.15),
                  child: Text((c['name'] as String).split(' ').map((w) => w[0]).join(),
                      style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: dmAccent))),
                const SizedBox(width: 10),
                Expanded(child: Text(c['name'] as String, style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: dmTxtMain))),
                AnimatedContainer(duration: const Duration(milliseconds: 150),
                  width: 22, height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: sel ? const LinearGradient(colors: [Color(0xFFE08020), Color(0xFFF4A24A)]) : null,
                    color: sel ? null : Colors.transparent,
                    border: Border.all(color: sel ? AppColors.warning : dmBorder, width: 2)),
                  child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null),
              ]),
            ),
          );
        }),
      ],
    ]));
  }

  // ── LEAVE TIME ────────────────────────────────────────────────────────────
  Widget _buildLeaveTimeCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _cardTitle('Leave Period', Icons.beach_access_rounded, const Color(0xFF4A90D9)),
      const Spacer(),
      GestureDetector(
        onTap: () => setState(() => _leaveEnabled = !_leaveEnabled),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 48, height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: _leaveEnabled ? LinearGradient(colors: [dmAccent, dmAccent.withOpacity(0.7)]) : null,
            color: _leaveEnabled ? null : dmCard2,
            border: Border.all(color: _leaveEnabled ? dmAccent : dmBorder),
          ),
          child: Stack(alignment: Alignment.center, children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              left: _leaveEnabled ? 23 : 2,
              child: Container(width: 20, height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)])),
            ),
          ]),
        ),
      ),
    ]),
    const SizedBox(height: 6),
    Text('Set a time period when you are away and unavailable',
        style: GoogleFonts.dmSans(fontSize: 12, color: dmTxtSub, fontWeight: FontWeight.w500)),
    AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _leaveEnabled ? Column(children: [
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _dateTile('From', _leaveFrom, Icons.flight_takeoff_rounded, const Color(0xFF2ECC96), () async {
            final d = await _pickDate(_leaveFrom);
            if (!mounted) return;
            if (d != null) setState(() => _leaveFrom = d);
          })),
          const SizedBox(width: 10),
          Expanded(child: _dateTile('Until', _leaveTo, Icons.flight_land_rounded, const Color(0xFFE05C5C), () async {
            final d = await _pickDate(_leaveTo);
            if (!mounted) return;
            if (d != null) setState(() => _leaveTo = d);
          })),
        ]),
      ]) : const SizedBox.shrink(),
    ),
  ]));

  Widget _dateTile(String label, DateTime date, IconData icon, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 6),
          Text(_fmtDate(date), style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w800, color: dmTxtMain)),
          const SizedBox(height: 2),
          Text('Tap to change', style: GoogleFonts.dmSans(fontSize: 10, color: dmTxtSub)),
        ]),
      ),
    );

  // ── INFO / BIO / SERVICES / REVIEWS ───────────────────────────────────────
  Widget _buildInfoCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _cardTitle('Personal Info', Icons.person_outline_rounded, dmAccent),
    const SizedBox(height: 16),
    _editField('Full Name', _nameCtrl, Icons.badge_outlined),
    const SizedBox(height: 12),
    _editField('Email Address', _emailCtrl, Icons.email_outlined),
    const SizedBox(height: 12),
    _editField('Phone Number', _phoneCtrl, Icons.phone_outlined),
  ]));

  Widget _buildBioCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _cardTitle('About Me', Icons.info_outline_rounded, dmAccent),
    const SizedBox(height: 16),
    if (_isEditing)
      TextField(controller: _bioCtrl, maxLines: 3,
          style: GoogleFonts.dmSans(fontSize: 13.5, color: dmTxtMain, fontWeight: FontWeight.w500),
          decoration: InputDecoration(filled: true, fillColor: dmCard2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: dmAccent, width: 1.5)),
              contentPadding: const EdgeInsets.all(14)))
    else
      Text(_bioCtrl.text, style: GoogleFonts.dmSans(
          fontSize: 13.5, color: dmTxtBody, fontWeight: FontWeight.w500, height: 1.6)),
  ]));

  Widget _buildServicesCard() {
    final services = ['Deep Tissue Massage','Consultation','Skin Care','Hair Coloring','Physiotherapy'];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Services Offered', Icons.medical_services_outlined, dmAccent),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: services.map((s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: dmAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dmAccent.withOpacity(0.25))),
        child: Text(s, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: dmAccent)),
      )).toList()),
    ]));
  }

  Widget _buildReviewsCard() {
    final reviews = [
      {'name':'Aisha Khan','text':'Amazing experience! Very professional.','rating':5,'ac':const Color(0xFF4A90D9),'bg':const Color(0xFF1A2A40)},
      {'name':'Omar Farooq','text':'Highly recommend. Excellent service!','rating':5,'ac':const Color(0xFF2ECC96),'bg':const Color(0xFF0F2820)},
      {'name':'Zara Malik','text':'Great attention to detail. Will come again.','rating':4,'ac':const Color(0xFFF4A24A),'bg':const Color(0xFF2A1E0A)},
    ];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _cardTitle('Recent Reviews', Icons.star_outline_rounded, AppColors.warning),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
          child: Row(children: [const Icon(Icons.star_rounded, color: AppColors.warning, size: 14), const SizedBox(width: 4),
            Text('4.9', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warning))])),
      ]),
      const SizedBox(height: 16),
      ...reviews.map((r) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(14), border: Border.all(color: dmBorder2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 16, backgroundColor: (r['bg'] as Color),
                child: Text((r['name'] as String).split(' ').map((w) => w[0]).join(),
                    style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: r['ac'] as Color))),
            const SizedBox(width: 10),
            Expanded(child: Text(r['name'] as String, style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w700, color: dmTxtMain))),
            Row(children: List.generate(5, (i) => Icon(Icons.star_rounded, size: 13,
                color: i < (r['rating'] as int) ? AppColors.warning : dmBorder))),
          ]),
          const SizedBox(height: 8),
          Text(r['text'] as String, style: GoogleFonts.dmSans(
              fontSize: 12.5, color: dmTxtBody, fontWeight: FontWeight.w500, height: 1.5)),
        ]))),
    ]));
  }

  // ── ACCESSIBILITY FAB (draggable, quadrant-aware, theme-aware) ───────────
  Widget _buildAccessibilityFAB() {
    final appState = AppStateProvider.of(context);
    // Respect the global "show accessibility button" setting
    if (!appState.showAccessibilityButton) return const SizedBox.shrink();

    const fabSize   = 54.0;
    const margin    = 12.0;
    final mq        = MediaQuery.of(context);
    final screenW   = mq.size.width;
    final screenH   = mq.size.height;
    final statusBarH = mq.padding.top;
    final navBarH   = mq.padding.bottom;
    // Approximate stack height: Scaffold body = screen minus status bar and
    // the system nav bar (no bottom nav on this screen).
    final stackH    = screenH - statusBarH - navBarH;
    final maxRight  = screenW - fabSize - margin;
    final maxBottom = stackH  - fabSize - margin;
    const minEdge   = margin;

    return Positioned.fill(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _fabPosNotifier,
        builder: (_, fabPos, __) {
          final cr = fabPos.dx.clamp(minEdge, maxRight);
          final cb = fabPos.dy.clamp(minEdge, maxBottom);

          // FAB's actual pixel position from Stack top-left
          final fabLeft = screenW - cr - fabSize;
          final fabTop  = stackH  - cb - fabSize;

          // Quadrant: open popup toward screen centre so it stays on-screen
          final isOnLeft = fabLeft < screenW / 2;
          final isOnTop  = fabTop  < stackH  / 2;

          // ── popup panel ─────────────────────────────────────────────────
          final popupMargin = isOnTop
              ? const EdgeInsets.only(top: 10)
              : const EdgeInsets.only(bottom: 10);

          final popupPanel = AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: _showAccessibility
                ? Container(
                    width: 240,
                    margin: popupMargin,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: appState.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: appState.border, width: 1.5),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [appState.accent, appState.accent.withOpacity(0.7)]),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(child: AppointlyHandIcon(size: 16, color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        Text('Quick Access', style: GoogleFonts.dmSans(
                            fontSize: 13, fontWeight: FontWeight.w900, color: appState.txtMain)),
                      ]),
                      const SizedBox(height: 10),
                      _accessBtn(Icons.camera_alt_rounded, 'Change Photo', AppColors.green, _pickProfilePhoto),
                      const SizedBox(height: 6),
                      _accessBtn(Icons.circle_rounded, 'Status: \$_selectedStatus', _statusColor, () {
                        setState(() {
                          _selectedStatus = _selectedStatus == 'Available' ? 'Busy' : _selectedStatus == 'Busy' ? 'Leave' : 'Available';
                          _showAccessibility = false;
                        });
                      }),
                      const SizedBox(height: 6),
                      _accessBtn(_privacyIcon, 'Privacy: \$_privacyMode', _privacyColor, () {
                        setState(() {
                          final modes = ['Public','Contacts Only','Protected','Private'];
                          _privacyMode = modes[(modes.indexOf(_privacyMode) + 1) % modes.length];
                          _showAccessibility = false;
                        });
                      }),
                      const SizedBox(height: 6),
                      _accessBtn(Icons.palette_rounded, 'Theme: \${appState.themeMode.label}', const Color(0xFF9C6FE0), () {
                        final modes = AppThemeMode.values
                            .where((m) => m != AppThemeMode.customDark && m != AppThemeMode.customLight)
                            .toList();
                        final next = modes[(modes.indexOf(appState.themeMode) + 1) % modes.length];
                        appState.setTheme(next);
                        setState(() => _showAccessibility = false);
                      }),
                      const SizedBox(height: 6),
                      _accessBtn(Icons.edit_rounded, _isEditing ? 'Save Profile' : 'Edit Profile', AppColors.green, () {
                        setState(() { _isEditing = !_isEditing; _showAccessibility = false; });
                      }),
                    ]),
                  )
                : const SizedBox.shrink(),
          );

          // ── FAB button ──────────────────────────────────────────────────
          final fabButton = GestureDetector(
            onTap: () => setState(() => _showAccessibility = !_showAccessibility),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: fabSize, height: fabSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [appState.accent, appState.accent.withOpacity(0.75)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(17),
                boxShadow: [
                  BoxShadow(color: appState.accent.withOpacity(0.5), blurRadius: 18, offset: const Offset(0, 6)),
                  BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 8,  offset: const Offset(0, 3)),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
              ),
              child: Center(child: AppointlyHandIcon(
                isClose: _showAccessibility,
                size: 28, color: Colors.white,
              )),
            ),
          );

          // ── Draggable wrapper with quadrant-aware Positioned anchor ─────
          return Stack(
            children: [
              Positioned(
                left:   isOnLeft ? fabLeft    : null,
                right:  isOnLeft ? null       : cr,
                top:    isOnTop  ? fabTop     : null,
                bottom: isOnTop  ? null       : cb,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    _fabPosNotifier.value = Offset(
                      (fabPos.dx - details.delta.dx).clamp(minEdge, maxRight),
                      (fabPos.dy - details.delta.dy).clamp(minEdge, maxBottom),
                    );
                    if (_showAccessibility) setState(() => _showAccessibility = false);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isOnLeft
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: isOnTop
                        ? [fabButton, popupPanel]
                        : [popupPanel, fabButton],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _accessBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Row(children: [
        Icon(icon, size: 16, color: color), const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.dmSans(
            fontSize: 12.5, fontWeight: FontWeight.w700, color: dmTxtMain),
            overflow: TextOverflow.ellipsis)),
      ]),
    ));

  Color get _statusColor {
    switch (_selectedStatus) {
      case 'Available': return AppColors.green;
      case 'Busy':      return AppColors.warning;
      default:          return const Color(0xFF8AA0BC);
    }
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final stats = [
      {'label':'Appointments','value':'1,284','icon':Icons.calendar_today_rounded,'color':dmAccent},
      {'label':'Clients',      'value':'248',  'icon':Icons.people_alt_rounded,   'color':AppColors.green},
      {'label':'Reviews',      'value':'4.9★', 'icon':Icons.star_rounded,         'color':AppColors.warning},
    ];
    return Row(children: stats.asMap().entries.map((e) => Expanded(child: Container(
      margin: EdgeInsets.only(left: e.key == 0 ? 0 : 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dmBorder, width: 1.5),
          boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05), blurRadius: 10)]),
      child: Column(children: [
        Icon(e.value['icon'] as IconData, color: e.value['color'] as Color, size: 20),
        const SizedBox(height: 8),
        Text(e.value['value'] as String, style: GoogleFonts.dmSans(
            fontSize: 16, fontWeight: FontWeight.w900, color: dmTxtMain, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(e.value['label'] as String, textAlign: TextAlign.center, style: GoogleFonts.dmSans(
            fontSize: 9.5, color: dmTxtSub, fontWeight: FontWeight.w600)),
      ]),
    ))).toList());
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700,
          color: dmTxtSub, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      if (_isEditing)
        TextField(controller: ctrl,
          style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain, fontWeight: FontWeight.w600),
          decoration: InputDecoration(prefixIcon: Icon(icon, color: dmAccent, size: 18),
              filled: true, fillColor: dmCard2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: dmAccent, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)))
      else
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: dmCard2, borderRadius: BorderRadius.circular(12), border: Border.all(color: dmBorder)),
          child: Row(children: [
            Icon(icon, color: dmAccent, size: 18), const SizedBox(width: 10),
            Expanded(child: Text(ctrl.text, style: GoogleFonts.dmSans(fontSize: 14, color: dmTxtMain, fontWeight: FontWeight.w600))),
          ])),
    ]);

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: dmCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dmBorder, width: 1.5),
        boxShadow: [BoxShadow(color: dmAccent.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4))]),
    child: child);

  Widget _cardTitle(String title, IconData icon, Color color) => Row(children: [
    Container(width: 34, height: 34,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Icon(icon, color: color, size: 18)),
    const SizedBox(width: 10),
    Text(title, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800,
        color: dmTxtMain, letterSpacing: -0.3)),
  ]);

  Widget _glass({required Widget child}) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.22))),
    child: Center(child: child),
  );
}
