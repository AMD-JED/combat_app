import 'package:flutter_test/flutter_test.dart';

import 'package:combat_app_frontend/models/reel_model.dart';
import 'package:combat_app_frontend/providers/reels_provider.dart';

Map<String, dynamic> _reelJson({
  int id = 1,
  int authorId = 7,
  Map<String, dynamic>? extra,
}) =>
    {
      'id': id,
      'author': {
        'id': authorId,
        'username': 'fighter$authorId',
        'full_name': 'Fighter $authorId',
        'avatar_url': null,
      },
      'media_url': 'https://res.cloudinary.com/demo/video/upload/v1/reel.mp4',
      'thumbnail_url': null,
      'caption': '1-2 combo drill',
      'sport_id': 3,
      'duration_seconds': 12,
      'view_count': 5,
      'likes_count': 2,
      'comments_count': 1,
      'is_liked_by_me': true,
      'is_coach_content': false,
      'is_following_author': true,
      'created_at': '2026-10-16T10:00:00',
      ...?extra,
    };

void main() {
  group('ReelModel.fromJson', () {
    test('reads every field of ReelResponse', () {
      final r = ReelModel.fromJson(_reelJson());
      expect(r.id, 1);
      expect(r.author.username, 'fighter7');
      expect(r.caption, '1-2 combo drill');
      expect(r.sportId, 3);
      expect(r.durationSeconds, 12);
      expect(r.viewCount, 5);
      expect(r.likesCount, 2);
      expect(r.commentsCount, 1);
      expect(r.likedByMe, isTrue);
      expect(r.isCoachContent, isFalse);
      expect(r.followingAuthor, isTrue);
      expect(r.createdAt, DateTime.parse('2026-10-16T10:00:00'));
    });

    test('tolerates optional fields being null or absent', () {
      final json = _reelJson()
        ..['caption'] = null
        ..['sport_id'] = null
        ..['duration_seconds'] = null
        ..remove('is_following_author'); // an older backend
      final r = ReelModel.fromJson(json);
      expect(r.caption, isNull);
      expect(r.sportId, isNull);
      expect(r.durationSeconds, isNull);
      expect(r.followingAuthor, isFalse);
    });

    test('accepts counters sent as doubles', () {
      final r = ReelModel.fromJson(_reelJson(extra: {'likes_count': 4.0}));
      expect(r.likesCount, 4);
    });
  });

  group('ReelModel.copyWith', () {
    test('changes only what is given', () {
      final r = ReelModel.fromJson(_reelJson());
      final next = r.copyWith(likedByMe: false, likesCount: 1);
      expect(next.likedByMe, isFalse);
      expect(next.likesCount, 1);
      expect(next.commentsCount, r.commentsCount);
      expect(next.followingAuthor, r.followingAuthor);
      expect(next.author.id, r.author.id);
      expect(next.mediaUrl, r.mediaUrl);
    });
  });

  group('formatCount', () {
    test('small numbers are printed as they are', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
    });

    test('thousands and millions are abbreviated', () {
      expect(formatCount(1000), '1K');
      expect(formatCount(1200), '1.2K');
      expect(formatCount(12500), '13K');
      expect(formatCount(1000000), '1M');
      expect(formatCount(3400000), '3.4M');
    });
  });

  group('ReelsState', () {
    test('copyWith keeps the sport filter unless told otherwise', () {
      const s = ReelsState(sportId: 3);
      expect(s.copyWith(isLoading: true).sportId, 3);
      expect(s.copyWith(clearSport: true).sportId, isNull);
      expect(s.copyWith(sportId: 5).sportId, 5);
    });

    test('a signed-out notifier never loads anything', () {
      final notifier = ReelsNotifier(null);
      notifier.ensureLoaded();
      expect(notifier.state.reels, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      notifier.dispose();
    });
  });
}
