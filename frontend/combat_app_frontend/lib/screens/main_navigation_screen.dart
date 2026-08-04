import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'feed/feed_screen.dart';
import 'profile/profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    FeedScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.dynamic_feed, color: AppTheme.primaryRed),
            label: 'التغذية',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppTheme.textMuted),
            selectedIcon: Icon(Icons.person, color: AppTheme.primaryRed),
            label: 'الملف الشخصي',
          ),
        ],
      ),
    );
  }
}
