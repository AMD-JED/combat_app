import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../services/message_service.dart';
import 'auth_provider.dart';
import 'chat_socket_provider.dart';

class ConversationsState {
  final List<ConversationModel> conversations;
  final bool isLoading;
  final String? errorMessage;

  const ConversationsState({
    this.conversations = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  int get totalUnread =>
      conversations.fold(0, (sum, c) => sum + c.unreadCount);

  /// The loaded conversation with this id, or null if it isn't in the list.
  ConversationModel? byId(int conversationId) {
    for (final c in conversations) {
      if (c.id == conversationId) return c;
    }
    return null;
  }

  ConversationsState copyWith({
    List<ConversationModel>? conversations,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Holds the conversation list shown on `conversations_screen.dart`, the
/// unread badge on the bottom nav and the "online" dots.
///
/// It listens to the shared socket (`chat_socket_provider.dart`) itself, so
/// the list stays live — new messages, unread counts, presence — even when no
/// chat screen is open. `chat_provider.dart` only calls [clearUnread] (and
/// [bumpConversation] for REST-fallback sends).
class ConversationsNotifier extends StateNotifier<ConversationsState> {
  ConversationsNotifier(this._ref, ChatSocketNotifier socket)
      : super(const ConversationsState()) {
    _eventSub = socket.events.listen(_onSocketEvent);
    // After a reconnect we may have missed events — resync from the server.
    _reconnectSub = socket.reconnected.listen((_) => fetchConversations());
  }

  final Ref _ref;
  final MessageService _service = MessageService();
  StreamSubscription? _eventSub;
  StreamSubscription? _reconnectSub;

  /// The conversation currently on screen (if any): incoming messages for it
  /// must not raise the unread counter, the open chat marks them read.
  int? _activeConversationId;

  void setActiveConversation(int conversationId) {
    _activeConversationId = conversationId;
  }

  /// Only clears if [conversationId] is still the active one, so closing a
  /// chat can't wipe the marker of the chat that was just opened.
  void clearActiveConversation(int conversationId) {
    if (_activeConversationId == conversationId) _activeConversationId = null;
  }

  Future<void> fetchConversations() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conversations = await _service.getConversations();
      state = state.copyWith(conversations: conversations, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void _onSocketEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    final data = event['data'];
    if (data is! Map<String, dynamic>) return;

    switch (type) {
      case 'new_message':
        try {
          final message = MessageModel.fromJson(data);
          final myId = _ref.read(authProvider).user?.id;
          final isMine = message.sender.id == myId;
          bumpConversation(
            message,
            incrementUnread:
                !isMine && message.conversationId != _activeConversationId,
          );
        } catch (_) {
          // Malformed payload — ignore rather than break the stream.
        }
        break;
      case 'presence':
        final userId = data['user_id'];
        final online = data['is_online'];
        if (userId is int && online is bool) _setPresence(userId, online);
        break;
    }
  }

  void _setPresence(int userId, bool online) {
    var changed = false;
    final list = state.conversations.map((c) {
      if (c.otherUser.id == userId && c.otherUserOnline != online) {
        changed = true;
        return c.copyWith(otherUserOnline: online);
      }
      return c;
    }).toList();
    if (changed) state = state.copyWith(conversations: list);
  }

  /// Moves the conversation to the top and updates its preview/unread count.
  void bumpConversation(MessageModel message, {required bool incrementUnread}) {
    final list = [...state.conversations];
    final index = list.indexWhere((c) => c.id == message.conversationId);
    if (index == -1) {
      // Conversation not loaded yet (e.g. brand-new DM) — refetch fully.
      fetchConversations();
      return;
    }
    // The same message can reach us twice (sender's other devices, a repeated
    // broadcast) — never count it twice.
    if (list[index].lastMessage?.id == message.id) return;

    final updated = list[index].copyWith(
      lastMessage: message,
      lastMessageAt: message.createdAt,
      unreadCount:
          incrementUnread ? list[index].unreadCount + 1 : list[index].unreadCount,
    );
    list.removeAt(index);
    list.insert(0, updated);
    state = state.copyWith(conversations: list);
  }

  /// Called after the user reads a conversation.
  void clearUnread(int conversationId) {
    final list = state.conversations.map((c) {
      if (c.id == conversationId) return c.copyWith(unreadCount: 0);
      return c;
    }).toList();
    state = state.copyWith(conversations: list);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _reconnectSub?.cancel();
    super.dispose();
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  // Fresh (empty) list per account, and re-bound to the new socket notifier
  // whenever the signed-in user changes.
  ref.watch(authProvider.select((s) => s.user?.id));
  final socket = ref.watch(chatSocketProvider.notifier);
  return ConversationsNotifier(ref, socket);
});
