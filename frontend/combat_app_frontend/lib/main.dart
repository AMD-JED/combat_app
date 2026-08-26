import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers/sports_provider.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: CombatSportsApp()));
}

class CombatSportsApp extends ConsumerWidget {
  const CombatSportsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final accent = ref.watch(currentSportAccentProvider);

    return MaterialApp.router(
      title: 'Athletes Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(accent),
      routerConfig: router,
      // The backend team is working in Arabic, and the UI copy above is
      // Arabic-first — set the locale/directionality accordingly.
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
