import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../services/api_client.dart';
import '../services/user_service.dart';

/// Reusable user picker: search Appointly users by name or email and
/// tap one to select it. Used wherever a numeric user ID used to be
/// typed by hand — new chat, new call, and booking a provider.
///
/// Pops with the selected [AppUser], or null when dismissed.
///
/// A "enter the ID manually" fallback is kept at the bottom for users
/// whose name cannot be found (e.g. a typo'd name); it returns an
/// [AppUser] with only the ID set (name shown as "User N").
class UserPickerScreen extends StatefulWidget {
  final String title;

  const UserPickerScreen({super.key, this.title = 'Choose a person'});

  @override
  State<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends State<UserPickerScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<AppUser> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  Color get _bg => AppStateProvider.of(context).bg;
  Color get _cardBg => AppStateProvider.of(context).cardBg;
  Color get _border => AppStateProvider.of(context).border;
  Color get _txtMain => AppStateProvider.of(context).txtMain;
  Color get _txtSub => AppStateProvider.of(context).txtSub;
  Color get _accent => AppStateProvider.of(context).accent;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _searched = false;
        _error = null;
      });
      return;
    }
    // Rebuild so the Clear (X) suffix icon appears while typing — the
    // old code only setState on the empty-query path, so the X never
    // showed until a search completed.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final users = await UserService.instance.searchUsers(query);
      if (!mounted) return;
      // A newer keystroke may have started another search; only show
      // results for the query still in the field.
      if (_searchCtrl.text.trim() != query) return;
      setState(() {
        _results = users;
        _searching = false;
        _searched = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _error = e.message;
      });
    }
  }

  Future<void> _enterIdManually() async {
    final idCtrl = TextEditingController();
    // Declared outside the builder: the builder re-runs on every
    // setDialogState, which would reset an inner variable.
    String? error;
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: _cardBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Enter user ID',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w800,
                color: _txtMain,
              ),
            ),
            content: TextField(
              controller: idCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.dmSans(color: _txtMain),
              decoration: InputDecoration(
                hintText: 'e.g. 3',
                helperText: 'Ask the other person for their ID.',
                errorText: error,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.dmSans(
                    color: _txtSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  // Bad input used to pop with null and silently do
                  // nothing — now it shows an inline error instead.
                  final n = int.tryParse(idCtrl.text.trim());
                  if (n == null || n <= 0) {
                    setDialogState(
                        () => error = 'Enter a valid user ID (a number above 0).');
                    return;
                  }
                  Navigator.pop(dialogCtx, n);
                },
                child: Text(
                  'Use ID',
                  style: GoogleFonts.dmSans(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (id == null || !mounted) return;
    Navigator.pop(
      context,
      AppUser(id: id, fullName: 'User $id', email: '', profession: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          // Gradient hero header, matching the other screens (the old
          // plain AppBar looked out of place).
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: appState.heroGradient,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.22)),
                      ),
                      child: const Center(
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onQueryChanged,
              onSubmitted: (q) {
                _debounce?.cancel();
                if (q.trim().isNotEmpty) _search(q.trim());
              },
              style: GoogleFonts.dmSans(fontSize: 15, color: _txtMain),
              decoration: InputDecoration(
                hintText: 'Search by name or email…',
                hintStyle: GoogleFonts.dmSans(color: _txtSub.withOpacity(0.6)),
                prefixIcon: Icon(Icons.search_rounded, color: _txtSub),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: _txtSub,
                          size: 20,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onQueryChanged('');
                        },
                      ),
                filled: true,
                fillColor: _cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enterIdManually,
                icon: Icon(Icons.badge_outlined, size: 18, color: _accent),
                label: Text(
                  'Enter a user ID manually',
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _accent.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: _txtSub.withOpacity(0.4),
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 14, color: _txtSub),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _search(_searchCtrl.text.trim()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 56,
                color: _txtSub.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Find someone',
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _txtSub,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Type a name or email above to search all Appointly users.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: _txtSub.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No users found',
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _txtSub,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check the spelling, or enter their user ID below.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final user = _results[i];
        return _userTile(user);
      },
    );
  }

  Widget _userTile(AppUser user) => GestureDetector(
    onTap: () => Navigator.pop(context, user),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withOpacity(0.15),
            ),
            child: Center(
              child: Text(
                user.initials,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: _accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: GoogleFonts.dmSans(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _txtMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    user.profession,
                    user.email,
                  ].where((s) => s.isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: _txtSub),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _txtSub.withOpacity(0.5)),
        ],
      ),
    ),
  );
}
