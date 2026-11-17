// Unit tests for chat media: message DTO parsing with file fields,
// the API -> model mapping for image/file messages, inbox preview
// text, and the size/MIME/size-formatting helpers. Pure Dart, no
// plugins, no network — run with `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:appointly/chat/models/chat_models.dart';
import 'package:appointly/services/api_client.dart';
import 'package:appointly/services/chat_service.dart';

void main() {
  Map<String, dynamic> apiJson({
    String messageType = 'text',
    String content = 'hello',
    String? fileName,
    int? fileSize,
  }) {
    final json = <String, dynamic>{
      'id': '691a00000000000000000001',
      'room_id': '5cc143928a5a',
      'sender_id': '3',
      'sender_username': 'appt-test-b@example.com',
      'content': content,
      'message_type': messageType,
      'read_by': ['3'],
      'created_at': '2026-11-16T20:01:00Z',
    };
    if (fileName != null) json['file_name'] = fileName;
    if (fileSize != null) json['file_size'] = fileSize;
    return json;
  }

  group('ChatApiMessage.fromJson with media fields', () {
    test('parses image file name and size', () {
      final msg = ChatApiMessage.fromJson(apiJson(
        messageType: 'image',
        content: 'https://res.cloudinary.com/demo/photo.jpg',
        fileName: 'photo.jpg',
        fileSize: 204800,
      ));
      expect(msg.messageType, 'image');
      expect(msg.content, 'https://res.cloudinary.com/demo/photo.jpg');
      expect(msg.fileName, 'photo.jpg');
      expect(msg.fileSize, 204800);
    });

    test('parses file name and size', () {
      final msg = ChatApiMessage.fromJson(apiJson(
        messageType: 'file',
        content: 'https://res.cloudinary.com/demo/report.pdf',
        fileName: 'report.pdf',
        fileSize: 1048576,
      ));
      expect(msg.messageType, 'file');
      expect(msg.fileName, 'report.pdf');
      expect(msg.fileSize, 1048576);
    });

    test('old messages without media fields parse with nulls', () {
      final msg = ChatApiMessage.fromJson(apiJson(messageType: 'image'));
      expect(msg.fileName, isNull);
      expect(msg.fileSize, isNull);
    });
  });

  group('ChatApiMessage.previewText', () {
    test('image message previews as Photo', () {
      final msg = ChatApiMessage.fromJson(apiJson(
        messageType: 'image',
        content: 'https://res.cloudinary.com/demo/photo.jpg',
        fileName: 'photo.jpg',
      ));
      expect(msg.previewText, 'Photo');
    });

    test('file message previews as its file name', () {
      final msg = ChatApiMessage.fromJson(apiJson(
        messageType: 'file',
        content: 'https://res.cloudinary.com/demo/report.pdf',
        fileName: 'report.pdf',
      ));
      expect(msg.previewText, 'report.pdf');
    });

    test('file message without a name previews as File', () {
      final msg = ChatApiMessage.fromJson(apiJson(
        messageType: 'file',
        content: 'https://res.cloudinary.com/demo/x',
      ));
      expect(msg.previewText, 'File');
    });

    test('text message previews as its content', () {
      final msg = ChatApiMessage.fromJson(apiJson(content: 'hello there'));
      expect(msg.previewText, 'hello there');
    });
  });

  group('ChatMessage.fromApi with media', () {
    test('maps an image message and keeps its file fields', () {
      final api = ChatApiMessage.fromJson(apiJson(
        messageType: 'image',
        content: 'https://res.cloudinary.com/demo/photo.jpg',
        fileName: 'photo.jpg',
        fileSize: 204800,
      ));
      final msg = ChatMessage.fromApi(api, currentUserId: '2');
      expect(msg.type, MessageType.image);
      expect(msg.text, 'https://res.cloudinary.com/demo/photo.jpg');
      expect(msg.fileName, 'photo.jpg');
      expect(msg.fileSize, 204800);
      expect(msg.fromMe, isFalse);
    });

    test('maps a file message', () {
      final api = ChatApiMessage.fromJson(apiJson(
        messageType: 'file',
        content: 'https://res.cloudinary.com/demo/report.pdf',
        fileName: 'report.pdf',
        fileSize: 1048576,
      ));
      final msg = ChatMessage.fromApi(api, currentUserId: '2');
      expect(msg.type, MessageType.file);
      expect(msg.fileName, 'report.pdf');
      expect(msg.fileSize, 1048576);
    });

    test('old media message without file fields maps with nulls', () {
      final api = ChatApiMessage.fromJson(apiJson(messageType: 'image'));
      final msg = ChatMessage.fromApi(api, currentUserId: '2');
      expect(msg.type, MessageType.image);
      expect(msg.fileName, isNull);
      expect(msg.fileSize, isNull);
    });
  });

  group('ChatMessage.previewText', () {
    test('image shows Photo, file shows its name, text shows text', () {
      final image = ChatMessage(
        id: '1',
        text: 'https://example.com/a.jpg',
        fromMe: false,
        time: '9:00 PM',
        type: MessageType.image,
        fileName: 'a.jpg',
      );
      final file = ChatMessage(
        id: '2',
        text: 'https://example.com/b.pdf',
        fromMe: false,
        time: '9:01 PM',
        type: MessageType.file,
        fileName: 'b.pdf',
      );
      final unnamed = ChatMessage(
        id: '3',
        text: 'https://example.com/c',
        fromMe: false,
        time: '9:02 PM',
        type: MessageType.file,
      );
      final text = ChatMessage(
        id: '4',
        text: 'hello',
        fromMe: false,
        time: '9:03 PM',
        type: MessageType.text,
      );
      expect(image.previewText, 'Photo');
      expect(file.previewText, 'b.pdf');
      expect(unnamed.previewText, 'File');
      expect(text.previewText, 'hello');
    });
  });

  group('ChatService media helpers', () {
    test('isImageFile matches image extensions only', () {
      expect(ChatService.isImageFile('photo.jpg'), isTrue);
      expect(ChatService.isImageFile('pic.PNG'), isTrue);
      expect(ChatService.isImageFile('shot.webp'), isTrue);
      expect(ChatService.isImageFile('doc.pdf'), isFalse);
      expect(ChatService.isImageFile('notes.txt'), isFalse);
      expect(ChatService.isImageFile('noextension'), isFalse);
    });

    test('validateMediaSize enforces the 10 MB image limit', () {
      expect(
        () => ChatService.validateMediaSize(9 * 1024 * 1024, 'a.jpg'),
        returnsNormally,
      );
      expect(
        () => ChatService.validateMediaSize(11 * 1024 * 1024, 'a.jpg'),
        throwsA(isA<ApiException>()),
      );
    });

    test('validateMediaSize enforces the 25 MB file limit', () {
      expect(
        () => ChatService.validateMediaSize(20 * 1024 * 1024, 'a.zip'),
        returnsNormally,
      );
      expect(
        () => ChatService.validateMediaSize(26 * 1024 * 1024, 'a.zip'),
        throwsA(isA<ApiException>()),
      );
    });

    test('mimeTypeFor returns common types', () {
      expect(ChatService.mimeTypeFor('a.jpg'), 'image/jpeg');
      expect(ChatService.mimeTypeFor('a.png'), 'image/png');
      expect(ChatService.mimeTypeFor('a.pdf'), 'application/pdf');
      expect(ChatService.mimeTypeFor('a.docx'),
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(ChatService.mimeTypeFor('a.unknown'), 'application/octet-stream');
    });

    test('formatFileSize formats bytes, KB and MB', () {
      expect(ChatService.formatFileSize(0), '0 B');
      expect(ChatService.formatFileSize(512), '512 B');
      expect(ChatService.formatFileSize(1024), '1 KB');
      expect(ChatService.formatFileSize(1536), '1.5 KB');
      expect(ChatService.formatFileSize(2 * 1024 * 1024), '2 MB');
      expect(
        ChatService.formatFileSize((2.4 * 1024 * 1024).round()),
        '2.4 MB',
      );
    });
  });
}
