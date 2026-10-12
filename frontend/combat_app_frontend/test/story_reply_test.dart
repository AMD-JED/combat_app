import 'package:flutter_test/flutter_test.dart';

import 'package:combat_app_frontend/models/message_model.dart';

Map<String, dynamic> _message({int? replyToStoryId, String? deletedAt}) => {
      'id': 1,
      'conversation_id': 3,
      'sender': {
        'id': 7,
        'username': 'fighter',
        'full_name': 'Test Fighter',
        'avatar_url': null,
      },
      'content': 'Great shot!',
      'media_url': null,
      'media_type': null,
      'is_read': false,
      'deleted_at': deletedAt,
      'created_at': '2026-10-06T10:00:00',
      if (replyToStoryId != null) 'reply_to_story_id': replyToStoryId,
    };

void main() {
  group('story reply tag', () {
    test('a message with reply_to_story_id is a story reply', () {
      final m = MessageModel.fromJson(_message(replyToStoryId: 42));
      expect(m.replyToStoryId, 42);
      expect(m.isStoryReply, isTrue);
    });

    test('a plain message (field absent or null) is not', () {
      expect(MessageModel.fromJson(_message()).isStoryReply, isFalse);
      expect(MessageModel.fromJson(_message()).replyToStoryId, isNull);
    });

    test('a deleted story reply drops the tag', () {
      final m = MessageModel.fromJson(
        _message(replyToStoryId: 42, deletedAt: '2026-10-06T11:00:00'),
      );
      expect(m.isDeleted, isTrue);
      expect(m.isStoryReply, isFalse);
    });

    test('copyWith keeps the tag (read receipts must not erase it)', () {
      final m = MessageModel.fromJson(_message(replyToStoryId: 42));
      expect(m.copyWith(isRead: true).replyToStoryId, 42);
      expect(m.copyWith(isRead: true).isRead, isTrue);
    });
  });
}
