// Unit tests for the chat API parsing: room/message DTOs and the message
// page shape. Pure Dart, no plugins, no network — run with `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/services/chat_service.dart';

void main() {
  group('ChatRoomInfo.fromJson', () {
    test('parses room fields', () {
      final room = ChatRoomInfo.fromJson({
        'room_id': '5cc143928a5a',
        'name': 'API test chat',
        'participants': ['2', '3'],
        'is_group': false,
        'created_at': '2026-11-16T20:00:00Z',
      });
      expect(room.roomId, '5cc143928a5a');
      expect(room.name, 'API test chat');
      expect(room.participants, ['2', '3']);
      expect(room.isGroup, isFalse);
      expect(room.createdAt, isNotNull);
    });
  });

  group('ChatApiMessage.fromJson', () {
    test('parses message fields', () {
      final msg = ChatApiMessage.fromJson({
        'id': '691a00000000000000000001',
        'room_id': '5cc143928a5a',
        'sender_id': '2',
        'sender_username': 'appt-test-a@example.com',
        'content': 'Hello from A',
        'message_type': 'text',
        'read_by': ['2'],
        'created_at': '2026-11-16T20:01:00Z',
      });
      expect(msg.id, '691a00000000000000000001');
      expect(msg.senderId, '2');
      expect(msg.content, 'Hello from A');
      expect(msg.messageType, 'text');
      expect(msg.readBy, ['2']);
    });

    test('defaults missing fields instead of throwing', () {
      final msg = ChatApiMessage.fromJson({'id': 'x'});
      expect(msg.content, '');
      expect(msg.messageType, 'text');
      expect(msg.readBy, isEmpty);
    });
  });

  group('MessagePage.fromJson', () {
    test('parses count, cursor and messages', () {
      final page = MessagePage.fromJson({
        'room_id': '5cc143928a5a',
        'count': 2,
        'next_before': '2026-11-16T20:01:00Z',
        'messages': [
          {
            'id': '1',
            'room_id': '5cc143928a5a',
            'sender_id': '2',
            'content': 'Hello from A',
            'message_type': 'text',
            'created_at': '2026-11-16T20:01:00Z',
          },
          {
            'id': '2',
            'room_id': '5cc143928a5a',
            'sender_id': '3',
            'content': 'Hi A, B here',
            'message_type': 'text',
            'created_at': '2026-11-16T20:02:00Z',
          },
        ],
      });
      expect(page.count, 2);
      expect(page.nextBefore, '2026-11-16T20:01:00Z');
      expect(page.messages.map((m) => m.content), [
        'Hello from A',
        'Hi A, B here',
      ]);
    });
  });

  group('ChatApiMessage.parseServerTime', () {
    test('parses an offset timestamp unchanged', () {
      final parsed = ChatApiMessage.parseServerTime(
        '2026-11-18T22:39:00Z',
      );
      expect(parsed, DateTime.utc(2026, 11, 18, 22, 39));
    });

    test('assumes UTC when the timestamp has no offset', () {
      // A naive string parsed as local time would shift the day for
      // PKT users (UTC+5) — the date-separator bug. It must parse as
      // UTC instead.
      final parsed = ChatApiMessage.parseServerTime('2026-11-18T22:39:00');
      expect(parsed, DateTime.utc(2026, 11, 18, 22, 39));
      expect(parsed!.isUtc, isTrue);
    });

    test('returns null for null or empty input', () {
      expect(ChatApiMessage.parseServerTime(null), isNull);
      expect(ChatApiMessage.parseServerTime(''), isNull);
    });
  });

  group('ChatApiMessage.fromJson reply fields', () {
    test('parses reply_to_id and reply_to_text', () {
      final msg = ChatApiMessage.fromJson({
        'id': '691a00000000000000000002',
        'room_id': '5cc143928a5a',
        'sender_id': '3',
        'content': 'replying here',
        'message_type': 'text',
        'created_at': '2026-11-18T22:40:00Z',
        'reply_to_id': '691a00000000000000000001',
        'reply_to_text': 'original message',
      });
      expect(msg.replyToId, '691a00000000000000000001');
      expect(msg.replyToText, 'original message');
    });

    test('reply fields are null on old messages', () {
      final msg = ChatApiMessage.fromJson({'id': 'x'});
      expect(msg.replyToId, isNull);
      expect(msg.replyToText, isNull);
    });
  });

  group('ChatRoomInfo.fromJson enriched fields', () {
    test('parses last_message and unread_count', () {
      final room = ChatRoomInfo.fromJson({
        'room_id': '5cc143928a5a',
        'name': 'API test chat',
        'participants': ['2', '3'],
        'is_group': false,
        'created_at': '2026-11-16T20:00:00Z',
        'unread_count': 2,
        'last_message': {
          'id': '691a00000000000000000001',
          'room_id': '5cc143928a5a',
          'sender_id': '3',
          'content': 'latest',
          'message_type': 'text',
          'read_by': ['3'],
          'created_at': '2026-11-18T22:39:00Z',
        },
      });
      expect(room.unreadCount, 2);
      expect(room.lastMessage, isNotNull);
      expect(room.lastMessage!.content, 'latest');
    });

    test('enriched fields are null on older backends', () {
      final room = ChatRoomInfo.fromJson({
        'room_id': '5cc143928a5a',
        'name': 'API test chat',
        'participants': ['2', '3'],
        'is_group': false,
        'created_at': '2026-11-16T20:00:00Z',
      });
      expect(room.unreadCount, isNull);
      expect(room.lastMessage, isNull);
    });
  });

  group('ChatService.countUnread', () {
    ChatApiMessage msg(
      String id,
      String senderId,
      List<String> readBy,
      String createdAt,
    ) => ChatApiMessage.fromJson({
      'id': id,
      'room_id': '5cc143928a5a',
      'sender_id': senderId,
      'content': 'msg $id',
      'message_type': 'text',
      'read_by': readBy,
      'created_at': createdAt,
    });

    test('counts only other people\'s unread messages', () {
      final messages = [
        msg('1', '2', ['2'], '2026-11-16T20:01:00Z'), // mine — skip
        msg('2', '3', ['3'], '2026-11-16T20:02:00Z'), // theirs, unread
        msg('3', '3', ['3'], '2026-11-16T20:03:00Z'), // theirs, unread
      ];
      expect(ChatService.countUnread(messages, myId: '2'), 2);
    });

    test('ignores messages already read via read_by', () {
      final messages = [
        msg('1', '3', ['3', '2'], '2026-11-16T20:01:00Z'), // read
        msg('2', '3', ['3'], '2026-11-16T20:02:00Z'), // unread
      ];
      expect(ChatService.countUnread(messages, myId: '2'), 1);
    });

    test('ignores messages older than the local last-read stamp', () {
      final messages = [
        msg('1', '3', ['3'], '2026-11-16T20:01:00Z'), // before stamp
        msg('2', '3', ['3'], '2026-11-16T20:03:00Z'), // after stamp
      ];
      expect(
        ChatService.countUnread(
          messages,
          myId: '2',
          lastReadAt: DateTime.parse('2026-11-16T20:02:00Z'),
        ),
        1,
      );
    });

    test('returns 0 when not logged in', () {
      final messages = [
        msg('1', '3', ['3'], '2026-11-16T20:01:00Z'),
      ];
      expect(ChatService.countUnread(messages, myId: null), 0);
    });
  });
}
