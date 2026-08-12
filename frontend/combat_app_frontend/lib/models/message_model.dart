import 'user_model.dart';

/// Mirrors `app/schemas/message.py::MessageResponse` exactly.
class MessageModel {
  final int id;
  final int conversationId;
  final UserModel sender;
  final String? content;
  final String? mediaUrl;
  final String? mediaType; // "image" | "video"
  final bool isRead;
  final DateTime? deletedAt;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.content,
    this.mediaUrl,
    this.mediaType,
    required this.isRead,
    this.deletedAt,
    required this.createdAt,
  });

  /// The backend keeps `content`/`media_url` in the payload even after a
  /// soft-delete is requested by the REST endpoint's response model, but the
  /// WS `_msg_to_dict` helper nulls them out when `deleted_at` is set — this
  /// getter covers both cases defensively.
  bool get isDeleted => deletedAt != null;

  String get displayContent => isDeleted ? '🚫 تم حذف هذه الرسالة' : (content ?? '');

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int,
      sender: UserModel.fromJson(json['sender'] as Map<String, dynamic>),
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      mediaType: json['media_type'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  MessageModel copyWith({bool? isRead}) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      sender: sender,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      isRead: isRead ?? this.isRead,
      deletedAt: deletedAt,
      createdAt: createdAt,
    );
  }
}

/// Mirrors `app/schemas/message.py::ConversationResponse` exactly.
class ConversationModel {
  final int id;
  final UserModel otherUser;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime lastMessageAt;

  const ConversationModel({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    required this.unreadCount,
    required this.lastMessageAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as int,
      otherUser: UserModel.fromJson(json['other_user'] as Map<String, dynamic>),
      lastMessage: json['last_message'] != null
          ? MessageModel.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
    );
  }

  ConversationModel copyWith({
    MessageModel? lastMessage,
    int? unreadCount,
    DateTime? lastMessageAt,
  }) {
    return ConversationModel(
      id: id,
      otherUser: otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}
