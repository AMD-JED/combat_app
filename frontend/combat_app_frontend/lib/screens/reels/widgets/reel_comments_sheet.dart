import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/comment_model.dart';
import '../../../providers/reels_provider.dart';
import '../../feed/widgets/feed_helpers.dart';

/// Bottom sheet with a reel's comments and the input to add one.
/// Comments are loaded once when the sheet opens; the reel's counter is kept
/// in sync by `ReelsNotifier.addComment`.
class ReelCommentsSheet extends ConsumerStatefulWidget {
  final int reelId;

  const ReelCommentsSheet({super.key, required this.reelId});

  @override
  ConsumerState<ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends ConsumerState<ReelCommentsSheet> {
  final _controller = TextEditingController();
  List<CommentModel> _comments = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final comments = await ref.read(reelsProvider.notifier).loadComments(widget.reelId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    final comment = await ref.read(reelsProvider.notifier).addComment(widget.reelId, text);
    if (!mounted) return;
    if (comment == null) {
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.reelsCommentFailed)));
      return;
    }
    _controller.clear();
    setState(() {
      _comments = [..._comments, comment];
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final height = MediaQuery.sizeOf(context).height;
    final count = ref.watch(
      reelsProvider.select((s) {
        for (final r in s.reels) {
          if (r.id == widget.reelId) return r.commentsCount;
        }
        return _comments.length;
      }),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.reelsCommentsTitle} · ${l10n.commentsCount(count)}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildList(l10n, theme, accent, muted)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.commentHint,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: _controller.text.trim().isEmpty ? null : _send,
                          icon: DirectionalSendIcon(size: 22, color: accent),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, ThemeData theme, Color accent, Color muted) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.commentsLoadError, style: TextStyle(color: muted)),
            TextButton(onPressed: _load, child: Text(l10n.retryButton)),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.commentsEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final c = _comments[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RoundedAvatar(url: c.author.avatarUrl, accent: accent, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.author.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(l10n, c.createdAt),
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(c.content, style: const TextStyle(fontSize: 13, height: 1.35)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
