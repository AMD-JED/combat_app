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

class PostModel {
  final int id;
  final String? content;
  final String? mediaUrl;
  final PostType postType;
  final String? tags;
  final UserModel author;
  final int likesCount;
  final int commentsCount;
  final DateTime createdAt;
  final bool isLikedByMe;

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
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
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
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
    );
  }

  PostModel copyWith({
    String? content,
    String? mediaUrl,
    PostType? postType,
    String? tags,
    int? likesCount,
    int? commentsCount,
    bool? isLikedByMe,
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
    );
  }
}
