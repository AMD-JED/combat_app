import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'app_locale';

/// The three languages Athletes Hub ships with. UI text itself lives in
/// `lib/l10n/app_{ar,fr,en}.arb` — this list only tracks which ones exist.
const supportedLocales = [Locale('ar'), Locale('fr'), Locale('en')];

/// Persists the user's language preference across app restarts. Defaults
/// to Arabic (the project's primary language) rather than following the
/// device locale, since the current user base is Arabic-first and an
/// unrecognized device locale would otherwise silently fall back to
/// whichever language happens to be first in `supportedLocales`.
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('ar')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && supportedLocales.any((l) => l.languageCode == saved)) {
      state = Locale(saved);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);
