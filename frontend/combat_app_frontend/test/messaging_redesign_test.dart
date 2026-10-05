import 'package:flutter_test/flutter_test.dart';

import 'package:combat_app_frontend/models/message_model.dart';
import 'package:combat_app_frontend/screens/messages/widgets/chat_helpers.dart';

Map<String, dynamic> _sender() => {
      'id': 7,
      'username': 'fighter',
      'full_name': 'Test Fighter',
      'avatar_url': null,
    };

Map<String, dynamic> _message({
  String? content,
  String? mediaUrl,
  String? mediaType,
  String? deletedAt,
}) =>
    {
      'id': 1,
      'conversation_id': 3,
      'sender': _sender(),
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'is_read': false,
      'deleted_at': deletedAt,
      'created_at': '2026-10-03T10:00:00',
    };

void main() {
  group('videoPosterUrl', () {
    test('derives the 1s JPG poster from a Cloudinary video URL', () {
      expect(
        videoPosterUrl(
            'https://res.cloudinary.com/demo/video/upload/combat/messages/videos/msg_1.mp4'),
        'https://res.cloudinary.com/demo/video/upload/so_1/combat/messages/videos/msg_1.jpg',
      );
    });

    test('returns empty for non-Cloudinary-video URLs', () {
      expect(videoPosterUrl('https://example.com/a.mp4'), '');
    });
  });

  group('MessageModel media flags', () {
    test('image message', () {
      final m = MessageModel.fromJson(_message(
        mediaUrl: 'https://res.cloudinary.com/demo/image/upload/a.jpg',
        mediaType: 'image',
      ));
      expect(m.hasMedia, isTrue);
      expect(m.isImage, isTrue);
      expect(m.isVideo, isFalse);
    });

    test('video message', () {
      final m = MessageModel.fromJson(_message(
        mediaUrl: 'https://res.cloudinary.com/demo/video/upload/a.mp4',
        mediaType: 'video',
      ));
      expect(m.isVideo, isTrue);
      expect(m.isImage, isFalse);
    });

    test('a deleted message never reports media', () {
      final m = MessageModel.fromJson(_message(
        mediaUrl: 'https://res.cloudinary.com/demo/image/upload/a.jpg',
        mediaType: 'image',
        deletedAt: '2026-10-03T11:00:00',
      ));
      expect(m.isDeleted, isTrue);
      expect(m.hasMedia, isFalse);
      expect(m.displayContent, '');
    });

    test('text-only message has no media', () {
      final m = MessageModel.fromJson(_message(content: 'yo'));
      expect(m.hasMedia, isFalse);
      expect(m.displayContent, 'yo');
    });
  });

  group('ConversationModel presence', () {
    Map<String, dynamic> conv({bool? online}) => {
          'id': 3,
          'other_user': {..._sender(), 'belt_rank': 'Black belt'},
          'last_message': null,
          'unread_count': 2,
          'last_message_at': '2026-10-03T10:00:00',
          if (online != null) 'other_user_online': online,
        };

    test('parses other_user_online and defaults to false when absent', () {
      expect(ConversationModel.fromJson(conv(online: true)).otherUserOnline, isTrue);
      expect(ConversationModel.fromJson(conv()).otherUserOnline, isFalse);
    });

    test('copyWith keeps and updates presence', () {
      final c = ConversationModel.fromJson(conv(online: true));
      expect(c.copyWith(unreadCount: 0).otherUserOnline, isTrue);
      expect(c.copyWith(otherUserOnline: false).otherUserOnline, isFalse);
    });
  });
}
