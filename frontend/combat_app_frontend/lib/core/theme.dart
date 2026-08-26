import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One accent per sport, mirrors the `Sport` rows seeded on the backend
/// (`feature/multi-sport` — see `seed_sports.py`). `key` MUST match the
/// backend `Sport.name`/slug exactly, since it's what the API sends/expects.
///
/// NOTE: hardcoded here as a stopgap so the UI has something to render
/// immediately. Once `sports_service.dart` is wired to `GET /api/v1/sports/`,
/// this should become data-driven (color/icon can be added as columns, or
/// kept as a small local lookup keyed by the slug the backend returns).
enum SportAccent {
  combat(key: 'combat', color: Color(0xFF8B5CF6), icon: Icons.sports_mma, label: 'قتالية'),
  football(key: 'football', color: Color(0xFF10B981), icon: Icons.sports_soccer, label: 'كرة قدم'),
  running(key: 'running', color: Color(0xFF06B6D4), icon: Icons.directions_run, label: 'جري');

  final String key;
  final Color color;
  final IconData icon;
  final String label;

  const SportAccent({
    required this.key,
    required this.color,
    required this.icon,
    required this.label,
  });

  static SportAccent fromKey(String? key) {
    return SportAccent.values.firstWhere(
      (e) => e.key == key,
      orElse: () => SportAccent.combat,
    );
  }
}

/// Design tokens + ThemeData factory matching the Athletes Hub mockup
/// (light Material 3, Anybody/Hanken Grotesk/JetBrains Mono, per-sport
/// accent color). Replaces the old dark red/gold combat-only theme.
class AppTheme {
  // --- Base M3 tokens (from the mockup's tailwind config, sport-agnostic) ---
  static const Color background = Color(0xFFFDF7FF);
  static const Color surface = Color(0xFFF2ECF4);
  static const Color surfaceHigh = Color(0xFFECE6EE);
  static const Color surfaceLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1D1B20);
  static const Color onSurfaceVariant = Color(0xFF494551);
  static const Color outline = Color(0xFF7A7582);
  static const Color outlineVariant = Color(0xFFCBC4D2);
  static const Color error = Color(0xFFBA1A1A);

  // --- Legacy aliases -------------------------------------------------
  // Old screens (pre-redesign) reference these directly. Kept temporarily
  // so the app keeps compiling while auth/feed/profile are redesigned
  // screen-by-screen; remove once every screen uses Theme.of(context)
  // + the sport accent instead of static AppTheme colors.
  static const Color textMuted = onSurfaceVariant;
  static const Color primaryRed = error;
  static const Color gold = Color(0xFFD4AF37);

  static TextTheme _textTheme() {
    final headline = GoogleFonts.anybody();
    final body = GoogleFonts.hankenGrotesk();
    final labelCaps = GoogleFonts.jetBrainsMono();

    return TextTheme(
      displayLarge: headline.copyWith(
          fontSize: 48, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5, color: onSurface),
      headlineMedium: headline.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, height: 1.3, color: onSurface),
      titleMedium: headline.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, color: onSurface),
      bodyLarge: body.copyWith(fontSize: 18, height: 1.6, color: onSurface),
      bodyMedium: body.copyWith(fontSize: 16, height: 1.5, color: onSurface),
      bodySmall: body.copyWith(fontSize: 14, height: 1.4, color: onSurfaceVariant),
      labelSmall: labelCaps.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: onSurfaceVariant),
    );
  }

  /// Builds the full app [ThemeData] tinted with [accent]'s color. Call this
  /// with the athlete's chosen sport (default [SportAccent.combat] pre-login
  /// / during onboarding before a sport is picked).
  static ThemeData themeFor(SportAccent accent) {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final textTheme = _textTheme();

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent.color,
        brightness: Brightness.light,
      ).copyWith(
        primary: accent.color,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: onSurface,
        error: error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
          textStyle: textTheme.labelSmall?.copyWith(fontSize: 14, color: Colors.white),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent.color),
      ),
      cardTheme: CardThemeData(
        color: surfaceLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLowest,
        indicatorColor: accent.color.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall?.copyWith(letterSpacing: 0.2)),
      ),
    );
  }

  /// Bridge for call sites still doing `AppTheme.dark` from the v3 code.
  /// TODO: remove once `main.dart` reads the user's sport from
  /// `authProvider`/`sportProvider` and calls [themeFor] directly.
  static ThemeData get dark => themeFor(SportAccent.combat);
}
