import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/comment_model.dart';
import '../../../models/post_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/post_provider.dart';
import '../../../providers/sports_provider.dart';
import 'feed_helpers.dart';
import 'reaction_button.dart';
import 'reaction_config.dart';

/// Feed post card — a Flutter port of the React prototype's `PostCard.tsx`:
/// author header, text, media, reactions summary row, action bar (reaction
/// button with the long-press picker + comment) and an inline comments
/// drawer.
///
/// Prototype elements that have no real data behind them yet (bookmark,
/// share counter, AI badge, "Chaud" quick button, sparring/workout pills
/// guessed from the text, "follow" menu item) are intentionally not rendered.
class PostCard extends ConsumerStatefulWidget {
  final PostModel post;

  const PostCard({super.key, required this.post});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _showComments = false;

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.postDeleteConfirmTitle),
        content: Text(l10n.postDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(feedProvider.notifier).deletePost(widget.post.id);
    }
  }

  void _openImage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final post = widget.post;
    final author = post.author;

    final currentUser = ref.watch(authProvider).user;
    final isMyPost = currentUser?.id == author.id;
    final sport = ref.watch(currentSportAccentProvider);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final divider = theme.dividerColor;

    final hasText = post.content != null && post.content!.isNotEmpty;
    final hasMedia = post.mediaUrl != null && post.mediaUrl!.isNotEmpty;
    final gym = author.gymAffiliation;
    final hasGym = gym != null && gym.isNotEmpty;

    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: muted);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          top: BorderSide(color: divider.withValues(alpha: 0.5)),
          bottom: BorderSide(color: divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------------------------- header
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.push('/u/${author.username}'),
                  child: RoundedAvatar(url: author.avatarUrl, accent: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/u/${author.username}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                author.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (author.isCoach) ...[
                              const SizedBox(width: 6),
                              _CoachBadge(label: l10n.coachBadge, color: accent),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (hasGym) ...[
                              Flexible(
                                child: Text(
                                  gym,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(' · ', style: subtitleStyle),
                            ],
                            Text(formatRelativeTime(l10n, post.createdAt), style: subtitleStyle),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMyPost)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: muted),
                    onSelected: (value) {
                      if (value == 'delete') _confirmDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(l10n.postDeleteAction),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ------------------------------------------------------ text
          if (hasText)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                post.content!,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.55),
              ),
            ),

          // ----------------------------------------------------- media
          if (hasMedia)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.symmetric(
                  horizontal: BorderSide(color: divider.withValues(alpha: 0.5)),
                ),
              ),
              child: post.postType == PostType.video
                  ? _VideoAttachment(url: post.mediaUrl!, accent: accent)
                  : GestureDetector(
                      onTap: () => _openImage(post.mediaUrl!),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: Image.network(
                          post.mediaUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 220,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => SizedBox(
                            height: 160,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined, color: muted, size: 40),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

          // ------------------------------------------- reactions summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divider.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                _ReactionSummary(post: post, sport: sport),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showComments = !_showComments),
                  child: Text(
                    l10n.commentsCount(post.commentsCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------------------------ action bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: ReactionButton(
                    current: post.userReaction,
                    sport: sport,
                    onReact: (reaction) =>
                        ref.read(feedProvider.notifier).react(post.id, reaction),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _CommentButton(
                    label: l10n.commentAction,
                    active: _showComments,
                    accent: accent,
                    onTap: () => setState(() => _showComments = !_showComments),
                  ),
                ),
              ],
            ),
          ),

          // -------------------------------------------- comments drawer
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _showComments
                ? _CommentsDrawer(key: ValueKey('comments-${post.id}'), postId: post.id)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces

class _CoachBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CoachBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Overlapping emoji bubbles of the most used reactions + the total count.
/// Renders nothing while the post has no reaction yet.
class _ReactionSummary extends StatelessWidget {
  final PostModel post;
  final SportAccent sport;

  const _ReactionSummary({required this.post, required this.sport});

  @override
  Widget build(BuildContext context) {
    final tops = post.topReactions.take(3).toList();
    if (post.likesCount <= 0 || tops.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const bubble = 20.0;
    const overlap = 14.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: bubble,
          width: bubble + (tops.length - 1) * overlap,
          child: Stack(
            children: [
              for (var i = 0; i < tops.length; i++)
                PositionedDirectional(
                  start: i * overlap,
                  child: Container(
                    width: bubble,
                    height: bubble,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reactionConfigFor(tops[i].key, l10n, sport).color,
                      border: Border.all(
                        color: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      reactionConfigFor(tops[i].key, l10n, sport).emoji,
                      style: const TextStyle(fontSize: 10, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${post.likesCount}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _CommentButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _CommentButton({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? accent : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.30) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable placeholder for a video post. There's no in-app player yet —
/// the `posts` table has nowhere to store the thumbnail Cloudinary already
/// generates, and a real inline player is a bigger lift (video_player +
/// buffering/controls) than this redesign covers — so this opens the raw
/// Cloudinary MP4 URL externally instead of showing a broken image.
class _VideoAttachment extends StatelessWidget {
  final String url;
  final Color accent;

  const _VideoAttachment({required this.url, required this.accent});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.2),
                border: Border.all(color: accent.withValues(alpha: 0.6)),
              ),
              child: Icon(Icons.play_arrow_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.videoTapToPlay,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;

  const _ImageViewer({required this.url});

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
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 56,
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- comments drawer

/// Inline comments panel under the card (the prototype's "expanded comments
/// drawer"). Loads the post's comments when it opens
/// (`GET /posts/{id}/comments`, newest first) and prepends new ones.
class _CommentsDrawer extends ConsumerStatefulWidget {
  final int postId;

  const _CommentsDrawer({super.key, required this.postId});

  @override
  ConsumerState<_CommentsDrawer> createState() => _CommentsDrawerState();
}

class _CommentsDrawerState extends ConsumerState<_CommentsDrawer> {
  final TextEditingController _controller = TextEditingController();
  List<CommentModel>? _comments;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(feedProvider.notifier).fetchComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final comment = await ref.read(feedProvider.notifier).addComment(widget.postId, text);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (comment != null) {
        _controller.clear();
        _comments = [comment, ...?_comments];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final myAvatar = ref.watch(authProvider).user?.avatarUrl;

    Widget list;
    if (_loading) {
      list = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              l10n.commentsLoadError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
            TextButton(onPressed: _retry, child: Text(l10n.retryButton)),
          ],
        ),
      );
    } else if (_comments == null || _comments!.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          l10n.commentsEmpty,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      final comments = _comments!;
      list = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: comments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _CommentTile(comment: comments[index]),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          list,
          const SizedBox(height: 10),
          Row(
            children: [
              RoundedAvatar(url: myAvatar, accent: accent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  inputFormatters: [LengthLimitingTextInputFormatter(500)],
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: l10n.commentHint,
                    hintStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: muted),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: accent),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final enabled = value.text.trim().isNotEmpty && !_sending;
                  return GestureDetector(
                    onTap: enabled ? _send : null,
                    child: Opacity(
                      opacity: enabled ? 1 : 0.35,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: accentGradient(accent),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.30),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Center(
                                child: DirectionalSendIcon(size: 15, color: Colors.white),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RoundedAvatar(url: comment.author.avatarUrl, accent: accent, size: 28),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.author.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTime(l10n, comment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
