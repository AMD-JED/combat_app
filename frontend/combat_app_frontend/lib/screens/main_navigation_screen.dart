import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/conversations_provider.dart';
import '../providers/sports_provider.dart';
import 'feed/feed_screen.dart';
import 'messages/conversations_screen.dart';
import 'profile/profile_screen.dart';
import 'reels/reels_screen.dart';
import 'search/search_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _selectedIndex = 0;

  // Tab indexes — keep in sync with the NavigationDestinations below.
  static const int _reelsIndex = 1;

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
    final l10n = AppLocalizations.of(context)!;
    final totalUnread = ref.watch(conversationsProvider).totalUnread;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const FeedScreen(),
          // The IndexedStack keeps hidden tabs alive: tell Reels when it is
          // really on screen so it pauses the video otherwise.
          ReelsScreen(isActive: _selectedIndex == _reelsIndex),
          const SearchScreen(),
          const ConversationsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: theme.cardTheme.color,
        indicatorColor: accent.withValues(alpha: 0.15),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined, color: muted),
            selectedIcon: Icon(Icons.dynamic_feed, color: accent),
            label: l10n.feedTab,
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline, color: muted),
            selectedIcon: Icon(Icons.play_circle, color: accent),
            label: l10n.reelsTab,
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined, color: muted),
            selectedIcon: Icon(Icons.search, color: accent),
            label: l10n.searchTab,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: accent,
              child: Icon(Icons.chat_bubble_outline, color: muted),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text('$totalUnread'),
              backgroundColor: accent,
              child: Icon(Icons.chat_bubble, color: accent),
            ),
            label: l10n.messagesTab,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: muted),
            selectedIcon: Icon(Icons.person, color: accent),
            label: l10n.profileTab,
          ),
        ],
      ),
    );
  }
}
