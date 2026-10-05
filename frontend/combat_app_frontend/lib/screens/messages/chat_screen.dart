import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_socket_provider.dart';
import '../../providers/conversations_provider.dart';
import 'widgets/chat_helpers.dart';
import 'widgets/message_bubble.dart';

/// Conversation screen — Flutter port of the prototype's `ChatScreen.tsx`
/// (conversation view), themed from the active light/dark theme instead of
/// the prototype's hard-coded white. Adds image/video attachments, which the
/// backend already supported.
class ChatScreen extends ConsumerStatefulWidget {
  final int conversationId;
  final UserModel otherUser;

  const ChatScreen({super.key, required this.conversationId, required this.otherUser});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const int _maxImageMb = 10;
  static const int _maxVideoMb = 200;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  late final ConversationsNotifier _conversations;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // Cached so dispose() doesn't need `ref`.
    _conversations = ref.read(conversationsProvider.notifier);
    _conversations.setActiveConversation(widget.conversationId);
    _textController.addListener(() {
      final has = _textController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _conversations.clearActiveConversation(widget.conversationId);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ChatNotifier get _chat => ref.read(chatProvider(widget.conversationId).notifier);

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _sendText(String text) {
    if (text.trim().isEmpty) return;
    _chat.sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _sendText(text);
    _textController.clear();
  }

  Future<void> _pickMedia({required bool video}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final XFile? file = video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1920,
            imageQuality: 85,
          );
    if (file == null || !mounted) return;

    final limitMb = video ? _maxVideoMb : _maxImageMb;
    final size = await file.length();
    if (size > limitMb * 1024 * 1024) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatMediaTooLarge(limitMb))));
      return;
    }
    if (!mounted) return;
    await _chat.sendMedia(file, isVideo: video);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final chatState = ref.watch(chatProvider(widget.conversationId));
    final myUserId = ref.watch(authProvider).user?.id;
    final isSocketUp = ref.watch(chatSocketProvider.select((s) => s.isConnected));
    final isOnline = ref.watch(conversationsProvider
        .select((s) => s.byId(widget.conversationId)?.otherUserOnline ?? false));

    ref.listen(chatProvider(widget.conversationId), (previous, next) {
      if ((previous?.messages.length ?? 0) != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    final rank = widget.otherUser.beltRank;
    final String subtitle;
    final Color subtitleColor;
    if (chatState.typingUsername != null) {
      subtitle = l10n.chatTyping;
      subtitleColor = scheme.primary;
    } else if (rank != null && rank.isNotEmpty) {
      subtitle = rank;
      subtitleColor = scheme.primary;
    } else {
      subtitle = isOnline ? l10n.chatOnline : l10n.chatOffline;
      subtitleColor = scheme.onSurface.withValues(alpha: 0.55);
    }

    final quickReplies = [
      l10n.chatQuickAvailableTonight,
      l10n.chatQuickThanksSession,
      l10n.chatQuickWhichClub,
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: Row(
          children: [
            ChatAvatar(url: widget.otherUser.avatarUrl, radius: 19, online: isOnline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUser.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: l10n.chatChallengeTooltip,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _sendText(l10n.chatChallengeMessage),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_mma, size: 15, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        l10n.chatChallengeButton,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isSocketUp)
            _Banner(text: l10n.chatReconnecting, color: scheme.onSurface.withValues(alpha: 0.7)),
          if (chatState.errorMessage != null)
            _Banner(text: chatState.errorMessage!, color: scheme.error),
          if (chatState.mediaUploadFailed)
            _Banner(text: l10n.chatUploadFailed, color: scheme.error),
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
                            ? () => _chat.deleteMessage(message.id)
                            : null,
                      );
                    },
                  ),
          ),
          if (chatState.isUploadingMedia)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.chatUploading,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ),
            ),
          // Quick suggestion pills (client-side canned messages).
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ActionChip(
                  label: Text(quickReplies[index], style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  shape: const StadiumBorder(),
                  backgroundColor: scheme.surface,
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  onPressed: () => _sendText(quickReplies[index]),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<bool>(
                    tooltip: l10n.chatAttachTooltip,
                    enabled: !chatState.isUploadingMedia,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                    onSelected: (isVideo) => _pickMedia(video: isVideo),
                    itemBuilder: (context) => [
                      PopupMenuItem<bool>(
                        value: false,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.image_outlined),
                          title: Text(l10n.chatAttachPhoto),
                        ),
                      ),
                      PopupMenuItem<bool>(
                        value: true,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(l10n.chatAttachVideo),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onChanged: (_) => _chat.notifyTyping(),
                      decoration: InputDecoration(
                        hintText: l10n.chatInputHint,
                        filled: true,
                        fillColor: scheme.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _hasText ? 1 : 0.4,
                    child: CircleAvatar(
                      backgroundColor: scheme.primary,
                      child: IconButton(
                        icon: Icon(Icons.send, color: scheme.onPrimary, size: 20),
                        onPressed: _hasText ? _send : null,
                      ),
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

class _Banner extends StatelessWidget {
  final String text;
  final Color color;

  const _Banner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}
