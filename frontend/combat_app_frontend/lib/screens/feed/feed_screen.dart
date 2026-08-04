import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/post_provider.dart';
import 'widgets/post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(feedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_mma, color: AppTheme.gold, size: 24),
            SizedBox(width: 8),
            Text(
              'Combat Feed',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
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
        backgroundColor: AppTheme.primaryRed,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
        onPressed: () => context.push('/create-post'),
      ),
      body: feedState.isLoading && feedState.posts.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryRed),
            )
          : RefreshIndicator(
              color: AppTheme.primaryRed,
              backgroundColor: AppTheme.surface,
              onRefresh: () => ref.read(feedProvider.notifier).fetchFeed(),
              child: feedState.posts.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dynamic_feed, size: 64, color: AppTheme.textMuted),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد منشورات في التغذية بعد',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'قم بإنشاء أول منشور لك أو متابعة أبطال آخرين!',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: feedState.posts.length,
                      itemBuilder: (context, index) {
                        return PostCard(post: feedState.posts[index]);
                      },
                    ),
            ),
    );
  }
}
