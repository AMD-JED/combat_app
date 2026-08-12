import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int conversationId;
  final UserModel otherUser;

  const ChatScreen({super.key, required this.conversationId, required this.otherUser});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatProvider(widget.conversationId).notifier).sendMessage(text);
    _textController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.conversationId));
    final myUserId = ref.watch(authProvider).user?.id;

    ref.listen(chatProvider(widget.conversationId), (previous, next) {
      if ((previous?.messages.length ?? 0) != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surface,
              backgroundImage: widget.otherUser.avatarUrl != null
                  ? CachedNetworkImageProvider(widget.otherUser.avatarUrl!)
                  : null,
              child: widget.otherUser.avatarUrl == null
                  ? const Icon(Icons.person, size: 18, color: AppTheme.textMuted)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.otherUser.fullName, style: const TextStyle(fontSize: 16)),
                  if (chatState.typingUsername != null)
                    const Text('يكتب الآن...',
                        style: TextStyle(fontSize: 12, color: AppTheme.gold))
                  else if (!chatState.isConnected)
                    const Text('غير متصل',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (chatState.errorMessage != null)
            Container(
              width: double.infinity,
              color: AppTheme.primaryRed.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(8),
              child: Text(
                chatState.errorMessage!,
                style: const TextStyle(color: AppTheme.primaryRed, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatState.messages[index];
                      final isMine = message.sender.id == myUserId;
                      return MessageBubble(
                        message: message,
                        isMine: isMine,
                        onLongPressDelete: isMine
                            ? () => ref
                                .read(chatProvider(widget.conversationId).notifier)
                                .deleteMessage(message.id)
                            : null,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onChanged: (_) => ref
                          .read(chatProvider(widget.conversationId).notifier)
                          .notifyTyping(),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: InputBorder.none,
                        filled: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryRed,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
