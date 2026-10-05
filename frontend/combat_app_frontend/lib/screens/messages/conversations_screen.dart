import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/conversations_provider.dart';
import '../feed/widgets/feed_helpers.dart';
import 'widgets/chat_helpers.dart';

/// Conversation list — port of the prototype's `ChatScreen.tsx` list view:
/// one rounded card per conversation (avatar + online dot, name, time, rank,
/// last message, unread dot). The list is live: new messages, unread counts
/// and presence arrive over the shared socket (see `conversations_provider`).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(conversationsProvider.notifier).fetchConversations());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(conversationsProvider);
    final muted = scheme.onSurface.withValues(alpha: 0.55);

    Widget body;
    if (state.isLoading && state.conversations.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.conversations.isEmpty) {
      body = ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.chat_bubble_outline, size: 64, color: muted),
          const SizedBox(height: 16),
          Center(
            child: Text(
              state.errorMessage != null ? state.errorMessage! : l10n.chatEmptyTitle,
              style: TextStyle(color: muted),
              textAlign: TextAlign.center,
            ),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () => ref.read(conversationsProvider.notifier).fetchConversations(),
                  child: Text(l10n.retryButton),
                ),
              ),
            ),
        ],
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: state.conversations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return state.totalUnread > 0
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        l10n.chatUnreadCount(state.totalUnread),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
          return _ConversationCard(conversation: state.conversations[index - 1]);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.messagesTab)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(conversationsProvider.notifier).fetchConversations(),
        child: body,
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final ConversationModel conversation;
  const _ConversationCard({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final other = conversation.otherUser;
    final last = conversation.lastMessage;
    final hasUnread = conversation.unreadCount > 0;
    final rank = other.beltRank;
    final muted = scheme.onSurface.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/messages/${conversation.id}', extra: other),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ChatAvatar(
                url: other.avatarUrl,
                radius: 26,
                online: conversation.otherUserOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            other.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRelativeTime(l10n, conversation.lastMessageAt),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                    if (rank != null && rank.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          rank,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      last == null ? l10n.chatStartConversation : messagePreview(l10n, last),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: hasUnread ? scheme.onSurface : muted,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 10),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
