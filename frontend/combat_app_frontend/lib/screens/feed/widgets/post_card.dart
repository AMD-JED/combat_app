import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Author Avatar & Name & Delete button if author
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryRed.withValues(alpha: 0.2),
                  backgroundImage: post.author.avatarUrl != null
                      ? NetworkImage(post.author.avatarUrl!)
                      : null,
                  child: post.author.avatarUrl == null
                      ? const Icon(Icons.person, color: Colors.white, size: 22)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post.author.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          if (post.author.sportType != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryRed.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                post.author.sportType!.value,
                                style: const TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${post.author.username} • ${_formatTime(post.createdAt)}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isMyPost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                    color: AppTheme.surface,
                    onSelected: (value) {
                      if (value == 'delete') {
                        ref.read(feedProvider.notifier).deletePost(post.id);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppTheme.primaryRed, size: 20),
                            SizedBox(width: 8),
                            Text('حذف المنشور', style: TextStyle(color: Colors.white)),
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
              Text(
                post.content!,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
              ),
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
                    color: AppTheme.background,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: AppTheme.textMuted, size: 40),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white10),
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
                          color: post.isLikedByMe ? AppTheme.primaryRed : AppTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.likesCount}',
                          style: TextStyle(
                            color: post.isLikedByMe ? AppTheme.primaryRed : AppTheme.textMuted,
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
                          style: const TextStyle(
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
