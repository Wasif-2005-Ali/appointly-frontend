// Unit tests for the chat date-separator rules (null-createdAt rows
// must never silently merge into the previous day), the group-read
// rule, server reply quotes, and the Recent emojis tracker. Pure
// Dart, no plugins, no network — run with `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/chat/models/chat_models.dart';
import 'package:appointly/services/chat_service.dart';

void main() {
  group('DateSeparators', () {
    // Local (not UTC) fixtures: separators group by LOCAL calendar day,
    // so UTC fixtures collide in timezones east of UTC (e.g. PKT).
    final nov17 = DateTime(2026, 11, 17, 20, 0);
    final nov18 = DateTime(2026, 11, 18, 17, 39);

    test('null-createdAt message takes the next dated neighbour', () {
      // The reported bug: sent 18 Nov 22:39 PKT, shown under Nov 17.
      // The undated row sits between a Nov 17 message and a Nov 18
      // message — its effective date is Nov 18 (next neighbour).
      final dates = [nov17, null, nov18];
      expect(DateSeparators.effectiveDate(dates, 1), nov18);
    });

    test('null-createdAt message shows its own separator', () {
      final dates = [nov17, null, nov18];
      // Index 1 (undated, effective Nov 18) starts a new day after
      // the Nov 17 message — it must NOT merge into Nov 17.
      expect(DateSeparators.showSeparator(dates, 1), isTrue);
      // Index 2 is the same effective day as index 1: no separator.
      expect(DateSeparators.showSeparator(dates, 2), isFalse);
    });

    test('undated message at the end takes the previous neighbour', () {
      final dates = [nov17, nov18, null];
      expect(DateSeparators.effectiveDate(dates, 2), nov18);
      expect(DateSeparators.showSeparator(dates, 2), isFalse);
    });

    test('first message always gets a separator', () {
      expect(DateSeparators.showSeparator([null, nov18], 0), isTrue);
      expect(DateSeparators.showSeparator([nov18], 0), isTrue);
    });

    test('same-day messages share one separator', () {
      final dates = [nov18, DateTime(2026, 11, 18, 18, 0)];
      expect(DateSeparators.showSeparator(dates, 1), isFalse);
    });

    test('all-undated list has no effective date', () {
      expect(DateSeparators.effectiveDate([null, null], 0), isNull);
      expect(DateSeparators.showSeparator([null, null], 1), isFalse);
    });
  });

  group('ChatMessage.fromApi group read', () {
    ChatApiMessage api({required List<String> readBy}) =>
        ChatApiMessage.fromJson({
          'id': '691a00000000000000000001',
          'room_id': '5cc143928a5a',
          'sender_id': '2',
          'content': 'hello group',
          'message_type': 'text',
          'read_by': readBy,
          'created_at': '2026-11-18T22:39:00Z',
        });

    test('group message is read only when ALL others read it', () {
      // Only one of two other members read — not read yet.
      final partial = ChatMessage.fromApi(
        api(readBy: ['2', '3']),
        currentUserId: '2',
        otherMemberIds: ['3', '4'],
      );
      expect(partial.status, MessageStatus.delivered);

      final all = ChatMessage.fromApi(
        api(readBy: ['2', '3', '4']),
        currentUserId: '2',
        otherMemberIds: ['3', '4'],
      );
      expect(all.status, MessageStatus.read);
    });

    test('1:1 room is read when the peer read it', () {
      final msg = ChatMessage.fromApi(
        api(readBy: ['2', '3']),
        currentUserId: '2',
        otherMemberIds: ['3'],
      );
      expect(msg.status, MessageStatus.read);
    });

    test('falls back to the any-reader rule without member info', () {
      final msg = ChatMessage.fromApi(
        api(readBy: ['2', '3']),
        currentUserId: '2',
      );
      expect(msg.status, MessageStatus.read);
    });
  });

  group('ChatMessage.fromApi server reply quote', () {
    test('builds replyTo from the broadcast fields', () {
      final api = ChatApiMessage.fromJson({
        'id': '691a00000000000000000002',
        'room_id': '5cc143928a5a',
        'sender_id': '3',
        'content': 'replying here',
        'message_type': 'text',
        'read_by': ['3'],
        'created_at': '2026-11-18T22:40:00Z',
        'reply_to_id': '691a00000000000000000001',
        'reply_to_text': 'original message',
      });
      final msg = ChatMessage.fromApi(api, currentUserId: '2');
      expect(msg.replyTo, isNotNull);
      expect(msg.replyTo!.id, '691a00000000000000000001');
      expect(msg.replyTo!.text, 'original message');
    });

    test('no replyTo on messages without quote fields', () {
      final api = ChatApiMessage.fromJson({
        'id': '691a00000000000000000002',
        'room_id': '5cc143928a5a',
        'sender_id': '3',
        'content': 'plain',
        'message_type': 'text',
        'created_at': '2026-11-18T22:40:00Z',
      });
      final msg = ChatMessage.fromApi(api, currentUserId: '2');
      expect(msg.replyTo, isNull);
    });
  });

  group('RecentEmojis', () {
    setUp(RecentEmojis.debugReset);

    test('records most-recent-first with no duplicates', () {
      RecentEmojis.record('😀');
      RecentEmojis.record('🔥');
      RecentEmojis.record('😀');
      expect(RecentEmojis.recent, ['😀', '🔥']);
    });

    test('caps the list at 16', () {
      for (var i = 0; i < 20; i++) {
        RecentEmojis.record('e$i');
      }
      expect(RecentEmojis.recent.length, 16);
      expect(RecentEmojis.recent.first, 'e19');
    });
  });
}
