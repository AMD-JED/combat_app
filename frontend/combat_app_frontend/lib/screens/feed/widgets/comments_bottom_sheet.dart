import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../models/comment_model.dart';
import '../../../providers/post_provider.dart';

class CommentsBottomSheet extends ConsumerStatefulWidget {
  final int postId;

  const CommentsBottomSheet({super.key, required this.postId});

  @override
  ConsumerState<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends ConsumerState<CommentsBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<CommentModel> _comments = [];
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final comment = await ref.read(feedProvider.notifier).addComment(widget.postId, text);
    setState(() => _isSending = false);

    if (comment != null) {
      _controller.clear();
      setState(() {
        _comments.insert(0, comment);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'التعليقات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurface,
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.outlineVariant),

          // Comments List
          Expanded(
            child: _comments.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد تعليقات بعد. كن أول من يعلّق!',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final c = _comments[index];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: accent.withValues(alpha: 0.15),
                            backgroundImage: c.author.avatarUrl != null
                                ? NetworkImage(c.author.avatarUrl!)
                                : null,
                            child: c.author.avatarUrl == null
                                ? Icon(Icons.person, size: 20, color: accent)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${c.author.username}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.content,
                                    style: const TextStyle(color: AppTheme.onSurface, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceLowest,
              border: Border(top: BorderSide(color: AppTheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: AppTheme.onSurface),
                    decoration: const InputDecoration(
                      hintText: 'اكتب تعليقاً...',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendComment,
                  icon: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        )
                      : Icon(Icons.send_rounded, color: accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
