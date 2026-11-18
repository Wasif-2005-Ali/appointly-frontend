import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/call_service.dart';
import '../user_session.dart';

/// Call history: my 30 most recent calls, newest first
/// (`GET /api/call/history/`).
///
/// The history API carries user IDs, not names, and there is no
/// get-user-by-ID endpoint, so the other party shows as `User #id`.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallSessionInfo>? _calls;
  String? _error;
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : (_calls == null || _calls!.isEmpty)
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _calls!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _buildTile(_calls![index]);
                        },
                      ),
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: missed
            ? Colors.red.withValues(alpha: 0.12)
            : colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(
          call.callType == 'audio' ? Icons.call : Icons.videocam,
          color: missed ? Colors.red : colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        'User #$peerId',
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
