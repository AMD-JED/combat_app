import 'user_model.dart';

enum PostType {
  text('text'),
  image('image'),
  video('video'),
  workout('workout');

  final String value;
  const PostType(this.value);

  static PostType fromString(String? raw) {
    if (raw == null) return PostType.text;
    return PostType.values.firstWhere(
      (e) => e.value.toLowerCase() == raw.toLowerCase(),
      orElse: () => PostType.text,
    );
  }
}

/// Mirrors `app/models/post.py::ReactionType` (backend v5) and
/// `ReactionType` in the React prototype's `src/types.ts`. `value` is exactly
/// what the API sends/expects (`POST /posts/{id}/react`).
///
/// The declaration order is also the display order of the reactions bar.
enum ReactionType {
  respect('respect'),
  fire('fire'),
  strength('strength'),
  precision('precision'),
  champion('champion'),
  sport('sport');

  final String value;
  const ReactionType(this.value);

  static ReactionType? fromString(String? raw) {
    if (raw == null) return null;
    final lower = raw.toLowerCase();
    for (final reaction in ReactionType.values) {
      if (reaction.value == lower) return reaction;
    }
    return null;
  }
}

class PostModel {
  final int id;
  final String? content;
  final String? mediaUrl;
  final PostType postType;
  final String? tags;
  final UserModel author;

  /// Total number of reactions of any type (the backend keeps this field
  /// under its old "likes" name for backward compatibility).
  final int likesCount;
  final int commentsCount;
  final DateTime createdAt;
  final bool isLikedByMe;

  /// Per-type counters (`reaction_counts`). The backend always sends all six
  /// keys; a missing key is simply treated as 0.
  final Map<ReactionType, int> reactionCounts;

  /// The current user's single reaction on this post (`user_reaction`).
  final ReactionType? userReaction;

  const PostModel({
    required this.id,
    this.content,
    this.mediaUrl,
    required this.postType,
    this.tags,
    required this.author,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    this.isLikedByMe = false,
    this.reactionCounts = const {},
    this.userReaction,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final counts = <ReactionType, int>{};
    final rawCounts = json['reaction_counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        final type = ReactionType.fromString(key as String?);
        if (type != null) counts[type] = (value as num?)?.toInt() ?? 0;
      });
    }

    final userReaction = ReactionType.fromString(json['user_reaction'] as String?);

    return PostModel(
      id: json['id'] as int,
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      postType: PostType.fromString(json['post_type'] as String?),
      tags: json['tags'] as String?,
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>),
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      isLikedByMe: json['is_liked_by_me'] as bool? ?? userReaction != null,
      reactionCounts: counts,
      userReaction: userReaction,
    );
  }

  /// Reactions that have at least one vote, most popular first — used for the
  /// little overlapping emoji bubbles in the post card's stats row.
  List<MapEntry<ReactionType, int>> get topReactions {
    final entries = reactionCounts.entries.where((e) => e.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  PostModel copyWith({
    String? content,
    String? mediaUrl,
    PostType? postType,
    String? tags,
    int? likesCount,
    int? commentsCount,
    bool? isLikedByMe,
    Map<ReactionType, int>? reactionCounts,
    ReactionType? userReaction,
    bool clearUserReaction = false,
  }) {
    return PostModel(
      id: id,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      postType: postType ?? this.postType,
      tags: tags ?? this.tags,
      author: author,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      userReaction: clearUserReaction ? null : (userReaction ?? this.userReaction),
    );
  }
}
