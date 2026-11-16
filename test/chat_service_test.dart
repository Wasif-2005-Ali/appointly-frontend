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
      expect(page.messages.map((m) => m.content),
          ['Hello from A', 'Hi A, B here']);
    });
  });
}
