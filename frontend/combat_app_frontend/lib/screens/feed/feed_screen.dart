import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/post_provider.dart';
import '../../providers/sports_provider.dart';
import 'widgets/post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(feedProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final sportIcon = ref.watch(currentSportAccentProvider).icon;

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
            icon: const Icon(Icons.refresh, color: AppTheme.textMuted),
            onPressed: () => ref.read(feedProvider.notifier).fetchFeed(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
        onPressed: () => context.push('/create-post'),
      ),
      body: feedState.isLoading && feedState.posts.isEmpty
          ? Center(child: CircularProgressIndicator(color: accent))
          : RefreshIndicator(
              color: accent,
              backgroundColor: AppTheme.surfaceLowest,
              onRefresh: () => ref.read(feedProvider.notifier).fetchFeed(),
              child: feedState.errorMessage != null && feedState.posts.isEmpty
                  ? _FeedMessage(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذّر تحميل التغذية',
                      subtitle: feedState.errorMessage!,
                      accent: accent,
                    )
                  : feedState.posts.isEmpty
                      ? _FeedMessage(
                          icon: Icons.dynamic_feed,
                          title: 'لا توجد منشورات في التغذية بعد',
                          subtitle: 'قم بإنشاء أول منشور لك أو متابعة أبطال آخرين!',
                          accent: accent,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80, top: 8),
                          itemCount: feedState.posts.length,
                          itemBuilder: (context, index) {
                            return PostCard(post: feedState.posts[index]);
                          },
                        ),
            ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
