import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/post_provider.dart';
import '../../providers/sports_provider.dart';
import 'widgets/composer_bar.dart';
import 'widgets/post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final feedState = ref.watch(feedProvider);
    final accent = theme.colorScheme.primary;
    final sportIcon = ref.watch(currentSportAccentProvider).icon;
    final posts = feedState.posts;

    Widget body;
    if (feedState.isLoading && posts.isEmpty) {
      body = Center(child: CircularProgressIndicator(color: accent));
    } else {
      final showError = feedState.errorMessage != null && posts.isEmpty;
      body = RefreshIndicator(
        color: accent,
        backgroundColor: theme.cardTheme.color,
        onRefresh: () => ref.read(feedProvider.notifier).fetchFeed(),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          // The composer bar is the first row; then either the posts or a
          // single empty/error message.
          itemCount: 1 + (posts.isEmpty ? 1 : posts.length),
          itemBuilder: (context, index) {
            if (index == 0) return const ComposerBar();
            if (posts.isEmpty) {
              return showError
                  ? _FeedMessage(
                      icon: Icons.wifi_off_rounded,
                      title: l10n.feedLoadError,
                      subtitle: feedState.errorMessage!,
                      accent: accent,
                      actionLabel: l10n.retryButton,
                      onAction: () => ref.read(feedProvider.notifier).fetchFeed(),
                    )
                  : _FeedMessage(
                      icon: Icons.dynamic_feed,
                      title: l10n.feedEmptyTitle,
                      subtitle: l10n.feedEmptySubtitle,
                      accent: accent,
                    );
            }
            final post = posts[index - 1];
            return PostCard(key: ValueKey('post-${post.id}'), post: post);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sportIcon, color: accent, size: 24),
            const SizedBox(width: 8),
            const Text('Athletes Hub', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => ref.read(feedProvider.notifier).fetchFeed(),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: accent),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
