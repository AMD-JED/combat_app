import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_socket_provider.dart';
import '../providers/conversations_provider.dart';
import '../services/message_service.dart';
import '../services/upload_service.dart';

class ChatState {
  final List<MessageModel> messages; // chronological, oldest -> newest
  final bool isLoading;
  final bool isUploadingMedia;
  final bool mediaUploadFailed;
  final String? typingUsername;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isUploadingMedia = false,
    this.mediaUploadFailed = false,
    this.typingUsername,
    this.errorMessage,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isUploadingMedia,
    bool? mediaUploadFailed,
    String? typingUsername,
    bool clearTyping = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isUploadingMedia: isUploadingMedia ?? this.isUploadingMedia,
      mediaUploadFailed: mediaUploadFailed ?? this.mediaUploadFailed,
      typingUsername: clearTyping ? null : (typingUsername ?? this.typingUsername),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// One instance per open conversation (via `.family`). Loads history over
/// REST, then consumes the app-wide socket (`chat_socket_provider.dart`) for
/// live updates — it no longer opens a socket of its own.
///
/// IMPORTANT: the backend pushes `new_message` to BOTH participants on every
/// device — so a message we just sent optimistically also arrives back over
/// the socket. We replace the optimistic entry with the server copy, and
/// de-dupe by message `id`.
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this._ref, this.conversationId) : super(const ChatState()) {
    _socket = _ref.read(chatSocketProvider.notifier);
    _eventSub = _socket.events.listen(_handleEvent);
    _reconnectSub = _socket.reconnected.listen((_) => _reloadHistory());
    _init();
  }

  final Ref _ref;
  final int conversationId;
  final MessageService _messageService = MessageService();
  final UploadService _uploadService = UploadService();
  late final ChatSocketNotifier _socket;
  StreamSubscription? _eventSub;
  StreamSubscription? _reconnectSub;
  Timer? _typingClearTimer;
  DateTime? _lastTypingSent;
  int _optimisticIdCounter = -1; // negative IDs never collide with real server IDs

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    try {
      final history = await _messageService.getMessages(conversationId);
      state = state.copyWith(messages: history, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }

    // A brand-new DM isn't in the list yet — load it so the header can show
    // the real online status.
    if (_ref.read(conversationsProvider).byId(conversationId) == null) {
      _ref.read(conversationsProvider.notifier).fetchConversations();
    }

    await markConversationRead();
  }

  /// After a socket reconnect: pull the latest history, keep anything still
  /// pending (negative ids).
  Future<void> _reloadHistory() async {
    try {
      final history = await _messageService.getMessages(conversationId);
      final pending = state.messages.where((m) => m.id < 0);
      state = state.copyWith(messages: [...history, ...pending]);
      await markConversationRead();
    } catch (_) {
      // Non-fatal: live events keep flowing.
    }
  }

  int get _myUserId => _ref.read(authProvider).user!.id;

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    final data = event['data'];
    if (data is! Map<String, dynamic>) return;

    switch (type) {
      case 'new_message':
        try {
          _onNewMessage(MessageModel.fromJson(data));
        } catch (_) {
          // Malformed payload — ignore.
        }
        break;
      case 'message_read':
        if (data['conversation_id'] == conversationId) {
          final updated = state.messages
              .map((m) => m.sender.id == _myUserId ? m.copyWith(isRead: true) : m)
              .toList();
          state = state.copyWith(messages: updated);
        }
        break;
      case 'user_typing':
        if (data['conversation_id'] == conversationId &&
            data['user_id'] != _myUserId) {
          _typingClearTimer?.cancel();
          state = state.copyWith(typingUsername: data['username'] as String?);
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) state = state.copyWith(clearTyping: true);
          });
        }
        break;
      case 'error':
        state = state.copyWith(errorMessage: data['detail'] as String?);
        break;
    }
  }

  void _onNewMessage(MessageModel incoming) {
    if (incoming.conversationId != conversationId) return;

    final isMine = incoming.sender.id == _myUserId;
    final list = [...state.messages];

    if (isMine) {
      // Replace the OLDEST pending optimistic message: echoes come back in
      // the order we sent them.
      final pendingIndex = list.indexWhere((m) => m.id < 0);
      if (pendingIndex != -1) {
        list[pendingIndex] = incoming;
        state = state.copyWith(messages: list);
        return;
      }
    }

    // Real server IDs are only ever positive — skip anything already shown
    // (a repeated delivery would otherwise be appended a second time).
    if (incoming.id > 0 && list.any((m) => m.id == incoming.id)) return;

    list.add(incoming);
    state = state.copyWith(messages: list);

    // The conversations list updates itself from the same socket event
    // (`ConversationsNotifier`). While this chat is open, mark as read.
    if (!isMine) markConversationRead();
  }

  /// Text message.
  void sendMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _send(content: trimmed);
  }

  /// Picks have already happened in the UI; this uploads the file to the
  /// backend, then sends a message carrying the returned Cloudinary URL.
  Future<void> sendMedia(XFile file, {required bool isVideo}) async {
    if (state.isUploadingMedia) return;
    state = state.copyWith(
      isUploadingMedia: true,
      mediaUploadFailed: false,
      clearError: true,
    );
    try {
      final url = await _uploadService.uploadMessageMedia(file, isVideo: isVideo);
      if (!mounted) return;
      state = state.copyWith(isUploadingMedia: false);
      _send(mediaUrl: url, mediaType: isVideo ? 'video' : 'image');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isUploadingMedia: false, mediaUploadFailed: true);
    }
  }

  void _send({String? content, String? mediaUrl, String? mediaType}) {
    final me = _ref.read(authProvider).user!;
    final optimistic = MessageModel(
      id: _optimisticIdCounter--,
      conversationId: conversationId,
      sender: me,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      isRead: false,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);

    final sentOverSocket = _socket.sendMessage(
      conversationId: conversationId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );
    if (!sentOverSocket) _sendViaRest(optimistic);
  }

  /// Socket is down: send over REST and swap the optimistic bubble for the
  /// server copy (REST has no socket echo).
  Future<void> _sendViaRest(MessageModel optimistic) async {
    try {
      final saved = await _messageService.sendMessageRest(
        conversationId,
        content: optimistic.content,
        mediaUrl: optimistic.mediaUrl,
        mediaType: optimistic.mediaType,
      );
      if (!mounted) return;
      final list = state.messages.map((m) => m.id == optimistic.id ? saved : m).toList();
      state = state.copyWith(messages: list);
      _ref
          .read(conversationsProvider.notifier)
          .bumpConversation(saved, incrementUnread: false);
    } catch (e) {
      if (!mounted) return;
      final list = state.messages.where((m) => m.id != optimistic.id).toList();
      state = state.copyWith(messages: list, errorMessage: e.toString());
    }
  }

  /// Throttled: at most one typing ping every 2 seconds.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTypingSent = now;
    _socket.sendTyping(conversationId);
  }

  Future<void> markConversationRead() async {
    _socket.markRead(conversationId);
    _ref.read(conversationsProvider.notifier).clearUnread(conversationId);
    try {
      await _messageService.markRead(conversationId);
    } catch (_) {
      // Non-fatal — the WS mark_read already notified the other side.
    }
  }

  Future<void> deleteMessage(int messageId) async {
    try {
      await _messageService.deleteMessage(messageId);
      final list = state.messages.map((m) {
        if (m.id == messageId) {
          return MessageModel(
            id: m.id,
            conversationId: m.conversationId,
            sender: m.sender,
            content: null,
            mediaUrl: null,
            mediaType: m.mediaType,
            isRead: m.isRead,
            deletedAt: DateTime.now(),
            createdAt: m.createdAt,
          );
        }
        return m;
      }).toList();
      state = state.copyWith(messages: list);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  @override
  void dispose() {
    _typingClearTimer?.cancel();
    _eventSub?.cancel();
    _reconnectSub?.cancel();
    super.dispose();
  }
}

/// `autoDispose`: the notifier lives only while its chat screen is open.
/// Otherwise it would keep reacting to socket events after the screen is gone
/// — in particular auto-marking new messages as read while the user is
/// looking at the conversation list.
final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, int>((ref, conversationId) {
  return ChatNotifier(ref, conversationId);
});
