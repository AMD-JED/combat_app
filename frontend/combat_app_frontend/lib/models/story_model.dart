import 'dart:ui' show Color;

import 'user_model.dart';

/// Mirrors `StoryContentType` in `app/schemas/story.py`.
enum StoryContentType {
  image('image'),
  video('video'),
  text('text');

  final String value;
  const StoryContentType(this.value);

  static StoryContentType parse(String? raw) {
    for (final type in StoryContentType.values) {
      if (type.value == raw) return type;
    }
    return StoryContentType.text;
  }
}

/// Mirrors `StoryVisibility` in `app/schemas/story.py`.
enum StoryVisibility {
  public('public'),
  followers('followers');

  final String value;
  const StoryVisibility(this.value);

  static StoryVisibility parse(String? raw) {
    return raw == 'followers' ? StoryVisibility.followers : StoryVisibility.public;
  }
}

/// Mirrors `StoryResponse` (backend v9 + v11 likes).
///
/// For image/video stories `textContent` is the optional caption; for text
/// stories it is the story itself (see `StoryCreate` in the backend).
class StoryModel {
  final int id;
  final UserModel author;
  final StoryContentType contentType;
  final String? mediaUrl;
  final String? textContent;
  final String? backgroundColor;
  final StoryVisibility visibility;
  final int viewsCount;
  final bool viewedByMe;
  final int likesCount;
  final bool likedByMe;
  final DateTime createdAt;
  final DateTime expiresAt;

  const StoryModel({
    required this.id,
    required this.author,
    required this.contentType,
    this.mediaUrl,
    this.textContent,
    this.backgroundColor,
    this.visibility = StoryVisibility.public,
    this.viewsCount = 0,
    this.viewedByMe = false,
    this.likesCount = 0,
    this.likedByMe = false,
    required this.createdAt,
    required this.expiresAt,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as int,
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>),
      contentType: StoryContentType.parse(json['content_type'] as String?),
      mediaUrl: json['media_url'] as String?,
      textContent: json['text_content'] as String?,
      backgroundColor: json['background_color'] as String?,
      visibility: StoryVisibility.parse(json['visibility'] as String?),
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      viewedByMe: json['viewed_by_me'] as bool? ?? false,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  bool get hasCaption => (textContent ?? '').trim().isNotEmpty;

  /// `#RRGGBB` / `#AARRGGBB` from the backend -> [Color]; null when absent or
  /// malformed (the UI then falls back to the accent gradient).
  Color? get parsedBackground => parseHexColor(backgroundColor);

  StoryModel copyWith({
    int? viewsCount,
    bool? viewedByMe,
    int? likesCount,
    bool? likedByMe,
  }) {
    return StoryModel(
      id: id,
      author: author,
      contentType: contentType,
      mediaUrl: mediaUrl,
      textContent: textContent,
      backgroundColor: backgroundColor,
      visibility: visibility,
      viewsCount: viewsCount ?? this.viewsCount,
      viewedByMe: viewedByMe ?? this.viewedByMe,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

/// Parses `#RRGGBB` or `#AARRGGBB` (the `#` is optional). Returns null for
/// anything else.
Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  var hex = raw.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

/// `#RRGGBB` for the backend (`StoryCreate.background_color`, max 20 chars).
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// All the active stories of one author, oldest first (viewing order).
class StoryGroup {
  final UserModel author;
  final List<StoryModel> stories;

  const StoryGroup({required this.author, required this.stories});

  bool get hasUnseen => stories.any((s) => !s.viewedByMe);

  DateTime get latestAt =>
      stories.map((s) => s.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Where to start playing: the first story the viewer hasn't seen, or the
  /// first one when everything has been seen.
  int get firstUnseenIndex {
    final index = stories.indexWhere((s) => !s.viewedByMe);
    return index == -1 ? 0 : index;
  }
}

/// Turns the flat `GET /stories/feed` list into one group per author:
/// my own group first, then authors with unseen stories, then the rest —
/// each block newest-first. Inside a group stories are oldest-first.
List<StoryGroup> groupStories(List<StoryModel> stories, {required int myUserId}) {
  final byAuthor = <int, List<StoryModel>>{};
  for (final story in stories) {
    byAuthor.putIfAbsent(story.author.id, () => []).add(story);
  }

  final groups = byAuthor.values.map((list) {
    final sorted = [...list]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return StoryGroup(author: sorted.first.author, stories: sorted);
  }).toList();

  groups.sort((a, b) {
    final aMine = a.author.id == myUserId;
    final bMine = b.author.id == myUserId;
    if (aMine != bMine) return aMine ? -1 : 1;
    if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
    return b.latestAt.compareTo(a.latestAt);
  });
  return groups;
}

/// One row of `GET /stories/{id}/views` ("seen by", author only).
class StoryViewer {
  final UserModel viewer;
  final DateTime viewedAt;

  const StoryViewer({required this.viewer, required this.viewedAt});

  factory StoryViewer.fromJson(Map<String, dynamic> json) {
    return StoryViewer(
      viewer: UserModel.fromJson(json['viewer'] as Map<String, dynamic>),
      viewedAt: DateTime.parse(json['viewed_at'] as String),
    );
  }
}
