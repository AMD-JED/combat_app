import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chat_socket_service.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../services/message_service.dart';

class ChatState {
  final List<MessageModel> messages; // chronological, oldest -> newest
  final bool isLoading;
  final bool isConnected;
  final String? typingUsername;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isConnected = false,
    this.typingUsername,
    this.errorMessage,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isConnected,
    String? typingUsername,
    bool clearTyping = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isConnected: isConnected ?? this.isConnected,
      typingUsername: clearTyping ? null : (typingUsername ?? this.typingUsername),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// One instance per open conversation (via `.family`). Loads history over
/// REST, then opens the shared `/messages/ws` socket for live updates.
///
/// IMPORTANT: the backend pushes `new_message` to BOTH participants on every
/// device (see `connection_manager.py::send_to_user` called for sender AND
/// recipient) — so a message we just sent optimistically will also arrive
/// back over the socket. We de-dupe by message `id` once the server echo
/// arrives, replacing the optimistic entry.
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this._ref, this.conversationId) : super(const ChatState()) {
    _init();
  }

  final Ref _ref;
  final int conversationId;
  final MessageService _messageService = MessageService();
  final ChatSocketService _socket = ChatSocketService();
  StreamSubscription? _eventSub;
  Timer? _typingClearTimer;
  int _optimisticIdCounter = -1; // negative IDs never collide with real server IDs

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    try {
      final history = await _messageService.getMessages(conversationId);
      state = state.copyWith(messages: history, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }

    await _connectSocket();
    await markConversationRead();
  }

  Future<void> _connectSocket() async {
    try {
      await _socket.connect();
      state = state.copyWith(isConnected: true, clearError: true);
      _eventSub = _socket.events.listen(_handleEvent, onError: (e) {
        state = state.copyWith(isConnected: false, errorMessage: e.toString());
      });
    } catch (e) {
      state = state.copyWith(isConnected: false, errorMessage: e.toString());
    }
  }

  int get _myUserId => _ref.read(authProvider).user!.id;

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;

    switch (type) {
      case 'new_message':
        _onNewMessage(MessageModel.fromJson(data));
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
            state = state.copyWith(clearTyping: true);
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
      // Replace the most recent optimistic (negative-id) message with the
      // real server copy, if one is pending.
      final pendingIndex = list.lastIndexWhere((m) => m.id < 0);
      if (pendingIndex != -1) {
        list[pendingIndex] = incoming;
        state = state.copyWith(messages: list);
        return;
      }
    }

    list.add(incoming);
    state = state.copyWith(messages: list);

    // Keep the conversations list preview/order in sync.
    _ref.read(conversationsProvider.notifier).bumpConversation(
          incoming,
          incrementUnread: !isMine,
        );

    // If we're actively viewing this conversation, immediately mark as read.
    if (!isMine) markConversationRead();
  }

  void sendMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final me = _ref.read(authProvider).user!;
    final optimistic = MessageModel(
      id: _optimisticIdCounter--,
      conversationId: conversationId,
      sender: me,
      content: trimmed,
      isRead: false,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);

    _socket.sendMessage(conversationId: conversationId, content: trimmed);
  }

  void notifyTyping() {
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
    _socket.dispose();
    super.dispose();
  }
}

final chatProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, int>((ref, conversationId) {
  return ChatNotifier(ref, conversationId);
});
