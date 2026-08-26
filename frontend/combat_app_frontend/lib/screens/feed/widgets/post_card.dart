import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../models/post_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/post_provider.dart';
import 'comments_bottom_sheet.dart';

class PostCard extends ConsumerWidget {
  final PostModel post;

  const PostCard({super.key, required this.post});

  String _formatTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).user;
    final isMyPost = currentUser?.id == post.author.id;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Author Avatar & Name (tap → public profile) & Delete button if author
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.push('/u/${post.author.username}'),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: accent.withValues(alpha: 0.15),
                    backgroundImage: post.author.avatarUrl != null
                        ? NetworkImage(post.author.avatarUrl!)
                        : null,
                    child: post.author.avatarUrl == null
                        ? Icon(Icons.person, color: accent, size: 22)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/u/${post.author.username}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              post.author.fullName,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (post.author.sportType != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  post.author.sportType!.value,
                                  style: textTheme.labelSmall?.copyWith(color: accent, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '@${post.author.username} • ${_formatTime(post.createdAt)}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMyPost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                    color: AppTheme.surfaceLowest,
                    onSelected: (value) {
                      if (value == 'delete') {
                        ref.read(feedProvider.notifier).deletePost(post.id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                            const SizedBox(width: 8),
                            Text('حذف المنشور', style: textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Content text
            if (post.content != null && post.content!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(post.content!, style: textTheme.bodyMedium),
            ],

            // Media Preview
            if (post.mediaUrl != null && post.mediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  post.mediaUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 150,
                    color: AppTheme.surface,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: AppTheme.textMuted, size: 40),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            const SizedBox(height: 8),

            // Action Buttons: Like & Comment
            Row(
              children: [
                // Like Button
                InkWell(
                  onTap: () {
                    ref.read(feedProvider.notifier).toggleLike(post.id);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          post.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                          color: post.isLikedByMe ? AppTheme.error : AppTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.likesCount}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: post.isLikedByMe ? AppTheme.error : AppTheme.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Comment Button
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CommentsBottomSheet(postId: post.id),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.commentsCount}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
