import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_app_frontend/models/story_model.dart';

Map<String, dynamic> _author(int id) => {
      'id': id,
      'username': 'fighter$id',
      'full_name': 'Fighter $id',
      'avatar_url': null,
    };

Map<String, dynamic> _storyJson({
  required int id,
  required int authorId,
  String type = 'image',
  String createdAt = '2026-10-06T10:00:00',
  bool viewed = false,
  Map<String, dynamic>? extra,
}) =>
    {
      'id': id,
      'author': _author(authorId),
      'content_type': type,
      'media_url': type == 'text' ? null : 'https://res.cloudinary.com/demo/a.jpg',
      'text_content': null,
      'background_color': null,
      'visibility': 'public',
      'views_count': 0,
      'viewed_by_me': viewed,
      'likes_count': 0,
      'liked_by_me': false,
      'created_at': createdAt,
      'expires_at': '2026-10-07T10:00:00',
      ...?extra,
    };

StoryModel _story({
  required int id,
  required int authorId,
  String createdAt = '2026-10-06T10:00:00',
  bool viewed = false,
}) =>
    StoryModel.fromJson(_storyJson(
      id: id,
      authorId: authorId,
      createdAt: createdAt,
      viewed: viewed,
    ));

void main() {
  group('StoryModel.fromJson', () {
    test('parses a v11 response with likes and caption', () {
      final story = StoryModel.fromJson(_storyJson(
        id: 5,
        authorId: 2,
        extra: {'text_content': 'Sparring tonight', 'likes_count': 3, 'liked_by_me': true},
      ));
      expect(story.id, 5);
      expect(story.contentType, StoryContentType.image);
      expect(story.hasCaption, isTrue);
      expect(story.likesCount, 3);
      expect(story.likedByMe, isTrue);
      expect(story.visibility, StoryVisibility.public);
    });

    test('older payloads without likes still parse (defaults)', () {
      final json = _storyJson(id: 1, authorId: 2)
        ..remove('likes_count')
        ..remove('liked_by_me');
      final story = StoryModel.fromJson(json);
      expect(story.likesCount, 0);
      expect(story.likedByMe, isFalse);
    });

    test('unknown content type falls back to text, followers visibility parses', () {
      final story = StoryModel.fromJson(_storyJson(
        id: 1,
        authorId: 2,
        type: 'text',
        extra: {'content_type': 'hologram', 'visibility': 'followers'},
      ));
      expect(story.contentType, StoryContentType.text);
      expect(story.visibility, StoryVisibility.followers);
    });

    test('copyWith updates only the given fields', () {
      final story = _story(id: 1, authorId: 2);
      final liked = story.copyWith(likedByMe: true, likesCount: 4);
      expect(liked.likedByMe, isTrue);
      expect(liked.likesCount, 4);
      expect(liked.id, story.id);
      expect(liked.viewedByMe, story.viewedByMe);
    });
  });

  group('colors', () {
    test('parseHexColor accepts #RRGGBB, RRGGBB and #AARRGGBB', () {
      expect(parseHexColor('#7C3AED'), const Color(0xFF7C3AED));
      expect(parseHexColor('7C3AED'), const Color(0xFF7C3AED));
      expect(parseHexColor('#807C3AED'), const Color(0x807C3AED));
    });

    test('parseHexColor returns null for junk', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#12'), isNull);
      expect(parseHexColor('#ZZZZZZ'), isNull);
    });

    test('colorToHex round-trips and fits the backend 20-char limit', () {
      const color = Color(0xFF111827);
      expect(colorToHex(color), '#111827');
      expect(parseHexColor(colorToHex(color)), color);
    });
  });

  group('groupStories', () {
    test('mine first, then unseen authors, then seen; each newest first', () {
      final stories = [
        _story(id: 1, authorId: 2, createdAt: '2026-10-06T10:00:00'),
        _story(id: 2, authorId: 3, createdAt: '2026-10-06T11:00:00', viewed: true),
        _story(id: 3, authorId: 1, createdAt: '2026-10-06T09:00:00'),
        _story(id: 4, authorId: 4, createdAt: '2026-10-06T12:00:00'),
      ];
      final groups = groupStories(stories, myUserId: 1);
      expect(groups.map((g) => g.author.id).toList(), [1, 4, 2, 3]);
    });

    test('stories inside a group are oldest first; unseen index skips seen ones', () {
      final stories = [
        _story(id: 2, authorId: 2, createdAt: '2026-10-06T10:00:00'),
        _story(id: 1, authorId: 2, createdAt: '2026-10-06T09:30:00', viewed: true),
      ];
      final group = groupStories(stories, myUserId: 1).single;
      expect(group.stories.map((s) => s.id).toList(), [1, 2]);
      expect(group.hasUnseen, isTrue);
      expect(group.firstUnseenIndex, 1);
    });

    test('a fully seen group starts at the first story', () {
      final stories = [
        _story(id: 1, authorId: 2, viewed: true),
        _story(id: 2, authorId: 2, createdAt: '2026-10-06T11:00:00', viewed: true),
      ];
      final group = groupStories(stories, myUserId: 1).single;
      expect(group.hasUnseen, isFalse);
      expect(group.firstUnseenIndex, 0);
    });

    test('empty feed gives no groups', () {
      expect(groupStories(const [], myUserId: 1), isEmpty);
    });
  });

  test('StoryViewer.fromJson', () {
    final viewer = StoryViewer.fromJson({
      'viewer': _author(9),
      'viewed_at': '2026-10-06T10:05:00',
    });
    expect(viewer.viewer.id, 9);
    expect(viewer.viewedAt, DateTime.parse('2026-10-06T10:05:00'));
  });
}
