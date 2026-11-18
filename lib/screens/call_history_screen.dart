import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/api_client.dart';
import '../services/call_service.dart';
import '../services/user_service.dart';
import '../user_session.dart';
import 'call_screen.dart';

/// Call history: my 30 most recent calls, newest first
/// (`GET /api/call/history/`).
///
/// The history API carries user IDs, not names; names are resolved
/// per peer via `GET /api/v1/auth/users/<id>/` (cached in
/// [UserService]) and fall back to `User #id` when the lookup fails.
/// Tapping a row redials that person.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallSessionInfo>? _calls;
  String? _error;
  bool _loading = true;

  /// Resolved peer names by user ID (only IDs that resolved — the
  /// rest fall back to `User #id` in [_peerName]).
  final Map<String, String> _peerNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calls = await CallService.instance.fetchHistory();
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _loading = false;
      });
      _resolveNames(calls);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load call history. Please try again.';
        _loading = false;
      });
    }
  }

  String get _myId => UserSession.instance.userId?.toString() ?? '';

  /// Resolve the display name for each distinct peer in the list.
  /// Lookups run in parallel and are cached in [UserService], so a
  /// rebuild or refresh never refires requests for known peers;
  /// failures just leave the row as `User #id`.
  Future<void> _resolveNames(List<CallSessionInfo> calls) async {
    final peerIds = <String>{};
    for (final call in calls) {
      final peerId = call.callerId == _myId ? call.calleeId : call.callerId;
      if (peerId.isNotEmpty && !_peerNames.containsKey(peerId)) {
        peerIds.add(peerId);
      }
    }
    if (peerIds.isEmpty) return;
    final results = await Future.wait(
      peerIds.map((id) async {
        final numericId = int.tryParse(id);
        if (numericId == null) return null;
        final user = await UserService.instance.fetchUserById(numericId);
        return user == null ? null : MapEntry(id, user.fullName);
      }),
    );
    if (!mounted) return;
    var changed = false;
    for (final entry in results) {
      if (entry != null && entry.value.isNotEmpty) {
        _peerNames[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  String _peerName(String peerId) => _peerNames[peerId] ?? 'User #$peerId';

  /// Tap-to-redial: open the call screen for this peer, with the
  /// same call type (video/voice) as the history entry.
  Future<void> _redial(CallSessionInfo call) async {
    final peerId = call.callerId == _myId ? call.calleeId : call.callerId;
    if (peerId.isEmpty) return;
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen.outgoing(
          calleeId: peerId,
          calleeName: _peerNames[peerId] ?? '',
          callType: call.callType,
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroColors = AppStateProvider.of(context).heroGradient;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient hero, matching the dashboard's header.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: heroColors,
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Call History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Tap a call to call that person again.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : (_calls == null || _calls!.isEmpty)
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              itemCount: _calls!.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                return _buildTile(_calls![index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No calls yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Calls you make or receive will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(CallSessionInfo call) {
    final outgoing = call.callerId == _myId;
    final peerId = outgoing ? call.calleeId : call.callerId;
    final missed = call.status == 'missed';
    final colorScheme = Theme.of(context).colorScheme;
    final peerName = _peerName(peerId);
    final nameKnown = _peerNames.containsKey(peerId);
    return ListTile(
      onTap: () => _redial(call),
      leading: CircleAvatar(
        backgroundColor: missed
            ? Colors.red.withValues(alpha: 0.12)
            : colorScheme.primary.withValues(alpha: 0.12),
        child: nameKnown
            ? Text(
                initialsFor(peerName),
                style: TextStyle(
                  color: missed ? Colors.red : colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(
                call.callType == 'audio' ? Icons.call : Icons.videocam,
                color: missed ? Colors.red : colorScheme.primary,
                size: 20,
              ),
      ),
      title: Text(
        peerName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: missed ? Colors.red : null,
        ),
      ),
      subtitle: Text(
        '${outgoing ? 'Outgoing' : 'Incoming'} · ${_statusLabel(call.status)}'
        '${_durationLabel(call)}',
      ),
      trailing: Text(
        _dateLabel(call.startedAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ended':
        return 'Ended';
      case 'rejected':
        return 'Declined';
      case 'missed':
        return 'Missed';
      case 'ringing':
        return 'Ringing';
      case 'connected':
        return 'Connected';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }

  String _durationLabel(CallSessionInfo call) {
    final seconds = call.durationSeconds;
    if (seconds == null || seconds <= 0) return '';
    final d = Duration(seconds: seconds.round());
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return ' · $m:$s';
  }

  String _dateLabel(DateTime? startedAt) {
    if (startedAt == null) return '';
    final local = startedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = DateFormat('h:mm a').format(local);
    if (day == today) return 'Today, $time';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $time';
    }
    return DateFormat('MMM d, h:mm a').format(local);
  }
}
