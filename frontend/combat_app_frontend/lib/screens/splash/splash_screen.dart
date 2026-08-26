import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Shown momentarily on app start while [AuthNotifier] checks for a stored
/// token and (if present) fetches the current user. The router's redirect
/// logic moves away from here automatically once auth status resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // No sport profile loaded yet at this point in the app lifecycle, so
    // this always renders with the default (combat) accent from main.dart.
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt_rounded, size: 44, color: accent),
            ),
            const SizedBox(height: 20),
            Text('Athletes Hub', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'شبكة الرياضيين الاجتماعية',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            CircularProgressIndicator(color: accent),
          ],
        ),
      ),
    );
  }
}
