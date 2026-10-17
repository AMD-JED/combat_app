import 'user_model.dart';

/// Mirrors `ReelResponse` (backend v9 + `is_following_author` from v12).
class ReelModel {
  final int id;
  final UserModel author;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String? caption;
  final int? sportId;
  final int? durationSeconds;
  final int viewCount;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;
  final bool isCoachContent;
  final bool followingAuthor;
  final DateTime createdAt;

  const ReelModel({
    required this.id,
    required this.author,
    required this.mediaUrl,
    this.thumbnailUrl,
    this.caption,
    this.sportId,
    this.durationSeconds,
    this.viewCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.likedByMe = false,
    this.isCoachContent = false,
    this.followingAuthor = false,
    required this.createdAt,
  });

  factory ReelModel.fromJson(Map<String, dynamic> json) {
    return ReelModel(
      id: json['id'] as int,
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>),
      mediaUrl: json['media_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      caption: json['caption'] as String?,
      sportId: json['sport_id'] as int?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['is_liked_by_me'] as bool? ?? false,
      isCoachContent: json['is_coach_content'] as bool? ?? false,
      followingAuthor: json['is_following_author'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  ReelModel copyWith({
    int? likesCount,
    int? commentsCount,
    bool? likedByMe,
    bool? followingAuthor,
    int? viewCount,
  }) {
    return ReelModel(
      id: id,
      author: author,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      caption: caption,
      sportId: sportId,
      durationSeconds: durationSeconds,
      viewCount: viewCount ?? this.viewCount,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      likedByMe: likedByMe ?? this.likedByMe,
      isCoachContent: isCoachContent,
      followingAuthor: followingAuthor ?? this.followingAuthor,
      createdAt: createdAt,
    );
  }
}

/// 950 → "950", 1200 → "1.2K", 3400000 → "3.4M" (the action-bar counters).
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 999500) {
    final k = n / 1000;
    return '${k >= 10 ? k.round() : _oneDecimal(k)}K';
  }
  final m = n / 1000000;
  return '${m >= 10 ? m.round() : _oneDecimal(m)}M';
}

String _oneDecimal(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
