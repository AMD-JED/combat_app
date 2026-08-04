import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Shown momentarily on app start while [AuthNotifier] checks for a stored
/// token and (if present) fetches the current user. The router's redirect
/// logic moves away from here automatically once auth status resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_mma, size: 72, color: AppTheme.gold),
            const SizedBox(height: 16),
            Text(
              'Combat Sports Network',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppTheme.primaryRed),
          ],
        ),
      ),
    );
  }
}
