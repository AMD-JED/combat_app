import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/conversations_provider.dart';
import '../providers/sports_provider.dart';
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
    // Load sport profiles so the app can tint itself with the user's
    // primary sport accent (see currentSportAccentProvider).
    Future.microtask(() => ref.read(sportProfilesProvider.notifier).fetchMyProfiles());
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = ref.watch(conversationsProvider).totalUnread;
    final accent = Theme.of(context).colorScheme.primary;

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
        backgroundColor: AppTheme.surfaceLowest,
        indicatorColor: accent.withValues(alpha: 0.15),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.dynamic_feed, color: accent),
            label: 'التغذية',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: accent,
              child: Icon(Icons.chat_bubble_outline, color: AppTheme.textMuted),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: accent,
              child: Icon(Icons.chat_bubble, color: accent),
            ),
            label: 'الرسائل',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.person, color: accent),
            label: 'الملف الشخصي',
          ),
        ],
      ),
    );
  }
}
