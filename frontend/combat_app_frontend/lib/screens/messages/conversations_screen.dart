import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/message_model.dart';
import '../../providers/conversations_provider.dart';

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
    final state = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(conversationsProvider.notifier).fetchConversations(),
        child: state.isLoading && state.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.conversations.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.chat_bubble_outline, size: 64, color: AppTheme.textMuted),
                      SizedBox(height: 16),
                      Center(
                        child: Text('لا توجد محادثات بعد',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: state.conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final conversation = state.conversations[index];
                      return _ConversationTile(conversation: conversation);
                    },
                  ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  const _ConversationTile({required this.conversation});

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'قبل ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'قبل ${diff.inHours} س';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final last = conversation.lastMessage;
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      onTap: () => context.push('/messages/${conversation.id}', extra: other),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: AppTheme.surface,
        backgroundImage:
            other.avatarUrl != null ? CachedNetworkImageProvider(other.avatarUrl!) : null,
        child: other.avatarUrl == null
            ? const Icon(Icons.person, color: AppTheme.textMuted)
            : null,
      ),
      title: Text(other.fullName,
          style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(
        last == null ? 'ابدأ المحادثة الآن' : last.displayContent,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnread ? Colors.white : AppTheme.textMuted,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_formatTime(conversation.lastMessageAt),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          if (hasUnread) ...[
            const SizedBox(height: 6),
            CircleAvatar(
              radius: 9,
              backgroundColor: AppTheme.primaryRed,
              child: Text('${conversation.unreadCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}
