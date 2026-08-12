import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../services/message_service.dart';

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

/// Holds the conversation list shown on `conversations_screen.dart` and the
/// unread badge on the bottom nav. `chat_provider.dart` calls
/// [bumpConversation]/[markConversationRead] on this notifier whenever a
/// relevant WS event arrives, so the list stays live even if the user never
/// leaves an open chat.
class ConversationsNotifier extends StateNotifier<ConversationsState> {
  ConversationsNotifier() : super(const ConversationsState());

  final MessageService _service = MessageService();

  Future<void> fetchConversations() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conversations = await _service.getConversations();
      state = state.copyWith(conversations: conversations, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Called when a `new_message` WS event arrives for any conversation —
  /// moves it to the top and updates its preview/unread count.
  void bumpConversation(MessageModel message, {required bool incrementUnread}) {
    final list = [...state.conversations];
    final index = list.indexWhere((c) => c.id == message.conversationId);
    if (index == -1) {
      // Conversation not loaded yet (e.g. brand-new DM) — refetch fully.
      fetchConversations();
      return;
    }
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

  /// Called after the user reads a conversation (either locally, on chat
  /// open, or via a `message_read` WS event for messages *they* sent).
  void clearUnread(int conversationId) {
    final list = state.conversations.map((c) {
      if (c.id == conversationId) return c.copyWith(unreadCount: 0);
      return c;
    }).toList();
    state = state.copyWith(conversations: list);
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  return ConversationsNotifier();
});
