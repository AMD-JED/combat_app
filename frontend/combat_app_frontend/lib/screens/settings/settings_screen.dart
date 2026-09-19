import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_mode_provider.dart';

/// Lets the athlete pick their own theme (light/dark/system) and language
/// (ar/fr/en) instead of the app forcing one choice on everybody. Both
/// selections apply immediately and persist across restarts.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: l10n.appearanceSection),
          RadioListTile<ThemeMode>(
            title: Text(l10n.themeSystem),
            value: ThemeMode.system,
            groupValue: themeMode,
            onChanged: (mode) =>
                ref.read(themeModeProvider.notifier).setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            title: Text(l10n.themeLight),
            value: ThemeMode.light,
            groupValue: themeMode,
            onChanged: (mode) =>
                ref.read(themeModeProvider.notifier).setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            title: Text(l10n.themeDark),
            value: ThemeMode.dark,
            groupValue: themeMode,
            onChanged: (mode) =>
                ref.read(themeModeProvider.notifier).setThemeMode(mode!),
          ),
          const Divider(height: 32),
          _SectionHeader(title: l10n.languageSection),
          // Language names are shown in their own native script regardless
          // of the app's current language (same convention iOS/Android use
          // in their own language pickers), so these three are not run
          // through AppLocalizations.
          RadioListTile<Locale>(
            title: const Text('العربية'),
            value: const Locale('ar'),
            groupValue: locale,
            onChanged: (value) =>
                ref.read(localeProvider.notifier).setLocale(value!),
          ),
          RadioListTile<Locale>(
            title: const Text('Français'),
            value: const Locale('fr'),
            groupValue: locale,
            onChanged: (value) =>
                ref.read(localeProvider.notifier).setLocale(value!),
          ),
          RadioListTile<Locale>(
            title: const Text('English'),
            value: const Locale('en'),
            groupValue: locale,
            onChanged: (value) =>
                ref.read(localeProvider.notifier).setLocale(value!),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
