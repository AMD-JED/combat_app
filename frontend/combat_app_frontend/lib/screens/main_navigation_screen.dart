import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/conversations_provider.dart';
import 'feed/feed_screen.dart';
import 'messages/conversations_screen.dart';
import 'profile/profile_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    FeedScreen(),
    ConversationsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Load the conversation list once at startup so the unread badge is
    // accurate even before the person opens the Messages tab.
    Future.microtask(() => ref.read(conversationsProvider.notifier).fetchConversations());
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = ref.watch(conversationsProvider).totalUnread;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primaryRed.withValues(alpha: 0.2),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.dynamic_feed, color: AppTheme.primaryRed),
            label: 'التغذية',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: AppTheme.primaryRed,
              child: const Icon(Icons.chat_bubble_outline, color: AppTheme.textMuted),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: AppTheme.primaryRed,
              child: const Icon(Icons.chat_bubble, color: AppTheme.primaryRed),
            ),
            label: 'الرسائل',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.person, color: AppTheme.primaryRed),
            label: 'الملف الشخصي',
          ),
        ],
      ),
    );
  }
}
