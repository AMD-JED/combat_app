import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/message_model.dart';
import 'chat_helpers.dart';

/// Chat bubble — colors come from the active theme (accent for mine, surface
/// for theirs) so it follows light/dark mode and the sport accent. Supports
/// text, images (tap = full screen) and videos (tap = opens the MP4
/// externally, same as the feed: there is no in-app player yet).
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final VoidCallback? onLongPressDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPressDelete,
  });

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final bubbleColor = isMine ? scheme.primary : scheme.surface;
    final textColor = isMine ? scheme.onPrimary : scheme.onSurface;
    final metaColor = isMine
        ? scheme.onPrimary.withValues(alpha: 0.7)
        : scheme.onSurface.withValues(alpha: 0.5);

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.72;
    final text = message.displayContent;
    final isPending = message.id < 0;

    return Align(
      // Directional, so "mine" sits on the trailing side in LTR (fr/en) and
      // mirrors automatically in RTL (ar), like every other chat app.
      alignment: isMine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: isMine && !message.isDeleted && !isPending ? onLongPressDelete : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(isMine ? 18 : 4),
              bottomEnd: Radius.circular(isMine ? 4 : 18),
            ),
            border: isMine
                ? null
                : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.hasMedia)
                _MediaAttachment(message: message, width: maxBubbleWidth),
              Padding(
                padding: EdgeInsets.fromLTRB(14, message.hasMedia ? 8 : 10, 14, 8),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isStoryReply)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            decoration: BoxDecoration(
                              border: BorderDirectional(
                                start: BorderSide(color: metaColor, width: 2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.reply, size: 13, color: metaColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    isMine
                                        ? l10n.chatStoryReplyMine
                                        : l10n.chatStoryReplyTheirs,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: metaColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (message.isDeleted)
                        Text(
                          l10n.chatMessageDeleted,
                          style: TextStyle(
                            color: metaColor,
                            fontStyle: FontStyle.italic,
                            fontSize: 15,
                          ),
                        )
                      else if (text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.createdAt),
                              style: TextStyle(fontSize: 10, color: metaColor),
                            ),
                            if (isMine && !message.isDeleted) ...[
                              const SizedBox(width: 4),
                              Icon(
                                isPending
                                    ? Icons.schedule
                                    : (message.isRead ? Icons.done_all : Icons.done),
                                size: 14,
                                color: message.isRead
                                    ? scheme.onPrimary
                                    : scheme.onPrimary.withValues(alpha: 0.7),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaAttachment extends StatelessWidget {
  final MessageModel message;
  final double width;

  const _MediaAttachment({required this.message, required this.width});

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl!;
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(color: scheme.onSurface.withValues(alpha: 0.08));

    if (message.isVideo) {
      final poster = videoPosterUrl(url);
      return InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: SizedBox(
          width: width,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: poster,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => placeholder,
                  errorWidget: (_, __, ___) => Container(color: Colors.black87),
                )
              else
                Container(color: Colors.black87),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _FullScreenImage(url: url)),
      ),
      child: SizedBox(
        width: width,
        height: 220,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => Container(
            color: scheme.onSurface.withValues(alpha: 0.08),
            child: Icon(Icons.broken_image_outlined, color: scheme.onSurface.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  final String url;

  const _FullScreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}
