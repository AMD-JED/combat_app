import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/sports_provider.dart';
import 'providers/theme_mode_provider.dart';
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
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Athletes Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(accent, brightness: Brightness.light),
      darkTheme: AppTheme.themeFor(accent, brightness: Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      // Language + theme are user preferences now (Settings screen), not
      // fixed decisions — see locale_provider.dart / theme_mode_provider.dart.
      // Flutter derives text direction from the active locale automatically
      // (Arabic -> RTL, French/English -> LTR), so no manual Directionality
      // wrapper is needed here anymore.
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
