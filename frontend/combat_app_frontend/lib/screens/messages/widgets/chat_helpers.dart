import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/message_model.dart';

/// Online-dot green (the prototype's `emerald-500`).
const Color kOnlineColor = Color(0xFF10B981);

/// One-line text for a message in the conversation list: the deleted
/// placeholder, the text itself, or a localized "📷 Photo" / "🎥 Video".
String messagePreview(AppLocalizations l10n, MessageModel message) {
  if (message.isDeleted) return l10n.chatMessageDeleted;
  final text = message.content?.trim() ?? '';
  if (text.isNotEmpty) return text;
  if (message.mediaType == 'video') return l10n.chatMediaVideoPreview;
  if (message.mediaUrl != null) return l10n.chatMediaImagePreview;
  return '';
}

/// Poster frame (1s) of a Cloudinary video URL — mirrors
/// `cloudinary_service.video_poster_url` on the backend. Returns '' for URLs
/// that don't look like a Cloudinary video so callers can fall back.
String videoPosterUrl(String videoUrl) {
  const marker = '/video/upload/';
  if (!videoUrl.contains(marker)) return '';
  final slash = videoUrl.lastIndexOf('/');
  final head = videoUrl.substring(0, slash).replaceFirst(marker, '/video/upload/so_1/');
  final last = videoUrl.substring(slash + 1);
  final dot = last.lastIndexOf('.');
  final stem = dot == -1 ? last : last.substring(0, dot);
  return '$head/$stem.jpg';
}

/// Round avatar with the optional green "online" dot (prototype `ChatScreen`).
class ChatAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final bool online;

  const ChatAvatar({
    super.key,
    required this.url,
    required this.radius,
    this.online = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUrl = url != null && url!.isNotEmpty;
    final dot = radius * 0.5;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          backgroundImage: hasUrl ? CachedNetworkImageProvider(url!) : null,
          child: hasUrl ? null : Icon(Icons.person, size: radius, color: scheme.primary),
        ),
        if (online)
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: kOnlineColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
